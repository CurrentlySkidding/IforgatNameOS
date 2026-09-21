# The Little Quest
# A small Legend-of-Zelda-style adventure, written in SimpleLang.
#
# Move with W A S D (or the arrow keys).  Walk into a monster to hit it.
# Find the sword, grab the key, open the locked door, take the Triforce.
# Press Q to give up.

# ---------------------------------------------------------------- colours --
set WHITE to 1
set YELLOW to 16
set LIME to 32
set GREY to 256
set CYAN to 512
set RED to 16384
set BLACK to 32768

# ------------------------------------------------------------------ world --
# #  wall        .  floor       +  doorway      D  locked door
# S  sword       K  key         $  rupee        T  the Triforce

set rooms to [
  [
    "################",
    "#..............#",
    "#...S..........#",
    "#..............+",
    "#........$.....#",
    "#..............#",
    "################"
  ],
  [
    "################",
    "#....##...##...#",
    "#....##...##...#",
    "+.......K......+",
    "#....##...##...#",
    "#....##...##...#",
    "################"
  ],
  [
    "################",
    "#..$........$..#",
    "#..............#",
    "+..............D",
    "#..............#",
    "#..$........$..#",
    "################"
  ],
  [
    "################",
    "#..............#",
    "#..............#",
    "+.......T......#",
    "#..............#",
    "#..............#",
    "################"
  ]
]

# Each doorway: from room, x, y, to room, x, y
set doors to [
  [1, 16, 4, 2, 2, 4],
  [2, 1, 4, 1, 15, 4],
  [2, 16, 4, 3, 2, 4],
  [3, 1, 4, 2, 15, 4],
  [3, 16, 4, 4, 2, 4],
  [4, 1, 4, 3, 15, 4]
]

# Each monster: x, y, room, alive
set monsters to [
  [6, 2, 2, 1],
  [11, 5, 2, 1],
  [5, 2, 3, 1],
  [12, 5, 3, 1],
  [8, 5, 3, 1]
]

# ----------------------------------------------------------------- player --
set px to 3
set py to 4
set room to 1
set hearts to 3
set keys to 0
set rupees to 0
set sword to 0
set won to 0
set message to "Find the sword."

# ------------------------------------------------------------------ tiles --

to tileAt with r, x, y
  if y < 1 then give "#" end
  if y > len(rooms[r]) then give "#" end
  set row to rooms[r][y]
  if x < 1 then give "#" end
  if x > len(row) then give "#" end
  give row[x]
end

to setTile with r, x, y, ch
  set row to rooms[r][y]
  set rooms[r][y] to piece(row, 1, x - 1) + ch + piece(row, x + 1, len(row))
end

to monsterAt with x, y
  for i from 1 to len(monsters)
    set m to monsters[i]
    if m[4] == 1 and m[3] == room and m[1] == x and m[2] == y then
      give i
    end
  end
  give 0
end

# ------------------------------------------------------------------ drawing --

to render
  clear()
  set top to 3

  draw(2, 1, "The Little Quest", CYAN, BLACK)

  set bar to ""
  repeat hearts times
    set bar to bar + "<3 "
  end
  draw(2, 2, bar, RED, BLACK)
  draw(14, 2, "key " + keys, YELLOW, BLACK)
  draw(22, 2, "gem " + rupees, CYAN, BLACK)
  if sword == 1 then
    draw(30, 2, "sword", WHITE, BLACK)
  end

  for y from 1 to len(rooms[room])
    set row to rooms[room][y]
    for x from 1 to len(row)
      set ch to row[x]
      set colour to GREY
      if ch == "." then set ch to " " end
      if ch == "S" then set colour to WHITE end
      if ch == "K" then set colour to YELLOW end
      if ch == "$" then set colour to CYAN end
      if ch == "T" then set colour to YELLOW end
      if ch == "D" then set colour to YELLOW end
      if ch == "+" then set colour to GREY end
      draw(x + 2, top + y, ch, colour, BLACK)
    end
  end

  for i from 1 to len(monsters)
    set m to monsters[i]
    if m[4] == 1 and m[3] == room then
      draw(m[1] + 2, top + m[2], "&", RED, BLACK)
    end
  end

  draw(px + 2, top + py, "@", LIME, BLACK)
  draw(2, top + len(rooms[room]) + 2, message, WHITE, BLACK)
end

# ------------------------------------------------------------------ moving --

to useDoor with x, y
  for i from 1 to len(doors)
    set d to doors[i]
    if d[1] == room and d[2] == x and d[3] == y then
      set room to d[4]
      set px to d[5]
      set py to d[6]
      set message to "Room " + room + "."
      give 1
    end
  end
  give 0
end

to pickUp with ch, x, y
  if ch == "S" then
    set sword to 1
    set message to "A sword! Walk into monsters."
    call setTile with room, x, y, "."
  end
  if ch == "K" then
    set keys to keys + 1
    set message to "A key. Something is locked."
    call setTile with room, x, y, "."
  end
  if ch == "$" then
    set rupees to rupees + 1
    set message to "A gem. Shiny."
    call setTile with room, x, y, "."
  end
  if ch == "T" then
    set won to 1
  end
end

to tryMove with dx, dy
  set nx to px + dx
  set ny to py + dy

  set hit to monsterAt(nx, ny)
  if hit > 0 then
    if sword == 1 then
      set monsters[hit][4] to 0
      set message to "You strike it down."
    else
      set hearts to hearts - 1
      set message to "It hurts! You need a sword."
    end
    give nothing
  end

  set ch to tileAt(room, nx, ny)

  if ch == "#" then
    give nothing
  end

  if ch == "D" then
    if keys > 0 then
      set keys to keys - 1
      call setTile with room, nx, ny, "+"
      set message to "The lock opens."
    else
      set message to "It is locked."
    end
    give nothing
  end

  if ch == "+" then
    set opened to useDoor(nx, ny)
    if opened == 1 then
      give nothing
    end
  end

  set px to nx
  set py to ny
  call pickUp with ch, nx, ny
end

to moveMonsters
  for i from 1 to len(monsters)
    set m to monsters[i]
    if m[4] == 1 and m[3] == room then
      set mx to m[1]
      set my to m[2]
      set dx to 0
      set dy to 0
      if px > mx then set dx to 1 end
      if px < mx then set dx to 0 - 1 end
      if py > my then set dy to 1 end
      if py < my then set dy to 0 - 1 end

      # step one axis at a time so they shuffle instead of gliding
      if random(1, 2) == 1 then
        set dy to 0
      else
        set dx to 0
      end

      set tx to mx + dx
      set ty to my + dy

      if tx == px and ty == py then
        set hearts to hearts - 1
        set message to "The monster bites you!"
      else if tileAt(room, tx, ty) == "." and monsterAt(tx, ty) == 0 then
        set monsters[i][1] to tx
        set monsters[i][2] to ty
      end
    end
  end
end

# -------------------------------------------------------------------- play --

say "The Little Quest"
say ""
say "W A S D to move, or the arrow keys."
say "Walk into a monster to attack it."
say "Q gives up."
say ""
say "Press any key to begin."
set ignored to key()

forever
  call render

  if won == 1 then
    stop
  end
  if hearts < 1 then
    stop
  end

  set k to key()

  if k == "q" then
    set message to "You walked away."
    stop
  end

  if k == "w" or k == "up" then
    call tryMove with 0, 0 - 1
  end
  if k == "s" or k == "down" then
    call tryMove with 0, 1
  end
  if k == "a" or k == "left" then
    call tryMove with 0 - 1, 0
  end
  if k == "d" or k == "right" then
    call tryMove with 1, 0
  end

  if won == 0 and hearts > 0 then
    call moveMonsters
  end
end

clear()
if won == 1 then
  say "You lift the Triforce above your head."
  say "Gems collected: " + rupees
  say ""
  say "THE QUEST IS COMPLETE"
else if hearts < 1 then
  say "You fall. The monsters win this time."
  say "Gems collected: " + rupees
else
  say "You walked away from the quest."
  say "Gems collected: " + rupees
end
