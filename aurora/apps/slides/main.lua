--[[ Slides -- presentations for Aurora --------------------------------------
     Edit a deck of slides, preview them live, and present full screen or on
     any attached monitor (which is the whole point of doing this in
     Minecraft: a wall of monitors makes a projector).
----------------------------------------------------------------------------]]

local args       = { ... }
local App        = arequire("ui.app")
local base       = arequire("ui.widget")
local W          = arequire("ui.widgets")
local theme      = arequire("gfx.theme")
local util       = arequire("lib.util")
local pixel      = arequire("gfx.pixel")
local Surface    = arequire("gfx.surface")
local vfs        = arequire("kernel.vfs")
local printer    = arequire("svc.printer")
local devices    = arequire("kernel.devices")
local displaySvc = arequire("svc.display")
local compositor = arequire("gfx.compositor")

local app = App({ title = "Slides" })

local deck = {
  title = "Untitled deck",
  slides = {
    { title = "Your title here", body = { "First point", "Second point" }, layout = "title" },
  },
}
local state = { path = args[1], index = 1, modified = false, presenting = nil }

local LAYOUTS = {
  { id = "title",   label = "Title" },
  { id = "bullets", label = "Bullets" },
  { id = "quote",   label = "Quote" },
  { id = "big",     label = "Big number" },
}

------------------------------------------------------------- slide render --

--- Draw one slide into any surface.  Used for the preview, for presenting
--- full screen, and for presenting on a monitor.
local function renderSlide(s, slide, x, y, w, h, large)
  local c = theme.c
  s:fill(x, y, w, h, " ", c.text, c.window)
  if not slide then return end

  local title = slide.title or ""
  local body = slide.body or {}

  if slide.layout == "title" then
    local titleY = y + math.max(1, math.floor(h / 2) - 2)
    if large and h >= 9 and w >= 20 then
      local canvas = pixel.Canvas(math.min(w - 2, 40), 3, c.window)
      local text = title:upper():sub(1, 12)
      local tw = pixel.textWidth(text)
      canvas:text(math.max(1, math.floor((canvas.w - tw) / 2) + 1), 2, text, c.accent)
      canvas:render(s, x + math.floor((w - math.min(w - 2, 40)) / 2), titleY - 1)
    else
      s:writeCentered(titleY, title, c.accent, c.window, x, w)
    end
    local line = body[1] or ""
    s:writeCentered(titleY + (large and 4 or 2), line, c.dim, c.window, x, w)

  elseif slide.layout == "quote" then
    local lines = util.wrap(body[1] or title, math.max(8, w - 6))
    local top = y + math.max(1, math.floor((h - #lines) / 2))
    for i, text in ipairs(lines) do
      s:writeCentered(top + i - 1, "\"" .. text .. "\"", c.text, c.window, x, w)
    end
    s:writeCentered(top + #lines + 1, "\151 " .. title, c.dim, c.window, x, w)

  elseif slide.layout == "big" then
    local value = body[1] or "42"
    if large and h >= 8 and w >= 16 then
      local canvas = pixel.Canvas(math.min(w - 2, 36), 3, c.window)
      local tw = pixel.textWidth(value:sub(1, 10))
      canvas:text(math.max(1, math.floor((canvas.w - tw) / 2) + 1), 2, value:sub(1, 10), c.accent)
      canvas:render(s, x + math.floor((w - math.min(w - 2, 36)) / 2), y + math.floor(h / 2) - 2)
    else
      s:writeCentered(y + math.floor(h / 2) - 1, value, c.accent, c.window, x, w)
    end
    s:writeCentered(y + math.floor(h / 2) + (large and 3 or 1), title, c.text, c.window, x, w)

  else
    s:write(x + 2, y + 1, util.ellipsis(title, w - 4), c.accent, c.window)
    s:fill(x + 2, y + 2, math.min(w - 4, #title), 1, "\131", c.accent, c.window)
    local row = y + 4
    for _, item in ipairs(body) do
      for i, line in ipairs(util.wrap(item, w - 8)) do
        if row > y + h - 1 then break end
        if i == 1 then
          s:write(x + 3, row, "\7", c.accentSoft, c.window)
          s:write(x + 5, row, line, c.text, c.window)
        else
          s:write(x + 5, row, line, c.text, c.window)
        end
        row = row + 1
      end
      row = row + (h > 12 and 1 or 0)
    end
  end
end

---------------------------------------------------------- preview widget ---

local Preview = util.class(base.Widget)

function Preview:init()
  base.Widget.init(self, {})
  self.hexpand, self.vexpand = true, true
end

function Preview:measure() return 24, 8 end

function Preview:draw(s)
  local c = theme.c
  s:fill(self.x, self.y, self.w, self.h, " ", c.text, c.desktop)
  local inner = { x = self.x + 1, y = self.y, w = self.w - 2, h = self.h - 1 }
  local behind = c.desktop
  compositor.drawShadow(s, inner.x, inner.y, inner.w, inner.h)
  renderSlide(s, deck.slides[state.index], inner.x, inner.y, inner.w, inner.h, self.h >= 9)
  s:roundRect(inner.x, inner.y, inner.w, inner.h, c.window, behind)
  s:writeRight(self.x, self.y + self.h - 1,
               ("Slide %d of %d"):format(state.index, #deck.slides),
               c.dim, c.desktop, self.w - 1)
end

-------------------------------------------------------------------- chrome --

local slideList = W.ListBox({ rows = {}, showSubtitles = false })
slideList.vexpand = true
local listScroller = base.Scrolled({ background = theme.c.window })
listScroller.widthRequest = 14
listScroller.vexpand = true
listScroller:setChild(slideList)

local preview = Preview()

local nameLabel = W.Label({ text = "Untitled deck" })
nameLabel.hexpand = true
local presentButton = W.Button({ label = "Present", style = "suggested" })
local addButton = W.IconButton({ icon = "\4", width = 3 })
local menuButton = W.IconButton({ icon = "\7", width = 3 })

local toolbar = W.Toolbar({ spacing = 0 })
toolbar:add(nameLabel)
toolbar:add(addButton)
toolbar:add(presentButton)
toolbar:add(menuButton)

local body = base.Box({ orientation = "horizontal", spacing = 0 })
body.hexpand, body.vexpand = true, true
body:add(listScroller)
body:add(W.Separator({ orientation = "vertical" }))
body:add(preview)

local root = base.Box({ orientation = "vertical", spacing = 0 })
root.hexpand, root.vexpand = true, true
root:add(toolbar)
root:add(body)
app:setRoot(root)

------------------------------------------------------------------ helpers --

local function refresh()
  local rows = {}
  for i, slide in ipairs(deck.slides) do
    rows[#rows + 1] = {
      title = ("%d. %s"):format(i, util.ellipsis(slide.title or "Untitled", 9)),
      icon = { char = "\254", colour = i == state.index and theme.c.accent or theme.c.dim },
    }
  end
  slideList:setRows(rows, true)
  slideList.selected = state.index
  nameLabel:setText(" " .. util.ellipsis(deck.title, 20) .. (state.modified and " \7" or ""))
  aurora.setTitle(deck.title .. (state.modified and " *" or ""))
  app:queueDraw()
end

local function currentSlide()
  return deck.slides[state.index]
end

local function editSlide()
  local slide = currentSlide()
  if not slide then return end

  local titleEntry = W.Entry({ text = slide.title or "", placeholder = "Slide title" })
  titleEntry.hexpand = true
  local bodyEntry = W.Entry({ text = table.concat(slide.body or {}, " | "),
                              placeholder = "Points separated by |" })
  bodyEntry.hexpand = true
  local layoutTabs = W.Tabs({ tabs = {
    { label = "Title", id = "title" },
    { label = "List", id = "bullets" },
    { label = "Quote", id = "quote" },
    { label = "Big", id = "big" },
  } })
  for i, tab in ipairs(layoutTabs.tabs) do
    if tab.id == (slide.layout or "bullets") then layoutTabs.active = i end
  end

  local form = base.Box({ orientation = "vertical", spacing = 1 })
  form.hexpand = true
  form:add(titleEntry)
  form:add(bodyEntry)
  form:add(layoutTabs)

  app:dialog({
    title = "Edit slide " .. state.index,
    body = form,
    actions = {
      { label = "Cancel" },
      { label = "Apply", style = "suggested", onClick = function()
          slide.title = titleEntry.text
          slide.body = {}
          for _, piece in ipairs(util.splitAll(bodyEntry.text, "|")) do
            piece = util.trim(piece)
            if piece ~= "" then slide.body[#slide.body + 1] = piece end
          end
          slide.layout = layoutTabs.tabs[layoutTabs.active].id
          state.modified = true
          refresh()
        end },
    },
  })
  app:setFocus(titleEntry)
end

local function addSlide()
  table.insert(deck.slides, state.index + 1, {
    title = "New slide", body = { "Point one" }, layout = "bullets",
  })
  state.index = state.index + 1
  state.modified = true
  refresh()
  editSlide()
end

local function deleteSlide()
  if #deck.slides <= 1 then
    app:notify("A deck needs at least one slide")
    return
  end
  table.remove(deck.slides, state.index)
  state.index = util.clamp(state.index, 1, #deck.slides)
  state.modified = true
  refresh()
end

--------------------------------------------------------------- load / save --

local function loadDeck(path)
  local saved = util.readTable(path, nil)
  if not saved or not saved.slides then
    app:notify("That is not a deck", "error")
    return
  end
  deck = saved
  state.path = path
  state.index = 1
  state.modified = false
  vfs.touchRecent(path)
  refresh()
end

local function saveAs(path)
  if not util.writeTable(path, deck) then
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
    title = "Save deck",
    text = vfs.HOME .. "/Decks/" .. deck.title:gsub("%s+", "-"):lower() .. ".adeck",
    acceptLabel = "Save",
    onAccept = function(path) if util.trim(path) ~= "" then saveAs(util.trim(path)) end end,
  })
end

------------------------------------------------------------------ present ---

--- Present on a monitor: Aurora hands the whole monitor to this process and
--- we paint slides straight into its display surface.
local function presentOnMonitor(name)
  local d = displaySvc.claim(name, aurora.proc)
  if not d then
    app:notify("Could not take over that monitor", "error")
    return
  end
  state.presenting = { display = d, name = name }
  app:notify("Presenting on " .. name .. "  \183  arrow keys to move", "success")
  app:queueDraw()
end

local function stopPresenting()
  if state.presenting then
    displaySvc.release(state.presenting.name)
    state.presenting = nil
    app:notify("Stopped presenting")
    app:queueDraw()
  end
end

--- Repaint whatever we are presenting on.
local function paintPresentation()
  if not state.presenting then return end
  local d = state.presenting.display
  local s = d.surface
  s:resetClip()
  renderSlide(s, currentSlide(), 1, 1, s.w, s.h, true)
  -- a slim progress strip along the bottom
  local filled = math.floor(s.w * (state.index / math.max(1, #deck.slides)) + 0.5)
  s:fill(1, s.h, s.w, 1, " ", theme.c.accent, theme.c.card)
  if filled > 0 then s:fill(1, s.h, filled, 1, " ", theme.c.accent, theme.c.accent) end
  d:invalidate()
  d:present()
end

local function gotoSlide(index)
  state.index = util.clamp(index, 1, #deck.slides)
  refresh()
  paintPresentation()
end

local function choosePresentTarget()
  local monitors = devices.byClass("display")
  local items = {}
  for _, record in ipairs(monitors) do
    items[#items + 1] = {
      label = record.name .. (record.w and ("  " .. record.w .. "x" .. record.h) or ""),
      icon = "\254",
      action = function() presentOnMonitor(record.name) end,
    }
  end
  if #items == 0 then
    app:dialog({
      title = "No monitors attached",
      body = "Place a monitor next to this computer (or wire one up with modems) "
             .. "and it will show up here.",
      actions = { { label = "OK", style = "suggested" } },
    })
    return
  end
  items[#items + 1] = { separator = true }
  items[#items + 1] = { label = "Stop presenting", icon = "\215",
                        disabled = state.presenting == nil, action = stopPresenting }
  app:menu(app.surface.w - 26, 2, items, 26)
end

-------------------------------------------------------------------- menu ---

local function openMenu()
  app:menu(app.surface.w - 26, 2, {
    { label = "New deck", icon = "\254", action = function()
        deck = { title = "Untitled deck", slides = {
          { title = "Your title here", body = { "Subtitle" }, layout = "title" } } }
        state.path = nil
        state.index = 1
        state.modified = false
        refresh()
      end },
    { label = "Open\133", icon = "\4", accel = "^O", action = function()
        app:prompt({
          title = "Open deck",
          text = state.path or (vfs.HOME .. "/Decks/"),
          acceptLabel = "Open",
          onAccept = function(path) if fs.exists(path) then loadDeck(path) end end,
        })
      end },
    { label = "Save", icon = "\4", accel = "^S", action = save },
    { label = "Rename deck\133", icon = "\187", action = function()
        app:prompt({
          title = "Deck title",
          text = deck.title,
          onAccept = function(text)
            deck.title = util.trim(text)
            state.modified = true
            refresh()
          end,
        })
      end },
    { separator = true },
    { label = "Edit slide", icon = "\187", accel = "\17\217", action = editSlide },
    { label = "Add slide", icon = "\4", action = addSlide },
    { label = "Delete slide", icon = "\215", destructive = true, action = deleteSlide },
    { label = "Move slide up", icon = "\30", action = function()
        if state.index > 1 then
          deck.slides[state.index], deck.slides[state.index - 1] =
            deck.slides[state.index - 1], deck.slides[state.index]
          state.index = state.index - 1
          state.modified = true
          refresh()
        end
      end },
    { label = "Move slide down", icon = "\31", action = function()
        if state.index < #deck.slides then
          deck.slides[state.index], deck.slides[state.index + 1] =
            deck.slides[state.index + 1], deck.slides[state.index]
          state.index = state.index + 1
          state.modified = true
          refresh()
        end
      end },
    { separator = true },
    { label = "Present on a monitor\133", icon = "\254", action = choosePresentTarget },
    { label = "Stop presenting", icon = "\215", disabled = state.presenting == nil,
      action = stopPresenting },
    { label = "Print handout", icon = "\22", action = function()
        local lines = {}
        for i, slide in ipairs(deck.slides) do
          lines[#lines + 1] = ("%d. %s"):format(i, slide.title or "")
          for _, point in ipairs(slide.body or {}) do
            lines[#lines + 1] = "   - " .. point
          end
          lines[#lines + 1] = ""
        end
        local job = printer.submit({ title = deck.title, content = lines })
        app:notify("Queued handout for printing", "success")
      end },
  }, 26)
end

------------------------------------------------------------------ wiring ---

slideList:connect("select", function(_, index)
  state.index = util.clamp(index, 1, #deck.slides)
  refresh()
  paintPresentation()
end)
slideList:connect("activate", function() editSlide() end)

addButton:connect("clicked", addSlide)
menuButton:connect("clicked", openMenu)
presentButton:connect("clicked", function()
  if state.presenting then stopPresenting() else choosePresentTarget() end
end)

app:accel("ctrl+s", save)
app:accel("ctrl+n", addSlide)
app:accel("ctrl+e", editSlide)
app:accel("f5", choosePresentTarget)
app:accel("pageDown", function() gotoSlide(state.index + 1) end)
app:accel("pageUp", function() gotoSlide(state.index - 1) end)
app:accel("escape", stopPresenting)

app.onClose = function()
  stopPresenting()
  if not state.modified then return true end
  app:confirm({
    title = "Save before closing?",
    message = "This deck has unsaved changes.",
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
    if path and fs.exists(path) then loadDeck(path) end
  elseif name == "monitor_touch" and state.presenting then
    gotoSlide(state.index + 1)
  elseif name == "peripheral_detach" and state.presenting
         and select(1, ...) == state.presenting.name then
    state.presenting = nil
    app:notify("The monitor was removed", "error")
  end
end

if state.path and fs.exists(state.path) then
  loadDeck(state.path)
end

refresh()
app:setFocus(slideList)
app:run()
