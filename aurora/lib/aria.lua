--[[ aurora.lib.aria ---------------------------------------------------------
     The assistant's brain.

     It is rules all the way down -- patterns matched in priority order, with
     the subject pulled out and looked up in the knowledge base.  No model, no
     network: it answers instantly and works on a computer buried in a cave.

     `aria.ask(text, context)` returns a list of reply lines plus an optional
     action for the app to carry out.
----------------------------------------------------------------------------]]

local util      = arequire("lib.util")
local knowledge = arequire("lib.knowledge")

local aria = {}

aria.NAME = "Aria"
aria.MEMORY = "/aurora/var/aria.cfg"

aria.memory = { name = nil, asked = 0, topics = {} }

function aria.load()
  local stored = util.readTable(aria.MEMORY, nil)
  if type(stored) == "table" then
    aria.memory.name = stored.name
    aria.memory.asked = stored.asked or 0
    aria.memory.topics = stored.topics or {}
  end
end

function aria.save()
  util.writeTable(aria.MEMORY, aria.memory)
end

function aria.forget()
  aria.memory = { name = nil, asked = 0, topics = {} }
  aria.save()
end

local function remember(topic)
  if not topic then return end
  aria.memory.topics[topic] = (aria.memory.topics[topic] or 0) + 1
end

--- What the user asks about most.
function aria.favouriteTopic()
  local best, bestCount = nil, 0
  for topic, count in pairs(aria.memory.topics) do
    if count > bestCount then best, bestCount = topic, count end
  end
  return best, bestCount
end

------------------------------------------------------------------ helpers --

local function pick(list)
  return list[math.random(1, #list)]
end

local function has(text, ...)
  for _, word in ipairs({ ... }) do
    if text:find(word, 1, true) then return true end
  end
  return false
end

local function startsWith(text, ...)
  for _, word in ipairs({ ... }) do
    if text:sub(1, #word) == word then return true end
  end
  return false
end

local function addressed(text)
  return aria.memory.name and (", " .. aria.memory.name) or ""
end

------------------------------------------------------------------ replies --

local GREETINGS = {
  "Hey%s. What do you need?",
  "Hello%s.",
  "Hi%s. Ask me about Minecraft, or tell me to open something.",
}

local THANKS = {
  "Any time.",
  "No trouble.",
  "That is what I am here for.",
}

local CONFUSED = {
  "I do not know that one. Try \"how do I make a beacon\" or \"where is diamond\".",
  "Not sure. I know recipes, mobs, ores, enchantments, potions and this computer.",
  "No idea, sorry. Type \"help\" to see what I can actually do.",
}

local JOKES = {
  "I would tell you a redstone joke, but the timing is off.",
  "A creeper walks into a bar. Everyone leaves.",
  "Why does nobody trust a skeleton? No guts.",
  "I tried to write a mining joke. It did not pan out.",
  "Endermen hate this one simple trick: a two-block ceiling.",
}

------------------------------------------------------------------- intents --

--- Each intent gets the lowered text and the context table.  Returning a
--- table of lines (and optionally an action) stops the chain.
local intents = {}

-- ---- identity and small talk ----------------------------------------------

intents[#intents + 1] = function(text)
  if not (startsWith(text, "my name is", "call me", "i am called", "i'm called")
          or text:match("^i am %a+$") or text:match("^i'm %a+$")) then
    return nil
  end
  local name = text:gsub("my name is", ""):gsub("call me", "")
                   :gsub("i am called", ""):gsub("i'm called", "")
                   :gsub("^i am ", ""):gsub("^i'm ", "")
  name = util.trim(name):gsub("^%l", string.upper)
  if name == "" then return nil end
  aria.memory.name = name
  aria.save()
  return { ("Got it. I will call you %s."):format(name) }
end

intents[#intents + 1] = function(text)
  if not has(text, "what is my name", "who am i") then return nil end
  if aria.memory.name then
    return { "You are " .. aria.memory.name .. "." }
  end
  return { "You have not told me. Say \"my name is ...\" and I will remember." }
end

intents[#intents + 1] = function(text)
  if not (has(text, "who are you", "what are you", "your name")) then return nil end
  return {
    "I am Aria, the assistant built into this computer.",
    "I know Minecraft, and I can drive the rest of the system for you.",
  }
end

intents[#intents + 1] = function(text)
  if not (startsWith(text, "hi", "hey", "hello", "yo ", "yo") or text == "sup") then
    return nil
  end
  return { pick(GREETINGS):format(addressed(text)) }
end

intents[#intents + 1] = function(text)
  if not has(text, "thank", "thanks", "cheers", "ta ") then return nil end
  return { pick(THANKS) }
end

intents[#intents + 1] = function(text)
  if not has(text, "joke", "funny", "make me laugh") then return nil end
  return { pick(JOKES) }
end

intents[#intents + 1] = function(text)
  if not has(text, "how are you", "you ok", "you alright") then return nil end
  return { "Running fine. Uptime is good and nothing has crashed today." }
end

-- ---- help ------------------------------------------------------------------

intents[#intents + 1] = function(text)
  if not (text == "help" or has(text, "what can you do", "what do you know",
                                "commands", "how do i use you")) then
    return nil
  end
  return {
    "Ask me things like:",
    "  how do I make a beacon",
    "  where do I find diamond",
    "  tell me about the warden",
    "  what does mending do",
    "  how do I brew fire resistance",
    "Or tell me to do things:",
    "  open files / launch messages",
    "  message 12",
    "  arm the base / lights on",
    "  status / who is online",
  }
end

-- ---- running the computer --------------------------------------------------

local APP_WORDS = {
  files = "files", file = "files", folder = "files", explorer = "files",
  terminal = "terminal", shell = "terminal", console = "terminal",
  editor = "editor", edit = "editor", code = "editor", notepad = "editor",
  writer = "writer", document = "writer", write = "writer",
  sheets = "sheets", spreadsheet = "sheets", sheet = "sheets",
  slides = "slides", presentation = "slides", deck = "slides",
  settings = "settings", preferences = "settings", options = "settings",
  calculator = "calc", calc = "calc", maths = "calc", math = "calc",
  monitor = "monitor", processes = "monitor", tasks = "monitor",
  messages = "messages", chat = "messages", message = "messages",
  web = "web", browser = "web", internet = "web", sites = "web",
  defense = "defense", defence = "defense", security = "defense",
  base = "defense", alarm = "defense",
}

intents[#intents + 1] = function(text)
  if not startsWith(text, "open ", "launch ", "start ", "run ", "show me ") then
    return nil
  end
  local target = text:gsub("^open ", ""):gsub("^launch ", ""):gsub("^start ", "")
                     :gsub("^run ", ""):gsub("^show me ", "")
  target = util.trim(target:gsub("^the ", ""):gsub("^my ", ""))
  local appId = APP_WORDS[target]
  if not appId then
    for word, id in pairs(APP_WORDS) do
      if target:find(word, 1, true) then appId = id break end
    end
  end
  if not appId then return nil end
  return { "Opening " .. appId .. "." }, { kind = "launch", app = appId }
end

intents[#intents + 1] = function(text)
  local id = text:match("^message%s+(%d+)") or text:match("^text%s+(%d+)")
             or text:match("^chat%s+(%d+)")
  if not id then return nil end
  return { "Opening a conversation with computer " .. id .. "." },
         { kind = "launch", app = "messages", args = { id } }
end

intents[#intents + 1] = function(text, context)
  if not has(text, "who is online", "who's online", "anyone online",
             "who is on the network", "list computers", "peers") then
    return nil
  end
  local peers = context.peers or {}
  if #peers == 0 then
    return { "Nobody yet. Either no modem is attached or nobody else is running Aurora." }
  end
  local lines = { "On the network right now:" }
  for _, peer in ipairs(peers) do
    lines[#lines + 1] = ("  %s (computer %d)%s")
      :format(peer.name, peer.id, peer.online and "" or " - offline")
  end
  return lines
end

-- ---- the base --------------------------------------------------------------

intents[#intents + 1] = function(text, context)
  if not (has(text, "arm the base", "arm the system", "lock the base",
              "arm defense", "arm defence", "lock down")) then
    return nil
  end
  return { "Arming the defense system." }, { kind = "arm" }
end

intents[#intents + 1] = function(text)
  if not (has(text, "disarm", "unlock the base", "stand down")) then return nil end
  return { "Disarming." }, { kind = "disarm" }
end

intents[#intents + 1] = function(text)
  local on = has(text, "lights on", "turn on the lights", "turn the lights on")
  local off = has(text, "lights off", "turn off the lights", "turn the lights off")
  if not (on or off) then return nil end
  return { on and "Lights on." or "Lights off." },
         { kind = "lights", on = on and true or false }
end

intents[#intents + 1] = function(text, context)
  if not has(text, "status", "how are things", "report", "sitrep",
             "everything ok", "everything alright") then
    return nil
  end
  local lines = { "Here is where things stand:" }
  for _, line in ipairs(context.status or {}) do
    lines[#lines + 1] = "  " .. line
  end
  if #lines == 1 then lines[#lines + 1] = "  Nothing to report." end
  return lines
end

-- ---- Minecraft knowledge ---------------------------------------------------

intents[#intents + 1] = function(text)
  if not has(text, "tip", "advice", "teach me", "tell me something") then return nil end
  local topic
  for name in pairs(knowledge.tips) do
    if text:find(name, 1, true) then topic = name end
  end
  local tip = knowledge.tip(topic)
  return tip and { tip } or nil
end

intents[#intents + 1] = function(text)
  if not has(text, "brew", "potion") then return nil end
  local subject = knowledge.subject(text):gsub("potion of ", ""):gsub(" potion", "")
  local category, key, entry = knowledge.find(subject)
  if category == "potion" then
    remember("potions")
    local lines = knowledge.describe(category, key, entry)
    lines[#lines + 1] = pick(knowledge.brewingModifiers)
    return lines
  end
  return {
    "Start with nether wart in a water bottle to make an awkward potion.",
    "Then add the ingredient for what you want. Ask me about a specific one.",
  }
end

--- The catch-all knowledge lookup, last so the specific intents win.
intents[#intents + 1] = function(text)
  local subject = knowledge.subject(text)
  if subject == "" then return nil end
  local category, key, entry = knowledge.find(subject)
  if not category then return nil end
  remember(category)
  return knowledge.describe(category, key, entry)
end

------------------------------------------------------------------- asking --

--- Ask Aria something.
--- @param text string
--- @param context table { peers = {...}, status = { "line", ... } }
--- @return lines, action
function aria.ask(text, context)
  context = context or {}
  local lowered = util.trim(tostring(text or "")):lower()
  if lowered == "" then return { "Go on then." } end

  aria.memory.asked = aria.memory.asked + 1
  if aria.memory.asked % 10 == 0 then aria.save() end

  for _, intent in ipairs(intents) do
    local ok, lines, action = pcall(intent, lowered, context)
    if ok and lines then return lines, action end
  end

  return { pick(CONFUSED) }
end

--- The line Aria opens with.
function aria.greeting()
  aria.load()
  if aria.memory.name then
    local topic = aria.favouriteTopic()
    if topic and aria.memory.asked > 6 then
      return {
        ("Welcome back, %s."):format(aria.memory.name),
        ("Still on %s, or something new today?"):format(topic .. "s"),
      }
    end
    return { ("Hello again, %s. What do you need?"):format(aria.memory.name) }
  end
  return {
    "I am Aria. I know " .. knowledge.count() .. " things about Minecraft,",
    "and I can drive this computer for you.",
    "Type \"help\" if you want the tour.",
  }
end

return aria
