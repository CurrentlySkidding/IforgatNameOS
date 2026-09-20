--[[ aurora.kernel.vfs -------------------------------------------------------
     File services layered on top of CC's `fs`: a trash can, bookmarks, a
     recent-files list, and the type registry that decides which app opens
     which file.
----------------------------------------------------------------------------]]

local util = arequire("lib.util")
local log  = arequire("kernel.log")

local vfs = {}

vfs.HOME    = "/home"
vfs.TRASH   = "/home/.trash"
vfs.CONFIG  = "/aurora/etc"
vfs.VAR     = "/aurora/var"
vfs.USERAPPS = "/home/apps"

--------------------------------------------------------------- file types ---

-- kind: text | code | doc | sheet | slides | image | archive | binary | folder
vfs.types = {
  lua  = { kind = "code",  label = "Lua source",     app = "editor",  colour = colours.blue,      char = "\187" },
  txt  = { kind = "text",  label = "Plain text",     app = "editor",  colour = colours.lightGrey, char = "\171" },
  md   = { kind = "text",  label = "Markdown",       app = "writer",  colour = colours.cyan,      char = "\171" },
  adoc = { kind = "doc",   label = "Aurora document", app = "writer", colour = colours.lightBlue, char = "\254" },
  asheet = { kind = "sheet", label = "Aurora sheet", app = "sheets",  colour = colours.green,     char = "\254" },
  csv  = { kind = "sheet", label = "CSV table",      app = "sheets",  colour = colours.lime,      char = "\254" },
  adeck = { kind = "slides", label = "Aurora deck",  app = "slides",  colour = colours.orange,    char = "\254" },
  aapp = { kind = "code",  label = "Aurora project", app = "builder", colour = colours.magenta,   char = "\254" },
  cfg  = { kind = "text",  label = "Configuration",  app = "editor",  colour = colours.yellow,    char = "\171" },
  json = { kind = "text",  label = "JSON data",      app = "editor",  colour = colours.yellow,    char = "\171" },
  log  = { kind = "text",  label = "Log file",       app = "editor",  colour = colours.lightGrey, char = "\171" },
  nfp  = { kind = "image", label = "Paint image",    app = nil,       colour = colours.purple,    char = "\254" },
  nft  = { kind = "image", label = "Paint image",    app = nil,       colour = colours.purple,    char = "\254" },
}

vfs.folderType = { kind = "folder", label = "Folder", colour = colours.lightBlue, char = "\254" }

function vfs.typeOf(path)
  if fs.isDir(path) then return vfs.folderType end
  local ext = util.extension(path)
  return vfs.types[ext] or {
    kind = "binary", label = ext == "" and "File" or (ext:upper() .. " file"),
    app = "editor", colour = colours.lightGrey, char = "\171",
  }
end

------------------------------------------------------------------- setup ----

function vfs.ensure()
  for _, dir in ipairs({ vfs.HOME, vfs.TRASH, vfs.CONFIG, vfs.VAR, vfs.USERAPPS,
                         vfs.HOME .. "/Documents", vfs.HOME .. "/Sheets",
                         vfs.HOME .. "/Decks", vfs.HOME .. "/Scripts" }) do
    if not fs.exists(dir) then
      local ok, err = pcall(fs.makeDir, dir)
      if not ok then log.warn("vfs", "makeDir " .. dir .. ": " .. tostring(err)) end
    end
  end
end

------------------------------------------------------------------ places ----

function vfs.places()
  local list = {
    { name = "Home",      path = vfs.HOME,                 char = "\127", colour = colours.lightBlue },
    { name = "Documents", path = vfs.HOME .. "/Documents", char = "\254", colour = colours.blue },
    { name = "Sheets",    path = vfs.HOME .. "/Sheets",    char = "\254", colour = colours.green },
    { name = "Decks",     path = vfs.HOME .. "/Decks",     char = "\254", colour = colours.orange },
    { name = "Scripts",   path = vfs.HOME .. "/Scripts",   char = "\187", colour = colours.magenta },
    { name = "Apps",      path = vfs.USERAPPS,             char = "\254", colour = colours.purple },
    { name = "System",    path = "/aurora",                char = "\015", colour = colours.lightGrey },
    { name = "ROM",       path = "/rom",                   char = "\015", colour = colours.lightGrey },
    { name = "Trash",     path = vfs.TRASH,                char = "\233", colour = colours.red },
  }
  for _, disk in ipairs(peripheral.getNames()) do
    if peripheral.getType(disk) == "drive" then
      local d = peripheral.wrap(disk)
      if d and d.getMountPath and d.getMountPath() then
        list[#list + 1] = {
          name = (d.getDiskLabel and d.getDiskLabel()) or "Disk",
          path = d.getMountPath(), char = "\007", colour = colours.yellow, removable = true,
        }
      end
    end
  end
  local saved = util.readTable(vfs.CONFIG .. "/bookmarks.cfg", nil)
  if saved then
    for _, b in ipairs(saved) do
      if fs.exists(b.path) then
        list[#list + 1] = { name = b.name, path = b.path, char = "\004",
                            colour = colours.cyan, bookmark = true }
      end
    end
  end
  return list
end

function vfs.addBookmark(path)
  local saved = util.readTable(vfs.CONFIG .. "/bookmarks.cfg", {})
  for _, b in ipairs(saved) do if b.path == path then return false end end
  saved[#saved + 1] = { name = fs.getName(path), path = path }
  util.writeTable(vfs.CONFIG .. "/bookmarks.cfg", saved)
  return true
end

function vfs.removeBookmark(path)
  local saved = util.readTable(vfs.CONFIG .. "/bookmarks.cfg", {})
  for i, b in ipairs(saved) do
    if b.path == path then
      table.remove(saved, i)
      util.writeTable(vfs.CONFIG .. "/bookmarks.cfg", saved)
      return true
    end
  end
  return false
end

------------------------------------------------------------------ listing ---

--- List a directory as entry tables, folders first then alphabetical.
function vfs.list(path, showHidden)
  if not fs.exists(path) or not fs.isDir(path) then return {}, "not a folder" end
  local ok, names = pcall(fs.list, path)
  if not ok then return {}, tostring(names) end
  local entries = {}
  for _, name in ipairs(names) do
    if showHidden or name:sub(1, 1) ~= "." then
      local full = fs.combine(path, name)
      local isDir = fs.isDir(full)
      local size = 0
      if not isDir then
        local sizeOk, value = pcall(fs.getSize, full)
        size = sizeOk and value or 0
      end
      entries[#entries + 1] = {
        name = name,
        path = full,
        isDir = isDir,
        size = size,
        readOnly = fs.isReadOnly(full),
        type = isDir and vfs.folderType or vfs.typeOf(full),
      }
    end
  end
  table.sort(entries, function(a, b)
    if a.isDir ~= b.isDir then return a.isDir end
    return a.name:lower() < b.name:lower()
  end)
  return entries
end

function vfs.parent(path)
  if path == "" or path == "/" then return "/" end
  local dir = fs.getDir(path)
  return dir == "" and "/" or dir
end

function vfs.breadcrumbs(path)
  local parts = { { name = "/", path = "/" } }
  local acc = ""
  for _, piece in ipairs(util.split(path, "/")) do
    acc = acc == "" and piece or (acc .. "/" .. piece)
    parts[#parts + 1] = { name = piece, path = "/" .. acc }
  end
  return parts
end

--------------------------------------------------------------- operations ---

local function uniquePath(target)
  if not fs.exists(target) then return target end
  local dir = fs.getDir(target)
  local name = fs.getName(target)
  local base, ext = name:match("^(.-)(%.[%w_]+)$")
  base = base or name
  ext = ext or ""
  local n = 2
  while true do
    local candidate = fs.combine(dir, ("%s (%d)%s"):format(base, n, ext))
    if not fs.exists(candidate) then return candidate end
    n = n + 1
  end
end
vfs.uniquePath = uniquePath

function vfs.copy(src, destDir)
  local target = uniquePath(fs.combine(destDir, fs.getName(src)))
  local ok, err = pcall(fs.copy, src, target)
  if not ok then return nil, tostring(err) end
  return target
end

function vfs.move(src, destDir)
  local target = uniquePath(fs.combine(destDir, fs.getName(src)))
  local ok, err = pcall(fs.move, src, target)
  if not ok then return nil, tostring(err) end
  return target
end

function vfs.rename(path, newName)
  local target = fs.combine(fs.getDir(path), newName)
  if fs.exists(target) then return nil, "a file with that name already exists" end
  local ok, err = pcall(fs.move, path, target)
  if not ok then return nil, tostring(err) end
  return target
end

--- Move to trash, remembering where it came from so it can be restored.
function vfs.trash(path)
  if fs.isReadOnly(path) then return nil, "read-only" end
  if not fs.exists(vfs.TRASH) then fs.makeDir(vfs.TRASH) end
  local target = uniquePath(fs.combine(vfs.TRASH, fs.getName(path)))
  local ok, err = pcall(fs.move, path, target)
  if not ok then return nil, tostring(err) end
  local index = util.readTable(vfs.VAR .. "/trash.idx", {})
  index[fs.getName(target)] = { origin = path, at = os.epoch("utc") }
  util.writeTable(vfs.VAR .. "/trash.idx", index)
  return target
end

function vfs.restore(trashedPath)
  local index = util.readTable(vfs.VAR .. "/trash.idx", {})
  local entry = index[fs.getName(trashedPath)]
  if not entry then return nil, "unknown origin" end
  local target = uniquePath(entry.origin)
  local dir = fs.getDir(target)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local ok, err = pcall(fs.move, trashedPath, target)
  if not ok then return nil, tostring(err) end
  index[fs.getName(trashedPath)] = nil
  util.writeTable(vfs.VAR .. "/trash.idx", index)
  return target
end

function vfs.emptyTrash()
  local n = 0
  for _, name in ipairs(fs.list(vfs.TRASH)) do
    if pcall(fs.delete, fs.combine(vfs.TRASH, name)) then n = n + 1 end
  end
  util.writeTable(vfs.VAR .. "/trash.idx", {})
  return n
end

function vfs.delete(path)
  local ok, err = pcall(fs.delete, path)
  if not ok then return false, tostring(err) end
  return true
end

function vfs.newFolder(parent, name)
  local target = uniquePath(fs.combine(parent, name or "New Folder"))
  local ok, err = pcall(fs.makeDir, target)
  if not ok then return nil, tostring(err) end
  return target
end

function vfs.newFile(parent, name, contents)
  local target = uniquePath(fs.combine(parent, name or "Untitled.txt"))
  if not util.writeFile(target, contents or "") then return nil, "cannot write" end
  return target
end

----------------------------------------------------------------- recents ----

function vfs.touchRecent(path)
  local recents = util.readTable(vfs.VAR .. "/recent.idx", {})
  for i, entry in ipairs(recents) do
    if entry.path == path then table.remove(recents, i) break end
  end
  table.insert(recents, 1, { path = path, at = os.epoch("utc") })
  while #recents > 20 do table.remove(recents) end
  util.writeTable(vfs.VAR .. "/recent.idx", recents)
end

function vfs.recents()
  local recents = util.readTable(vfs.VAR .. "/recent.idx", {})
  local out = {}
  for _, entry in ipairs(recents) do
    if fs.exists(entry.path) then out[#out + 1] = entry end
  end
  return out
end

--------------------------------------------------------------- clipboard ----

-- Modules are shared by every process, so this is the system-wide clipboard.
vfs.clipboard = { paths = {}, mode = "copy" }

function vfs.copyToClipboard(paths, mode)
  vfs.clipboard = { paths = paths, mode = mode or "copy" }
end

function vfs.pasteInto(destDir)
  local results, errors = {}, {}
  for _, path in ipairs(vfs.clipboard.paths or {}) do
    if fs.exists(path) then
      local target, err
      if vfs.clipboard.mode == "cut" then
        target, err = vfs.move(path, destDir)
      else
        target, err = vfs.copy(path, destDir)
      end
      if target then results[#results + 1] = target else errors[#errors + 1] = err end
    end
  end
  if vfs.clipboard.mode == "cut" then vfs.clipboard = { paths = {}, mode = "copy" } end
  return results, errors
end

------------------------------------------------------------------- usage ----

function vfs.usage()
  local free = fs.getFreeSpace("/")
  local capacity = fs.getCapacity and fs.getCapacity("/") or nil
  if type(free) ~= "number" then free = 0 end
  if not capacity then capacity = free * 2 end
  return { free = free, capacity = capacity, used = math.max(0, capacity - free) }
end

return vfs
