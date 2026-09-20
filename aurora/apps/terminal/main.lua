--[[ Terminal ---------------------------------------------------------------
     Runs an unmodified CraftOS shell inside an Aurora window.  The kernel has
     already pointed the global `term` API at this window's buffer, so every
     ROM program -- edit, lua, worm, paint -- works exactly as it does on a
     bare computer.
----------------------------------------------------------------------------]]

local args  = { ... }
local theme = arequire("gfx.theme")
local util  = arequire("lib.util")
local log   = arequire("kernel.log")

local w, h = term.getSize()

term.setBackgroundColour(theme.c.view)
term.setTextColour(theme.c.text)
term.clear()
term.setCursorPos(1, 1)

--------------------------------------------------------------------- banner --

-- os.version() returns a string like "CraftOS 1.9"; keep it simple and safe.
local function safeVersion()
  local ok, value = pcall(os.version)
  return ok and tostring(value) or "CraftOS"
end

term.setTextColour(theme.c.accent)
term.write("Aurora Terminal")
term.setCursorPos(1, 2)
term.setTextColour(theme.c.dim)
term.write(util.ellipsis(safeVersion() .. "  \183  "
  .. (os.getComputerLabel() or ("computer " .. os.getComputerID())), w))
term.setCursorPos(1, 4)
term.setTextColour(theme.c.text)

aurora.setTitle("Terminal")

------------------------------------------------------------------ run it ----

-- Opening a .lua file from Files starts the terminal with that program.
if args[1] and fs.exists(args[1]) and not fs.isDir(args[1]) then
  aurora.setTitle(fs.getName(args[1]))
  term.setTextColour(theme.c.dim)
  print("Running " .. args[1])
  term.setTextColour(theme.c.text)
  local ok, err = pcall(os.run, {}, args[1], table.unpack(args, 2))
  if not ok then
    term.setTextColour(theme.c.destructive)
    print(tostring(err))
    term.setTextColour(theme.c.text)
  end
  print("")
  aurora.setTitle("Terminal")
end

local ok, err = pcall(os.run, {}, "/rom/programs/shell.lua")
if not ok then
  log.error("terminal", tostring(err))
  term.setTextColour(theme.c.destructive)
  print("Shell stopped: " .. tostring(err))
  term.setTextColour(theme.c.dim)
  print("Press any key to close this window.")
  os.pullEvent("key")
end
