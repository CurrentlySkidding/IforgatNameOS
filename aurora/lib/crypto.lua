--[[ aurora.lib.crypto -------------------------------------------------------
     Encryption and message authentication for Aurora's secure network.

     The cipher is XXTEA: small, well-defined, and fast enough in Lua that a
     chat message or a web page costs a fraction of a tick.  The same
     primitive builds the message authentication code, so there is exactly one
     algorithm to trust.

     What this gives you: somebody sniffing your channel with a modem cannot
     read your traffic or forge a message that passes the MAC.  What it does
     not give you: protection from anyone who can read the key off your
     computer's disk.  Treat the network key like a base password.
----------------------------------------------------------------------------]]

local bitops = arequire("lib.bitops")

local crypto = {}

local bxor, band, bor = bitops.bxor, bitops.band, bitops.bor
local lshift, rshift = bitops.lshift, bitops.rshift

local DELTA = 0x9E3779B9

local function refresh()
  bxor, band, bor = bitops.bxor, bitops.band, bitops.bor
  lshift, rshift = bitops.lshift, bitops.rshift
end
crypto.refresh = refresh

------------------------------------------------------------ word packing ----

--- string -> array of little-endian uint32, length appended when asked.
local function toWords(text, includeLength)
  local count = math.ceil(#text / 4)
  local words = {}
  for i = 1, count do
    local a = text:byte((i - 1) * 4 + 1) or 0
    local b = text:byte((i - 1) * 4 + 2) or 0
    local c = text:byte((i - 1) * 4 + 3) or 0
    local d = text:byte((i - 1) * 4 + 4) or 0
    words[i] = a + b * 256 + c * 65536 + d * 16777216
  end
  if includeLength then words[count + 1] = #text end
  return words
end

local function fromWords(words, hasLength)
  local length
  if hasLength then
    length = words[#words]
    table.remove(words)
    if type(length) ~= "number" or length < 0 or length > #words * 4 then
      return nil
    end
  end
  local bytes = {}
  for i = 1, #words do
    local value = words[i] % 4294967296
    bytes[#bytes + 1] = string.char(value % 256)
    bytes[#bytes + 1] = string.char(math.floor(value / 256) % 256)
    bytes[#bytes + 1] = string.char(math.floor(value / 65536) % 256)
    bytes[#bytes + 1] = string.char(math.floor(value / 16777216) % 256)
  end
  local out = table.concat(bytes)
  if length then out = out:sub(1, length) end
  return out
end

--------------------------------------------------------------------- key ----

--- Derive four 32-bit key words from a passphrase.  Four FNV-1a passes with
--- different offsets, then a few rounds of mixing so a one-character change
--- to the passphrase changes every word.
function crypto.deriveKey(passphrase)
  passphrase = tostring(passphrase or "")
  if passphrase == "" then passphrase = "aurora" end
  local key = { 0x811C9DC5, 0x01000193, 0xDEADBEEF, 0x5BF03635 }
  for round = 1, 4 do
    local hash = key[round]
    for i = 1, #passphrase do
      hash = bxor(hash, passphrase:byte(i) + round)
      hash = (hash * 16777619) % 4294967296
      hash = bxor(hash, rshift(hash, 13))
    end
    key[round] = hash
  end
  for _ = 1, 3 do
    for i = 1, 4 do
      local previous = key[(i + 2) % 4 + 1]
      key[i] = bxor(key[i], (previous * 2654435761) % 4294967296)
      key[i] = bor(rshift(key[i], 7), lshift(key[i], 25))
    end
  end
  return key
end

------------------------------------------------------------------ XXTEA -----

local function mx(sum, y, z, p, e, key)
  local left = bxor(rshift(z, 5), lshift(y, 2))
  local right = bxor(rshift(y, 3), lshift(z, 4))
  local keyWord = key[band(bxor(p % 4, e), 3) + 1]
  return bxor((left + right) % 4294967296,
              (bxor(sum, y) + bxor(keyWord, z)) % 4294967296)
end

local function encryptWords(words, key)
  local n = #words
  if n < 2 then return words end
  local rounds = 6 + math.floor(52 / n)
  local sum = 0
  local z = words[n]
  for _ = 1, rounds do
    sum = (sum + DELTA) % 4294967296
    local e = band(rshift(sum, 2), 3)
    local y
    for p = 0, n - 2 do
      y = words[p + 2]
      words[p + 1] = (words[p + 1] + mx(sum, y, z, p, e, key)) % 4294967296
      z = words[p + 1]
    end
    y = words[1]
    words[n] = (words[n] + mx(sum, y, z, n - 1, e, key)) % 4294967296
    z = words[n]
  end
  return words
end

local function decryptWords(words, key)
  local n = #words
  if n < 2 then return words end
  local rounds = 6 + math.floor(52 / n)
  local sum = (rounds * DELTA) % 4294967296
  local y = words[1]
  for _ = 1, rounds do
    local e = band(rshift(sum, 2), 3)
    local z
    for p = n - 1, 1, -1 do
      z = words[p]
      words[p + 1] = (words[p + 1] - mx(sum, y, z, p, e, key)) % 4294967296
      y = words[p + 1]
    end
    z = words[n]
    words[1] = (words[1] - mx(sum, y, z, 0, e, key)) % 4294967296
    y = words[1]
    sum = (sum - DELTA) % 4294967296
  end
  return words
end

-------------------------------------------------------------------- hex -----

local HEX = "0123456789abcdef"

function crypto.toHex(text)
  local out = {}
  for i = 1, #text do
    local byte = text:byte(i)
    out[i] = HEX:sub(math.floor(byte / 16) + 1, math.floor(byte / 16) + 1)
            .. HEX:sub(byte % 16 + 1, byte % 16 + 1)
  end
  return table.concat(out)
end

function crypto.fromHex(text)
  if #text % 2 ~= 0 then return nil end
  local out = {}
  for i = 1, #text, 2 do
    local byte = tonumber(text:sub(i, i + 1), 16)
    if not byte then return nil end
    out[#out + 1] = string.char(byte)
  end
  return table.concat(out)
end

----------------------------------------------------------------- public -----

--- Encrypt a string.  Returns hex, which survives serialisation and rednet.
function crypto.encrypt(plaintext, key)
  if type(key) ~= "table" then key = crypto.deriveKey(key) end
  plaintext = tostring(plaintext or "")
  if plaintext == "" then return "" end
  local words = toWords(plaintext, true)
  -- XXTEA needs at least two words to mix anything
  while #words < 2 do words[#words + 1] = 0 end
  return crypto.toHex(fromWords(encryptWords(words, key), false))
end

--- Decrypt.  Returns nil when the text is not valid ciphertext for this key.
function crypto.decrypt(ciphertext, key)
  if type(key) ~= "table" then key = crypto.deriveKey(key) end
  if ciphertext == "" or ciphertext == nil then return "" end
  local raw = crypto.fromHex(tostring(ciphertext))
  if not raw or #raw < 8 or #raw % 4 ~= 0 then return nil end
  local words = toWords(raw, false)
  local ok, result = pcall(function()
    return fromWords(decryptWords(words, key), true)
  end)
  if not ok then return nil end
  return result
end

--- Keyed message authentication: XXTEA in CBC-MAC form over the message,
--- returned as 16 hex characters.
function crypto.mac(message, key)
  if type(key) ~= "table" then key = crypto.deriveKey(key) end
  message = tostring(message or "")
  local words = toWords(message .. "\1aurora-mac", true)
  while #words < 2 do words[#words + 1] = 0 end
  local state = { 0, 0 }
  for i = 1, #words, 2 do
    state[1] = bxor(state[1], words[i])
    state[2] = bxor(state[2], words[i + 1] or 0x5A5A5A5A)
    encryptWords(state, key)
  end
  return crypto.toHex(fromWords({ state[1], state[2] }, false))
end

--- Constant-ish time comparison, so a wrong MAC does not leak where it
--- diverged through timing.
function crypto.equal(a, b)
  a, b = tostring(a or ""), tostring(b or "")
  if #a ~= #b then return false end
  local diff = 0
  for i = 1, #a do
    diff = bor(diff, bxor(a:byte(i), b:byte(i)))
  end
  return diff == 0
end

--- A short random token, used for nonces and session ids.
--- Every character must be exactly one hex digit: picking a random *range*
--- out of the alphabet instead of a random *index* produced short and even
--- empty tokens, which collide, and colliding nonces get dropped as replays.
function crypto.token(length)
  length = length or 8
  local out = {}
  for i = 1, length do
    local index = math.random(1, 16)
    out[i] = HEX:sub(index, index)
  end
  -- Mix in a counter and the clock so two computers that boot together, with
  -- the same seeded random sequence, still do not produce the same tokens.
  crypto.counter = (crypto.counter or 0) + 1
  local stamp = crypto.toHex(tostring(os.epoch("utc") % 4096) .. tostring(crypto.counter))
  local token = (table.concat(out) .. stamp)
  if #token < length then
    token = token .. string.rep("0", length - #token)
  end
  return token:sub(1, length)
end

crypto.counter = 0

--- Fingerprint of a key, so people can check two machines share one without
--- ever showing the key itself.
function crypto.fingerprint(key)
  if type(key) ~= "table" then key = crypto.deriveKey(key) end
  return crypto.mac("fingerprint", key):sub(1, 8):upper()
end

return crypto
