--[[ aurora.kernel.devices ---------------------------------------------------
     Peripheral hot-plug manager.  Keeps a live inventory of everything wired
     to the computer, classifies it, and tells the rest of the system when
     something appears or disappears.

     Monitors become extra displays, printers become print targets, modems
     become the network stack, speakers become the sound system.
----------------------------------------------------------------------------]]

local util = arequire("lib.util")
local log  = arequire("kernel.log")

local devices = {}

devices.list = {}        -- name -> device record
devices.listeners = {}

local CLASSES = {
  monitor        = { class = "display", label = "Monitor",        char = "\254", colour = colours.lightBlue },
  printer        = { class = "printer", label = "Printer",        char = "\022", colour = colours.yellow },
  modem          = { class = "network", label = "Modem",          char = "\015", colour = colours.cyan },
  speaker        = { class = "audio",   label = "Speaker",        char = "\014", colour = colours.magenta },
  drive          = { class = "storage", label = "Disk drive",     char = "\007", colour = colours.orange },
  computer       = { class = "compute", label = "Computer",       char = "\254", colour = colours.lightGrey },
  turtle         = { class = "compute", label = "Turtle",         char = "\254", colour = colours.green },
  command        = { class = "compute", label = "Command block",  char = "\254", colour = colours.purple },
}

local function classify(name, kind)
  local def = CLASSES[kind]
  if not def then
    -- Generic inventories, tanks and mod blocks all land here.
    def = { class = "other", label = kind or "Peripheral", char = "\004", colour = colours.lightGrey }
  end
  local record = {
    name = name,
    kind = kind,
    class = def.class,
    label = def.label,
    char = def.char,
    colour = def.colour,
    wired = name:find("_") ~= nil,   -- "monitor_3" means wired via a modem
  }
  record.side = record.wired and nil or name
  return record
end

local function notify(event, record)
  for _, fn in ipairs(devices.listeners) do
    pcall(fn, event, record)
  end
end

function devices.onChange(fn)
  devices.listeners[#devices.listeners + 1] = fn
end

function devices.attach(name)
  local ok, kind = pcall(peripheral.getType, name)
  if not ok or not kind then return nil end
  local record = classify(name, kind)
  local wrapOk, wrapped = pcall(peripheral.wrap, name)
  record.handle = wrapOk and wrapped or nil

  if record.class == "display" and record.handle then
    pcall(record.handle.setTextScale, 0.5)
    local sizeOk, w, h = pcall(record.handle.getSize)
    if sizeOk then record.w, record.h = w, h end
    record.colourCapable = record.handle.isColour and record.handle.isColour() or false
  elseif record.class == "network" and record.handle then
    record.wireless = record.handle.isWireless and record.handle.isWireless() or false
  elseif record.class == "storage" and record.handle then
    record.mount = record.handle.getMountPath and record.handle.getMountPath() or nil
    record.diskLabel = record.handle.getDiskLabel and record.handle.getDiskLabel() or nil
  end

  devices.list[name] = record
  log.info("devices", "attached " .. name .. " (" .. kind .. ")")
  notify("attach", record)
  return record
end

function devices.detach(name)
  local record = devices.list[name]
  devices.list[name] = nil
  if record then
    log.info("devices", "detached " .. name)
    notify("detach", record)
  end
  return record
end

function devices.scan()
  local seen = {}
  for _, name in ipairs(peripheral.getNames()) do
    seen[name] = true
    if not devices.list[name] then devices.attach(name) end
  end
  for name in pairs(devices.list) do
    if not seen[name] then devices.detach(name) end
  end
end

--- Handle a raw CC event.  Returns true if it was a device event.
function devices.handleEvent(ev)
  local name = ev[1]
  if name == "peripheral" then
    devices.attach(ev[2])
    return true
  elseif name == "peripheral_detach" then
    devices.detach(ev[2])
    return true
  elseif name == "monitor_resize" then
    local record = devices.list[ev[2]]
    if record and record.handle then
      local ok, w, h = pcall(record.handle.getSize)
      if ok then record.w, record.h = w, h end
      notify("resize", record)
    end
    return true
  elseif name == "disk" or name == "disk_eject" then
    devices.scan()
    return true
  end
  return false
end

------------------------------------------------------------------ queries ---

function devices.byClass(class)
  local out = {}
  for _, record in pairs(devices.list) do
    if record.class == class then out[#out + 1] = record end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function devices.get(name) return devices.list[name] end

function devices.first(class)
  local all = devices.byClass(class)
  return all[1]
end

function devices.all()
  local out = {}
  for _, record in pairs(devices.list) do out[#out + 1] = record end
  table.sort(out, function(a, b)
    if a.class ~= b.class then return a.class < b.class end
    return a.name < b.name
  end)
  return out
end

function devices.summary()
  local counts = {}
  for _, record in pairs(devices.list) do
    counts[record.class] = (counts[record.class] or 0) + 1
  end
  return counts
end

return devices
