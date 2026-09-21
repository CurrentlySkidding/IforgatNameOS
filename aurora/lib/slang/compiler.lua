--[[ aurora.lib.slang.compiler ----------------------------------------------
     SimpleLang: AST -> assembly, and assembly <-> loadable program.

     The compiler always emits readable assembly text (a .as file), and the
     assembler reads that text straight back.  What you see in the .as file is
     exactly what runs -- it is the real intermediate form, not a listing.

        .func main
            PUSH     5
            STORE    score
            LOAD     score
            PUSH     3
            GT
            JMPF     L1
            PUSH     "nice"
            HOST     say 1
        L1:
            HALT
        .end
----------------------------------------------------------------------------]]

local util = arequire("lib.util")

local compiler = {}

compiler.VERSION = 1

--------------------------------------------------------------- code emitter --

local Emitter = util.class()

function Emitter:init(name, params)
  self.name = name
  self.params = params or {}
  self.code = {}
  self.labelCount = 0
end

function Emitter:emit(op, a, b, line)
  self.code[#self.code + 1] = { op = op, a = a, b = b, line = line }
end

function Emitter:label()
  self.labelCount = self.labelCount + 1
  return "L" .. self.labelCount
end

function Emitter:place(label)
  self.code[#self.code + 1] = { label = label }
end

------------------------------------------------------------------ codegen --

local Codegen = util.class()

function Codegen:init()
  self.functions = {}
  self.order = {}
  self.uses = {}
end

function Codegen:fail(line, message)
  error({ slang = true, line = line or 0, message = message }, 0)
end

function Codegen:expression(out, node)
  local kind = node.kind

  if kind == "number" or kind == "string" or kind == "boolean" then
    out:emit("PUSH", node.value, nil, node.line)

  elseif kind == "nothing" then
    out:emit("PUSHNIL", nil, nil, node.line)

  elseif kind == "name" then
    out:emit("LOAD", node.name, nil, node.line)

  elseif kind == "list" then
    out:emit("NEWLIST", nil, nil, node.line)
    for _, item in ipairs(node.items) do
      self:expression(out, item)
      out:emit("APPEND", nil, nil, node.line)
    end

  elseif kind == "index" then
    self:expression(out, node.target)
    self:expression(out, node.index)
    out:emit("INDEX", nil, nil, node.line)

  elseif kind == "binary" or kind == "compare" then
    self:expression(out, node.left)
    self:expression(out, node.right)
    out:emit(node.op:upper(), nil, nil, node.line)

  elseif kind == "unary" then
    self:expression(out, node.value)
    out:emit(node.op == "not" and "NOT" or "NEG", nil, nil, node.line)

  elseif kind == "logic" then
    -- short circuit, leaving the deciding value on the stack
    local done = out:label()
    self:expression(out, node.left)
    out:emit("DUP", nil, nil, node.line)
    out:emit(node.op == "and" and "JMPF" or "JMPT", done, nil, node.line)
    out:emit("POP", nil, nil, node.line)
    self:expression(out, node.right)
    out:place(done)

  elseif kind == "call" then
    for _, arg in ipairs(node.args) do self:expression(out, arg) end
    if self.functions[node.name] then
      out:emit("CALL", node.name, #node.args, node.line)
    else
      out:emit("HOST", node.name, #node.args, node.line)
    end

  else
    self:fail(node.line, "cannot compile a " .. tostring(kind))
  end
end

function Codegen:statement(out, node, loop)
  local kind = node.kind

  if kind == "assign" then
    self:expression(out, node.value)
    out:emit("STORE", node.name, nil, node.line)

  elseif kind == "setindex" then
    self:expression(out, node.target)
    self:expression(out, node.index)
    self:expression(out, node.value)
    out:emit("SETINDEX", nil, nil, node.line)

  elseif kind == "say" then
    for _, arg in ipairs(node.args) do self:expression(out, arg) end
    out:emit("HOST", "say", #node.args, node.line)
    out:emit("POP", nil, nil, node.line)

  elseif kind == "ask" then
    out:emit("PUSH", node.prompt or "", nil, node.line)
    out:emit("HOST", "ask", 1, node.line)
    out:emit("STORE", node.name, nil, node.line)

  elseif kind == "if" then
    local otherwise, done = out:label(), out:label()
    self:expression(out, node.condition)
    out:emit("JMPF", otherwise, nil, node.line)
    self:block(out, node.body, loop)
    out:emit("JMP", done, nil, node.line)
    out:place(otherwise)
    if node.otherwise then self:block(out, node.otherwise, loop) end
    out:place(done)

  elseif kind == "while" then
    local top, done = out:label(), out:label()
    out:place(top)
    self:expression(out, node.condition)
    out:emit("JMPF", done, nil, node.line)
    self:block(out, node.body, { breakLabel = done })
    out:emit("JMP", top, nil, node.line)
    out:place(done)

  elseif kind == "repeat" then
    -- a hidden counter keeps the loop variable out of the user's way
    local counter = "@n" .. (out.labelCount + 1)
    local top, done = out:label(), out:label()
    self:expression(out, node.count)
    out:emit("STORE", counter, nil, node.line)
    out:place(top)
    out:emit("LOAD", counter, nil, node.line)
    out:emit("PUSH", 0, nil, node.line)
    out:emit("GT", nil, nil, node.line)
    out:emit("JMPF", done, nil, node.line)
    self:block(out, node.body, { breakLabel = done })
    out:emit("LOAD", counter, nil, node.line)
    out:emit("PUSH", 1, nil, node.line)
    out:emit("SUB", nil, nil, node.line)
    out:emit("STORE", counter, nil, node.line)
    out:emit("JMP", top, nil, node.line)
    out:place(done)

  elseif kind == "for" then
    local limit = "@to" .. (out.labelCount + 1)
    local top, done = out:label(), out:label()
    self:expression(out, node.from)
    out:emit("STORE", node.name, nil, node.line)
    self:expression(out, node.to)
    out:emit("STORE", limit, nil, node.line)
    out:place(top)
    out:emit("LOAD", node.name, nil, node.line)
    out:emit("LOAD", limit, nil, node.line)
    out:emit("LE", nil, nil, node.line)
    out:emit("JMPF", done, nil, node.line)
    self:block(out, node.body, { breakLabel = done })
    out:emit("LOAD", node.name, nil, node.line)
    out:emit("PUSH", 1, nil, node.line)
    out:emit("ADD", nil, nil, node.line)
    out:emit("STORE", node.name, nil, node.line)
    out:emit("JMP", top, nil, node.line)
    out:place(done)

  elseif kind == "callstmt" then
    for _, arg in ipairs(node.args) do self:expression(out, arg) end
    if self.functions[node.name] then
      out:emit("CALL", node.name, #node.args, node.line)
    else
      out:emit("HOST", node.name, #node.args, node.line)
    end
    out:emit("POP", nil, nil, node.line)

  elseif kind == "give" then
    if node.value then
      self:expression(out, node.value)
    else
      out:emit("PUSHNIL", nil, nil, node.line)
    end
    out:emit("RET", nil, nil, node.line)

  elseif kind == "stop" then
    if not (loop and loop.breakLabel) then
      self:fail(node.line, "'stop' only works inside a loop")
    end
    out:emit("JMP", loop.breakLabel, nil, node.line)

  elseif kind == "expression" then
    self:expression(out, node.value)
    out:emit("POP", nil, nil, node.line)

  elseif kind == "function" or kind == "use" then
    -- handled before this pass
  else
    self:fail(node.line, "cannot compile a " .. tostring(kind))
  end
end

function Codegen:block(out, body, loop)
  for _, node in ipairs(body) do self:statement(out, node, loop) end
end

--- Hoist function definitions and `use` lines so calls resolve wherever they
--- appear in the file.
function Codegen:collect(body)
  for _, node in ipairs(body) do
    if node.kind == "function" then
      if self.functions[node.name] then
        self:fail(node.line, node.name .. " is defined twice")
      end
      self.functions[node.name] = node
      self.order[#self.order + 1] = node.name
    elseif node.kind == "use" then
      self.uses[#self.uses + 1] = node.name
    end
  end
end

function Codegen:run(body, name)
  self:collect(body)

  local program = { name = name or "program", version = compiler.VERSION,
                    funcs = {}, order = {}, uses = self.uses, main = "main" }

  for _, functionName in ipairs(self.order) do
    local node = self.functions[functionName]
    for _, inner in ipairs(node.body) do
      if inner.kind == "function" then
        self:fail(inner.line, "actions cannot be defined inside other actions")
      end
    end
    local out = Emitter(functionName, node.params)
    self:block(out, node.body, nil)
    out:emit("PUSHNIL", nil, nil, node.line)
    out:emit("RET", nil, nil, node.line)
    program.funcs[functionName] = { name = functionName, params = node.params,
                                    code = out.code }
    program.order[#program.order + 1] = functionName
  end

  local main = Emitter("main", {})
  self:block(main, body, nil)
  main:emit("HALT", nil, nil, 0)
  program.funcs.main = { name = "main", params = {}, code = main.code }
  table.insert(program.order, 1, "main")

  return program
end

------------------------------------------------------------ assembly text --

local function quote(value)
  local text = tostring(value)
  text = text:gsub("\\", "\\\\")
  text = text:gsub('"', '\\"')
  text = text:gsub("\n", "\\n")
  text = text:gsub("\t", "\\t")
  return '"' .. text .. '"'
end

local function literal(value)
  if type(value) == "string" then return quote(value) end
  if type(value) == "boolean" then return value and "true" or "false" end
  if value == nil then return "nil" end
  return tostring(value)
end

--- Render a program as assembly text.
function compiler.toAssembly(program)
  local lines = {
    "; SimpleLang assembly",
    "; program " .. tostring(program.name),
    "; version " .. tostring(program.version or compiler.VERSION),
    "",
  }
  for _, use in ipairs(program.uses or {}) do
    lines[#lines + 1] = ".use " .. use
  end
  if #(program.uses or {}) > 0 then lines[#lines + 1] = "" end

  for _, name in ipairs(program.order) do
    local fn = program.funcs[name]
    local header = ".func " .. name
    if #fn.params > 0 then header = header .. " " .. table.concat(fn.params, " ") end
    lines[#lines + 1] = header
    for _, instruction in ipairs(fn.code) do
      if instruction.label then
        lines[#lines + 1] = instruction.label .. ":"
      elseif instruction.a == nil and instruction.b == nil then
        lines[#lines + 1] = "    " .. instruction.op
      else
        local text = ("    %-8s %s"):format(instruction.op, literal(instruction.a))
        if instruction.b ~= nil then text = text .. " " .. literal(instruction.b) end
        lines[#lines + 1] = text
      end
    end
    lines[#lines + 1] = ".end"
    lines[#lines + 1] = ""
  end
  return table.concat(lines, "\n")
end

local function parseArgument(text)
  if text == nil or text == "" or text == "nil" then return nil end
  if text == "true" then return true end
  if text == "false" then return false end
  if text:sub(1, 1) == '"' then
    local body = text:sub(2, -2)
    body = body:gsub("\\n", "\n")
    body = body:gsub("\\t", "\t")
    body = body:gsub('\\"', '"')
    body = body:gsub("\\\\", "\\")
    return body
  end
  return tonumber(text) or text
end

--- Split an operand line, respecting quoted strings.
local function splitArguments(text)
  local out, i, length = {}, 1, #text
  while i <= length do
    local char = text:sub(i, i)
    if char == " " or char == "\t" then
      i = i + 1
    elseif char == '"' then
      local start = i
      i = i + 1
      while i <= length do
        local c = text:sub(i, i)
        if c == "\\" then i = i + 2
        elseif c == '"' then i = i + 1 break
        else i = i + 1 end
      end
      out[#out + 1] = text:sub(start, i - 1)
    else
      local start = i
      while i <= length and not text:sub(i, i):match("%s") do i = i + 1 end
      out[#out + 1] = text:sub(start, i - 1)
    end
  end
  return out
end

--- Read assembly text back into a program.  Returns program, or nil + error.
function compiler.fromAssembly(text)
  local program = { name = "program", version = compiler.VERSION,
                    funcs = {}, order = {}, uses = {}, main = "main" }
  local current, lineNumber = nil, 0

  for _, raw in ipairs(util.splitAll(tostring(text or ""):gsub("\r", ""), "\n")) do
    lineNumber = lineNumber + 1
    local line = util.trim(raw:gsub(";.*$", ""))
    if line ~= "" then
      if line:sub(1, 5) == ".func" then
        local parts = splitArguments(line:sub(6))
        if not parts[1] then
          return nil, { line = lineNumber, message = ".func needs a name" }
        end
        local params = {}
        for i = 2, #parts do params[#params + 1] = parts[i] end
        current = { name = parts[1], params = params, code = {} }
        program.funcs[parts[1]] = current
        program.order[#program.order + 1] = parts[1]
      elseif line == ".end" then
        current = nil
      elseif line:sub(1, 4) == ".use" then
        program.uses[#program.uses + 1] = util.trim(line:sub(5))
      elseif line:match("^[%w_@]+:$") then
        if not current then
          return nil, { line = lineNumber, message = "a label outside any .func" }
        end
        current.code[#current.code + 1] = { label = line:sub(1, -2) }
      else
        if not current then
          return nil, { line = lineNumber, message = "an instruction outside any .func" }
        end
        local parts = splitArguments(line)
        if not parts[1] then
          return nil, { line = lineNumber, message = "empty instruction" }
        end
        current.code[#current.code + 1] = {
          op = parts[1]:upper(),
          a = parseArgument(parts[2]),
          b = parseArgument(parts[3]),
        }
      end
    end
  end

  if not program.funcs.main then
    return nil, { line = 0, message = "this assembly has no main function" }
  end
  return program
end

------------------------------------------------------------------- public --

--- Compile SimpleLang source.  Returns program, assemblyText, or nil+nil+error.
function compiler.compile(source, name)
  local parserModule = arequire("lib.slang.parser")
  local ast, err = parserModule.parse(source)
  if not ast then return nil, nil, err end

  local ok, result = pcall(function() return Codegen():run(ast, name) end)
  if not ok then
    if type(result) == "table" and result.slang then return nil, nil, result end
    return nil, nil, { line = 0, message = tostring(result) }
  end
  return result, compiler.toAssembly(result)
end

return compiler
