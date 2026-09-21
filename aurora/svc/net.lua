--[[ aurora.svc.net ----------------------------------------------------------
     Aurora's secure network.

     Everything that leaves this computer -- chat, web pages, defense alerts --
     goes out as an encrypted, authenticated, replay-protected frame over
     rednet.  Computers that share a network key can talk; anyone else with a
     modem on the same channel sees hex.

     Frames look like this on the wire:

       { v = 1, from = 7, name = "base", to = 12, ts = ..., nonce = "a1b2...",
         body = "<hex ciphertext>", mac = "<hex>" }

     `body` decrypts to a serialised { kind = "chat", data = {...} }.
----------------------------------------------------------------------------]]

local util    = arequire("lib.util")
local crypto  = arequire("lib.crypto")
local log     = arequire("kernel.log")
local devices = arequire("kernel.devices")

local net = {}

net.PROTOCOL = "aurora"
net.CONFIG = "/aurora/etc/net.cfg"
net.PEERS = "/aurora/var/peers.cfg"
net.VERSION = 1

net.open = false
net.modem = nil
net.key = nil
net.keyName = "aurora"
net.subscribers = {}       -- kind -> { pid, ... }
net.peers = {}             -- id -> { id, name, lastSeen, rtt }
net.seenNonces = {}
net.nonceOrder = {}
net.stats = { sent = 0, received = 0, rejected = 0 }

local MAX_NONCES = 256
local PEER_TIMEOUT = 90     -- seconds before a peer is considered offline

------------------------------------------------------------------- config ---

function net.loadConfig()
  local cfg = util.readTable(net.CONFIG, nil) or {}
  net.keyName = cfg.key or "aurora"
  net.autoOpen = cfg.autoOpen ~= false
  net.displayName = cfg.name or os.getComputerLabel() or ("computer-" .. os.getComputerID())
  net.key = crypto.deriveKey(net.keyName)
  net.peers = util.readTable(net.PEERS, {}) or {}
  return cfg
end

function net.saveConfig()
  util.writeTable(net.CONFIG, {
    key = net.keyName,
    autoOpen = net.autoOpen ~= false,
    name = net.displayName,
  })
end

--- Change the shared network key.  Every computer on your network needs the
--- same one; the fingerprint lets you check without showing the key.
function net.setKey(passphrase)
  net.keyName = tostring(passphrase or "aurora")
  net.key = crypto.deriveKey(net.keyName)
  net.saveConfig()
  log.info("net", "network key changed, fingerprint " .. net.fingerprint())
  return net.fingerprint()
end

function net.setName(name)
  net.displayName = util.trim(tostring(name or ""))
  if net.displayName == "" then
    net.displayName = os.getComputerLabel() or ("computer-" .. os.getComputerID())
  end
  net.saveConfig()
end

function net.fingerprint()
  return crypto.fingerprint(net.key or crypto.deriveKey(net.keyName))
end

------------------------------------------------------------------- modem ----

function net.modems()
  return devices.byClass("network")
end

--- Open the first available modem.  Returns true, or false plus a reason.
function net.start()
  if net.open and net.modem and rednet.isOpen(net.modem) then return true end
  local list = net.modems()
  if #list == 0 then
    net.open = false
    return false, "no modem attached"
  end
  for _, record in ipairs(list) do
    local ok = pcall(rednet.open, record.name)
    if ok and rednet.isOpen(record.name) then
      net.modem = record.name
      net.open = true
      log.info("net", "online via " .. record.name)
      net.announce()
      return true
    end
  end
  net.open = false
  return false, "could not open a modem"
end

function net.stop()
  if net.modem and rednet.isOpen(net.modem) then
    pcall(rednet.close, net.modem)
  end
  net.open = false
  log.info("net", "offline")
end

function net.status()
  if not net.open then
    return #net.modems() == 0 and "no modem" or "offline"
  end
  return "online"
end

-------------------------------------------------------------------- frames --

local function rememberNonce(nonce)
  net.seenNonces[nonce] = true
  net.nonceOrder[#net.nonceOrder + 1] = nonce
  if #net.nonceOrder > MAX_NONCES then
    local oldest = table.remove(net.nonceOrder, 1)
    net.seenNonces[oldest] = nil
  end
end

local function macInput(frame)
  return table.concat({
    tostring(frame.v), tostring(frame.from), tostring(frame.to or ""),
    tostring(frame.ts), frame.nonce, frame.body,
  }, "|")
end

local function buildFrame(target, kind, data)
  local inner = textutils.serialise({ kind = kind, data = data })
  local frame = {
    v = net.VERSION,
    from = os.getComputerID(),
    name = net.displayName,
    to = target,
    ts = os.epoch("utc"),
    nonce = crypto.token(12),
    body = crypto.encrypt(inner, net.key),
  }
  frame.mac = crypto.mac(macInput(frame), net.key)
  return frame
end

--- Validate and open a frame.  Returns kind, data, or nil plus a reason.
function net.unpack(frame)
  if type(frame) ~= "table" then return nil, "not a frame" end
  if frame.v ~= net.VERSION then return nil, "wrong protocol version" end
  if type(frame.nonce) ~= "string" or type(frame.body) ~= "string"
     or type(frame.mac) ~= "string" then
    return nil, "malformed frame"
  end
  if net.seenNonces[frame.nonce] then return nil, "replayed frame" end
  if not crypto.equal(frame.mac, crypto.mac(macInput(frame), net.key)) then
    return nil, "bad signature (different network key?)"
  end
  local plain = crypto.decrypt(frame.body, net.key)
  if not plain then return nil, "could not decrypt" end
  local inner = textutils.unserialise(plain)
  if type(inner) ~= "table" or type(inner.kind) ~= "string" then
    return nil, "bad payload"
  end
  rememberNonce(frame.nonce)
  return inner.kind, inner.data
end

--------------------------------------------------------------------- send ---

function net.send(target, kind, data)
  if not net.open then
    local ok, err = net.start()
    if not ok then return false, err end
  end
  local frame = buildFrame(target, kind, data)
  local ok = pcall(rednet.send, target, frame, net.PROTOCOL)
  if ok then net.stats.sent = net.stats.sent + 1 end
  return ok
end

function net.broadcast(kind, data)
  if not net.open then
    local ok, err = net.start()
    if not ok then return false, err end
  end
  local frame = buildFrame(nil, kind, data)
  local ok = pcall(rednet.broadcast, frame, net.PROTOCOL)
  if ok then net.stats.sent = net.stats.sent + 1 end
  return ok
end

--------------------------------------------------------------- subscribers --

--- Subscribe a process to a message kind.  When a frame of that kind arrives
--- the process receives an "aurora_net" event: kind, senderId, data, name.
function net.subscribe(kind, pid)
  net.subscribers[kind] = net.subscribers[kind] or {}
  for _, existing in ipairs(net.subscribers[kind]) do
    if existing == pid then return end
  end
  table.insert(net.subscribers[kind], pid)
end

function net.unsubscribe(kind, pid)
  local list = net.subscribers[kind]
  if not list then return end
  util.remove(list, pid)
end

function net.unsubscribeAll(pid)
  for _, list in pairs(net.subscribers) do util.remove(list, pid) end
end

local function deliver(kind, sender, data, name)
  local sched = arequire("kernel.sched")
  for _, pid in ipairs(net.subscribers[kind] or {}) do
    sched.post(pid, "aurora_net", kind, sender, data, name)
  end
  for _, pid in ipairs(net.subscribers["*"] or {}) do
    sched.post(pid, "aurora_net", kind, sender, data, name)
  end
end

-------------------------------------------------------------------- peers ---

function net.notePeer(id, name)
  local peer = net.peers[tostring(id)] or { id = id }
  peer.id = id
  peer.name = name or peer.name or ("computer-" .. id)
  peer.lastSeen = os.clock()
  net.peers[tostring(id)] = peer
end

function net.peerList()
  local out = {}
  for _, peer in pairs(net.peers) do
    out[#out + 1] = {
      id = peer.id,
      name = peer.name,
      lastSeen = peer.lastSeen,
      online = peer.lastSeen ~= nil and (os.clock() - peer.lastSeen) < PEER_TIMEOUT,
    }
  end
  table.sort(out, function(a, b)
    if a.online ~= b.online then return a.online end
    return (a.name or ""):lower() < (b.name or ""):lower()
  end)
  return out
end

function net.savePeers()
  local slim = {}
  for key, peer in pairs(net.peers) do
    slim[key] = { id = peer.id, name = peer.name }
  end
  util.writeTable(net.PEERS, slim)
end

function net.announce()
  net.broadcast("net.hello", { name = net.displayName })
end

function net.forgetPeers()
  net.peers = {}
  net.savePeers()
end

------------------------------------------------------------------ handling --

--- Handle one rednet_message event.  Returns true when it was ours.
function net.handle(sender, message, protocol)
  if protocol ~= net.PROTOCOL then return false end
  local kind, data = net.unpack(message)
  if not kind then
    net.stats.rejected = net.stats.rejected + 1
    log.debug("net", ("dropped a frame from %s: %s"):format(tostring(sender), tostring(data)))
    return true
  end
  net.stats.received = net.stats.received + 1
  net.notePeer(sender, message.name)

  if kind == "net.hello" then
    -- answer directly so the newcomer learns about us too
    net.send(sender, "net.here", { name = net.displayName })
  elseif kind == "net.here" then
    net.savePeers()
  end

  deliver(kind, sender, data, message.name)
  return true
end

------------------------------------------------------------------ service ---

--- The networking service body, run as an Aurora process.
function net.service()
  net.loadConfig()
  if net.autoOpen ~= false then net.start() end

  local announceTimer = os.startTimer(30)
  while true do
    local event = table.pack(os.pullEvent())
    if event[1] == "rednet_message" then
      pcall(net.handle, event[2], event[3], event[4])
    elseif event[1] == "timer" and event[2] == announceTimer then
      announceTimer = os.startTimer(30)
      if net.open then
        pcall(net.announce)
        net.savePeers()
      elseif net.autoOpen ~= false then
        pcall(net.start)
      end
    elseif event[1] == "peripheral" or event[1] == "peripheral_detach" then
      if net.autoOpen ~= false and not net.open then pcall(net.start) end
    end
  end
end

--- Ask a peer for something and wait for the matching reply.
--- Runs inside the calling process, so it blocks only that window.
--- @return data, senderId  or nil, error
function net.request(target, kind, data, replyKind, timeout)
  timeout = timeout or 3
  local sched = arequire("kernel.sched")
  local pid = aurora and aurora.pid
  if not pid then return nil, "no process context" end

  net.subscribe(replyKind, pid)
  local ok, err = net.send(target, kind, data)
  if not ok then
    net.unsubscribe(replyKind, pid)
    return nil, err or "could not send"
  end

  local deadline = os.startTimer(timeout)
  while true do
    local event = table.pack(os.pullEvent())
    if event[1] == "aurora_net" and event[2] == replyKind and event[3] == target then
      os.cancelTimer(deadline)
      net.unsubscribe(replyKind, pid)
      return event[4], event[3]
    elseif event[1] == "timer" and event[2] == deadline then
      net.unsubscribe(replyKind, pid)
      return nil, "no reply from computer " .. tostring(target)
    end
  end
end

return net
