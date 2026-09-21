--[[ aurora.svc.messages ----------------------------------------------------
     Chat storage and delivery.

     This runs as a service so messages still arrive when the Messages window
     is closed: they land in the conversation log on disk and raise a desktop
     notification.  The app reads the same module, so it sees history and live
     traffic through one code path.
----------------------------------------------------------------------------]]

local util = arequire("lib.util")
local log  = arequire("kernel.log")
local net  = arequire("svc.net")

local messages = {}

messages.DIR = "/home/.messages"
messages.MAX_PER_PEER = 200

messages.unread = {}       -- peerId -> count
messages.listeners = {}    -- pids that want live updates

local function pathFor(peerId)
  return fs.combine(messages.DIR, tostring(peerId) .. ".log")
end

function messages.ensure()
  if not fs.exists(messages.DIR) then pcall(fs.makeDir, messages.DIR) end
end

--------------------------------------------------------------- storage -----

function messages.conversation(peerId)
  local stored = util.readTable(pathFor(peerId), nil)
  if type(stored) ~= "table" then return {} end
  return stored
end

function messages.append(peerId, entry)
  messages.ensure()
  local conversation = messages.conversation(peerId)
  conversation[#conversation + 1] = entry
  while #conversation > messages.MAX_PER_PEER do table.remove(conversation, 1) end
  util.writeTable(pathFor(peerId), conversation)
  return conversation
end

function messages.clear(peerId)
  pcall(fs.delete, pathFor(peerId))
  messages.unread[tostring(peerId)] = nil
end

function messages.unreadCount(peerId)
  return messages.unread[tostring(peerId)] or 0
end

function messages.totalUnread()
  local total = 0
  for _, n in pairs(messages.unread) do total = total + n end
  return total
end

function messages.markRead(peerId)
  messages.unread[tostring(peerId)] = nil
end

--- Conversations that exist on disk, newest activity first.
function messages.threads()
  messages.ensure()
  local out = {}
  local ok, names = pcall(fs.list, messages.DIR)
  if not ok then return out end
  for _, name in ipairs(names) do
    local id = tonumber(name:match("^(%d+)%.log$"))
    if id then
      local conversation = messages.conversation(id)
      local last = conversation[#conversation]
      local peer = net.peers[tostring(id)]
      out[#out + 1] = {
        id = id,
        name = (peer and peer.name) or ("computer-" .. id),
        last = last,
        unread = messages.unreadCount(id),
        count = #conversation,
      }
    end
  end
  table.sort(out, function(a, b)
    local at = a.last and a.last.ts or 0
    local bt = b.last and b.last.ts or 0
    return at > bt
  end)
  return out
end

----------------------------------------------------------------- sending ---

--- Send a message.  Returns true, or false plus a reason.
function messages.send(peerId, text)
  text = util.trim(tostring(text or ""))
  if text == "" then return false, "nothing to send" end
  local ok, err = net.send(peerId, "chat", { text = text })
  if not ok then return false, err or "could not send" end
  messages.append(peerId, {
    from = os.getComputerID(),
    mine = true,
    text = text,
    ts = os.epoch("utc"),
    clock = util.clock(),
  })
  messages.notifyListeners(peerId)
  return true
end

function messages.notifyListeners(peerId)
  local sched = arequire("kernel.sched")
  for _, pid in ipairs(messages.listeners) do
    sched.post(pid, "aurora_messages", peerId)
  end
end

function messages.listen(pid)
  for _, existing in ipairs(messages.listeners) do
    if existing == pid then return end
  end
  table.insert(messages.listeners, pid)
end

function messages.unlisten(pid)
  util.remove(messages.listeners, pid)
end

---------------------------------------------------------------- service ----

function messages.receive(sender, data, senderName)
  local text = data and data.text
  if type(text) ~= "string" or text == "" then return end
  messages.append(sender, {
    from = sender,
    mine = false,
    text = text,
    ts = os.epoch("utc"),
    clock = util.clock(),
  })
  local key = tostring(sender)
  messages.unread[key] = (messages.unread[key] or 0) + 1
  messages.notifyListeners(sender)

  local desktop = arequire("shell.desktop")
  desktop.notify(senderName or ("computer-" .. sender), util.ellipsis(text, 28))
  log.info("messages", ("message from %s"):format(tostring(sender)))
end

--- The service body: subscribe, then park on incoming chat frames.
function messages.service()
  messages.ensure()
  net.subscribe("chat", aurora.pid)
  while true do
    local event, kind, sender, data, name = os.pullEvent("aurora_net")
    if kind == "chat" then
      pcall(messages.receive, sender, data, name)
    end
  end
end

return messages
