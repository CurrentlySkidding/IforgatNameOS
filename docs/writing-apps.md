# Writing Aurora apps

An Aurora app is a folder with a `manifest.lua` and a `main.lua`. Put it in
`/home/apps/<id>/` and it shows up in the app grid.

```
/home/apps/hello/
  manifest.lua
  main.lua
```

## The manifest

`manifest.lua` is a Lua chunk that returns a table, so you can use the `colours`
API in it.

```lua
return {
  id       = "hello",           -- must match the folder name
  name     = "Hello",           -- shown in the grid, the dash and the header
  summary  = "My first app",    -- shown in search and Settings
  keywords = "greeting demo",   -- extra search terms
  category = "Other",           -- groups the app grid
  main     = "main.lua",        -- entry point (default: main.lua)
  singleton = false,            -- true: focus the running copy instead of a new one
  char     = "\254",            -- one character, drawn in the window header
  handles  = { "text", "code" },-- file kinds this app can open
  window   = { w = 30, h = 10, resizable = true },
  icon = {
    colour      = colours.green,  -- the squircle
    glyphColour = colours.white,
    accent      = colours.lime,   -- used by "+" pixels in art
    glyph       = "H",            -- 5x7 bitmap text, OR:
    art = {                       -- pixel art, "#" = glyph, "+" = accent
      "..####..",
      ".#....#.",
      "..####..",
    },
  },
}
```

File kinds are `text`, `code`, `doc`, `sheet`, `slides`, `image`, `folder`,
`binary`, or `*` for anything.

## The entry point

`main.lua` runs as its own process. Command-line arguments — usually the path
of a file to open — arrive as varargs.

```lua
local args = { ... }
local App  = arequire("ui.app")
local base = arequire("ui.widget")
local W    = arequire("ui.widgets")

local app = App({ title = "Hello" })
-- ... build a widget tree ...
app:setRoot(root)
app:run()
```

`arequire(name)` loads an Aurora module. Modules are cached system-wide, so two
apps share one copy.

Inside a process the global `aurora` is your handle on the window:

| Call | Does |
| --- | --- |
| `aurora.setTitle(text)` | change the header bar title |
| `aurora.setIcon({char=, colour=})` | change the header icon |
| `aurora.surface()` | the window's character buffer |
| `aurora.damage()` | mark the window for repaint |
| `aurora.post(pid, ...)` | send an event to another process |
| `aurora.spawn(opts)` | start a process yourself |
| `aurora.exit()` | quit |

## Layout

Widgets measure, then get allocated a rectangle, then draw — the GTK model.

- **`base.Box`** — `orientation` (`"vertical"` / `"horizontal"`), `spacing`,
  `padding`, `homogeneous`. Children with `hexpand` / `vexpand` soak up spare
  space.
- **`base.Scrolled`** — one child, a scrollbar, and real clipping.
- **`base.Stack`** — one child visible at a time; `addPage(name, widget)` and
  `setPage(name)`.
- **`base.Fixed`** — absolute positions via `put(child, x, y, w, h)`.

A widget that should fill its parent needs `hexpand` / `vexpand` set. This is
the single most common reason a widget "disappears" — without `hexpand` a
horizontal box only gets as wide as its natural size.

```lua
local box = base.Box({ orientation = "vertical", spacing = 1, padding = 1 })
box.hexpand, box.vexpand = true, true
```

## Controls

```lua
W.Label({ text = "Hi", align = "start|center|end", wrap = false, dim = false })
W.Button({ label = "Go", style = "normal|suggested|destructive|flat" })
W.IconButton({ icon = "\4", width = 3 })
W.Entry({ text = "", placeholder = "Search", icon = "\4", password = false })
W.Switch({ active = false })
W.CheckBox({ label = "Enabled", active = false })
W.ListBox({ rows = { { title = "One", subtitle = "…", icon = { char = "\4",
                       colour = colours.blue }, trailing = "2 KB" } } })
W.IconGrid({ items = { { label = "App", icon = { colour = colours.blue } } } })
W.Chart({ series = { 3, 7, 2 }, kind = "bar|line" })
W.ProgressBar({ value = 0.5 })
W.Tabs({ tabs = { { label = "One", id = "one" } } })
W.Dropdown({ options = { { label = "A", value = 1 } } })
W.Separator({ orientation = "horizontal|vertical" })
W.StatusPage({ title = "Nothing here", description = "…", icon = { … } })
W.Toolbar({ spacing = 0 })
arequire("ui.textview")({ wrap = true, showNumbers = true, highlighter = fn })
```

Signals are plain callbacks:

```lua
button:connect("clicked", function(self) … end)
entry:connect("changed", function(self, text) … end)
entry:connect("activate", function(self, text) … end)
list:connect("select",   function(self, index, row) … end)
list:connect("activate", function(self, index, row) … end)   -- double click / Enter
switch:connect("changed", function(self, active) … end)
tabs:connect("changed",  function(self, index, tab) … end)
view:connect("changed",  function(self) … end)               -- TextView edits
view:connect("moved",    function(self, line, col) … end)
```

## Desktop furniture

```lua
app:notify("Saved", "success")          -- toast: info | success | error

app:dialog({
  title = "Delete?",
  body = "This cannot be undone.",      -- string or a widget
  actions = {
    { label = "Cancel" },
    { label = "Delete", style = "destructive", onClick = fn },
  },
})

app:prompt({ title = "Rename", text = "old name", onAccept = function(text) … end })
app:confirm({ title = "Sure?", message = "…", onAccept = fn, destructive = true })

app:menu(x, y, {
  { label = "Open", icon = "\4", accel = "^O", action = fn },
  { separator = true },
  { label = "Delete", destructive = true, action = fn, disabled = false },
}, 24)

app:accel("ctrl+s", save)               -- CC key names: ctrl+one, not ctrl+1
app:after(2, fn)                        -- run once, in 2 seconds
app:every(5, fn)                        -- run every 5 seconds
```

Bare-key accelerators are suppressed while the caret is in a text field, and
all accelerators are suppressed while a dialog is open, so `Delete` as a
shortcut will not eat characters.

## Lifecycle

```lua
app.onClose = function()
  if not dirty then return true end     -- true (or nothing): allow the close
  app:confirm({ … onAccept = function() save() app:quit() end,
                    onCancel = app.quit })
  return false                          -- false: veto it, we'll quit ourselves
end

app.onEvent = function(name, ...)
  if name == "aurora_open" then         -- another process asked us to open a file
    local path = select(1, ...)
  elseif name == "peripheral" then      -- something was plugged in
  elseif name == "monitor_touch" then   -- somebody touched a monitor we own
  end
end
```

`aurora_resize` and `term_resize` are handled for you; the app re-lays-out.

## Files, printing and monitors

```lua
local vfs     = arequire("kernel.vfs")
local apps    = arequire("svc.apps")
local printer = arequire("svc.printer")
local display = arequire("svc.display")
local devices = arequire("kernel.devices")

vfs.list("/home")                       -- entries with name, path, isDir, size, type
vfs.trash(path)                         -- move to trash (restorable)
vfs.copyToClipboard({ path }, "copy")   -- system-wide clipboard
apps.openFile(path)                     -- open in whichever app claims the type

printer.submit({ title = "Report", content = "line\nline" })
printer.available()                     -- attached printers with ink/paper

local d = display.claim("monitor_1", aurora.proc)   -- take a monitor over
d.surface:write(1, 1, "Hello", colours.white, colours.black)
d:invalidate(); d:present()
display.release("monitor_1")

devices.byClass("display")              -- display | printer | network | audio | storage
```

## Drawing your own widget

Subclass `base.Widget` when the stock controls do not fit — the spreadsheet
grid and the slide preview are both custom widgets.

```lua
local util = arequire("lib.util")
local base = arequire("ui.widget")
local theme = arequire("gfx.theme")

local Gauge = util.class(base.Widget)

function Gauge:init(props)
  base.Widget.init(self, props or {})
  self.value = 0
  self.focusable = true
end

function Gauge:measure() return 12, 3 end     -- natural width, height

function Gauge:draw(s)                        -- s is the window Surface
  s:fill(self.x, self.y, self.w, self.h, " ", theme.c.text, theme.c.card)
  s:pill(self.x, self.y + 1, self.w, theme.c.accent)
end

function Gauge:onMouse(kind, button, px, py)  -- absolute coordinates
  if kind == "mouse_click" then
    self.value = (px - self.x) / self.w
    self:invalidate()
    return true                               -- handled; stop bubbling
  end
  return kind == "mouse_up"
end

function Gauge:onKey(key) return false end
```

Useful `Surface` calls: `write`, `blit`, `fill`, `frame`, `writeCentered`,
`pill(x, y, w, colour)`, `roundRect`, `roundCorner`, `pushClip` / `popClip`,
`draw(otherSurface, x, y)` and `scrim`.

Always colour from `theme.c.*` rather than naming a `colours.*` value, so your
app follows light mode and the user's accent.

## Publishing

The App Builder's **Export installer** writes a single `.lua` file that
recreates your app anywhere:

```bash
wget run https://raw.githubusercontent.com/you/your-repo/main/hello-install.lua
```

Or commit the folder to a repo and tell people to drop it in `/home/apps/`.
