--[[ aurora.svc.apps --------------------------------------------------------
     The application registry.  Scans the system app folder and the user's
     own /home/apps folder for manifests, and knows how to launch them and
     which one opens a given file type.
----------------------------------------------------------------------------]]

local util  = arequire("lib.util")
local log   = arequire("kernel.log")
local sched = arequire("kernel.sched")
local vfs   = arequire("kernel.vfs")

local apps = {}

apps.SYSTEM_DIR = "/aurora/apps"
apps.USER_DIR   = "/home/apps"

apps.registry = {}    -- id -> manifest
apps.order = {}       -- ids, sorted for the app grid

local DEFAULT_MANIFEST = {
  name = "Untitled app",
  summary = "",
  category = "Other",
  main = "main.lua",
  window = { w = 40, h = 14 },
  icon = { colour = colours.blue, glyph = "A" },
  char = "\254",
}

--- Read an app manifest.  Preferred form is manifest.lua, a Lua chunk that
--- returns a table (so it can use the `colours` API); a serialised `manifest`
--- file is also accepted, and an app with neither but a main.lua still runs.
local function loadManifest(dir, id, source)
  local manifest
  local luaPath = fs.combine(dir, "manifest.lua")
  if fs.exists(luaPath) then
    local src = util.readFile(luaPath)
    local chunk, err = src and load(src, "@" .. luaPath, "t", _G)
    if chunk then
      local ok, value = pcall(chunk)
      if ok and type(value) == "table" then
        manifest = value
      else
        log.warn("apps", "manifest " .. id .. ": " .. tostring(value))
      end
    elseif err then
      log.warn("apps", "manifest " .. id .. ": " .. tostring(err))
    end
  end
  if not manifest then
    manifest = util.readTable(fs.combine(dir, "manifest"), nil)
  end
  if not manifest then
    -- An app can also ship a single main.lua with no manifest.
    if not fs.exists(fs.combine(dir, "main.lua")) then return nil end
    manifest = { name = id }
  end
  local merged = util.deepCopy(DEFAULT_MANIFEST)
  util.merge(merged, manifest)
  merged.id = manifest.id or id
  merged.dir = dir
  merged.path = fs.combine(dir, merged.main or "main.lua")
  merged.source = source
  if not fs.exists(merged.path) then return nil end
  return merged
end

function apps.scan()
  apps.registry = {}
  apps.order = {}
  for _, entry in ipairs({ { dir = apps.SYSTEM_DIR, source = "system" },
                           { dir = apps.USER_DIR, source = "user" } }) do
    if fs.exists(entry.dir) and fs.isDir(entry.dir) then
      for _, name in ipairs(fs.list(entry.dir)) do
        local dir = fs.combine(entry.dir, name)
        if fs.isDir(dir) then
          local manifest = loadManifest(dir, name, entry.source)
          if manifest then
            apps.registry[manifest.id] = manifest
            apps.order[#apps.order + 1] = manifest.id
          end
        end
      end
    end
  end
  table.sort(apps.order, function(a, b)
    local ma, mb = apps.registry[a], apps.registry[b]
    if ma.category ~= mb.category then return ma.category < mb.category end
    return ma.name:lower() < mb.name:lower()
  end)
  log.info("apps", ("registry: %d apps"):format(#apps.order))
  return apps.order
end

function apps.get(id) return apps.registry[id] end

function apps.all()
  local out = {}
  for _, id in ipairs(apps.order) do out[#out + 1] = apps.registry[id] end
  return out
end

function apps.byCategory()
  local groups, order = {}, {}
  for _, manifest in ipairs(apps.all()) do
    if not groups[manifest.category] then
      groups[manifest.category] = {}
      order[#order + 1] = manifest.category
    end
    table.insert(groups[manifest.category], manifest)
  end
  return groups, order
end

function apps.search(query)
  query = util.trim(query or ""):lower()
  if query == "" then return apps.all() end
  local out = {}
  for _, manifest in ipairs(apps.all()) do
    local haystack = (manifest.name .. " " .. (manifest.summary or "") .. " " ..
                      (manifest.keywords or "")):lower()
    if haystack:find(query, 1, true) then out[#out + 1] = manifest end
  end
  return out
end

--------------------------------------------------------------- favourites ---

local FAVOURITES_PATH = "/aurora/etc/favourites.cfg"

function apps.favourites()
  local saved = util.readTable(FAVOURITES_PATH, nil)
  if not saved then
    saved = { "files", "terminal", "assistant", "messages", "web" }
  end
  local out = {}
  for _, id in ipairs(saved) do
    if apps.registry[id] then out[#out + 1] = apps.registry[id] end
  end
  return out
end

function apps.setFavourites(ids)
  util.writeTable(FAVOURITES_PATH, ids)
end

function apps.toggleFavourite(id)
  local saved = util.readTable(FAVOURITES_PATH, nil)
  if not saved then
    saved = {}
    for _, m in ipairs(apps.favourites()) do saved[#saved + 1] = m.id end
  end
  local index = util.indexOf(saved, id)
  if index then table.remove(saved, index) else saved[#saved + 1] = id end
  apps.setFavourites(saved)
  return index == nil
end

------------------------------------------------------------------ launch ----

--- Launch an app by id.  Existing singleton instances are raised instead.
function apps.launch(id, args, opts)
  opts = opts or {}
  local manifest = apps.registry[id]
  if not manifest then
    log.warn("apps", "no such app: " .. tostring(id))
    return nil, "no such app: " .. tostring(id)
  end

  if manifest.singleton and not opts.forceNew then
    local existing = sched.find(id)
    if existing then
      if args and #args > 0 then
        sched.post(existing, "aurora_open", table.unpack(args))
      end
      sched.restore(existing)
      return existing
    end
  end

  local window = false
  if manifest.window ~= false then
    window = {
      w = manifest.window and manifest.window.w,
      h = manifest.window and manifest.window.h,
      resizable = not (manifest.window and manifest.window.resizable == false),
    }
  end

  local proc, err = sched.spawn({
    name = manifest.id,
    appId = manifest.id,
    title = manifest.name,
    icon = { char = manifest.char, colour = manifest.icon and manifest.icon.colour },
    path = manifest.path,
    args = args or {},
    window = window,
    display = opts.display,
    meta = { manifest = manifest },
    env = { APP_DIR = manifest.dir, APP_ID = manifest.id },
  })
  if not proc then
    log.error("apps", "launch " .. id .. ": " .. tostring(err))
    return nil, err
  end
  return proc
end

--------------------------------------------------------------- open file ----

--- Pick the right app for a path and open it there.
function apps.openFile(path)
  if fs.isDir(path) then
    return apps.launch("files", { path })
  end
  local fileType = vfs.typeOf(path)
  local target = fileType.app or "editor"
  if not apps.registry[target] then target = "editor" end
  vfs.touchRecent(path)
  return apps.launch(target, { path })
end

--- Every app that declares it can handle this file's kind.
function apps.openersFor(path)
  local fileType = vfs.typeOf(path)
  local out = {}
  for _, manifest in ipairs(apps.all()) do
    local handles = manifest.handles or {}
    for _, kind in ipairs(handles) do
      if kind == fileType.kind or kind == "*" then
        out[#out + 1] = manifest
        break
      end
    end
  end
  return out
end

--------------------------------------------------------------- scaffolds ----

--- Create a new user app folder.  Used by the App Builder's export.
function apps.createUserApp(id, manifest, source)
  local dir = fs.combine(apps.USER_DIR, id)
  if fs.exists(dir) then return nil, "an app with that id already exists" end
  fs.makeDir(dir)
  manifest.id = id
  manifest.main = manifest.main or "main.lua"
  util.writeFile(fs.combine(dir, "manifest.lua"),
                 "return " .. textutils.serialise(manifest) .. "\n")
  util.writeFile(fs.combine(dir, manifest.main), source or "")
  apps.scan()
  return dir
end

function apps.deleteUserApp(id)
  local manifest = apps.registry[id]
  if not manifest or manifest.source ~= "user" then return false, "not a user app" end
  local ok, err = pcall(fs.delete, manifest.dir)
  if not ok then return false, tostring(err) end
  apps.scan()
  return true
end

return apps
