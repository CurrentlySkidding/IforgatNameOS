--[[ Sheets -- the Aurora spreadsheet ---------------------------------------
     Live formulas (=SUM(A1:A9)), column sizing, CSV import and export, a
     chart view over any range, and printing.
----------------------------------------------------------------------------]]

local args    = { ... }
local App     = arequire("ui.app")
local base    = arequire("ui.widget")
local W       = arequire("ui.widgets")
local theme   = arequire("gfx.theme")
local util    = arequire("lib.util")
local Surface = arequire("gfx.surface")
local formula = arequire("lib.formula")
local vfs     = arequire("kernel.vfs")
local printer = arequire("svc.printer")

local app = App({ title = "Sheets" })

local sheet = {
  name = "Sheet 1",
  cells = {},
  widths = {},
  rows = 60,
  cols = 26,
}
local state = { path = args[1], col = 1, row = 1, modified = false }

local DEFAULT_WIDTH = 7
local ROW_HEADER_W = 4

local function widthOf(col)
  return sheet.widths[col] or DEFAULT_WIDTH
end

local function cellText(col, row)
  local cell = sheet.cells[formula.makeRef(col, row)]
  return cell and cell.text or ""
end

local function setCellText(col, row, text)
  local ref = formula.makeRef(col, row)
  if text == nil or text == "" then
    sheet.cells[ref] = nil
  else
    sheet.cells[ref] = { text = text }
  end
  state.modified = true
end

local function displayValue(col, row)
  local ref = formula.makeRef(col, row)
  local ok, value = pcall(formula.evaluate, sheet, ref)
  if not ok then return "#ERROR" end
  return formula.format(value)
end

------------------------------------------------------------- grid widget ---

local GridWidget = util.class(base.Widget)

function GridWidget:init(props)
  base.Widget.init(self, props or {})
  self.focusable = true
  self.hexpand, self.vexpand = true, true
  self.scrollCol, self.scrollRow = 1, 1
end

function GridWidget:measure() return 20, 6 end

function GridWidget:visibleCols()
  local cols, x = {}, self.x + ROW_HEADER_W
  local col = self.scrollCol
  while col <= sheet.cols and x <= self.x + self.w - 1 do
    local w = math.min(widthOf(col), self.x + self.w - x)
    cols[#cols + 1] = { col = col, x = x, w = w }
    x = x + w
    col = col + 1
  end
  return cols
end

function GridWidget:visibleRows()
  local rows = {}
  for i = 0, self.h - 2 do
    local row = self.scrollRow + i
    if row > sheet.rows then break end
    rows[#rows + 1] = { row = row, y = self.y + 1 + i }
  end
  return rows
end

function GridWidget:ensureVisible()
  if state.row < self.scrollRow then self.scrollRow = state.row end
  local visible = self:visibleRows()
  if #visible > 0 and state.row > visible[#visible].row then
    self.scrollRow = self.scrollRow + (state.row - visible[#visible].row)
  end
  if state.col < self.scrollCol then self.scrollCol = state.col end
  local cols = self:visibleCols()
  local last = cols[#cols]
  while last and state.col > last.col do
    self.scrollCol = self.scrollCol + 1
    cols = self:visibleCols()
    last = cols[#cols]
  end
  self:invalidate()
end

function GridWidget:draw(s)
  local c = theme.c
  s:fill(self.x, self.y, self.w, self.h, " ", c.text, c.view)
  s:pushClip(self.x, self.y, self.w, self.h)

  local cols = self:visibleCols()
  local rows = self:visibleRows()

  -- corner + column headers
  s:fill(self.x, self.y, self.w, 1, " ", c.dim, c.card)
  for _, entry in ipairs(cols) do
    local name = formula.indexToColumn(entry.col)
    local selected = entry.col == state.col
    local bg = selected and c.accent or c.card
    s:fill(entry.x, self.y, entry.w, 1, " ", selected and c.onAccent or c.dim, bg)
    s:write(entry.x + math.floor((entry.w - #name) / 2), self.y, name,
            selected and c.onAccent or c.dim, bg)
  end

  for _, rowEntry in ipairs(rows) do
    local selected = rowEntry.row == state.row
    local headerBg = selected and c.accent or c.card
    s:fill(self.x, rowEntry.y, ROW_HEADER_W, 1, " ", selected and c.onAccent or c.dim, headerBg)
    s:write(self.x, rowEntry.y, util.padLeft(tostring(rowEntry.row), ROW_HEADER_W - 1),
            selected and c.onAccent or c.dim, headerBg)

    for _, colEntry in ipairs(cols) do
      local isCursor = (colEntry.col == state.col and rowEntry.row == state.row)
      local bg = isCursor and c.selection or c.view
      local fg = isCursor and c.onAccent or c.text
      local raw = cellText(colEntry.col, rowEntry.row)
      local value = raw == "" and "" or displayValue(colEntry.col, rowEntry.row)
      if type(value) == "string" and value:sub(1, 1) == "#" and not isCursor then
        fg = c.destructive
      end
      s:fill(colEntry.x, rowEntry.y, colEntry.w, 1, " ", fg, bg)
      local text = util.ellipsis(tostring(value), colEntry.w - 1)
      -- numbers align right, text aligns left, just like every spreadsheet
      if tonumber(value) ~= nil then
        s:write(colEntry.x + colEntry.w - 1 - #text, rowEntry.y, text, fg, bg)
      else
        s:write(colEntry.x, rowEntry.y, text, fg, bg)
      end
    end
  end

  s:popClip()
end

function GridWidget:cellAt(px, py)
  if py <= self.y then return nil end
  local rows = self:visibleRows()
  local row
  for _, entry in ipairs(rows) do
    if entry.y == py then row = entry.row end
  end
  if not row then return nil end
  for _, entry in ipairs(self:visibleCols()) do
    if px >= entry.x and px < entry.x + entry.w then return entry.col, row end
  end
  return nil
end

function GridWidget:onMouse(kind, button, px, py)
  if kind == "mouse_scroll" then
    self.scrollRow = math.max(1, math.min(sheet.rows, self.scrollRow + button * 2))
    self:invalidate()
    return true
  end
  if kind == "mouse_click" then
    local col, row = self:cellAt(px, py)
    if col then
      state.col, state.row = col, row
      self:emit("moved")
      self:invalidate()
    end
    return true
  end
  return kind == "mouse_up"
end

function GridWidget:onKey(key)
  local moved = true
  if key == keys.up then state.row = math.max(1, state.row - 1)
  elseif key == keys.down then state.row = math.min(sheet.rows, state.row + 1)
  elseif key == keys.left then state.col = math.max(1, state.col - 1)
  elseif key == keys.right then state.col = math.min(sheet.cols, state.col + 1)
  elseif key == keys.pageUp then state.row = math.max(1, state.row - (self.h - 1))
  elseif key == keys.pageDown then state.row = math.min(sheet.rows, state.row + (self.h - 1))
  elseif key == keys.home then state.col = 1
  elseif key == keys["end"] then
    local last = 1
    for ref in pairs(sheet.cells) do
      local col = formula.parseRef(ref)
      if col and col > last then last = col end
    end
    state.col = last
  elseif key == keys.delete or key == keys.backspace then
    setCellText(state.col, state.row, "")
    self:emit("edited")
    moved = false
    self:invalidate()
  elseif key == keys.enter then
    self:emit("beginEdit")
    return true
  else
    return false
  end
  if moved then
    self:ensureVisible()
    self:emit("moved")
  end
  return true
end

function GridWidget:onChar(ch)
  self:emit("beginEdit", ch)
  return true
end

-------------------------------------------------------------------- chrome --

local grid = GridWidget()

local refLabel = W.Label({ text = "A1", dim = true })
refLabel.widthRequest = 6

local formulaEntry = W.Entry({ placeholder = "Value or =FORMULA", flat = true })
formulaEntry.hexpand = true

local formulaBar = base.Box({ orientation = "horizontal", spacing = 1 })
formulaBar.hexpand = true
formulaBar.background = theme.c.card
formulaBar:add(refLabel)
formulaBar:add(formulaEntry)

local nameLabel = W.Label({ text = "Untitled" })
nameLabel.hexpand = true
local saveButton = W.IconButton({ icon = "\4", width = 3 })
local chartButton = W.IconButton({ icon = "\254", width = 3 })
local menuButton = W.IconButton({ icon = "\7", width = 3 })

local toolbar = W.Toolbar({ spacing = 0 })
toolbar:add(nameLabel)
toolbar:add(saveButton)
toolbar:add(chartButton)
toolbar:add(menuButton)

local statusLabel = W.Label({ text = "", dim = true })
statusLabel.hexpand = true
local status = base.Box({ orientation = "horizontal" })
status.hexpand = true
status.background = theme.c.window
status:add(statusLabel)

local chart = W.Chart({ series = {}, kind = "bar", height = 6 })
chart.hexpand = true
chart.visible = false

local root = base.Box({ orientation = "vertical", spacing = 0 })
root.hexpand, root.vexpand = true, true
root:add(toolbar)
root:add(formulaBar)
root:add(grid)
root:add(chart)
root:add(status)
app:setRoot(root)

------------------------------------------------------------------ helpers --

local function currentRef()
  return formula.makeRef(state.col, state.row)
end

local function refreshBar()
  refLabel:setText(currentRef())
  formulaEntry:setText(cellText(state.col, state.row), true)
  local value = displayValue(state.col, state.row)
  local used = 0
  for _ in pairs(sheet.cells) do used = used + 1 end
  statusLabel:setText((" %s = %s  \183  %d cells used")
    :format(currentRef(), tostring(value == "" and "(empty)" or value), used))
  nameLabel:setText(" " .. util.ellipsis(
    state.path and fs.getName(state.path) or sheet.name, 20) .. (state.modified and " \7" or ""))
  aurora.setTitle((state.path and util.stripExtension(fs.getName(state.path)) or sheet.name)
    .. (state.modified and " *" or ""))
  app:queueDraw()
end

local function commitEdit()
  setCellText(state.col, state.row, formulaEntry.text)
  refreshBar()
  app:setFocus(grid)
end

--------------------------------------------------------------- load / save --

local function loadSheet(path)
  local ext = util.extension(path)
  if ext == "csv" then
    local data = util.readFile(path)
    if not data then app:notify("Could not read the file", "error") return end
    sheet.cells = {}
    local row = 1
    for _, line in ipairs(util.splitAll(data:gsub("\r", ""), "\n")) do
      if line ~= "" or row == 1 then
        local col = 1
        for _, field in ipairs(util.splitAll(line, ",")) do
          if field ~= "" then setCellText(col, row, field) end
          col = col + 1
        end
      end
      row = row + 1
    end
  else
    local saved = util.readTable(path, nil)
    if not saved then app:notify("Could not read the sheet", "error") return end
    sheet.cells = saved.cells or {}
    sheet.widths = saved.widths or {}
    sheet.name = saved.name or fs.getName(path)
    sheet.rows = saved.rows or 60
    sheet.cols = saved.cols or 26
  end
  state.path = path
  state.modified = false
  vfs.touchRecent(path)
  refreshBar()
end

local function toCSV()
  local maxCol, maxRow = 1, 1
  for ref in pairs(sheet.cells) do
    local col, row = formula.parseRef(ref)
    if col then
      maxCol = math.max(maxCol, col)
      maxRow = math.max(maxRow, row)
    end
  end
  local lines = {}
  for row = 1, maxRow do
    local fields = {}
    for col = 1, maxCol do
      local value = cellText(col, row)
      if value:sub(1, 1) == "=" then value = tostring(displayValue(col, row)) end
      if value:find(",") then value = '"' .. value .. '"' end
      fields[#fields + 1] = value
    end
    lines[#lines + 1] = table.concat(fields, ",")
  end
  return table.concat(lines, "\n")
end

local function saveAs(path)
  local ok
  if util.extension(path) == "csv" then
    ok = util.writeFile(path, toCSV())
  else
    ok = util.writeTable(path, {
      name = sheet.name, cells = sheet.cells, widths = sheet.widths,
      rows = sheet.rows, cols = sheet.cols,
    })
  end
  if not ok then
    app:notify("Could not save", "error")
    return false
  end
  state.path = path
  state.modified = false
  vfs.touchRecent(path)
  refreshBar()
  app:notify("Saved " .. fs.getName(path), "success")
  return true
end

local function save()
  if state.path then return saveAs(state.path) end
  app:prompt({
    title = "Save spreadsheet",
    text = vfs.HOME .. "/Sheets/Untitled.asheet",
    acceptLabel = "Save",
    onAccept = function(path) if util.trim(path) ~= "" then saveAs(util.trim(path)) end end,
  })
end

------------------------------------------------------------------- chart ----

local function buildChart(rangeText)
  local from, to = rangeText:upper():match("^%s*(%a+%d+)%s*:%s*(%a+%d+)%s*$")
  if not from then
    app:notify("Use a range like A1:A10", "error")
    return
  end
  local c1, r1 = formula.parseRef(from)
  local c2, r2 = formula.parseRef(to)
  if not c1 or not c2 then app:notify("Bad range", "error") return end
  if c1 > c2 then c1, c2 = c2, c1 end
  if r1 > r2 then r1, r2 = r2, r1 end
  local series = {}
  for row = r1, r2 do
    for col = c1, c2 do
      local value = tonumber(displayValue(col, row))
      if value then series[#series + 1] = value end
    end
  end
  if #series == 0 then
    app:notify("That range has no numbers", "error")
    return
  end
  chart:setSeries(series)
  chart.visible = true
  state.chartRange = rangeText
  app:queueLayout()
end

-------------------------------------------------------------------- menu ---

local function openMenu()
  app:menu(app.surface.w - 22, 2, {
    { label = "Open", icon = "\4", accel = "^O", action = function()
        app:prompt({
          title = "Open spreadsheet",
          text = state.path or (vfs.HOME .. "/Sheets/"),
          acceptLabel = "Open",
          onAccept = function(path) if fs.exists(path) then loadSheet(path) end end,
        })
      end },
    { label = "Save as", icon = "\4", action = function()
        app:prompt({
          title = "Save as",
          text = state.path or (vfs.HOME .. "/Sheets/Untitled.asheet"),
          acceptLabel = "Save",
          onAccept = function(path) saveAs(path) end,
        })
      end },
    { separator = true },
    { label = "Sum this column", icon = "\4", action = function()
        local column = formula.indexToColumn(state.col)
        setCellText(state.col, state.row,
                    ("=SUM(%s1:%s%d)"):format(column, column, math.max(1, state.row - 1)))
        refreshBar()
      end },
    { label = "Chart a range", icon = "\254", action = function()
        app:prompt({
          title = "Chart a range",
          message = "Which cells should the chart show?",
          text = state.chartRange or "A1:A10",
          acceptLabel = "Chart",
          onAccept = buildChart,
        })
      end },
    { label = "Column width", icon = "\4", action = function()
        app:prompt({
          title = "Width of column " .. formula.indexToColumn(state.col),
          text = tostring(widthOf(state.col)),
          onAccept = function(text)
            local n = tonumber(text)
            if n then
              sheet.widths[state.col] = util.clamp(math.floor(n), 3, 20)
              state.modified = true
              refreshBar()
            end
          end,
        })
      end },
    { separator = true },
    { label = "Export CSV", icon = "y", action = function()
        local target = (state.path and util.stripExtension(state.path)
                        or (vfs.HOME .. "/Sheets/Untitled")) .. ".csv"
        util.writeFile(target, toCSV())
        app:notify("Exported " .. fs.getName(target), "success")
      end },
    { label = "Print", icon = "\22", accel = "^P", action = function()
        local job = printer.submit({
          title = state.path and fs.getName(state.path) or sheet.name,
          content = toCSV():gsub(",", "  "),
          source = state.path,
        })
        app:notify("Queued \"" .. job.title .. "\"", "success")
      end },
    { label = "Functions", icon = "\4", action = function()
        local names = {}
        for name in pairs(formula.functions) do
          if not name:match("^__") then names[#names + 1] = name end
        end
        table.sort(names)
        app:dialog({
          title = "Functions",
          body = table.concat(names, ", "),
          actions = { { label = "Close", style = "suggested" } },
        })
      end },
  }, 22)
end

------------------------------------------------------------------ wiring ---

grid:connect("moved", refreshBar)
grid:connect("edited", refreshBar)
grid:connect("beginEdit", function(_, ch)
  app:setFocus(formulaEntry)
  if ch then
    formulaEntry:setText(ch, true)
    formulaEntry.cursor = 2
  end
  app:queueDraw()
end)

formulaEntry:connect("activate", function()
  commitEdit()
  state.row = math.min(sheet.rows, state.row + 1)
  grid:ensureVisible()
  refreshBar()
end)

saveButton:connect("clicked", save)
chartButton:connect("clicked", function()
  if chart.visible then
    chart.visible = false
  else
    buildChart(state.chartRange or "A1:A10")
  end
  app:queueLayout()
end)
menuButton:connect("clicked", openMenu)

app:accel("ctrl+s", save)
app:accel("ctrl+p", function()
  local job = printer.submit({
    title = state.path and fs.getName(state.path) or sheet.name,
    content = toCSV():gsub(",", "  "),
  })
  app:notify("Queued \"" .. job.title .. "\"", "success")
end)

app.onClose = function()
  if not state.modified then return true end
  app:confirm({
    title = "Save before closing?",
    message = "This spreadsheet has unsaved changes.",
    acceptLabel = "Save",
    cancelLabel = "Discard",
    onAccept = function() save() app:quit() end,
    onCancel = function() app:quit() end,
  })
  return false
end

app.onEvent = function(name, ...)
  if name == "aurora_open" then
    local path = select(1, ...)
    if path and fs.exists(path) then loadSheet(path) end
  end
end

if state.path and fs.exists(state.path) and not fs.isDir(state.path) then
  loadSheet(state.path)
else
  state.path = nil
  setCellText(1, 1, "Item")
  setCellText(2, 1, "Amount")
  state.modified = false
end

refreshBar()
app:setFocus(grid)
app:run()
