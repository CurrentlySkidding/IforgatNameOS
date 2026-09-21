--[[ Defense ----------------------------------------------------------------
     The control panel for the base defense system.

     Three tabs: a status board with the arm button, the devices you can
     switch, and the event log.
----------------------------------------------------------------------------]]

local App     = arequire("ui.app")
local base    = arequire("ui.widget")
local W       = arequire("ui.widgets")
local theme   = arequire("gfx.theme")
local util    = arequire("lib.util")
local pixel   = arequire("gfx.pixel")
local defense = arequire("svc.defense")
local net     = arequire("svc.net")

local app = App({ title = "Defense" })

------------------------------------------------------------------- chrome --

local tabs = W.Tabs({ tabs = {
  { label = "Status", id = "status" },
  { label = "Devices", id = "devices" },
  { label = "Log", id = "log" },
} })

local menuButton = W.IconButton({ icon = "\7", width = 3 })

local toolbar = W.Toolbar({ spacing = 0 })
toolbar:add(tabs)
local spacer = W.Label({ text = "" })
spacer.hexpand = true
toolbar:add(spacer)
toolbar:add(menuButton)

------------------------------------------------------------ status board ---

local StatusBoard = util.class(base.Widget)

function StatusBoard:init()
  base.Widget.init(self, {})
  self.hexpand, self.vexpand = true, true
end

function StatusBoard:measure() return 24, 8 end

function StatusBoard:draw(s)
  local c = theme.c
  local summary = defense.summary()
  local bg = c.window
  s:fill(self.x, self.y, self.w, self.h, " ", c.text, bg)

  local colour = c.success
  local word = "SECURE"
  if summary.status == "armed" then colour, word = c.warning, "ARMED" end
  if summary.status == "alarm" then colour, word = c.destructive, "ALARM" end

  -- The state, big, in the pixel font: readable across the room on a monitor.
  if self.w >= 24 and self.h >= 7 then
    local canvas = pixel.Canvas(math.min(self.w - 2, 30), 3, bg)
    local tw = pixel.textWidth(word)
    canvas:text(math.max(1, math.floor((canvas.w - tw) / 2) + 1), 2, word, colour)
    canvas:render(s, self.x + math.floor((self.w - math.min(self.w - 2, 30)) / 2), self.y)
  else
    s:writeCentered(self.y + 1, word, colour, bg, self.x, self.w)
  end

  local rows = {
    ("Devices   %d  (%d on)"):format(summary.devices, summary.active),
    ("Sensors   %d  (%d tripped)"):format(summary.sensors, summary.tripped),
    ("Network   %s"):format(net.status()),
  }
  if summary.detectors > 0 then
    local players = defense.scanPlayers()
    rows[#rows + 1] = ("Nearby    %s")
      :format(#players == 0 and "nobody" or util.ellipsis(table.concat(players, ", "), 22))
  end

  local top = self.y + 4
  for i, text in ipairs(rows) do
    if top + i - 1 < self.y + self.h then
      s:write(self.x + 2, top + i - 1, util.ellipsis(text, self.w - 4), c.dim, bg)
    end
  end
end

local statusBoard = StatusBoard()

local armButton = W.Button({ label = "Arm", style = "suggested" })
armButton.hexpand = true
local panicButton = W.Button({ label = "Panic", style = "destructive" })
panicButton.hexpand = true

local statusButtons = base.Box({ orientation = "horizontal", spacing = 1 })
statusButtons.hexpand = true
statusButtons:add(armButton)
statusButtons:add(panicButton)

local statusPage = base.Box({ orientation = "vertical", spacing = 0 })
statusPage.hexpand, statusPage.vexpand = true, true
statusPage:add(statusBoard)
statusPage:add(statusButtons)

----------------------------------------------------------------- devices ---

local deviceList = W.ListBox({ rows = {}, showSubtitles = true, background = theme.c.window })
deviceList.vexpand = true
local deviceScroller = base.Scrolled({ background = theme.c.window })
deviceScroller.hexpand, deviceScroller.vexpand = true, true
deviceScroller:setChild(deviceList)

--------------------------------------------------------------------- log ---

local logList = W.ListBox({ rows = {}, showSubtitles = false, background = theme.c.window })
logList.vexpand = true
local logScroller = base.Scrolled({ background = theme.c.window })
logScroller.hexpand, logScroller.vexpand = true, true
logScroller:setChild(logList)

local pages = base.Stack()
pages.hexpand, pages.vexpand = true, true
pages:addPage("status", statusPage)
pages:addPage("devices", deviceScroller)
pages:addPage("log", logScroller)

local root = base.Box({ orientation = "vertical", spacing = 0 })
root.hexpand, root.vexpand = true, true
root:add(toolbar)
root:add(pages)
app:setRoot(root)

------------------------------------------------------------------ refresh --

local function refreshDevices()
  local rows = {}
  for _, device in ipairs(defense.devices) do
    local kind = defense.kindOf(device.kind)
    local where = device.side
    if device.colour and device.colour ~= 0 then
      where = where .. " (bundled)"
    end
    rows[#rows + 1] = {
      title = device.name,
      subtitle = ("%s  \183  %s%s"):format(kind.label, where,
                                           device.onAlarm and "  \183  alarm" or ""),
      icon = { char = kind.char, colour = device.on and theme.c.success or theme.c.dim },
      trailing = device.on and "ON" or "off",
      deviceId = device.id,
    }
  end
  for _, sensor in ipairs(defense.sensors) do
    rows[#rows + 1] = {
      title = sensor.name,
      subtitle = ("Sensor  \183  %s%s"):format(sensor.side, sensor.invert and "  \183  inverted" or ""),
      icon = { char = "\4", colour = sensor.tripped and theme.c.destructive or theme.c.dim },
      trailing = sensor.tripped and "TRIP" or "",
      sensorId = sensor.id,
    }
  end
  if #rows == 0 then
    rows[1] = { title = "Nothing wired up yet",
                subtitle = "Add a door, light or sensor from the menu" }
  end
  deviceList:setRows(rows, true)
end

local function refreshLog()
  local rows = {}
  local colours_ = {
    alarm = theme.c.destructive, armed = theme.c.warning,
    disarmed = theme.c.success, clear = theme.c.success,
    sensor = theme.c.warning, remote = theme.c.destructive,
  }
  for _, event in ipairs(defense.events) do
    rows[#rows + 1] = {
      title = ("%s  %s"):format(event.clock or "", util.ellipsis(event.detail or event.kind, 28)),
      icon = { char = "\7", colour = colours_[event.kind] or theme.c.dim },
    }
  end
  if #rows == 0 then rows[1] = { title = "Nothing has happened yet" } end
  logList:setRows(rows, true)
end

local function refresh()
  local status = defense.status()
  armButton.label = status == "disarmed" and "Arm" or "Disarm"
  armButton.style = status == "disarmed" and "suggested" or "normal"
  panicButton.label = defense.alarming and "Stop alarm" or "Panic"
  aurora.setTitle(status == "alarm" and "Defense - ALARM" or "Defense")

  if pages.currentName == "devices" then refreshDevices() end
  if pages.currentName == "log" then refreshLog() end
  app:queueLayout()
end

------------------------------------------------------------------ actions --

local function withPasscode(title, fn)
  if not defense.passcode then fn() return end
  app:prompt({
    title = title,
    message = "Enter the passcode",
    text = "",
    onAccept = function(code)
      if defense.checkPasscode(code) then
        fn()
      else
        app:notify("Wrong passcode", "error")
        defense.record("denied", "wrong passcode")
      end
    end,
  })
end

local function toggleArm()
  if defense.status() == "disarmed" then
    withPasscode("Arm the system", function()
      defense.arm()
      app:notify("System armed", "success")
      refresh()
    end)
  else
    withPasscode("Disarm the system", function()
      defense.disarm()
      app:notify("System disarmed", "success")
      refresh()
    end)
  end
end

local function panic()
  if defense.alarming then
    withPasscode("Stop the alarm", function()
      defense.stopAlarm()
      refresh()
    end)
  else
    defense.trigger("panic button")
    refresh()
  end
end

local function addDevice()
  local nameEntry = W.Entry({ text = "", placeholder = "Name, e.g. Front door" })
  nameEntry.hexpand = true
  local sideTabs = W.Tabs({ tabs = {} })
  for _, side in ipairs(defense.SIDES) do
    sideTabs.tabs[#sideTabs.tabs + 1] = { label = side:sub(1, 2):upper(), id = side }
  end
  local kindTabs = W.Tabs({ tabs = {
    { label = "Door", id = "door" },
    { label = "Light", id = "light" },
    { label = "Trap", id = "trap" },
    { label = "Siren", id = "siren" },
  } })
  local alarmCheck = W.CheckBox({ label = "Fires on alarm", active = false })
  alarmCheck.hexpand = true

  local form = base.Box({ orientation = "vertical", spacing = 0 })
  form.hexpand = true
  form:add(nameEntry)
  form:add(sideTabs)
  form:add(kindTabs)
  form:add(alarmCheck)

  app:dialog({
    title = "Add a device",
    body = form,
    actions = {
      { label = "Cancel" },
      { label = "Add", style = "suggested", onClick = function()
          local name = util.trim(nameEntry.text)
          if name == "" then name = "Device" end
          defense.addDevice(name,
                            sideTabs.tabs[sideTabs.active].id,
                            kindTabs.tabs[kindTabs.active].id,
                            0, alarmCheck.active)
          refreshDevices()
          app:notify(name .. " added", "success")
        end },
    },
  })
  app:setFocus(nameEntry)
end

local function addSensor()
  local nameEntry = W.Entry({ text = "", placeholder = "Name, e.g. Back gate" })
  nameEntry.hexpand = true
  local sideTabs = W.Tabs({ tabs = {} })
  for _, side in ipairs(defense.SIDES) do
    sideTabs.tabs[#sideTabs.tabs + 1] = { label = side:sub(1, 2):upper(), id = side }
  end
  local invertCheck = W.CheckBox({ label = "Trip when power stops", active = false })
  invertCheck.hexpand = true

  local form = base.Box({ orientation = "vertical", spacing = 0 })
  form.hexpand = true
  form:add(nameEntry)
  form:add(sideTabs)
  form:add(invertCheck)

  app:dialog({
    title = "Add a sensor",
    body = form,
    actions = {
      { label = "Cancel" },
      { label = "Add", style = "suggested", onClick = function()
          local name = util.trim(nameEntry.text)
          if name == "" then name = "Sensor" end
          defense.addSensor(name, sideTabs.tabs[sideTabs.active].id, 0, invertCheck.active)
          refreshDevices()
          app:notify(name .. " added", "success")
        end },
    },
  })
  app:setFocus(nameEntry)
end

local function openMenu()
  app:menu(app.surface.w - 26, 2, {
    { label = "Add device", icon = "\254", action = addDevice },
    { label = "Add sensor", icon = "\4", action = addSensor },
    { label = "All devices off", icon = "\215", action = function()
        defense.allOff()
        refreshDevices()
        app:notify("Everything switched off")
      end },
    { separator = true },
    { label = defense.passcode and "Change passcode" or "Set a passcode", icon = "\7",
      action = function()
        app:prompt({
          title = "Passcode",
          message = "Leave it empty for no passcode.",
          text = "",
          onAccept = function(code)
            defense.setPasscode(code)
            app:notify(defense.passcode and "Passcode set" or "Passcode removed", "success")
          end,
        })
      end },
    { label = defense.alertRemote and "Stop alerting the network"
                                   or "Alert the network on alarm", icon = "\15",
      action = function()
        defense.alertRemote = not defense.alertRemote
        defense.save()
        app:notify(defense.alertRemote and "Alerts will be broadcast"
                                        or "Alerts stay on this computer")
      end },
    { separator = true },
    { label = "Clear the log", icon = "\233", destructive = true, action = function()
        defense.clearLog()
        refreshLog()
      end },
  }, 26)
end

------------------------------------------------------------------ wiring ---

tabs:connect("changed", function(_, index, tab)
  pages:setPage(tab.id)
  refresh()
end)
menuButton:connect("clicked", openMenu)
armButton:connect("clicked", toggleArm)
panicButton:connect("clicked", panic)

deviceList:connect("activate", function(_, index, row)
  if row.deviceId then
    defense.toggleDevice(row.deviceId)
    refreshDevices()
  elseif row.sensorId then
    local id = row.sensorId
    app:confirm({
      title = "Remove this sensor?",
      message = row.title .. " will stop being watched.",
      acceptLabel = "Remove",
      destructive = true,
      onAccept = function()
        defense.removeSensor(id)
        refreshDevices()
      end,
    })
  end
end)

app:accel("ctrl+a", toggleArm)
app:accel("f5", refresh)

app.onEvent = function(name)
  if name == "aurora_defense" then refresh() app:queueDraw() end
end

app.onClose = function()
  defense.unlisten(aurora.pid)
  return true
end

defense.listen(aurora.pid)
app:every(2, function()
  if pages.currentName == "status" then app:queueDraw() end
end)

refresh()
app:setFocus(armButton)
app:run()
