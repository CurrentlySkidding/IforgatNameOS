--[[ aurora.ui.app ----------------------------------------------------------
     The application runtime.  An Aurora app builds a widget tree, hands it to
     App and calls :run().  This file owns the per-app event loop, focus
     handling, modal dialogs, popover menus and toasts.
----------------------------------------------------------------------------]]

local util    = arequire("lib.util")
local theme   = arequire("gfx.theme")
local base    = arequire("ui.widget")
local W       = arequire("ui.widgets")
local Surface = arequire("gfx.surface")

local App = util.class()

function App:init(props)
  props = props or {}
  self.surface = aurora.surface()
  self.proc = aurora.proc
  self.running = true
  self.drawDirty = true
  self.layoutDirty = true
  self.focus = nil
  self.modal = nil
  self.popover = nil
  self.toast = nil
  self.captured = nil
  self.shiftHeld = false
  self.ctrlHeld = false
  self.altHeld = false
  self.accelerators = {}
  self.timers = {}
  self.background = props.background or theme.c.window

  if props.title then aurora.setTitle(props.title) end
  if props.icon then aurora.setIcon(props.icon) end

  self.root = props.root or base.Box({ orientation = "vertical" })
  self.root.app = self

  theme.onChange(function() self:queueDraw() end)
end

function App:setRoot(widget)
  self.root = widget
  widget.app = self
  widget.parent = nil
  self:queueLayout()
  return widget
end

function App:queueDraw() self.drawDirty = true end
function App:queueLayout() self.layoutDirty = true self.drawDirty = true end

function App:quit() self.running = false end

------------------------------------------------------------------- focus ----

function App:setFocus(widget)
  if self.focus == widget then return end
  if self.focus then
    self.focus.focused = false
    self.focus:onFocus(false)
  end
  self.focus = widget
  if widget then
    widget.focused = true
    widget:onFocus(true)
  end
  self:queueDraw()
end

function App:focusChain()
  local scope = self.modal or self.root
  return scope:collectFocusable({})
end

function App:cycleFocus(backwards)
  local chain = self:focusChain()
  if #chain == 0 then return end
  local index = util.indexOf(chain, self.focus) or 0
  index = index + (backwards and -1 or 1)
  if index < 1 then index = #chain end
  if index > #chain then index = 1 end
  self:setFocus(chain[index])
end

function App:focusFirst()
  local chain = self:focusChain()
  if chain[1] then self:setFocus(chain[1]) end
end

----------------------------------------------------------- accelerators -----

--- Register a keyboard shortcut.
--- app:accel("ctrl+s", function() ... end)
function App:accel(combo, fn, description)
  self.accelerators[combo:lower()] = { fn = fn, description = description }
end

function App:comboFor(key)
  local name = keys.getName(key)
  if not name then return nil end
  local parts = {}
  if self.ctrlHeld then parts[#parts + 1] = "ctrl" end
  if self.altHeld then parts[#parts + 1] = "alt" end
  if self.shiftHeld then parts[#parts + 1] = "shift" end
  parts[#parts + 1] = name
  return table.concat(parts, "+")
end

------------------------------------------------------------------ layout ----

function App:layout()
  local s = self.surface
  self.root:allocate(1, 1, s.w, s.h)
  if self.modal then self:layoutModal() end
  self.layoutDirty = false
end

function App:layoutModal()
  local s = self.surface
  local dialog = self.modal
  local dw, dh = dialog:measure()
  dw = math.min(math.max(dw, 22), s.w - 2)
  dh = math.min(dh, s.h - 2)
  local dx = math.floor((s.w - dw) / 2) + 1
  local dy = math.floor((s.h - dh) / 2) + 1
  dialog:allocate(dx, dy, dw, dh)
end

------------------------------------------------------------------ render ----

function App:render()
  local s = self.surface
  s:resetClip()
  s:clear(self.background, theme.c.text)
  self.root:draw(s)

  if self.popover then
    self:drawPopover(s)
  end

  if self.modal then
    s:scrim(1, 1, s.w, s.h, theme.c.scrimText, theme.c.scrim)
    local d = self.modal
    local compositor = arequire("gfx.compositor")
    compositor.drawShadow(s, d.x, d.y, d.w, d.h)
    local behind = theme.c.scrim
    s:fill(d.x, d.y, d.w, d.h, " ", theme.c.text, theme.c.card)
    s:roundRect(d.x, d.y, d.w, d.h, theme.c.card, behind)
    d:draw(s)
  end

  if self.toast then self:drawToast(s) end

  -- publish the caret so the compositor can put a real blinking cursor there
  local caret = self.focus and self.focus.caret
  if self.modal and self.focus and not self:isDescendant(self.focus, self.modal) then
    caret = nil
  end
  self.proc.caret = caret
  self.drawDirty = false
  aurora.damage()
end

function App:isDescendant(widget, ancestor)
  local node = widget
  while node do
    if node == ancestor then return true end
    node = node.parent
  end
  return false
end

------------------------------------------------------------------ toasts ----

function App:notify(message, kind)
  self.toast = { message = message, kind = kind or "info", until_ = os.clock() + 3 }
  self.toastTimer = os.startTimer(3)
  self:queueDraw()
end

function App:drawToast(s)
  local c = theme.c
  local t = self.toast
  local text = " " .. util.ellipsis(t.message, s.w - 6) .. " "
  local w = math.min(#text + 2, s.w - 2)
  local x = math.floor((s.w - w) / 2) + 1
  local y = s.h - 1
  local bg = c.card
  local fg = c.text
  if t.kind == "error" then bg, fg = c.destructive, c.onAccent end
  if t.kind == "success" then bg, fg = c.success, c.onAccent end
  local innerX, innerW = s:pill(x, y, w, bg)
  s:write(innerX, y, util.ellipsis(text, innerW), fg, bg)
end

----------------------------------------------------------------- dialogs ----

--- Build and show a modal dialog.
--- opts = { title, body = string | widget, actions = { {label,style,onClick} } }
function App:dialog(opts)
  local box = base.Box({ orientation = "vertical", padding = 1, spacing = 1 })
  box.background = theme.c.card

  local title = W.Label({ text = opts.title or "", align = "center" })
  title.hexpand = true
  box:add(title)

  local body = opts.body
  if type(body) == "string" then
    body = W.Label({ text = body, wrap = true, dim = true, align = "center" })
    body.hexpand = true
  end
  if body then
    body.hexpand = true
    box:add(body)
  end

  if opts.actions and #opts.actions > 0 then
    local row = base.Box({ orientation = "horizontal", spacing = 1 })
    row.hexpand = true
    for _, action in ipairs(opts.actions) do
      local button = W.Button({ label = action.label, style = action.style or "normal" })
      button.hexpand = true
      button:connect("clicked", function()
        self:closeDialog()
        if action.onClick then action.onClick() end
      end)
      row:add(button)
    end
    box:add(row)
  end

  box.app = self
  box.__dialogWidth = opts.width
  self.modal = box
  self.modalReturnFocus = self.focus
  self:queueLayout()
  self:focusFirst()
  return box
end

function App:closeDialog()
  self.modal = nil
  self:setFocus(self.modalReturnFocus)
  self.modalReturnFocus = nil
  self:queueLayout()
end

--- Convenience: a single-field prompt.
function App:prompt(opts)
  local entry = W.Entry({ text = opts.text or "", placeholder = opts.placeholder or "" })
  entry.hexpand = true
  local wrapper = base.Box({ orientation = "vertical", spacing = 1 })
  wrapper.hexpand = true
  if opts.message then
    local label = W.Label({ text = opts.message, wrap = true, dim = true })
    label.hexpand = true
    wrapper:add(label)
  end
  wrapper:add(entry)

  local dialog = self:dialog({
    title = opts.title or "Enter a value",
    body = wrapper,
    actions = {
      { label = opts.cancelLabel or "Cancel", onClick = opts.onCancel },
      { label = opts.acceptLabel or "OK", style = "suggested",
        onClick = function() if opts.onAccept then opts.onAccept(entry.text) end end },
    },
  })
  entry:connect("activate", function()
    self:closeDialog()
    if opts.onAccept then opts.onAccept(entry.text) end
  end)
  self:setFocus(entry)
  return dialog
end

function App:confirm(opts)
  return self:dialog({
    title = opts.title or "Are you sure?",
    body = opts.message,
    actions = {
      { label = opts.cancelLabel or "Cancel", onClick = opts.onCancel },
      { label = opts.acceptLabel or "Continue",
        style = opts.destructive and "destructive" or "suggested",
        onClick = opts.onAccept },
    },
  })
end

---------------------------------------------------------------- popovers ----

--- items = { {label=, icon=, action=fn, separator=bool, disabled=bool}, ... }
function App:menu(x, y, items, width)
  local w = width or 0
  for _, item in ipairs(items) do
    w = math.max(w, #(item.label or "") + (item.accel and #item.accel + 2 or 0) + 4)
  end
  local h = #items
  local s = self.surface
  x = util.clamp(x, 1, math.max(1, s.w - w + 1))
  y = util.clamp(y, 1, math.max(1, s.h - h + 1))
  self.popover = { x = x, y = y, w = w, h = h, items = items, hover = nil }
  self:queueDraw()
  return self.popover
end

function App:closeMenu()
  if self.popover then
    self.popover = nil
    self:queueDraw()
  end
end

function App:drawPopover(s)
  local c = theme.c
  local p = self.popover
  local compositor = arequire("gfx.compositor")
  compositor.drawShadow(s, p.x, p.y, p.w, p.h)
  local behindTL = select(3, s:getCell(p.x, p.y)) or c.window
  s:fill(p.x, p.y, p.w, p.h, " ", c.text, c.card)
  s:roundRect(p.x, p.y, p.w, p.h, c.card, behindTL)
  for i, item in ipairs(p.items) do
    local y = p.y + i - 1
    if item.separator then
      s:fill(p.x + 1, y, p.w - 2, 1, "\131", c.separator, c.card)
    else
      local bg = (p.hover == i) and c.hover or c.card
      local fg = item.disabled and c.dim or c.text
      if item.destructive then fg = c.destructive end
      s:fill(p.x, y, p.w, 1, " ", fg, bg)
      local tx = p.x + 1
      if item.icon then
        s:write(tx, y, item.icon, item.disabled and c.dim or (item.iconColour or c.accent), bg)
        tx = tx + 2
      end
      s:write(tx, y, util.ellipsis(item.label or "", p.w - (tx - p.x) - 1), fg, bg)
      if item.accel then
        s:write(p.x + p.w - #item.accel - 1, y, item.accel, c.dim, bg)
      end
    end
  end
end

function App:popoverHit(px, py)
  local p = self.popover
  if not p then return nil end
  if px < p.x or px >= p.x + p.w or py < p.y or py >= p.y + p.h then return false end
  return py - p.y + 1
end

------------------------------------------------------------------ timers ----

function App:after(seconds, fn)
  local id = os.startTimer(seconds)
  self.timers[id] = fn
  return id
end

function App:every(seconds, fn)
  local function tick()
    fn()
    self.timers[os.startTimer(seconds)] = tick
  end
  self.timers[os.startTimer(seconds)] = tick
end

----------------------------------------------------------------- dispatch ---

local MODIFIERS = {
  [keys.leftShift] = "shift", [keys.rightShift] = "shift",
  [keys.leftCtrl] = "ctrl",   [keys.rightCtrl] = "ctrl",
  [keys.leftAlt] = "alt",     [keys.rightAlt] = "alt",
}

function App:bubbleMouse(widget, kind, button, px, py)
  local node = widget
  while node do
    if node.sensitive and node:onMouse(kind, button, px, py) then return node end
    node = node.parent
  end
  return nil
end

function App:dispatch(ev)
  local name = ev[1]

  if name == "key" then
    local key, held = ev[2], ev[3]
    local modifier = MODIFIERS[key]
    if modifier then
      self[modifier .. "Held"] = true
      if self.focus then self.focus.shiftHeld = self.shiftHeld end
      return
    end

    if self.popover then
      if key == keys.escape then self:closeMenu() return end
      if key == keys.down or key == keys.up then
        local n = #self.popover.items
        local i = self.popover.hover or (key == keys.down and 0 or n + 1)
        repeat
          i = i + (key == keys.down and 1 or -1)
          if i < 1 then i = n end
          if i > n then i = 1 end
        until not self.popover.items[i].separator
        self.popover.hover = i
        self:queueDraw()
        return
      end
      if key == keys.enter and self.popover.hover then
        local item = self.popover.items[self.popover.hover]
        self:closeMenu()
        if item.action and not item.disabled then item.action() end
        return
      end
    end

    if self.modal and key == keys.escape then
      self:closeDialog()
      return
    end

    -- Accelerators never fire while a dialog is up, and a bare key (no
    -- modifier) never fires while the caret is in a text field.
    local combo = self:comboFor(key)
    local accel = combo and self.accelerators[combo]
    if accel and not self.modal then
      local bare = not (self.ctrlHeld or self.altHeld)
      if not (bare and self.focus and self.focus.textInput) then
        accel.fn()
        return
      end
    end

    if key == keys.tab and not self.ctrlHeld then
      self:cycleFocus(self.shiftHeld)
      return
    end

    if self.focus then
      self.focus.shiftHeld = self.shiftHeld
      self.focus.ctrlHeld = self.ctrlHeld
      if self.focus:onKey(key, held) then return end
    end
    self:emitUnhandled("key", key, held)

  elseif name == "key_up" then
    local modifier = MODIFIERS[ev[2]]
    if modifier then
      self[modifier .. "Held"] = false
      if self.focus then self.focus.shiftHeld = self.shiftHeld end
    end

  elseif name == "char" then
    if self.focus and self.focus:onChar(ev[2]) then return end
    self:emitUnhandled("char", ev[2])

  elseif name == "paste" then
    if self.focus and self.focus:onPaste(ev[2]) then return end

  elseif name == "mouse_click" then
    local button, px, py = ev[2], ev[3], ev[4]
    local hit = self:popoverHit(px, py)
    if hit ~= nil then
      if hit == false then
        self:closeMenu()
      else
        local item = self.popover.items[hit]
        self:closeMenu()
        if item and item.action and not item.disabled and not item.separator then
          item.action()
        end
      end
      return
    end

    local scope = self.modal or self.root
    if self.modal and not self.modal:contains(px, py) then return end
    local widget = scope:pick(px, py)
    if widget then
      local focusTarget = widget
      while focusTarget and not focusTarget.focusable do focusTarget = focusTarget.parent end
      if focusTarget then self:setFocus(focusTarget) end
      self.captured = self:bubbleMouse(widget, "mouse_click", button, px, py)
    end

  elseif name == "mouse_drag" then
    if self.captured then
      self.captured:onMouse("mouse_drag", ev[2], ev[3], ev[4])
    end

  elseif name == "mouse_up" then
    if self.captured then
      self.captured:onMouse("mouse_up", ev[2], ev[3], ev[4])
      self.captured = nil
    end

  elseif name == "mouse_scroll" then
    local scope = self.modal or self.root
    local widget = scope:pick(ev[3], ev[4])
    if widget then self:bubbleMouse(widget, "mouse_scroll", ev[2], ev[3], ev[4]) end

  elseif name == "timer" then
    local fn = self.timers[ev[2]]
    if fn then
      self.timers[ev[2]] = nil
      fn()
    end
    if self.toast and os.clock() >= self.toast.until_ then
      self.toast = nil
      self:queueDraw()
    end

  elseif name == "term_resize" or name == "aurora_resize" then
    self.surface = aurora.surface()
    self:queueLayout()

  elseif name == "terminate" then
    self:emitClose()

  else
    self:emitUnhandled(table.unpack(ev, 1, ev.n or #ev))
  end
end

function App:emitUnhandled(...)
  if self.onEvent then self.onEvent(...) end
end

function App:emitClose()
  if self.onClose then
    if self.onClose() == false then return end
  end
  self.running = false
end

-------------------------------------------------------------------- run -----

function App:run()
  self:layout()
  self:render()
  while self.running do
    local ev = table.pack(os.pullEvent())
    local ok, err = pcall(self.dispatch, self, ev)
    if not ok then
      local log = arequire("kernel.log")
      log.error(self.proc.name, tostring(err))
      self:notify("Error: " .. tostring(err):sub(1, 40), "error")
    end
    if self.layoutDirty then self:layout() end
    if self.drawDirty then self:render() end
  end
end

--------------------------------------------------------------- utilities ----

--- Shorthand for a vertical page with standard padding.
function App.page(props)
  props = props or {}
  local box = base.Box({
    orientation = props.orientation or "vertical",
    spacing = props.spacing or 1,
    padding = props.padding or 1,
  })
  box.hexpand, box.vexpand = true, true
  return box
end

--- A GNOME "preferences group": a titled card of rows.
function App.group(title, rows)
  local box = base.Box({ orientation = "vertical", spacing = 0 })
  box.hexpand = true
  if title then
    local label = W.Label({ text = title, dim = true })
    label.hexpand = true
    label.marginBottom = 0
    box:add(label)
  end
  local list = W.ListBox({ rows = rows or {}, card = true })
  list.hexpand = true
  box:add(list)
  box.list = list
  return box
end

App.Widget = base.Widget
App.Box = base.Box
App.Fixed = base.Fixed
App.Stack = base.Stack
App.Scrolled = base.Scrolled
App.widgets = W

return App
