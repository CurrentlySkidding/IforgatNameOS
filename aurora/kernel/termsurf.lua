--[[ aurora.kernel.termsurf -------------------------------------------------
     A complete CC terminal implementation backed by an Aurora Surface.

     This is what lets Aurora run *unmodified* CraftOS programs -- the shell,
     edit, worm, anything on the ROM -- inside a desktop window.  The kernel
     term.redirect()s to one of these before resuming a process, so the global
     `term` API inside that process writes into its window instead of the
     screen.
----------------------------------------------------------------------------]]

local Surface = arequire("gfx.surface")
local theme   = arequire("gfx.theme")

local termsurf = {}

--- @param surface Surface  the window's client buffer
--- @param onDamage function called whenever the buffer changes
function termsurf.create(surface, onDamage)
  local cx, cy = 1, 1
  local fg, bg = theme.c.text, theme.c.window
  local blink = false
  local palette = {}

  local t = {}

  local function damage()
    if onDamage then onDamage() end
  end

  function t.write(text)
    text = tostring(text)
    if #text == 0 then return end
    surface:write(cx, cy, text, fg, bg)
    cx = cx + #text
    damage()
  end

  function t.blit(text, textColour, backColour)
    if #text ~= #textColour or #text ~= #backColour then
      error("Arguments must be the same length", 2)
    end
    surface:blit(cx, cy, text, textColour, backColour)
    cx = cx + #text
    damage()
  end

  function t.clear()
    surface:clear(bg, fg, " ")
    damage()
  end

  function t.clearLine()
    surface:clearLine(cy, bg, fg)
    damage()
  end

  function t.getCursorPos() return cx, cy end

  function t.setCursorPos(x, y)
    cx, cy = math.floor(tonumber(x) or 1), math.floor(tonumber(y) or 1)
    damage()
  end

  function t.setCursorBlink(value)
    blink = value and true or false
    damage()
  end

  function t.getCursorBlink() return blink end

  function t.getSize() return surface.w, surface.h end

  function t.scroll(n)
    surface:scroll(n, bg, fg)
    damage()
  end

  function t.isColour() return true end
  t.isColor = t.isColour

  function t.setTextColour(colour)
    fg = colour
  end
  t.setTextColor = t.setTextColour

  function t.setBackgroundColour(colour)
    bg = colour
  end
  t.setBackgroundColor = t.setBackgroundColour

  function t.getTextColour() return fg end
  t.getTextColor = t.getTextColour

  function t.getBackgroundColour() return bg end
  t.getBackgroundColor = t.getBackgroundColour

  -- Palette changes are kept per-window.  A single app must not be able to
  -- repaint the whole desktop, so these are recorded but not pushed to the
  -- hardware; getPaletteColour still round-trips so programs behave.
  function t.setPaletteColour(colour, r, g, b)
    if type(r) == "number" and g == nil then
      palette[colour] = r
    else
      palette[colour] = math.floor(r * 255) * 65536 + math.floor(g * 255) * 256 + math.floor(b * 255)
    end
  end
  t.setPaletteColor = t.setPaletteColour

  function t.getPaletteColour(colour)
    local packed = palette[colour] or theme.current.palette[colour]
    if not packed then
      if term.nativePaletteColour then return term.nativePaletteColour(colour) end
      return 0, 0, 0
    end
    return math.floor(packed / 65536) % 256 / 255,
           math.floor(packed / 256) % 256 / 255,
           packed % 256 / 255
  end
  t.getPaletteColor = t.getPaletteColour

  function t.nativePaletteColour(colour)
    if term.nativePaletteColour then return term.nativePaletteColour(colour) end
    return t.getPaletteColour(colour)
  end
  t.nativePaletteColor = t.nativePaletteColour

  -- Aurora extensions used by the window manager.
  t.__aurora = {
    surface = surface,
    cursor = function() return cx, cy, blink, fg end,
    reset = function(newFg, newBg)
      fg = newFg or theme.c.text
      bg = newBg or theme.c.window
      cx, cy = 1, 1
      blink = false
    end,
    rebind = function(newSurface)
      surface = newSurface
      if cx > surface.w then cx = surface.w end
      if cy > surface.h then cy = surface.h end
    end,
  }

  return t
end

return termsurf
