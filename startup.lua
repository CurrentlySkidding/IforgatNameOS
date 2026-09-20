--[[ Aurora OS boot stub ------------------------------------------------------
     Dropped at the root of the computer so CC:Tweaked runs it on power-on.
     Everything else lives under /aurora.
----------------------------------------------------------------------------]]

local BOOT = "/aurora/boot.lua"

-- Aurora runs real CraftOS shells inside its Terminal app, and those shells
-- re-run the startup scripts.  This guard stops us booting inside ourselves.
if _G.AURORA_RUNNING then return end

if not fs.exists(BOOT) then
  term.setTextColour(colours.red)
  print("Aurora OS is not installed (missing " .. BOOT .. ").")
  term.setTextColour(colours.white)
  print("Run the installer again to repair it.")
  return
end

local handle = fs.open(BOOT, "r")
local src = handle.readAll()
handle.close()

local fn, err = load(src, "@" .. BOOT, "t", _G)
if not fn then
  printError("Aurora boot image is damaged: " .. tostring(err))
  return
end

local ok, bootErr = pcall(fn)
if not ok then
  term.setBackgroundColour(colours.black)
  term.setTextColour(colours.white)
  term.clear()
  term.setCursorPos(1, 1)
  print("Aurora OS halted.")
  print("")
  printError(tostring(bootErr))
  print("")
  print("Press any key to return to the CraftOS shell.")
  os.pullEvent("key")
  term.setBackgroundColour(colours.black)
  term.clear()
  term.setCursorPos(1, 1)
end
