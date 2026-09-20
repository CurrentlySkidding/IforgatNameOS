--[[ Aurora OS installer ----------------------------------------------------

     Run this on any CC:Tweaked computer:

       wget run https://raw.githubusercontent.com/OWNER/REPO/main/install.lua

     Options (all optional):
       install OWNER/REPO [branch]     install from a different fork
       install --update                keep /home, replace the system
       install --uninstall             remove Aurora, keep /home

     Everything lands in /aurora, plus a /startup.lua that boots it.
----------------------------------------------------------------------------]]

local DEFAULT_REPO = "OWNER/REPO"
local DEFAULT_BRANCH = "main"

local args = { ... }

local repo, branch = DEFAULT_REPO, DEFAULT_BRANCH
local mode = "install"

for _, arg in ipairs(args) do
  if arg == "--update" then mode = "update"
  elseif arg == "--uninstall" then mode = "uninstall"
  elseif arg:find("/", 1, true) then repo = arg
  else branch = arg end
end

local BASE = ("https://raw.githubusercontent.com/%s/%s/"):format(repo, branch)

--------------------------------------------------------------------- ui -----

local w, h = term.getSize()
local colour = term.isColour()

local function paint(fg, bg)
  if colour then
    term.setTextColour(fg)
    if bg then term.setBackgroundColour(bg) end
  end
end

local function header()
  term.setBackgroundColour(colours.black)
  term.clear()
  term.setCursorPos(1, 1)
  paint(colours.cyan)
  print("Aurora OS")
  paint(colours.lightGrey)
  print("a desktop for CC:Tweaked")
  paint(colours.white)
  print("")
end

local function status(text, fg)
  paint(fg or colours.white)
  print(text)
  paint(colours.white)
end

local function progress(done, total, label)
  local barW = math.max(10, w - 8)
  local filled = math.floor(barW * (done / math.max(1, total)))
  local _, y = term.getCursorPos()
  term.setCursorPos(1, y)
  term.clearLine()
  paint(colours.lightGrey)
  term.write("[")
  paint(colours.cyan)
  term.write(string.rep("=", filled))
  paint(colours.grey)
  term.write(string.rep(".", barW - filled))
  paint(colours.lightGrey)
  term.write("] ")
  paint(colours.white)
  term.write(("%d%%"):format(math.floor(done / math.max(1, total) * 100)))
  if label then
    term.setCursorPos(1, y + 1)
    term.clearLine()
    paint(colours.lightGrey)
    term.write(label:sub(1, w))
    paint(colours.white)
  end
  term.setCursorPos(1, y)
end

--------------------------------------------------------------- uninstall ----

if mode == "uninstall" then
  header()
  status("This removes /aurora and /startup.lua.", colours.yellow)
  status("Your files in /home are left alone.")
  write("Type YES to continue: ")
  local answer = read()
  if answer ~= "YES" then
    status("Cancelled.", colours.red)
    return
  end
  if fs.exists("/aurora") then fs.delete("/aurora") end
  if fs.exists("/startup.lua") then fs.delete("/startup.lua") end
  status("Aurora removed.", colours.lime)
  return
end

------------------------------------------------------------------ checks ----

header()

if not http then
  status("The HTTP API is disabled on this computer.", colours.red)
  status("Enable it in the ComputerCraft config, or copy the files in by disk.")
  return
end

if repo == DEFAULT_REPO then
  status("This installer has not been pointed at a repository yet.", colours.red)
  status("Run it with your repo, for example:")
  paint(colours.lightGrey)
  print("  install yourname/aurora-os")
  paint(colours.white)
  return
end

status("Source: " .. repo .. " (" .. branch .. ")", colours.lightGrey)
print("")

------------------------------------------------------------------- fetch ----

local function fetch(path)
  local url = BASE .. path
  local handle, err = http.get(url)
  if not handle then return nil, tostring(err) end
  local data = handle.readAll()
  handle.close()
  return data
end

status("Reading the file list...")
local listing, listErr = fetch("files.txt")
if not listing then
  status("Could not reach GitHub: " .. tostring(listErr), colours.red)
  status("Check the repo name, the branch, and that the files are pushed.")
  return
end

local files = {}
for raw in (listing .. "\n"):gmatch("([^\n]*)\n") do
  local line = raw:gsub("[%s\r]+$", "")
  if line ~= "" and line:sub(1, 1) ~= "#" then files[#files + 1] = line end
end

if #files == 0 then
  status("files.txt is empty.", colours.red)
  return
end

status(("Downloading %d files..."):format(#files))
print("")

-- Stage everything first so a half-finished download cannot brick the boot.
local staging = "/.aurora-staging"
if fs.exists(staging) then fs.delete(staging) end
fs.makeDir(staging)

local failures = {}
for index, path in ipairs(files) do
  progress(index - 1, #files, path)
  local data, err = fetch(path)
  if data then
    local target = fs.combine(staging, path)
    local dir = fs.getDir(target)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local file = fs.open(target, "w")
    file.write(data)
    file.close()
  else
    failures[#failures + 1] = path .. " (" .. tostring(err) .. ")"
  end
end
progress(#files, #files, "done")
print("")
print("")

if #failures > 0 then
  status(("%d file(s) failed:"):format(#failures), colours.red)
  for i = 1, math.min(5, #failures) do status("  " .. failures[i], colours.red) end
  status("Nothing was installed.", colours.red)
  fs.delete(staging)
  return
end

------------------------------------------------------------------ install ---

status("Installing...")

if fs.exists("/aurora") then
  -- keep the user's settings and their own apps across an update
  local keep = { "etc", "var" }
  local backup = "/.aurora-keep"
  if fs.exists(backup) then fs.delete(backup) end
  fs.makeDir(backup)
  for _, name in ipairs(keep) do
    local from = fs.combine("/aurora", name)
    if fs.exists(from) then fs.copy(from, fs.combine(backup, name)) end
  end
  fs.delete("/aurora")
  for _, name in ipairs(keep) do
    local from = fs.combine(backup, name)
    if fs.exists(from) then
      if not fs.exists("/aurora") then fs.makeDir("/aurora") end
      fs.move(from, fs.combine("/aurora", name))
    end
  end
  fs.delete(backup)
end

for _, path in ipairs(files) do
  local from = fs.combine(staging, path)
  local to = "/" .. path
  local dir = fs.getDir(to)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  -- never clobber a config the user already has
  local isConfig = path:find("^aurora/etc/") ~= nil
  if fs.exists(to) and not (isConfig and mode == "update") then fs.delete(to) end
  if not fs.exists(to) then fs.move(from, to) end
end

fs.delete(staging)

for _, dir in ipairs({ "/home", "/home/Documents", "/home/Sheets",
                       "/home/Decks", "/home/Scripts", "/home/apps" }) do
  if not fs.exists(dir) then fs.makeDir(dir) end
end

print("")
status("Aurora is installed.", colours.lime)
print("")
paint(colours.lightGrey)
print("  F1        Activities overview")
print("  F2        All applications")
print("  Alt+Tab   Switch windows")
print("")
paint(colours.white)
write("Reboot into Aurora now? [Y/n] ")
local answer = read()
if answer == "" or answer:lower():sub(1, 1) == "y" then
  os.reboot()
else
  print("Run /startup.lua, or reboot when you are ready.")
end
