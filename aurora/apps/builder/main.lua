--[[ App Builder ------------------------------------------------------------
     Lay out a real Aurora app, attach Lua to its events, run it in a window,
     then publish it into the app grid or export a one-file installer you can
     put on GitHub.

     Projects are saved as .aapp files (a serialised table).  Publishing
     generates the same main.lua that a hand-written app would have.
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
local sched    = arequire("kernel.sched")

local app = App({ title = "App Builder" })

---------------------------------------------------------------- the model --

local project = {
  id = "myapp",
  name = "My App",
  summary = "Built with Aurora App Builder",
  category = "Other",
  iconColour = colours.magenta,
  iconGlyph = "A",
  width = 40,
  height = 14,
  widgets = {},
  logic = "-- Your code runs after the window is built.\n"
       .. "-- Widgets you named are in `ui`, e.g. ui.title:setText(\"Hi\")\n\n",
}
local state = { path = args[1], selected = 1, modified = false, tab = 1 }

-- Every widget kind the designer can place, with its default props and the
-- code needed to build it.
local KINDS = {
  {
    id = "Label", label = "Label", w = 16, h = 1,
    props = { text = "Label", dim = false, align = "start" },
    build = function(p)
      return ("W.Label({ text = %q, dim = %s, align = %q })")
        :format(p.text or "", tostring(p.dim and true or false), p.align or "start")
    end,
  },
  {
    id = "Button", label = "Button", w = 12, h = 1,
    props = { text = "Click me", style = "suggested" },
    events = { "clicked" },
    build = function(p)
      return ("W.Button({ label = %q, style = %q })")
        :format(p.text or "Button", p.style or "normal")
    end,
  },
  {
    id = "Entry", label = "Text field", w = 18, h = 1,
    props = { text = "", placeholder = "Type here" },
    events = { "changed", "activate" },
    build = function(p)
      return ("W.Entry({ text = %q, placeholder = %q })")
        :format(p.text or "", p.placeholder or "")
    end,
  },
  {
    id = "Switch", label = "Switch", w = 4, h = 1,
    props = { active = false },
    events = { "changed" },
    build = function(p)
      return ("W.Switch({ active = %s })"):format(tostring(p.active and true or false))
    end,
  },
  {
    id = "CheckBox", label = "Checkbox", w = 16, h = 1,
    props = { text = "Enabled", active = false },
    events = { "changed" },
    build = function(p)
      return ("W.CheckBox({ label = %q, active = %s })")
        :format(p.text or "", tostring(p.active and true or false))
    end,
  },
  {
    id = "ProgressBar", label = "Progress", w = 18, h = 1,
    props = { value = 0.5 },
    build = function(p)
      return ("W.ProgressBar({ value = %s })"):format(tostring(tonumber(p.value) or 0))
    end,
  },
  {
    id = "Separator", label = "Separator", w = 20, h = 1,
    props = {},
    build = function() return "W.Separator({})" end,
  },
  {
    id = "ListBox", label = "List", w = 20, h = 6,
    props = { items = "One|Two|Three" },
    events = { "select", "activate" },
    build = function(p)
      local rows = {}
      for _, item in ipairs(util.splitAll(p.items or "", "|")) do
        item = util.trim(item)
        if item ~= "" then rows[#rows + 1] = ("{ title = %q }"):format(item) end
      end
      return ("W.ListBox({ rows = { %s } })"):format(table.concat(rows, ", "))
    end,
  },
  {
    id = "TextView", label = "Text area", w = 24, h = 6,
    props = { text = "" },
    events = { "changed" },
    build = function(p)
      return ("TextView({ text = %q })"):format(p.text or "")
    end,
  },
  {
    id = "Chart", label = "Chart", w = 20, h = 6,
    props = { series = "3,7,2,9,5", kind = "bar" },
    build = function(p)
      local values = {}
      for _, piece in ipairs(util.splitAll(p.series or "", ",")) do
        local n = tonumber(util.trim(piece))
        if n then values[#values + 1] = tostring(n) end
      end
      return ("W.Chart({ series = { %s }, kind = %q })")
        :format(table.concat(values, ", "), p.kind or "bar")
    end,
  },
}

local function kindOf(id)
  for _, kind in ipairs(KINDS) do
    if kind.id == id then return kind end
  end
  return KINDS[1]
end

------------------------------------------------------------------ preview --

local Canvas = util.class(base.Widget)

function Canvas:init()
  base.Widget.init(self, {})
  self.hexpand, self.vexpand = true, true
  self.focusable = true
end

function Canvas:measure() return 24, 8 end

function Canvas:draw(s)
  local c = theme.c
  s:fill(self.x, self.y, self.w, self.h, " ", c.text, c.desktop)

  -- the app window being designed, drawn to scale where it fits
  local vw = math.min(self.w - 2, project.width)
  local vh = math.min(self.h - 2, project.height)
  local ox = self.x + math.floor((self.w - vw) / 2)
  local oy = self.y + math.floor((self.h - vh) / 2)

  s:fill(ox, oy, vw, vh, " ", c.text, c.window)
  s:roundRect(ox, oy, vw, vh, c.window, c.desktop)
  s:pushClip(ox, oy, vw, vh)

  for i, widget in ipairs(project.widgets) do
    local kind = kindOf(widget.kind)
    local wx, wy = ox + widget.x - 1, oy + widget.y - 1
    local selected = (i == state.selected)
    local bg = selected and c.hover or c.card
    local fg = selected and c.text or c.dim

    if widget.kind == "Button" then
      s:pill(wx, wy, widget.w, selected and c.accent or c.card)
      local label = util.ellipsis(widget.props.text or "", widget.w - 2)
      s:write(wx + 1 + math.floor((widget.w - 2 - #label) / 2), wy, label,
              selected and c.onAccent or c.text, selected and c.accent or c.card)
    elseif widget.kind == "Separator" then
      s:fill(wx, wy, widget.w, 1, "\131", selected and c.accent or c.separator, c.window)
    else
      s:fill(wx, wy, widget.w, widget.h, " ", fg, bg)
      local label = util.ellipsis(widget.props.text or widget.props.placeholder
                                  or kind.label, widget.w)
      s:write(wx, wy, label, fg, bg)
      if widget.h > 1 then
        s:write(wx, wy + widget.h - 1, util.ellipsis(kind.label, widget.w), c.dim, bg)
      end
    end

    if selected then
      s:write(math.max(ox, wx - 1), wy, "\16", c.accent, c.window)
    end
  end

  s:popClip()
  s:write(self.x, self.y + self.h - 1,
          (" %d\215%d window  \183  %d widgets"):format(project.width, project.height,
                                                        #project.widgets),
          c.dim, c.desktop)
end

function Canvas:onKey(key)
  local widget = project.widgets[state.selected]
  if not widget then return false end
  local step = 1
  if key == keys.up then widget.y = math.max(1, widget.y - step)
  elseif key == keys.down then widget.y = math.min(project.height - 1, widget.y + step)
  elseif key == keys.left then widget.x = math.max(1, widget.x - step)
  elseif key == keys.right then widget.x = math.min(project.width, widget.x + step)
  else return false end
  state.modified = true
  self:invalidate()
  self:emit("changed")
  return true
end

------------------------------------------------------------------- chrome --

local outline = W.ListBox({ rows = {}, showSubtitles = true })
outline.vexpand = true
local outlineScroller = base.Scrolled({ background = theme.c.window })
outlineScroller.widthRequest = 14
outlineScroller.vexpand = true
outlineScroller:setChild(outline)

local canvas = Canvas()

local designPane = base.Box({ orientation = "horizontal", spacing = 0 })
designPane.hexpand, designPane.vexpand = true, true
designPane:add(outlineScroller)
designPane:add(W.Separator({ orientation = "vertical" }))
designPane:add(canvas)

local codeView = TextView({ showNumbers = true, highlighter = syntax.lua })
codeView.hexpand, codeView.vexpand = true, true

local generatedView = TextView({ showNumbers = true, highlighter = syntax.lua, readOnly = true })
generatedView.hexpand, generatedView.vexpand = true, true

local pages = base.Stack()
pages.hexpand, pages.vexpand = true, true
pages:addPage("design", designPane)
pages:addPage("logic", codeView)
pages:addPage("source", generatedView)

local tabs = W.Tabs({ tabs = {
  { label = "Design", id = "design" },
  { label = "Logic", id = "logic" },
  { label = "Source", id = "source" },
} })

local runButton = W.Button({ label = "Run", style = "suggested" })
local menuButton = W.IconButton({ icon = "\7", width = 3 })
local addButton = W.IconButton({ icon = "\4", width = 3 })

local toolbar = W.Toolbar({ spacing = 0 })
toolbar:add(tabs)
local spacer = W.Label({ text = "" })
spacer.hexpand = true
toolbar:add(spacer)
toolbar:add(addButton)
toolbar:add(runButton)
toolbar:add(menuButton)

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

------------------------------------------------------- code generation -----

local function varName(widget, index)
  local name = widget.name
  if name and name:match("^[%a_][%w_]*$") then return name end
  return ("widget%d"):format(index)
end

local function generate()
  local out = {}
  local function emit(line) out[#out + 1] = line end

  emit("--[[ " .. project.name .. " -- built with Aurora App Builder ]]--")
  emit("")
  emit("local args     = { ... }")
  emit("local App      = arequire(\"ui.app\")")
  emit("local base     = arequire(\"ui.widget\")")
  emit("local W        = arequire(\"ui.widgets\")")
  emit("local TextView = arequire(\"ui.textview\")")
  emit("local theme    = arequire(\"gfx.theme\")")
  emit("local util     = arequire(\"lib.util\")")
  emit("")
  emit(("local app = App({ title = %q })"):format(project.name))
  emit("")
  emit("local root = base.Fixed({ background = theme.c.window })")
  emit("root.hexpand, root.vexpand = true, true")
  emit("")
  emit("-- Named widgets, so your logic can reach them.")
  emit("local ui = {}")
  emit("")

  for index, widget in ipairs(project.widgets) do
    local kind = kindOf(widget.kind)
    local name = varName(widget, index)
    emit(("local %s = %s"):format(name, kind.build(widget.props)))
    emit(("root:put(%s, %d, %d, %d, %d)")
      :format(name, widget.x - 1, widget.y - 1, widget.w, widget.h))
    emit(("ui[%q] = %s"):format(name, name))
    for signal, source in pairs(widget.handlers or {}) do
      if util.trim(source) ~= "" then
        emit(("%s:connect(%q, function(self, ...)"):format(name, signal))
        for _, line in ipairs(util.splitAll(source, "\n")) do
          emit("  " .. line)
        end
        emit("end)")
      end
    end
    emit("")
  end

  emit("app:setRoot(root)")
  emit("")
  emit("---------------------------------------------------------------- logic --")
  emit("")
  for _, line in ipairs(util.splitAll(project.logic or "", "\n")) do
    emit(line)
  end
  emit("")
  emit("app:run()")

  return table.concat(out, "\n")
end

local function manifest()
  return {
    id = project.id,
    name = project.name,
    summary = project.summary,
    category = project.category,
    main = "main.lua",
    char = "\254",
    window = { w = project.width, h = project.height },
    icon = { colour = project.iconColour, glyph = project.iconGlyph },
  }
end

------------------------------------------------------------------ refresh --

local function refresh()
  local rows = {}
  for index, widget in ipairs(project.widgets) do
    local kind = kindOf(widget.kind)
    rows[#rows + 1] = {
      title = varName(widget, index),
      subtitle = ("%s %d,%d"):format(kind.label, widget.x, widget.y),
      icon = { char = "\254", colour = theme.c.accent },
    }
  end
  outline:setRows(rows, true)
  outline.selected = util.clamp(state.selected, 1, math.max(1, #rows))
  statusLabel:setText((" %s  \183  id %s  \183  %d widgets%s")
    :format(project.name, project.id, #project.widgets, state.modified and "  \7" or ""))
  aurora.setTitle(project.name .. (state.modified and " *" or ""))
  if pages.currentName == "source" then
    generatedView:setText(generate())
  end
  app:queueDraw()
end

---------------------------------------------------------------- properties --

local function editProperties()
  local widget = project.widgets[state.selected]
  if not widget then
    app:notify("Add a widget first")
    return
  end
  local kind = kindOf(widget.kind)

  local nameEntry = W.Entry({ text = widget.name or "", placeholder = "Name (for your code)" })
  nameEntry.hexpand = true
  local textEntry = W.Entry({ text = tostring(widget.props.text or widget.props.items
                              or widget.props.series or widget.props.placeholder or ""),
                              placeholder = "Text" })
  textEntry.hexpand = true
  local geometryEntry = W.Entry({
    text = ("%d,%d,%d,%d"):format(widget.x, widget.y, widget.w, widget.h),
    placeholder = "x,y,width,height" })
  geometryEntry.hexpand = true

  local form = base.Box({ orientation = "vertical", spacing = 0 })
  form.hexpand = true
  form:add(W.Label({ text = kind.label .. " properties", dim = true }))
  form:add(nameEntry)
  form:add(textEntry)
  form:add(geometryEntry)

  app:dialog({
    title = "Properties",
    body = form,
    actions = {
      { label = "Cancel" },
      { label = "Apply", style = "suggested", onClick = function()
          if util.trim(nameEntry.text) ~= "" then widget.name = util.trim(nameEntry.text) end
          local value = textEntry.text
          if widget.props.items ~= nil then widget.props.items = value
          elseif widget.props.series ~= nil then widget.props.series = value
          else widget.props.text = value end
          local parts = util.splitAll(geometryEntry.text, ",")
          widget.x = math.max(1, tonumber(parts[1]) or widget.x)
          widget.y = math.max(1, tonumber(parts[2]) or widget.y)
          widget.w = math.max(1, tonumber(parts[3]) or widget.w)
          widget.h = math.max(1, tonumber(parts[4]) or widget.h)
          state.modified = true
          refresh()
        end },
    },
  })
  app:setFocus(nameEntry)
end

local function editHandler()
  local widget = project.widgets[state.selected]
  if not widget then return end
  local kind = kindOf(widget.kind)
  if not kind.events or #kind.events == 0 then
    app:notify(kind.label .. " has no events")
    return
  end
  local signal = kind.events[1]
  widget.handlers = widget.handlers or {}

  local entry = W.Entry({ text = widget.handlers[signal] or "",
                          placeholder = "Lua, e.g. ui.output:setText(\"hi\")" })
  entry.hexpand = true
  local form = base.Box({ orientation = "vertical", spacing = 0 })
  form.hexpand = true
  form:add(W.Label({ text = "on " .. signal, dim = true }))
  form:add(entry)

  app:dialog({
    title = "Event handler",
    body = form,
    actions = {
      { label = "Cancel" },
      { label = "Save", style = "suggested", onClick = function()
          widget.handlers[signal] = entry.text
          state.modified = true
          refresh()
        end },
    },
  })
  app:setFocus(entry)
end

--------------------------------------------------------------- add widget --

local function addWidget()
  local items = {}
  for _, kind in ipairs(KINDS) do
    items[#items + 1] = {
      label = kind.label,
      icon = "\254",
      action = function()
        local widget = {
          kind = kind.id,
          x = 2, y = math.min(project.height - 1, #project.widgets * 2 + 2),
          w = kind.w, h = kind.h,
          props = util.deepCopy(kind.props),
          handlers = {},
        }
        widget.name = kind.id:lower() .. (#project.widgets + 1)
        project.widgets[#project.widgets + 1] = widget
        state.selected = #project.widgets
        state.modified = true
        refresh()
      end,
    }
  end
  app:menu(4, 2, items, 18)
end

------------------------------------------------------------ run / publish --

local function currentSource()
  return generate()
end

local function runProject()
  local dir = "/aurora/var/builder-preview"
  if not fs.exists(dir) then fs.makeDir(dir) end
  local path = fs.combine(dir, "main.lua")
  if not util.writeFile(path, currentSource()) then
    app:notify("Could not write the preview", "error")
    return
  end
  local proc, err = sched.spawn({
    name = project.id .. "-preview",
    title = project.name .. " (preview)",
    path = path,
    window = { w = project.width, h = project.height },
    icon = { char = "\254", colour = project.iconColour },
    meta = { manifest = manifest() },
  })
  if not proc then
    app:notify("Could not start: " .. tostring(err), "error")
  else
    app:notify("Running " .. project.name, "success")
  end
end

local function publish()
  local id = project.id
  if not id:match("^[%a][%w_%-]*$") then
    app:notify("The app id must start with a letter", "error")
    return
  end
  local dir = fs.combine(appsSvc.USER_DIR, id)
  local function write()
    if not fs.exists(dir) then fs.makeDir(dir) end
    util.writeFile(fs.combine(dir, "manifest.lua"),
                   "return " .. textutils.serialise(manifest()) .. "\n")
    util.writeFile(fs.combine(dir, "main.lua"), currentSource())
    appsSvc.scan()
    app:notify(project.name .. " is now in your apps", "success")
  end
  if fs.exists(dir) then
    app:confirm({
      title = "Replace the installed app?",
      message = project.name .. " is already installed. Overwrite it?",
      acceptLabel = "Replace",
      onAccept = write,
    })
  else
    write()
  end
end

--- A single file that recreates the app on any Aurora computer.
local function exportInstaller()
  local source = currentSource()
  local target = fs.combine(vfs.HOME, project.id .. "-install.lua")
  local lines = {
    "--[[ Installer for " .. project.name .. " (Aurora app) ]]--",
    "local id = " .. ("%q"):format(project.id),
    "local dir = \"/home/apps/\" .. id",
    "if not fs.exists(dir) then fs.makeDir(dir) end",
    "local manifest = " .. textutils.serialise(manifest()),
    "local h = fs.open(fs.combine(dir, \"manifest.lua\"), \"w\")",
    "h.write(\"return \" .. textutils.serialise(manifest))",
    "h.close()",
    "local source = " .. ("%q"):format(source),
    "h = fs.open(fs.combine(dir, \"main.lua\"), \"w\")",
    "h.write(source)",
    "h.close()",
    "print(\"Installed \" .. manifest.name .. \" to \" .. dir)",
    "print(\"Open the Activities overview to launch it.\")",
  }
  if not util.writeFile(target, table.concat(lines, "\n")) then
    app:notify("Could not write the installer", "error")
    return
  end
  app:dialog({
    title = "Installer exported",
    body = "Saved to " .. target .. "\n\nPut this file in a GitHub repo, then on any "
        .. "computer run:  wget run <raw url>",
    actions = { { label = "Nice", style = "suggested" } },
  })
end

--------------------------------------------------------------- load / save --

local function loadProject(path)
  local saved = util.readTable(path, nil)
  if not saved or not saved.widgets then
    app:notify("That is not a Builder project", "error")
    return
  end
  project = saved
  project.logic = project.logic or ""
  state.path = path
  state.selected = 1
  state.modified = false
  codeView:setText(project.logic)
  vfs.touchRecent(path)
  refresh()
end

local function saveAs(path)
  project.logic = codeView:getText()
  if not util.writeTable(path, project) then
    app:notify("Could not save", "error")
    return false
  end
  state.path = path
  state.modified = false
  vfs.touchRecent(path)
  refresh()
  app:notify("Saved " .. fs.getName(path), "success")
  return true
end

local function save()
  if state.path then return saveAs(state.path) end
  app:prompt({
    title = "Save project",
    text = vfs.HOME .. "/Scripts/" .. project.id .. ".aapp",
    acceptLabel = "Save",
    onAccept = function(path) if util.trim(path) ~= "" then saveAs(util.trim(path)) end end,
  })
end

local function editAppSettings()
  local idEntry = W.Entry({ text = project.id, placeholder = "app id" })
  idEntry.hexpand = true
  local nameEntry = W.Entry({ text = project.name, placeholder = "App name" })
  nameEntry.hexpand = true
  local summaryEntry = W.Entry({ text = project.summary, placeholder = "One-line summary" })
  summaryEntry.hexpand = true
  local sizeEntry = W.Entry({ text = ("%d,%d"):format(project.width, project.height),
                              placeholder = "width,height" })
  sizeEntry.hexpand = true

  local form = base.Box({ orientation = "vertical", spacing = 0 })
  form.hexpand = true
  form:add(idEntry)
  form:add(nameEntry)
  form:add(summaryEntry)
  form:add(sizeEntry)

  app:dialog({
    title = "App settings",
    body = form,
    actions = {
      { label = "Cancel" },
      { label = "Apply", style = "suggested", onClick = function()
          project.id = util.trim(idEntry.text):gsub("%s+", "-"):lower()
          project.name = util.trim(nameEntry.text)
          project.summary = util.trim(summaryEntry.text)
          local parts = util.splitAll(sizeEntry.text, ",")
          project.width = util.clamp(tonumber(parts[1]) or project.width, 16, 51)
          project.height = util.clamp(tonumber(parts[2]) or project.height, 5, 25)
          state.modified = true
          refresh()
        end },
    },
  })
  app:setFocus(nameEntry)
end

-------------------------------------------------------------------- menu ---

local function openMenu()
  app:menu(app.surface.w - 28, 2, {
    { label = "New project", icon = "\254", action = function()
        project = {
          id = "myapp", name = "My App", summary = "", category = "Other",
          iconColour = colours.magenta, iconGlyph = "A",
          width = 40, height = 14, widgets = {}, logic = "",
        }
        state.path = nil
        state.modified = false
        codeView:setText("")
        refresh()
      end },
    { label = "Open project\133", icon = "\4", accel = "^O", action = function()
        app:prompt({
          title = "Open project",
          text = state.path or (vfs.HOME .. "/Scripts/"),
          acceptLabel = "Open",
          onAccept = function(path) if fs.exists(path) then loadProject(path) end end,
        })
      end },
    { label = "Save project", icon = "\4", accel = "^S", action = save },
    { separator = true },
    { label = "App settings\133", icon = "\4", action = editAppSettings },
    { label = "Widget properties\133", icon = "\187", action = editProperties },
    { label = "Event handler\133", icon = "\16", action = editHandler },
    { label = "Delete widget", icon = "\215", destructive = true, action = function()
        if project.widgets[state.selected] then
          table.remove(project.widgets, state.selected)
          state.selected = math.max(1, state.selected - 1)
          state.modified = true
          refresh()
        end
      end },
    { separator = true },
    { label = "Run", icon = "\16", accel = "F5", action = runProject },
    { label = "Publish to my apps", icon = "\4", action = publish },
    { label = "Export installer\133", icon = "\4", action = exportInstaller },
    { label = "Copy source to editor", icon = "\187", action = function()
        local path = "/aurora/var/builder-source.lua"
        util.writeFile(path, currentSource())
        appsSvc.launch("editor", { path })
      end },
  }, 28)
end

------------------------------------------------------------------ wiring ---

tabs:connect("changed", function(_, index, tab)
  pages:setPage(tab.id)
  if tab.id == "source" then generatedView:setText(generate()) end
  if tab.id == "logic" then app:setFocus(codeView) end
  app:queueLayout()
end)

outline:connect("select", function(_, index)
  state.selected = index
  canvas:invalidate()
  app:queueDraw()
end)
outline:connect("activate", editProperties)

addButton:connect("clicked", addWidget)
runButton:connect("clicked", runProject)
menuButton:connect("clicked", openMenu)
canvas:connect("changed", refresh)
codeView:connect("changed", function()
  project.logic = codeView:getText()
  state.modified = true
end)

app:accel("ctrl+s", save)
app:accel("ctrl+n", addWidget)
app:accel("f5", runProject)
app:accel("f2", editProperties)
app:accel("ctrl+e", editHandler)
app:accel("ctrl+p", publish)

app.onClose = function()
  if not state.modified then return true end
  app:confirm({
    title = "Save before closing?",
    message = "This project has unsaved changes.",
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
    if path and fs.exists(path) then loadProject(path) end
  end
end

if state.path and fs.exists(state.path) then
  loadProject(state.path)
else
  state.path = nil
  -- a small starter project so the canvas is never empty
  project.widgets = {
    { kind = "Label", name = "title", x = 2, y = 2, w = 20, h = 1,
      props = { text = "Hello, Aurora", dim = false, align = "start" }, handlers = {} },
    { kind = "Button", name = "go", x = 2, y = 4, w = 12, h = 1,
      props = { text = "Press me", style = "suggested" },
      handlers = { clicked = "ui.title:setText(\"You pressed it!\")" } },
  }
  codeView:setText(project.logic)
end

refresh()
app:setFocus(outline)
app:run()
