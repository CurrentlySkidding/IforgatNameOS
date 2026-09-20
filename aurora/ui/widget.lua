--[[ aurora.ui.widget --------------------------------------------------------
     The widget base class plus the layout containers.  Deliberately modelled
     on GTK4: widgets measure, then get allocated a rectangle, then draw.
     Signals are plain callbacks.
----------------------------------------------------------------------------]]

local util  = arequire("lib.util")
local theme = arequire("gfx.theme")

local M = {}

----------------------------------------------------------------- Widget -----

local Widget = util.class()
M.Widget = Widget

function Widget:init(props)
  props = props or {}
  self.x, self.y, self.w, self.h = 1, 1, 0, 0
  self.visible = props.visible ~= false
  self.sensitive = props.sensitive ~= false
  self.hexpand = props.hexpand or false
  self.vexpand = props.vexpand or false
  self.widthRequest = props.width
  self.heightRequest = props.height
  self.marginTop = props.marginTop or props.margin or 0
  self.marginBottom = props.marginBottom or props.margin or 0
  self.marginStart = props.marginStart or props.margin or 0
  self.marginEnd = props.marginEnd or props.margin or 0
  self.focusable = props.focusable or false
  self.tooltip = props.tooltip
  self.name = props.name
  self.children = {}
  self.handlers = {}
  self.app = nil
end

function Widget:connect(signal, fn)
  self.handlers[signal] = self.handlers[signal] or {}
  table.insert(self.handlers[signal], fn)
  return self
end

function Widget:emit(signal, ...)
  local list = self.handlers[signal]
  if not list then return false end
  for _, fn in ipairs(list) do fn(self, ...) end
  return true
end

function Widget:invalidate()
  local root = self
  while root.parent do root = root.parent end
  if root.app then root.app:queueDraw() end
end

function Widget:relayout()
  local root = self
  while root.parent do root = root.parent end
  if root.app then root.app:queueLayout() end
end

function Widget:add(child)
  child.parent = self
  self.children[#self.children + 1] = child
  self:relayout()
  return child
end

function Widget:remove(child)
  for i, c in ipairs(self.children) do
    if c == child then
      table.remove(self.children, i)
      child.parent = nil
      self:relayout()
      return true
    end
  end
  return false
end

function Widget:clear()
  for _, c in ipairs(self.children) do c.parent = nil end
  self.children = {}
  self:relayout()
end

--- Natural size before expansion.
function Widget:measure()
  return self.widthRequest or 1, self.heightRequest or 1
end

function Widget:allocate(x, y, w, h)
  self.x, self.y, self.w, self.h = x, y, w, h
end

function Widget:draw(s) end

--- Absolute bounds test in surface coordinates.
function Widget:contains(px, py)
  return px >= self.x and px < self.x + self.w and py >= self.y and py < self.y + self.h
end

--- Deepest visible child under the point.
function Widget:pick(px, py)
  if not self.visible or not self:contains(px, py) then return nil end
  for i = #self.children, 1, -1 do
    local hit = self.children[i]:pick(px, py)
    if hit then return hit end
  end
  return self
end

--- Mouse handling.  Coordinates are absolute (surface space).
function Widget:onMouse(kind, button, px, py) return false end
function Widget:onKey(key, held) return false end
function Widget:onChar(ch) return false end
function Widget:onPaste(text) return false end
function Widget:onFocus(gained) end

--- Collect focusable descendants in tab order.
function Widget:collectFocusable(out)
  out = out or {}
  if self.visible and self.sensitive and self.focusable then out[#out + 1] = self end
  for _, c in ipairs(self.children) do c:collectFocusable(out) end
  return out
end

function Widget:setVisible(value)
  if self.visible ~= value then
    self.visible = value
    self:relayout()
  end
end

function Widget:find(name)
  if self.name == name then return self end
  for _, c in ipairs(self.children) do
    local found = c:find(name)
    if found then return found end
  end
  return nil
end

-------------------------------------------------------------------- Box -----

local Box = util.class(Widget)
M.Box = Box

function Box:init(props)
  Widget.init(self, props)
  self.orientation = props.orientation or "vertical"
  self.spacing = props.spacing or 0
  self.homogeneous = props.homogeneous or false
  self.padding = props.padding or 0
  self.background = props.background
end

function Box:measure()
  local horizontal = self.orientation == "horizontal"
  local main, cross = 0, 0
  local count = 0
  for _, c in ipairs(self.children) do
    if c.visible then
      local cw, ch = c:measure()
      cw = cw + c.marginStart + c.marginEnd
      ch = ch + c.marginTop + c.marginBottom
      if horizontal then
        main = main + cw
        cross = math.max(cross, ch)
      else
        main = main + ch
        cross = math.max(cross, cw)
      end
      count = count + 1
    end
  end
  if count > 1 then main = main + self.spacing * (count - 1) end
  main = main + self.padding * 2
  cross = cross + self.padding * 2
  local w, h
  if horizontal then w, h = main, cross else w, h = cross, main end
  return math.max(self.widthRequest or 0, w), math.max(self.heightRequest or 0, h)
end

function Box:allocate(x, y, w, h)
  Widget.allocate(self, x, y, w, h)
  local horizontal = self.orientation == "horizontal"
  local pad = self.padding
  local innerX, innerY = x + pad, y + pad
  local innerW, innerH = w - pad * 2, h - pad * 2

  local visible = {}
  for _, c in ipairs(self.children) do if c.visible then visible[#visible + 1] = c end end
  if #visible == 0 then return end

  local total = horizontal and innerW or innerH
  local gaps = self.spacing * (#visible - 1)
  local available = total - gaps

  local sizes, expanders = {}, {}
  local used = 0
  for i, c in ipairs(visible) do
    local cw, ch = c:measure()
    local size
    if horizontal then
      size = cw + c.marginStart + c.marginEnd
    else
      size = ch + c.marginTop + c.marginBottom
    end
    if self.homogeneous then size = math.floor(available / #visible) end
    sizes[i] = size
    used = used + size
    if (horizontal and c.hexpand) or (not horizontal and c.vexpand) then
      expanders[#expanders + 1] = i
    end
  end

  local extra = available - used
  if extra > 0 and #expanders > 0 then
    local share = math.floor(extra / #expanders)
    local remainder = extra - share * #expanders
    for n, i in ipairs(expanders) do
      sizes[i] = sizes[i] + share + (n <= remainder and 1 or 0)
    end
  elseif extra < 0 then
    -- Shrink from the end until it fits.
    local deficit = -extra
    for i = #visible, 1, -1 do
      local take = math.min(deficit, math.max(0, sizes[i] - 1))
      sizes[i] = sizes[i] - take
      deficit = deficit - take
      if deficit <= 0 then break end
    end
  end

  local cursor = horizontal and innerX or innerY
  for i, c in ipairs(visible) do
    if horizontal then
      local cw = sizes[i] - c.marginStart - c.marginEnd
      local ch = c.vexpand and (innerH - c.marginTop - c.marginBottom)
                 or math.min(innerH - c.marginTop - c.marginBottom, (select(2, c:measure())))
      c:allocate(cursor + c.marginStart, innerY + c.marginTop, math.max(0, cw), math.max(0, ch))
    else
      local ch = sizes[i] - c.marginTop - c.marginBottom
      local cw = c.hexpand and (innerW - c.marginStart - c.marginEnd)
                 or math.min(innerW - c.marginStart - c.marginEnd, (c:measure()))
      c:allocate(innerX + c.marginStart, cursor + c.marginTop, math.max(0, cw), math.max(0, ch))
    end
    cursor = cursor + sizes[i] + self.spacing
  end
end

function Box:draw(s)
  if self.background then
    s:fill(self.x, self.y, self.w, self.h, " ", theme.c.text, self.background)
  end
  for _, c in ipairs(self.children) do
    if c.visible and c.w > 0 and c.h > 0 then c:draw(s) end
  end
end

------------------------------------------------------------------ Fixed -----

--- Absolute positioning: used by the app builder canvas.
local Fixed = util.class(Widget)
M.Fixed = Fixed

function Fixed:init(props)
  Widget.init(self, props)
  self.background = props and props.background
  self.placements = {}
end

function Fixed:put(child, dx, dy, dw, dh)
  self:add(child)
  self.placements[child] = { x = dx, y = dy, w = dw, h = dh }
  return child
end

function Fixed:allocate(x, y, w, h)
  Widget.allocate(self, x, y, w, h)
  for _, c in ipairs(self.children) do
    local p = self.placements[c] or { x = 0, y = 0 }
    local cw, ch = c:measure()
    c:allocate(x + p.x, y + p.y, p.w or cw, p.h or ch)
  end
end

function Fixed:draw(s)
  if self.background then
    s:fill(self.x, self.y, self.w, self.h, " ", theme.c.text, self.background)
  end
  for _, c in ipairs(self.children) do
    if c.visible then c:draw(s) end
  end
end

------------------------------------------------------------------ Stack -----

--- Show one child at a time; the basis of tabbed views and wizards.
local Stack = util.class(Widget)
M.Stack = Stack

function Stack:init(props)
  Widget.init(self, props)
  self.pages = {}
  self.order = {}
  self.currentName = nil
end

function Stack:addPage(name, child, title)
  self.pages[name] = { widget = child, title = title or name }
  self.order[#self.order + 1] = name
  self:add(child)
  child.visible = false
  if not self.currentName then self:setPage(name) end
  return child
end

function Stack:setPage(name)
  if not self.pages[name] then return false end
  for pageName, page in pairs(self.pages) do
    page.widget.visible = (pageName == name)
  end
  self.currentName = name
  self:emit("changed", name)
  self:relayout()
  return true
end

function Stack:current()
  local page = self.pages[self.currentName]
  return page and page.widget
end

function Stack:measure()
  local w, h = self.widthRequest or 1, self.heightRequest or 1
  for _, page in pairs(self.pages) do
    local cw, ch = page.widget:measure()
    w, h = math.max(w, cw), math.max(h, ch)
  end
  return w, h
end

function Stack:allocate(x, y, w, h)
  Widget.allocate(self, x, y, w, h)
  local child = self:current()
  if child then child:allocate(x, y, w, h) end
end

function Stack:draw(s)
  local child = self:current()
  if child then child:draw(s) end
end

--------------------------------------------------------- ScrolledWindow -----

local Scrolled = util.class(Widget)
M.Scrolled = Scrolled

function Scrolled:init(props)
  props = props or {}
  Widget.init(self, props)
  self.offset = 0
  self.contentH = 0
  self.background = props.background or theme.c.view
  self.showBar = props.showBar ~= false
  self.step = props.step or 2
end

function Scrolled:setChild(child)
  self:clear()
  self:add(child)
  self.offset = 0
  return child
end

function Scrolled:child() return self.children[1] end

function Scrolled:measure()
  local c = self:child()
  if not c then return self.widthRequest or 1, self.heightRequest or 1 end
  local cw, ch = c:measure()
  return math.max(self.widthRequest or 0, cw), math.max(self.heightRequest or 0, ch)
end

function Scrolled:allocate(x, y, w, h)
  Widget.allocate(self, x, y, w, h)
  local c = self:child()
  if not c then return end
  local barW = 0
  local _, ch = c:measure()
  self.contentH = ch
  if self.showBar and ch > h then barW = 1 end
  self.barW = barW
  c:allocate(x, y - self.offset, w - barW, math.max(ch, h))
  self:clampOffset()
end

function Scrolled:clampOffset()
  local maxOffset = math.max(0, self.contentH - self.h)
  if self.offset > maxOffset then self.offset = maxOffset end
  if self.offset < 0 then self.offset = 0 end
end

function Scrolled:scrollBy(delta)
  local before = self.offset
  self.offset = self.offset + delta
  self:clampOffset()
  if before ~= self.offset then
    self:relayout()
    return true
  end
  return false
end

function Scrolled:scrollTo(row)
  self.offset = row
  self:clampOffset()
  self:relayout()
end

--- Keep an absolute content row inside the viewport.
function Scrolled:reveal(contentRow, padding)
  padding = padding or 0
  local top = self.offset
  local bottom = self.offset + self.h - 1
  if contentRow - padding < top then
    self.offset = math.max(0, contentRow - padding)
  elseif contentRow + padding > bottom then
    self.offset = contentRow + padding - self.h + 1
  end
  self:clampOffset()
end

function Scrolled:draw(s)
  local c = self:child()
  s:fill(self.x, self.y, self.w, self.h, " ", theme.c.text, self.background)
  if not c then return end

  s:pushClip(self.x, self.y, self.w - (self.barW or 0), self.h)
  c:draw(s)
  s:popClip()

  if self.barW and self.barW > 0 then
    local trackX = self.x + self.w - 1
    s:fill(trackX, self.y, 1, self.h, " ", theme.c.dim, self.background)
    local ratio = self.h / self.contentH
    local thumb = math.max(1, math.floor(self.h * ratio))
    local maxOffset = math.max(1, self.contentH - self.h)
    local pos = math.floor((self.h - thumb) * (self.offset / maxOffset))
    for i = 0, thumb - 1 do
      s:write(trackX, self.y + pos + i, "\149", theme.c.dim, self.background)
    end
  end
end

function Scrolled:onMouse(kind, button, px, py)
  if kind == "mouse_scroll" then
    return self:scrollBy(button * self.step)
  end
  return false
end

return M
