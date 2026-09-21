--[[ tools/craftos.lua -------------------------------------------------------
     A small CC:Tweaked emulator used to boot and exercise Aurora outside
     Minecraft.  It implements just enough of CraftOS -- fs, term (with
     redirects), os events and timers, colours, keys, textutils, peripheral --
     that the real, unmodified Aurora sources run on top of it.

     Not a general-purpose emulator: it exists so the test harness can boot
     the OS, click things and read the screen back.
----------------------------------------------------------------------------]]

local emu = {}

---------------------------------------------------------------- utilities ---

local function normalise(path)
  path = tostring(path or ""):gsub("\\", "/")
  local parts = {}
  for piece in path:gmatch("[^/]+") do
    if piece == ".." then
      table.remove(parts)
    elseif piece ~= "." then
      parts[#parts + 1] = piece
    end
  end
  return table.concat(parts, "/")
end

------------------------------------------------------------------- colours --

local colours = {}
local COLOUR_NAMES = {
  "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "grey",
  "lightGrey", "cyan", "purple", "blue", "brown", "green", "red", "black",
}
for i, name in ipairs(COLOUR_NAMES) do
  colours[name] = 2 ^ (i - 1)
end
colours.gray = colours.grey
colours.lightGray = colours.lightGrey
colours.combine = function(...) local n = 0 for _, v in ipairs({...}) do n = n + v end return n end

local colors = {}
for k, v in pairs(colours) do colors[k] = v end
colors.gray = colours.grey
colors.lightGray = colours.lightGrey

---------------------------------------------------------------------- keys --

local keys = {}
local KEY_LIST = {
  one = 2, two = 3, three = 4, four = 5, five = 6, six = 7, seven = 8,
  eight = 9, nine = 10, zero = 11, minus = 12, equals = 13, backspace = 14,
  tab = 15, q = 16, w = 17, e = 18, r = 19, t = 20, y = 21, u = 22, i = 23,
  o = 24, p = 25, leftBracket = 26, rightBracket = 27, enter = 28,
  leftCtrl = 29, a = 30, s = 31, d = 32, f = 33, g = 34, h = 35, j = 36,
  k = 37, l = 38, semicolon = 39, apostrophe = 40, grave = 41, leftShift = 42,
  backslash = 43, z = 44, x = 45, c = 46, v = 47, b = 48, n = 49, m = 50,
  comma = 51, period = 52, slash = 53, rightShift = 54, multiply = 55,
  leftAlt = 56, space = 57, capsLock = 58, f1 = 59, f2 = 60, f3 = 61, f4 = 62,
  f5 = 63, f6 = 64, f7 = 65, f8 = 66, f9 = 67, f10 = 68, numLock = 69,
  scrollLock = 70, numPad7 = 71, numPad8 = 72, numPad9 = 73, numPadSubtract = 74,
  numPad4 = 75, numPad5 = 76, numPad6 = 77, numPadAdd = 78, numPad1 = 79,
  numPad2 = 80, numPad3 = 81, numPad0 = 82, numPadDecimal = 83, f11 = 87,
  f12 = 88, numPadEnter = 156, rightCtrl = 157, numPadDivide = 181,
  rightAlt = 184, pause = 197, home = 199, up = 200, pageUp = 201, left = 203,
  right = 205, ["end"] = 207, down = 208, pageDown = 209, insert = 210,
  delete = 211, leftSuper = 219, rightSuper = 220, escape = 1,
}
local keyNames = {}
for name, code in pairs(KEY_LIST) do
  keys[name] = code
  keyNames[code] = name
end
keys.getName = function(code) return keyNames[code] end

-------------------------------------------------------------------- vfs -----

local vfs = { nodes = {} }   -- path -> { dir = bool, data = string, ro = bool }

vfs.nodes[""] = { dir = true }

local function parentOf(path)
  local dir = path:match("^(.*)/[^/]*$")
  return dir or ""
end

local function ensureDir(path)
  path = normalise(path)
  if path == "" then return end
  if vfs.nodes[path] and vfs.nodes[path].dir then return end
  ensureDir(parentOf(path))
  vfs.nodes[path] = { dir = true }
end

function vfs.write(path, data, readOnly)
  path = normalise(path)
  ensureDir(parentOf(path))
  vfs.nodes[path] = { dir = false, data = data, ro = readOnly or false }
end

function vfs.mkdir(path)
  ensureDir(path)
end

emu.vfs = vfs

local fs = {}

function fs.combine(...)
  local parts = {}
  for _, piece in ipairs({ ... }) do parts[#parts + 1] = tostring(piece) end
  return normalise(table.concat(parts, "/"))
end

function fs.getDir(path) return parentOf(normalise(path)) end
function fs.getName(path)
  local name = normalise(path):match("[^/]+$")
  return name or "root"
end

function fs.exists(path) return vfs.nodes[normalise(path)] ~= nil end
function fs.isDir(path)
  local node = vfs.nodes[normalise(path)]
  return node ~= nil and node.dir == true
end
function fs.isReadOnly(path)
  local node = vfs.nodes[normalise(path)]
  if node then return node.ro == true end
  local dir = parentOf(normalise(path))
  local parent = vfs.nodes[dir]
  return parent ~= nil and parent.ro == true
end

function fs.list(path)
  path = normalise(path)
  if not fs.isDir(path) then error("Not a directory: " .. path, 2) end
  local seen, out = {}, {}
  local prefix = path == "" and "" or (path .. "/")
  for node in pairs(vfs.nodes) do
    if node ~= path and node:sub(1, #prefix) == prefix then
      local rest = node:sub(#prefix + 1)
      local name = rest:match("^[^/]+")
      if name and not seen[name] then
        seen[name] = true
        out[#out + 1] = name
      end
    end
  end
  table.sort(out)
  return out
end

function fs.getSize(path)
  local node = vfs.nodes[normalise(path)]
  if not node then return 0 end
  return node.dir and 0 or #(node.data or "")
end

function fs.makeDir(path) ensureDir(path) end

function fs.delete(path)
  path = normalise(path)
  local prefix = path .. "/"
  for node in pairs(vfs.nodes) do
    if node == path or node:sub(1, #prefix) == prefix then
      vfs.nodes[node] = nil
    end
  end
end

function fs.move(from, to)
  from, to = normalise(from), normalise(to)
  local node = vfs.nodes[from]
  if not node then error("No such file: " .. from, 2) end
  local prefix = from .. "/"
  local moves = {}
  for key, value in pairs(vfs.nodes) do
    if key == from then
      moves[to] = value
    elseif key:sub(1, #prefix) == prefix then
      moves[to .. "/" .. key:sub(#prefix + 1)] = value
    end
  end
  fs.delete(from)
  ensureDir(parentOf(to))
  for key, value in pairs(moves) do vfs.nodes[key] = value end
end

function fs.copy(from, to)
  from, to = normalise(from), normalise(to)
  local node = vfs.nodes[from]
  if not node then error("No such file: " .. from, 2) end
  local prefix = from .. "/"
  ensureDir(parentOf(to))
  for key, value in pairs(vfs.nodes) do
    if key == from then
      vfs.nodes[to] = { dir = value.dir, data = value.data }
    elseif key:sub(1, #prefix) == prefix then
      vfs.nodes[to .. "/" .. key:sub(#prefix + 1)] = { dir = value.dir, data = value.data }
    end
  end
end

function fs.getFreeSpace() return 512000 end
function fs.getCapacity() return 1000000 end

function fs.open(path, mode)
  path = normalise(path)
  if mode == "r" then
    local node = vfs.nodes[path]
    if not node or node.dir then return nil end
    local pos = 1
    local data = node.data or ""
    return {
      readAll = function() local rest = data:sub(pos) pos = #data + 1 return rest end,
      readLine = function()
        if pos > #data then return nil end
        local stop = data:find("\n", pos, true)
        local line
        if stop then line = data:sub(pos, stop - 1) pos = stop + 1
        else line = data:sub(pos) pos = #data + 1 end
        return line
      end,
      read = function(n)
        if pos > #data then return nil end
        n = n or 1
        local chunk = data:sub(pos, pos + n - 1)
        pos = pos + n
        return chunk
      end,
      close = function() end,
    }
  elseif mode == "w" or mode == "a" then
    if fs.isReadOnly(path) then return nil end
    local existing = (mode == "a" and vfs.nodes[path] and vfs.nodes[path].data) or ""
    local buffer = { existing }
    return {
      write = function(text) buffer[#buffer + 1] = tostring(text) end,
      writeLine = function(text) buffer[#buffer + 1] = tostring(text) .. "\n" end,
      flush = function() vfs.write(path, table.concat(buffer)) end,
      close = function() vfs.write(path, table.concat(buffer)) end,
    }
  end
  return nil
end

function fs.find(pattern) return {} end
function fs.getDrive() return "hdd" end
function fs.complete() return {} end

-------------------------------------------------------------------- term ----

local function newTerminal(w, h)
  local t = { w = w, h = h, cx = 1, cy = 1, fg = colours.white, bg = colours.black,
              blink = false, palette = {} }
  t.text, t.fgs, t.bgs = {}, {}, {}
  local HEX = "0123456789abcdef"
  local toBlit = {}
  for i = 0, 15 do toBlit[2 ^ i] = HEX:sub(i + 1, i + 1) end
  t.toBlit = toBlit

  local function blank()
    for y = 1, h do
      t.text[y] = string.rep(" ", w)
      t.fgs[y] = string.rep("0", w)
      t.bgs[y] = string.rep("f", w)
    end
  end
  blank()

  local function splice(row, x, value)
    return row:sub(1, x - 1) .. value .. row:sub(x + #value)
  end

  function t.write(text)
    text = tostring(text)
    if t.cy < 1 or t.cy > h or #text == 0 then t.cx = t.cx + #text return end
    local x = t.cx
    if x < 1 then
      local cut = 2 - x
      if cut > #text then t.cx = t.cx + #text return end
      text = text:sub(cut)
      x = 1
    end
    if x + #text - 1 > w then text = text:sub(1, w - x + 1) end
    if #text > 0 then
      t.text[t.cy] = splice(t.text[t.cy], x, text)
      t.fgs[t.cy] = splice(t.fgs[t.cy], x, string.rep(toBlit[t.fg] or "0", #text))
      t.bgs[t.cy] = splice(t.bgs[t.cy], x, string.rep(toBlit[t.bg] or "f", #text))
    end
    t.cx = t.cx + #tostring(text)
  end

  function t.blit(text, fg, bg)
    if #text ~= #fg or #text ~= #bg then error("Arguments must be the same length", 2) end
    if t.cy < 1 or t.cy > h then t.cx = t.cx + #text return end
    local x = t.cx
    if x < 1 then
      local cut = 2 - x
      if cut > #text then t.cx = t.cx + #text return end
      text, fg, bg = text:sub(cut), fg:sub(cut), bg:sub(cut)
      x = 1
    end
    if x + #text - 1 > w then
      local keep = w - x + 1
      if keep <= 0 then t.cx = t.cx + #text return end
      text, fg, bg = text:sub(1, keep), fg:sub(1, keep), bg:sub(1, keep)
    end
    t.text[t.cy] = splice(t.text[t.cy], x, text)
    t.fgs[t.cy] = splice(t.fgs[t.cy], x, fg)
    t.bgs[t.cy] = splice(t.bgs[t.cy], x, bg)
    t.cx = t.cx + #text
  end

  function t.clear() blank() end
  function t.clearLine()
    if t.cy >= 1 and t.cy <= h then
      t.text[t.cy] = string.rep(" ", w)
      t.fgs[t.cy] = string.rep(toBlit[t.fg] or "0", w)
      t.bgs[t.cy] = string.rep(toBlit[t.bg] or "f", w)
    end
  end
  function t.getCursorPos() return t.cx, t.cy end
  function t.setCursorPos(x, y) t.cx, t.cy = math.floor(x), math.floor(y) end
  function t.setCursorBlink(v) t.blink = v and true or false end
  function t.getCursorBlink() return t.blink end
  function t.getSize() return w, h end
  function t.isColour() return true end
  t.isColor = t.isColour
  function t.setTextColour(c) t.fg = c end
  t.setTextColor = t.setTextColour
  function t.setBackgroundColour(c) t.bg = c end
  t.setBackgroundColor = t.setBackgroundColour
  function t.getTextColour() return t.fg end
  t.getTextColor = t.getTextColour
  function t.getBackgroundColour() return t.bg end
  t.getBackgroundColor = t.getBackgroundColour
  function t.scroll(n)
    local newText, newFg, newBg = {}, {}, {}
    for y = 1, h do
      local from = y + n
      if from >= 1 and from <= h then
        newText[y], newFg[y], newBg[y] = t.text[from], t.fgs[from], t.bgs[from]
      else
        newText[y] = string.rep(" ", w)
        newFg[y] = string.rep(toBlit[t.fg] or "0", w)
        newBg[y] = string.rep(toBlit[t.bg] or "f", w)
      end
    end
    t.text, t.fgs, t.bgs = newText, newFg, newBg
  end
  function t.setPaletteColour(colour, r, g, b)
    if g == nil then t.palette[colour] = r
    else t.palette[colour] = math.floor(r * 255) * 65536
                             + math.floor(g * 255) * 256 + math.floor(b * 255) end
  end
  t.setPaletteColor = t.setPaletteColour
  function t.getPaletteColour(colour)
    local packed = t.palette[colour] or 0
    return math.floor(packed / 65536) % 256 / 255,
           math.floor(packed / 256) % 256 / 255, packed % 256 / 255
  end
  t.getPaletteColor = t.getPaletteColour
  function t.nativePaletteColour(colour) return t.getPaletteColour(colour) end
  t.nativePaletteColor = t.nativePaletteColour
  function t.setTextScale() end
  return t
end

emu.newTerminal = newTerminal

-------------------------------------------------------------------- build ---

--- Build a CraftOS environment.  Returns the sandbox globals table.
function emu.build(opts)
  opts = opts or {}
  local width = opts.width or 51
  local height = opts.height or 19

  local native = newTerminal(width, height)
  local current = native

  local term = {}
  local TERM_METHODS = {
    "write", "blit", "clear", "clearLine", "getCursorPos", "setCursorPos",
    "setCursorBlink", "getCursorBlink", "getSize", "scroll", "isColour", "isColor",
    "setTextColour", "setTextColor", "setBackgroundColour", "setBackgroundColor",
    "getTextColour", "getTextColor", "getBackgroundColour", "getBackgroundColor",
    "setPaletteColour", "setPaletteColor", "getPaletteColour", "getPaletteColor",
  }
  for _, name in ipairs(TERM_METHODS) do
    term[name] = function(...) return current[name](...) end
  end
  term.native = function() return native end
  term.current = function() return current end
  term.redirect = function(target)
    if type(target) ~= "table" then error("bad argument #1 to redirect", 2) end
    local previous = current
    current = target
    return previous
  end
  term.nativePaletteColour = function(colour) return native.nativePaletteColour(colour) end
  term.nativePaletteColor = term.nativePaletteColour

  ---------------------------------------------------------------- events ----

  local clock = 0
  local queue = {}
  local timers = {}
  local nextTimer = 1

  local os_api = {}
  function os_api.clock() return clock end
  function os_api.time() return (clock / 50) % 24 end
  function os_api.day() return math.floor(clock / 1200) end
  function os_api.epoch() return math.floor(clock * 1000) + 1700000000000 end
  function os_api.date(format)
    format = format or "%H:%M"
    local minutes = math.floor(clock / 60) % 60
    local hours = math.floor(clock / 3600) % 24
    local out = format:gsub("%%H", string.format("%02d", hours))
                      :gsub("%%M", string.format("%02d", minutes))
                      :gsub("%%S", string.format("%02d", math.floor(clock) % 60))
                      :gsub("%%a", "Mon"):gsub("%%d", "01"):gsub("%%b", "Jan")
    return out
  end
  function os_api.startTimer(seconds)
    local id = nextTimer
    nextTimer = nextTimer + 1
    timers[id] = clock + (tonumber(seconds) or 0)
    return id
  end
  function os_api.cancelTimer(id) timers[id] = nil end
  function os_api.queueEvent(...) queue[#queue + 1] = table.pack(...) end
  function os_api.pullEventRaw(filter)
    return coroutine.yield(filter)
  end
  function os_api.pullEvent(filter)
    local event = table.pack(coroutine.yield(filter))
    if event[1] == "terminate" then error("Terminated", 0) end
    return table.unpack(event, 1, event.n)
  end
  function os_api.sleep(seconds)
    local id = os_api.startTimer(seconds or 0)
    repeat
      local _, timerId = os_api.pullEvent("timer")
    until timerId == id
  end
  local computerId = opts.id or 7
  function os_api.getComputerID() return computerId end
  function os_api.computerID() return computerId end
  local label = opts.label or "aurora-dev"
  function os_api.getComputerLabel() return label end
  function os_api.setComputerLabel(value) label = value end
  function os_api.version() return "CraftOS 1.9" end
  function os_api.reboot() error("__emu_reboot__", 0) end
  function os_api.shutdown() error("__emu_shutdown__", 0) end

  ------------------------------------------------------------- textutils ----

  local textutils = {}
  local function serialiseValue(value, indent, seen)
    local t = type(value)
    if t == "number" or t == "boolean" or t == "nil" then return tostring(value) end
    if t == "string" then return string.format("%q", value) end
    if t == "table" then
      if seen[value] then return "nil --[[cycle]]" end
      seen[value] = true
      local parts = { "{\n" }
      local nextIndent = indent .. "  "
      for k, v in pairs(value) do
        local key
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then key = k .. " = "
        else key = "[" .. serialiseValue(k, nextIndent, seen) .. "] = " end
        parts[#parts + 1] = nextIndent .. key .. serialiseValue(v, nextIndent, seen) .. ",\n"
      end
      parts[#parts + 1] = indent .. "}"
      seen[value] = nil
      return table.concat(parts)
    end
    return "nil"
  end
  function textutils.serialise(value) return serialiseValue(value, "", {}) end
  textutils.serialize = textutils.serialise
  function textutils.unserialise(text)
    local chunk = load("return " .. tostring(text), "unserialise", "t", {})
    if not chunk then return nil end
    local ok, value = pcall(chunk)
    if not ok then return nil end
    return value
  end
  textutils.unserialize = textutils.unserialise
  function textutils.formatTime(time, twentyFour)
    local hours = math.floor(time)
    local minutes = math.floor((time - hours) * 60)
    return string.format("%02d:%02d", hours, minutes)
  end
  function textutils.slowPrint(text) print(text) end

  ------------------------------------------------------------ peripheral ----

  local peripherals = opts.peripherals or {}
  local peripheral = {}
  function peripheral.getNames()
    local out = {}
    for name in pairs(peripherals) do out[#out + 1] = name end
    table.sort(out)
    return out
  end
  function peripheral.getType(name)
    local p = peripherals[name]
    return p and p.type or nil
  end
  function peripheral.isPresent(name) return peripherals[name] ~= nil end
  function peripheral.wrap(name)
    local p = peripherals[name]
    return p and p.handle or nil
  end
  function peripheral.call(name, method, ...)
    local p = peripherals[name]
    if not p or not p.handle or not p.handle[method] then return nil end
    return p.handle[method](...)
  end
  function peripheral.find(kind)
    for name, p in pairs(peripherals) do
      if p.type == kind then return p.handle end
    end
    return nil
  end

  -- Forward declaration: rednet's closures capture this before the driver
  -- table below fills it in.
  local machine = {}

  ---------------------------------------------------------------- others ----

  -- rednet, wired to a Python-side bus so two emulated computers can really
  -- talk to each other.  Frames cross as serialised strings, exactly as they
  -- would over a modem.
  local openSides = {}
  local rednet = {}
  rednet.open = function(side) openSides[side or "back"] = true end
  rednet.close = function(side)
    if side then openSides[side] = nil else openSides = {} end
  end
  rednet.isOpen = function(side)
    if side then return openSides[side] == true end
    return next(openSides) ~= nil
  end
  rednet.send = function(id, message, protocol)
    if machine.onTransmit then
      machine.onTransmit(id, textutils.serialise(message), protocol or "")
    end
    return true
  end
  rednet.broadcast = function(message, protocol)
    if machine.onTransmit then
      machine.onTransmit(-1, textutils.serialise(message), protocol or "")
    end
    return true
  end
  rednet.receive = function() return nil end
  rednet.host = function() end
  rednet.unhost = function() end
  rednet.lookup = function() return nil end

  local parallel = {}
  function parallel.waitForAny(...)
    local routines = {}
    for _, fn in ipairs({ ... }) do routines[#routines + 1] = coroutine.create(fn) end
    local filters = {}
    local event = {}
    while true do
      for i, co in ipairs(routines) do
        if coroutine.status(co) ~= "dead" then
          if filters[i] == nil or filters[i] == event[1] or event[1] == "terminate" then
            local results = table.pack(coroutine.resume(co, table.unpack(event, 1, event.n or 0)))
            if not results[1] then error(results[2], 0) end
            filters[i] = results[2]
          end
          if coroutine.status(co) == "dead" then return i end
        end
      end
      event = table.pack(coroutine.yield())
    end
  end
  parallel.waitForAll = parallel.waitForAny

  local settings = {
    set = function() end, get = function(_, default) return default end,
    unset = function() end, save = function() end, load = function() end,
    define = function() end, getNames = function() return {} end,
  }

  ---------------------------------------------------------------- globals ---

  local env = {}
  env._G = env
  for _, name in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall",
                          "xpcall", "select", "setmetatable", "getmetatable",
                          "rawget", "rawset", "rawequal", "rawlen", "tonumber",
                          "tostring", "type", "unpack", "load", "loadstring",
                          "math", "string", "table", "coroutine", "os" }) do
    env[name] = _G[name]
  end
  env.os = setmetatable(os_api, { __index = {} })
  env.fs = fs
  env.term = term
  env.colours = colours
  env.colors = colors
  env.keys = keys
  env.textutils = textutils
  env.peripheral = peripheral
  env.rednet = rednet
  env.parallel = parallel
  env.settings = settings

  -- Redstone: an in-memory model of the six sides, so the defense system can
  -- actually be driven and tripped from a test.
  local rsOutput, rsInput = {}, {}
  local rsBundledOut, rsBundledIn = {}, {}
  local redstone = {}
  function redstone.getSides()
    return { "top", "bottom", "left", "right", "front", "back" }
  end
  function redstone.setOutput(side, on) rsOutput[side] = on and true or false end
  function redstone.getOutput(side) return rsOutput[side] == true end
  function redstone.getInput(side) return rsInput[side] == true end
  function redstone.setAnalogOutput(side, value)
    rsOutput[side] = (value or 0) > 0
  end
  function redstone.getAnalogOutput(side) return rsOutput[side] and 15 or 0 end
  function redstone.getAnalogInput(side) return rsInput[side] and 15 or 0 end
  function redstone.setBundledOutput(side, value) rsBundledOut[side] = value or 0 end
  function redstone.getBundledOutput(side) return rsBundledOut[side] or 0 end
  function redstone.getBundledInput(side) return rsBundledIn[side] or 0 end
  function redstone.testBundledInput(side, mask)
    return ((rsBundledIn[side] or 0) % (mask * 2)) >= mask
  end
  env.redstone = redstone
  env.rs = redstone

  --- Test hook: pretend something powered a side, and fire the event.
  function machine.setRedstoneInput(side, on)
    rsInput[side] = on and true or false
    queue[#queue + 1] = table.pack("redstone")
  end
  function machine.getRedstoneOutput(side) return rsOutput[side] == true end

  env.http = opts.http or nil
  -- CC:Tweaked ships bit32; modern Lua does not, so provide it here or the
  -- emulator would silently exercise a different code path than the game.
  env.bit32 = _G.bit32 or (function()
    local chunk = load([==[
      return {
        band = function(a, b) return (a & b) & 0xFFFFFFFF end,
        bor = function(a, b) return (a | b) & 0xFFFFFFFF end,
        bxor = function(a, b) return (a ~ b) & 0xFFFFFFFF end,
        bnot = function(a) return (~a) & 0xFFFFFFFF end,
        lshift = function(v, n) return (v << n) & 0xFFFFFFFF end,
        rshift = function(v, n) return (v & 0xFFFFFFFF) >> n end,
      }
    ]==])
    return chunk and chunk() or nil
  end)()
  env.table = setmetatable({ pack = table.pack, unpack = table.unpack,
                             insert = table.insert, remove = table.remove,
                             concat = table.concat, sort = table.sort }, nil)

  function env.print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local text = table.concat(parts, "\t")
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      local w, h = term.getSize()
      local _, y = term.getCursorPos()
      term.write(line)
      if y >= h then term.scroll(1) term.setCursorPos(1, h)
      else term.setCursorPos(1, y + 1) end
    end
  end
  env.write = function(text) term.write(text) end
  env.printError = function(...)
    term.setTextColour(colours.red)
    env.print(...)
    term.setTextColour(colours.white)
  end
  env.read = function() return "" end
  env.sleep = os_api.sleep
  env.loadfile = function(path, mode, fenv)
    local handle = fs.open(path, "r")
    if not handle then return nil, "File not found" end
    local data = handle.readAll()
    handle.close()
    return load(data, "@" .. path, "t", fenv or env)
  end
  env.dofile = function(path)
    local chunk, err = env.loadfile(path)
    if not chunk then error(err, 2) end
    return chunk()
  end
  os_api.run = function(fenv, path, ...)
    setmetatable(fenv, { __index = env })
    local chunk, err = env.loadfile(path, nil, fenv)
    if not chunk then
      env.printError(err)
      return false
    end
    local results = table.pack(pcall(chunk, ...))
    if not results[1] then
      env.printError(results[2])
      return false
    end
    return true
  end
  os_api.loadAPI = function() return false end

  ----------------------------------------------------------------- driver ---

  machine.env = env
  local _machineFields = {
    env = env,
    fs = fs,
    vfs = vfs,
    term = term,
    native = native,
    colours = colours,
    keys = keys,
    queue = queue,
    timers = timers,
  }
  for key, value in pairs(_machineFields) do machine[key] = value end

  function machine.now() return clock end
  function machine.advance(seconds) clock = clock + (seconds or 0.05) end

  function machine.push(...)
    queue[#queue + 1] = table.pack(...)
  end

  --- Hand this computer a frame that arrived over the wire.
  function machine.deliverRednet(sender, serialised, protocol)
    local message = textutils.unserialise(serialised)
    if message == nil then return false end
    queue[#queue + 1] = table.pack("rednet_message", sender, message, protocol)
    return true
  end

  --- Pop the next event, firing any timer that is due.
  local function nextEvent()
    if #queue > 0 then return table.remove(queue, 1) end
    -- find the earliest timer
    local bestId, bestAt
    for id, at in pairs(timers) do
      if not bestAt or at < bestAt then bestId, bestAt = id, at end
    end
    if bestId then
      timers[bestId] = nil
      clock = math.max(clock, bestAt)
      return table.pack("timer", bestId)
    end
    return nil
  end
  machine.nextEvent = nextEvent

  function machine.boot(path)
    local chunk, err = env.loadfile(path)
    if not chunk then return nil, err end
    machine.co = coroutine.create(chunk)
    machine.filter = nil
    machine.dead = false
    local ok, result = coroutine.resume(machine.co)
    if not ok then
      machine.dead = true
      machine.error = result
      return false, result
    end
    machine.filter = type(result) == "string" and result or nil
    if coroutine.status(machine.co) == "dead" then machine.dead = true end
    return true
  end

  --- Drain only events that are already queued, never falling forward onto a
  --- timer.  Two machines running side by side each have their own clock, and
  --- letting one jump ahead to its next timeout would time out a request the
  --- other has not had a chance to answer yet.
  function machine.pumpQueued(limit)
    limit = limit or 50
    local steps = 0
    while not machine.dead and steps < limit and #queue > 0 do
      local event = table.remove(queue, 1)
      if machine.filter == nil or event[1] == machine.filter
         or event[1] == "terminate" then
        machine.advance(0.01)
        local ok, result = coroutine.resume(machine.co, table.unpack(event, 1, event.n))
        if not ok then
          machine.dead = true
          machine.error = result
          return steps
        end
        machine.filter = type(result) == "string" and result or nil
        if coroutine.status(machine.co) == "dead" then machine.dead = true end
      end
      steps = steps + 1
    end
    return steps
  end

  --- When is this machine's earliest pending timer due?  Returns nil when it
  --- has none.  A harness running two machines uses this to fire whichever
  --- timer is genuinely next, instead of letting one machine's clock run
  --- ahead and time out work the other has not been scheduled to do yet.
  function machine.nextTimer()
    local soonest
    for _, at in pairs(timers) do
      if not soonest or at < soonest then soonest = at end
    end
    return soonest
  end

  --- Fire exactly one timer: the earliest.  Returns true if one was fired.
  function machine.fireTimer()
    local bestId, bestAt
    for id, at in pairs(timers) do
      if not bestAt or at < bestAt then bestId, bestAt = id, at end
    end
    if not bestId then return false end
    timers[bestId] = nil
    clock = math.max(clock, bestAt)
    queue[#queue + 1] = table.pack("timer", bestId)
    return true
  end

  --- Run until the queue and the timers are exhausted, or `limit` steps pass.
  function machine.pump(limit)
    limit = limit or 400
    local steps = 0
    while not machine.dead and steps < limit do
      local event = nextEvent()
      if not event then break end
      if machine.filter == nil or event[1] == machine.filter or event[1] == "terminate" then
        machine.advance(0.05)
        local ok, result = coroutine.resume(machine.co, table.unpack(event, 1, event.n))
        if not ok then
          machine.dead = true
          machine.error = result
          return steps, result
        end
        machine.filter = type(result) == "string" and result or nil
        if coroutine.status(machine.co) == "dead" then machine.dead = true end
      end
      steps = steps + 1
    end
    return steps
  end

  return machine
end

return emu
