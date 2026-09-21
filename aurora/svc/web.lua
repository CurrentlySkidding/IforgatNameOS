--[[ aurora.svc.web ----------------------------------------------------------
     A small internet for your world.

     Every Aurora computer can host a site: drop pages in /home/www and other
     computers on the same network key can browse them.  Sites announce
     themselves, so the browser's home page is a directory of everything it
     has heard from -- no DNS, no configuration.

     Pages use a deliberately tiny markup:

        # Heading            a heading
        ## Subheading
        * item               a bullet
        > quoted             a quote
        --- or ===           a rule
        [Shop](12/shop)      a link to page "shop" on computer 12
        [Docs](docs)         a link to another page on this site
        plain text           a paragraph, wrapped to the window
----------------------------------------------------------------------------]]

local util = arequire("lib.util")
local log  = arequire("kernel.log")
local net  = arequire("svc.net")

local web = {}

web.ROOT = "/home/www"
web.CONFIG = "/aurora/etc/web.cfg"
web.MAX_PAGE = 8192

web.sites = {}         -- id -> { id, name, title, lastSeen }
web.hosting = true
web.siteTitle = nil

------------------------------------------------------------------ config ---

function web.loadConfig()
  local cfg = util.readTable(web.CONFIG, nil) or {}
  web.hosting = cfg.hosting ~= false
  web.siteTitle = cfg.title
  return cfg
end

function web.saveConfig()
  util.writeTable(web.CONFIG, { hosting = web.hosting, title = web.siteTitle })
end

function web.title()
  return web.siteTitle or net.displayName or ("computer-" .. os.getComputerID())
end

--------------------------------------------------------------- the pages ---

local DEFAULT_INDEX = [[
# Welcome

This page is served from /home/www/index.page on this computer.

Edit it in the Text Editor and anyone on your network key can read it.

* Pages are plain text files ending in .page
* Link to another page like this: [About](about)
* Link to another computer like this: [Their site](12/index)

> Open the Web app's menu to turn hosting off.
]]

local DEFAULT_ABOUT = [[
# About this site

Hosted on an Aurora computer, somewhere in a Minecraft world.

[Back home](index)
]]

function web.ensure()
  if not fs.exists(web.ROOT) then
    pcall(fs.makeDir, web.ROOT)
    util.writeFile(fs.combine(web.ROOT, "index.page"), DEFAULT_INDEX)
    util.writeFile(fs.combine(web.ROOT, "about.page"), DEFAULT_ABOUT)
  end
end

local function sanitise(path)
  path = tostring(path or "index")
  path = path:gsub("%.page$", "")
  -- no climbing out of the web root
  if path:find("%.%.") or path:find(":") then return nil end
  path = path:gsub("^/+", ""):gsub("/+$", "")
  if path == "" then path = "index" end
  return path
end

function web.read(path)
  web.ensure()
  local clean = sanitise(path)
  if not clean then return nil, "bad path" end
  local file = fs.combine(web.ROOT, clean .. ".page")
  local data = util.readFile(file)
  if not data then return nil, "no such page" end
  return data:sub(1, web.MAX_PAGE)
end

function web.pages()
  web.ensure()
  local out = {}
  local ok, names = pcall(fs.list, web.ROOT)
  if not ok then return out end
  for _, name in ipairs(names) do
    local page = name:match("^(.+)%.page$")
    if page then out[#out + 1] = page end
  end
  table.sort(out)
  return out
end

-------------------------------------------------------------- the markup ---

--- Parse page source into drawable blocks.
--- Each block is { kind = "heading"|"sub"|"text"|"bullet"|"quote"|"rule",
---                 text = ..., links = { {label=, target=, from=, to=} } }
function web.parse(source, width)
  width = math.max(12, width or 40)
  local blocks = {}

  for _, raw in ipairs(util.splitAll(tostring(source or ""):gsub("\r", ""), "\n")) do
    local line = raw
    local kind = "text"
    if line:match("^%s*##%s") then
      kind, line = "sub", line:gsub("^%s*##%s+", "")
    elseif line:match("^%s*#%s") then
      kind, line = "heading", line:gsub("^%s*#%s+", "")
    elseif line:match("^%s*[%*%-]%s") then
      kind, line = "bullet", line:gsub("^%s*[%*%-]%s+", "")
    elseif line:match("^%s*>%s?") then
      kind, line = "quote", line:gsub("^%s*>%s?", "")
    elseif line:match("^%s*[%-=][%-=][%-=]+%s*$") then
      blocks[#blocks + 1] = { kind = "rule" }
      line = nil
    end

    if line ~= nil then
      if util.trim(line) == "" then
        blocks[#blocks + 1] = { kind = "blank" }
      else
        -- pull the links out, leaving their labels in the text
        local links = {}
        local plain = line:gsub("%[([^%]]*)%]%(([^%)]*)%)", function(label, target)
          links[#links + 1] = { label = label, target = target }
          return label
        end)

        local indent = (kind == "bullet" and 2) or (kind == "quote" and 3) or 0
        local lines = util.wrap(plain, width - indent)
        for i, text in ipairs(lines) do
          local block = { kind = kind, text = text, indent = indent, links = {} }
          if i == 1 and kind == "bullet" then block.bullet = true end
          -- work out which links fall on this wrapped line
          for _, link in ipairs(links) do
            local at = text:find(link.label, 1, true)
            if at and link.label ~= "" then
              block.links[#block.links + 1] = {
                label = link.label, target = link.target,
                from = at, to = at + #link.label - 1,
              }
            end
          end
          blocks[#blocks + 1] = block
        end
      end
    end
  end

  return blocks
end

--- Resolve a link target against the page you are on.
--- Returns siteId, path.
function web.resolve(target, currentSite)
  target = util.trim(tostring(target or ""))
  local site, path = target:match("^(%d+)/(.+)$")
  if site then return tonumber(site), path end
  site = target:match("^(%d+)$")
  if site then return tonumber(site), "index" end
  return currentSite, target
end

------------------------------------------------------------------ fetching --

--- Fetch a page from a computer.  Local requests skip the network entirely.
function web.fetch(siteId, path)
  if siteId == nil or siteId == os.getComputerID() then
    local data, err = web.read(path)
    if not data then return nil, err end
    return data
  end
  local data, err = net.request(siteId, "web.get", { path = path }, "web.page", 3)
  if not data then return nil, err end
  if data.error then return nil, data.error end
  return data.body, nil, data.title
end

------------------------------------------------------------------- sites ----

function web.noteSite(id, name, title)
  web.sites[tostring(id)] = {
    id = id,
    name = name or ("computer-" .. id),
    title = title,
    lastSeen = os.clock(),
  }
end

function web.siteList()
  local out = {}
  for _, site in pairs(web.sites) do
    out[#out + 1] = {
      id = site.id,
      name = site.name,
      title = site.title or site.name,
      online = site.lastSeen and (os.clock() - site.lastSeen) < 120,
    }
  end
  table.sort(out, function(a, b) return (a.title or ""):lower() < (b.title or ""):lower() end)
  return out
end

function web.announce()
  if not web.hosting then return end
  net.broadcast("web.site", { title = web.title() })
end

function web.discover()
  net.broadcast("web.who", {})
end

----------------------------------------------------------------- service ----

function web.service()
  web.loadConfig()
  web.ensure()
  net.subscribe("web.get", aurora.pid)
  net.subscribe("web.site", aurora.pid)
  net.subscribe("web.who", aurora.pid)

  local announceTimer = os.startTimer(45)
  while true do
    local event = table.pack(os.pullEvent())

    if event[1] == "aurora_net" then
      local kind, sender, data, name = event[2], event[3], event[4], event[5]

      if kind == "web.get" then
        if web.hosting then
          local body, err = web.read(data and data.path)
          net.send(sender, "web.page", body
            and { body = body, title = web.title(), path = data and data.path }
            or { error = err or "no such page" })
        else
          net.send(sender, "web.page", { error = "this computer is not hosting" })
        end

      elseif kind == "web.site" then
        web.noteSite(sender, name, data and data.title)

      elseif kind == "web.who" then
        if web.hosting then
          net.send(sender, "web.site", { title = web.title() })
        end
      end

    elseif event[1] == "timer" and event[2] == announceTimer then
      announceTimer = os.startTimer(45)
      pcall(web.announce)
    end
  end
end

return web
