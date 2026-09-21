--[[ Files -- the Aurora file manager ---------------------------------------
     Sidebar of places, list or grid view, full clipboard and trash support,
     and it hands files off to whichever app claims their type.
----------------------------------------------------------------------------]]

local args    = { ... }
local App     = arequire("ui.app")
local base    = arequire("ui.widget")
local W       = arequire("ui.widgets")
local theme   = arequire("gfx.theme")
local util    = arequire("lib.util")
local vfs     = arequire("kernel.vfs")
local appsSvc = arequire("svc.apps")
local printer = arequire("svc.printer")

local app = App({ title = "Files" })

local state = {
  path = args[1] and fs.exists(args[1]) and (fs.isDir(args[1]) and args[1] or fs.getDir(args[1]))
         or vfs.HOME,
  view = "list",            -- list | grid
  showHidden = false,
  history = {},
  future = {},
  entries = {},
}

-------------------------------------------------------------------- chrome --

local pathLabel = W.Label({ text = "", dim = false })
pathLabel.hexpand = true

local placesButton = W.IconButton({ icon = "\127", width = 3 })
local backButton = W.IconButton({ icon = "\17", width = 3 })
local upButton = W.IconButton({ icon = "\30", width = 3 })
local menuButton = W.IconButton({ icon = "\7", width = 3 })

local toolbar = W.Toolbar({ spacing = 0 })
toolbar:add(placesButton)
toolbar:add(backButton)
toolbar:add(upButton)
toolbar:add(pathLabel)
toolbar:add(menuButton)

--------------------------------------------------------------- side panel --

-- The places list used to sit open permanently, costing a quarter of the
-- window's width.  It is a toggle now (the house button, or Ctrl+B) so the
-- file list gets the whole window by default.
local placesList = W.ListBox({ rows = {}, background = theme.c.window })
placesList.vexpand = true

local sidebar = base.Scrolled({ background = theme.c.window })
sidebar.widthRequest = 13
sidebar.vexpand = true
sidebar:setChild(placesList)
sidebar.visible = false

local sidebarSeparator = W.Separator({ orientation = "vertical" })
sidebarSeparator.visible = false

----------------------------------------------------------------- content ---

local fileList = W.ListBox({ rows = {}, showSubtitles = false })
fileList.vexpand = true
fileList.hexpand = true

local fileGrid = W.IconGrid({ items = {}, cellW = 9, cellH = 5, iconW = 6, iconH = 3 })
fileGrid.hexpand = true

local emptyState = W.StatusPage({
  title = "This folder is empty",
  description = "Drop something in it, or create a new file from the menu.",
  icon = { colour = theme.c.active, glyph = "?" },
})

local contentStack = base.Stack()
contentStack.hexpand, contentStack.vexpand = true, true

local listScroller = base.Scrolled({})
listScroller.hexpand, listScroller.vexpand = true, true
listScroller:setChild(fileList)

local gridScroller = base.Scrolled({})
gridScroller.hexpand, gridScroller.vexpand = true, true
gridScroller:setChild(fileGrid)

contentStack:addPage("list", listScroller)
contentStack:addPage("grid", gridScroller)
contentStack:addPage("empty", emptyState)

local body = base.Box({ orientation = "horizontal", spacing = 0 })
body.hexpand, body.vexpand = true, true
body:add(sidebar)
body:add(sidebarSeparator)
body:add(contentStack)

local root = base.Box({ orientation = "vertical", spacing = 0 })
root.hexpand, root.vexpand = true, true
root:add(toolbar)
root:add(body)
app:setRoot(root)

------------------------------------------------------------------ helpers --

local function selectedEntry()
  if state.view == "grid" then
    local item = fileGrid.items[fileGrid.selected]
    return item and item.entry
  end
  local row = fileList:current()
  return row and row.entry
end

local function refreshPlaces()
  local rows = {}
  for _, place in ipairs(vfs.places()) do
    rows[#rows + 1] = {
      title = place.name,
      icon = { char = place.char, colour = place.colour },
      value = place.path,
    }
  end
  placesList:setRows(rows, true)
end

local function refresh()
  state.entries = vfs.list(state.path, state.showHidden)

  local rows, items = {}, {}
  for _, entry in ipairs(state.entries) do
    rows[#rows + 1] = {
      title = entry.name,
      icon = { char = entry.type.char, colour = entry.type.colour },
      trailing = entry.isDir and "" or util.formatSize(entry.size),
      entry = entry,
    }
    items[#items + 1] = {
      label = entry.name,
      icon = { colour = entry.type.colour,
               art = entry.isDir and { "###.....", "########", "#......#", "########" } or nil,
               glyph = entry.isDir and nil or (util.extension(entry.name):upper():sub(1, 2)) },
      entry = entry,
    }
  end

  fileList:setRows(rows)
  fileGrid:setItems(items)

  if #state.entries == 0 then
    contentStack:setPage("empty")
  else
    contentStack:setPage(state.view)
  end

  local shown = state.path == "" and "/" or state.path
  if util.startsWith(shown, vfs.HOME) then
    shown = "~" .. shown:sub(#vfs.HOME + 1)
  end
  pathLabel:setText(" " .. util.ellipsis(shown, 28))
  aurora.setTitle(state.path == vfs.HOME and "Home" or fs.getName(state.path))


  backButton.sensitive = #state.history > 0
  upButton.sensitive = state.path ~= "/"
  app:queueLayout()
end

local function navigate(path, remember)
  if not fs.exists(path) or not fs.isDir(path) then
    app:notify("Cannot open " .. fs.getName(path), "error")
    return
  end
  if remember ~= false and state.path ~= path then
    table.insert(state.history, state.path)
    state.future = {}
  end
  state.path = path
  fileList.selected = 1
  fileGrid.selected = 1
  listScroller.offset = 0
  gridScroller.offset = 0
  refresh()
end

local function goBack()
  local previous = table.remove(state.history)
  if previous then
    table.insert(state.future, state.path)
    state.path = previous
    refresh()
  end
end

local function openEntry(entry)
  if not entry then return end
  if entry.isDir then
    navigate(entry.path)
  else
    appsSvc.openFile(entry.path)
  end
end

------------------------------------------------------------------ actions --

local function newFolder()
  app:prompt({
    title = "New folder",
    text = "New Folder",
    onAccept = function(name)
      if util.trim(name) == "" then return end
      local target, err = vfs.newFolder(state.path, util.trim(name))
      if not target then app:notify(err or "Could not create the folder", "error")
      else refresh() end
    end,
  })
end

local function newFile()
  app:prompt({
    title = "New file",
    text = "Untitled.txt",
    onAccept = function(name)
      if util.trim(name) == "" then return end
      local target, err = vfs.newFile(state.path, util.trim(name), "")
      if not target then app:notify(err or "Could not create the file", "error")
      else refresh() end
    end,
  })
end

local function renameSelected()
  local entry = selectedEntry()
  if not entry then return end
  app:prompt({
    title = "Rename",
    text = entry.name,
    onAccept = function(name)
      name = util.trim(name)
      if name == "" or name == entry.name then return end
      local target, err = vfs.rename(entry.path, name)
      if not target then app:notify(err or "Could not rename", "error")
      else refresh() end
    end,
  })
end

local function deleteSelected()
  local entry = selectedEntry()
  if not entry then return end
  local inTrash = util.startsWith(entry.path, vfs.TRASH)
  app:confirm({
    title = inTrash and "Delete permanently?" or "Move to trash?",
    message = entry.name .. (inTrash and " will be gone for good." or " can be restored later."),
    acceptLabel = inTrash and "Delete" or "Move to Trash",
    destructive = true,
    onAccept = function()
      local ok, err
      if inTrash then ok, err = vfs.delete(entry.path)
      else ok, err = vfs.trash(entry.path) end
      if not ok then app:notify(err or "Could not delete", "error") end
      refresh()
    end,
  })
end

local function copySelected(mode)
  local entry = selectedEntry()
  if not entry then return end
  vfs.copyToClipboard({ entry.path }, mode)
  app:notify((mode == "cut" and "Cut " or "Copied ") .. entry.name)
end

local function pasteHere()
  if #(vfs.clipboard.paths or {}) == 0 then
    app:notify("Nothing to paste")
    return
  end
  local results, errors = vfs.pasteInto(state.path)
  refresh()
  if #errors > 0 then
    app:notify(errors[1], "error")
  else
    app:notify(#results .. " item(s) pasted", "success")
  end
end

local function showProperties()
  local entry = selectedEntry()
  if not entry then return end
  local lines = {
    "Name      " .. entry.name,
    "Where     " .. util.ellipsis(fs.getDir(entry.path), 28),
    "Type      " .. entry.type.label,
    "Size      " .. (entry.isDir and "--" or util.formatSize(entry.size)),
    "Access    " .. (entry.readOnly and "read only" or "read and write"),
  }
  local box = base.Box({ orientation = "vertical", spacing = 0 })
  box.hexpand = true
  for _, line in ipairs(lines) do
    local label = W.Label({ text = line, dim = true })
    label.hexpand = true
    box:add(label)
  end
  app:dialog({
    title = "Properties",
    body = box,
    actions = { { label = "Close", style = "suggested" } },
  })
end

local function openMenu()
  local entry = selectedEntry()
  local inTrash = util.startsWith(state.path, vfs.TRASH)
  local items = {
    { label = "New folder", icon = "\254", action = newFolder, accel = "^N" },
    { label = "New program", icon = "\187", action = function()
        app:prompt({
          title = "New SimpleLang program",
          text = "program.sl",
          onAccept = function(name)
            name = util.trim(name)
            if name == "" then return end
            if util.extension(name) == "" then name = name .. ".sl" end
            local target = vfs.newFile(state.path, name,
              "# " .. name .. "\n\nsay \"hello\"\n")
            if target then
              refresh()
              appsSvc.launch("studio", { target })
            end
          end,
        })
      end },
    { separator = true },
    { label = "Copy", icon = "\4", accel = "^C", disabled = entry == nil,
      action = function() copySelected("copy") end },
    { label = "Paste", icon = "\4", accel = "^V", action = pasteHere },
    { label = "Rename", icon = "\187", accel = "F2", disabled = entry == nil,
      action = renameSelected },
    { label = inTrash and "Delete" or "Move to Trash", icon = "\233",
      destructive = true, disabled = entry == nil, action = deleteSelected },
    { separator = true },
    { label = state.view == "list" and "View as grid" or "View as list",
      icon = "\254", action = function()
        state.view = state.view == "list" and "grid" or "list"
        refresh()
      end },
    { label = "Properties", icon = "\4", disabled = entry == nil,
      action = showProperties },
  }

  -- Anything runnable gets a Run entry at the top, where you expect it.
  if entry and not entry.isDir then
    if entry.type.kind == "program" then
      table.insert(items, 1, { label = "Run", icon = "\16", action = function()
        appsSvc.runProgram(entry.path)
      end })
    elseif util.extension(entry.name) == "sl" then
      table.insert(items, 1, { label = "Build and run", icon = "\16", action = function()
        local slang = arequire("lib.slang.init")
        local built, buildErr = slang.buildFile(entry.path)
        if not built then
          app:notify(slang.errorText(buildErr), "error")
        else
          refresh()
          appsSvc.runProgram(built.programPath)
        end
      end })
    end
  end

  -- Contextual extras, so they are only in the way when they are useful.
  if entry and not entry.isDir then
    table.insert(items, { label = "Print", icon = "\22", action = function()
      local job, err = printer.printFile(entry.path)
      if job then app:notify("Sent " .. entry.name .. " to the printer", "success")
      else app:notify(err or "Print failed", "error") end
    end })
  end
  if inTrash then
    table.insert(items, { label = "Empty trash", icon = "\233", destructive = true,
      action = function()
        app:confirm({
          title = "Empty the trash?",
          message = "Everything in the trash will be deleted permanently.",
          acceptLabel = "Empty Trash",
          destructive = true,
          onAccept = function()
            local n = vfs.emptyTrash()
            app:notify(n .. " item(s) deleted", "success")
            refresh()
          end,
        })
      end })
  end

  app:menu(app.surface.w - 22, 2, items, 22)
end

------------------------------------------------------------------- wiring --

backButton:connect("clicked", goBack)
upButton:connect("clicked", function() navigate(vfs.parent(state.path)) end)
menuButton:connect("clicked", openMenu)
local function toggleSidebar()
  sidebar.visible = not sidebar.visible
  sidebarSeparator.visible = sidebar.visible
  app:queueLayout()
end

placesButton:connect("clicked", toggleSidebar)

placesList:connect("select", function(_, index, row)
  if row and row.value then navigate(row.value) end
end)
placesList:connect("activate", function(_, index, row)
  if row and row.value then navigate(row.value) end
end)

fileList:connect("activate", function(_, index, row)
  openEntry(row and row.entry)
end)
fileGrid:connect("activate", function(_, index, item)
  openEntry(item and item.entry)
end)

app:accel("ctrl+n", newFolder)
app:accel("ctrl+c", function() copySelected("copy") end)
app:accel("ctrl+x", function() copySelected("cut") end)
app:accel("ctrl+v", pasteHere)
app:accel("ctrl+b", toggleSidebar)
app:accel("ctrl+h", function() state.showHidden = not state.showHidden refresh() end)
app:accel("ctrl+l", function()
  app:prompt({
    title = "Go to folder",
    text = state.path,
    onAccept = function(path) navigate(path) end,
  })
end)
app:accel("f2", renameSelected)
app:accel("f5", refresh)
app:accel("delete", deleteSelected)
app:accel("backspace", function() navigate(vfs.parent(state.path)) end)
app:accel("alt+left", goBack)

app.onEvent = function(name, ...)
  if name == "aurora_open" then
    local path = select(1, ...)
    if path and fs.exists(path) then
      navigate(fs.isDir(path) and path or fs.getDir(path))
    end
  elseif name == "disk" or name == "disk_eject" or name == "peripheral"
      or name == "peripheral_detach" then
    refreshPlaces()
    app:queueDraw()
  end
end

refreshPlaces()
refresh()
app:setFocus(fileList)
app:run()
