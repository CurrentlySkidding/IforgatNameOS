--[[ Messages ---------------------------------------------------------------
     Encrypted chat over the Aurora secure network.

     Two screens rather than a split view, because a 40-column window has no
     room for both: a list of conversations, and one conversation at a time.
----------------------------------------------------------------------------]]

local args     = { ... }
local App      = arequire("ui.app")
local base     = arequire("ui.widget")
local W        = arequire("ui.widgets")
local theme    = arequire("gfx.theme")
local util     = arequire("lib.util")
local net      = arequire("svc.net")
local messages = arequire("svc.messages")

local app = App({ title = "Messages" })

local state = { peer = nil, peerName = nil }

------------------------------------------------------------------- chrome --

local titleLabel = W.Label({ text = " Messages" })
titleLabel.hexpand = true

local backButton = W.IconButton({ icon = "\17", width = 3 })
backButton.visible = false
local menuButton = W.IconButton({ icon = "\7", width = 3 })

local toolbar = W.Toolbar({ spacing = 0 })
toolbar:add(backButton)
toolbar:add(titleLabel)
toolbar:add(menuButton)

----------------------------------------------------------- conversations ---

local threadList = W.ListBox({ rows = {}, showSubtitles = true })
threadList.vexpand = true
threadList.hexpand = true

local threadEmpty = W.StatusPage({
  title = "No conversations",
  description = "Pick a computer from the menu to start talking. "
             .. "They need the same network key as you.",
  icon = { colour = theme.c.success, glyph = "M" },
})

local threadScroller = base.Scrolled({})
threadScroller.hexpand, threadScroller.vexpand = true, true
threadScroller:setChild(threadList)

--------------------------------------------------------------- one thread --

--- The transcript is a custom widget: chat bubbles wrap and alternate sides,
--- which no stock list widget does.
local Transcript = util.class(base.Widget)

function Transcript:init()
  base.Widget.init(self, {})
  self.hexpand, self.vexpand = true, true
  self.entries = {}
  self.scroll = 0
end

function Transcript:setEntries(entries)
  self.entries = entries or {}
  self:scrollToEnd()
  self:invalidate()
end

--- Lay the transcript out into display rows, newest last.
function Transcript:rows()
  local width = math.max(8, self.w - 2)
  local rows = {}
  for _, entry in ipairs(self.entries) do
    local lines = util.wrap(entry.text, width - 2)
    for i, line in ipairs(lines) do
      rows[#rows + 1] = {
        text = line,
        mine = entry.mine,
        first = i == 1,
        last = i == #lines,
        clock = entry.clock,
      }
    end
  end
  return rows
end

function Transcript:scrollToEnd()
  self.scroll = math.max(0, #self:rows() - self.h)
end

function Transcript:draw(s)
  local c = theme.c
  s:fill(self.x, self.y, self.w, self.h, " ", c.text, c.view)
  local rows = self:rows()
  local maxScroll = math.max(0, #rows - self.h)
  if self.scroll > maxScroll then self.scroll = maxScroll end

  if #rows == 0 then
    s:writeCentered(self.y + math.floor(self.h / 2),
                    "Say something", c.dim, c.view, self.x, self.w)
    return
  end

  for i = 1, self.h do
    local row = rows[self.scroll + i]
    if row then
      local y = self.y + i - 1
      local bg = row.mine and c.accent or c.card
      local fg = row.mine and c.onAccent or c.text
      local width = #row.text + 2
      local x = row.mine and (self.x + self.w - width - 1) or (self.x + 1)
      s:fill(x, y, width, 1, " ", fg, bg)
      s:write(x + 1, y, row.text, fg, bg)
      -- notch the bubble ends so they read as speech bubbles
      s:roundCorner(x, y, row.first and "tl" or "bl", bg, c.view)
      s:roundCorner(x + width - 1, y, row.last and "br" or "tr", bg, c.view)
    end
  end
end

function Transcript:onMouse(kind, button)
  if kind == "mouse_scroll" then
    self.scroll = util.clamp(self.scroll + button * 2, 0,
                             math.max(0, #self:rows() - self.h))
    self:invalidate()
    return true
  end
  return false
end

local transcript = Transcript()

local composeEntry = W.Entry({ placeholder = "Message", icon = "\4" })
composeEntry.hexpand = true

local composeRow = base.Box({ orientation = "horizontal", spacing = 0 })
composeRow.hexpand = true
composeRow.background = theme.c.window
composeRow:add(composeEntry)

local threadPage = base.Box({ orientation = "vertical", spacing = 0 })
threadPage.hexpand, threadPage.vexpand = true, true
threadPage:add(transcript)
threadPage:add(composeRow)

local pages = base.Stack()
pages.hexpand, pages.vexpand = true, true
pages:addPage("list", threadScroller)
pages:addPage("empty", threadEmpty)
pages:addPage("thread", threadPage)

local root = base.Box({ orientation = "vertical", spacing = 0 })
root.hexpand, root.vexpand = true, true
root:add(toolbar)
root:add(pages)
app:setRoot(root)

------------------------------------------------------------------ helpers --

local function nameFor(peerId)
  local peer = net.peers[tostring(peerId)]
  return (peer and peer.name) or ("computer-" .. peerId)
end

local function showList()
  state.peer = nil
  backButton.visible = false
  titleLabel:setText(" Messages" ..
    (net.status() == "online" and "" or "  (" .. net.status() .. ")"))
  aurora.setTitle("Messages")

  local threads = messages.threads()
  if #threads == 0 then
    pages:setPage("empty")
  else
    local rows = {}
    for _, thread in ipairs(threads) do
      local preview = thread.last and thread.last.text or "No messages yet"
      if thread.last and thread.last.mine then preview = "You: " .. preview end
      local peer = net.peers[tostring(thread.id)]
      local online = peer and peer.lastSeen and (os.clock() - peer.lastSeen) < 90
      rows[#rows + 1] = {
        title = thread.name,
        subtitle = util.ellipsis(preview, 30),
        icon = { char = "\7", colour = online and theme.c.success or theme.c.dim },
        trailing = thread.unread > 0 and tostring(thread.unread) or nil,
        peerId = thread.id,
      }
    end
    threadList:setRows(rows, true)
    pages:setPage("list")
  end
  app:queueLayout()
end

local function showThread(peerId)
  state.peer = peerId
  state.peerName = nameFor(peerId)
  messages.markRead(peerId)
  backButton.visible = true
  titleLabel:setText(" " .. util.ellipsis(state.peerName, 22))
  aurora.setTitle(state.peerName)
  transcript:setEntries(messages.conversation(peerId))
  pages:setPage("thread")
  app:queueLayout()
  app:setFocus(composeEntry)
end

local function refresh()
  if state.peer then
    transcript:setEntries(messages.conversation(state.peer))
    messages.markRead(state.peer)
    app:queueDraw()
  else
    showList()
  end
end

local function send()
  local text = util.trim(composeEntry.text)
  if text == "" or not state.peer then return end
  local ok, err = messages.send(state.peer, text)
  if not ok then
    app:notify(err or "Could not send", "error")
    return
  end
  composeEntry:setText("", true)
  refresh()
end

-------------------------------------------------------------------- menu ---

local function pickPeer()
  local items = {}
  for _, peer in ipairs(net.peerList()) do
    items[#items + 1] = {
      label = util.ellipsis(peer.name, 16) .. (peer.online and "" or " (off)"),
      icon = "\7",
      action = function() showThread(peer.id) end,
    }
  end
  if #items == 0 then
    items[#items + 1] = { label = "Nobody found yet", icon = "\4", disabled = true }
  end
  items[#items + 1] = { separator = true }
  items[#items + 1] = { label = "Enter an ID", icon = "\4", action = function()
    app:prompt({
      title = "Computer ID",
      message = "Which computer do you want to message?",
      text = "",
      onAccept = function(text)
        local id = tonumber(util.trim(text))
        if id then showThread(id) else app:notify("That is not an ID", "error") end
      end,
    })
  end }
  app:menu(2, 2, items, 22)
end

local function openMenu()
  app:menu(app.surface.w - 24, 2, {
    { label = "New conversation", icon = "\4", action = pickPeer },
    { label = "Look for computers", icon = "\15", action = function()
        local ok, err = net.start()
        if ok then
          net.announce()
          app:notify("Looking for computers\133")
        else
          app:notify(err or "No modem", "error")
        end
      end },
    { separator = true },
    { label = "Delete this chat", icon = "\233", destructive = true,
      disabled = state.peer == nil, action = function()
        local peer = state.peer
        app:confirm({
          title = "Delete this conversation?",
          message = "The messages on this computer will be removed.",
          acceptLabel = "Delete",
          destructive = true,
          onAccept = function()
            messages.clear(peer)
            showList()
          end,
        })
      end },
    { label = "Network settings", icon = "\4", action = function()
        arequire("svc.apps").launch("settings", { "network" })
      end },
  }, 24)
end

------------------------------------------------------------------ wiring ---

backButton:connect("clicked", showList)
menuButton:connect("clicked", openMenu)
threadList:connect("activate", function(_, index, row)
  if row and row.peerId then showThread(row.peerId) end
end)
composeEntry:connect("activate", send)

app:accel("ctrl+n", pickPeer)
app:accel("escape", function() if state.peer then showList() end end)

app.onEvent = function(name, ...)
  if name == "aurora_messages" then
    refresh()
  elseif name == "aurora_open" then
    local id = tonumber(select(1, ...))
    if id then showThread(id) end
  end
end

app.onClose = function()
  messages.unlisten(aurora.pid)
  return true
end

messages.listen(aurora.pid)
net.start()

if args[1] and tonumber(args[1]) then
  showThread(tonumber(args[1]))
else
  showList()
end

app:run()
