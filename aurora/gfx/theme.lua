--[[ aurora.gfx.theme --------------------------------------------------------
     CC:Tweaked gives us 16 palette slots, and on advanced computers each slot
     can be redefined to any 24-bit colour.  Aurora spends those 16 slots on an
     Adwaita-derived ramp: five neutrals for the shell chrome and eleven hues
     for accents and app icons.

     Code never refers to a slot directly -- it uses semantic tokens
     (theme.c.window, theme.c.accent, ...) so swapping the whole look is one
     table swap plus a palette upload.
----------------------------------------------------------------------------]]

local util = arequire("lib.util")

local theme = {}

theme.schemes = {}

-- Slot handles.  Names are CC's, meanings are ours.
local S = {
  n0 = colours.black,      -- deepest neutral
  n1 = colours.grey,       -- window background
  n2 = colours.brown,      -- raised surface / header
  n3 = colours.lightGrey,  -- dim text, separators
  n4 = colours.white,      -- primary text
  blue = colours.blue,
  lightBlue = colours.lightBlue,
  cyan = colours.cyan,
  green = colours.green,
  lime = colours.lime,
  yellow = colours.yellow,
  orange = colours.orange,
  red = colours.red,
  pink = colours.pink,
  magenta = colours.magenta,
  purple = colours.purple,
}

theme.slots = S

---------------------------------------------------------------- schemes -----

theme.schemes.dark = {
  id = "dark",
  name = "Adwaita Dark",
  palette = {
    [S.n0]        = 0x0F0F14,
    [S.n1]        = 0x24242B,
    [S.n2]        = 0x33333D,
    [S.n3]        = 0x8B8B99,
    [S.n4]        = 0xF2F2F6,
    [S.blue]      = 0x3584E4,
    [S.lightBlue] = 0x78AEED,
    [S.cyan]      = 0x21B8C4,
    [S.green]     = 0x2EC27E,
    [S.lime]      = 0x57E389,
    [S.yellow]    = 0xF5C211,
    [S.orange]    = 0xFF7800,
    [S.red]       = 0xE01B24,
    [S.pink]      = 0xF66151,
    [S.magenta]   = 0xDC8ADD,
    [S.purple]    = 0x9141AC,
  },
  tokens = {
    desktop      = S.n0,
    window       = S.n1,
    header       = S.n2,
    headerIdle   = S.n1,
    view         = S.n0,
    card         = S.n2,
    hover        = S.n2,
    active       = S.n3,
    border       = S.n2,
    separator    = S.n2,
    shadow       = S.n0,
    text         = S.n4,
    dim          = S.n3,
    onAccent     = S.n4,
    accent       = S.blue,
    accentSoft   = S.lightBlue,
    destructive  = S.red,
    success      = S.green,
    warning      = S.orange,
    panel        = S.n0,
    panelText    = S.n4,
    scrim        = S.n0,
    scrimText    = S.n3,
    selection    = S.blue,
    inverse      = S.n4,
    inverseText  = S.n0,
  },
  wallpaper = { top = S.purple, mid = S.blue, bottom = S.n0, aurora = S.cyan },
  dark = true,
}

theme.schemes.light = {
  id = "light",
  name = "Adwaita Light",
  palette = {
    [S.n0]        = 0x1B1B21,  -- primary text in light mode
    [S.n1]        = 0xF4F4F6,  -- window background
    [S.n2]        = 0xE3E3E9,  -- header / hover
    [S.n3]        = 0x6E6E7A,  -- dim text
    [S.n4]        = 0xFFFFFF,  -- views / cards
    [S.blue]      = 0x1C71D8,
    [S.lightBlue] = 0x62A0EA,
    [S.cyan]      = 0x0E8FA3,
    [S.green]     = 0x26A269,
    [S.lime]      = 0x57E389,
    [S.yellow]    = 0xE5A50A,
    [S.orange]    = 0xE66100,
    [S.red]       = 0xC01C28,
    [S.pink]      = 0xED5B4E,
    [S.magenta]   = 0xC061CB,
    [S.purple]    = 0x813D9C,
  },
  tokens = {
    desktop      = S.n2,
    window       = S.n1,
    header       = S.n2,
    headerIdle   = S.n1,
    view         = S.n4,
    card         = S.n4,
    hover        = S.n2,
    active       = S.n3,
    border       = S.n2,
    separator    = S.n2,
    shadow       = S.n3,
    text         = S.n0,
    dim          = S.n3,
    onAccent     = S.n4,
    accent       = S.blue,
    accentSoft   = S.lightBlue,
    destructive  = S.red,
    success      = S.green,
    warning      = S.orange,
    panel        = S.n0,
    panelText    = S.n4,
    scrim        = S.n0,
    scrimText    = S.n3,
    selection    = S.blue,
    inverse      = S.n0,
    inverseText  = S.n4,
  },
  wallpaper = { top = S.lightBlue, mid = S.blue, bottom = S.purple, aurora = S.n4 },
  dark = false,
}

-- A high-contrast scheme for basic (non-colour) computers and accessibility.
theme.schemes.contrast = {
  id = "contrast",
  name = "High Contrast",
  palette = {
    [S.n0]        = 0x000000,
    [S.n1]        = 0x101010,
    [S.n2]        = 0x2A2A2A,
    [S.n3]        = 0xB4B4B4,
    [S.n4]        = 0xFFFFFF,
    [S.blue]      = 0x4D9AFF,
    [S.lightBlue] = 0x9CC8FF,
    [S.cyan]      = 0x2BE0F0,
    [S.green]     = 0x3BE08A,
    [S.lime]      = 0x7CFFB0,
    [S.yellow]    = 0xFFE033,
    [S.orange]    = 0xFF9436,
    [S.red]       = 0xFF4D57,
    [S.pink]      = 0xFF8A7A,
    [S.magenta]   = 0xF0A3F0,
    [S.purple]    = 0xB566D0,
  },
  tokens = nil,  -- filled in below from the dark scheme
  wallpaper = { top = S.n0, mid = S.n1, bottom = S.n0, aurora = S.blue },
  dark = true,
}
theme.schemes.contrast.tokens = util.copy(theme.schemes.dark.tokens)

----------------------------------------------------------------- accents ----

-- Named accent colours the user can pick in Settings.  Each remaps the blue
-- slot so every accent-coloured control in the system follows along.
theme.accents = {
  { id = "blue",   name = "Blue",   dark = 0x3584E4, light = 0x1C71D8 },
  { id = "teal",   name = "Teal",   dark = 0x2190A4, light = 0x007184 },
  { id = "green",  name = "Green",  dark = 0x3A944A, light = 0x2A7A38 },
  { id = "yellow", name = "Yellow", dark = 0xC88800, light = 0xA86F00 },
  { id = "orange", name = "Orange", dark = 0xED5B00, light = 0xD14900 },
  { id = "red",    name = "Red",    dark = 0xE62D42, light = 0xC0193A },
  { id = "pink",   name = "Pink",   dark = 0xD56199, light = 0xB8457D },
  { id = "purple", name = "Purple", dark = 0x9141AC, light = 0x813D9C },
  { id = "slate",  name = "Slate",  dark = 0x6F8396, light = 0x54707F },
}

------------------------------------------------------------------ state -----

theme.current = theme.schemes.dark
theme.accent = "blue"
theme.c = theme.current.tokens
theme.wallpaper = theme.current.wallpaper
theme.listeners = {}

local function accentDef(id)
  for _, a in ipairs(theme.accents) do
    if a.id == id then return a end
  end
  return theme.accents[1]
end

--- Push the active palette into a terminal-like object.
function theme.applyTo(target)
  if not target or not target.setPaletteColour then return end
  if target.isColour and not target.isColour() then return end
  local pal = theme.current.palette
  local acc = accentDef(theme.accent)
  local accValue = theme.current.dark and acc.dark or acc.light
  for slot, value in pairs(pal) do
    if slot == S.blue then value = accValue end
    pcall(target.setPaletteColour, slot, value)
  end
  -- Derive the soft accent by lightening the chosen accent.
  local r = math.floor(accValue / 65536) % 256
  local g = math.floor(accValue / 256) % 256
  local b = accValue % 256
  local function lift(v) return math.min(255, math.floor(v + (255 - v) * 0.45)) end
  pcall(target.setPaletteColour, S.lightBlue, lift(r) * 65536 + lift(g) * 256 + lift(b))
end

function theme.onChange(fn)
  theme.listeners[#theme.listeners + 1] = fn
end

local function notify()
  for _, fn in ipairs(theme.listeners) do pcall(fn) end
end

function theme.set(schemeId, accentId)
  local scheme = theme.schemes[schemeId]
  if scheme then
    theme.current = scheme
    theme.c = scheme.tokens
    theme.wallpaper = scheme.wallpaper
  end
  if accentId then theme.accent = accentId end
  notify()
end

function theme.save(path)
  util.writeTable(path or "/aurora/etc/theme.cfg", {
    scheme = theme.current.id,
    accent = theme.accent,
    wallpaper = theme.wallpaperStyle,
  })
end

function theme.load(path)
  local cfg = util.readTable(path or "/aurora/etc/theme.cfg", nil)
  if not cfg then return end
  theme.wallpaperStyle = cfg.wallpaper or "aurora"
  theme.set(cfg.scheme or "dark", cfg.accent or "blue")
end

theme.wallpaperStyle = "aurora"

return theme
