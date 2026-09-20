--[[ aurora.gfx.compositor ---------------------------------------------------
     Owns every output device (the computer's own screen plus any attached
     monitors), keeps a Surface per device and pushes only the rows that
     actually changed.  One term.blit per dirty row is the cheapest thing CC
     can do, so a full-screen repaint costs at most 19 calls.
----------------------------------------------------------------------------]]

local util    = arequire("lib.util")
local Surface = arequire("gfx.surface")
local theme   = arequire("gfx.theme")

local compositor = {}

local Display = util.class()
compositor.Display = Display

--- @param output table  a CC terminal object (term.native() or a monitor)
function Display:init(id, output, kind)
  self.id = id
  self.out = output
  self.kind = kind or "screen"     -- "screen" | "monitor"
  self.role = kind == "monitor" and "mirror" or "primary"
  self.dirty = true
  self.cursor = { x = 1, y = 1, blink = false, colour = colours.white }
  self.prev = { t = {}, f = {}, b = {} }
  local w, h = output.getSize()
  self.surface = Surface(w, h, theme.c.desktop, theme.c.text)
  self.w, self.h = w, h
  theme.applyTo(output)
  pcall(output.setCursorBlink, false)
end

function Display:checkSize()
  local ok, w, h = pcall(self.out.getSize)
  if not ok then return false end
  if w ~= self.w or h ~= self.h then
    self.w, self.h = w, h
    self.surface:resize(w, h, theme.c.desktop, theme.c.text)
    self.prev = { t = {}, f = {}, b = {} }
    self.dirty = true
    return true
  end
  return false
end

function Display:invalidate()
  self.dirty = true
end

--- Force the next present() to redraw every row (after a palette change).
function Display:reset()
  self.prev = { t = {}, f = {}, b = {} }
  self.dirty = true
  theme.applyTo(self.out)
end

function Display:present()
  if not self.dirty then return end
  local out, s, prev = self.out, self.surface, self.prev
  local ok = pcall(function()
    local blinkWasOn = false
    for y = 1, s.h do
      local t, f, b = s.t[y], s.f[y], s.b[y]
      if t ~= prev.t[y] or f ~= prev.f[y] or b ~= prev.b[y] then
        out.setCursorPos(1, y)
        out.blit(t, f, b)
        prev.t[y], prev.f[y], prev.b[y] = t, f, b
      end
    end
    local c = self.cursor
    if c.blink then
      out.setTextColour(c.colour)
      out.setCursorPos(c.x, c.y)
      out.setCursorBlink(true)
      blinkWasOn = true
    end
    if not blinkWasOn then out.setCursorBlink(false) end
  end)
  self.dirty = false
  return ok
end

function Display:setCursor(x, y, blink, colour)
  local c = self.cursor
  if c.x ~= x or c.y ~= y or c.blink ~= blink or c.colour ~= colour then
    c.x, c.y, c.blink, c.colour = x, y, blink, colour or c.colour
    self.dirty = true
  end
end

------------------------------------------------------------------ registry --

compositor.displays = {}
compositor.primary = nil

function compositor.init()
  local primary = Display("screen", term.native(), "screen")
  primary.role = "primary"
  compositor.displays = { primary }
  compositor.primary = primary
  return primary
end

function compositor.add(id, output, kind)
  for _, d in ipairs(compositor.displays) do
    if d.id == id then return d end
  end
  local d = Display(id, output, kind)
  compositor.displays[#compositor.displays + 1] = d
  return d
end

function compositor.remove(id)
  for i, d in ipairs(compositor.displays) do
    if d.id == id then table.remove(compositor.displays, i) return d end
  end
end

function compositor.get(id)
  for _, d in ipairs(compositor.displays) do
    if d.id == id then return d end
  end
end

function compositor.presentAll()
  for _, d in ipairs(compositor.displays) do d:present() end
end

function compositor.invalidateAll()
  for _, d in ipairs(compositor.displays) do d:invalidate() end
end

function compositor.resetAll()
  for _, d in ipairs(compositor.displays) do d:reset() end
end

------------------------------------------------------------ window chrome ---

-- Adwaita-style chrome: a soft drop shadow, a header bar with the title and
-- a round close button, rounded outer corners, and a subtle bottom edge.

local CLOSE  = "\215"  -- multiplication sign reads as a tidy X in CC's font
local MAX    = "\254"  -- filled square
local MIN    = "\196"  -- horizontal bar

compositor.buttons = { close = CLOSE, maximize = MAX, minimize = MIN }

--- Sample what is already on the surface so rounded corners blend in.
local function behindColour(surface, x, y, fallback)
  local _, _, bg = surface:getCell(x, y)
  return bg or fallback
end

--- Draw the drop shadow for a window rect (call before drawing the window).
function compositor.drawShadow(surface, x, y, w, h)
  local c = theme.c
  local sx, sy = x + 1, y + 1
  -- right edge
  for row = sy, sy + h - 1 do
    if row >= 1 and row <= surface.h then
      for col = x + w, sx + w - 1 do
        local ch = surface:getCell(col, row)
        if ch then surface:setCell(col, row, " ", c.text, c.shadow) end
      end
    end
  end
  -- bottom edge
  for col = sx, sx + w - 1 do
    local row = y + h
    if row >= 1 and row <= surface.h then
      local ch = surface:getCell(col, row)
      if ch then surface:setCell(col, row, " ", c.text, c.shadow) end
    end
  end
end

--- Full window frame: header bar + client area + rounded corners.
--- Returns the client rectangle (x, y, w, h).
--- @param win table {x,y,w,h,title,icon,focused,maximized,resizable,headerless}
function compositor.drawFrame(surface, win)
  local c = theme.c
  local x, y, w, h = win.x, win.y, win.w, win.h
  if w < 4 or h < 2 then return x, y, w, h end

  local focused = win.focused
  local headerBg = focused and c.header or c.headerIdle
  local titleFg = focused and c.text or c.dim
  local headerH = win.headerless and 0 or 1

  -- Remember what is behind the four corners before we paint over them.
  local tl = behindColour(surface, x, y, c.desktop)
  local tr = behindColour(surface, x + w - 1, y, c.desktop)
  local bl = behindColour(surface, x, y + h - 1, c.desktop)
  local br = behindColour(surface, x + w - 1, y + h - 1, c.desktop)

  if headerH > 0 then
    surface:fill(x, y, w, 1, " ", titleFg, headerBg)

    -- icon + title, left aligned like a GNOME HeaderBar with a start widget
    local cursor = x + 1
    if win.iconChar then
      surface:write(cursor, y, win.iconChar, win.iconColour or c.accent, headerBg)
      cursor = cursor + #win.iconChar + 1
    end

    -- One control, like GNOME.  Minimise and maximise live in the window menu
    -- (click the title, or double-click it to maximise), which keeps three
    -- glyphs and four cells of clutter off every single window.
    local ctrlW = 2
    win.controlRects = {}
    local cx = x + w - ctrlW
    local closeFg = win.hoverControl == "close" and c.destructive or titleFg
    surface:write(cx, y, CLOSE, closeFg, headerBg)
    win.controlRects[1] = { kind = "close", x = cx, y = y }

    local avail = (x + w - ctrlW - 1) - cursor
    if avail > 2 then
      local title = util.ellipsis(win.title or "", avail)
      -- centre the title when there is room, otherwise left-align
      local tx = x + math.floor((w - #title) / 2)
      if tx < cursor then tx = cursor end
      if tx + #title > x + w - ctrlW - 1 then tx = cursor end
      surface:write(tx, y, title, titleFg, headerBg)
    end
  end

  local clientY = y + headerH
  local clientH = h - headerH
  if clientH > 0 then
    surface:fill(x, clientY, w, clientH, " ", c.text, c.window)
  end

  -- rounded outer corners (skipped when maximised -- GNOME does the same)
  if not win.maximized then
    if headerH > 0 then
      surface:roundCorner(x, y, "tl", headerBg, tl)
      surface:roundCorner(x + w - 1, y, "tr", headerBg, tr)
    else
      surface:roundCorner(x, y, "tl", c.window, tl)
      surface:roundCorner(x + w - 1, y, "tr", c.window, tr)
    end
    if clientH > 0 then
      surface:roundCorner(x, y + h - 1, "bl", c.window, bl)
      surface:roundCorner(x + w - 1, y + h - 1, "br", c.window, br)
    end
  end

  return x, clientY, w, clientH
end

--- Hit test the header controls.
function compositor.hitControl(win, x, y)
  for _, r in ipairs(win.controlRects or {}) do
    if r.x == x and r.y == y then return r.kind end
  end
  return nil
end

return compositor
