--[[ System Monitor ---------------------------------------------------------
     Processes, attached devices, storage and the kernel log.
----------------------------------------------------------------------------]]

local App     = arequire("ui.app")
local base    = arequire("ui.widget")
local W       = arequire("ui.widgets")
local theme   = arequire("gfx.theme")
local util    = arequire("lib.util")
local kernel  = arequire("kernel.init")
local sched   = arequire("kernel.sched")
local devices = arequire("kernel.devices")
local vfs     = arequire("kernel.vfs")
local log     = arequire("kernel.log")

local app = App({ title = "System Monitor" })

local tabs = W.Tabs({ tabs = {
  { label = "Processes", id = "procs" },
  { label = "Devices", id = "devices" },
  { label = "Storage", id = "storage" },
  { label = "Log", id = "log" },
} })

local toolbar = W.Toolbar({ spacing = 0 })
toolbar:add(tabs)
local spacer = W.Label({ text = "" })
spacer.hexpand = true
toolbar:add(spacer)
local refreshButton = W.IconButton({ icon = "\24", width = 3 })
toolbar:add(refreshButton)

local procList = W.ListBox({ rows = {}, showSubtitles = true, background = theme.c.window })
procList.vexpand = true
local deviceList = W.ListBox({ rows = {}, showSubtitles = true, background = theme.c.window })
deviceList.vexpand = true
local logList = W.ListBox({ rows = {}, showSubtitles = true, background = theme.c.window })
logList.vexpand = true

local function scrolled(child)
  local s = base.Scrolled({ background = theme.c.window })
  s.hexpand, s.vexpand = true, true
  s:setChild(child)
  return s
end

local procScroller = scrolled(procList)
local deviceScroller = scrolled(deviceList)
local logScroller = scrolled(logList)

-- storage page: a usage bar plus a chart of the last few samples
local storagePage = base.Box({ orientation = "vertical", spacing = 1, padding = 1 })
storagePage.hexpand, storagePage.vexpand = true, true
local usageLabel = W.Label({ text = "", dim = true })
usageLabel.hexpand = true
local usageBar = W.ProgressBar({ value = 0 })
usageBar.hexpand = true
local procChart = W.Chart({ series = {}, kind = "line", height = 6 })
procChart.hexpand = true
local chartLabel = W.Label({ text = "Running processes", dim = true })
chartLabel.hexpand = true
storagePage:add(usageLabel)
storagePage:add(usageBar)
storagePage:add(chartLabel)
storagePage:add(procChart)

local pages = base.Stack()
pages.hexpand, pages.vexpand = true, true
pages:addPage("procs", procScroller)
pages:addPage("devices", deviceScroller)
pages:addPage("storage", storagePage)
pages:addPage("log", logScroller)

local statusLabel = W.Label({ text = "", dim = true })
statusLabel.hexpand = true
local status = base.Box({ orientation = "horizontal" })
status.hexpand = true
status.background = theme.c.window
status:add(statusLabel)

local root = base.Box({ orientation = "vertical", spacing = 0 })
root.hexpand, root.vexpand = true, true
root:add(toolbar)
root:add(pages)
root:add(status)
app:setRoot(root)

------------------------------------------------------------------ refresh --

local history = {}

local function refreshProcs()
  local rows = {}
  for _, proc in ipairs(sched.procs) do
    local kind = proc.win and "window" or "service"
    local age = math.floor(os.clock() - (proc.started or os.clock()))
    rows[#rows + 1] = {
      title = ("%d  %s"):format(proc.pid, proc.title or proc.name),
      subtitle = ("%s  \183  %ds  \183  %s"):format(kind, age,
        proc.win and (proc.win.minimized and "minimised" or "visible") or "background"),
      icon = { char = "\254", colour = proc == sched.focus and theme.c.accent or theme.c.dim },
      value = proc,
    }
  end
  procList:setRows(rows, true)
end

local function refreshDevices()
  local rows = {}
  local all = devices.all()
  for _, record in ipairs(all) do
    local detail = record.class
    if record.class == "display" and record.w then
      detail = detail .. ("  \183  %dx%d"):format(record.w, record.h)
    elseif record.class == "network" then
      detail = detail .. (record.wireless and "  \183  wireless" or "  \183  wired")
    elseif record.class == "storage" and record.mount then
      detail = detail .. "  \183  " .. record.mount
    end
    rows[#rows + 1] = {
      title = record.name,
      subtitle = record.label .. "  \183  " .. detail,
      icon = { char = record.char, colour = record.colour },
    }
  end
  if #rows == 0 then
    rows[1] = { title = "Nothing attached", subtitle = "No peripherals found" }
  end
  deviceList:setRows(rows, true)
end

local function refreshLog()
  local rows = {}
  for _, entry in ipairs(log.tail(60)) do
    local colour = theme.c.dim
    if entry.level == "warn" then colour = theme.c.warning end
    if entry.level == "error" then colour = theme.c.destructive end
    rows[#rows + 1] = {
      title = entry.source .. ": " .. entry.message,
      subtitle = entry.time .. "  \183  " .. entry.level,
      icon = { char = "\7", colour = colour },
    }
  end
  if #rows == 0 then rows[1] = { title = "Log is empty" } end
  logList:setRows(rows, true)
end

local function refreshStorage()
  local usage = vfs.usage()
  local fraction = usage.capacity > 0 and (usage.used / usage.capacity) or 0
  usageBar:setValue(fraction)
  usageLabel:setText(("%s used of %s  (%d%%)")
    :format(util.formatSize(usage.used), util.formatSize(usage.capacity),
            math.floor(fraction * 100)))
  procChart:setSeries(history)
end

local function refreshAll()
  local windows, services, total = sched.count()
  history[#history + 1] = total
  while #history > 24 do table.remove(history, 1) end

  if pages.currentName == "procs" then refreshProcs()
  elseif pages.currentName == "devices" then refreshDevices()
  elseif pages.currentName == "log" then refreshLog()
  else refreshStorage() end

  statusLabel:setText((" %d processes  \183  %d windows  \183  up %d min")
    :format(total, windows, math.floor(kernel.uptime() / 60)))
  app:queueLayout()
end

------------------------------------------------------------------ wiring --

tabs:connect("changed", function(_, index, tab)
  pages:setPage(tab.id)
  refreshAll()
end)

refreshButton:connect("clicked", refreshAll)

procList:connect("activate", function(_, index, row)
  local proc = row and row.value
  if not proc then return end
  app:menu(app.surface.w - 24, 3, {
    { label = "Bring to front", icon = "\16", disabled = proc.win == nil,
      action = function() sched.restore(proc) end },
    { label = "Minimise", icon = "\31", disabled = proc.win == nil,
      action = function() sched.minimize(proc) refreshAll() end },
    { separator = true },
    { label = "End process", icon = "\215", destructive = true, action = function()
        app:confirm({
          title = "End " .. (proc.title or proc.name) .. "?",
          message = "Anything it has not saved will be lost.",
          acceptLabel = "End",
          destructive = true,
          onAccept = function()
            sched.kill(proc, "system monitor")
            refreshAll()
          end,
        })
      end },
  }, 22)
end)

app:accel("f5", refreshAll)

app:every(2, refreshAll)
refreshAll()
app:setFocus(procList)
app:run()
