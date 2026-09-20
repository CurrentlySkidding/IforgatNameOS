--[[ aurora.ui.widgets -------------------------------------------------------
     The control set.  Everything here draws itself in the Adwaita idiom:
     pill buttons, filled entries, flat list rows with a coloured selection,
     and generous use of the dim/accent tokens.
----------------------------------------------------------------------------]]

local util   = arequire("lib.util")
local theme  = arequire("gfx.theme")
local base   = arequire("ui.widget")
local pixel  = arequire("gfx.pixel")

local Widget = base.Widget

local W = {}
for k, v in pairs(base) do W[k] = v end

------------------------------------------------------------------ Label -----

local Label = util.class(Widget)
W.Label = Label

function Label:init(props)
  props = props or {}
  if type(props) == "string" then props = { text = props } end
  Widget.init(self, props)
  self.text = props.text or ""
  self.fg = props.fg
  self.bg = props.bg
  self.align = props.align or "start"
  self.wrap = props.wrap or false
  self.dim = props.dim or false
  self.selectable = false
end

function Label:setText(text)
  text = tostring(text)
  if self.text ~= text then
    self.text = text
    if self.wrap then self:relayout() else self:invalidate() end
  end
end

function Label:measure()
  if self.wrap then
    local width = self.widthRequest or self.w
    if width <= 0 then width = 20 end
    return width, #util.wrap(self.text, width)
  end
  return math.max(self.widthRequest or 0, #self.text), self.heightRequest or 1
end

function Label:draw(s)
  local fg = self.fg or (self.dim and theme.c.dim or theme.c.text)
  local bg = self.bg
  if bg then s:fill(self.x, self.y, self.w, self.h, " ", fg, bg) end
  bg = bg or select(3, s:getCell(self.x, self.y)) or theme.c.window

  local lines = self.wrap and util.wrap(self.text, self.w) or { self.text }
  for i = 1, math.min(#lines, self.h) do
    local line = util.ellipsis(lines[i], self.w)
    local x = self.x
    if self.align == "center" then
      x = self.x + math.floor((self.w - #line) / 2)
    elseif self.align == "end" then
      x = self.x + self.w - #line
    end
    s:write(x, self.y + i - 1, line, fg, bg)
  end
end

------------------------------------------------------------------ Button ----

local Button = util.class(Widget)
W.Button = Button

function Button:init(props)
  props = props or {}
  if type(props) == "string" then props = { label = props } end
  Widget.init(self, props)
  self.label = props.label or ""
  self.style = props.style or "normal"   -- normal|suggested|destructive|flat|accent-flat
  self.icon = props.icon
  self.focusable = props.focusable ~= false
  self.hover = false
  self.pressed = false
  self.heightRequest = props.height or 1
  if props.onClick then self:connect("clicked", props.onClick) end
end

function Button:setLabel(text)
  self.label = text
  self:invalidate()
end

function Button:contentWidth()
  local n = #self.label
  if self.icon then n = n + #self.icon + 1 end
  return n
end

function Button:measure()
  local pad = self.style == "flat" and 2 or 4
  return math.max(self.widthRequest or 0, self:contentWidth() + pad), self.heightRequest or 1
end

function Button:colours()
  local c = theme.c
  if not self.sensitive then return c.dim, c.card end
  if self.style == "suggested" then
    return c.onAccent, self.hover and c.accentSoft or c.accent
  elseif self.style == "destructive" then
    return c.onAccent, self.hover and c.pink or c.destructive
  elseif self.style == "flat" then
    return self.hover and c.text or (self.dimLabel and c.dim or c.text),
           self.hover and c.hover or nil
  elseif self.style == "accent-flat" then
    return c.accent, self.hover and c.hover or nil
  end
  return c.text, self.hover and c.active or c.card
end

function Button:draw(s)
  local fg, bg = self:colours()
  local y = self.y + math.floor((self.h - 1) / 2)
  local text = self.label
  if self.icon then
    text = self.icon .. (self.label ~= "" and (" " .. self.label) or "")
  end

  if self.style == "flat" or self.style == "accent-flat" then
    if bg then s:fill(self.x, self.y, self.w, self.h, " ", fg, bg) end
    local behind = bg or select(3, s:getCell(self.x, y)) or theme.c.window
    local tx = self.x + math.floor((self.w - #text) / 2)
    s:write(tx, y, util.ellipsis(text, self.w), fg, behind)
  else
    local innerX, innerW = s:pill(self.x, y, self.w, bg)
    local shown = util.ellipsis(text, innerW)
    s:write(innerX + math.floor((innerW - #shown) / 2), y, shown, fg, bg)
  end

  if self.focused then
    -- focus ring: a thin accent underline beneath the control
    local ry = math.min(self.y + self.h - 1, y)
    s:write(self.x, ry, "", theme.c.accent, bg or theme.c.window)
    if self.h > 1 then
      s:fill(self.x, self.y + self.h - 1, self.w, 1, "\131", theme.c.accent, theme.c.window)
    end
  end
end

function Button:onMouse(kind, button, px, py)
  if not self.sensitive then return false end
  if kind == "mouse_click" then
    self.pressed = true
    self:invalidate()
    return true
  elseif kind == "mouse_up" then
    if self.pressed then
      self.pressed = false
      self:emit("clicked")
      self:invalidate()
    end
    return true
  end
  return false
end

function Button:onKey(key)
  if key == keys.enter or key == keys.space then
    self:emit("clicked")
    return true
  end
  return false
end

-------------------------------------------------------------- IconButton ----

local IconButton = util.class(Button)
W.IconButton = IconButton

function IconButton:init(props)
  props = props or {}
  props.style = props.style or "flat"
  props.label = ""
  Button.init(self, props)
  self.icon = props.icon or "\4"
  self.widthRequest = props.width or 3
end

function IconButton:measure()
  return self.widthRequest or 3, self.heightRequest or 1
end

------------------------------------------------------------------ Toggle ----

local Switch = util.class(Widget)
W.Switch = Switch

function Switch:init(props)
  props = props or {}
  Widget.init(self, props)
  self.active = props.active or false
  self.focusable = true
  self.widthRequest = 4
  self.heightRequest = 1
  if props.onChange then self:connect("changed", props.onChange) end
end

function Switch:setActive(value, silent)
  value = value and true or false
  if self.active ~= value then
    self.active = value
    if not silent then self:emit("changed", value) end
    self:invalidate()
  end
end

function Switch:measure() return 4, 1 end

function Switch:draw(s)
  local c = theme.c
  local track = self.active and c.accent or c.active
  local knob = c.onAccent
  s:pill(self.x, self.y, 4, track)
  local knobX = self.active and (self.x + 2) or (self.x + 1)
  s:write(knobX, self.y, "\7", knob, track)
end

function Switch:onMouse(kind)
  if kind == "mouse_click" then
    self:setActive(not self.active)
    return true
  end
  return kind == "mouse_up"
end

function Switch:onKey(key)
  if key == keys.space or key == keys.enter then
    self:setActive(not self.active)
    return true
  end
  return false
end

---------------------------------------------------------------- CheckBox ----

local CheckBox = util.class(Widget)
W.CheckBox = CheckBox

function CheckBox:init(props)
  props = props or {}
  Widget.init(self, props)
  self.label = props.label or ""
  self.active = props.active or false
  self.focusable = true
  self.heightRequest = 1
  if props.onChange then self:connect("changed", props.onChange) end
end

function CheckBox:measure() return #self.label + 4, 1 end

function CheckBox:draw(s)
  local c = theme.c
  local bg = select(3, s:getCell(self.x, self.y)) or c.window
  local mark = self.active and "\251" or " "
  local boxBg = self.active and c.accent or c.active
  s:write(self.x, self.y, " ", c.onAccent, boxBg)
  s:write(self.x, self.y, mark, c.onAccent, boxBg)
  s:write(self.x + 2, self.y, util.ellipsis(self.label, self.w - 2), c.text, bg)
end

function CheckBox:onMouse(kind)
  if kind == "mouse_click" then
    self.active = not self.active
    self:emit("changed", self.active)
    self:invalidate()
    return true
  end
  return kind == "mouse_up"
end

CheckBox.onKey = Switch.onKey

-------------------------------------------------------------------- Entry ---

local Entry = util.class(Widget)
W.Entry = Entry

function Entry:init(props)
  props = props or {}
  Widget.init(self, props)
  self.text = props.text or ""
  self.placeholder = props.placeholder or ""
  self.cursor = #self.text + 1
  self.scroll = 0
  self.focusable = true
  self.password = props.password or false
  self.icon = props.icon
  self.heightRequest = 1
  self.flat = props.flat or false
  self.textInput = true
  if props.onChange then self:connect("changed", props.onChange) end
  if props.onActivate then self:connect("activate", props.onActivate) end
end

function Entry:setText(text, silent)
  self.text = tostring(text or "")
  self.cursor = #self.text + 1
  self.scroll = 0
  if not silent then self:emit("changed", self.text) end
  self:invalidate()
end

function Entry:measure()
  return math.max(self.widthRequest or 0, 12), 1
end

function Entry:visibleText()
  local shown = self.password and string.rep("\7", #self.text) or self.text
  return shown
end

function Entry:innerRect()
  if self.flat then return self.x, self.w end
  return self.x + 1, self.w - 2
end

function Entry:draw(s)
  local c = theme.c
  local bg = self.flat and (select(3, s:getCell(self.x, self.y)) or c.window) or c.view
  local innerX, innerW = self:innerRect()
  if self.icon then innerW = innerW - 2 end

  if self.flat then
    s:fill(self.x, self.y, self.w, 1, " ", c.text, bg)
  else
    s:pill(self.x, self.y, self.w, bg)
  end

  local textX = innerX
  if self.icon then
    s:write(innerX, self.y, self.icon, self.focused and c.accent or c.dim, bg)
    textX = innerX + 2
  end

  local shown = self:visibleText()
  -- keep the caret in view
  if self.cursor - self.scroll > innerW then self.scroll = self.cursor - innerW end
  if self.cursor - self.scroll < 1 then self.scroll = self.cursor - 1 end
  if self.scroll < 0 then self.scroll = 0 end

  if shown == "" and not self.focused then
    s:write(textX, self.y, util.ellipsis(self.placeholder, innerW), c.dim, bg)
  else
    s:write(textX, self.y, shown:sub(self.scroll + 1, self.scroll + innerW), c.text, bg)
  end

  if self.focused then
    self.caret = { x = textX + (self.cursor - self.scroll - 1), y = self.y, colour = c.accent }
  else
    self.caret = nil
  end
end

function Entry:onMouse(kind, button, px, py)
  if kind == "mouse_click" then
    local innerX = self:innerRect()
    if self.icon then innerX = innerX + 2 end
    self.cursor = util.clamp(px - innerX + 1 + self.scroll, 1, #self.text + 1)
    self:invalidate()
    return true
  end
  return kind == "mouse_up"
end

function Entry:onChar(ch)
  self.text = self.text:sub(1, self.cursor - 1) .. ch .. self.text:sub(self.cursor)
  self.cursor = self.cursor + 1
  self:emit("changed", self.text)
  self:invalidate()
  return true
end

function Entry:onPaste(text)
  text = text:gsub("[\r\n]", " ")
  self.text = self.text:sub(1, self.cursor - 1) .. text .. self.text:sub(self.cursor)
  self.cursor = self.cursor + #text
  self:emit("changed", self.text)
  self:invalidate()
  return true
end

function Entry:onKey(key)
  if key == keys.backspace then
    if self.cursor > 1 then
      self.text = self.text:sub(1, self.cursor - 2) .. self.text:sub(self.cursor)
      self.cursor = self.cursor - 1
      self:emit("changed", self.text)
    end
  elseif key == keys.delete then
    self.text = self.text:sub(1, self.cursor - 1) .. self.text:sub(self.cursor + 1)
    self:emit("changed", self.text)
  elseif key == keys.left then
    self.cursor = math.max(1, self.cursor - 1)
  elseif key == keys.right then
    self.cursor = math.min(#self.text + 1, self.cursor + 1)
  elseif key == keys.home then
    self.cursor = 1
  elseif key == keys["end"] then
    self.cursor = #self.text + 1
  elseif key == keys.enter then
    self:emit("activate", self.text)
  else
    return false
  end
  self:invalidate()
  return true
end

--------------------------------------------------------------- Separator ----

local Separator = util.class(Widget)
W.Separator = Separator

function Separator:init(props)
  props = props or {}
  Widget.init(self, props)
  self.orientation = props.orientation or "horizontal"
  self.heightRequest = self.orientation == "horizontal" and 1 or (props.height or 1)
  self.widthRequest = self.orientation == "vertical" and 1 or (props.width or 1)
end

function Separator:measure()
  if self.orientation == "horizontal" then return self.widthRequest or 1, 1 end
  return 1, self.heightRequest or 1
end

function Separator:draw(s)
  local c = theme.c
  if self.orientation == "horizontal" then
    s:fill(self.x, self.y, self.w, 1, "\131", c.separator, select(3, s:getCell(self.x, self.y)) or c.window)
  else
    s:fill(self.x, self.y, 1, self.h, "\149", c.separator, select(3, s:getCell(self.x, self.y)) or c.window)
  end
end

------------------------------------------------------------- ProgressBar ----

local ProgressBar = util.class(Widget)
W.ProgressBar = ProgressBar

function ProgressBar:init(props)
  props = props or {}
  Widget.init(self, props)
  self.value = props.value or 0
  self.heightRequest = 1
end

function ProgressBar:setValue(v)
  self.value = util.clamp(v, 0, 1)
  self:invalidate()
end

function ProgressBar:measure() return math.max(self.widthRequest or 0, 10), 1 end

function ProgressBar:draw(s)
  local c = theme.c
  local filled = math.floor(self.w * util.clamp(self.value, 0, 1) + 0.5)
  s:fill(self.x, self.y, self.w, 1, "\140", c.active, select(3, s:getCell(self.x, self.y)) or c.window)
  if filled > 0 then
    s:fill(self.x, self.y, filled, 1, "\140", c.accent, select(3, s:getCell(self.x, self.y)) or c.window)
  end
end

----------------------------------------------------------------- Spinner ----

local Spinner = util.class(Widget)
W.Spinner = Spinner

local SPIN = { "\140", "\138", "\133", "\131", "\135", "\139" }

function Spinner:init(props)
  Widget.init(self, props)
  self.frame = 1
  self.widthRequest, self.heightRequest = 1, 1
end

function Spinner:tick()
  self.frame = self.frame % #SPIN + 1
  self:invalidate()
end

function Spinner:measure() return 1, 1 end

function Spinner:draw(s)
  s:write(self.x, self.y, SPIN[self.frame], theme.c.accent,
          select(3, s:getCell(self.x, self.y)) or theme.c.window)
end

----------------------------------------------------------------- ListBox ----

local ListBox = util.class(Widget)
W.ListBox = ListBox

--- rows = { { title=, subtitle=, icon={char=,colour=}, value=, trailing=, header= }, ... }
function ListBox:init(props)
  props = props or {}
  Widget.init(self, props)
  self.rows = props.rows or {}
  self.selected = props.selected or 1
  self.hoverRow = nil
  self.focusable = true
  self.rowHeight = props.rowHeight or 1
  self.showSubtitles = props.showSubtitles ~= false
  self.background = props.background
  self.card = props.card or false
  if props.onActivate then self:connect("activate", props.onActivate) end
  if props.onSelect then self:connect("select", props.onSelect) end
end

function ListBox:setRows(rows, keepSelection)
  self.rows = rows or {}
  if not keepSelection then self.selected = math.min(self.selected, #self.rows) end
  if self.selected < 1 and #self.rows > 0 then self.selected = 1 end
  self:relayout()
end

function ListBox:rowSpan(row)
  if row.header then return 1 end
  if self.showSubtitles and row.subtitle then return 2 end
  return self.rowHeight
end

function ListBox:measure()
  local h = 0
  for _, row in ipairs(self.rows) do h = h + self:rowSpan(row) end
  return math.max(self.widthRequest or 0, 16), math.max(h, self.heightRequest or 1)
end

function ListBox:rowAt(py)
  local y = self.y
  for i, row in ipairs(self.rows) do
    local span = self:rowSpan(row)
    if py >= y and py < y + span then return i end
    y = y + span
  end
  return nil
end

function ListBox:select(index, silent)
  index = util.clamp(index, 1, math.max(1, #self.rows))
  if self.rows[index] and self.rows[index].header then
    index = index + 1
  end
  if index ~= self.selected then
    self.selected = index
    if not silent then self:emit("select", index, self.rows[index]) end
    self:invalidate()
  end
end

function ListBox:current() return self.rows[self.selected] end

function ListBox:draw(s)
  local c = theme.c
  local baseBg = self.background or (self.card and c.card or c.view)
  s:fill(self.x, self.y, self.w, self.h, " ", c.text, baseBg)

  local y = self.y
  for i, row in ipairs(self.rows) do
    local span = self:rowSpan(row)
    if y + span - 1 >= self.y and y < self.y + self.h then
      if row.header then
        s:write(self.x + 1, y, util.ellipsis(row.title:upper(), self.w - 2), c.dim, baseBg)
      else
        local selected = (i == self.selected)
        local bg = baseBg
        local fg = c.text
        if selected then
          bg = self.focused and c.accent or c.active
          fg = c.onAccent
        elseif i == self.hoverRow then
          bg = c.hover
        end
        s:fill(self.x, y, self.w, span, " ", fg, bg)

        local tx = self.x + 1
        if row.icon then
          s:write(tx, y, row.icon.char or "\4",
                  selected and c.onAccent or (row.icon.colour or c.accent), bg)
          tx = tx + 2
        end
        local trailing = row.trailing and tostring(row.trailing) or nil
        local avail = self.w - (tx - self.x) - 1 - (trailing and (#trailing + 1) or 0)
        s:write(tx, y, util.ellipsis(row.title or "", avail), fg, bg)
        if trailing then
          s:write(self.x + self.w - #trailing - 1, y, trailing,
                  selected and c.onAccent or c.dim, bg)
        end
        if span > 1 and row.subtitle then
          s:write(tx, y + 1, util.ellipsis(row.subtitle, avail),
                  selected and c.onAccent or c.dim, bg)
        end
      end
    end
    y = y + span
  end
end

function ListBox:onMouse(kind, button, px, py)
  local index = self:rowAt(py)
  if not index then return false end
  local row = self.rows[index]
  if row and row.header then return false end
  if kind == "mouse_click" then
    local wasSelected = self.selected == index
    self:select(index)
    self.clickTime = os.clock()
    if wasSelected and self.lastClick and os.clock() - self.lastClick < 0.5 then
      self:emit("activate", index, row)
      self.lastClick = nil
    else
      self.lastClick = os.clock()
    end
    return true
  elseif kind == "mouse_up" then
    return true
  end
  return false
end

function ListBox:onKey(key)
  if key == keys.up then
    local i = self.selected - 1
    while i >= 1 and self.rows[i] and self.rows[i].header do i = i - 1 end
    if i >= 1 then self:select(i) end
    return true
  elseif key == keys.down then
    local i = self.selected + 1
    while self.rows[i] and self.rows[i].header do i = i + 1 end
    if i <= #self.rows then self:select(i) end
    return true
  elseif key == keys.enter then
    self:emit("activate", self.selected, self.rows[self.selected])
    return true
  elseif key == keys.home then
    self:select(1)
    return true
  elseif key == keys["end"] then
    self:select(#self.rows)
    return true
  end
  return false
end

---------------------------------------------------------------- IconGrid ----

local IconGrid = util.class(Widget)
W.IconGrid = IconGrid

--- items = { { label=, icon={colour=,glyph=,art=}, value= }, ... }
function IconGrid:init(props)
  props = props or {}
  Widget.init(self, props)
  self.items = props.items or {}
  self.selected = props.selected or 1
  self.cellW = props.cellW or 9
  self.cellH = props.cellH or 5
  self.iconW = props.iconW or 6
  self.iconH = props.iconH or 3
  self.focusable = true
  self.background = props.background
  if props.onActivate then self:connect("activate", props.onActivate) end
  if props.onSelect then self:connect("select", props.onSelect) end
end

function IconGrid:setItems(items)
  self.items = items or {}
  if self.selected > #self.items then self.selected = math.max(1, #self.items) end
  self:relayout()
end

function IconGrid:columns()
  return math.max(1, math.floor(self.w / self.cellW))
end

function IconGrid:measure()
  local cols = math.max(1, math.floor((self.widthRequest or self.w or self.cellW) / self.cellW))
  local rows = math.ceil(#self.items / cols)
  return self.widthRequest or (cols * self.cellW), math.max(1, rows * self.cellH)
end

function IconGrid:itemAt(px, py)
  local cols = self:columns()
  local gridW = cols * self.cellW
  local ox = self.x + math.floor((self.w - gridW) / 2)
  local col = math.floor((px - ox) / self.cellW)
  local row = math.floor((py - self.y) / self.cellH)
  if col < 0 or col >= cols or row < 0 then return nil end
  local index = row * cols + col + 1
  if index > #self.items then return nil end
  return index
end

function IconGrid:draw(s)
  local c = theme.c
  local bg = self.background
  if bg then s:fill(self.x, self.y, self.w, self.h, " ", c.text, bg) end
  bg = bg or select(3, s:getCell(self.x, self.y)) or c.window

  local cols = self:columns()
  local gridW = cols * self.cellW
  local ox = self.x + math.floor((self.w - gridW) / 2)

  for i, item in ipairs(self.items) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local cx = ox + col * self.cellW
    local cy = self.y + row * self.cellH
    if cy + self.cellH - 1 >= self.y and cy < self.y + self.h + self.cellH then
      local selected = (i == self.selected)
      local cellBg = bg
      if selected then
        cellBg = self.focused and c.hover or c.hover
        s:fill(cx, cy, self.cellW, self.cellH, " ", c.text, cellBg)
        local behind = bg
        s:roundCorner(cx, cy, "tl", cellBg, behind)
        s:roundCorner(cx + self.cellW - 1, cy, "tr", cellBg, behind)
        s:roundCorner(cx, cy + self.cellH - 1, "bl", cellBg, behind)
        s:roundCorner(cx + self.cellW - 1, cy + self.cellH - 1, "br", cellBg, behind)
      end
      local iconX = cx + math.floor((self.cellW - self.iconW) / 2)
      pixel.drawIcon(s, iconX, cy, item.icon or {}, self.iconW, self.iconH, cellBg)
      local label = util.ellipsis(item.label or "", self.cellW - 1)
      s:write(cx + math.floor((self.cellW - #label) / 2), cy + self.iconH,
              label, selected and c.text or c.text, cellBg)
      if item.subtitle and self.cellH > self.iconH + 1 then
        local sub = util.ellipsis(item.subtitle, self.cellW - 1)
        s:write(cx + math.floor((self.cellW - #sub) / 2), cy + self.iconH + 1, sub, c.dim, cellBg)
      end
    end
  end
end

function IconGrid:onMouse(kind, button, px, py)
  local index = self:itemAt(px, py)
  if not index then return false end
  if kind == "mouse_click" then
    local repeated = (self.selected == index) and self.lastClick and (os.clock() - self.lastClick < 0.5)
    self.selected = index
    self:emit("select", index, self.items[index])
    if repeated then
      self:emit("activate", index, self.items[index])
      self.lastClick = nil
    else
      self.lastClick = os.clock()
    end
    self:invalidate()
    return true
  end
  return kind == "mouse_up"
end

function IconGrid:onKey(key)
  local cols = self:columns()
  local before = self.selected
  if key == keys.left then self.selected = math.max(1, self.selected - 1)
  elseif key == keys.right then self.selected = math.min(#self.items, self.selected + 1)
  elseif key == keys.up then self.selected = math.max(1, self.selected - cols)
  elseif key == keys.down then self.selected = math.min(#self.items, self.selected + cols)
  elseif key == keys.enter then
    self:emit("activate", self.selected, self.items[self.selected])
    return true
  else
    return false
  end
  if before ~= self.selected then
    self:emit("select", self.selected, self.items[self.selected])
    self:invalidate()
  end
  return true
end

-------------------------------------------------------------- StatusPage ----

--- GNOME's empty-state: big icon, title, description, optional button.
local StatusPage = util.class(Widget)
W.StatusPage = StatusPage

function StatusPage:init(props)
  props = props or {}
  Widget.init(self, props)
  self.title = props.title or ""
  self.description = props.description or ""
  self.icon = props.icon
  self.vexpand = true
  self.hexpand = true
end

function StatusPage:measure() return 20, 6 end

function StatusPage:draw(s)
  local c = theme.c
  local bg = theme.c.window
  s:fill(self.x, self.y, self.w, self.h, " ", c.text, bg)
  local lines = util.wrap(self.description, math.min(self.w - 4, 34))
  local blockH = 3 + 1 + 1 + #lines
  local top = self.y + math.max(0, math.floor((self.h - blockH) / 2))
  if self.icon then
    pixel.drawIcon(s, self.x + math.floor((self.w - 6) / 2), top, self.icon, 6, 3, bg)
  end
  s:writeCentered(top + 4, self.title, c.text, bg, self.x, self.w)
  for i, line in ipairs(lines) do
    s:writeCentered(top + 5 + i, line, c.dim, bg, self.x, self.w)
  end
end

----------------------------------------------------------------- Toolbar ----

local Toolbar = util.class(base.Box)
W.Toolbar = Toolbar

function Toolbar:init(props)
  props = props or {}
  props.orientation = props.orientation or "horizontal"
  props.spacing = props.spacing or 1
  base.Box.init(self, props)
  -- A toolbar always spans its parent; without this it would collapse to the
  -- width of its buttons.
  self.hexpand = props.hexpand ~= false
  self.heightRequest = props.height or 1
  self.background = props.background or theme.c.header
end

function Toolbar:measure()
  return math.max(self.widthRequest or 0, 10), self.heightRequest or 1
end

function Toolbar:draw(s)
  s:fill(self.x, self.y, self.w, self.h, " ", theme.c.text, self.background or theme.c.header)
  for _, c in ipairs(self.children) do
    if c.visible then c:draw(s) end
  end
end

--------------------------------------------------------------- ViewTabs -----

local Tabs = util.class(Widget)
W.Tabs = Tabs

function Tabs:init(props)
  props = props or {}
  Widget.init(self, props)
  self.tabs = props.tabs or {}     -- { {label=, id=}, ... }
  self.active = props.active or 1
  self.heightRequest = 1
  if props.onChange then self:connect("changed", props.onChange) end
end

function Tabs:measure()
  local w = 0
  for _, t in ipairs(self.tabs) do w = w + #t.label + 3 end
  return w, 1
end

function Tabs:tabAt(px)
  local x = self.x
  for i, t in ipairs(self.tabs) do
    local w = #t.label + 3
    if px >= x and px < x + w then return i end
    x = x + w
  end
  return nil
end

function Tabs:setActive(i)
  if i ~= self.active and self.tabs[i] then
    self.active = i
    self:emit("changed", i, self.tabs[i])
    self:invalidate()
  end
end

function Tabs:draw(s)
  local c = theme.c
  local bg = select(3, s:getCell(self.x, self.y)) or c.header
  s:fill(self.x, self.y, self.w, 1, " ", c.dim, bg)
  local x = self.x
  for i, t in ipairs(self.tabs) do
    local w = #t.label + 3
    if i == self.active then
      s:pill(x, self.y, w, c.accent, bg)
      s:write(x + 2, self.y, t.label, c.onAccent, c.accent)
    else
      s:write(x + 2, self.y, t.label, c.dim, bg)
    end
    x = x + w
  end
end

function Tabs:onMouse(kind, button, px)
  if kind == "mouse_click" then
    local i = self:tabAt(px)
    if i then self:setActive(i) return true end
  end
  return kind == "mouse_up"
end

---------------------------------------------------------------- Dropdown ----

local Dropdown = util.class(Widget)
W.Dropdown = Dropdown

function Dropdown:init(props)
  props = props or {}
  Widget.init(self, props)
  self.options = props.options or {}   -- { {label=, value=}, ... }
  self.selected = props.selected or 1
  self.focusable = true
  self.heightRequest = 1
  self.placeholder = props.placeholder or "Choose"
  if props.onChange then self:connect("changed", props.onChange) end
end

function Dropdown:value()
  local opt = self.options[self.selected]
  return opt and (opt.value ~= nil and opt.value or opt.label)
end

function Dropdown:setSelected(i, silent)
  if self.options[i] and i ~= self.selected then
    self.selected = i
    if not silent then self:emit("changed", i, self.options[i]) end
    self:invalidate()
  end
end

function Dropdown:measure()
  local w = #self.placeholder
  for _, o in ipairs(self.options) do w = math.max(w, #o.label) end
  return math.max(self.widthRequest or 0, w + 6), 1
end

function Dropdown:draw(s)
  local c = theme.c
  local opt = self.options[self.selected]
  local label = opt and opt.label or self.placeholder
  local bg = self.focused and c.active or c.card
  local innerX, innerW = s:pill(self.x, self.y, self.w, bg)
  s:write(innerX, self.y, util.ellipsis(label, innerW - 2), c.text, bg)
  s:write(self.x + self.w - 2, self.y, "\31", c.dim, bg)
end

function Dropdown:onMouse(kind, button, px, py)
  if kind == "mouse_click" then
    self:emit("open", self)
    return true
  end
  return kind == "mouse_up"
end

function Dropdown:onKey(key)
  if key == keys.left or key == keys.up then
    self:setSelected(math.max(1, self.selected - 1))
    return true
  elseif key == keys.right or key == keys.down then
    self:setSelected(math.min(#self.options, self.selected + 1))
    return true
  elseif key == keys.enter or key == keys.space then
    self:emit("open", self)
    return true
  end
  return false
end

------------------------------------------------------------------ Chart -----

--- A tiny bar/line chart used by Sheets and the System Monitor.
local Chart = util.class(Widget)
W.Chart = Chart

function Chart:init(props)
  props = props or {}
  Widget.init(self, props)
  self.series = props.series or {}
  self.kind = props.kind or "bar"      -- bar | line
  self.colour = props.colour or theme.c.accent
  self.heightRequest = props.height or 6
end

function Chart:setSeries(values)
  self.series = values or {}
  self:invalidate()
end

function Chart:measure()
  return math.max(self.widthRequest or 0, 12), self.heightRequest or 6
end

function Chart:draw(s)
  local c = theme.c
  local bg = c.view
  s:fill(self.x, self.y, self.w, self.h, " ", c.text, bg)
  if #self.series == 0 then
    s:writeCentered(self.y + math.floor(self.h / 2), "No data", c.dim, bg, self.x, self.w)
    return
  end

  local canvas = pixel.Canvas(self.w, self.h, bg)
  local maxV, minV = self.series[1], self.series[1]
  for _, v in ipairs(self.series) do
    maxV = math.max(maxV, v)
    minV = math.min(minV, v)
  end
  if maxV == minV then maxV = minV + 1 end
  local pw, ph = canvas.w, canvas.h

  if self.kind == "line" then
    local prevX, prevY
    for i, v in ipairs(self.series) do
      local px = 1 + math.floor((i - 1) / math.max(1, #self.series - 1) * (pw - 1))
      local py = ph - math.floor((v - minV) / (maxV - minV) * (ph - 1))
      if prevX then canvas:line(prevX, prevY, px, py, self.colour) end
      prevX, prevY = px, py
    end
  else
    local barW = math.max(1, math.floor(pw / #self.series))
    for i, v in ipairs(self.series) do
      local height = math.floor((v - minV) / (maxV - minV) * ph)
      if height < 1 and v > minV then height = 1 end
      local bx = 1 + (i - 1) * barW
      if height > 0 then
        canvas:rect(bx, ph - height + 1, math.max(1, barW - 1), height, self.colour)
      end
    end
  end
  canvas:render(s, self.x, self.y)
end

return W
