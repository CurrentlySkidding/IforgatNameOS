--[[ Settings ---------------------------------------------------------------
     Appearance, displays, printers, applications and system information.
----------------------------------------------------------------------------]]

local args       = { ... }
local App        = arequire("ui.app")
local base       = arequire("ui.widget")
local W          = arequire("ui.widgets")
local theme      = arequire("gfx.theme")
local util       = arequire("lib.util")
local pixel      = arequire("gfx.pixel")
local kernel     = arequire("kernel.init")
local sched      = arequire("kernel.sched")
local devices    = arequire("kernel.devices")
local vfs        = arequire("kernel.vfs")
local log        = arequire("kernel.log")
local appsSvc    = arequire("svc.apps")
local printer    = arequire("svc.printer")
local displaySvc = arequire("svc.display")
local wallpaper  = arequire("shell.wallpaper")
local compositor = arequire("gfx.compositor")

local app = App({ title = "Settings" })

local SECTIONS = {
  { id = "appearance", label = "Appearance", icon = "\7" },
  { id = "displays",   label = "Displays",   icon = "\254" },
  { id = "printers",   label = "Printers",   icon = "\22" },
  { id = "network",    label = "Network",    icon = "\15" },
  { id = "apps",       label = "Apps",       icon = "\4" },
  { id = "about",      label = "About",      icon = "\4" },
}

local sidebar = W.ListBox({ rows = {}, background = theme.c.window })
sidebar.vexpand = true
do
  local rows = {}
  for _, section in ipairs(SECTIONS) do
    rows[#rows + 1] = { title = section.label,
                        icon = { char = section.icon, colour = theme.c.accent },
                        value = section.id }
  end
  sidebar:setRows(rows)
end
local sidebarScroller = base.Scrolled({ background = theme.c.window })
sidebarScroller.widthRequest = 11
sidebarScroller.vexpand = true
sidebarScroller:setChild(sidebar)

local pages = base.Stack()
pages.hexpand, pages.vexpand = true, true

local function applyAndRefresh()
  theme.save()
  wallpaper.invalidate()
  compositor.resetAll()
  sched.damageAll()
  app:queueDraw()
end

------------------------------------------------------------- appearance ----

local appearancePage
do
  local page = App.page({ padding = 1, spacing = 1 })

  local schemeTabs = W.Tabs({ tabs = {
    { label = "Dark", id = "dark" },
    { label = "Light", id = "light" },
    { label = "Contrast", id = "contrast" },
  } })
  for i, tab in ipairs(schemeTabs.tabs) do
    if tab.id == theme.current.id then schemeTabs.active = i end
  end
  schemeTabs:connect("changed", function(_, index, tab)
    theme.set(tab.id, nil)
    applyAndRefresh()
  end)

  local AccentStrip = util.class(base.Widget)
  function AccentStrip:init()
    base.Widget.init(self, {})
    self.hexpand = true
    self.heightRequest = 1
    self.focusable = true
  end
  function AccentStrip:measure() return 20, 1 end
  function AccentStrip:draw(s)
    local bg = theme.c.window
    s:fill(self.x, self.y, self.w, 1, " ", theme.c.text, bg)
    local x = self.x
    for _, accent in ipairs(theme.accents) do
      local colour = theme.current.dark and accent.dark or accent.light
      -- the palette only has one accent slot, so show swatches using the
      -- nearest named colours instead
      local swatch = ({ blue = colours.blue, teal = colours.cyan, green = colours.green,
                        yellow = colours.yellow, orange = colours.orange, red = colours.red,
                        pink = colours.pink, purple = colours.purple,
                        slate = colours.lightGrey })[accent.id]
      local selected = theme.accent == accent.id
      s:write(x, self.y, selected and "\254" or "\7", swatch, bg)
      x = x + 2
    end
  end
  function AccentStrip:onMouse(kind, button, px)
    if kind ~= "mouse_click" then return kind == "mouse_up" end
    local index = math.floor((px - self.x) / 2) + 1
    local accent = theme.accents[index]
    if accent then
      theme.set(nil, accent.id)
      applyAndRefresh()
    end
    return true
  end

  local accentStrip = AccentStrip()

  local wallpaperTabs = W.Tabs({ tabs = {} })
  for _, style in ipairs(wallpaper.styles) do
    wallpaperTabs.tabs[#wallpaperTabs.tabs + 1] = { label = style.name, id = style.id }
  end
  for i, tab in ipairs(wallpaperTabs.tabs) do
    if tab.id == theme.wallpaperStyle then wallpaperTabs.active = i end
  end
  wallpaperTabs:connect("changed", function(_, index, tab)
    theme.wallpaperStyle = tab.id
    applyAndRefresh()
  end)

  local Preview = util.class(base.Widget)
  function Preview:init()
    base.Widget.init(self, {})
    self.hexpand = true
    self.heightRequest = 5
  end
  function Preview:measure() return 20, 5 end
  function Preview:draw(s)
    local wp = wallpaper.get(self.w, self.h, theme.wallpaperStyle)
    s:draw(wp, self.x, self.y)
    -- a miniature window so the accent and chrome are visible
    local wx, wy = self.x + 3, self.y + 1
    local ww, wh = math.min(self.w - 6, 18), math.min(self.h - 2, 3)
    s:fill(wx, wy, ww, 1, " ", theme.c.text, theme.c.header)
    s:write(wx + 1, wy, "Preview", theme.c.text, theme.c.header)
    s:fill(wx, wy + 1, ww, wh - 1, " ", theme.c.text, theme.c.window)
    s:pill(wx + 2, wy + 2, 9, theme.c.accent)
    s:write(wx + 4, wy + 2, "Button", theme.c.onAccent, theme.c.accent)
    s:roundRect(wx, wy, ww, wh, theme.c.header, theme.c.desktop)
  end

  page:add(W.Label({ text = "Style", dim = true }))
  page:add(schemeTabs)
  page:add(W.Label({ text = "Accent colour", dim = true }))
  page:add(accentStrip)
  page:add(W.Label({ text = "Background", dim = true }))
  page:add(wallpaperTabs)
  page:add(Preview())

  local scroller = base.Scrolled({ background = theme.c.window })
  scroller.hexpand, scroller.vexpand = true, true
  scroller:setChild(page)
  appearancePage = scroller
end

--------------------------------------------------------------- displays ----

local displaysList = W.ListBox({ rows = {}, showSubtitles = true, background = theme.c.window })
displaysList.vexpand = true

local function refreshDisplays()
  local rows = {}
  for _, entry in ipairs(displaySvc.list()) do
    local role = entry.kind == "screen" and "Built-in screen"
                 or (displaySvc.roleLabels[entry.role] or entry.role)
    rows[#rows + 1] = {
      title = entry.id,
      subtitle = ("%dx%d  \183  %s"):format(entry.w, entry.h, role),
      icon = { char = "\254", colour = entry.kind == "screen" and theme.c.accent
                                       or theme.c.accentSoft },
      value = entry,
    }
  end
  if #rows == 0 then
    rows[1] = { title = "No displays", subtitle = "That should not happen" }
  end
  displaysList:setRows(rows, true)
  app:queueLayout()
end

displaysList:connect("activate", function(_, index, row)
  local entry = row and row.value
  if not entry or entry.kind ~= "monitor" then
    app:notify("The built-in screen is always the primary display")
    return
  end
  local items = {}
  for _, role in ipairs({ "mirror", "extend", "dedicated", "off" }) do
    items[#items + 1] = {
      label = displaySvc.roleLabels[role],
      icon = entry.role == role and "\7" or " ",
      action = function()
        displaySvc.setRole(entry.id, role)
        refreshDisplays()
        sched.damageAll()
      end,
    }
  end
  items[#items + 1] = { separator = true }
  for _, scale in ipairs({ 0.5, 1, 1.5, 2 }) do
    items[#items + 1] = {
      label = "Text scale " .. scale,
      icon = entry.scale == scale and "\7" or " ",
      action = function()
        displaySvc.setScale(entry.id, scale)
        refreshDisplays()
        sched.damageAll()
      end,
    }
  end
  app:menu(app.surface.w - 26, 3, items, 24)
end)

local displaysPage = base.Box({ orientation = "vertical", spacing = 0 })
displaysPage.hexpand, displaysPage.vexpand = true, true
do
  local hint = W.Label({ text = " Select a monitor to change what it shows", dim = true })
  hint.hexpand = true
  displaysPage:add(hint)
  local scroller = base.Scrolled({ background = theme.c.window })
  scroller.hexpand, scroller.vexpand = true, true
  scroller:setChild(displaysList)
  displaysPage:add(scroller)
end

--------------------------------------------------------------- printers ----

local printersList = W.ListBox({ rows = {}, showSubtitles = true, background = theme.c.window })
printersList.vexpand = true

local function refreshPrinters()
  local rows = {}
  for _, record in ipairs(printer.available()) do
    local status = printer.status(record)
    local ink, paper = 0, 0
    if record.handle then
      local ok, value = pcall(record.handle.getInkLevel)
      if ok then ink = value or 0 end
      local okPaper, valuePaper = pcall(record.handle.getPaperLevel)
      if okPaper then paper = valuePaper or 0 end
    end
    rows[#rows + 1] = {
      title = record.name,
      subtitle = ("%s  \183  ink %d  \183  paper %d"):format(status, ink, paper),
      icon = { char = "\22", colour = status == "ready" and theme.c.success or theme.c.warning },
      value = record,
    }
  end
  if #printer.queue > 0 then
    rows[#rows + 1] = { header = true, title = "Queue" }
    for _, job in ipairs(printer.queue) do
      rows[#rows + 1] = { title = job.title, subtitle = job.state,
                          icon = { char = "\4", colour = theme.c.dim } }
    end
  end
  if #printer.history > 0 then
    rows[#rows + 1] = { header = true, title = "Recent" }
    for _, job in ipairs(printer.history) do
      rows[#rows + 1] = {
        title = job.title,
        subtitle = job.state == "done" and (job.printed .. " pages") or (job.error or job.state),
        icon = { char = "\4", colour = job.state == "done" and theme.c.success
                                       or theme.c.destructive },
      }
    end
  end
  if #rows == 0 then
    rows[1] = { title = "No printers attached",
                subtitle = "Place one beside the computer or wire it up" }
  end
  printersList:setRows(rows, true)
  app:queueLayout()
end

local printersPage = base.Box({ orientation = "vertical", spacing = 0 })
printersPage.hexpand, printersPage.vexpand = true, true
do
  local testButton = W.Button({ label = "Print a test page", style = "suggested" })
  testButton.hexpand = true
  testButton.marginStart, testButton.marginEnd = 1, 1
  testButton:connect("clicked", function()
    local target = printer.default()
    if not target then
      app:notify("No printer attached", "error")
      return
    end
    printer.submit({
      title = "Aurora test page",
      content = {
        "Aurora " .. kernel.VERSION,
        "",
        "If you are reading this, printing works.",
        "Computer " .. os.getComputerID(),
        util.dateLine() .. "  " .. util.clock(),
      },
      target = target.name,
    })
    app:notify("Test page queued", "success")
  end)
  local scroller = base.Scrolled({ background = theme.c.window })
  scroller.hexpand, scroller.vexpand = true, true
  scroller:setChild(printersList)
  printersPage:add(scroller)
  printersPage:add(testButton)
end

---------------------------------------------------------------- network ----

local networkList = W.ListBox({ rows = {}, showSubtitles = true, background = theme.c.window })
networkList.vexpand = true

local function refreshNetwork()
  local rows = {}
  for _, record in ipairs(devices.byClass("network")) do
    rows[#rows + 1] = {
      title = record.name,
      subtitle = (record.wireless and "Wireless modem" or "Wired modem")
                 .. (rednet.isOpen(record.name) and "  \183  open" or "  \183  closed"),
      icon = { char = "\15", colour = rednet.isOpen(record.name) and theme.c.success
                                      or theme.c.dim },
      value = record,
    }
  end
  rows[#rows + 1] = { header = true, title = "This computer" }
  rows[#rows + 1] = { title = "Computer ID", trailing = tostring(os.getComputerID()) }
  rows[#rows + 1] = { title = "Label", trailing = os.getComputerLabel() or "not set" }
  rows[#rows + 1] = { title = "HTTP", trailing = http and "enabled" or "disabled" }
  networkList:setRows(rows, true)
  app:queueLayout()
end

networkList:connect("activate", function(_, index, row)
  local record = row and row.value
  if not record then
    if row and row.title == "Label" then
      app:prompt({
        title = "Computer label",
        text = os.getComputerLabel() or "",
        onAccept = function(text)
          if util.trim(text) == "" then os.setComputerLabel(nil)
          else os.setComputerLabel(util.trim(text)) end
          refreshNetwork()
        end,
      })
    end
    return
  end
  if rednet.isOpen(record.name) then
    rednet.close(record.name)
    app:notify("Closed " .. record.name)
  else
    local ok = pcall(rednet.open, record.name)
    app:notify(ok and ("Opened " .. record.name) or "Could not open the modem",
               ok and "success" or "error")
  end
  refreshNetwork()
end)

local networkPage = base.Scrolled({ background = theme.c.window })
networkPage.hexpand, networkPage.vexpand = true, true
networkPage:setChild(networkList)

------------------------------------------------------------------- apps ----

local appsList = W.ListBox({ rows = {}, showSubtitles = true, background = theme.c.window })
appsList.vexpand = true

local function refreshApps()
  local favourites = {}
  for _, manifest in ipairs(appsSvc.favourites()) do favourites[manifest.id] = true end
  local rows = {}
  local groups, order = appsSvc.byCategory()
  for _, category in ipairs(order) do
    rows[#rows + 1] = { header = true, title = category }
    for _, manifest in ipairs(groups[category]) do
      rows[#rows + 1] = {
        title = manifest.name,
        subtitle = manifest.summary,
        trailing = favourites[manifest.id] and "\7" or nil,
        icon = { char = manifest.char, colour = manifest.icon and manifest.icon.colour },
        value = manifest,
      }
    end
  end
  appsList:setRows(rows, true)
  app:queueLayout()
end

appsList:connect("activate", function(_, index, row)
  local manifest = row and row.value
  if not manifest then return end
  app:menu(app.surface.w - 26, 3, {
    { label = "Launch", icon = "\16", action = function() appsSvc.launch(manifest.id) end },
    { label = "Toggle in dash", icon = "\7", action = function()
        appsSvc.toggleFavourite(manifest.id)
        refreshApps()
        sched.damageAll()
      end },
    { separator = true },
    { label = "Uninstall", icon = "\215", destructive = true,
      disabled = manifest.source ~= "user",
      action = function()
        app:confirm({
          title = "Uninstall " .. manifest.name .. "?",
          message = "The app folder will be deleted.",
          acceptLabel = "Uninstall",
          destructive = true,
          onAccept = function()
            appsSvc.deleteUserApp(manifest.id)
            refreshApps()
            sched.damageAll()
          end,
        })
      end },
  }, 22)
end)

local appsPage = base.Scrolled({ background = theme.c.window })
appsPage.hexpand, appsPage.vexpand = true, true
appsPage:setChild(appsList)

------------------------------------------------------------------ about ----

local aboutPage
do
  local AboutHeader = util.class(base.Widget)
  function AboutHeader:init()
    base.Widget.init(self, {})
    self.hexpand = true
    self.heightRequest = 5
  end
  function AboutHeader:measure() return 20, 5 end
  function AboutHeader:draw(s)
    local bg = theme.c.window
    s:fill(self.x, self.y, self.w, self.h, " ", theme.c.text, bg)
    local logoW = math.min(self.w - 2, 22)
    local canvas = pixel.Canvas(logoW, 3, bg)
    local tw = pixel.textWidth("AURORA")
    canvas:text(math.floor((canvas.w - tw) / 2) + 1, 2, "AURORA", theme.c.accent)
    canvas:render(s, self.x + math.floor((self.w - logoW) / 2), self.y)
    s:writeCentered(self.y + 4, kernel.VERSION .. "  \"" .. kernel.CODENAME .. "\"",
                    theme.c.dim, bg, self.x, self.w)
  end

  local infoList = W.ListBox({ rows = {}, background = theme.c.window })
  infoList.vexpand = true

  local function refreshAbout()
    local info = kernel.info()
    local usage = vfs.usage()
    local rows = {
      { header = true, title = "System" },
      { title = "Version", trailing = info.version },
      { title = "Kernel uptime", trailing = ("%d min"):format(math.floor(info.uptime / 60)) },
      { title = "Processes", trailing = tostring(info.processes) },
      { title = "Computer", trailing = (info.label or ("#" .. info.computerId)) },
      { title = "Terminal", trailing = info.advanced and "advanced" or "basic" },
      { header = true, title = "Storage" },
      { title = "Free space", trailing = util.formatSize(usage.free) },
      { title = "Used", trailing = util.formatSize(usage.used) },
      { header = true, title = "Devices" },
    }
    local counts = info.devices
    local any = false
    for class, n in pairs(counts) do
      rows[#rows + 1] = { title = class, trailing = tostring(n) }
      any = true
    end
    if not any then rows[#rows + 1] = { title = "Nothing attached", trailing = "" } end
    infoList:setRows(rows, true)
  end

  local page = base.Box({ orientation = "vertical", spacing = 0 })
  page.hexpand, page.vexpand = true, true
  page:add(AboutHeader())
  local scroller = base.Scrolled({ background = theme.c.window })
  scroller.hexpand, scroller.vexpand = true, true
  scroller:setChild(infoList)
  page:add(scroller)
  aboutPage = page
  aboutPage.refresh = refreshAbout
  refreshAbout()
end

------------------------------------------------------------------ layout ---

pages:addPage("appearance", appearancePage)
pages:addPage("displays", displaysPage)
pages:addPage("printers", printersPage)
pages:addPage("network", networkPage)
pages:addPage("apps", appsPage)
pages:addPage("about", aboutPage)

local body = base.Box({ orientation = "horizontal", spacing = 0 })
body.hexpand, body.vexpand = true, true
body:add(sidebarScroller)
body:add(W.Separator({ orientation = "vertical" }))
body:add(pages)

app:setRoot(body)

local function showSection(id)
  pages:setPage(id)
  if id == "displays" then refreshDisplays() end
  if id == "printers" then refreshPrinters() end
  if id == "network" then refreshNetwork() end
  if id == "apps" then refreshApps() end
  if id == "about" and aboutPage.refresh then aboutPage.refresh() end
  app:queueLayout()
end

sidebar:connect("select", function(_, index, row)
  if row and row.value then showSection(row.value) end
end)
sidebar:connect("activate", function(_, index, row)
  if row and row.value then showSection(row.value) end
end)

app.onEvent = function(name)
  if name == "peripheral" or name == "peripheral_detach" or name == "monitor_resize" then
    if pages.currentName == "displays" then refreshDisplays() end
    if pages.currentName == "printers" then refreshPrinters() end
    if pages.currentName == "network" then refreshNetwork() end
    app:queueDraw()
  end
end

if args[1] then
  for _, section in ipairs(SECTIONS) do
    if section.id == args[1] then showSection(args[1]) end
  end
end

app:setFocus(sidebar)
app:run()
