# Aurora OS

A desktop operating system for **CC: Tweaked** computers in Minecraft.

Aurora boots straight from power-on, replaces the CraftOS shell with a
GNOME-style desktop, and brings its own kernel, window manager, compositor,
widget toolkit and application suite — a file manager, a terminal, a code
editor, a word processor, a spreadsheet, a presentation app, an app builder,
settings and a system monitor. It drives monitors and printers as real
peripherals, so a wall of monitors becomes a projector and a printer prints
your documents.

It runs on a 51x19 character grid in 16 colours. Aurora redefines every one of
those 16 palette slots to an Adwaita-derived ramp and uses CC's 2x3 sub-pixel
glyphs for icons, rounded window corners and pill-shaped buttons, so it reads
like a real desktop rather than a text menu.

```
 ● Activities        14:32  Mon 03 Feb                    ⌨ 🖨 ▣  ⏻
┌──────────────────────── Files ──────────────────── ─ □ ✕ ┐
│ ◄  ▲  /home                                        ▣  ⋮  │
│ ⌂ Home         │ ▣ Documents                              │
│ ▣ Documents    │ ▣ Sheets                                 │
│ ▣ Sheets       │ ▣ Decks                                  │
│ ▣ Decks        │ ▣ Scripts                                │
│ ⧉ Trash        │ ▶ notes.txt                     1.2 KB   │
│ 5 folders, 1 file  ·  412.0 KB free                       │
└───────────────────────────────────────────────────────────┘
```

---

## Install

On any CC: Tweaked computer with the HTTP API enabled:

```
wget run https://raw.githubusercontent.com/CurrentlySkidding/IforgatNameOS/main/install.lua
```

The installer downloads everything into a staging folder first, so a dropped
connection can never leave you with a half-installed system that won't boot.
When it's done it offers to reboot.

Other modes:

| Command | What it does |
| --- | --- |
| `install --update` | reinstall the system, keep `/home` and your settings |
| `install --uninstall` | remove Aurora, keep `/home` |
| `install owner/fork [branch]` | install from a fork |

**No HTTP?** Copy the repository onto a floppy disk, then from the CraftOS
shell: `cp /disk/aurora /aurora` and `cp /disk/startup.lua /startup.lua`.

**Requirements:** an *advanced* computer (gold) for colour and mouse input.
Aurora runs on a basic computer but you lose the palette and the pointer.

---

## Using it

### The shell

| Key | Action |
| --- | --- |
| `F1` | Activities overview — windows, search, dash |
| `F2` | All applications grid |
| `Alt`+`Tab` | Switch windows |
| `F11` | Maximise / restore the focused window |
| `Alt`+`F4` | Close the focused window |
| `Ctrl`+`F5` | Force a full repaint |

Start typing in the overview to search apps *and* your files; press `Enter` to
open the first hit. Drag a window by its header bar; drop it against the top
edge to maximise. Drag the bottom-right corner to resize. Click the power icon
at the right of the top panel for lock, restart, shut down, or drop back to
CraftOS.

### The apps

**Files** — places sidebar, list or icon view, copy/cut/paste, rename, trash
with restore, properties, and print. Opens each file in whichever app claims
its type.

**Terminal** — a real, unmodified CraftOS shell running inside a window. `edit`,
`lua`, `paint`, `worm`, your own programs: all of it works, because the kernel
redirects the global `term` API into the window's buffer.

**Text Editor** — Lua and Markdown syntax highlighting, find and replace, undo,
go-to-line, line numbers, soft wrap, and "run this file in a terminal".

**Writer** — paragraph styles (title, heading, bullet, quote), live word count,
Markdown on disk so other tools can read it, and printing with real pagination
and page titles.

**Sheets** — a spreadsheet with a genuine formula engine: `=SUM(A1:A9)`,
`=AVERAGE`, `=IF(A1>10,"over","under")`, `=A1*B2+1`, cross-references, ranges,
and cycle detection that reports `#CYCLE` instead of hanging. Import and export
CSV, chart any range, resize columns, print.

**Slides** — build a deck, preview it live, then present it **on a monitor**.
Aurora hands the monitor over to the app, so a monitor wall behind you becomes
the projector while you keep the speaker view on the computer.

**App Builder** — lay out widgets on a canvas, attach Lua to their events,
press Run to spawn it as a live window, then either publish it into your app
grid or export a single-file installer you can push to GitHub.

**Settings** — light/dark/high-contrast themes, nine accent colours, five
wallpapers, monitor roles and text scale, printers and their queue, modems,
app management, and system info.

**System Monitor** — processes (with end-process), attached devices, storage
and the live kernel log.

### Peripherals

| Peripheral | What Aurora does with it |
| --- | --- |
| Monitor | becomes a display: mirror the desktop, run as an extended workspace, be claimed by one app (Slides), or switch off. Touches become clicks. |
| Printer | becomes a print target. Documents are paginated to the printer's page size, titled, and spooled by a background service. |
| Modem | shows up in Settings → Network; open and close it there. |
| Disk drive | mounts as a place in the Files sidebar. |

Everything hot-plugs — attach a monitor while the desktop is running and it
appears in Settings within a tick.

---

## Writing your own apps

An app is a folder under `/home/apps/<id>/` with two files.

`manifest.lua`:

```lua
return {
  id = "hello",
  name = "Hello",
  summary = "My first Aurora app",
  category = "Other",
  window = { w = 30, h = 10 },
  char = "\254",
  icon = { colour = colours.green, glyph = "H" },
}
```

`main.lua`:

```lua
local App  = arequire("ui.app")
local base = arequire("ui.widget")
local W    = arequire("ui.widgets")

local app = App({ title = "Hello" })

local label = W.Label({ text = "Click the button", align = "center" })
label.hexpand = true

local button = W.Button({ label = "Click me", style = "suggested" })
button.hexpand = true

local box = base.Box({ orientation = "vertical", spacing = 1, padding = 1 })
box.hexpand, box.vexpand = true, true
box:add(label)
box:add(button)

button:connect("clicked", function()
  label:setText("Hello from Aurora!")
end)

app:setRoot(box)
app:run()
```

Drop the folder in `/home/apps/` and it appears in the app grid on the next
scan (Settings → Apps, or a reboot). Or build it visually in the App Builder
and hit Publish.

The toolkit gives you `Label`, `Button`, `IconButton`, `Entry`, `TextView`,
`Switch`, `CheckBox`, `ListBox`, `IconGrid`, `Chart`, `ProgressBar`, `Spinner`,
`Separator`, `Tabs`, `Dropdown`, `StatusPage` and `Toolbar`, plus `Box`,
`Grid`, `Fixed`, `Stack` and `Scrolled` containers — and `app:dialog`,
`app:prompt`, `app:confirm`, `app:menu`, `app:notify` and `app:accel` for the
usual desktop furniture.

See [docs/writing-apps.md](docs/writing-apps.md) for the full reference and
[docs/architecture.md](docs/architecture.md) for how the kernel works.

---

## Development

The repository ships a small CraftOS emulator so you can boot and drive Aurora
without opening Minecraft.

```bash
pip install lupa

python tools/check.py                      # syntax-check every Lua file
python tools/test_all.py                   # boot + integration tests
python tools/boot_test.py                  # render the desktop
python tools/boot_test.py --launch sheets  # render one app
python tools/boot_test.py --script "f1,click:5:16"
python tools/debug.py "f1" --screen        # kernel log + process table
python tools/make_manifest.py              # regenerate files.txt
```

`boot_test.py` prints the emulated screen with real 24-bit colour, mapping
CC's sub-pixel glyphs to shade characters so the layout is readable in a
normal terminal.

After adding or removing a shipped file, run `tools/make_manifest.py` — the
installer reads `files.txt`.

---

## Layout

```
startup.lua            boot stub CC runs at power-on
install.lua            network installer
files.txt              manifest the installer downloads

aurora/
  boot.lua             module loader, splash, hand-off to the kernel
  kernel/
    init.lua           bring-up order, main loop, panic screen
    sched.lua          process table, coroutine scheduler, event routing
    termsurf.lua       a full CC terminal backed by a window buffer
    vfs.lua            trash, places, file types, clipboard
    devices.lua        peripheral hot-plug
    log.lua            ring buffer + on-disk kernel log
  gfx/
    surface.lua        character buffer, clipping, rounded corners, pills
    compositor.lua     displays, dirty-row presenting, window chrome
    theme.lua          palettes and semantic colour tokens
    pixel.lua          2x3 sub-pixel canvas, 5x7 font, icon renderer
  ui/
    widget.lua         widget base + Box / Fixed / Stack / Scrolled
    widgets.lua        the control set
    textview.lua       the text editing widget
    app.lua            application runtime, dialogs, menus, toasts
  shell/
    desktop.lua        panel, overview, dash, window management, lock screen
    wallpaper.lua      dithered gradient wallpapers
  svc/
    apps.lua           app registry, launching, file associations
    display.lua        monitor roles and claiming
    printer.lua        print spooler
  lib/
    util.lua           helpers
    syntax.lua         Lua + Markdown highlighters
    formula.lua        spreadsheet formula engine
  apps/                the ten bundled applications
```

---

## How it works, briefly

Every window, background service and ROM program is a **coroutine** with its own
sandboxed globals, its own character buffer and its own terminal redirect. The
kernel pumps CC events into them: keyboard, mouse and terminate go to exactly
one process; timers, peripherals and networking are broadcast, which is what
CraftOS programs expect.

The **compositor** keeps one buffer per display and only pushes rows that
actually changed, so a full repaint costs at most 19 `term.blit` calls. Window
corners are rounded by knocking a single sub-pixel out of each corner cell with
CC's teletext glyphs; buttons get the same treatment on their end caps, which
is where the Adwaita silhouette comes from.

The **theme** spends all 16 palette slots on five neutrals and eleven hues.
Code never names a slot — it names a token (`theme.c.accent`, `theme.c.card`),
so switching to light mode or a different accent is one table swap and a
palette upload.

## Licence

MIT.
