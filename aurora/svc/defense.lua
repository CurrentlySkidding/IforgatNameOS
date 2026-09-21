--[[ aurora.svc.defense ------------------------------------------------------
     Base defense, wired to real redstone.

     A "device" is a named output: a door, a light, a trap, a siren.  Each one
     drives a redstone side (or a colour on a bundled cable) and can be
     switched by hand, by the alarm, or by a schedule.

     A "sensor" is an input: a redstone line from a pressure plate, a tripwire
     or a daylight sensor, or a player detector peripheral if the pack has
     one.  When the system is armed and a sensor trips, the alarm fires: every
     device marked as an alarm response switches on, the event is logged, a
     desktop notification appears, and an encrypted alert goes out to every
     computer on your network.
----------------------------------------------------------------------------]]

local util    = arequire("lib.util")
local log     = arequire("kernel.log")
local devices = arequire("kernel.devices")
local net     = arequire("svc.net")

local defense = {}

defense.CONFIG = "/aurora/etc/defense.cfg"
defense.LOG = "/aurora/var/defense.log"

defense.SIDES = { "top", "bottom", "left", "right", "front", "back" }

defense.armed = false
defense.alarming = false
defense.passcode = nil
defense.devices = {}       -- { id, name, side, colour, kind, on, onAlarm }
defense.sensors = {}       -- { id, name, side, kind, invert, tripped }
defense.events = {}        -- newest first
defense.listeners = {}
defense.alertRemote = true
defense.MAX_EVENTS = 60

local KINDS = {
  door   = { label = "Door",   char = "\254", colour = colours.lightBlue },
  light  = { label = "Light",  char = "\015", colour = colours.yellow },
  trap   = { label = "Trap",   char = "\016", colour = colours.red },
  siren  = { label = "Siren",  char = "\014", colour = colours.orange },
  turret = { label = "Turret", char = "\030", colour = colours.magenta },
  other  = { label = "Output", char = "\004", colour = colours.lightGrey },
}
defense.kinds = KINDS

function defense.kindOf(id)
  return KINDS[id] or KINDS.other
end

------------------------------------------------------------------ config ---

function defense.load()
  local cfg = util.readTable(defense.CONFIG, nil) or {}
  defense.devices = cfg.devices or {}
  defense.sensors = cfg.sensors or {}
  defense.passcode = cfg.passcode
  defense.armed = cfg.armed or false
  defense.alertRemote = cfg.alertRemote ~= false
  defense.events = util.readTable(defense.LOG, {}) or {}
  return cfg
end

function defense.save()
  util.writeTable(defense.CONFIG, {
    devices = defense.devices,
    sensors = defense.sensors,
    passcode = defense.passcode,
    armed = defense.armed,
    alertRemote = defense.alertRemote,
  })
end

----------------------------------------------------------------- redstone --

--- Set one output.  Handles both plain sides and bundled-cable colours.
local function applyOutput(device, on)
  local ok = pcall(function()
    if device.colour and device.colour ~= 0 then
      local current = redstone.getBundledOutput(device.side) or 0
      local updated
      if on then
        updated = colours.combine(current, device.colour)
      else
        updated = colours.subtract(current, device.colour)
      end
      redstone.setBundledOutput(device.side, updated)
    else
      redstone.setOutput(device.side, on and true or false)
    end
  end)
  return ok
end

local function readSensor(sensor)
  local ok, value = pcall(function()
    if sensor.colour and sensor.colour ~= 0 then
      local bundled = redstone.getBundledInput(sensor.side) or 0
      return colours.test(bundled, sensor.colour)
    end
    return redstone.getInput(sensor.side) and true or false
  end)
  if not ok then return false end
  if sensor.invert then return not value end
  return value and true or false
end

------------------------------------------------------------------ devices --

function defense.addDevice(name, side, kind, colour, onAlarm)
  local device = {
    id = util.uid(),
    name = name,
    side = side,
    kind = kind or "other",
    colour = colour or 0,
    onAlarm = onAlarm or false,
    on = false,
  }
  defense.devices[#defense.devices + 1] = device
  defense.save()
  return device
end

function defense.removeDevice(id)
  for i, device in ipairs(defense.devices) do
    if device.id == id then
      applyOutput(device, false)
      table.remove(defense.devices, i)
      defense.save()
      return true
    end
  end
  return false
end

function defense.findDevice(id)
  for _, device in ipairs(defense.devices) do
    if device.id == id then return device end
  end
end

function defense.setDevice(id, on)
  local device = defense.findDevice(id)
  if not device then return false, "no such device" end
  device.on = on and true or false
  applyOutput(device, device.on)
  defense.save()
  defense.record(device.on and "on" or "off", device.name)
  defense.notifyListeners()
  return true
end

function defense.toggleDevice(id)
  local device = defense.findDevice(id)
  if not device then return false end
  return defense.setDevice(id, not device.on)
end

--- Turn everything off.  Used by disarm and the panic button.
function defense.allOff()
  for _, device in ipairs(defense.devices) do
    device.on = false
    applyOutput(device, false)
  end
  defense.save()
  defense.notifyListeners()
end

------------------------------------------------------------------ sensors --

function defense.addSensor(name, side, colour, invert)
  local sensor = {
    id = util.uid(),
    name = name,
    side = side,
    colour = colour or 0,
    invert = invert or false,
    tripped = false,
  }
  defense.sensors[#defense.sensors + 1] = sensor
  defense.save()
  return sensor
end

function defense.removeSensor(id)
  for i, sensor in ipairs(defense.sensors) do
    if sensor.id == id then
      table.remove(defense.sensors, i)
      defense.save()
      return true
    end
  end
  return false
end

--- Peripherals that can tell us about players nearby, when the pack has them.
function defense.detectors()
  local out = {}
  for _, record in ipairs(devices.all()) do
    if record.kind == "playerDetector" or record.kind == "player_detector"
       or record.kind == "radar" or record.kind == "entityDetector" then
      out[#out + 1] = record
    end
  end
  return out
end

function defense.scanPlayers()
  local names = {}
  for _, record in ipairs(defense.detectors()) do
    local handle = record.handle
    if handle then
      for _, method in ipairs({ "getPlayersInRange", "getPlayersInCoords", "getPlayers" }) do
        if handle[method] then
          local ok, list = pcall(handle[method], 16)
          if ok and type(list) == "table" then
            for _, entry in ipairs(list) do
              names[#names + 1] = type(entry) == "table" and (entry.name or "?") or tostring(entry)
            end
          end
          break
        end
      end
    end
  end
  return names
end

------------------------------------------------------------------- events --

function defense.record(kind, detail)
  table.insert(defense.events, 1, {
    kind = kind,
    detail = detail,
    clock = util.clock(),
    ts = os.epoch("utc"),
  })
  while #defense.events > defense.MAX_EVENTS do table.remove(defense.events) end
  util.writeTable(defense.LOG, defense.events)
end

function defense.clearLog()
  defense.events = {}
  util.writeTable(defense.LOG, defense.events)
  defense.notifyListeners()
end

function defense.listen(pid)
  for _, existing in ipairs(defense.listeners) do
    if existing == pid then return end
  end
  table.insert(defense.listeners, pid)
end

function defense.unlisten(pid)
  util.remove(defense.listeners, pid)
end

function defense.notifyListeners()
  local sched = arequire("kernel.sched")
  for _, pid in ipairs(defense.listeners) do
    sched.post(pid, "aurora_defense")
  end
end

-------------------------------------------------------------- arm / alarm ---

function defense.arm()
  defense.armed = true
  defense.alarming = false
  -- settle the sensors so an already-open door does not fire instantly
  for _, sensor in ipairs(defense.sensors) do
    sensor.tripped = readSensor(sensor)
  end
  defense.save()
  defense.record("armed", "system armed")
  defense.notifyListeners()
  log.info("defense", "armed")
end

function defense.disarm()
  defense.armed = false
  if defense.alarming then defense.stopAlarm() end
  defense.save()
  defense.record("disarmed", "system disarmed")
  defense.notifyListeners()
  log.info("defense", "disarmed")
end

function defense.checkPasscode(code)
  if not defense.passcode or defense.passcode == "" then return true end
  return tostring(code or "") == defense.passcode
end

function defense.setPasscode(code)
  code = util.trim(tostring(code or ""))
  defense.passcode = code ~= "" and code or nil
  defense.save()
end

function defense.trigger(reason)
  if defense.alarming then return end
  defense.alarming = true
  defense.record("alarm", reason or "sensor tripped")
  log.warn("defense", "ALARM: " .. tostring(reason))

  for _, device in ipairs(defense.devices) do
    if device.onAlarm then
      device.on = true
      applyOutput(device, true)
    end
  end
  defense.save()

  local desktop = arequire("shell.desktop")
  desktop.notify("ALARM", reason or "sensor tripped", "error")

  if defense.alertRemote and net.open then
    net.broadcast("defense.alert", {
      reason = reason or "sensor tripped",
      from = net.displayName,
      clock = util.clock(),
    })
  end

  defense.notifyListeners()
end

function defense.stopAlarm()
  if not defense.alarming then return end
  defense.alarming = false
  for _, device in ipairs(defense.devices) do
    if device.onAlarm then
      device.on = false
      applyOutput(device, false)
    end
  end
  defense.save()
  defense.record("clear", "alarm cleared")
  defense.notifyListeners()
end

--- Read every sensor and fire the alarm on a fresh trip.
function defense.poll()
  if #defense.sensors == 0 then return end
  for _, sensor in ipairs(defense.sensors) do
    local now = readSensor(sensor)
    if now ~= sensor.tripped then
      sensor.tripped = now
      if now then
        defense.record("sensor", sensor.name .. " tripped")
        if defense.armed then
          defense.trigger(sensor.name .. " tripped")
        else
          defense.notifyListeners()
        end
      else
        defense.notifyListeners()
      end
    end
  end
end

------------------------------------------------------------------ summary --

function defense.status()
  if defense.alarming then return "alarm" end
  if defense.armed then return "armed" end
  return "disarmed"
end

function defense.summary()
  local on = 0
  for _, device in ipairs(defense.devices) do
    if device.on then on = on + 1 end
  end
  local tripped = 0
  for _, sensor in ipairs(defense.sensors) do
    if sensor.tripped then tripped = tripped + 1 end
  end
  return {
    status = defense.status(),
    devices = #defense.devices,
    active = on,
    sensors = #defense.sensors,
    tripped = tripped,
    detectors = #defense.detectors(),
  }
end

----------------------------------------------------------------- service ----

function defense.service()
  defense.load()
  net.subscribe("defense.alert", aurora.pid)

  -- Restore the outputs we were driving before the reboot.
  for _, device in ipairs(defense.devices) do
    applyOutput(device, device.on)
  end

  local pollTimer = os.startTimer(0.5)
  while true do
    local event = table.pack(os.pullEvent())

    if event[1] == "timer" and event[2] == pollTimer then
      pollTimer = os.startTimer(0.5)
      pcall(defense.poll)

    elseif event[1] == "redstone" then
      pcall(defense.poll)

    elseif event[1] == "aurora_net" and event[2] == "defense.alert" then
      local data, sender = event[4], event[3]
      local desktop = arequire("shell.desktop")
      local where = (data and data.from) or ("computer-" .. tostring(sender))
      desktop.notify("Alert from " .. where,
                     (data and data.reason) or "alarm", "error")
      defense.record("remote", where .. ": " .. ((data and data.reason) or "alarm"))
      defense.notifyListeners()
    end
  end
end

return defense
