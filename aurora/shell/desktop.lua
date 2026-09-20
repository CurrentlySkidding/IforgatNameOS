--[[ aurora.shell.desktop ----------------------------------------------------
     The desktop shell: top panel, Activities overview, dash, app grid,
     notifications, the power menu, the lock screen and all window management.

     It gets first refusal on every event; anything it does not claim falls
     through to the process table.
----------------------------------------------------------------------------]]

local util       = arequire("lib.util")
local theme      = arequire("gfx.theme")
local Surface    = arequire("gfx.surface")
local pixel      = arequire("gfx.pixel")
local compositor = arequire("gfx.compositor")
local sched      = arequire("kernel.sched")
local devices    = arequire("kernel.devices")
local log        = arequire("kernel.log")
local apps       = arequire("svc.apps")
local displaySvc = arequire("svc.display")
local wallpaper  = arequire("shell.wallpaper")

local desktop = {}

desktop.PANEL_H = 1
desktop.overview = false
desktop.appGrid = false
desktop.locked = false
desktop.search = ""
desktop.searchResults = {}
desktop.searchIndex = 1
desktop.notifications = {}
desktop.drag = nil
desktop.switcher = nil
desktop.powerMenu = false
desktop.hover = { control = nil, proc = nil }
desktop.dashSelection = 1
desktop.gridSelection = 1
desktop.overviewSelection = 1

local ACTIVITIES = "Activities"

-------------------------------------------------------------------- init ----

function desktop.init()
  theme.onChange(function()
    wallpaper.invalidate()
    compositor.resetAll()
    sched.damageAll()
  end)
  sched.on("exit", function(proc)
    displaySvc.releaseAllFor(proc.pid)
    if proc.crashed then
      desktop.notify(proc.title or proc.name, "stopped unexpectedly", "error")
    end
  end)
  desktop.clockTimer = os.startTimer(1)
end

------------------------------------------------------------ notifications ---

function desktop.notify(title, body, kind)
  table.insert(desktop.notifications, 1, {
    title = title, body = body, kind = kind or "info",
    expires = os.clock() + (kind == "error" and 8 or 5),
  })
  while #desktop.notifications > 4 do table.remove(desktop.notifications) end
  sched.dirty = true
end

local function expireNotifications()
  local now = os.clock()
  local changed = false
  for i = #desktop.notifications, 1, -1 do
    if desktop.notifications[i].expires <= now then
      table.remove(desktop.notifications, i)
      changed = true
    end
  end
  if changed then sched.dirty = true end
end

------------------------------------------------------------------- panel ----

local function statusItems()
  local items = {}
  local counts = devices.summary()
  if counts.network then
    items[#items + 1] = { char = "\015", colour = theme.c.accent, tip = "Network" }
  end
  if counts.printer then
    items[#items + 1] = { char = "\022", colour = theme.c.warning, tip = "Printer" }
  end
  if counts.display then
    items[#items + 1] = { char = "\254", colour = theme.c.accentSoft, tip = "Monitor" }
  end
  if counts.audio then
    items[#items + 1] = { char = "\014", colour = theme.c.success, tip = "Speaker" }
  end
  return items
end

function desktop.drawPanel(s, d)
  local c = theme.c
  local bg = c.panel
  s:fill(1, 1, s.w, 1, " ", c.panelText, bg)

  -- Activities
  local label = ACTIVITIES
  if s.w < 40 then label = "Apps" end
  local activeFg = desktop.overview and c.accent or c.panelText
  s:write(2, 1, "\7", desktop.overview and c.accent or c.dim, bg)
  s:write(4, 1, label, activeFg, bg)
  desktop.activitiesRect = { x = 1, w = #label + 4 }

  -- clock, centred
  local clock = util.clock()
  local date = util.dateLine()
  local centre = clock
  if s.w >= 44 then centre = clock .. "  " .. date end
  local cx = math.floor((s.w - #centre) / 2) + 1
  s:write(cx, 1, centre, c.panelText, bg)
  desktop.clockRect = { x = cx, w = #centre }

  -- status area
  local items = statusItems()
  local x = s.w - 1
  s:write(x, 1, "\30", c.panelText, bg)      -- power / system menu
  desktop.powerRect = { x = x, w = 1 }
  x = x - 2
  for i = #items, 1, -1 do
    s:write(x, 1, items[i].char, items[i].colour, bg)
    x = x - 2
  end
  desktop.statusRect = { x = x + 2, w = s.w - 2 - (x + 2) }
end

------------------------------------------------------------------ windows ---

local function clientOrigin(win)
  return win.x, win.y + (win.headerless and 0 or 1)
end

function desktop.drawWindows(s, d)
  for _, proc in ipairs(sched.stack) do
    local win = proc.win
    if win and not win.minimized and (proc.display == d or d.role ~= "extend") then
      win.focused = (sched.focus == proc)
      win.hoverControl = (desktop.hover.proc == proc) and desktop.hover.control or nil
      if not win.maximized then
        compositor.drawShadow(s, win.x, win.y, win.w, win.h)
      end
      compositor.drawFrame(s, win)
      local cx, cy = clientOrigin(win)
      s:draw(proc.surface, cx, cy)
      -- bottom-right resize grip
      if win.resizable ~= false and not win.maximized then
        s:write(win.x + win.w - 1, win.y + win.h - 1, "\133",
                theme.c.dim, theme.c.window)
      end
    end
  end
end

function desktop.applyCursor(d)
  local proc = sched.focus
  if not proc or not proc.win or proc.win.minimized or desktop.overview or desktop.locked then
    d:setCursor(1, 1, false)
    return
  end
  local win = proc.win
  local cx, cy = clientOrigin(win)
  local caret = proc.caret
  if caret then
    d:setCursor(cx + caret.x - 1, cy + caret.y - 1, true, caret.colour or theme.c.accent)
    return
  end
  local adapter = proc.term and proc.term.__aurora
  if adapter then
    local tx, ty, blink, fg = adapter.cursor()
    if blink then
      d:setCursor(cx + tx - 1, cy + ty - 1, true, fg)
      return
    end
  end
  d:setCursor(1, 1, false)
end

----------------------------------------------------------------- overview ---

local function visibleWindows()
  local out = {}
  for _, proc in ipairs(sched.stack) do
    if proc.win then out[#out + 1] = proc end
  end
  return out
end

local CARD_W, CARD_H = 11, 5

function desktop.overviewLayout(s)
  local dashH = 4
  local dashY = s.h - dashH + 1
  local searchY = 3
  local top = searchY + 2
  local bottom = dashY - 2
  return {
    searchY = searchY,
    top = top,
    bottom = bottom,
    dashY = dashY,
    dashH = dashH,
  }
end

function desktop.drawOverview(s)
  local c = theme.c
  local layout = desktop.overviewLayout(s)
  s:scrim(1, 2, s.w, s.h - 1, c.scrimText, c.scrim)

  -- search field
  local searchW = math.min(32, s.w - 8)
  local sx = math.floor((s.w - searchW) / 2) + 1
  local innerX, innerW = s:pill(sx, layout.searchY, searchW, c.card)
  local shown = desktop.search
  if shown == "" then
    s:write(innerX + 1, layout.searchY, "\4 Search apps and files", c.dim, c.card)
  else
    s:write(innerX + 1, layout.searchY, util.ellipsis(shown, innerW - 2), c.text, c.card)
  end
  desktop.searchRect = { x = sx, y = layout.searchY, w = searchW }

  if desktop.search ~= "" then
    desktop.drawSearchResults(s, layout)
  elseif desktop.appGrid then
    desktop.drawAppGrid(s, layout)
  else
    desktop.drawWindowCards(s, layout)
  end

  desktop.drawDash(s, layout)
end

function desktop.drawWindowCards(s, layout)
  local c = theme.c
  local wins = visibleWindows()
  local regionH = layout.bottom - layout.top + 1

  if #wins == 0 then
    local msg = "No open windows"
    s:writeCentered(layout.top + math.floor(regionH / 2) - 1, msg, c.dim, c.scrim)
    s:writeCentered(layout.top + math.floor(regionH / 2) + 1,
                    "Pick an app from the dash below", c.dim, c.scrim)
    desktop.cardRects = {}
    return
  end

  local cols = math.max(1, math.min(#wins, math.floor(s.w / (CARD_W + 1))))
  local rows = math.ceil(#wins / cols)
  local gridW = cols * (CARD_W + 1) - 1
  local ox = math.floor((s.w - gridW) / 2) + 1
  local oy = layout.top + math.max(0, math.floor((regionH - rows * (CARD_H + 1)) / 2))

  desktop.cardRects = {}
  for i, proc in ipairs(wins) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x = ox + col * (CARD_W + 1)
    local y = oy + row * (CARD_H + 1)
    if y + CARD_H - 1 <= layout.bottom then
      local selected = (i == desktop.overviewSelection)
      local bg = selected and c.hover or c.card
      compositor.drawShadow(s, x, y, CARD_W, CARD_H)
      s:fill(x, y, CARD_W, CARD_H, " ", c.text, bg)
      s:roundRect(x, y, CARD_W, CARD_H, bg, c.scrim)

      local manifest = proc.meta and proc.meta.manifest
      local icon = manifest and manifest.icon or { colour = c.accent, glyph = "?" }
      pixel.drawIcon(s, x + math.floor((CARD_W - 6) / 2), y + 1, icon, 6, 3, bg)
      local title = util.ellipsis(proc.title or proc.name, CARD_W - 2)
      s:write(x + math.floor((CARD_W - #title) / 2), y + CARD_H - 1, title,
              selected and c.text or c.dim, bg)
      if selected then
        s:write(x + CARD_W - 2, y, "\215", c.destructive, bg)
      end
      desktop.cardRects[#desktop.cardRects + 1] =
        { x = x, y = y, w = CARD_W, h = CARD_H, proc = proc, index = i }
    end
  end
end

function desktop.drawAppGrid(s, layout)
  local c = theme.c
  local list = apps.all()
  local cellW, cellH = 9, 4
  local cols = math.max(1, math.floor((s.w - 2) / cellW))
  local regionH = layout.bottom - layout.top + 1
  local rowsVisible = math.max(1, math.floor(regionH / cellH))
  local perPage = cols * rowsVisible
  desktop.gridPage = util.clamp(desktop.gridPage or 1, 1,
                                math.max(1, math.ceil(#list / perPage)))
  local startIndex = (desktop.gridPage - 1) * perPage + 1

  local gridW = cols * cellW
  local ox = math.floor((s.w - gridW) / 2) + 1
  desktop.gridRects = {}

  for slot = 0, perPage - 1 do
    local index = startIndex + slot
    local manifest = list[index]
    if manifest then
      local col = slot % cols
      local row = math.floor(slot / cols)
      local x = ox + col * cellW
      local y = layout.top + row * cellH
      local selected = (index == desktop.gridSelection)
      local bg = selected and c.hover or c.scrim
      if selected then
        s:fill(x, y, cellW, cellH, " ", c.text, bg)
        s:roundRect(x, y, cellW, cellH, bg, c.scrim)
      end
      pixel.drawIcon(s, x + math.floor((cellW - 6) / 2), y, manifest.icon, 6, 3, bg)
      local label = util.ellipsis(manifest.name, cellW - 1)
      s:write(x + math.floor((cellW - #label) / 2), y + 3, label, c.text, bg)
      desktop.gridRects[#desktop.gridRects + 1] =
        { x = x, y = y, w = cellW, h = cellH, manifest = manifest, index = index }
    end
  end

  local pages = math.max(1, math.ceil(#list / perPage))
  if pages > 1 then
    local dots = ""
    for i = 1, pages do dots = dots .. (i == desktop.gridPage and "\7" or "\250") end
    s:writeCentered(layout.bottom, dots, c.dim, c.scrim)
  end
end

function desktop.drawSearchResults(s, layout)
  local c = theme.c
  local results = desktop.searchResults
  if #results == 0 then
    s:writeCentered(layout.top + 2, "No results for \"" .. desktop.search .. "\"", c.dim, c.scrim)
    return
  end
  local w = math.min(40, s.w - 6)
  local x = math.floor((s.w - w) / 2) + 1
  desktop.resultRects = {}
  for i, item in ipairs(results) do
    local y = layout.top + i - 1
    if y > layout.bottom then break end
    local selected = (i == desktop.searchIndex)
    local bg = selected and c.accent or c.card
    local fg = selected and c.onAccent or c.text
    s:fill(x, y, w, 1, " ", fg, bg)
    s:roundRect(x, y, w, 1, bg, c.scrim)
    s:write(x + 2, y, item.char or "\4", selected and c.onAccent or (item.colour or c.accent), bg)
    s:write(x + 4, y, util.ellipsis(item.label, w - 6), fg, bg)
    if item.detail then
      local detail = util.ellipsis(item.detail, 14)
      s:write(x + w - #detail - 2, y, detail, selected and c.onAccent or c.dim, bg)
    end
    desktop.resultRects[#desktop.resultRects + 1] = { x = x, y = y, w = w, item = item, index = i }
  end
end

function desktop.drawDash(s, layout)
  local c = theme.c
  local favourites = apps.favourites()
  local iconW = 6
  local gap = 1
  local count = #favourites + 1     -- +1 for the app-grid button
  local dashW = count * (iconW + gap) - gap + 2
  dashW = math.min(dashW, s.w - 2)
  local x = math.floor((s.w - dashW) / 2) + 1
  local y = layout.dashY

  compositor.drawShadow(s, x, y, dashW, layout.dashH - 1)
  s:fill(x, y, dashW, layout.dashH - 1, " ", c.text, c.card)
  s:roundRect(x, y, dashW, layout.dashH - 1, c.card, c.scrim)

  desktop.dashRects = {}
  local cursor = x + 1
  for i, manifest in ipairs(favourites) do
    if cursor + iconW - 1 <= x + dashW - 1 then
      pixel.drawIcon(s, cursor, y, manifest.icon, iconW, 3, c.card)
      desktop.dashRects[#desktop.dashRects + 1] =
        { x = cursor, y = y, w = iconW, h = 3, manifest = manifest, index = i }
      cursor = cursor + iconW + gap
    end
  end

  -- app grid button
  if cursor + iconW - 1 <= x + dashW - 1 then
    local icon = { colour = desktop.appGrid and theme.c.accent or theme.c.active,
                   art = { "..+.+.+..", "..+.+.+..", "..+.+.+.." }, accent = theme.c.onAccent }
    pixel.drawIcon(s, cursor, y, icon, iconW, 3, c.card)
    desktop.dashRects[#desktop.dashRects + 1] =
      { x = cursor, y = y, w = iconW, h = 3, gridButton = true }
  end

  -- running indicators, one dot under each running favourite
  for _, rect in ipairs(desktop.dashRects) do
    if rect.manifest and sched.find(rect.manifest.id) then
      s:write(rect.x + math.floor(iconW / 2) - 1, y + 3, "\7", c.accent, c.card)
    end
  end
end

--------------------------------------------------------------- power menu ---

local POWER_ITEMS = {
  { id = "lock",     label = "Lock screen",  icon = "\7" },
  { id = "settings", label = "Settings",     icon = "\4" },
  { id = "monitor",  label = "System monitor", icon = "\254" },
  { id = "restart",  label = "Restart",      icon = "\24" },
  { id = "shutdown", label = "Shut down",    icon = "\25", destructive = true },
  { id = "craftos",  label = "Exit to CraftOS", icon = "\27" },
}

function desktop.drawPowerMenu(s)
  local c = theme.c
  local w = 22
  local h = #POWER_ITEMS
  local x = s.w - w
  local y = 2
  compositor.drawShadow(s, x, y, w, h)
  s:fill(x, y, w, h, " ", c.text, c.card)
  s:roundRect(x, y, w, h, c.card, select(3, s:getCell(x, y + h)) or c.desktop)
  desktop.powerRects = {}
  for i, item in ipairs(POWER_ITEMS) do
    local iy = y + i - 1
    local selected = (desktop.powerSelection == i)
    local bg = selected and c.hover or c.card
    local fg = item.destructive and c.destructive or c.text
    s:fill(x, iy, w, 1, " ", fg, bg)
    s:write(x + 1, iy, item.icon, item.destructive and c.destructive or c.accent, bg)
    s:write(x + 3, iy, item.label, fg, bg)
    desktop.powerRects[#desktop.powerRects + 1] = { x = x, y = iy, w = w, item = item, index = i }
  end
end

function desktop.powerAction(id)
  desktop.powerMenu = false
  if id == "lock" then
    desktop.locked = true
  elseif id == "settings" then
    apps.launch("settings")
  elseif id == "monitor" then
    apps.launch("monitor")
  elseif id == "restart" then
    desktop.shutdown("restart")
  elseif id == "shutdown" then
    desktop.shutdown("shutdown")
  elseif id == "craftos" then
    desktop.shutdown("exit")
  end
  sched.dirty = true
end

function desktop.shutdown(mode)
  desktop.quitReason = mode
  desktop.running = false
end

------------------------------------------------------------- lock screen ----

function desktop.drawLock(s)
  local c = theme.c
  local wp = wallpaper.get(s.w, s.h)
  s:draw(wp, 1, 1)
  s:scrim(1, 1, s.w, s.h, c.scrimText, c.scrim)

  local clock = util.clock()
  local canvasW = math.min(s.w - 4, pixel.textWidth(clock) / 2 + 4)
  local canvas = pixel.Canvas(math.ceil(canvasW), 3, c.scrim)
  local tw = pixel.textWidth(clock)
  canvas:text(math.floor((canvas.w - tw) / 2) + 1, 2, clock, c.text)
  canvas:render(s, math.floor((s.w - math.ceil(canvasW)) / 2) + 1, math.floor(s.h / 2) - 3)

  s:writeCentered(math.floor(s.h / 2) + 1, util.dateLine(), c.dim, c.scrim)
  s:writeCentered(s.h - 2, "Press any key to unlock", c.dim, c.scrim)
end

---------------------------------------------------------------- switcher ----

function desktop.drawSwitcher(s)
  local c = theme.c
  local wins = visibleWindows()
  if #wins == 0 then return end
  local itemW = 12
  local w = math.min(s.w - 4, #wins * itemW + 2)
  local h = 5
  local x = math.floor((s.w - w) / 2) + 1
  local y = math.floor((s.h - h) / 2) + 1
  compositor.drawShadow(s, x, y, w, h)
  s:fill(x, y, w, h, " ", c.text, c.card)
  s:roundRect(x, y, w, h, c.card, select(3, s:getCell(x, y - 1)) or c.desktop)
  for i, proc in ipairs(wins) do
    local ix = x + 1 + (i - 1) * itemW
    if ix + itemW - 1 <= x + w - 1 then
      local selected = (i == desktop.switcher.index)
      local bg = selected and c.hover or c.card
      if selected then s:fill(ix, y, itemW, h, " ", c.text, bg) end
      local manifest = proc.meta and proc.meta.manifest
      pixel.drawIcon(s, ix + math.floor((itemW - 6) / 2), y + 1,
                     manifest and manifest.icon or { colour = c.accent }, 6, 3, bg)
      local title = util.ellipsis(proc.title or proc.name, itemW - 1)
      s:write(ix + math.floor((itemW - #title) / 2), y + 4, title,
              selected and c.text or c.dim, bg)
    end
  end
end

----------------------------------------------------------- notifications ----

function desktop.drawNotifications(s)
  local c = theme.c
  local y = 2
  for _, note in ipairs(desktop.notifications) do
    local w = math.min(34, s.w - 4)
    local x = s.w - w - 1
    local h = note.body and 2 or 1
    compositor.drawShadow(s, x, y, w, h)
    s:fill(x, y, w, h, " ", c.text, c.card)
    s:roundRect(x, y, w, h, c.card, select(3, s:getCell(x, y - 1)) or c.desktop)
    local accent = c.accent
    if note.kind == "error" then accent = c.destructive end
    if note.kind == "success" then accent = c.success end
    s:write(x + 1, y, "\7", accent, c.card)
    s:write(x + 3, y, util.ellipsis(note.title, w - 4), c.text, c.card)
    if note.body then
      s:write(x + 3, y + 1, util.ellipsis(note.body, w - 4), c.dim, c.card)
    end
    y = y + h + 1
  end
end

------------------------------------------------------------------ render ----

function desktop.renderTo(d)
  local s = d.surface
  s:resetClip()

  if d.role == "off" then
    s:clear(colours.black, colours.black)
    d:invalidate()
    return
  end

  if d.role == "dedicated" then
    local owner = displaySvc.ownerOf(d.id)
    if owner then
      s:clear(theme.c.window, theme.c.text)
      s:draw(owner.surface, 1, 1)
      d:invalidate()
      return
    end
    displaySvc.drawIdle(d)
    return
  end

  if desktop.locked and d.kind == "screen" then
    desktop.drawLock(s)
    d:setCursor(1, 1, false)
    d:invalidate()
    return
  end

  local wp = wallpaper.get(s.w, s.h)
  s:draw(wp, 1, 1)

  desktop.drawWindows(s, d)
  desktop.drawPanel(s, d)

  if d.kind == "screen" or d.role == "mirror" then
    if desktop.overview then desktop.drawOverview(s) end
    if desktop.powerMenu then desktop.drawPowerMenu(s) end
    if desktop.switcher then desktop.drawSwitcher(s) end
    desktop.drawNotifications(s)
  end

  if d.kind == "screen" then desktop.applyCursor(d) end
  d:invalidate()
end

function desktop.render()
  for _, d in ipairs(compositor.displays) do
    if d.kind == "screen" or d.role == "mirror" or d.role == "extend"
       or d.role == "dedicated" or d.role == "off" then
      desktop.renderTo(d)
    end
  end
  compositor.presentAll()
  sched.dirty = false
end

------------------------------------------------------------------ search ----

function desktop.runSearch()
  local query = util.trim(desktop.search)
  desktop.searchResults = {}
  desktop.searchIndex = 1
  if query == "" then return end

  for _, manifest in ipairs(apps.search(query)) do
    desktop.searchResults[#desktop.searchResults + 1] = {
      label = manifest.name,
      detail = manifest.category,
      char = manifest.char,
      colour = manifest.icon and manifest.icon.colour,
      action = function() apps.launch(manifest.id) end,
    }
  end

  -- match files in the user's home folder, one level deep
  local vfs = arequire("kernel.vfs")
  local lowered = query:lower()
  local function scan(dir, depth)
    if depth > 2 or #desktop.searchResults > 12 then return end
    local ok, names = pcall(fs.list, dir)
    if not ok then return end
    for _, name in ipairs(names) do
      if name:lower():find(lowered, 1, true) and name:sub(1, 1) ~= "." then
        local path = fs.combine(dir, name)
        local fileType = vfs.typeOf(path)
        desktop.searchResults[#desktop.searchResults + 1] = {
          label = name,
          detail = fileType.label,
          char = fileType.char,
          colour = fileType.colour,
          action = function() apps.openFile(path) end,
        }
        if #desktop.searchResults > 12 then return end
      end
      local path = fs.combine(dir, name)
      if fs.isDir(path) and name:sub(1, 1) ~= "." then scan(path, depth + 1) end
    end
  end
  scan(vfs.HOME, 1)
end

--------------------------------------------------------------- overview -----

function desktop.toggleOverview(showGrid)
  if desktop.overview and desktop.appGrid == (showGrid or false) then
    desktop.closeOverview()
    return
  end
  desktop.overview = true
  desktop.appGrid = showGrid or false
  desktop.search = ""
  desktop.searchResults = {}
  desktop.overviewSelection = 1
  desktop.gridSelection = 1
  desktop.gridPage = 1
  sched.dirty = true
end

function desktop.closeOverview()
  desktop.overview = false
  desktop.appGrid = false
  desktop.search = ""
  sched.dirty = true
end

--------------------------------------------------------------- hit tests ----

local function inRect(rect, x, y)
  return rect and x >= rect.x and x < rect.x + (rect.w or 1)
         and (rect.y == nil or (y >= rect.y and y < rect.y + (rect.h or 1)))
end

------------------------------------------------------------ event handling --

local MOUSE = {
  mouse_click = true, mouse_up = true, mouse_drag = true, mouse_scroll = true,
}

--- Returns true when the shell consumed the event.
function desktop.handleEvent(ev)
  local name = ev[1]

  if name == "timer" and ev[2] == desktop.clockTimer then
    desktop.clockTimer = os.startTimer(1)
    expireNotifications()
    sched.dirty = true
    return true
  end

  if desktop.locked then
    if name == "key" or name == "mouse_click" or name == "char" then
      desktop.locked = false
      sched.dirty = true
    end
    return true
  end

  if name == "key" then
    return desktop.handleKey(ev[2], ev[3])
  elseif name == "key_up" then
    desktop.releaseModifier(ev[2])
    if (ev[2] == keys.leftAlt or ev[2] == keys.rightAlt) and desktop.switcher then
      local target = desktop.switcher.list[desktop.switcher.index]
      desktop.switcher = nil
      if target then sched.raise(target) end
      sched.dirty = true
      return true
    end
    return false
  elseif name == "char" then
    if desktop.overview then
      desktop.search = desktop.search .. ev[2]
      desktop.runSearch()
      sched.dirty = true
      return true
    end
    return false
  elseif MOUSE[name] then
    return desktop.handleMouse(name, ev[2], ev[3], ev[4])
  elseif name == "monitor_touch" then
    return desktop.handleTouch(ev[2], ev[3], ev[4])
  elseif name == "peripheral" or name == "peripheral_detach"
      or name == "monitor_resize" or name == "disk" or name == "disk_eject" then
    devices.handleEvent(ev)
    displaySvc.sync()
    if name == "peripheral" then
      local record = devices.get(ev[2])
      if record then desktop.notify(record.label .. " connected", record.name) end
    end
    sched.dirty = true
    return false      -- let apps see peripheral events too
  elseif name == "term_resize" then
    compositor.primary:checkSize()
    wallpaper.invalidate()
    sched.damageAll()
    return false
  end

  return false
end

-------------------------------------------------------------------- keys ----

local heldAlt = false
local heldCtrl = false

function desktop.releaseModifier(key)
  if key == keys.leftAlt or key == keys.rightAlt then heldAlt = false end
  if key == keys.leftCtrl or key == keys.rightCtrl then heldCtrl = false end
end

function desktop.handleKey(key, held)
  if key == keys.leftAlt or key == keys.rightAlt then heldAlt = true end
  if key == keys.leftCtrl or key == keys.rightCtrl then heldCtrl = true end

  -- Alt+Tab window switcher
  if key == keys.tab and heldAlt then
    local list = visibleWindows()
    if #list == 0 then return true end
    if not desktop.switcher then
      desktop.switcher = { list = list, index = math.max(1, #list - 1) }
      if #list == 1 then desktop.switcher.index = 1 end
    else
      desktop.switcher.index = desktop.switcher.index % #desktop.switcher.list + 1
    end
    sched.dirty = true
    return true
  end

  if key == keys.f1 then
    desktop.toggleOverview(false)
    return true
  end
  if key == keys.f2 then
    if desktop.overview and desktop.appGrid then
      desktop.closeOverview()
    else
      desktop.overview = true
      desktop.appGrid = true
      desktop.search = ""
      sched.dirty = true
    end
    return true
  end
  -- Ctrl+F5 forces a full repaint.  Plain F5 belongs to the focused app
  -- (refresh, run, present), so the shell keeps its hands off it.
  if key == keys.f5 and heldCtrl then
    compositor.resetAll()
    sched.damageAll()
    return true
  end
  if key == keys.f11 and sched.focus then
    sched.maximize(sched.focus, compositor.primary)
    return true
  end
  if key == keys.f4 and heldAlt and sched.focus then
    sched.kill(sched.focus, "alt+f4")
    return true
  end

  if desktop.powerMenu then
    if key == keys.escape then
      desktop.powerMenu = false
      sched.dirty = true
      return true
    elseif key == keys.up or key == keys.down then
      local n = #POWER_ITEMS
      desktop.powerSelection = ((desktop.powerSelection or 1) +
                                (key == keys.down and 1 or -1) - 1) % n + 1
      sched.dirty = true
      return true
    elseif key == keys.enter then
      desktop.powerAction(POWER_ITEMS[desktop.powerSelection or 1].id)
      return true
    end
  end

  if desktop.overview then
    return desktop.handleOverviewKey(key)
  end

  return false
end

function desktop.handleOverviewKey(key)
  if key == keys.escape then
    desktop.closeOverview()
    return true
  elseif key == keys.backspace then
    desktop.search = desktop.search:sub(1, -2)
    desktop.runSearch()
    sched.dirty = true
    return true
  elseif key == keys.enter then
    if desktop.search ~= "" then
      local item = desktop.searchResults[desktop.searchIndex]
      if item then
        desktop.closeOverview()
        item.action()
      end
    elseif desktop.appGrid then
      local manifest = apps.all()[desktop.gridSelection]
      if manifest then
        desktop.closeOverview()
        apps.launch(manifest.id)
      end
    else
      local wins = visibleWindows()
      local proc = wins[desktop.overviewSelection]
      if proc then
        desktop.closeOverview()
        sched.restore(proc)
      end
    end
    return true
  elseif key == keys.left or key == keys.right or key == keys.up or key == keys.down then
    local delta = (key == keys.right or key == keys.down) and 1 or -1
    if desktop.search ~= "" then
      desktop.searchIndex = util.clamp(desktop.searchIndex + delta, 1,
                                       math.max(1, #desktop.searchResults))
    elseif desktop.appGrid then
      desktop.gridSelection = util.clamp(desktop.gridSelection + delta, 1,
                                         math.max(1, #apps.all()))
    else
      desktop.overviewSelection = util.clamp(desktop.overviewSelection + delta, 1,
                                             math.max(1, #visibleWindows()))
    end
    sched.dirty = true
    return true
  end
  return true    -- the overview swallows everything else
end

------------------------------------------------------------------- mouse ----

function desktop.handleMouse(kind, button, x, y)
  -- active drag takes priority
  if desktop.drag then
    return desktop.handleDrag(kind, x, y)
  end

  if desktop.powerMenu then
    if kind == "mouse_click" then
      for _, rect in ipairs(desktop.powerRects or {}) do
        if x >= rect.x and x < rect.x + rect.w and y == rect.y then
          desktop.powerAction(rect.item.id)
          return true
        end
      end
      desktop.powerMenu = false
      sched.dirty = true
      return true
    end
    return true
  end

  -- top panel
  if y == 1 then
    if kind == "mouse_click" then
      if inRect(desktop.activitiesRect, x, y) then
        desktop.toggleOverview(false)
      elseif desktop.powerRect and x >= desktop.powerRect.x then
        desktop.powerMenu = true
        desktop.powerSelection = 1
        sched.dirty = true
      elseif desktop.statusRect and x >= desktop.statusRect.x then
        apps.launch("settings")
      elseif desktop.clockRect and inRect(desktop.clockRect, x, y) then
        desktop.notify("Aurora", util.dateLine() .. "  \183  " .. util.clock())
      end
    end
    return true
  end

  if desktop.overview then
    return desktop.handleOverviewMouse(kind, button, x, y)
  end

  -- notifications are clickable to dismiss
  if kind == "mouse_click" and #desktop.notifications > 0 and x > compositor.primary.w - 36 then
    local top = 2
    if y >= top and y <= top + 2 then
      table.remove(desktop.notifications, 1)
      sched.dirty = true
      return true
    end
  end

  -- window management
  local proc = sched.topAt(x, y)
  if not proc then
    if kind == "mouse_click" then
      sched.setFocus(nil)
      sched.dirty = true
    end
    return true
  end

  local win = proc.win
  local headerH = win.headerless and 0 or 1

  if kind == "mouse_click" then
    if proc ~= sched.focus then sched.raise(proc) end

    if headerH > 0 and y == win.y then
      local control = compositor.hitControl(win, x, y)
      if control == "close" then
        sched.kill(proc, "close button")
        return true
      elseif control == "max" then
        sched.maximize(proc, compositor.primary)
        return true
      elseif control == "min" then
        sched.minimize(proc)
        return true
      end
      -- double click to maximise, otherwise start a move
      local now = os.clock()
      if win.lastHeaderClick and now - win.lastHeaderClick < 0.4 then
        win.lastHeaderClick = nil
        sched.maximize(proc, compositor.primary)
      else
        win.lastHeaderClick = now
        desktop.drag = { proc = proc, mode = "move", dx = x - win.x, dy = y - win.y }
      end
      return true
    end

    -- resize grip
    if win.resizable ~= false and not win.maximized
       and x == win.x + win.w - 1 and y == win.y + win.h - 1 then
      desktop.drag = { proc = proc, mode = "resize", dx = x - (win.x + win.w - 1),
                       dy = y - (win.y + win.h - 1) }
      return true
    end

    sched.mouseTo(proc, "mouse_click", button, x, y)
    return true

  elseif kind == "mouse_drag" then
    sched.mouseTo(proc, "mouse_drag", button, x, y)
    return true
  elseif kind == "mouse_up" then
    sched.mouseTo(proc, "mouse_up", button, x, y)
    return true
  elseif kind == "mouse_scroll" then
    sched.mouseTo(proc, "mouse_scroll", button, x, y)
    return true
  end
  return true
end

function desktop.handleDrag(kind, x, y)
  local drag = desktop.drag
  local proc = drag.proc
  if proc.dead or not proc.win then
    desktop.drag = nil
    return true
  end
  local win = proc.win
  local d = compositor.primary

  if kind == "mouse_drag" then
    if drag.mode == "move" then
      local nx = util.clamp(x - drag.dx, 2 - win.w, d.w - 1)
      local ny = util.clamp(y - drag.dy, 2, d.h - 1)
      if win.maximized and (math.abs(ny - win.y) > 0 or math.abs(nx - win.x) > 2) then
        -- dragging a maximised window restores it, GNOME style
        sched.maximize(proc, d)
        win.x, win.y = nx, ny
      else
        sched.moveWindow(proc, nx, ny)
      end
    else
      sched.resizeWindow(proc, x - win.x + 1, y - win.y + 1)
      sched.damageAll()
    end
    return true
  elseif kind == "mouse_up" then
    -- snap to the top edge to maximise
    if drag.mode == "move" and y <= 2 and not win.maximized then
      sched.maximize(proc, d)
    end
    desktop.drag = nil
    sched.damageAll()
    return true
  end
  return true
end

function desktop.handleOverviewMouse(kind, button, x, y)
  if kind ~= "mouse_click" then
    if kind == "mouse_scroll" and desktop.appGrid then
      local list = apps.all()
      desktop.gridPage = math.max(1, (desktop.gridPage or 1) + button)
      sched.dirty = true
    end
    return true
  end

  for _, rect in ipairs(desktop.dashRects or {}) do
    if x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h then
      if rect.gridButton then
        desktop.appGrid = not desktop.appGrid
        desktop.search = ""
        sched.dirty = true
      else
        desktop.closeOverview()
        apps.launch(rect.manifest.id)
      end
      return true
    end
  end

  if desktop.search ~= "" then
    for _, rect in ipairs(desktop.resultRects or {}) do
      if x >= rect.x and x < rect.x + rect.w and y == rect.y then
        desktop.closeOverview()
        rect.item.action()
        return true
      end
    end
  elseif desktop.appGrid then
    for _, rect in ipairs(desktop.gridRects or {}) do
      if x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h then
        desktop.closeOverview()
        apps.launch(rect.manifest.id)
        return true
      end
    end
  else
    for _, rect in ipairs(desktop.cardRects or {}) do
      if x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h then
        if x == rect.x + rect.w - 2 and y == rect.y then
          sched.kill(rect.proc, "overview close")
        else
          desktop.closeOverview()
          sched.restore(rect.proc)
        end
        return true
      end
    end
  end

  if desktop.searchRect and y == desktop.searchRect.y then
    return true
  end

  desktop.closeOverview()
  return true
end

------------------------------------------------------------ monitor touch ---

function desktop.handleTouch(name, x, y)
  local target, tx, ty = displaySvc.routeTouch(name, x, y)
  if target == "mirror" then
    -- treat it as a click on the main screen
    desktop.handleMouse("mouse_click", 1, tx, ty)
    desktop.handleMouse("mouse_up", 1, tx, ty)
    return true
  elseif type(target) == "table" then
    sched.resume(target, table.pack("monitor_touch", name, tx, ty))
    return true
  end
  return false
end

return desktop
