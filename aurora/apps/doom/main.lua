--[[ Corridor ---------------------------------------------------------------
     A first-person maze, raycast every frame.

     One ray per pixel column of the sub-pixel canvas, so a 44-cell window is
     88 columns wide.  Walls are shaded by distance and by which face you are
     looking at, which is what sells the depth on a 16-colour display.
----------------------------------------------------------------------------]]

local App   = arequire("ui.app")
local base  = arequire("ui.widget")
local W     = arequire("ui.widgets")
local theme = arequire("gfx.theme")
local util  = arequire("lib.util")
local pixel = arequire("gfx.pixel")

local app = App({ title = "Corridor" })

-- 1 is wall, 2 is the exit, 0 is floor
local MAP = {
  "1111111111111111",
  "1000000010000001",
  "1011111010111101",
  "1010000010100001",
  "1010111110101111",
  "1010100000100001",
  "1010101111111101",
  "1000100000000001",
  "1111101111111011",
  "1000001000001011",
  "1011111011101011",
  "1010000010001001",
  "1010111110111101",
  "1000100000100021",
  "1111111111111111",
}

local MAP_W, MAP_H = #MAP[1], #MAP

local function tileAt(x, y)
  local column = math.floor(x) + 1
  local row = math.floor(y) + 1
  if column < 1 or row < 1 or column > MAP_W or row > MAP_H then return 1 end
  return tonumber(MAP[row]:sub(column, column)) or 1
end

local player = { x = 1.5, y = 1.5, angle = 0, health = 100, found = false }
local keysDown = {}

local FOV = math.pi / 3
local MOVE_SPEED = 2.6
local TURN_SPEED = 2.6

------------------------------------------------------------------- view ----

local View = util.class(base.Widget)

function View:init()
  base.Widget.init(self, {})
  self.hexpand, self.vexpand = true, true
  self.focusable = true
end

function View:measure() return 24, 10 end

--- Cast one ray, stepping through the grid until it hits something.
local function castRay(angle)
  local sin, cos = math.sin(angle), math.cos(angle)
  local distance = 0
  local step = 0.035
  while distance < 22 do
    distance = distance + step
    local tile = tileAt(player.x + cos * distance, player.y + sin * distance)
    if tile ~= 0 then
      -- work out which face we hit, for shading
      local hitX = player.x + cos * distance
      local hitY = player.y + sin * distance
      local fracX = hitX - math.floor(hitX)
      local fracY = hitY - math.floor(hitY)
      local vertical = math.min(fracX, 1 - fracX) < math.min(fracY, 1 - fracY)
      return distance, tile, vertical
    end
  end
  return distance, 0, false
end

function View:draw(s)
  local c = theme.c
  local canvas = pixel.Canvas(self.w, self.h - 1, c.desktop)
  local width, height = canvas.w, canvas.h
  local horizon = math.floor(height / 2)

  -- ceiling and floor, banded so distance reads even on flat ground
  for y = 1, horizon - 1 do
    canvas:hline(1, y, width, y < horizon / 2 and c.desktop or c.window)
  end
  for y = horizon, height do
    canvas:hline(1, y, width, y > horizon + height / 4 and c.card or c.window)
  end

  local nearest = 99
  for column = 1, width do
    local rayAngle = player.angle - FOV / 2 + FOV * (column - 1) / (width - 1)
    local distance, tile, vertical = castRay(rayAngle)
    -- undo the fisheye the flat projection plane introduces
    distance = distance * math.cos(rayAngle - player.angle)
    if distance < nearest then nearest = distance end

    if tile ~= 0 then
      local wallHeight = math.floor(height / math.max(0.25, distance))
      local top = math.max(1, horizon - math.floor(wallHeight / 2))
      local bottom = math.min(height, horizon + math.floor(wallHeight / 2))

      local colour
      if tile == 2 then
        colour = c.success
      elseif distance < 2.2 then
        colour = vertical and c.text or c.dim
      elseif distance < 4.5 then
        colour = vertical and c.dim or c.active
      elseif distance < 8 then
        colour = vertical and c.active or c.border
      else
        colour = c.window
      end

      for y = top, bottom do canvas:set(column, y, colour) end
    end
  end

  canvas:render(s, self.x, self.y)

  -- status line
  local row = self.y + self.h - 1
  s:fill(self.x, row, self.w, 1, " ", c.dim, c.panel)
  local hint = player.found and "you found the exit!" or "WASD move, arrows turn"
  local position = ("%.0f,%.0f"):format(player.x, player.y)
  s:write(self.x + 1, row, position, c.dim, c.panel)
  -- only show the hint if it will not run into the position readout
  if self.w - #position - 3 >= #hint then
    s:writeRight(self.x, row, hint, player.found and c.success or c.dim,
                 c.panel, self.w - 1)
  end
end

local view = View()
app:setRoot(view)

------------------------------------------------------------------ motion ---

local function tryMove(dx, dy)
  -- slide along walls instead of sticking to them
  if tileAt(player.x + dx * 0.25, player.y) == 0 then player.x = player.x + dx end
  if tileAt(player.x, player.y + dy * 0.25) == 0 then player.y = player.y + dy end
  if tileAt(player.x, player.y) == 2 then player.found = true end
end

local FRAME = 0.09

local function tick()
  local moved = false
  local forward = 0
  local strafe = 0
  local turn = 0

  if keysDown[keys.w] then forward = forward + 1 end
  if keysDown[keys.s] then forward = forward - 1 end
  if keysDown[keys.a] then strafe = strafe - 1 end
  if keysDown[keys.d] then strafe = strafe + 1 end
  if keysDown[keys.left] then turn = turn - 1 end
  if keysDown[keys.right] then turn = turn + 1 end
  if keysDown[keys.up] then forward = forward + 1 end
  if keysDown[keys.down] then forward = forward - 1 end

  if turn ~= 0 then
    player.angle = player.angle + turn * TURN_SPEED * FRAME
    moved = true
  end
  if forward ~= 0 or strafe ~= 0 then
    local sin, cos = math.sin(player.angle), math.cos(player.angle)
    local dx = (cos * forward - sin * strafe) * MOVE_SPEED * FRAME
    local dy = (sin * forward + cos * strafe) * MOVE_SPEED * FRAME
    tryMove(dx, dy)
    moved = true
  end

  if moved then app:queueDraw() end
  app:after(FRAME, tick)
end

-------------------------------------------------------------------- input --

function view:onKey(key, held)
  keysDown[key] = true
  if key == keys.r then
    player.x, player.y, player.angle, player.found = 1.5, 1.5, 0, false
    app:queueDraw()
  end
  return true
end

app.onEvent = function(name, ...)
  if name == "key_up" then
    keysDown[select(1, ...)] = nil
  end
end

-- Held keys matter here, so the app needs key_up events it would normally
-- only use for modifiers.
local originalDispatch = app.dispatch
app.dispatch = function(self, ev)
  if ev[1] == "key_up" then keysDown[ev[2]] = nil end
  return originalDispatch(self, ev)
end

app:after(FRAME, tick)
app:setFocus(view)
app:run()
