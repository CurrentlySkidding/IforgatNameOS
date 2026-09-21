--[[ Aria -------------------------------------------------------------------
     The assistant's window: a conversation, and a text box.

     The thinking lives in lib.aria; this file gathers the context Aria needs
     (who is on the network, what the base is doing) and carries out whatever
     action she decides on.
----------------------------------------------------------------------------]]

local args    = { ... }
local App     = arequire("ui.app")
local base    = arequire("ui.widget")
local W       = arequire("ui.widgets")
local theme   = arequire("gfx.theme")
local util    = arequire("lib.util")
local aria    = arequire("lib.aria")
local appsSvc = arequire("svc.apps")
local net     = arequire("svc.net")
local defense = arequire("svc.defense")
local printer = arequire("svc.printer")
local devices = arequire("kernel.devices")
local kernel  = arequire("kernel.init")
local vfs     = arequire("kernel.vfs")

local app = App({ title = "Aria" })

local history = {}     -- { who = "aria"|"you", text = }

------------------------------------------------------------------- chrome --

local titleLabel = W.Label({ text = " Aria" })
titleLabel.hexpand = true
local menuButton = W.IconButton({ icon = "\7", width = 3 })

local toolbar = W.Toolbar({ spacing = 0 })
toolbar:add(titleLabel)
toolbar:add(menuButton)

----------------------------------------------------------- conversation ----

local Conversation = util.class(base.Widget)

function Conversation:init()
  base.Widget.init(self, {})
  self.hexpand, self.vexpand = true, true
  self.scroll = 0
end

function Conversation:measure() return 24, 6 end

function Conversation:rows()
  local width = math.max(10, self.w - 4)
  local rows = {}
  for _, entry in ipairs(history) do
    local lines = util.wrap(entry.text, width)
    for i, line in ipairs(lines) do
      rows[#rows + 1] = { text = line, who = entry.who, first = i == 1 }
    end
  end
  return rows
end

function Conversation:scrollToEnd()
  self.scroll = math.max(0, #self:rows() - self.h)
  self:invalidate()
end

function Conversation:draw(s)
  local c = theme.c
  s:fill(self.x, self.y, self.w, self.h, " ", c.text, c.view)
  local rows = self:rows()
  local maxScroll = math.max(0, #rows - self.h)
  if self.scroll > maxScroll then self.scroll = maxScroll end

  for row = 1, self.h do
    local entry = rows[self.scroll + row]
    if entry then
      local y = self.y + row - 1
      local mine = entry.who == "you"
      local fg = mine and c.text or c.accentSoft
      if entry.first then
        s:write(self.x + 1, y, mine and "\16" or "\7",
                mine and c.dim or c.accent, c.view)
      end
      s:write(self.x + 3, y, entry.text, fg, c.view)
    end
  end

  if #rows > self.h then
    local trackX = self.x + self.w - 1
    local thumb = math.max(1, math.floor(self.h * self.h / #rows))
    local pos = math.floor((self.h - thumb) * (self.scroll / math.max(1, maxScroll)))
    for i = 0, thumb - 1 do
      s:write(trackX, self.y + pos + i, "\149", c.dim, c.view)
    end
  end
end

function Conversation:onMouse(kind, button)
  if kind == "mouse_scroll" then
    self.scroll = math.max(0, self.scroll + button * 2)
    self:invalidate()
    return true
  end
  return false
end

local conversation = Conversation()

local askEntry = W.Entry({ placeholder = "Ask me something", icon = "\4" })
askEntry.hexpand = true

local askRow = base.Box({ orientation = "horizontal", spacing = 0 })
askRow.hexpand = true
askRow.background = theme.c.window
askRow:add(askEntry)

local root = base.Box({ orientation = "vertical", spacing = 0 })
root.hexpand, root.vexpand = true, true
root:add(toolbar)
root:add(conversation)
root:add(askRow)
app:setRoot(root)

------------------------------------------------------------------ context --

--- Everything Aria might want to know about the machine she is running on.
local function buildContext()
  local status = {}

  local summary = defense.summary()
  if summary.devices > 0 or summary.sensors > 0 then
    status[#status + 1] = ("Defense is %s (%d devices, %d sensors)")
      :format(summary.status, summary.devices, summary.sensors)
  end

  status[#status + 1] = "Network is " .. net.status()
  local peers = net.peerList()
  local online = 0
  for _, peer in ipairs(peers) do if peer.online then online = online + 1 end end
  if #peers > 0 then
    status[#status + 1] = ("%d computer(s) known, %d online"):format(#peers, online)
  end

  local printers = printer.available()
  for _, record in ipairs(printers) do
    local state = printer.status(record)
    if state ~= "ready" then
      status[#status + 1] = ("Printer %s is %s"):format(record.name, state)
    end
  end

  local monitors = devices.byClass("display")
  if #monitors > 0 then
    status[#status + 1] = ("%d monitor(s) attached"):format(#monitors)
  end

  local usage = vfs.usage()
  status[#status + 1] = ("%s of disk free"):format(util.formatSize(usage.free))

  local info = kernel.info()
  status[#status + 1] = ("Up %d minutes, %d processes")
    :format(math.floor(info.uptime / 60), info.processes)

  return { peers = peers, status = status }
end

------------------------------------------------------------------ actions --

local function perform(action)
  if not action then return end

  if action.kind == "launch" then
    local ok = appsSvc.launch(action.app, action.args)
    if not ok then
      history[#history + 1] = { who = "aria", text = "I could not open that one." }
    end

  elseif action.kind == "arm" then
    if #defense.devices == 0 and #defense.sensors == 0 then
      history[#history + 1] = { who = "aria",
        text = "Nothing is wired up yet. Add a device in the Defense app first." }
    elseif defense.passcode then
      history[#history + 1] = { who = "aria",
        text = "That needs the passcode, so use the Defense app." }
      appsSvc.launch("defense")
    else
      defense.arm()
      history[#history + 1] = { who = "aria", text = "Armed. I will shout if anything trips." }
    end

  elseif action.kind == "disarm" then
    if defense.passcode then
      history[#history + 1] = { who = "aria", text = "Passcode needed. Opening Defense." }
      appsSvc.launch("defense")
    else
      defense.disarm()
    end

  elseif action.kind == "lights" then
    local touched = 0
    for _, device in ipairs(defense.devices) do
      if device.kind == "light" then
        defense.setDevice(device.id, action.on)
        touched = touched + 1
      end
    end
    if touched == 0 then
      history[#history + 1] = { who = "aria",
        text = "You have no lights set up. Add one in the Defense app." }
    end
  end
end

-------------------------------------------------------------------- asking --

local function say(lines)
  for _, line in ipairs(lines) do
    history[#history + 1] = { who = "aria", text = line }
  end
end

local function ask(text)
  text = util.trim(text)
  if text == "" then return end
  history[#history + 1] = { who = "you", text = text }
  askEntry:setText("", true)

  local lines, action = aria.ask(text, buildContext())
  say(lines)
  perform(action)

  while #history > 120 do table.remove(history, 1) end
  conversation:scrollToEnd()
  app:queueDraw()
end

-------------------------------------------------------------------- menu ---

local function openMenu()
  app:menu(app.surface.w - 24, 2, {
    { label = "What can you do?", icon = "\4", action = function() ask("help") end },
    { label = "Status report", icon = "\4", action = function() ask("status") end },
    { label = "Give me a tip", icon = "\7", action = function() ask("tip") end },
    { separator = true },
    { label = "Clear this chat", icon = "\233", action = function()
        history = {}
        say(aria.greeting())
        conversation:scrollToEnd()
        app:queueDraw()
      end },
    { label = "Forget about me", icon = "\215", destructive = true, action = function()
        app:confirm({
          title = "Forget everything?",
          message = "Aria will forget your name and what you usually ask about.",
          acceptLabel = "Forget",
          destructive = true,
          onAccept = function()
            aria.forget()
            app:notify("Memory cleared")
          end,
        })
      end },
  }, 24)
end

------------------------------------------------------------------ wiring ---

askEntry:connect("activate", function(_, text) ask(text) end)
menuButton:connect("clicked", openMenu)

app:accel("ctrl+l", function()
  history = {}
  say(aria.greeting())
  conversation:scrollToEnd()
  app:queueDraw()
end)

app.onEvent = function(name, ...)
  if name == "aurora_open" then
    local question = select(1, ...)
    if question then ask(tostring(question)) end
  end
end

aria.load()
say(aria.greeting())
conversation:scrollToEnd()

if args[1] then
  ask(table.concat(args, " "))
end

app:setFocus(askEntry)
app:run()
