--[[ aurora.lib.util -- tiny helpers shared by every layer of the system ]]--

local util = {}

---------------------------------------------------------------- classes -----

-- Minimal single-inheritance class helper.
--   local Button = util.class(Widget)
--   function Button:init(text) ... end
--   local b = Button("Hello")
function util.class(base)
  local cls = {}
  cls.__index = cls
  cls.super = base
  setmetatable(cls, {
    __index = base,
    __call = function(c, ...)
      local obj = setmetatable({}, c)
      if obj.init then obj:init(...) end
      return obj
    end,
  })
  return cls
end

----------------------------------------------------------------- numbers ----

function util.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function util.round(v)
  return math.floor(v + 0.5)
end

function util.lerp(a, b, t)
  return a + (b - a) * t
end

-- Smooth ease used by the shell animations.
function util.ease(t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  return t * t * (3 - 2 * t)
end

----------------------------------------------------------------- strings ----

function util.trim(s)
  return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

function util.startsWith(s, prefix)
  return s:sub(1, #prefix) == prefix
end

function util.endsWith(s, suffix)
  return suffix == "" or s:sub(-#suffix) == suffix
end

function util.split(s, sep)
  sep = sep or "%s"
  local out = {}
  for piece in tostring(s):gmatch("([^" .. sep .. "]+)") do out[#out + 1] = piece end
  return out
end

-- Split keeping empty fields (needed by the spreadsheet CSV reader).
function util.splitAll(s, sep)
  local out, start = {}, 1
  while true do
    local a, b = s:find(sep, start, true)
    if not a then out[#out + 1] = s:sub(start) break end
    out[#out + 1] = s:sub(start, a - 1)
    start = b + 1
  end
  return out
end

function util.pad(s, width, char)
  s = tostring(s)
  if #s >= width then return s:sub(1, width) end
  return s .. string.rep(char or " ", width - #s)
end

function util.padLeft(s, width, char)
  s = tostring(s)
  if #s >= width then return s:sub(1, width) end
  return string.rep(char or " ", width - #s) .. s
end

function util.ellipsis(s, width)
  s = tostring(s)
  if width <= 0 then return "" end
  if #s <= width then return s end
  if width <= 1 then return s:sub(1, width) end
  return s:sub(1, width - 1) .. "\7"
end

-- Greedy word wrap.
function util.wrap(text, width)
  local lines = {}
  if width < 1 then return { text } end
  for rawLine in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    if rawLine == "" then
      lines[#lines + 1] = ""
    else
      local current = ""
      for word in rawLine:gmatch("%S+") do
        if current == "" then
          current = word
        elseif #current + 1 + #word <= width then
          current = current .. " " .. word
        else
          lines[#lines + 1] = current
          current = word
        end
        while #current > width do
          lines[#lines + 1] = current:sub(1, width)
          current = current:sub(width + 1)
        end
      end
      lines[#lines + 1] = current
    end
  end
  return lines
end

------------------------------------------------------------------ tables ----

function util.copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

function util.deepCopy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local out = {}
  seen[t] = out
  for k, v in pairs(t) do out[util.deepCopy(k, seen)] = util.deepCopy(v, seen) end
  return out
end

function util.merge(into, from)
  for k, v in pairs(from or {}) do into[k] = v end
  return into
end

function util.indexOf(list, value)
  for i = 1, #list do if list[i] == value then return i end end
  return nil
end

function util.remove(list, value)
  local i = util.indexOf(list, value)
  if i then table.remove(list, i) end
  return i ~= nil
end

function util.keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

------------------------------------------------------------------- files ----

function util.readFile(path)
  if not fs.exists(path) or fs.isDir(path) then return nil end
  local h = fs.open(path, "r")
  if not h then return nil end
  local data = h.readAll()
  h.close()
  return data
end

function util.writeFile(path, data)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local h = fs.open(path, "w")
  if not h then return false end
  h.write(data)
  h.close()
  return true
end

function util.readTable(path, default)
  local data = util.readFile(path)
  if not data then return default end
  local ok, value = pcall(textutils.unserialise, data)
  if not ok or value == nil then return default end
  return value
end

function util.writeTable(path, value)
  return util.writeFile(path, textutils.serialise(value))
end

function util.extension(path)
  local name = fs.getName(path)
  return (name:match("%.([%w_]+)$") or ""):lower()
end

function util.stripExtension(name)
  return (name:gsub("%.[%w_]+$", ""))
end

function util.formatSize(bytes)
  if bytes < 1024 then return bytes .. " B" end
  if bytes < 1024 * 1024 then return string.format("%.1f KB", bytes / 1024) end
  return string.format("%.1f MB", bytes / 1048576)
end

-------------------------------------------------------------------- time ----

function util.clock()
  local ok, value = pcall(os.date, "%H:%M")
  if ok and value then return value end
  return textutils.formatTime(os.time(), true)
end

function util.dateLine()
  local ok, value = pcall(os.date, "%a %d %b")
  if ok and value then return value end
  return "Day " .. os.day()
end

function util.uid()
  return string.format("%x%04x", os.epoch("utc") % 0xFFFFFF, math.random(0, 0xFFFF))
end

return util
