--[[ Text Editor ------------------------------------------------------------
     Code and plain text, with Lua highlighting, find and replace, undo, and
     "run this file" for Lua sources.
----------------------------------------------------------------------------]]

local args     = { ... }
local App      = arequire("ui.app")
local base     = arequire("ui.widget")
local W        = arequire("ui.widgets")
local TextView = arequire("ui.textview")
local theme    = arequire("gfx.theme")
local util     = arequire("lib.util")
local syntax   = arequire("lib.syntax")
local vfs      = arequire("kernel.vfs")
local appsSvc  = arequire("svc.apps")
local printer  = arequire("svc.printer")

local app = App({ title = "Text Editor" })

local state = { path = args[1], modified = false }

-------------------------------------------------------------------- chrome --

local nameLabel = W.Label({ text = "Untitled" })
nameLabel.hexpand = true

local saveButton = W.IconButton({ icon = "\4", width = 3 })
local findButton = W.IconButton({ icon = "\4", width = 3 })
local menuButton = W.IconButton({ icon = "\7", width = 3 })

local toolbar = W.Toolbar({ spacing = 0 })
toolbar:add(nameLabel)
toolbar:add(saveButton)
toolbar:add(findButton)
toolbar:add(menuButton)

local view = TextView({ showNumbers = true })
view.hexpand, view.vexpand = true, true

local statusLabel = W.Label({ text = "", dim = true })
statusLabel.hexpand = true

local status = base.Box({ orientation = "horizontal" })
status.hexpand = true
status.background = theme.c.window
status:add(statusLabel)

-- find / replace bar, hidden until asked for
local findEntry = W.Entry({ placeholder = "Find", icon = "\4" })
findEntry.hexpand = true
local replaceEntry = W.Entry({ placeholder = "Replace with" })
replaceEntry.hexpand = true
local nextButton = W.Button({ label = "Next", style = "flat" })
local replaceAllButton = W.Button({ label = "All", style = "flat" })
local closeFindButton = W.IconButton({ icon = "\215", width = 3 })

local findBar = base.Box({ orientation = "horizontal", spacing = 1 })
findBar.hexpand = true
findBar.background = theme.c.card
findBar:add(findEntry)
findBar:add(replaceEntry)
findBar:add(nextButton)
findBar:add(replaceAllButton)
findBar:add(closeFindButton)
findBar.visible = false

local root = base.Box({ orientation = "vertical", spacing = 0 })
root.hexpand, root.vexpand = true, true
root:add(toolbar)
root:add(findBar)
root:add(view)
root:add(status)
app:setRoot(root)

------------------------------------------------------------------ helpers --

local function updateStatus()
  local mark = view.modified and " \7" or ""
  nameLabel:setText(" " .. util.ellipsis(state.path and fs.getName(state.path) or "Untitled", 22) .. mark)
  aurora.setTitle((state.path and fs.getName(state.path) or "Untitled") .. (view.modified and " *" or ""))
  local language = state.language or "Plain text"
  statusLabel:setText((" Ln %d, Col %d  \183  %d lines  \183  %s")
    :format(view.line, view.col, #view.lines, language))
end

local function applySyntax()
  if not state.path then
    view.highlighter = nil
    state.language = "Plain text"
    return
  end
  view.highlighter = syntax.forPath(state.path)
  local ext = util.extension(state.path)
  state.language = ext == "lua" and "Lua"
    or ((ext == "md" or ext == "adoc") and "Markdown" or "Plain text")
end

local function loadFile(path)
  local data = util.readFile(path)
  if data == nil then
    app:notify("Could not read " .. fs.getName(path), "error")
    return false
  end
  state.path = path
  view:setText(data)
  applySyntax()
  vfs.touchRecent(path)
  updateStatus()
  app:queueDraw()
  return true
end

local function saveAs(path)
  if fs.isReadOnly(path) then
    app:notify("That location is read only", "error")
    return false
  end
  if not util.writeFile(path, view:getText()) then
    app:notify("Could not write " .. fs.getName(path), "error")
    return false
  end
  state.path = path
  view.modified = false
  applySyntax()
  vfs.touchRecent(path)
  updateStatus()
  app:notify("Saved " .. fs.getName(path), "success")
  app:queueDraw()
  return true
end

local function save()
  if state.path then return saveAs(state.path) end
  app:prompt({
    title = "Save as",
    text = fs.combine(vfs.HOME, "Untitled.txt"),
    acceptLabel = "Save",
    onAccept = function(path) if util.trim(path) ~= "" then saveAs(util.trim(path)) end end,
  })
end

------------------------------------------------------------- find/replace --

local function showFind(withReplace)
  findBar.visible = true
  replaceEntry.visible = withReplace and true or false
  replaceAllButton.visible = replaceEntry.visible
  app:queueLayout()
  app:setFocus(findEntry)
end

local function hideFind()
  findBar.visible = false
  app:queueLayout()
  app:setFocus(view)
end

local function findNext()
  local needle = findEntry.text
  if needle == "" then return end
  local line, col = view:find(needle, view.line, view.col + 1, false)
  if line then
    view:moveTo(line, col, false)
    view.sel = { line = line, col = col }
    view:moveTo(line, col + #needle, true)
    view:ensureVisible()
    app:queueDraw()
  else
    app:notify("No more matches")
  end
end

nextButton:connect("clicked", findNext)
findEntry:connect("activate", findNext)
closeFindButton:connect("clicked", hideFind)
replaceAllButton:connect("clicked", function()
  local n = view:replaceAll(findEntry.text, replaceEntry.text, false)
  app:notify(n .. " replacement(s)", n > 0 and "success" or "info")
  updateStatus()
end)

-------------------------------------------------------------------- menu ---

local function runFile()
  if not state.path then
    app:notify("Save the file first")
    return
  end
  if view.modified then saveAs(state.path) end
  appsSvc.launch("terminal", { state.path })
end

local function openMenu()
  app:menu(app.surface.w - 22, 2, {
    { label = "Open", icon = "\4", accel = "^O", action = function()
        app:prompt({
          title = "Open file",
          text = state.path or (vfs.HOME .. "/"),
          acceptLabel = "Open",
          onAccept = function(path) if fs.exists(path) then loadFile(path) end end,
        })
      end },
    { label = "Save as", icon = "\4", action = function()
        app:prompt({
          title = "Save as",
          text = state.path or (vfs.HOME .. "/Untitled.txt"),
          acceptLabel = "Save",
          onAccept = function(path) saveAs(path) end,
        })
      end },
    { separator = true },
    { label = "Find", icon = "\4", accel = "^F", action = function() showFind(false) end },
    { label = "Replace", icon = "\4", accel = "^R", action = function() showFind(true) end },
    { separator = true },
    { label = view.wrap and "No word wrap" or "Word wrap", icon = "\7",
      action = function()
        view.wrap = not view.wrap
        view.scrollX = 0
        app:queueDraw()
      end },
    { label = "Run in Terminal", icon = "\16", action = runFile,
      disabled = state.path == nil },
    { label = "Print", icon = "\22", action = function()
        local job = printer.submit({
          title = state.path and fs.getName(state.path) or "Untitled",
          content = view:getText(),
          source = state.path,
        })
        app:notify("Queued \"" .. job.title .. "\" for printing", "success")
      end },
  }, 22)
end

------------------------------------------------------------------ wiring ---

saveButton:connect("clicked", save)
findButton:connect("clicked", function() showFind(false) end)
menuButton:connect("clicked", openMenu)

view:connect("changed", updateStatus)
view:connect("moved", updateStatus)

app:accel("ctrl+s", save)
app:accel("ctrl+o", function()
  app:prompt({
    title = "Open file",
    text = state.path or (vfs.HOME .. "/"),
    acceptLabel = "Open",
    onAccept = function(path) if fs.exists(path) then loadFile(path) end end,
  })
end)
app:accel("ctrl+f", function() showFind(false) end)
app:accel("ctrl+r", function() showFind(true) end)
app:accel("ctrl+g", function()
  app:prompt({
    title = "Go to line",
    text = tostring(view.line),
    onAccept = function(text)
      local n = tonumber(text)
      if n then view:gotoLine(n) updateStatus() app:queueDraw() end
    end,
  })
end)
app:accel("ctrl+z", function() view:undo() updateStatus() app:queueDraw() end)
app:accel("ctrl+y", function() view:redo() updateStatus() app:queueDraw() end)
app:accel("ctrl+a", function() view:selectAll() app:queueDraw() end)
app:accel("ctrl+d", function() view:deleteLine() updateStatus() app:queueDraw() end)
app:accel("escape", function() if findBar.visible then hideFind() end end)
app:accel("f3", findNext)

app.onClose = function()
  if not view.modified then return true end
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
    if path and fs.exists(path) then loadFile(path) end
  end
end

if state.path and fs.exists(state.path) and not fs.isDir(state.path) then
  loadFile(state.path)
else
  state.path = nil
  applySyntax()
end

updateStatus()
app:setFocus(view)
app:run()
