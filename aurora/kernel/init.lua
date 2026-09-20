--[[ aurora.kernel.init ------------------------------------------------------
     Kernel entry point: bring up the subsystems in order, start the services,
     then run the event loop until something asks us to power down.
----------------------------------------------------------------------------]]

local util       = arequire("lib.util")
local log        = arequire("kernel.log")
local theme      = arequire("gfx.theme")
local compositor = arequire("gfx.compositor")
local Surface    = arequire("gfx.surface")
local sched      = arequire("kernel.sched")
local vfs        = arequire("kernel.vfs")
local devices    = arequire("kernel.devices")

local kernel = {}

kernel.VERSION = "1.0.0"
kernel.CODENAME = "Borealis"
kernel.bootTime = os.clock()

--------------------------------------------------------------- subsystems ---

function kernel.bringUp(progress)
  local steps = {
    { "Mounting filesystems", function()
        vfs.ensure()
      end },
    { "Loading theme", function()
        theme.load()
        theme.applyTo(term.native())
      end },
    { "Starting compositor", function()
        compositor.init()
      end },
    { "Probing peripherals", function()
        devices.scan()
      end },
    { "Configuring displays", function()
        local displaySvc = arequire("svc.display")
        displaySvc.load()
        displaySvc.sync()
      end },
    { "Scanning applications", function()
        local apps = arequire("svc.apps")
        apps.scan()
      end },
    { "Starting services", function()
        kernel.startServices()
      end },
    { "Starting desktop shell", function()
        local desktop = arequire("shell.desktop")
        desktop.init()
        desktop.running = true
      end },
  }

  for i, step in ipairs(steps) do
    if progress then progress(step[1], i / #steps) end
    local ok, err = pcall(step[2])
    if not ok then
      log.error("kernel", step[1] .. " failed: " .. tostring(err))
      if progress then progress(step[1] .. " failed", i / #steps, tostring(err)) end
    end
  end
end

function kernel.startServices()
  local printer = arequire("svc.printer")
  sched.spawn({
    name = "printerd",
    title = "Print spooler",
    window = false,
    fn = function()
      local ok, err = pcall(printer.service)
      if not ok then log.error("printerd", tostring(err)) end
    end,
  })
end

--------------------------------------------------------------- autostart ----

function kernel.autostart()
  local apps = arequire("svc.apps")
  local list = util.readTable("/aurora/etc/autostart.cfg", nil)
  if not list then return end
  for _, id in ipairs(list) do
    local ok, err = pcall(apps.launch, id)
    if not ok then log.warn("kernel", "autostart " .. id .. ": " .. tostring(err)) end
  end
end

-------------------------------------------------------------- panic screen --

function kernel.panic(message, detail)
  log.error("kernel", tostring(message))
  local out = term.native()
  pcall(function()
    out.setBackgroundColour(colours.blue)
    out.setTextColour(colours.white)
    out.clear()
    local w, h = out.getSize()
    local title = "Aurora has stopped"
    out.setCursorPos(math.floor((w - #title) / 2) + 1, 3)
    out.write(title)
    out.setCursorPos(2, 5)
    out.write("The kernel hit an error it could not recover from.")
    local lines = util.wrap(tostring(message), w - 4)
    for i, line in ipairs(lines) do
      out.setCursorPos(3, 6 + i)
      out.write(line)
    end
    if detail then
      out.setCursorPos(2, h - 3)
      out.write(util.ellipsis(tostring(detail), w - 4))
    end
    out.setCursorPos(2, h - 1)
    out.write("Press any key to return to CraftOS.")
  end)
  os.pullEvent("key")
end

--------------------------------------------------------------- main loop ----

function kernel.loop()
  local desktop = arequire("shell.desktop")
  desktop.render()

  while desktop.running do
    local ev = table.pack(os.pullEventRaw())

    local ok, err = pcall(function()
      local consumed = desktop.handleEvent(ev)
      if not consumed then sched.route(ev) end
      sched.drain()
    end)

    if not ok then
      log.error("kernel", tostring(err))
      desktop.notify("System error", tostring(err):sub(1, 60), "error")
      sched.dirty = true
    end

    if sched.dirty then
      local renderOk, renderErr = pcall(desktop.render)
      if not renderOk then
        log.error("kernel", "render: " .. tostring(renderErr))
        sched.dirty = false
      end
    end
  end

  return desktop.quitReason or "shutdown"
end

-------------------------------------------------------------------- start ---

function kernel.start(progress)
  kernel.bringUp(progress)
  kernel.autostart()

  local reason = kernel.loop()
  kernel.teardown()
  return reason
end

function kernel.teardown()
  for _, proc in ipairs({ table.unpack(sched.procs) }) do
    pcall(sched.kill, proc, "shutdown")
  end
  local out = term.native()
  pcall(function()
    for i = 0, 15 do
      if out.setPaletteColour and term.nativePaletteColour then
        out.setPaletteColour(2 ^ i, term.nativePaletteColour(2 ^ i))
      end
    end
    out.setBackgroundColour(colours.black)
    out.setTextColour(colours.white)
    out.setCursorBlink(false)
    out.clear()
    out.setCursorPos(1, 1)
  end)
end

function kernel.uptime()
  return os.clock() - kernel.bootTime
end

function kernel.info()
  local windows, services, total = sched.count()
  return {
    version = kernel.VERSION,
    codename = kernel.CODENAME,
    uptime = kernel.uptime(),
    windows = windows,
    services = services,
    processes = total,
    devices = devices.summary(),
    computerId = os.getComputerID(),
    label = os.getComputerLabel(),
    advanced = term.isColour(),
  }
end

return kernel
