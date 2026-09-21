--[[ Studio -----------------------------------------------------------------
     The SimpleLang workbench: projects, an editor, the compiler, and the
     assembly it produces.

     Build writes two files beside your source: the .as assembly, which is
     exactly what runs, and the .ep executable you can launch from Files.
----------------------------------------------------------------------------]]

local args     = { ... }
local App      = arequire("ui.app")
local base     = arequire("ui.widget")
local W        = arequire("ui.widgets")
local TextView = arequire("ui.textview")
local theme    = arequire("gfx.theme")
local util     = arequire("lib.util")
local syntax   = arequire("lib.syntax")
local slang    = arequire("lib.slang.init")
local sched    = arequire("kernel.sched")
local vfs      = arequire("kernel.vfs")

local app = App({ title = "Studio" })

local PROJECTS = "/home/projects"

local state = { project = nil, path = nil, assembly = "" }

------------------------------------------------------------------- chrome --

local tabs = W.Tabs({ tabs = {
  { label = "Code", id = "code" },
  { label = "Asm", id = "assembly" },
} })

local nameLabel = W.Label({ text = " Studio", dim = true })
nameLabel.hexpand = true
local runButton = W.Button({ label = "Run", style = "suggested" })
local menuButton = W.IconButton({ icon = "\7", width = 3 })

local toolbar = W.Toolbar({ spacing = 0 })
toolbar:add(tabs)
toolbar:add(nameLabel)
toolbar:add(runButton)
toolbar:add(menuButton)

local fileList = W.ListBox({ rows = {}, background = theme.c.window })
fileList.vexpand = true
local fileScroller = base.Scrolled({ background = theme.c.window })
fileScroller.widthRequest = 11
fileScroller.vexpand = true
fileScroller:setChild(fileList)
fileScroller.visible = false

local editor = TextView({ showNumbers = true, highlighter = syntax.simplelang })
editor.hexpand, editor.vexpand = true, true

local codePane = base.Box({ orientation = "horizontal", spacing = 0 })
codePane.hexpand, codePane.vexpand = true, true
codePane:add(fileScroller)
codePane:add(editor)

local assemblyView = TextView({ showNumbers = true, readOnly = true,
                                highlighter = syntax.assembly })
assemblyView.hexpand, assemblyView.vexpand = true, true

local pages = base.Stack()
pages.hexpand, pages.vexpand = true, true
pages:addPage("code", codePane)
pages:addPage("assembly", assemblyView)

local statusLabel = W.Label({ text = "", dim = true })
statusLabel.hexpand = true
local status = base.Box({ orientation = "horizontal" })
status.hexpand = true
status.background = theme.c.window
status:add(statusLabel)

local root = base.Box({ orientation = "vertical", spacing = 0 })
root.hexpand, root.vexpand = true, true
root:add(toolbar)
root:add(pages)
root:add(status)
app:setRoot(root)

------------------------------------------------------------------ helpers --

local function setStatus(text, kind)
  statusLabel:setText(" " .. text)
  statusLabel.fg = (kind == "error" and theme.c.destructive)
                   or (kind == "good" and theme.c.success or nil)
  app:queueDraw()
end

local function refreshFiles()
  local rows = {}
  if state.project and fs.isDir(state.project) then
    for _, name in ipairs(fs.list(state.project)) do
      local full = fs.combine(state.project, name)
      if not fs.isDir(full) then
        local extension = util.extension(name)
        local colour = theme.c.dim
        if extension == "sl" then colour = theme.c.accent
        elseif extension == "as" then colour = theme.c.warning
        elseif extension == "ep" or extension == "cae" then colour = theme.c.success end
        rows[#rows + 1] = { title = util.ellipsis(name, 9),
                            icon = { char = "\171", colour = colour }, path = full }
      end
    end
  end
  if #rows == 0 then rows[1] = { title = "empty" } end
  fileList:setRows(rows, true)
end

local function updateTitle()
  local name = state.path and fs.getName(state.path) or "Untitled"
  nameLabel:setText(" " .. util.ellipsis(name, 13) .. (editor.modified and " \7" or ""))
  aurora.setTitle(state.project and fs.getName(state.project) or "Studio")
end

local function openFile(path)
  local data = util.readFile(path)
  if data == nil then
    setStatus("cannot open " .. fs.getName(path), "error")
    return
  end
  state.path = path
  local extension = util.extension(path)
  editor.highlighter = (extension == "as") and syntax.assembly
                       or (extension == "lua" and syntax.lua or syntax.simplelang)
  editor.readOnly = (extension == "ep" or extension == "cae")
  editor:setText(data)
  vfs.touchRecent(path)
  updateTitle()
  setStatus(fs.getName(path) .. "  \183  " .. #editor.lines .. " lines")
  tabs:setActive(1)
  pages:setPage("code")
  app:queueLayout()
end

local function save()
  if not state.path then
    app:prompt({
      title = "Save as",
      text = fs.combine(state.project or PROJECTS, "main.sl"),
      acceptLabel = "Save",
      onAccept = function(path)
        if util.trim(path) == "" then return end
        util.writeFile(path, editor:getText())
        state.path = path
        if not state.project then state.project = fs.getDir(path) end
        editor.modified = false
        refreshFiles()
        updateTitle()
        setStatus("saved", "good")
      end,
    })
    return false
  end
  util.writeFile(state.path, editor:getText())
  editor.modified = false
  updateTitle()
  refreshFiles()
  return true
end

------------------------------------------------------------- build and run --

local function showError(err)
  setStatus(slang.errorText(err), "error")
  if err and (err.line or 0) > 0 then
    editor:gotoLine(err.line)
    tabs:setActive(1)
    pages:setPage("code")
  end
  app:queueLayout()
end

--- Compile whatever is in the editor.  Returns built, programPath, or nil.
local function build(kind)
  if not save() then return nil end
  local name = util.stripExtension(fs.getName(state.path or "program"))

  local built, err = slang.build(editor:getText(), name)
  if not built then
    showError(err)
    return nil
  end

  state.assembly = built.assembly
  assemblyView:setText(built.assembly)

  local stem = util.stripExtension(state.path)
  local programPath = stem .. ((kind == "library") and ".cae" or ".ep")
  util.writeFile(stem .. ".as", built.assembly)
  util.writeFile(programPath, slang.pack(built.program, built.assembly,
                                         kind == "library" and "library" or "program"))

  local instructions = 0
  for _, fn in pairs(built.program.funcs) do instructions = instructions + #fn.code end
  refreshFiles()
  setStatus("built " .. fs.getName(programPath) .. "  \183  "
            .. instructions .. " instructions", "good")
  return built, programPath
end

local function run()
  local built = build()
  if not built then return end

  local program = built.program
  local ok, err = slang.linkLibraries(program)
  if not ok then showError(err) return end
  local linked, linkErr = slang.vm.link(program)
  if not linked then showError(linkErr) return end

  local title = util.stripExtension(fs.getName(state.path))
  sched.spawn({
    name = "sl-" .. title,
    title = title,
    window = { w = 40, h = 14 },
    icon = { char = "\16", colour = theme.c.success },
    fn = function()
      term.setBackgroundColour(theme.c.view)
      term.setTextColour(theme.c.text)
      term.clear()
      term.setCursorPos(1, 1)
      local success, runtimeError = slang.vm.run(linked, { io = slang.terminalIO() })
      print("")
      if not success then
        term.setTextColour(theme.c.destructive)
        print(slang.errorText(runtimeError))
      else
        term.setTextColour(theme.c.dim)
        print("-- finished --")
      end
      term.setTextColour(theme.c.dim)
      print("Press any key to close.")
      os.pullEvent("key")
    end,
  })
  setStatus("running " .. title, "good")
end

------------------------------------------------------------------ projects --

local STARTER = [[
# %s

say "hello from %s"

set score to 0
for i from 1 to 5
  set score to score + i
end
say "score is " + score

to shout with word
  give upper(word) + "!"
end

say shout("it works")
]]

local function openProject(dir)
  state.project = dir
  refreshFiles()
  fileScroller.visible = true
  local main = fs.combine(dir, "main.sl")
  if fs.exists(main) then
    openFile(main)
  else
    for _, name in ipairs(fs.list(dir)) do
      if util.extension(name) == "sl" then
        openFile(fs.combine(dir, name))
        break
      end
    end
  end
  updateTitle()
  app:queueLayout()
end

local function newProject()
  app:prompt({
    title = "New project",
    message = "It goes in /home/projects",
    text = "my-program",
    acceptLabel = "Create",
    onAccept = function(name)
      name = util.trim(name):gsub("[^%w%-_]", "-")
      if name == "" then return end
      local dir = fs.combine(PROJECTS, name)
      if fs.exists(dir) then
        setStatus("a project called " .. name .. " already exists", "error")
        return
      end
      fs.makeDir(dir)
      util.writeFile(fs.combine(dir, "main.sl"), STARTER:format(name, name))
      openProject(dir)
      setStatus("created " .. name, "good")
    end,
  })
end

local function pickProject()
  if not fs.exists(PROJECTS) then fs.makeDir(PROJECTS) end
  local items = {}
  for _, name in ipairs(fs.list(PROJECTS)) do
    local dir = fs.combine(PROJECTS, name)
    if fs.isDir(dir) then
      items[#items + 1] = { label = util.ellipsis(name, 18), icon = "\254",
                            action = function() openProject(dir) end }
    end
  end
  if #items == 0 then items[1] = { label = "No projects yet", disabled = true } end
  items[#items + 1] = { separator = true }
  items[#items + 1] = { label = "New project", icon = "\4", action = newProject }
  app:menu(2, 2, items, 24)
end

local function newFile()
  if not state.project then
    setStatus("open a project first", "error")
    return
  end
  app:prompt({
    title = "New file",
    text = "helper.sl",
    onAccept = function(name)
      name = util.trim(name)
      if name == "" then return end
      if util.extension(name) == "" then name = name .. ".sl" end
      local path = fs.combine(state.project, name)
      if fs.exists(path) then
        setStatus("that file already exists", "error")
        return
      end
      util.writeFile(path, "# " .. name .. "\n\n")
      openFile(path)
      refreshFiles()
    end,
  })
end

-------------------------------------------------------------------- menu ---

local HELP = [[
set x to 5
say "hi " + x
ask name "who are you"
if x > 3 then ... else ... end
repeat 3 times ... end
for i from 1 to 10 ... end
while x > 0 do ... end
forever ... end   (stop to leave)
to greet with who ... end
call greet with "kai"
give value
use mylib]]

local function openMenu()
  app:menu(app.surface.w - 26, 2, {
    { label = "Open project", icon = "\254", accel = "^O", action = pickProject },
    { label = "New project", icon = "\4", action = newProject },
    { label = "New file", icon = "\171", accel = "^N", action = newFile,
      disabled = state.project == nil },
    { label = "Save", icon = "\4", accel = "^S", action = function()
        if save() then setStatus("saved", "good") end
      end },
    { separator = true },
    { label = "Build", icon = "\4", accel = "F9", action = function() build() end },
    { label = "Build as library", icon = "\4", action = function()
        local built, path = build("library")
        if built then setStatus("library built: " .. fs.getName(path), "good") end
      end },
    { label = "Run", icon = "\16", accel = "F5", action = run },
    { separator = true },
    { label = "Language help", icon = "\4", action = function()
        app:dialog({ title = "SimpleLang", body = HELP,
                     actions = { { label = "Close", style = "suggested" } } })
      end },
  }, 26)
end

------------------------------------------------------------------ wiring ---

tabs:connect("changed", function(_, index, tab)
  pages:setPage(tab.id)
  if tab.id == "assembly" and state.assembly == "" then
    setStatus("build first to see the assembly")
  end
  app:queueLayout()
end)

runButton:connect("clicked", run)
menuButton:connect("clicked", openMenu)
fileList:connect("activate", function(_, index, row)
  if row and row.path then openFile(row.path) end
end)
editor:connect("changed", updateTitle)

app:accel("ctrl+s", function() if save() then setStatus("saved", "good") end end)
app:accel("ctrl+o", pickProject)
app:accel("ctrl+n", newFile)
app:accel("f9", function() build() end)
app:accel("f5", run)
app:accel("ctrl+z", function() editor:undo() app:queueDraw() end)

app.onClose = function()
  if not editor.modified then return true end
  app:confirm({
    title = "Save before closing?",
    message = "This file has unsaved changes.",
    acceptLabel = "Save",
    cancelLabel = "Discard",
    onAccept = function() save() app:quit() end,
    onCancel = function() app:quit() end,
  })
  return false
end

app.onEvent = function(name, ...)
  if name == "aurora_open" then
    local path = select(1, ...)
    if path and fs.exists(path) then
      state.project = fs.getDir(path)
      fileScroller.visible = true
      refreshFiles()
      openFile(path)
    end
  end
end

if not fs.exists(PROJECTS) then fs.makeDir(PROJECTS) end

if args[1] and fs.exists(args[1]) then
  if fs.isDir(args[1]) then
    openProject(args[1])
  else
    state.project = fs.getDir(args[1])
    fileScroller.visible = true
    refreshFiles()
    openFile(args[1])
  end
else
  editor:setText(STARTER:format("Untitled", "SimpleLang"))
  setStatus("press Run to try this, or open a project")
end

updateTitle()
app:setFocus(editor)
app:run()
