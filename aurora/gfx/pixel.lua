--[[ aurora.gfx.pixel --------------------------------------------------------
     Sub-pixel drawing.  CC's font contains 32 "teletext" glyphs (128-159) that
     divide a character cell into a 2x3 grid, so a 51x19 terminal is really a
     102x57 pixel display.  Aurora uses that for the boot logo, the wallpaper,
     app icons and the chart widget.

     Encoding: a cell shows at most two colours.  We take the bottom-right
     sub-pixel's colour as the background and set one bit per sub-pixel that
     differs from it:  tl=1 tr=2 ml=4 mr=8 bl=16, char = 128 + bits.
----------------------------------------------------------------------------]]

local util = arequire("lib.util")
local Surface = arequire("gfx.surface")

local pixel = {}

------------------------------------------------------------ pixel canvas ----

local Canvas = util.class()
pixel.Canvas = Canvas

--- @param cw number  width in character cells
--- @param ch number  height in character cells
function Canvas:init(cw, ch, fill)
  self.cw, self.ch = cw, ch
  self.w, self.h = cw * 2, ch * 3
  self.px = {}
  self:clear(fill or colours.black)
end

function Canvas:clear(colour)
  for y = 1, self.h do
    local row = {}
    for x = 1, self.w do row[x] = colour end
    self.px[y] = row
  end
end

function Canvas:set(x, y, colour)
  x, y = math.floor(x), math.floor(y)
  if x < 1 or y < 1 or x > self.w or y > self.h then return end
  self.px[y][x] = colour
end

function Canvas:get(x, y)
  if x < 1 or y < 1 or x > self.w or y > self.h then return nil end
  return self.px[y][x]
end

function Canvas:rect(x, y, w, h, colour)
  for row = y, y + h - 1 do
    for col = x, x + w - 1 do self:set(col, row, colour) end
  end
end

function Canvas:hline(x, y, w, colour)
  for col = x, x + w - 1 do self:set(col, y, colour) end
end

function Canvas:vline(x, y, h, colour)
  for row = y, y + h - 1 do self:set(x, row, colour) end
end

function Canvas:line(x1, y1, x2, y2, colour)
  x1, y1, x2, y2 = math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2)
  local dx, dy = math.abs(x2 - x1), -math.abs(y2 - y1)
  local sx = x1 < x2 and 1 or -1
  local sy = y1 < y2 and 1 or -1
  local err = dx + dy
  while true do
    self:set(x1, y1, colour)
    if x1 == x2 and y1 == y2 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x1 = x1 + sx end
    if e2 <= dx then err = err + dx; y1 = y1 + sy end
  end
end

--- Rounded rectangle -- the shape behind every app icon.
function Canvas:roundRect(x, y, w, h, colour, radius)
  radius = radius or 2
  for row = 0, h - 1 do
    local inset = 0
    if row < radius then inset = radius - row - 1 end
    if row >= h - radius then inset = radius - (h - row) end
    if inset < 0 then inset = 0 end
    self:hline(x + inset, y + row, w - inset * 2, colour)
  end
end

function Canvas:circle(cx, cy, r, colour, filled)
  for y = -r, r do
    for x = -r, r do
      local d = x * x + y * y
      if (filled and d <= r * r) or (not filled and d <= r * r and d > (r - 1) * (r - 1)) then
        self:set(cx + x, cy + y, colour)
      end
    end
  end
end

---------------------------------------------------------------- 5x7 font ----

-- Column-major bitmaps, LSB = top row.  Used for the boot logo, the lock
-- screen clock and Slides headings.
local FONT = {
  [" "] = { 0x00, 0x00, 0x00, 0x00, 0x00 },
  ["-"] = { 0x08, 0x08, 0x08, 0x08, 0x08 },
  ["."] = { 0x00, 0x60, 0x60, 0x00, 0x00 },
  [":"] = { 0x00, 0x36, 0x36, 0x00, 0x00 },
  ["/"] = { 0x20, 0x10, 0x08, 0x04, 0x02 },
  ["!"] = { 0x00, 0x00, 0x5F, 0x00, 0x00 },
  ["?"] = { 0x02, 0x01, 0x59, 0x09, 0x06 },
  ["0"] = { 0x3E, 0x51, 0x49, 0x45, 0x3E },
  ["1"] = { 0x00, 0x42, 0x7F, 0x40, 0x00 },
  ["2"] = { 0x42, 0x61, 0x51, 0x49, 0x46 },
  ["3"] = { 0x21, 0x41, 0x45, 0x4B, 0x31 },
  ["4"] = { 0x18, 0x14, 0x12, 0x7F, 0x10 },
  ["5"] = { 0x27, 0x45, 0x45, 0x45, 0x39 },
  ["6"] = { 0x3C, 0x4A, 0x49, 0x49, 0x30 },
  ["7"] = { 0x01, 0x71, 0x09, 0x05, 0x03 },
  ["8"] = { 0x36, 0x49, 0x49, 0x49, 0x36 },
  ["9"] = { 0x06, 0x49, 0x49, 0x29, 0x1E },
  ["A"] = { 0x7E, 0x11, 0x11, 0x11, 0x7E },
  ["B"] = { 0x7F, 0x49, 0x49, 0x49, 0x36 },
  ["C"] = { 0x3E, 0x41, 0x41, 0x41, 0x22 },
  ["D"] = { 0x7F, 0x41, 0x41, 0x22, 0x1C },
  ["E"] = { 0x7F, 0x49, 0x49, 0x49, 0x41 },
  ["F"] = { 0x7F, 0x09, 0x09, 0x09, 0x01 },
  ["G"] = { 0x3E, 0x41, 0x49, 0x49, 0x7A },
  ["H"] = { 0x7F, 0x08, 0x08, 0x08, 0x7F },
  ["I"] = { 0x00, 0x41, 0x7F, 0x41, 0x00 },
  ["J"] = { 0x20, 0x40, 0x41, 0x3F, 0x01 },
  ["K"] = { 0x7F, 0x08, 0x14, 0x22, 0x41 },
  ["L"] = { 0x7F, 0x40, 0x40, 0x40, 0x40 },
  ["M"] = { 0x7F, 0x02, 0x0C, 0x02, 0x7F },
  ["N"] = { 0x7F, 0x04, 0x08, 0x10, 0x7F },
  ["O"] = { 0x3E, 0x41, 0x41, 0x41, 0x3E },
  ["P"] = { 0x7F, 0x09, 0x09, 0x09, 0x06 },
  ["Q"] = { 0x3E, 0x41, 0x51, 0x21, 0x5E },
  ["R"] = { 0x7F, 0x09, 0x19, 0x29, 0x46 },
  ["S"] = { 0x46, 0x49, 0x49, 0x49, 0x31 },
  ["T"] = { 0x01, 0x01, 0x7F, 0x01, 0x01 },
  ["U"] = { 0x3F, 0x40, 0x40, 0x40, 0x3F },
  ["V"] = { 0x1F, 0x20, 0x40, 0x20, 0x1F },
  ["W"] = { 0x3F, 0x40, 0x38, 0x40, 0x3F },
  ["X"] = { 0x63, 0x14, 0x08, 0x14, 0x63 },
  ["Y"] = { 0x07, 0x08, 0x70, 0x08, 0x07 },
  ["Z"] = { 0x61, 0x51, 0x49, 0x45, 0x43 },
}
pixel.font = FONT

function pixel.textWidth(text, spacing)
  spacing = spacing or 1
  return #tostring(text) * (5 + spacing) - spacing
end

--- Draw 5x7 bitmap text onto the canvas.
function Canvas:text(x, y, text, colour, spacing)
  spacing = spacing or 1
  local cursor = x
  for i = 1, #text do
    local glyph = FONT[text:sub(i, i):upper()]
    if glyph then
      for col = 1, 5 do
        local bits = glyph[col]
        for row = 0, 6 do
          if math.floor(bits / 2 ^ row) % 2 == 1 then
            self:set(cursor + col - 1, y + row, colour)
          end
        end
      end
    end
    cursor = cursor + 5 + spacing
  end
  return cursor - spacing - x
end

------------------------------------------------------------- cell encode ----

local BIT = { 1, 2, 4, 8, 16 }  -- tl tr ml mr bl (br is the background)

--- Convert the canvas into character cells and draw onto a Surface.
--- Pixels equal to `transparent` keep whatever is already on the surface.
function Canvas:render(surface, cx, cy, transparent)
  local counts = {}
  for cellY = 0, self.ch - 1 do
    local text, fgs, bgs = {}, {}, {}
    local py = cellY * 3 + 1
    for cellX = 0, self.cw - 1 do
      local px = cellX * 2 + 1
      local p = {
        self.px[py][px],         self.px[py][px + 1],
        self.px[py + 1][px],     self.px[py + 1][px + 1],
        self.px[py + 2][px],     self.px[py + 2][px + 1],
      }

      local skip = false
      if transparent then
        skip = true
        for i = 1, 6 do if p[i] ~= transparent then skip = false break end end
      end

      if skip then
        local ch, f, b = surface:getCell(cx + cellX, cy + cellY)
        text[#text + 1] = ch or " "
        fgs[#fgs + 1] = Surface.blitChar(f or colours.white)
        bgs[#bgs + 1] = Surface.blitChar(b or colours.black)
      else
        -- Substitute the surface colour for transparent sub-pixels.
        if transparent then
          local _, _, behind = surface:getCell(cx + cellX, cy + cellY)
          behind = behind or colours.black
          for i = 1, 6 do if p[i] == transparent then p[i] = behind end end
        end

        for k in pairs(counts) do counts[k] = nil end
        for i = 1, 6 do counts[p[i]] = (counts[p[i]] or 0) + 1 end

        local bg = p[6]
        local fg, best = bg, -1
        for colour, n in pairs(counts) do
          if colour ~= bg and n > best then fg, best = colour, n end
        end

        local bits = 0
        for i = 1, 5 do
          if p[i] ~= bg then bits = bits + BIT[i] end
        end

        text[#text + 1] = string.char(128 + bits)
        fgs[#fgs + 1] = Surface.blitChar(fg)
        bgs[#bgs + 1] = Surface.blitChar(bg)
      end
    end
    surface:blit(cx, cy + cellY, table.concat(text), table.concat(fgs), table.concat(bgs))
  end
end

------------------------------------------------------------------ icons -----

-- App icons are a rounded squircle in the app's colour with a small glyph.
-- `glyph` is either a text string (drawn with the 5x7 font) or a bitmap of
-- rows of "." / "#" for pixel art.

pixel.iconCache = {}

local function parseBitmap(rows)
  local pts = {}
  for y = 1, #rows do
    local row = rows[y]
    for x = 1, #row do
      local c = row:sub(x, x)
      if c ~= "." and c ~= " " then pts[#pts + 1] = { x = x, y = y, c = c } end
    end
  end
  return pts, #rows[1], #rows
end

--- Draw an app icon.  Size is in cells: 6x3 (large) or 4x2 (small).
--- @param icon table {colour=, glyph=, art={...}, accent=}
pixel.TRANSPARENT = -1

function pixel.drawIcon(surface, x, y, icon, cellW, cellH, behind)
  cellW = cellW or 6
  cellH = cellH or 3
  local canvas = Canvas(cellW, cellH, behind or pixel.TRANSPARENT)
  local w, h = canvas.w, canvas.h
  local base = icon.colour or colours.blue
  canvas:roundRect(1, 1, w, h, base, cellH >= 3 and 2 or 1)

  local fg = icon.glyphColour or colours.white
  if icon.art then
    local pts, aw, ah = parseBitmap(icon.art)
    local ox = math.floor((w - aw) / 2)
    local oy = math.floor((h - ah) / 2)
    for _, p in ipairs(pts) do
      canvas:set(ox + p.x, oy + p.y, p.c == "+" and (icon.accent or fg) or fg)
    end
  elseif icon.glyph then
    local tw = pixel.textWidth(icon.glyph)
    canvas:text(math.floor((w - tw) / 2) + 1, math.floor((h - 7) / 2) + 1, icon.glyph, fg)
  end

  canvas:render(surface, x, y, behind and nil or pixel.TRANSPARENT)
  return cellW, cellH
end

--- Big centred logo text, returns the cell height used.
function pixel.logo(surface, cx, cy, cellW, text, colour, bg)
  local canvas = Canvas(cellW, 3, bg or colours.black)
  local tw = pixel.textWidth(text)
  canvas:text(math.floor((canvas.w - tw) / 2) + 1, 2, text, colour)
  canvas:render(surface, cx, cy)
  return 3
end

return pixel
