--[[ aurora.kernel.sched -----------------------------------------------------
     The process table and the cooperative scheduler.

     Every window, every background service and every ROM program Aurora runs
     is a coroutine with its own sandboxed global table, its own Surface and
     its own terminal redirect.  The kernel pumps CC events into them:

       * keyboard, mouse, paste and terminate go to exactly one process
         (the focused window, or the window under the pointer)
       * everything else -- timers, peripherals, rednet, http, speaker -- is
         broadcast, which is what CraftOS programs expect.
----------------------------------------------------------------------------]]

local util     = arequire("lib.util")
local Surface  = arequire("gfx.surface")
local theme    = arequire("gfx.theme")
local termsurf = arequire("kernel.termsurf")
local log      = arequire("kernel.log")

local sched = {}

sched.procs   = {}     -- creation order
sched.byPid   = {}
sched.stack   = {}     -- windowed processes, bottom -> top
sched.focus   = nil
sched.nextPid = 1
sched.hooks   = { spawn = {}, exit = {}, focus = {}, damage = {} }

-- Events delivered to a single process rather than broadcast.
local EXCLUSIVE = {
  key = true, key_up = true, char = true, paste = true, terminate = true,
  mouse_click = true, mouse_up = true, mouse_drag = true, mouse_scroll = true,
}
sched.exclusive = EXCLUSIVE

local function fire(kind, ...)
  for _, fn in ipairs(sched.hooks[kind] or {}) do pcall(fn, ...) end
end

function sched.on(kind, fn)
  sched.hooks[kind] = sched.hooks[kind] or {}
  table.insert(sched.hooks[kind], fn)
end

------------------------------------------------------------------ sandbox ---

--- Build the process API handle and the global table a process sees.
---
--- Shared modules (ui.app and friends) are loaded once against the real _G,
--- so they cannot reach a table that only exists in one process's env.  The
--- kernel therefore also points the `aurora` global at whichever process is
--- currently running -- safe because scheduling is cooperative, and the same
--- trick CC itself uses for term.redirect.
local function makeEnv(proc, extra)
  local env = setmetatable({}, { __index = _G })
  env._G = env
  env._ENV = env
  proc.api = {
    pid = proc.pid,
    proc = proc,
    require = arequire,
    exit = function() error("__aurora_exit__", 0) end,
    setTitle = function(title)
      proc.title = title
      if proc.win then proc.win.title = title end
      sched.damage(proc)
    end,
    setIcon = function(icon)
      proc.icon = icon
      if proc.win then
        proc.win.iconChar = icon and icon.char
        proc.win.iconColour = icon and icon.colour
      end
      sched.damage(proc)
    end,
    damage = function() sched.damage(proc) end,
    surface = function() return proc.surface end,
    post = function(pid, ...) sched.post(pid, ...) end,
    spawn = function(opts) return sched.spawn(opts) end,
    processes = function() return sched.procs end,
  }
  env.aurora = proc.api
  for k, v in pairs(extra or {}) do env[k] = v end
  return env
end

------------------------------------------------------------------- spawn ----

local cascade = 0

local function placeWindow(win, display)
  local dw, dh = display.w, display.h
  local workTop = 2                     -- row 1 is the top panel
  local workH = dh - 1
  win.w = math.min(win.w or math.floor(dw * 0.72), dw - 2)
  win.h = math.min(win.h or math.floor(workH * 0.8), workH - 1)
  win.w = math.max(win.w, 16)
  win.h = math.max(win.h, 4)
  if win.x == nil or win.y == nil then
    local offset = cascade % 4
    cascade = cascade + 1
    win.x = math.max(2, math.floor((dw - win.w) / 2) + offset * 2 - 3)
    win.y = math.max(workTop, math.floor((workH - win.h) / 2) + workTop + offset - 1)
  end
  if win.x + win.w - 1 > dw then win.x = dw - win.w end
  if win.y + win.h - 1 > dh then win.y = dh - win.h end
  if win.x < 1 then win.x = 1 end
  if win.y < workTop then win.y = workTop end
end

--- Spawn a process.
--- opts = {
---   name, title, icon = {char=, colour=},
---   fn = function | path = "/path/to/program.lua",
---   args = {...},
---   window = false | {w=,h=,x=,y=,resizable=,headerless=},
---   env = {extra globals},
---   appId = "files",
---   display = Display,
--- }
function sched.spawn(opts)
  opts = opts or {}
  local compositor = arequire("gfx.compositor")
  local display = opts.display or compositor.primary

  local proc = {
    pid     = sched.nextPid,
    name    = opts.name or opts.appId or "process",
    title   = opts.title or opts.name or "Untitled",
    icon    = opts.icon,
    appId   = opts.appId,
    kind    = opts.window == false and "service" or "app",
    args    = opts.args or {},
    inbox   = {},
    dirty   = true,
    started = os.clock(),
    display = display,
    meta    = opts.meta or {},
  }
  sched.nextPid = sched.nextPid + 1

  if opts.window ~= false then
    local win = util.copy(opts.window or {})
    win.title = proc.title
    win.resizable = win.resizable ~= false
    win.headerless = win.headerless or false
    win.minimized = false
    win.maximized = false
    if proc.icon then
      win.iconChar = proc.icon.char
      win.iconColour = proc.icon.colour
    end
    placeWindow(win, display)
    proc.win = win
    local clientH = win.h - (win.headerless and 0 or 1)
    proc.surface = Surface(win.w, math.max(1, clientH), theme.c.window, theme.c.text)
    proc.term = termsurf.create(proc.surface, function() sched.damage(proc) end)
    proc.redirect = proc.term
  else
    -- Services still get a scratch surface so they can use print() for logs.
    proc.surface = Surface(display.w, display.h, theme.c.window, theme.c.text)
    proc.term = termsurf.create(proc.surface, function() end)
    proc.redirect = proc.term
  end

  local body
  if opts.fn then
    body = opts.fn
  elseif opts.path then
    local src = util.readFile(opts.path)
    if not src then
      log.error("sched", "cannot read " .. tostring(opts.path))
      return nil, "not found: " .. tostring(opts.path)
    end
    local env = makeEnv(proc, opts.env)
    proc.env = env
    local fn, err = load(src, "@" .. opts.path, "t", env)
    if not fn then
      log.error("sched", "compile " .. opts.path .. ": " .. tostring(err))
      return nil, err
    end
    body = fn
  else
    return nil, "spawn needs fn or path"
  end

  if not proc.env then
    proc.env = makeEnv(proc, opts.env)
  end

  proc.co = coroutine.create(function(...)
    return body(...)
  end)

  sched.procs[#sched.procs + 1] = proc
  sched.byPid[proc.pid] = proc
  if proc.win then
    sched.stack[#sched.stack + 1] = proc
    sched.setFocus(proc)
  end

  log.info("sched", ("spawn #%d %s"):format(proc.pid, proc.name))
  fire("spawn", proc)

  -- Prime the coroutine with its arguments.
  sched.resume(proc, { n = #proc.args, table.unpack(proc.args, 1, #proc.args) }, true)
  return proc
end

------------------------------------------------------------------ resume ----

local resumeDepth = 0

function sched.resume(proc, ev, initial)
  if proc.dead then return end
  if not initial and proc.filter and ev[1] ~= proc.filter and ev[1] ~= "terminate" then
    return
  end
  if resumeDepth > 0 then
    -- Never re-enter the scheduler from inside a process; queue instead.
    proc.inbox[#proc.inbox + 1] = ev
    return
  end

  resumeDepth = resumeDepth + 1
  local previous = term.redirect(proc.redirect)
  local previousApi = _G.aurora
  _G.aurora = proc.api
  local ok, result = coroutine.resume(proc.co, table.unpack(ev, 1, ev.n or #ev))
  _G.aurora = previousApi
  proc.redirect = term.current()
  term.redirect(previous)
  resumeDepth = resumeDepth - 1

  if not ok then
    if tostring(result):find("__aurora_exit__", 1, true) then
      proc.dead = true
    else
      proc.dead = true
      proc.crashed = tostring(result)
      log.error("sched", ("#%d %s crashed: %s"):format(proc.pid, proc.name, proc.crashed))
    end
  elseif coroutine.status(proc.co) == "dead" then
    proc.dead = true
  else
    proc.filter = type(result) == "string" and result or nil
  end

  if proc.dead then sched.reap(proc) end
end

--- Deliver an event to exactly one process later (safe from inside a process).
function sched.post(pid, ...)
  local proc = type(pid) == "table" and pid or sched.byPid[pid]
  if not proc or proc.dead then return false end
  proc.inbox[#proc.inbox + 1] = table.pack(...)
  os.queueEvent("aurora_wake")
  return true
end

--- Drain queued per-process events.  Called once per kernel loop iteration.
function sched.drain()
  local worked = false
  for i = 1, #sched.procs do
    local proc = sched.procs[i]
    if proc and not proc.dead and #proc.inbox > 0 then
      local queue = proc.inbox
      proc.inbox = {}
      for _, ev in ipairs(queue) do
        sched.resume(proc, ev)
        if proc.dead then break end
      end
      worked = true
    end
  end
  return worked
end

------------------------------------------------------------------- reap -----

function sched.reap(proc)
  util.remove(sched.procs, proc)
  util.remove(sched.stack, proc)
  sched.byPid[proc.pid] = nil
  if sched.focus == proc then
    sched.focus = nil
    for i = #sched.stack, 1, -1 do
      if not sched.stack[i].win.minimized then
        sched.setFocus(sched.stack[i])
        break
      end
    end
  end
  log.info("sched", ("exit #%d %s"):format(proc.pid, proc.name))
  fire("exit", proc)
  sched.damageAll()
end

function sched.kill(proc, reason)
  if type(proc) == "number" then proc = sched.byPid[proc] end
  if not proc or proc.dead then return end
  -- Give the process a chance to shut down cleanly first.
  sched.resume(proc, table.pack("terminate"))
  if not proc.dead then
    proc.dead = true
    sched.reap(proc)
  end
  log.info("sched", "killed " .. tostring(reason or ""))
end

-------------------------------------------------------------- focus / z -----

function sched.setFocus(proc)
  if sched.focus == proc then return end
  local old = sched.focus
  if old and old.win then old.win.focused = false end
  sched.focus = proc
  if proc and proc.win then
    proc.win.focused = true
    proc.win.minimized = false
  end
  sched.damageAll()
  fire("focus", proc, old)
end

function sched.raise(proc)
  if not proc or not proc.win then return end
  util.remove(sched.stack, proc)
  sched.stack[#sched.stack + 1] = proc
  sched.setFocus(proc)
end

function sched.topAt(x, y)
  for i = #sched.stack, 1, -1 do
    local proc = sched.stack[i]
    local win = proc.win
    if win and not win.minimized then
      if x >= win.x and x < win.x + win.w and y >= win.y and y < win.y + win.h then
        return proc
      end
    end
  end
  return nil
end

function sched.cycleFocus(backwards)
  local visible = {}
  for _, proc in ipairs(sched.stack) do
    if proc.win and not proc.win.minimized then visible[#visible + 1] = proc end
  end
  if #visible == 0 then return end
  if backwards then
    sched.raise(visible[1])
  else
    -- Alt+Tab: bring the window below the top one forward.
    local target = visible[#visible - 1] or visible[#visible]
    sched.raise(target)
  end
end

--------------------------------------------------------------- geometry -----

function sched.damage(proc)
  proc.dirty = true
  sched.dirty = true
  fire("damage", proc)
end

function sched.damageAll()
  sched.dirty = true
  for _, proc in ipairs(sched.procs) do proc.dirty = true end
end

function sched.resizeWindow(proc, w, h)
  local win = proc.win
  if not win then return end
  w = math.max(16, math.floor(w))
  h = math.max(4, math.floor(h))
  if win.w == w and win.h == h then return end
  win.w, win.h = w, h
  local clientH = math.max(1, h - (win.headerless and 0 or 1))
  proc.surface:resize(w, clientH, theme.c.window, theme.c.text)
  if proc.term.__aurora then proc.term.__aurora.rebind(proc.surface) end
  sched.damage(proc)
  sched.post(proc, "term_resize")
  sched.post(proc, "aurora_resize", w, clientH)
end

function sched.moveWindow(proc, x, y)
  local win = proc.win
  if not win then return end
  win.x, win.y = math.floor(x), math.floor(y)
  sched.damageAll()
end

function sched.maximize(proc, display)
  local win = proc.win
  if not win then return end
  display = display or proc.display
  if win.maximized then
    local r = win.restoreRect
    win.maximized = false
    if r then
      win.x, win.y = r.x, r.y
      sched.resizeWindow(proc, r.w, r.h)
    end
  else
    win.restoreRect = { x = win.x, y = win.y, w = win.w, h = win.h }
    win.maximized = true
    win.x, win.y = 1, 2
    sched.resizeWindow(proc, display.w, display.h - 1)
  end
  sched.damageAll()
end

function sched.minimize(proc)
  if not proc.win then return end
  proc.win.minimized = true
  if sched.focus == proc then
    sched.focus = nil
    proc.win.focused = false
    for i = #sched.stack, 1, -1 do
      if not sched.stack[i].win.minimized then
        sched.setFocus(sched.stack[i])
        break
      end
    end
  end
  sched.damageAll()
end

function sched.restore(proc)
  if not proc.win then return end
  proc.win.minimized = false
  sched.raise(proc)
end

------------------------------------------------------------------ routing ---

--- Route one CC event into the process table.
--- The shell gets first refusal (hotkeys, panel clicks) before this runs.
function sched.route(ev)
  local name = ev[1]

  if name == "mouse_click" or name == "mouse_up" or name == "mouse_drag" or name == "mouse_scroll" then
    return  -- the window manager translates and forwards these itself
  end

  if EXCLUSIVE[name] then
    local focus = sched.focus
    if focus and not focus.dead then
      sched.resume(focus, ev)
    end
    return
  end

  -- Broadcast.  Iterate over a snapshot: processes may exit mid-loop.
  local snapshot = {}
  for i, proc in ipairs(sched.procs) do snapshot[i] = proc end
  for _, proc in ipairs(snapshot) do
    if not proc.dead then sched.resume(proc, ev) end
  end
end

--- Send a mouse event to a process in window-local coordinates.
function sched.mouseTo(proc, name, button, x, y)
  if not proc or proc.dead or not proc.win then return end
  local win = proc.win
  local headerH = win.headerless and 0 or 1
  local lx = x - win.x + 1
  local ly = y - win.y + 1 - headerH
  if ly < 1 or ly > proc.surface.h or lx < 1 or lx > proc.surface.w then return end
  sched.resume(proc, table.pack(name, button, lx, ly))
end

function sched.count()
  local windows, services = 0, 0
  for _, proc in ipairs(sched.procs) do
    if proc.win then windows = windows + 1 else services = services + 1 end
  end
  return windows, services, #sched.procs
end

function sched.find(appId)
  for _, proc in ipairs(sched.procs) do
    if proc.appId == appId then return proc end
  end
end

return sched
