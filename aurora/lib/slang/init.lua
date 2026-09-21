--[[ aurora.lib.slang --------------------------------------------------------
     SimpleLang: the front door.

     File types:
        .sl    source you write
        .as    the assembly the compiler produced -- exactly what runs
        .ep    a built executable program, opened from Files to run it
        .cae   a library ("compressed anywhere ep") other programs can `use`

     Building a .sl writes both the .as and the .ep beside it.
----------------------------------------------------------------------------]]

local util     = arequire("lib.util")
local parser   = arequire("lib.slang.parser")
local compiler = arequire("lib.slang.compiler")
local vm       = arequire("lib.slang.vm")

local slang = {}

slang.VERSION = "1.0"
slang.parser = parser
slang.compiler = compiler
slang.vm = vm
slang.LIBRARY_PATHS = { "/home/lib", "/home/projects" }

---------------------------------------------------------------- packaging --

-- A .ep or .cae is a serialised table holding the assembly text, so a built
-- program can always show you the source of truth it was made from.
local MAGIC = "AURORA-EP"

function slang.pack(program, assembly, kind)
  return textutils.serialise({
    magic = MAGIC,
    kind = kind or "program",
    version = compiler.VERSION,
    name = program.name,
    built = os.epoch("utc"),
    assembly = assembly,
  })
end

--- Read a packed .ep / .cae.  Returns program, assembly, or nil + nil + error.
function slang.unpack(data)
  local value = textutils.unserialise(tostring(data or ""))
  if type(value) ~= "table" or value.magic ~= MAGIC then
    return nil, nil, { line = 0, message = "this is not an Aurora program" }
  end
  local program, err = compiler.fromAssembly(value.assembly)
  if not program then return nil, nil, err end
  program.name = value.name or program.name
  program.kind = value.kind
  return program, value.assembly
end

------------------------------------------------------------------ library --

function slang.findLibrary(name)
  for _, dir in ipairs(slang.LIBRARY_PATHS) do
    local direct = fs.combine(dir, name .. ".cae")
    if fs.exists(direct) then return direct end
    local nested = fs.combine(fs.combine(dir, name), name .. ".cae")
    if fs.exists(nested) then return nested end
  end
  return nil
end

--- Merge every `use`d library's actions into a program.
function slang.linkLibraries(program, seen)
  seen = seen or {}
  for _, name in ipairs(program.uses or {}) do
    if not seen[name] then
      seen[name] = true
      local path = slang.findLibrary(name)
      if not path then
        return false, { line = 0,
                        message = "cannot find the library " .. name
                                  .. " (looked for " .. name .. ".cae)" }
      end
      local library, _, err = slang.unpack(util.readFile(path))
      if not library then return false, err end
      local ok, nestedErr = slang.linkLibraries(library, seen)
      if not ok then return false, nestedErr end
      for functionName, fn in pairs(library.funcs) do
        -- the library's own main is just its top level, so skip it
        if functionName ~= "main" and not program.funcs[functionName] then
          program.funcs[functionName] = fn
          program.order[#program.order + 1] = functionName
        end
      end
    end
  end
  return true
end

------------------------------------------------------------------- build ---

--- Compile source text.  Returns { program, assembly } or nil + error.
function slang.build(source, name)
  local program, assembly, err = compiler.compile(source, name)
  if not program then return nil, err end
  return { program = program, assembly = assembly }
end

--- Build a .sl file, writing .as and .ep (or .cae) beside it.
function slang.buildFile(path, kind)
  local source = util.readFile(path)
  if not source then
    return nil, { line = 0, message = "cannot read " .. tostring(path) }
  end
  local built, err = slang.build(source, util.stripExtension(fs.getName(path)))
  if not built then return nil, err end

  local base = util.stripExtension(path)
  local assemblyPath = base .. ".as"
  local programPath = base .. ((kind == "library") and ".cae" or ".ep")

  util.writeFile(assemblyPath, built.assembly)
  util.writeFile(programPath, slang.pack(built.program, built.assembly,
                                         kind == "library" and "library" or "program"))
  return { assemblyPath = assemblyPath, programPath = programPath,
           assembly = built.assembly, program = built.program }
end

--------------------------------------------------------------------- run ---

--- Load anything runnable: .sl (compiled first), .as, .ep or .cae.
function slang.load(path)
  local extension = util.extension(path)
  local data = util.readFile(path)
  if data == nil then
    return nil, nil, { line = 0, message = "cannot read " .. tostring(path) }
  end

  if extension == "sl" then
    local program, assembly, err =
      compiler.compile(data, util.stripExtension(fs.getName(path)))
    if not program then return nil, nil, err end
    return program, assembly
  elseif extension == "as" then
    local program, err = compiler.fromAssembly(data)
    if not program then return nil, nil, err end
    return program, data
  elseif extension == "ep" or extension == "cae" then
    return slang.unpack(data)
  end
  return nil, nil, { line = 0, message = "not a SimpleLang file" }
end

--- Load, link libraries, resolve labels and run.
function slang.runFile(path, io)
  local program, _, err = slang.load(path)
  if not program then return false, err end
  local ok, linkErr = slang.linkLibraries(program)
  if not ok then return false, linkErr end
  local linked, linkError = vm.link(program)
  if not linked then return false, linkError end
  return vm.run(linked, { io = io })
end

--- Compile and run source text without touching the disk.
function slang.runSource(source, io, name)
  local built, err = slang.build(source, name)
  if not built then return false, err end
  local ok, linkErr = slang.linkLibraries(built.program)
  if not ok then return false, linkErr end
  local linked, linkError = vm.link(built.program)
  if not linked then return false, linkError end
  return vm.run(linked, { io = io })
end

--- Format an error for a human.
function slang.errorText(err)
  if type(err) ~= "table" then return tostring(err) end
  if (err.line or 0) > 0 then
    return "line " .. err.line .. ": " .. (err.message or "something went wrong")
  end
  return tostring(err.message or "something went wrong")
end

--- The standard io table for running a program inside a terminal window.
function slang.terminalIO()
  local theme = arequire("gfx.theme")
  return {
    write = function(text) print(text) end,
    ask = function(prompt)
      if prompt ~= "" then write(prompt .. " ") end
      return read()
    end,
    wait = function(seconds) os.sleep(seconds) end,
    clear = function() term.clear() term.setCursorPos(1, 1) end,
    size = function() return term.getSize() end,
    draw = function(x, y, text, fg, bg)
      if fg then term.setTextColour(fg) end
      if bg then term.setBackgroundColour(bg) end
      term.setCursorPos(math.floor(x), math.floor(y))
      term.write(text)
      term.setTextColour(theme.c.text)
      term.setBackgroundColour(theme.c.view)
    end,
    colour = function(fg, bg)
      if fg then term.setTextColour(fg) end
      if bg then term.setBackgroundColour(bg) end
    end,
    key = function()
      local _, code = os.pullEvent("key")
      return keys.getName(code) or ""
    end,
  }
end

return slang
