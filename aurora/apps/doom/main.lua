--[[ Doom -------------------------------------------------------------------
     A first-person shooter, raycast every frame on the sub-pixel canvas.

     Walls use DDA raycasting, one ray per pixel column, and every column
     remembers how far away its wall was.  Monsters and pickups are sprites
     drawn after the walls, column by column, only where they are nearer than
     that wall -- which is how they hide properly behind corners.

     W A S D move    arrows turn    SPACE shoots    R restarts
----------------------------------------------------------------------------]]

local App   = arequire("ui.app")
local base  = arequire("ui.widget")
local theme = arequire("gfx.theme")
local util  = arequire("lib.util")
local pixel = arequire("gfx.pixel")

local app = App({ title = "Doom" })

--------------------------------------------------------------------- map ---

-- 1 wall.  Letters mark spawns: i imp, b brute, a ammo, h health.
local MAP = {
  "1111111111111111",
  "1000001000000001",
  "1000001000i00001",
  "10a0000000000b01",
  "1000001000000001",
  "1110111111011111",
  "1000000100000001",
  "10i0000100h000i1",
  "1000000000000001",
  "1000000100000001",
  "1111011111110111",
  "1000000000000001",
  "10b000a000000i01",
  "1000000000000001",
  "1111111111111111",
}

local MAP_W, MAP_H = #MAP[1], #MAP

local function wallAt(x, y)
  local column, row = math.floor(x) + 1, math.floor(y) + 1
  if column < 1 or row < 1 or column > MAP_W or row > MAP_H then return true end
  return MAP[row]:sub(column, column) == "1"
end

------------------------------------------------------------------- state ---

local FOV = math.pi / 3
local FRAME = 0.08
local MOVE_SPEED = 3.0
local TURN_SPEED = 2.4

local game
local keysDown = {}

local function newGame()
  game = {
    player = { x = 1.5, y = 1.5, angle = 0.4, health = 100, ammo = 20 },
    monsters = {},
    items = {},
    kills = 0,
    total = 0,
    fireCooldown = 0,
    flash = 0,         -- muzzle flash frames
    hurt = 0,          -- red screen frames
    state = "playing", -- playing | dead | won
    message = "Kill them all.",
    messageTime = 3,
  }
  for row = 1, MAP_H do
    for column = 1, MAP_W do
      local ch = MAP[row]:sub(column, column)
      local x, y = column - 0.5, row - 0.5
      if ch == "i" then
        table.insert(game.monsters, { x = x, y = y, health = 60, max = 60,
          kind = "imp", speed = 1.3, damage = 8, cooldown = 0, pain = 0 })
      elseif ch == "b" then
        table.insert(game.monsters, { x = x, y = y, health = 160, max = 160,
          kind = "brute", speed = 0.8, damage = 18, cooldown = 0, pain = 0 })
      elseif ch == "a" then
        table.insert(game.items, { x = x, y = y, kind = "ammo" })
      elseif ch == "h" then
        table.insert(game.items, { x = x, y = y, kind = "health" })
      end
    end
  end
  game.total = #game.monsters
end

newGame()

-------------------------------------------------------------- raycasting ---

--- DDA: walk the grid one cell boundary at a time.  Exact, and far cheaper
--- than marching a ray in tiny steps.
local function castRay(angle)
  local p = game.player
  local dirX, dirY = math.cos(angle), math.sin(angle)
  local mapX, mapY = math.floor(p.x), math.floor(p.y)
  local deltaX = dirX == 0 and 1e30 or math.abs(1 / dirX)
  local deltaY = dirY == 0 and 1e30 or math.abs(1 / dirY)
  local stepX, stepY, sideX, sideY

  if dirX < 0 then stepX, sideX = -1, (p.x - mapX) * deltaX
  else stepX, sideX = 1, (mapX + 1 - p.x) * deltaX end
  if dirY < 0 then stepY, sideY = -1, (p.y - mapY) * deltaY
  else stepY, sideY = 1, (mapY + 1 - p.y) * deltaY end

  for _ = 1, 64 do
    local side
    if sideX < sideY then
      sideX = sideX + deltaX
      mapX = mapX + stepX
      side = 0
    else
      sideY = sideY + deltaY
      mapY = mapY + stepY
      side = 1
    end
    if wallAt(mapX, mapY) then
      local distance = (side == 0) and (sideX - deltaX) or (sideY - deltaY)
      return distance, side == 0
    end
  end
  return 30, false
end

--- Where on screen a world point lands.  Returns column, distance, visible.
local function project(x, y, width)
  local p = game.player
  local dx, dy = x - p.x, y - p.y
  local distance = math.sqrt(dx * dx + dy * dy)
  local angle = math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx)
  local relative = angle - p.angle
  while relative > math.pi do relative = relative - 2 * math.pi end
  while relative < -math.pi do relative = relative + 2 * math.pi end
  local column = (relative / FOV + 0.5) * width
  -- perpendicular distance, to match the fisheye-corrected walls
  local depth = distance * math.cos(relative)
  return column, depth, math.abs(relative) < FOV
end

-------------------------------------------------------------------- draw ---

local View = util.class(base.Widget)

function View:init()
  base.Widget.init(self, {})
  self.hexpand, self.vexpand = true, true
  self.focusable = true
end

function View:measure() return 24, 10 end

--- Monster pixel art, as a function of position inside its sprite box.
local function monsterPixel(monster, u, v)
  local c = theme.c
  local body = monster.kind == "brute" and colours.purple or colours.red
  if monster.pain > 0 then body = colours.white end
  -- horns
  if v < 0.12 and (math.abs(u - 0.3) < 0.07 or math.abs(u - 0.7) < 0.07) then
    return colours.orange
  end
  -- head
  local hx, hy = u - 0.5, v - 0.28
  if hx * hx + hy * hy < 0.04 then
    if v > 0.22 and v < 0.3 and (math.abs(u - 0.42) < 0.05 or math.abs(u - 0.58) < 0.05) then
      return colours.yellow
    end
    return body
  end
  -- torso and arms
  if v >= 0.42 and v < 0.78 and u > 0.22 and u < 0.78 then return body end
  if v >= 0.45 and v < 0.7 and (u > 0.1 and u < 0.22 or u > 0.78 and u < 0.9) then
    return body
  end
  -- legs
  if v >= 0.78 and ((u > 0.28 and u < 0.44) or (u > 0.56 and u < 0.72)) then
    return c.dim
  end
  return nil
end

local function itemPixel(item, u, v)
  if item.kind == "ammo" then
    if v > 0.5 and u > 0.15 and u < 0.85 then return colours.yellow end
    if v > 0.35 and v <= 0.5 and u > 0.3 and u < 0.7 then return colours.orange end
  else
    if v > 0.4 and u > 0.15 and u < 0.85 then
      if (math.abs(u - 0.5) < 0.1) or (v > 0.6 and v < 0.78) then return colours.red end
      return colours.white
    end
  end
  return nil
end

--- The gun, drawn over everything at the bottom of the screen.
local GUN = {
  "....##....",
  "...#++#...",
  "...#++#...",
  "..#+##+#..",
  "..#+##+#..",
  ".#++##++#.",
  ".#++##++#.",
  "#++++++++#",
}

local function drawGun(canvas)
  local width, height = canvas.w, canvas.h
  local gunW, gunH = #GUN[1], #GUN
  local ox = math.floor((width - gunW) / 2)
  local recoil = game.flash > 0 and 1 or 0
  local oy = height - gunH + 1 + recoil
  if game.flash > 0 then
    -- muzzle flash just above the barrel
    for dy = -3, -1 do
      for dx = -1, 2 do
        if math.abs(dx - 0.5) + math.abs(dy + 2) < 2.5 then
          canvas:set(ox + 5 + dx, oy + dy, dy == -2 and colours.white or colours.yellow)
        end
      end
    end
  end
  for row = 1, gunH do
    local line = GUN[row]
    for column = 1, gunW do
      local ch = line:sub(column, column)
      if ch == "#" then canvas:set(ox + column, oy + row - 1, colours.grey)
      elseif ch == "+" then canvas:set(ox + column, oy + row - 1, colours.lightGrey) end
    end
  end
end

function View:draw(s)
  local c = theme.c
  local p = game.player
  local canvas = pixel.Canvas(self.w, self.h - 1, c.desktop)
  local width, height = canvas.w, canvas.h
  local horizon = math.floor(height / 2)

  -- ceiling and floor
  for y = 1, horizon do
    canvas:hline(1, y, width, y < horizon / 2 and c.desktop or c.window)
  end
  for y = horizon + 1, height do
    canvas:hline(1, y, width, y > horizon + height / 4 and colours.brown or c.window)
  end

  -- walls, remembering each column's depth for the sprites
  local depth = {}
  for column = 1, width do
    local rayAngle = p.angle - FOV / 2 + FOV * (column - 1) / (width - 1)
    local distance, vertical = castRay(rayAngle)
    distance = distance * math.cos(rayAngle - p.angle)
    depth[column] = distance

    local wallHeight = math.floor(height / math.max(0.2, distance))
    local top = math.max(1, horizon - math.floor(wallHeight / 2))
    local bottom = math.min(height, horizon + math.floor(wallHeight / 2))

    local colour
    if distance < 2 then colour = vertical and c.text or c.dim
    elseif distance < 4 then colour = vertical and c.dim or c.active
    elseif distance < 7 then colour = vertical and c.active or c.border
    else colour = c.window end

    for y = top, bottom do canvas:set(column, y, colour) end
  end

  -- sprites, far to near
  local sprites = {}
  for _, monster in ipairs(game.monsters) do
    if monster.health > 0 then sprites[#sprites + 1] = { thing = monster, monster = true } end
  end
  for _, item in ipairs(game.items) do
    sprites[#sprites + 1] = { thing = item, monster = false }
  end
  for _, sprite in ipairs(sprites) do
    local column, d, visible = project(sprite.thing.x, sprite.thing.y, width)
    sprite.column, sprite.depth, sprite.visible = column, d, visible
  end
  table.sort(sprites, function(a, b) return a.depth > b.depth end)

  for _, sprite in ipairs(sprites) do
    if sprite.visible and sprite.depth > 0.3 then
      local size = math.floor(height / sprite.depth)
      local spriteH = sprite.monster and size or math.floor(size * 0.45)
      local spriteW = sprite.monster and math.floor(size * 0.8) or math.floor(size * 0.5)
      local left = math.floor(sprite.column - spriteW / 2)
      local bottom = horizon + math.floor(size / 2)
      local top = bottom - spriteH
      for column = math.max(1, left), math.min(width, left + spriteW - 1) do
        if depth[column] > sprite.depth then
          local u = (column - left) / math.max(1, spriteW)
          for y = math.max(1, top), math.min(height, bottom) do
            local v = (y - top) / math.max(1, spriteH)
            local colour
            if sprite.monster then colour = monsterPixel(sprite.thing, u, v)
            else colour = itemPixel(sprite.thing, u, v) end
            if colour then canvas:set(column, y, colour) end
          end
        end
      end
    end
  end

  -- crosshair
  local mid = math.floor(width / 2)
  canvas:set(mid, horizon - 1, colours.lime)
  canvas:set(mid, horizon + 1, colours.lime)
  canvas:set(mid - 1, horizon, colours.lime)
  canvas:set(mid + 1, horizon, colours.lime)

  drawGun(canvas)

  -- taking damage tints the edges red
  if game.hurt > 0 then
    for y = 1, height do
      canvas:set(1, y, colours.red)
      canvas:set(2, y, colours.red)
      canvas:set(width, y, colours.red)
      canvas:set(width - 1, y, colours.red)
    end
  end

  canvas:render(s, self.x, self.y)

  -- status bar
  local row = self.y + self.h - 1
  s:fill(self.x, row, self.w, 1, " ", c.text, c.panel)
  local healthColour = p.health > 50 and c.success or (p.health > 25 and c.warning or c.destructive)
  s:write(self.x + 1, row, ("HP %d"):format(math.max(0, p.health)), healthColour, c.panel)
  s:write(self.x + 9, row, ("AMMO %d"):format(p.ammo),
          p.ammo > 0 and c.warning or c.destructive, c.panel)
  local killText = ("KILLS %d/%d"):format(game.kills, game.total)
  s:writeRight(self.x, row, killText, c.text, c.panel, self.w - 1)

  -- messages and end screens
  if game.state ~= "playing" then
    local title = game.state == "won" and "YOU WIN" or "YOU DIED"
    local colour = game.state == "won" and c.success or c.destructive
    local middle = self.y + math.floor((self.h - 1) / 2)
    s:fill(self.x + 4, middle - 1, self.w - 8, 3, " ", c.text, c.card)
    s:writeCentered(middle - 1, title, colour, c.card, self.x, self.w)
    s:writeCentered(middle + 1, "R to play again", c.dim, c.card, self.x, self.w)
  elseif game.messageTime > 0 then
    s:writeCentered(self.y, game.message, c.warning, c.desktop, self.x, self.w)
  end
end

local view = View()
app:setRoot(view)

------------------------------------------------------------------- rules ---

local function say(text)
  game.message = text
  game.messageTime = 2
end

local function blocked(x, y)
  return wallAt(x - 0.2, y - 0.2) or wallAt(x + 0.2, y - 0.2)
      or wallAt(x - 0.2, y + 0.2) or wallAt(x + 0.2, y + 0.2)
end

local function tryMove(thing, dx, dy)
  if not blocked(thing.x + dx, thing.y) then thing.x = thing.x + dx end
  if not blocked(thing.x, thing.y + dy) then thing.y = thing.y + dy end
end

--- Hitscan: whatever monster sits under the crosshair, nearest first,
--- and nearer than the wall behind it.
local function shoot()
  local p = game.player
  if game.fireCooldown > 0 then return end
  if p.ammo <= 0 then
    say("Out of ammo!")
    game.fireCooldown = 0.3
    return
  end
  p.ammo = p.ammo - 1
  game.fireCooldown = 0.3
  game.flash = 2

  local width = 88
  local centre = width / 2
  local wallDistance = castRay(p.angle)
  local target, targetDepth
  for _, monster in ipairs(game.monsters) do
    if monster.health > 0 then
      local column, d, visible = project(monster.x, monster.y, width)
      local halfWidth = (width / math.max(0.3, d)) * 0.3
      if visible and d > 0 and d < wallDistance
         and math.abs(column - centre) < halfWidth
         and (not target or d < targetDepth) then
        target, targetDepth = monster, d
      end
    end
  end

  if target then
    -- close shots hit harder
    local damage = math.floor(40 + math.max(0, 20 - targetDepth * 4))
    target.health = target.health - damage
    target.pain = 2
    if target.health <= 0 then
      game.kills = game.kills + 1
      say(target.kind == "brute" and "Brute down!" or "Imp down!")
      if game.kills >= game.total then
        game.state = "won"
      end
    end
  end
end

local function update(dt)
  local p = game.player
  if game.fireCooldown > 0 then game.fireCooldown = game.fireCooldown - dt end
  if game.flash > 0 then game.flash = game.flash - 1 end
  if game.hurt > 0 then game.hurt = game.hurt - 1 end
  if game.messageTime > 0 then game.messageTime = game.messageTime - dt end
  if game.state ~= "playing" then return end

  -- player movement
  local forward, strafe, turn = 0, 0, 0
  if keysDown[keys.w] or keysDown[keys.up] then forward = forward + 1 end
  if keysDown[keys.s] or keysDown[keys.down] then forward = forward - 1 end
  if keysDown[keys.a] then strafe = strafe - 1 end
  if keysDown[keys.d] then strafe = strafe + 1 end
  if keysDown[keys.left] then turn = turn - 1 end
  if keysDown[keys.right] then turn = turn + 1 end

  p.angle = p.angle + turn * TURN_SPEED * dt
  if forward ~= 0 or strafe ~= 0 then
    local sin, cos = math.sin(p.angle), math.cos(p.angle)
    tryMove(p, (cos * forward - sin * strafe) * MOVE_SPEED * dt,
               (sin * forward + cos * strafe) * MOVE_SPEED * dt)
  end
  if keysDown[keys.space] then shoot() end

  -- pickups
  for i = #game.items, 1, -1 do
    local item = game.items[i]
    local dx, dy = item.x - p.x, item.y - p.y
    if dx * dx + dy * dy < 0.4 then
      if item.kind == "ammo" then
        p.ammo = p.ammo + 12
        say("+12 ammo")
      else
        p.health = math.min(100, p.health + 30)
        say("+30 health")
      end
      table.remove(game.items, i)
    end
  end

  -- monsters hunt you down
  for _, monster in ipairs(game.monsters) do
    if monster.health > 0 then
      if monster.pain > 0 then monster.pain = monster.pain - 1 end
      if monster.cooldown > 0 then monster.cooldown = monster.cooldown - dt end
      local dx, dy = p.x - monster.x, p.y - monster.y
      local distance = math.sqrt(dx * dx + dy * dy)
      if distance < 10 and distance > 0.7 then
        tryMove(monster, dx / distance * monster.speed * dt,
                         dy / distance * monster.speed * dt)
      elseif distance <= 0.9 and monster.cooldown <= 0 then
        p.health = p.health - monster.damage
        monster.cooldown = 1.0
        game.hurt = 2
        if p.health <= 0 then
          game.state = "dead"
        end
      end
    end
  end
end

local function tick()
  update(FRAME)
  app:queueDraw()
  app:after(FRAME, tick)
end

------------------------------------------------------------------- input ---

function view:onKey(key)
  keysDown[key] = true
  if key == keys.r then
    newGame()
    keysDown = {}
  end
  return true
end

-- Held keys drive movement, so key_up matters here.
local originalDispatch = app.dispatch
app.dispatch = function(self, ev)
  if ev[1] == "key_up" then keysDown[ev[2]] = nil end
  return originalDispatch(self, ev)
end

app:after(FRAME, tick)
app:setFocus(view)
app:run()
