--[[ aurora.kernel.log -- ring buffer + on-disk kernel log ]]--

local log = {}

local PATH = "/aurora/var/kernel.log"
local MAX_MEMORY = 240

log.entries = {}
log.toDisk = true

local LEVELS = { debug = 10, info = 20, warn = 30, error = 40 }
log.level = LEVELS.info

local function stamp()
  local ok, value = pcall(os.date, "%H:%M:%S")
  if ok and value then return value end
  return textutils.formatTime(os.time(), true)
end

local function push(level, source, message)
  local entry = {
    level = level,
    source = source or "kernel",
    message = tostring(message),
    time = stamp(),
    uptime = os.clock(),
  }
  log.entries[#log.entries + 1] = entry
  if #log.entries > MAX_MEMORY then table.remove(log.entries, 1) end

  if log.toDisk and LEVELS[level] >= LEVELS.warn then
    pcall(function()
      local dir = fs.getDir(PATH)
      if not fs.exists(dir) then fs.makeDir(dir) end
      -- keep the on-disk log from growing without bound
      if fs.exists(PATH) and fs.getSize(PATH) > 16384 then fs.delete(PATH) end
      local h = fs.open(PATH, "a")
      if h then
        h.writeLine(("[%s] %-5s %s: %s"):format(entry.time, level:upper(), entry.source, entry.message))
        h.close()
      end
    end)
  end
  return entry
end

function log.debug(source, msg) if log.level <= LEVELS.debug then return push("debug", source, msg) end end
function log.info(source, msg)  if log.level <= LEVELS.info  then return push("info",  source, msg) end end
function log.warn(source, msg)  return push("warn",  source, msg) end
function log.error(source, msg) return push("error", source, msg) end

function log.tail(n)
  n = n or 20
  local out = {}
  for i = math.max(1, #log.entries - n + 1), #log.entries do
    out[#out + 1] = log.entries[i]
  end
  return out
end

function log.clear()
  log.entries = {}
  pcall(fs.delete, PATH)
end

log.path = PATH

return log
