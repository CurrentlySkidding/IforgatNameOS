--[[ Calculator -------------------------------------------------------------
     Type an expression or use the keypad; every result is kept on the tape.
----------------------------------------------------------------------------]]

local App   = arequire("ui.app")
local base  = arequire("ui.widget")
local W     = arequire("ui.widgets")
local theme = arequire("gfx.theme")
local util  = arequire("lib.util")

local app = App({ title = "Calculator" })

local state = { input = "", tape = {}, memory = 0 }

------------------------------------------------------------------ display --

local Display = util.class(base.Widget)

function Display:init()
  base.Widget.init(self, {})
  self.hexpand = true
  self.heightRequest = 3
end

function Display:measure() return 18, 3 end

function Display:draw(s)
  local c = theme.c
  s:fill(self.x, self.y, self.w, self.h, " ", c.text, c.view)
  local previous = state.tape[#state.tape]
  if previous then
    s:writeRight(self.x, self.y, util.ellipsis(previous.expression, self.w - 2),
                 c.dim, c.view, self.w - 1)
  end
  local shown = state.input == "" and "0" or state.input
  s:writeRight(self.x, self.y + 1, util.ellipsis(shown, self.w - 2), c.text, c.view, self.w - 1)
  if state.error then
    s:write(self.x + 1, self.y + 2, util.ellipsis(state.error, self.w - 2), c.destructive, c.view)
  elseif previous then
    s:writeRight(self.x, self.y + 2, "= " .. previous.result, c.accent, c.view, self.w - 1)
  end
end

local display = Display()

------------------------------------------------------------------- engine --

local SAFE = {
  abs = math.abs, ceil = math.ceil, floor = math.floor, sqrt = math.sqrt,
  sin = math.sin, cos = math.cos, tan = math.tan, exp = math.exp, log = math.log,
  min = math.min, max = math.max, pi = math.pi, e = math.exp(1),
  random = math.random, pow = function(a, b) return a ^ b end,
}

local function evaluate(expression)
  local prepared = expression:gsub("\215", "*"):gsub("\246", "/"):gsub("%%", "/100")
  local chunk, err = load("return " .. prepared, "=calc", "t", SAFE)
  if not chunk then return nil, "Syntax error" end
  local ok, value = pcall(chunk)
  if not ok or type(value) ~= "number" then return nil, "Cannot work that out" end
  if value ~= value then return nil, "Not a number" end
  return value
end

local function format(value)
  if value == math.floor(value) and math.abs(value) < 1e12 then
    return tostring(math.floor(value))
  end
  return (string.format("%.6f", value):gsub("0+$", ""):gsub("%.$", ""))
end

local function compute()
  if util.trim(state.input) == "" then return end
  local value, err = evaluate(state.input)
  if not value then
    state.error = err
  else
    state.error = nil
    table.insert(state.tape, { expression = state.input, result = format(value) })
    while #state.tape > 40 do table.remove(state.tape, 1) end
    state.input = format(value)
  end
  app:queueDraw()
end

--------------------------------------------------------------------- keys --

local KEYPAD = {
  { "C", "(", ")", "\246" },
  { "7", "8", "9", "\215" },
  { "4", "5", "6", "-" },
  { "1", "2", "3", "+" },
  { "0", ".", "\27", "=" },
}

local function press(label)
  state.error = nil
  if label == "C" then
    state.input = ""
  elseif label == "\27" then           -- backspace arrow
    state.input = state.input:sub(1, -2)
  elseif label == "=" then
    compute()
    return
  else
    state.input = state.input .. label
  end
  app:queueDraw()
end

local keypad = base.Box({ orientation = "vertical", spacing = 0 })
keypad.hexpand, keypad.vexpand = true, true

for _, row in ipairs(KEYPAD) do
  local line = base.Box({ orientation = "horizontal", spacing = 1 })
  line.hexpand = true
  for _, label in ipairs(row) do
    local style = "normal"
    if label == "=" then style = "suggested" end
    if label == "C" then style = "destructive" end
    local button = W.Button({ label = label, style = style })
    button.hexpand = true
    button:connect("clicked", function() press(label) end)
    line:add(button)
  end
  keypad:add(line)
end

local tapeList = W.ListBox({ rows = {}, background = theme.c.window })
tapeList.vexpand = true
local tapeScroller = base.Scrolled({ background = theme.c.window })
tapeScroller.vexpand = true
tapeScroller.widthRequest = 16
tapeScroller.visible = false
tapeScroller:setChild(tapeList)

local left = base.Box({ orientation = "vertical", spacing = 0 })
left.hexpand, left.vexpand = true, true
left:add(display)
left:add(keypad)

local body = base.Box({ orientation = "horizontal", spacing = 0 })
body.hexpand, body.vexpand = true, true
body:add(left)
body:add(tapeScroller)

app:setRoot(body)

local function refreshTape()
  local rows = {}
  for i = #state.tape, 1, -1 do
    local entry = state.tape[i]
    rows[#rows + 1] = { title = entry.expression .. " = " .. entry.result }
  end
  if #rows == 0 then rows[1] = { title = "Tape is empty" } end
  tapeList:setRows(rows)
end

----------------------------------------------------------------- keyboard --

app:accel("enter", compute)
app:accel("backspace", function() press("\27") end)
app:accel("delete", function() press("C") end)
app:accel("ctrl+t", function()
  tapeScroller.visible = not tapeScroller.visible
  refreshTape()
  app:queueLayout()
end)

-- The buttons are focusable, so plain characters would go to them first.
-- Routing them here keeps typing natural.
local originalDispatch = app.dispatch
app.dispatch = function(self, ev)
  if ev[1] == "char" then
    local ch = ev[2]
    if ch:match("[%d%.%+%-%*/%%%(%)%^]") then
      press(ch)
      return
    elseif ch == "=" then
      compute()
      return
    elseif ch == "c" or ch == "C" then
      press("C")
      return
    end
  end
  return originalDispatch(self, ev)
end

refreshTape()
app:run()
