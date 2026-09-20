--[[ Writer -- the Aurora word processor -------------------------------------
     Documents are paragraphs with a style (Title, Heading, Body, Bullet,
     Numbered, Quote).  They are stored as Markdown so anything else can read
     them, and they print with proper pagination and page numbers.
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
local printer  = arequire("svc.printer")
local devices  = arequire("kernel.devices")

local app = App({ title = "Writer" })

local state = { path = args[1] }

---------------------------------------------------------------- paragraph ---

-- Style detection and application work on the paragraph the caret is in.
local STYLES = {
  { id = "title",   label = "Title",    prefix = "# " },
  { id = "heading", label = "Heading",  prefix = "## " },
  { id = "sub",     label = "Subhead",  prefix = "### " },
  { id = "body",    label = "Body",     prefix = "" },
  { id = "bullet",  label = "Bullet",   prefix = "- " },
  { id = "number",  label = "Numbered", prefix = "1. " },
  { id = "quote",   label = "Quote",    prefix = "> " },
}

local function detectStyle(line)
  if line:match("^###%s") then return "sub" end
  if line:match("^##%s") then return "heading" end
  if line:match("^#%s") then return "title" end
  if line:match("^[%-%*]%s") then return "bullet" end
  if line:match("^%d+%.%s") then return "number" end
  if line:match("^>%s") then return "quote" end
  return "body"
end

local function stripPrefix(line)
  return (line:gsub("^###%s+", ""):gsub("^##%s+", ""):gsub("^#%s+", "")
              :gsub("^[%-%*]%s+", ""):gsub("^%d+%.%s+", ""):gsub("^>%s+", ""))
end

-------------------------------------------------------------------- chrome --

local nameLabel = W.Label({ text = "Untitled" })
nameLabel.hexpand = true

local styleTabs = W.Tabs({ tabs = {
  { label = "Title", id = "title" },
  { label = "H2", id = "heading" },
  { label = "Body", id = "body" },
  { label = "\7", id = "bullet" },
  { label = "\"", id = "quote" },
}, active = 3 })

local saveButton = W.IconButton({ icon = "\4", width = 3 })
local printButton = W.IconButton({ icon = "\22", width = 3 })
local menuButton = W.IconButton({ icon = "\7", width = 3 })

local toolbar = W.Toolbar({ spacing = 0 })
toolbar:add(styleTabs)
toolbar:add(nameLabel)
toolbar:add(saveButton)
toolbar:add(printButton)
toolbar:add(menuButton)

local view = TextView({ wrap = true, highlighter = syntax.markdown })
view.hexpand, view.vexpand = true, true

local statusLabel = W.Label({ text = "", dim = true })
statusLabel.hexpand = true
local status = base.Box({ orientation = "horizontal" })
status.hexpand = true
status.background = theme.c.window
status:add(statusLabel)

local root = base.Box({ orientation = "vertical", spacing = 0 })
root.hexpand, root.vexpand = true, true
root:add(toolbar)
root:add(view)
root:add(status)
app:setRoot(root)

------------------------------------------------------------------ helpers --

local function wordCount()
  local words, chars = 0, 0
  for _, line in ipairs(view.lines) do
    chars = chars + #line
    for _ in line:gmatch("%S+") do words = words + 1 end
  end
  return words, chars
end

local function updateStatus()
  local words, chars = wordCount()
  local styleId = detectStyle(view:currentLine())
  for i, tab in ipairs(styleTabs.tabs) do
    if tab.id == styleId then styleTabs.active = i end
  end
  statusLabel:setText((" %d words  \183  %d characters  \183  %s")
    :format(words, chars, styleId:sub(1, 1):upper() .. styleId:sub(2)))
  nameLabel:setText(" " .. util.ellipsis(
    state.path and fs.getName(state.path) or "Untitled", 18) .. (view.modified and " \7" or ""))
  aurora.setTitle((state.path and util.stripExtension(fs.getName(state.path)) or "Untitled")
    .. (view.modified and " *" or ""))
end

local function applyStyle(styleId)
  local def
  for _, s in ipairs(STYLES) do if s.id == styleId then def = s end end
  if not def then return end
  view:pushUndo()
  local text = stripPrefix(view:currentLine())
  view.lines[view.line] = def.prefix .. text
  view.col = math.min(#view.lines[view.line] + 1, view.col + #def.prefix)
  view:changed()
  updateStatus()
end

local function loadFile(path)
  local data = util.readFile(path)
  if data == nil then
    app:notify("Could not open " .. fs.getName(path), "error")
    return false
  end
  state.path = path
  view:setText(data)
  vfs.touchRecent(path)
  updateStatus()
  app:queueDraw()
  return true
end

local function saveAs(path)
  if not util.writeFile(path, view:getText()) then
    app:notify("Could not save", "error")
    return false
  end
  state.path = path
  view.modified = false
  vfs.touchRecent(path)
  updateStatus()
  app:notify("Saved " .. fs.getName(path), "success")
  app:queueDraw()
  return true
end

local function save()
  if state.path then return saveAs(state.path) end
  app:prompt({
    title = "Save document",
    text = vfs.HOME .. "/Documents/Untitled.md",
    acceptLabel = "Save",
    onAccept = function(path) if util.trim(path) ~= "" then saveAs(util.trim(path)) end end,
  })
end

------------------------------------------------------------------- print ---

--- Turn the Markdown source into printable lines: headings get underlined,
--- bullets get a real bullet, and quotes are indented.
local function renderForPrint(pageWidth)
  local out = {}
  for _, line in ipairs(view.lines) do
    local style = detectStyle(line)
    local text = stripPrefix(line)
    if style == "title" then
      out[#out + 1] = text:upper()
      out[#out + 1] = string.rep("=", math.min(#text, pageWidth))
      out[#out + 1] = ""
    elseif style == "heading" then
      out[#out + 1] = text
      out[#out + 1] = string.rep("-", math.min(#text, pageWidth))
    elseif style == "sub" then
      out[#out + 1] = text
    elseif style == "bullet" then
      out[#out + 1] = " * " .. text
    elseif style == "number" then
      out[#out + 1] = " " .. line
    elseif style == "quote" then
      out[#out + 1] = "   | " .. text
    else
      out[#out + 1] = text
    end
  end
  return out
end

local function printDocument()
  local target = printer.default()
  if not target then
    app:dialog({
      title = "No printer found",
      body = "Attach a printer to this computer, or place one next to it and try again.",
      actions = { { label = "OK", style = "suggested" } },
    })
    return
  end
  local ok, pageW = pcall(target.handle.getPageSize)
  local job = printer.submit({
    title = state.path and util.stripExtension(fs.getName(state.path)) or "Untitled",
    content = renderForPrint(ok and pageW or 25),
    target = target.name,
    source = state.path,
  })
  app:notify("Printing \"" .. job.title .. "\" on " .. target.name, "success")
end

-------------------------------------------------------------------- menu ---

local function openMenu()
  app:menu(app.surface.w - 26, 2, {
    { label = "New document", icon = "\254", action = function()
        view:setText("# Untitled\n\n")
        state.path = nil
        view:gotoLine(3)
        updateStatus()
      end },
    { label = "Open\133", icon = "\4", accel = "^O", action = function()
        app:prompt({
          title = "Open document",
          text = state.path or (vfs.HOME .. "/Documents/"),
          acceptLabel = "Open",
          onAccept = function(path) if fs.exists(path) then loadFile(path) end end,
        })
      end },
    { label = "Save", icon = "\4", accel = "^S", action = save },
    { label = "Save as\133", icon = "\4", action = function()
        app:prompt({
          title = "Save as",
          text = state.path or (vfs.HOME .. "/Documents/Untitled.md"),
          acceptLabel = "Save",
          onAccept = function(path) saveAs(path) end,
        })
      end },
    { separator = true },
    { label = "Paragraph style", icon = "\7", action = function()
        local items = {}
        for _, style in ipairs(STYLES) do
          items[#items + 1] = { label = style.label, icon = "\7",
                                action = function() applyStyle(style.id) end }
        end
        app:menu(4, 3, items, 18)
      end },
    { label = "Insert date", icon = "\4", action = function()
        view:insert(util.dateLine())
        updateStatus()
      end },
    { label = "Insert rule", icon = "\4", action = function()
        view:insert("\n---\n")
        updateStatus()
      end },
    { separator = true },
    { label = "Print\133", icon = "\22", accel = "^P", action = printDocument },
    { label = "Export as plain text", icon = "\171", action = function()
        local target = (state.path and util.stripExtension(state.path) or
                        (vfs.HOME .. "/Documents/Untitled")) .. ".txt"
        util.writeFile(target, table.concat(renderForPrint(60), "\n"))
        app:notify("Exported to " .. fs.getName(target), "success")
      end },
    { label = "Word count", icon = "\4", action = function()
        local words, chars = wordCount()
        app:dialog({
          title = "Word count",
          body = ("%d words\n%d characters\n%d paragraphs")
            :format(words, chars, #view.lines),
          actions = { { label = "Close", style = "suggested" } },
        })
      end },
  }, 26)
end

------------------------------------------------------------------ wiring ---

saveButton:connect("clicked", save)
printButton:connect("clicked", printDocument)
menuButton:connect("clicked", openMenu)
styleTabs:connect("changed", function(_, index, tab) applyStyle(tab.id) end)
view:connect("changed", updateStatus)
view:connect("moved", updateStatus)

app:accel("ctrl+s", save)
app:accel("ctrl+p", printDocument)
app:accel("ctrl+z", function() view:undo() updateStatus() app:queueDraw() end)
app:accel("ctrl+y", function() view:redo() updateStatus() app:queueDraw() end)
app:accel("ctrl+a", function() view:selectAll() app:queueDraw() end)
-- CC names its number keys "one", "two", ... so that is what comboFor sees.
app:accel("ctrl+one", function() applyStyle("title") end)
app:accel("ctrl+two", function() applyStyle("heading") end)
app:accel("ctrl+three", function() applyStyle("sub") end)
app:accel("ctrl+zero", function() applyStyle("body") end)
app:accel("ctrl+eight", function() applyStyle("bullet") end)

app.onClose = function()
  if not view.modified then return true end
  app:confirm({
    title = "Save before closing?",
    message = "This document has unsaved changes.",
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
  view:setText("# Untitled document\n\nStart writing here.\n")
  view:gotoLine(3)
end

updateStatus()
app:setFocus(view)
app:run()
