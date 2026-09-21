--[[ Web --------------------------------------------------------------------
     A browser for the little internet that lives on your network.

     Pages come from other Aurora computers over the encrypted network, are
     parsed into blocks, and drawn with clickable links.
----------------------------------------------------------------------------]]

local args    = { ... }
local App     = arequire("ui.app")
local base    = arequire("ui.widget")
local W       = arequire("ui.widgets")
local theme   = arequire("gfx.theme")
local util    = arequire("lib.util")
local net     = arequire("svc.net")
local web     = arequire("svc.web")
local appsSvc = arequire("svc.apps")

local app = App({ title = "Web" })

local state = {
  site = nil,            -- nil means the home directory
  path = "index",
  title = "Home",
  blocks = {},
  source = "",
  history = {},
  loading = false,
  error = nil,
}

------------------------------------------------------------------- chrome --

local backButton = W.IconButton({ icon = "\17", width = 3 })
local homeButton = W.IconButton({ icon = "\127", width = 3 })
local addressEntry = W.Entry({ placeholder = "computer/page", flat = true })
addressEntry.hexpand = true
local menuButton = W.IconButton({ icon = "\7", width = 3 })

local toolbar = W.Toolbar({ spacing = 0 })
toolbar:add(backButton)
toolbar:add(homeButton)
toolbar:add(addressEntry)
toolbar:add(menuButton)

---------------------------------------------------------------- page view --

local PageView = util.class(base.Widget)

function PageView:init()
  base.Widget.init(self, {})
  self.hexpand, self.vexpand = true, true
  self.focusable = true
  self.scroll = 0
  self.linkRects = {}
end

function PageView:measure() return 20, 6 end

function PageView:allocate(x, y, w, h)
  local changed = (w ~= self.w)
  base.Widget.allocate(self, x, y, w, h)
  if changed and self.onResize then self.onResize() end
end

function PageView:draw(s)
  local c = theme.c
  s:fill(self.x, self.y, self.w, self.h, " ", c.text, c.view)
  self.linkRects = {}

  if state.loading then
    s:writeCentered(self.y + math.floor(self.h / 2), "Loading\133", c.dim, c.view,
                    self.x, self.w)
    return
  end

  if state.error then
    s:writeCentered(self.y + math.floor(self.h / 2) - 1, "Cannot open that page",
                    c.destructive, c.view, self.x, self.w)
    s:writeCentered(self.y + math.floor(self.h / 2) + 1,
                    util.ellipsis(state.error, self.w - 2), c.dim, c.view,
                    self.x, self.w)
    return
  end

  local blocks = state.blocks
  local maxScroll = math.max(0, #blocks - self.h)
  if self.scroll > maxScroll then self.scroll = maxScroll end

  for row = 1, self.h do
    local block = blocks[self.scroll + row]
    if block then
      local y = self.y + row - 1
      local x = self.x + 1 + (block.indent or 0)

      if block.kind == "rule" then
        s:fill(self.x + 1, y, self.w - 2, 1, "\131", c.separator, c.view)
      elseif block.kind == "blank" then
        -- nothing to draw
      else
        local fg = c.text
        if block.kind == "heading" then fg = c.accent
        elseif block.kind == "sub" then fg = c.accentSoft
        elseif block.kind == "quote" then fg = c.dim end

        if block.bullet then
          s:write(self.x + 1, y, "\7", c.accentSoft, c.view)
        end
        if block.kind == "quote" then
          s:write(self.x + 1, y, "\149", c.separator, c.view)
        end

        s:write(x, y, block.text, fg, c.view)

        for _, link in ipairs(block.links or {}) do
          local lx = x + link.from - 1
          s:write(lx, y, link.label, c.accent, c.view)
          self.linkRects[#self.linkRects + 1] =
            { x = lx, y = y, w = #link.label, target = link.target }
        end
      end
    end
  end

  -- scrollbar
  if #blocks > self.h then
    local trackX = self.x + self.w - 1
    local thumb = math.max(1, math.floor(self.h * self.h / #blocks))
    local pos = math.floor((self.h - thumb) * (self.scroll / math.max(1, maxScroll)))
    for i = 0, thumb - 1 do
      s:write(trackX, self.y + pos + i, "\149", c.dim, c.view)
    end
  end
end

function PageView:onMouse(kind, button, px, py)
  if kind == "mouse_scroll" then
    self.scroll = math.max(0, self.scroll + button * 2)
    self:invalidate()
    return true
  end
  if kind == "mouse_click" then
    for _, rect in ipairs(self.linkRects) do
      if py == rect.y and px >= rect.x and px < rect.x + rect.w then
        self:emit("follow", rect.target)
        return true
      end
    end
    return true
  end
  return kind == "mouse_up"
end

function PageView:onKey(key)
  if key == keys.down then
    self.scroll = self.scroll + 1
  elseif key == keys.up then
    self.scroll = math.max(0, self.scroll - 1)
  elseif key == keys.pageDown then
    self.scroll = self.scroll + self.h
  elseif key == keys.pageUp then
    self.scroll = math.max(0, self.scroll - self.h)
  else
    return false
  end
  self:invalidate()
  return true
end

local pageView = PageView()

local root = base.Box({ orientation = "vertical", spacing = 0 })
root.hexpand, root.vexpand = true, true
root:add(toolbar)
root:add(pageView)
app:setRoot(root)

------------------------------------------------------------------ loading --

local function addressText()
  if not state.site then return "home" end
  return state.site .. "/" .. state.path
end

local function setBlocks(source)
  state.source = source or ""
  state.blocks = web.parse(state.source, math.max(12, pageView.w - 2))
  pageView.scroll = 0
end

--- Re-wrap without losing the reading position.
local function rewrap()
  if state.source == "" then return end
  state.blocks = web.parse(state.source, math.max(12, pageView.w - 2))
end

--- The home page is generated, not fetched: a directory of every site this
--- computer has heard announce itself.
local function showHome()
  state.site, state.path, state.error = nil, "index", nil
  state.title = "Home"
  local lines = { "# The Web", "" }
  local sites = web.siteList()
  if #sites == 0 then
    lines[#lines + 1] = "No sites found yet."
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Sites announce themselves every minute. Pick"
    lines[#lines + 1] = "\"Look for sites\" from the menu to ask now."
  else
    for _, site in ipairs(sites) do
      lines[#lines + 1] = ("* [%s](%d/index)%s")
        :format(site.title, site.id, site.online and "" or " (offline)")
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "---"
  lines[#lines + 1] = ("* [Your own site](%d/index)"):format(os.getComputerID())
  setBlocks(table.concat(lines, "\n"))
  addressEntry:setText("home", true)
  aurora.setTitle("Web")
  app:queueDraw()
end

local function load(site, path, remember)
  if site == nil then
    if remember ~= false and state.site then
      table.insert(state.history, { site = state.site, path = state.path })
    end
    showHome()
    return
  end

  if remember ~= false then
    table.insert(state.history, { site = state.site, path = state.path })
  end

  state.loading = true
  state.error = nil
  app:queueDraw()
  app:render()

  local body, err, title = web.fetch(site, path)
  state.loading = false

  if not body then
    state.error = err or "no reply"
    state.site, state.path = site, path
    addressEntry:setText(addressText(), true)
    app:queueDraw()
    return
  end

  state.site, state.path = site, path
  state.title = title or ("computer-" .. site)
  setBlocks(body)
  addressEntry:setText(addressText(), true)
  aurora.setTitle(util.ellipsis(state.title, 18))
  app:queueDraw()
end

local function goBack()
  local previous = table.remove(state.history)
  if not previous then return end
  if previous.site == nil then
    showHome()
  else
    load(previous.site, previous.path, false)
  end
end

local function follow(target)
  local site, path = web.resolve(target, state.site)
  load(site, path)
end

local function openAddress(text)
  text = util.trim(text)
  if text == "" or text == "home" then showHome() return end
  local site, path = web.resolve(text, state.site)
  load(site, path)
end

-------------------------------------------------------------------- menu ---

local function openMenu()
  app:menu(app.surface.w - 26, 2, {
    { label = "Look for sites", icon = "\15", action = function()
        local ok, err = net.start()
        if not ok then app:notify(err or "No modem", "error") return end
        web.discover()
        app:notify("Asking who is out there\133")
        app:after(1.5, showHome)
      end },
    { label = "Reload", icon = "\24", disabled = state.site == nil,
      action = function() load(state.site, state.path, false) end },
    { separator = true },
    { label = web.hosting and "Stop hosting" or "Start hosting", icon = "\254",
      action = function()
        web.hosting = not web.hosting
        web.saveConfig()
        if web.hosting then web.announce() end
        app:notify(web.hosting and "Now hosting your site" or "Hosting turned off")
      end },
    { label = "Edit my site", icon = "\187", action = function()
        web.ensure()
        appsSvc.launch("editor", { fs.combine(web.ROOT, "index.page") })
      end },
    { label = "My pages", icon = "\4", action = function()
        local items = {}
        for _, page in ipairs(web.pages()) do
          items[#items + 1] = { label = page, icon = "\171", action = function()
            appsSvc.launch("editor", { fs.combine(web.ROOT, page .. ".page") })
          end }
        end
        if #items == 0 then
          items[1] = { label = "No pages yet", disabled = true }
        end
        app:menu(4, 3, items, 20)
      end },
    { label = "Site name", icon = "\4", action = function()
        app:prompt({
          title = "What is your site called?",
          text = web.title(),
          onAccept = function(text)
            web.siteTitle = util.trim(text)
            web.saveConfig()
            web.announce()
            app:notify("Site renamed")
          end,
        })
      end },
  }, 26)
end

------------------------------------------------------------------ wiring ---

backButton:connect("clicked", goBack)
homeButton:connect("clicked", function() load(nil, nil, true) end)
menuButton:connect("clicked", openMenu)
addressEntry:connect("activate", function(_, text) openAddress(text) end)
pageView:connect("follow", function(_, target) follow(target) end)
pageView.onResize = rewrap

app:accel("ctrl+l", function() app:setFocus(addressEntry) end)
app:accel("ctrl+r", function()
  if state.site then load(state.site, state.path, false) end
end)
app:accel("backspace", goBack)
app:accel("alt+left", goBack)

app.onEvent = function(name, ...)
  if name == "aurora_open" then
    local target = select(1, ...)
    if target then openAddress(tostring(target)) end
  end
end

net.start()
web.ensure()
web.discover()

if args[1] then
  openAddress(tostring(args[1]))
else
  showHome()
end

app:setFocus(pageView)
app:run()
