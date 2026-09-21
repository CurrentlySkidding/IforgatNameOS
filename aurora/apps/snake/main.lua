--[[ Snake ------------------------------------------------------------------
     The board is drawn on the sub-pixel canvas, so it is 2x3 times finer than
     the character grid and the snake reads as a smooth line rather than a row
     of letters.
----------------------------------------------------------------------------]]

local App   = arequire("ui.app")
local base  = arequire("ui.widget")
local W     = arequire("ui.widgets")
local theme = arequire("gfx.theme")
local util  = arequire("lib.util")
local pixel = arequire("gfx.pixel")

local app = App({ title = "Snake" })

local HIGHSCORE = "/aurora/var/snake.cfg"

local game = {
  body = {}, direction = { x = 1, y = 0 }, next = { x = 1, y = 0 },
  food = { x = 10, y = 6 }, score = 0, best = 0,
  state = "ready",          -- ready | playing | dead
  speed = 0.14, width = 20, height = 12,
}

do
  local saved = util.readTable(HIGHSCORE, nil)
  if type(saved) == "table" then game.best = saved.best or 0 end
end

------------------------------------------------------------------- board ---

local Board = util.class(base.Widget)

function Board:init()
  base.Widget.init(self, {})
  self.hexpand, self.vexpand = true, true
  self.focusable = true
end

function Board:measure() return 20, 8 end

function Board:allocate(x, y, w, h)
  base.Widget.allocate(self, x, y, w, h)
  -- one cell is 2x3 pixels; leave a one-cell border for the wall
  game.width = math.max(8, (w - 2) * 2)
  game.height = math.max(6, (h - 2) * 3)
end

function Board:draw(s)
  local c = theme.c
  s:fill(self.x, self.y, self.w, self.h, " ", c.text, c.view)

  local canvas = pixel.Canvas(self.w, self.h, c.view)
  -- walls
  canvas:rect(1, 1, canvas.w, 1, c.separator)
  canvas:rect(1, canvas.h, canvas.w, 1, c.separator)
  canvas:vline(1, 1, canvas.h, c.separator)
  canvas:vline(canvas.w, 1, canvas.h, c.separator)

  -- food, drawn a touch bigger so it is easy to see
  canvas:set(game.food.x + 1, game.food.y + 1, c.destructive)

  for index, part in ipairs(game.body) do
    local colour = index == 1 and c.accent or c.success
    canvas:set(part.x + 1, part.y + 1, colour)
  end

  canvas:render(s, self.x, self.y)

  local header = ("Score %d    Best %d"):format(game.score, game.best)
  s:write(self.x + 1, self.y, header, c.dim, c.view)

  if game.state ~= "playing" then
    local title = game.state == "ready" and "SNAKE" or "GAME OVER"
    local hint = game.state == "ready" and "arrows or WASD to start"
                 or ("score " .. game.score .. "  \183  space to play again")
    local row = self.y + math.floor(self.h / 2) - 1
    s:fill(self.x + 2, row - 1, self.w - 4, 3, " ", c.text, c.card)
    s:writeCentered(row, title, c.accent, c.card, self.x, self.w)
    s:writeCentered(row + 1, util.ellipsis(hint, self.w - 4), c.dim, c.card,
                    self.x, self.w)
  end
end

local board = Board()
app:setRoot(board)

-------------------------------------------------------------------- rules --

local function placeFood()
  for _ = 1, 200 do
    local spot = { x = math.random(1, game.width), y = math.random(1, game.height) }
    local clear = true
    for _, part in ipairs(game.body) do
      if part.x == spot.x and part.y == spot.y then clear = false break end
    end
    if clear then
      game.food = spot
      return
    end
  end
end

local function reset()
  game.body = {}
  local startX = math.floor(game.width / 3)
  local startY = math.floor(game.height / 2)
  for i = 0, 3 do
    game.body[#game.body + 1] = { x = startX - i, y = startY }
  end
  game.direction = { x = 1, y = 0 }
  game.next = { x = 1, y = 0 }
  game.score = 0
  game.speed = 0.14
  placeFood()
end

local function die()
  game.state = "dead"
  if game.score > game.best then
    game.best = game.score
    util.writeTable(HIGHSCORE, { best = game.best })
  end
  app:queueDraw()
end

local function step()
  if game.state ~= "playing" then return end
  game.direction = game.next

  local head = game.body[1]
  local target = { x = head.x + game.direction.x, y = head.y + game.direction.y }

  if target.x < 1 or target.y < 1 or target.x > game.width or target.y > game.height then
    die()
    return
  end
  for index, part in ipairs(game.body) do
    -- the tail moves out of the way on the same tick, so it is not a crash
    if part.x == target.x and part.y == target.y and index < #game.body then
      die()
      return
    end
  end

  table.insert(game.body, 1, target)
  if target.x == game.food.x and target.y == game.food.y then
    game.score = game.score + 1
    game.speed = math.max(0.05, game.speed - 0.004)
    placeFood()
  else
    table.remove(game.body)
  end
  app:queueDraw()
end

local function tick()
  step()
  app:after(game.speed, tick)
end

------------------------------------------------------------------- input ---

local function turn(dx, dy)
  -- no instant reversal onto your own neck
  if game.direction.x == -dx and game.direction.y == -dy then return end
  game.next = { x = dx, y = dy }
end

local function startGame()
  reset()
  game.state = "playing"
  app:queueDraw()
end

function board:onKey(key)
  if key == keys.left or key == keys.a then turn(-1, 0)
  elseif key == keys.right or key == keys.d then turn(1, 0)
  elseif key == keys.up or key == keys.w then turn(0, -1)
  elseif key == keys.down or key == keys.s then turn(0, 1)
  elseif key == keys.space or key == keys.enter then
    if game.state ~= "playing" then startGame() end
    return true
  else
    return false
  end
  if game.state ~= "playing" then startGame() end
  return true
end

function board:onMouse(kind)
  if kind == "mouse_click" and game.state ~= "playing" then
    startGame()
    return true
  end
  return kind == "mouse_up"
end

reset()
app:after(game.speed, tick)
app:setFocus(board)
app:run()
