--[[ aurora.ui.textview -----------------------------------------------------
     A real multi-line text editor widget: selection, clipboard, undo, line
     numbers, soft wrap and pluggable syntax highlighting.  Text Editor,
     Writer and the App Builder's code view all sit on top of this.
----------------------------------------------------------------------------]]

local util    = arequire("lib.util")
local theme   = arequire("gfx.theme")
local base    = arequire("ui.widget")
local Surface = arequire("gfx.surface")

local Widget = base.Widget
local TextView = util.class(Widget)

function TextView:init(props)
  props = props or {}
  Widget.init(self, props)
  self.lines = { "" }
  self.line, self.col = 1, 1
  self.scrollY, self.scrollX = 0, 0
  self.sel = nil                        -- {line=, col=} selection anchor
  self.focusable = true
  self.readOnly = props.readOnly or false
  self.showNumbers = props.showNumbers or false
  self.wrap = props.wrap or false
  self.tabWidth = props.tabWidth or 2
  self.highlighter = props.highlighter  -- fn(text) -> blit fg string
  self.background = props.background
  self.undoStack, self.redoStack = {}, {}
  self.modified = false
  self.hexpand, self.vexpand = true, true
  self.textInput = true
  if props.text then self:setText(props.text) end
  if props.onChange then self:connect("changed", props.onChange) end
end

------------------------------------------------------------------ content ---

function TextView:setText(text)
  self.lines = {}
  for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    self.lines[#self.lines + 1] = (line:gsub("\r", ""))
  end
  if #self.lines == 0 then self.lines = { "" } end
  -- a trailing newline produces one empty line we do not want to duplicate
  if #self.lines > 1 and self.lines[#self.lines] == "" then table.remove(self.lines) end
  self.line, self.col = 1, 1
  self.scrollY, self.scrollX = 0, 0
  self.sel = nil
  self.undoStack, self.redoStack = {}, {}
  self.modified = false
  self:invalidate()
end

function TextView:getText()
  return table.concat(self.lines, "\n")
end

function TextView:lineCount() return #self.lines end

function TextView:currentLine() return self.lines[self.line] or "" end

-------------------------------------------------------------------- undo ----

function TextView:pushUndo()
  local snapshot = {
    lines = { table.unpack(self.lines) },
    line = self.line, col = self.col,
  }
  self.undoStack[#self.undoStack + 1] = snapshot
  if #self.undoStack > 60 then table.remove(self.undoStack, 1) end
  self.redoStack = {}
end

function TextView:undo()
  local snapshot = table.remove(self.undoStack)
  if not snapshot then return false end
  self.redoStack[#self.redoStack + 1] = {
    lines = { table.unpack(self.lines) }, line = self.line, col = self.col,
  }
  self.lines = snapshot.lines
  self.line, self.col = snapshot.line, snapshot.col
  self.sel = nil
  self:changed()
  return true
end

function TextView:redo()
  local snapshot = table.remove(self.redoStack)
  if not snapshot then return false end
  self.undoStack[#self.undoStack + 1] = {
    lines = { table.unpack(self.lines) }, line = self.line, col = self.col,
  }
  self.lines = snapshot.lines
  self.line, self.col = snapshot.line, snapshot.col
  self.sel = nil
  self:changed()
  return true
end

function TextView:changed()
  self.modified = true
  self:emit("changed")
  self:invalidate()
end

--------------------------------------------------------------- selection ----

function TextView:hasSelection()
  return self.sel ~= nil and not (self.sel.line == self.line and self.sel.col == self.col)
end

function TextView:selectionRange()
  if not self:hasSelection() then return nil end
  local a, b = self.sel, { line = self.line, col = self.col }
  if a.line > b.line or (a.line == b.line and a.col > b.col) then a, b = b, a end
  return a, b
end

function TextView:selectAll()
  self.sel = { line = 1, col = 1 }
  self.line = #self.lines
  self.col = #self.lines[#self.lines] + 1
  self:invalidate()
end

function TextView:selectedText()
  local a, b = self:selectionRange()
  if not a then return "" end
  if a.line == b.line then
    return self.lines[a.line]:sub(a.col, b.col - 1)
  end
  local parts = { self.lines[a.line]:sub(a.col) }
  for i = a.line + 1, b.line - 1 do parts[#parts + 1] = self.lines[i] end
  parts[#parts + 1] = self.lines[b.line]:sub(1, b.col - 1)
  return table.concat(parts, "\n")
end

function TextView:deleteSelection()
  local a, b = self:selectionRange()
  if not a then return false end
  self:pushUndo()
  if a.line == b.line then
    local line = self.lines[a.line]
    self.lines[a.line] = line:sub(1, a.col - 1) .. line:sub(b.col)
  else
    local head = self.lines[a.line]:sub(1, a.col - 1)
    local tail = self.lines[b.line]:sub(b.col)
    for _ = a.line + 1, b.line do table.remove(self.lines, a.line + 1) end
    self.lines[a.line] = head .. tail
  end
  self.line, self.col = a.line, a.col
  self.sel = nil
  self:changed()
  return true
end

-------------------------------------------------------------- mutations -----

function TextView:insert(text)
  if self.readOnly then return end
  if self:hasSelection() then self:deleteSelection() else self:pushUndo() end
  local pieces = util.splitAll(tostring(text), "\n")
  local current = self.lines[self.line]
  local head = current:sub(1, self.col - 1)
  local tail = current:sub(self.col)
  if #pieces == 1 then
    self.lines[self.line] = head .. pieces[1] .. tail
    self.col = self.col + #pieces[1]
  else
    self.lines[self.line] = head .. pieces[1]
    for i = 2, #pieces do
      table.insert(self.lines, self.line + i - 1, pieces[i])
    end
    self.line = self.line + #pieces - 1
    self.col = #pieces[#pieces] + 1
    self.lines[self.line] = self.lines[self.line] .. tail
  end
  self.sel = nil
  self:changed()
end

function TextView:newline()
  if self.readOnly then return end
  if self:hasSelection() then self:deleteSelection() else self:pushUndo() end
  local current = self.lines[self.line]
  local head = current:sub(1, self.col - 1)
  local tail = current:sub(self.col)
  -- keep the indentation of the line we are leaving
  local indent = head:match("^(%s*)") or ""
  self.lines[self.line] = head
  table.insert(self.lines, self.line + 1, indent .. tail)
  self.line = self.line + 1
  self.col = #indent + 1
  self:changed()
end

function TextView:backspace()
  if self.readOnly then return end
  if self:hasSelection() then self:deleteSelection() return end
  if self.col > 1 then
    self:pushUndo()
    local current = self.lines[self.line]
    self.lines[self.line] = current:sub(1, self.col - 2) .. current:sub(self.col)
    self.col = self.col - 1
    self:changed()
  elseif self.line > 1 then
    self:pushUndo()
    local previous = self.lines[self.line - 1]
    self.col = #previous + 1
    self.lines[self.line - 1] = previous .. self.lines[self.line]
    table.remove(self.lines, self.line)
    self.line = self.line - 1
    self:changed()
  end
end

function TextView:deleteForward()
  if self.readOnly then return end
  if self:hasSelection() then self:deleteSelection() return end
  local current = self.lines[self.line]
  if self.col <= #current then
    self:pushUndo()
    self.lines[self.line] = current:sub(1, self.col - 1) .. current:sub(self.col + 1)
    self:changed()
  elseif self.line < #self.lines then
    self:pushUndo()
    self.lines[self.line] = current .. self.lines[self.line + 1]
    table.remove(self.lines, self.line + 1)
    self:changed()
  end
end

function TextView:deleteLine()
  if self.readOnly then return end
  self:pushUndo()
  table.remove(self.lines, self.line)
  if #self.lines == 0 then self.lines = { "" } end
  self.line = math.min(self.line, #self.lines)
  self.col = 1
  self:changed()
end

--------------------------------------------------------------- movement -----

function TextView:clampCursor()
  self.line = util.clamp(self.line, 1, #self.lines)
  self.col = util.clamp(self.col, 1, #self.lines[self.line] + 1)
end

function TextView:moveTo(line, col, extend)
  if extend then
    if not self.sel then self.sel = { line = self.line, col = self.col } end
  else
    self.sel = nil
  end
  self.line, self.col = line, col
  self:clampCursor()
  self:emit("moved", self.line, self.col)
  self:invalidate()
end

function TextView:gutterWidth()
  if not self.showNumbers then return 0 end
  return #tostring(#self.lines) + 1
end

function TextView:viewWidth()
  return math.max(1, self.w - self:gutterWidth() - 1)
end

--- Rows a line occupies in soft-wrap mode.
function TextView:wrapLine(text)
  if not self.wrap then return { text } end
  local width = self:viewWidth()
  if #text == 0 then return { "" } end
  return util.wrap(text, width)
end

function TextView:ensureVisible()
  -- Apps often load a document and jump to a line before the first layout
  -- pass, when the widget still has no size.  Scrolling against a zero-sized
  -- viewport would leave a nonsense offset behind, so wait for a real one.
  if self.w <= 0 or self.h <= 0 then return end

  local viewH = self.h
  if self.wrap then
    -- count display rows up to the cursor
    local row = 0
    for i = 1, self.line - 1 do row = row + #self:wrapLine(self.lines[i]) end
    local sub = self:wrapLine(self:currentLine())
    local remaining = self.col - 1
    for i = 1, #sub do
      if remaining <= #sub[i] then break end
      remaining = remaining - #sub[i] - 1
      row = row + 1
    end
    if row < self.scrollY then self.scrollY = row end
    if row >= self.scrollY + viewH then self.scrollY = row - viewH + 1 end
  else
    if self.line - 1 < self.scrollY then self.scrollY = self.line - 1 end
    if self.line - 1 >= self.scrollY + viewH then self.scrollY = self.line - viewH end
    local viewW = self:viewWidth()
    if self.col - 1 < self.scrollX then self.scrollX = math.max(0, self.col - 1) end
    if self.col - 1 >= self.scrollX + viewW then self.scrollX = self.col - viewW end
  end
  if self.scrollY < 0 then self.scrollY = 0 end
  if self.scrollX < 0 then self.scrollX = 0 end
end

function TextView:gotoLine(n)
  self:moveTo(util.clamp(n, 1, #self.lines), 1, false)
  self:ensureVisible()
end

-------------------------------------------------------------------- find ----

--- Search forward from the cursor, wrapping once.  Returns line, col.
function TextView:find(needle, fromLine, fromCol, caseSensitive)
  if needle == "" then return nil end
  local hay = caseSensitive and nil or needle:lower()
  local startLine = fromLine or self.line
  local startCol = fromCol or (self.col + 1)
  for pass = 1, 2 do
    local first = pass == 1 and startLine or 1
    local last = pass == 1 and #self.lines or startLine
    for i = first, last do
      local text = caseSensitive and self.lines[i] or self.lines[i]:lower()
      local from = (i == first and pass == 1) and startCol or 1
      local a = text:find(caseSensitive and needle or hay, from, true)
      if a then return i, a end
    end
  end
  return nil
end

function TextView:replaceAll(needle, replacement, caseSensitive)
  if needle == "" then return 0 end
  self:pushUndo()
  local count = 0
  for i, text in ipairs(self.lines) do
    local out, n
    if caseSensitive then
      out, n = text:gsub(needle:gsub("(%W)", "%%%1"), (replacement:gsub("%%", "%%%%")))
    else
      out, n = text, 0
      local lower = text:lower()
      local needleLower = needle:lower()
      local cursor, pieces = 1, {}
      while true do
        local a = lower:find(needleLower, cursor, true)
        if not a then break end
        pieces[#pieces + 1] = text:sub(cursor, a - 1)
        pieces[#pieces + 1] = replacement
        cursor = a + #needle
        n = n + 1
      end
      pieces[#pieces + 1] = text:sub(cursor)
      out = table.concat(pieces)
    end
    self.lines[i] = out
    count = count + n
  end
  if count > 0 then self:changed() end
  return count
end

-------------------------------------------------------------------- draw ----

local function selectionOnLine(a, b, index, length)
  if not a then return nil end
  if index < a.line or index > b.line then return nil end
  local from = (index == a.line) and a.col or 1
  local to = (index == b.line) and b.col - 1 or length
  if to < from then
    if index == b.line and b.col == 1 then return nil end
    to = from
  end
  return from, to
end

function TextView:draw(s)
  local c = theme.c
  local bg = self.background or c.view
  s:fill(self.x, self.y, self.w, self.h, " ", c.text, bg)

  local gutter = self:gutterWidth()
  local textX = self.x + gutter + (gutter > 0 and 1 or 0)
  local viewW = self:viewWidth()
  local a, b = self:selectionRange()

  s:pushClip(self.x, self.y, self.w, self.h)

  if self.wrap then
    local row = -self.scrollY
    for i = 1, #self.lines do
      local segments = self:wrapLine(self.lines[i])
      for seg = 1, #segments do
        if row >= 0 and row < self.h then
          local y = self.y + row
          if gutter > 0 and seg == 1 then
            s:write(self.x, y, util.padLeft(tostring(i), gutter - 1),
                    i == self.line and c.text or c.dim, bg)
          end
          s:write(textX, y, segments[seg], c.text, bg)
        end
        row = row + 1
      end
      if row >= self.h + self.scrollY then break end
    end
  else
    for row = 0, self.h - 1 do
      local index = self.scrollY + row + 1
      local y = self.y + row
      if index <= #self.lines then
        local text = self.lines[index]
        if gutter > 0 then
          s:write(self.x, y, util.padLeft(tostring(index), gutter - 1),
                  index == self.line and c.accent or c.dim, bg)
        end
        local visible = text:sub(self.scrollX + 1, self.scrollX + viewW)
        local fgRun
        if self.highlighter then
          local full = self.highlighter(text)
          fgRun = full:sub(self.scrollX + 1, self.scrollX + viewW)
          if #fgRun < #visible then
            fgRun = fgRun .. string.rep(Surface.blitChar(c.text), #visible - #fgRun)
          end
        end
        if not fgRun or #fgRun ~= #visible then
          fgRun = string.rep(Surface.blitChar(c.text), #visible)
        end
        local bgRun = string.rep(Surface.blitChar(bg), #visible)

        -- paint the selection over the highlight run
        local from, to = selectionOnLine(a, b, index, #text)
        if from then
          local selFrom = math.max(1, from - self.scrollX)
          local selTo = math.min(#visible, to - self.scrollX)
          if selTo >= selFrom then
            bgRun = bgRun:sub(1, selFrom - 1)
                    .. string.rep(Surface.blitChar(c.selection), selTo - selFrom + 1)
                    .. bgRun:sub(selTo + 1)
            fgRun = fgRun:sub(1, selFrom - 1)
                    .. string.rep(Surface.blitChar(c.onAccent), selTo - selFrom + 1)
                    .. fgRun:sub(selTo + 1)
          end
        end
        if #visible > 0 then
          s:blit(textX, y, visible, fgRun, bgRun)
        end
      elseif gutter > 0 then
        s:write(self.x, y, util.padLeft("\126", gutter - 1), c.separator, bg)
      end
    end
  end

  s:popClip()

  if self.focused then
    local cy, cx
    if self.wrap then
      local row = -self.scrollY
      for i = 1, self.line - 1 do row = row + #self:wrapLine(self.lines[i]) end
      local segments = self:wrapLine(self:currentLine())
      local remaining = self.col - 1
      local segIndex = 1
      while segIndex < #segments and remaining > #segments[segIndex] do
        remaining = remaining - #segments[segIndex] - 1
        row = row + 1
        segIndex = segIndex + 1
      end
      cy = self.y + row
      cx = textX + remaining
    else
      cy = self.y + (self.line - 1 - self.scrollY)
      cx = textX + (self.col - 1 - self.scrollX)
    end
    if cy >= self.y and cy < self.y + self.h then
      self.caret = { x = cx, y = cy, colour = c.accent }
    else
      self.caret = nil
    end
  else
    self.caret = nil
  end
end

------------------------------------------------------------------- input ----

function TextView:onChar(ch)
  if self.readOnly then return false end
  self:insert(ch)
  self:ensureVisible()
  return true
end

function TextView:onPaste(text)
  if self.readOnly then return false end
  self:insert(text)
  self:ensureVisible()
  return true
end

function TextView:onKey(key, held)
  local extend = self.shiftHeld
  local handled = true

  if key == keys.up then
    self:moveTo(self.line - 1, self.col, extend)
  elseif key == keys.down then
    self:moveTo(self.line + 1, self.col, extend)
  elseif key == keys.left then
    if self.col > 1 then
      self:moveTo(self.line, self.col - 1, extend)
    elseif self.line > 1 then
      self:moveTo(self.line - 1, #self.lines[self.line - 1] + 1, extend)
    end
  elseif key == keys.right then
    if self.col <= #self:currentLine() then
      self:moveTo(self.line, self.col + 1, extend)
    elseif self.line < #self.lines then
      self:moveTo(self.line + 1, 1, extend)
    end
  elseif key == keys.home then
    self:moveTo(self.line, 1, extend)
  elseif key == keys["end"] then
    self:moveTo(self.line, #self:currentLine() + 1, extend)
  elseif key == keys.pageUp then
    self:moveTo(self.line - self.h, self.col, extend)
  elseif key == keys.pageDown then
    self:moveTo(self.line + self.h, self.col, extend)
  elseif key == keys.enter or key == keys.numPadEnter then
    self:newline()
  elseif key == keys.backspace then
    self:backspace()
  elseif key == keys.delete then
    self:deleteForward()
  elseif key == keys.tab then
    self:insert(string.rep(" ", self.tabWidth))
  else
    handled = false
  end

  if handled then self:ensureVisible() end
  return handled
end

function TextView:onMouse(kind, button, px, py)
  local gutter = self:gutterWidth()
  local textX = self.x + gutter + (gutter > 0 and 1 or 0)

  if kind == "mouse_scroll" then
    self.scrollY = math.max(0, self.scrollY + button * 2)
    local maxScroll = math.max(0, self:displayRows() - self.h)
    self.scrollY = math.min(self.scrollY, maxScroll)
    self:invalidate()
    return true
  end

  if kind == "mouse_click" or kind == "mouse_drag" then
    local row = py - self.y
    local line, col
    if self.wrap then
      local target = self.scrollY + row
      local acc = 0
      line, col = #self.lines, #self.lines[#self.lines] + 1
      for i = 1, #self.lines do
        local segments = self:wrapLine(self.lines[i])
        if target < acc + #segments then
          local segIndex = target - acc + 1
          local offset = 0
          for k = 1, segIndex - 1 do offset = offset + #segments[k] + 1 end
          line = i
          col = math.min(#self.lines[i] + 1, offset + (px - textX) + 1)
          break
        end
        acc = acc + #segments
      end
    else
      line = util.clamp(self.scrollY + row + 1, 1, #self.lines)
      col = util.clamp(px - textX + 1 + self.scrollX, 1, #self.lines[line] + 1)
    end
    if kind == "mouse_click" then
      self:moveTo(line, col, false)
      self.dragging = true
    else
      if not self.sel then self.sel = { line = self.line, col = self.col } end
      self:moveTo(line, col, true)
    end
    self:ensureVisible()
    return true
  elseif kind == "mouse_up" then
    self.dragging = false
    return true
  end
  return false
end

function TextView:displayRows()
  if not self.wrap then return #self.lines end
  local rows = 0
  for _, text in ipairs(self.lines) do rows = rows + #self:wrapLine(text) end
  return rows
end

function TextView:measure()
  return math.max(self.widthRequest or 0, 20), math.max(self.heightRequest or 0, 3)
end

function TextView:allocate(x, y, w, h)
  local first = self.w <= 0 or self.h <= 0
  local resized = (w ~= self.w or h ~= self.h)
  Widget.allocate(self, x, y, w, h)
  if (first or resized) and w > 0 and h > 0 then
    -- now that there is a real viewport, put the caret back on screen
    self.scrollY = math.max(0, math.min(self.scrollY, math.max(0, self:displayRows() - h)))
    self:ensureVisible()
  end
end

return TextView
