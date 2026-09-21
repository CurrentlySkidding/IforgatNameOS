--[[ aurora.lib.bitops -------------------------------------------------------
     32-bit bitwise operations that work on every Lua the OS might meet.

     CC:Tweaked ships bit32, so in game that is what runs.  Lua 5.3 and newer
     have native operators but no bit32; those are reached through load() so
     this file still parses on 5.1, where the operators are a syntax error.
     A pure-arithmetic implementation backs both up.
----------------------------------------------------------------------------]]

local bitops = {}

local MASK = 0xFFFFFFFF

bitops.backend = "arithmetic"

---------------------------------------------------------------- arithmetic --

local function normalise(value)
  value = value % 4294967296
  if value < 0 then value = value + 4294967296 end
  return value
end

local function arithXor(a, b)
  a, b = normalise(a), normalise(b)
  local result, bit = 0, 1
  while a > 0 or b > 0 do
    local abit, bbit = a % 2, b % 2
    if abit ~= bbit then result = result + bit end
    a = (a - abit) / 2
    b = (b - bbit) / 2
    bit = bit * 2
  end
  return result
end

local function arithAnd(a, b)
  a, b = normalise(a), normalise(b)
  local result, bit = 0, 1
  while a > 0 and b > 0 do
    local abit, bbit = a % 2, b % 2
    if abit == 1 and bbit == 1 then result = result + bit end
    a = (a - abit) / 2
    b = (b - bbit) / 2
    bit = bit * 2
  end
  return result
end

local function arithOr(a, b)
  a, b = normalise(a), normalise(b)
  local result, bit = 0, 1
  while a > 0 or b > 0 do
    local abit, bbit = a % 2, b % 2
    if abit == 1 or bbit == 1 then result = result + bit end
    a = (a - abit) / 2
    b = (b - bbit) / 2
    bit = bit * 2
  end
  return result
end

local function arithLshift(value, places)
  if places >= 32 then return 0 end
  return normalise(normalise(value) * 2 ^ places)
end

local function arithRshift(value, places)
  if places >= 32 then return 0 end
  return math.floor(normalise(value) / 2 ^ places)
end

local arithmetic = {
  bxor = arithXor, band = arithAnd, bor = arithOr,
  lshift = arithLshift, rshift = arithRshift,
}

bitops.arithmetic = arithmetic

------------------------------------------------------------------ backends --

--- Lua 5.3+ native operators, compiled at runtime so 5.1 can still parse us.
local function nativeBackend()
  local chunk = load([[
    return {
      bxor = function(a, b) return (a ~ b) & 0xFFFFFFFF end,
      band = function(a, b) return (a & b) & 0xFFFFFFFF end,
      bor = function(a, b) return (a | b) & 0xFFFFFFFF end,
      lshift = function(v, n) return (v << n) & 0xFFFFFFFF end,
      rshift = function(v, n) return (v & 0xFFFFFFFF) >> n end,
    }
  ]])
  if not chunk then return nil end
  local ok, value = pcall(chunk)
  if not ok or type(value) ~= "table" then return nil end
  -- sanity check before trusting it
  if value.bxor(0xF0F0F0F0, 0x0F0F0F0F) ~= 0xFFFFFFFF then return nil end
  return value
end

local selected
if type(_G.bit32) == "table" and _G.bit32.bxor then
  selected = {
    bxor = _G.bit32.bxor, band = _G.bit32.band, bor = _G.bit32.bor,
    lshift = _G.bit32.lshift, rshift = _G.bit32.rshift,
  }
  bitops.backend = "bit32"
else
  selected = nativeBackend()
  if selected then
    bitops.backend = "native"
  else
    selected = arithmetic
    bitops.backend = "arithmetic"
  end
end

bitops.bxor = selected.bxor
bitops.band = selected.band
bitops.bor = selected.bor
bitops.lshift = selected.lshift
bitops.rshift = selected.rshift
bitops.normalise = normalise
bitops.MASK = MASK

--- Force a backend.  Only the tests use this, to check they agree.
function bitops.use(name)
  local backend
  if name == "arithmetic" then
    backend = arithmetic
  elseif name == "bit32" and type(_G.bit32) == "table" then
    backend = { bxor = _G.bit32.bxor, band = _G.bit32.band, bor = _G.bit32.bor,
                lshift = _G.bit32.lshift, rshift = _G.bit32.rshift }
  elseif name == "native" then
    backend = nativeBackend()
  end
  if not backend then return false end
  bitops.bxor, bitops.band, bitops.bor = backend.bxor, backend.band, backend.bor
  bitops.lshift, bitops.rshift = backend.lshift, backend.rshift
  bitops.backend = name
  return true
end

return bitops
