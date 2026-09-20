--[[ aurora.shell.wallpaper --------------------------------------------------
     Wallpapers are rendered once into a Surface and reused until the theme,
     the style or the screen size changes.  Ordered (Bayer) dithering between
     palette colours buys a surprising amount of gradient out of 16 colours.
----------------------------------------------------------------------------]]

local util    = arequire("lib.util")
local theme   = arequire("gfx.theme")
local pixel   = arequire("gfx.pixel")
local Surface = arequire("gfx.surface")

local wallpaper = {}

local BAYER = {
  { 0, 8, 2, 10 },
  { 12, 4, 14, 6 },
  { 3, 11, 1, 9 },
  { 15, 7, 13, 5 },
}

local function dither(x, y, t)
  local threshold = (BAYER[(y - 1) % 4 + 1][(x - 1) % 4 + 1] + 0.5) / 16
  return t > threshold
end

--- Interpolate through a list of {position, colour} stops with dithering.
local function rampColour(stops, t, x, y)
  for i = 1, #stops - 1 do
    local a, b = stops[i], stops[i + 1]
    if t >= a[1] and t <= b[1] then
      local span = b[1] - a[1]
      local local_t = span > 0 and (t - a[1]) / span or 0
      return dither(x, y, local_t) and b[2] or a[2]
    end
  end
  return stops[#stops][2]
end

wallpaper.styles = {
  { id = "aurora",    name = "Aurora" },
  { id = "twilight",  name = "Twilight" },
  { id = "blueprint", name = "Blueprint" },
  { id = "solid",     name = "Solid" },
  { id = "mountains", name = "Mountains" },
}

---------------------------------------------------------------- renderers ---

local function drawAurora(canvas, w, h)
  local p = theme.wallpaper
  local stops = { { 0, p.top }, { 0.55, p.mid }, { 1, p.bottom } }
  for y = 1, h do
    local t = (y - 1) / math.max(1, h - 1)
    for x = 1, w do
      canvas:set(x, y, rampColour(stops, t, x, y))
    end
  end

  -- two soft ribbons of light sweeping across the upper half
  for band = 1, 2 do
    local amplitude = h * (band == 1 and 0.10 or 0.07)
    local centre = h * (band == 1 and 0.30 or 0.46)
    local period = w / (band == 1 and 1.6 or 2.4)
    local thickness = math.max(2, math.floor(h * 0.09))
    local colour = band == 1 and p.aurora or theme.c.accent
    for x = 1, w do
      local baseY = centre + math.sin((x / period) * math.pi * 2 + band) * amplitude
      for k = 0, thickness do
        local y = math.floor(baseY + k)
        local fade = 1 - (k / thickness)
        if dither(x, y, fade * 0.85) then canvas:set(x, y, colour) end
      end
    end
  end
end

local function drawTwilight(canvas, w, h)
  local c = theme.c
  local stops = { { 0, theme.wallpaper.bottom }, { 0.6, theme.wallpaper.mid }, { 1, theme.wallpaper.top } }
  for y = 1, h do
    local t = (y - 1) / math.max(1, h - 1)
    for x = 1, w do canvas:set(x, y, rampColour(stops, t, x, y)) end
  end
  -- a low sun
  local cx, cy = math.floor(w * 0.72), math.floor(h * 0.62)
  canvas:circle(cx, cy, math.floor(h * 0.18), c.warning, true)
end

local function drawBlueprint(canvas, w, h)
  local c = theme.c
  canvas:rect(1, 1, w, h, theme.wallpaper.bottom)
  for x = 1, w, 8 do canvas:vline(x, 1, h, theme.wallpaper.mid) end
  for y = 1, h, 6 do canvas:hline(1, y, w, theme.wallpaper.mid) end
  for x = 1, w, 24 do canvas:vline(x, 1, h, c.accent) end
  for y = 1, h, 18 do canvas:hline(1, y, w, c.accent) end
end

local function drawSolid(canvas, w, h)
  canvas:rect(1, 1, w, h, theme.c.desktop)
end

local function drawMountains(canvas, w, h)
  local p = theme.wallpaper
  local stops = { { 0, p.top }, { 1, p.mid } }
  for y = 1, h do
    local t = (y - 1) / math.max(1, h - 1)
    for x = 1, w do canvas:set(x, y, rampColour(stops, t, x, y)) end
  end
  local ranges = {
    { base = 0.62, amp = 0.16, period = 1.1, colour = theme.c.accent },
    { base = 0.76, amp = 0.13, period = 0.7, colour = p.bottom },
  }
  for _, range in ipairs(ranges) do
    for x = 1, w do
      local peak = h * range.base
                   - math.abs(math.sin(x / (w / (range.period * 3)) * math.pi)) * h * range.amp
      for y = math.floor(peak), h do canvas:set(x, y, range.colour) end
    end
  end
end

local RENDERERS = {
  aurora = drawAurora,
  twilight = drawTwilight,
  blueprint = drawBlueprint,
  solid = drawSolid,
  mountains = drawMountains,
}

------------------------------------------------------------------ public ----

wallpaper.cache = {}

--- Get (and build if needed) a wallpaper Surface for a display size.
function wallpaper.get(w, h, style)
  style = style or theme.wallpaperStyle or "aurora"
  local key = ("%s:%d:%d:%s:%s"):format(style, w, h, theme.current.id, theme.accent)
  if wallpaper.cache.key == key then return wallpaper.cache.surface end

  local surface = Surface(w, h, theme.c.desktop, theme.c.text)
  local canvas = pixel.Canvas(w, h, theme.c.desktop)
  local renderer = RENDERERS[style] or drawAurora
  renderer(canvas, canvas.w, canvas.h)
  canvas:render(surface, 1, 1)

  wallpaper.cache = { key = key, surface = surface }
  return surface
end

function wallpaper.invalidate()
  wallpaper.cache = {}
end

return wallpaper
