--[[ aurora.gfx.surface ------------------------------------------------------
     A Surface is an off-screen character buffer: three parallel arrays of
     strings (text / foreground / background) exactly like CC's own terminal
     rows.  Keeping rows as strings means compositing is a handful of
     string.sub concatenations and presenting a row is a single term.blit.
----------------------------------------------------------------------------]]

local util = arequire("lib.util")

local Surface = util.class()

local HEX = "0123456789abcdef"

-- colour value (1,2,4,8,...) -> blit character
local toBlit = {}
-- blit character -> colour value
local fromBlit = {}
for i = 0, 15 do
  local ch = HEX:sub(i + 1, i + 1)
  toBlit[2 ^ i] = ch
  fromBlit[ch] = 2 ^ i
end

Surface.toBlit = toBlit
Surface.fromBlit = fromBlit

local function blitChar(colour)
  return toBlit[colour] or "0"
end
Surface.blitChar = blitChar

-- Runs of one repeated character are by far the most allocated strings in the
-- system: every coloured write builds two of them, and a full-screen repaint
-- builds hundreds.  They are tiny and highly repetitive, so memoising them
-- turns most draws into table lookups.
local runCache = {}
local RUN_CACHE_MAX = 64

local function run(char, n)
  if n <= 0 then return "" end
  if n > RUN_CACHE_MAX then return string.rep(char, n) end
  local byLength = runCache[char]
  if not byLength then
    byLength = {}
    runCache[char] = byLength
  end
  local cached = byLength[n]
  if not cached then
    cached = string.rep(char, n)
    byLength[n] = cached
  end
  return cached
end
Surface.run = run

function Surface:init(w, h, bg, fg, char)
  self.w = math.max(0, math.floor(w or 0))
  self.h = math.max(0, math.floor(h or 0))
  self.t, self.f, self.b = {}, {}, {}
  self:clear(bg or colours.black, fg or colours.white, char or " ")
end

function Surface:clear(bg, fg, char)
  local line = run(char or " ", self.w)
  local fl = run(blitChar(fg or colours.white), self.w)
  local bl = run(blitChar(bg or colours.black), self.w)
  for y = 1, self.h do
    self.t[y], self.f[y], self.b[y] = line, fl, bl
  end
  for y = self.h + 1, #self.t do
    self.t[y], self.f[y], self.b[y] = nil, nil, nil
  end
end

function Surface:resize(w, h, bg, fg)
  w, h = math.max(0, math.floor(w)), math.max(0, math.floor(h))
  if w == self.w and h == self.h then return false end
  local blank = string.rep(" ", w)
  local fl = string.rep(blitChar(fg or colours.white), w)
  local bl = string.rep(blitChar(bg or colours.black), w)
  for y = 1, h do
    if self.t[y] then
      if w > self.w then
        self.t[y] = self.t[y] .. blank:sub(1, w - self.w)
        self.f[y] = self.f[y] .. fl:sub(1, w - self.w)
        self.b[y] = self.b[y] .. bl:sub(1, w - self.w)
      elseif w < self.w then
        self.t[y] = self.t[y]:sub(1, w)
        self.f[y] = self.f[y]:sub(1, w)
        self.b[y] = self.b[y]:sub(1, w)
      end
    else
      self.t[y], self.f[y], self.b[y] = blank, fl, bl
    end
  end
  for y = h + 1, #self.t do
    self.t[y], self.f[y], self.b[y] = nil, nil, nil
  end
  self.w, self.h = w, h
  return true
end

function Surface:inBounds(x, y)
  return x >= 1 and y >= 1 and x <= self.w and y <= self.h
end

--- Clipping -----------------------------------------------------------------
-- Scrolled views push a clip rect so their children cannot paint over the
-- rest of the window.  Clips nest; each push intersects with the current one.

function Surface:pushClip(x, y, w, h)
  self.clipStack = self.clipStack or {}
  local current = self.clip
  local rect = { x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1 }
  if current then
    rect.x1 = math.max(rect.x1, current.x1)
    rect.y1 = math.max(rect.y1, current.y1)
    rect.x2 = math.min(rect.x2, current.x2)
    rect.y2 = math.min(rect.y2, current.y2)
  end
  self.clipStack[#self.clipStack + 1] = current
  self.clip = rect
end

function Surface:popClip()
  if not self.clipStack or #self.clipStack == 0 then
    self.clip = nil
    return
  end
  self.clip = self.clipStack[#self.clipStack]
  table.remove(self.clipStack)
end

function Surface:resetClip()
  self.clip = nil
  self.clipStack = {}
end

--- Raw blit of pre-built text/fg/bg strings, clipped to the surface.
function Surface:blit(x, y, text, fg, bg)
  y = math.floor(y)
  if y < 1 or y > self.h then return end
  x = math.floor(x)
  local len = #text
  if len == 0 then return end

  local clip = self.clip
  if clip then
    if y < clip.y1 or y > clip.y2 then return end
    if x < clip.x1 then
      local cut = clip.x1 - x + 1
      if cut > len then return end
      text, fg, bg = text:sub(cut), fg:sub(cut), bg:sub(cut)
      len = #text
      x = clip.x1
    end
    if x + len - 1 > clip.x2 then
      local keep = clip.x2 - x + 1
      if keep <= 0 then return end
      text, fg, bg = text:sub(1, keep), fg:sub(1, keep), bg:sub(1, keep)
      len = keep
    end
  end

  if x < 1 then
    local cut = 2 - x
    if cut > len then return end
    text, fg, bg = text:sub(cut), fg:sub(cut), bg:sub(cut)
    len = #text
    x = 1
  end
  if x + len - 1 > self.w then
    local keep = self.w - x + 1
    if keep <= 0 then return end
    text, fg, bg = text:sub(1, keep), fg:sub(1, keep), bg:sub(1, keep)
    len = keep
  end
  -- Fast path: a write that covers the whole row replaces it outright,
  -- which is what compositing a full-width window or the wallpaper does.
  if x == 1 and len == self.w then
    self.t[y], self.f[y], self.b[y] = text, fg, bg
    return
  end

  local row = self.t[y]
  self.t[y] = row:sub(1, x - 1) .. text .. row:sub(x + len)
  row = self.f[y]
  self.f[y] = row:sub(1, x - 1) .. fg .. row:sub(x + len)
  row = self.b[y]
  self.b[y] = row:sub(1, x - 1) .. bg .. row:sub(x + len)
end

--- Write text with uniform colours.
function Surface:write(x, y, text, fg, bg)
  text = tostring(text)
  local len = #text
  if len == 0 then return end
  self:blit(x, y, text, run(blitChar(fg), len), run(blitChar(bg), len))
end

function Surface:fill(x, y, w, h, char, fg, bg)
  if w <= 0 or h <= 0 then return end
  local text = run(char or " ", w)
  local fl = run(blitChar(fg), w)
  local bl = run(blitChar(bg), w)
  for row = y, y + h - 1 do
    self:blit(x, row, text, fl, bl)
  end
end

--- One-cell outline drawn with CP437 box characters.
function Surface:frame(x, y, w, h, fg, bg)
  if w < 2 or h < 2 then return end
  local top = "\218" .. string.rep("\196", w - 2) .. "\191"
  local bottom = "\192" .. string.rep("\196", w - 2) .. "\217"
  self:write(x, y, top, fg, bg)
  self:write(x, y + h - 1, bottom, fg, bg)
  for row = y + 1, y + h - 2 do
    self:write(x, row, "\179", fg, bg)
    self:write(x + w - 1, row, "\179", fg, bg)
  end
end

function Surface:hline(x, y, w, fg, bg, char)
  self:write(x, y, string.rep(char or "\196", w), fg, bg)
end

--- Text helpers -------------------------------------------------------------

function Surface:writeCentered(y, text, fg, bg, x, w)
  x = x or 1
  w = w or self.w
  text = util.ellipsis(tostring(text), w)
  self:write(x + math.floor((w - #text) / 2), y, text, fg, bg)
end

function Surface:writeRight(x, y, text, fg, bg, w)
  text = tostring(text)
  self:write(x + (w or 0) - #text, y, text, fg, bg)
end

--- Cell access --------------------------------------------------------------

function Surface:getCell(x, y)
  if not self:inBounds(x, y) then return nil end
  return self.t[y]:sub(x, x), fromBlit[self.f[y]:sub(x, x)], fromBlit[self.b[y]:sub(x, x)]
end

function Surface:setCell(x, y, char, fg, bg)
  if not self:inBounds(x, y) then return end
  self:blit(x, y, char, blitChar(fg), blitChar(bg))
end

--- Compositing --------------------------------------------------------------

--- Draw another surface onto this one at (dx, dy).
function Surface:draw(src, dx, dy, sx, sy, sw, sh)
  sx, sy = sx or 1, sy or 1
  sw = sw or src.w
  sh = sh or src.h
  for row = 0, sh - 1 do
    local srcY = sy + row
    if srcY >= 1 and srcY <= src.h then
      self:blit(dx, dy + row,
        src.t[srcY]:sub(sx, sx + sw - 1),
        src.f[srcY]:sub(sx, sx + sw - 1),
        src.b[srcY]:sub(sx, sx + sw - 1))
    end
  end
end

--- Darken a rectangle: used by the Activities overview + modal dialogs.
--- Cells keep their text but are redrawn in the "scrim" colours.
function Surface:scrim(x, y, w, h, fg, bg)
  for row = y, y + h - 1 do
    if row >= 1 and row <= self.h then
      local x1 = math.max(1, x)
      local x2 = math.min(self.w, x + w - 1)
      if x2 >= x1 then
        local n = x2 - x1 + 1
        local text = self.t[row]:sub(x1, x2)
        -- Blank out block glyphs so the scrim reads evenly.
        text = text:gsub("[\128-\159\176-\223]", " ")
        self:blit(x1, row, text, run(blitChar(fg), n), run(blitChar(bg), n))
      end
    end
  end
end

--- Scroll the whole surface by n rows (positive = content moves up).
function Surface:scroll(n, bg, fg)
  if n == 0 then return end
  local blank = run(" ", self.w)
  local fl = run(blitChar(fg or colours.white), self.w)
  local bl = run(blitChar(bg or colours.black), self.w)
  if n > 0 then
    for y = 1, self.h do
      local from = y + n
      if from <= self.h then
        self.t[y], self.f[y], self.b[y] = self.t[from], self.f[from], self.b[from]
      else
        self.t[y], self.f[y], self.b[y] = blank, fl, bl
      end
    end
  else
    for y = self.h, 1, -1 do
      local from = y + n
      if from >= 1 then
        self.t[y], self.f[y], self.b[y] = self.t[from], self.f[from], self.b[from]
      else
        self.t[y], self.f[y], self.b[y] = blank, fl, bl
      end
    end
  end
end

function Surface:clearLine(y, bg, fg)
  if y < 1 or y > self.h then return end
  self.t[y] = run(" ", self.w)
  self.f[y] = run(blitChar(fg or colours.white), self.w)
  self.b[y] = run(blitChar(bg or colours.black), self.w)
end

--- Rounded corners ----------------------------------------------------------
-- CC's teletext glyphs (128-159) encode a 2x3 sub-pixel grid.  Knocking a
-- single sub-pixel out of each corner reads as a soft rounded edge, which is
-- what gives Aurora windows their Adwaita silhouette.
--   bits: tl=1 tr=2 ml=4 mr=8 bl=16  (br handled by swapping fg/bg)

local CORNER = {
  tl = { char = string.char(128 + 1),  swap = false },
  tr = { char = string.char(128 + 2),  swap = false },
  bl = { char = string.char(128 + 16), swap = false },
  br = { char = string.char(128 + 31), swap = true  },
}

--- Round one corner cell.  `inner` is the window colour, `outer` what shows
--- through the notch (read from whatever has already been composited).
function Surface:roundCorner(x, y, which, inner, outer)
  local def = CORNER[which]
  if not def or not self:inBounds(x, y) then return end
  if def.swap then
    self:blit(x, y, def.char, blitChar(inner), blitChar(outer))
  else
    self:blit(x, y, def.char, blitChar(outer), blitChar(inner))
  end
end

--- Round all four corners of a rect, sampling the colours currently behind it.
function Surface:roundRect(x, y, w, h, inner, outerTL, outerTR, outerBL, outerBR)
  self:roundCorner(x, y, "tl", inner, outerTL)
  self:roundCorner(x + w - 1, y, "tr", inner, outerTR or outerTL)
  self:roundCorner(x, y + h - 1, "bl", inner, outerBL or outerTL)
  self:roundCorner(x + w - 1, y + h - 1, "br", inner, outerBR or outerTL)
end

--- Pills --------------------------------------------------------------------
-- A one-row control with both corners notched on each end reads as a rounded
-- pill -- the shape of every Adwaita button.  Costs one cell per end cap.

local CAP_LEFT  = string.char(128 + 1 + 16)   -- tl + bl knocked out
local CAP_RIGHT = string.char(128 + 29)       -- tr + br knocked out (inverted)

function Surface:capLeft(x, y, inner, outer)
  self:blit(x, y, CAP_LEFT, blitChar(outer), blitChar(inner))
end

function Surface:capRight(x, y, inner, outer)
  self:blit(x, y, CAP_RIGHT, blitChar(inner), blitChar(outer))
end

--- Fill a one-row pill and return the inner text rect (x, width).
function Surface:pill(x, y, w, inner, outer)
  if w <= 0 then return x, 0 end
  if w <= 2 then
    self:fill(x, y, w, 1, " ", inner, inner)
    return x, w
  end
  -- Sample what is behind the caps *before* painting over it.
  local behindL = outer or select(3, self:getCell(x, y))
  local behindR = outer or select(3, self:getCell(x + w - 1, y))
  self:fill(x, y, w, 1, " ", inner, inner)
  self:capLeft(x, y, inner, behindL)
  self:capRight(x + w - 1, y, inner, behindR)
  return x + 1, w - 2
end

--- Snapshot / restore (used for popovers and menus) -------------------------

function Surface:snapshot(x, y, w, h)
  local snap = { x = x, y = y, w = w, h = h, t = {}, f = {}, b = {} }
  for row = 1, h do
    local sy = y + row - 1
    if sy >= 1 and sy <= self.h then
      snap.t[row] = self.t[sy]:sub(x, x + w - 1)
      snap.f[row] = self.f[sy]:sub(x, x + w - 1)
      snap.b[row] = self.b[sy]:sub(x, x + w - 1)
    end
  end
  return snap
end

function Surface:restore(snap)
  for row = 1, snap.h do
    if snap.t[row] then
      self:blit(snap.x, snap.y + row - 1, snap.t[row], snap.f[row], snap.b[row])
    end
  end
end

return Surface
