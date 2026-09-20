--[[ aurora.svc.display ------------------------------------------------------
     Multi-monitor support.  Every attached CC monitor becomes an Aurora
     Display and can be set to one of three roles:

       mirror    -- shows the same desktop as the computer's own screen
       extend    -- its own workspace; windows can be sent to it
       dedicated -- one app owns it (Slides presenting, a status board)
       off       -- blanked

     Touches on a monitor are translated into mouse events for whatever the
     monitor is showing.
----------------------------------------------------------------------------]]

local util       = arequire("lib.util")
local log        = arequire("kernel.log")
local devices    = arequire("kernel.devices")
local compositor = arequire("gfx.compositor")
local theme      = arequire("gfx.theme")

local display = {}

display.CONFIG = "/aurora/etc/displays.cfg"
display.roles = {}      -- monitor name -> role
display.owners = {}     -- monitor name -> pid of the dedicated app
display.scale = {}      -- monitor name -> text scale

local ROLE_LABELS = {
  mirror = "Mirror main screen",
  extend = "Extended workspace",
  dedicated = "Dedicated to an app",
  off = "Turned off",
}
display.roleLabels = ROLE_LABELS

function display.load()
  local cfg = util.readTable(display.CONFIG, nil)
  if cfg then
    display.roles = cfg.roles or {}
    display.scale = cfg.scale or {}
  end
end

function display.save()
  util.writeTable(display.CONFIG, { roles = display.roles, scale = display.scale })
end

--- Bring every attached monitor into the compositor.
function display.sync()
  for _, record in ipairs(devices.byClass("display")) do
    local existing = compositor.get(record.name)
    if not existing and record.handle then
      local scale = display.scale[record.name] or 0.5
      pcall(record.handle.setTextScale, scale)
      local d = compositor.add(record.name, record.handle, "monitor")
      d.role = display.roles[record.name] or "mirror"
      d.device = record
      log.info("display", ("monitor %s online (%dx%d, %s)")
        :format(record.name, d.w, d.h, d.role))
    elseif existing then
      existing:checkSize()
    end
  end
  -- drop monitors that went away
  for _, d in ipairs({ table.unpack(compositor.displays) }) do
    if d.kind == "monitor" and not devices.get(d.id) then
      compositor.remove(d.id)
      display.owners[d.id] = nil
      log.info("display", "monitor " .. d.id .. " removed")
    end
  end
end

function display.setRole(name, role)
  display.roles[name] = role
  local d = compositor.get(name)
  if d then
    d.role = role
    d:reset()
  end
  if role ~= "dedicated" then display.owners[name] = nil end
  display.save()
end

function display.setScale(name, scale)
  display.scale[name] = scale
  local record = devices.get(name)
  if record and record.handle then
    pcall(record.handle.setTextScale, scale)
  end
  local d = compositor.get(name)
  if d then
    d:checkSize()
    d:reset()
  end
  display.save()
end

--- Hand a monitor to a single process (used by Slides "Present").
function display.claim(name, proc)
  local d = compositor.get(name)
  if not d then return nil, "no such monitor" end
  display.roles[name] = "dedicated"
  d.role = "dedicated"
  display.owners[name] = proc.pid
  d:reset()
  return d
end

function display.release(name)
  display.owners[name] = nil
  display.roles[name] = display.roles[name] == "dedicated" and "mirror" or display.roles[name]
  local d = compositor.get(name)
  if d then
    d.role = display.roles[name] or "mirror"
    d:reset()
  end
end

function display.releaseAllFor(pid)
  for name, owner in pairs(display.owners) do
    if owner == pid then display.release(name) end
  end
end

function display.ownerOf(name)
  local pid = display.owners[name]
  if not pid then return nil end
  local sched = arequire("kernel.sched")
  return sched.byPid[pid]
end

--- Draw a "no signal" style idle screen on monitors with nothing to show.
function display.drawIdle(d)
  local pixel = arequire("gfx.pixel")
  local c = theme.c
  local s = d.surface
  s:clear(c.desktop, c.dim)
  if d.h >= 6 and d.w >= 20 then
    local canvas = pixel.Canvas(math.min(d.w, 24), 3, c.desktop)
    local tw = pixel.textWidth("AURORA")
    canvas:text(math.floor((canvas.w - tw) / 2) + 1, 2, "AURORA", c.accent)
    canvas:render(s, math.floor((d.w - math.min(d.w, 24)) / 2) + 1,
                  math.floor(d.h / 2) - 2)
    s:writeCentered(math.floor(d.h / 2) + 2,
                    ROLE_LABELS[d.role] or "Idle", c.dim, c.desktop)
  else
    s:writeCentered(math.max(1, math.floor(d.h / 2)), "Aurora", c.accent, c.desktop)
  end
  d:invalidate()
end

--- Translate a monitor_touch into a click for whatever owns that monitor.
--- Returns target ("shell" | proc | nil), x, y
function display.routeTouch(name, x, y)
  local d = compositor.get(name)
  if not d then return nil end
  if d.role == "mirror" then
    return "mirror", x, y
  elseif d.role == "dedicated" then
    local proc = display.ownerOf(name)
    if proc then return proc, x, y end
  elseif d.role == "extend" then
    return "extend", x, y, d
  end
  return nil
end

function display.list()
  local out = {}
  for _, d in ipairs(compositor.displays) do
    out[#out + 1] = {
      id = d.id,
      kind = d.kind,
      role = d.role,
      w = d.w,
      h = d.h,
      scale = display.scale[d.id] or (d.kind == "monitor" and 0.5 or 1),
      colour = d.device and d.device.colourCapable,
      owner = display.owners[d.id],
    }
  end
  return out
end

return display
