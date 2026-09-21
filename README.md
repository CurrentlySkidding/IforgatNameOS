# Aurora OS

A desktop operating system for **CC: Tweaked** computers in Minecraft.

Aurora boots straight from power-on, replaces the CraftOS shell with a
GNOME-style desktop, and brings its own kernel, window manager, compositor,
widget toolkit and application suite — a file manager, a terminal, a code
editor, a word processor, a spreadsheet, a presentation app, settings and a
system monitor. On top of that sits an encrypted network the rest of the
system is built on: chat with other computers, a little internet you host
yourself, a base defense system wired to real redstone, and an assistant that
knows Minecraft and can drive the machine for you.

It drives monitors and printers as real peripherals, so a wall of monitors
becomes a projector and a printer prints your documents.

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

Title bars carry a single close button, like GNOME. Minimise and maximise live
in the window menu — **right-click the title bar** — and double-clicking the
title bar maximises.

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

**Messages** — encrypted chat with every other Aurora computer on your
network key. Messages arrive even when the window is closed: they land in the
conversation log and raise a notification.

**Web** — a small internet for your world. Every computer can host a site from
`/home/www`; sites announce themselves, so the browser's home page is a live
directory of everything it has heard from. Pages use a tiny markup with
headings, bullets, quotes and clickable links that reach across computers.

**Studio** — the SimpleLang workbench: projects, an editor, the compiler, and
the assembly it produces. Build writes the `.as` assembly and the `.ep`
executable beside your source; Run launches it in its own window.

**Snake** and **Corridor** — an arcade game and a first-person raycast maze,
both drawn on the sub-pixel canvas.

**Aria** — the assistant. Ask her how to make a beacon, where diamond spawns,
what the Warden's health is, how to brew fire resistance, or what Mending
does. Tell her to open an app, message a computer, arm the base or turn the
lights on and she does it. Ask for a status report and she reads the network,
the printers, the disk and the defense system back to you. She remembers your
name and what you usually ask about. It is rules and a knowledge base, not a
model — which means it answers instantly and works on a computer buried in a
cave with no connection to anything.

**Defense** — the base security system, wired to actual redstone. Devices are
named outputs (doors, lights, traps, sirens, turrets) on a side or a bundled
cable colour. Sensors are inputs from pressure plates, tripwires or player
detectors. Arm the system behind a passcode and a tripped sensor fires every
device marked as an alarm response, logs it, notifies you, and broadcasts an
encrypted alert to every other computer on your network.

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

## The secure network

Everything that leaves an Aurora computer — chat, web pages, defense alerts —
goes out as an encrypted, authenticated, replay-protected frame over rednet.

Computers that share a **network key** can talk to each other. Set it in
Settings → Network; each machine shows a fingerprint so you can check two of
them match without ever showing the key itself. Change the key and traffic
from the old one stops being readable, which is the whole point.

The cipher is XXTEA and the message authentication code is the same primitive
in CBC-MAC form, so there is exactly one algorithm to trust. Frames carry a
nonce and are rejected if replayed.

What this gives you: somebody sniffing your channel with a modem sees hex, and
cannot forge a message that passes the MAC. What it does not give you:
protection from anyone who can read the key off your computer's disk. Treat
the network key like a base password.

You need a modem on each computer. Wireless reaches 64 blocks (further up
high, less in a storm); an ender modem reaches anywhere, across dimensions.

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
scan (Settings → Apps, or a reboot).

The toolkit gives you `Label`, `Button`, `IconButton`, `Entry`, `TextView`,
`Switch`, `CheckBox`, `ListBox`, `IconGrid`, `Chart`, `ProgressBar`, `Spinner`,
`Separator`, `Tabs`, `Dropdown`, `StatusPage` and `Toolbar`, plus `Box`,
`Grid`, `Fixed`, `Stack` and `Scrolled` containers — and `app:dialog`,
`app:prompt`, `app:confirm`, `app:menu`, `app:notify` and `app:accel` for the
usual desktop furniture.

See [docs/writing-apps.md](docs/writing-apps.md) for the full reference,
[docs/network.md](docs/network.md) for the secure network, and
[docs/architecture.md](docs/architecture.md) for how the kernel works.

---

## Development

The repository ships a small CraftOS emulator so you can boot and drive Aurora
without opening Minecraft.

```bash
pip install lupa

python tools/check.py                      # syntax-check every Lua file
python tools/test_all.py                   # boot + integration tests
python tools/bench.py                      # compositing cost per interaction
python tools/boot_test.py                  # render the desktop
python tools/boot_test.py --launch sheets  # render one app
python tools/boot_test.py --script "f1,click:5:16"
python tools/debug.py "f1" --screen        # kernel log + process table
python tools/make_manifest.py              # regenerate files.txt
```

`boot_test.py` prints the emulated screen with real 24-bit colour, mapping
CC's sub-pixel glyphs to shade characters so the layout is readable in a
normal terminal.

The emulator models redstone and wires two machines together over a rednet
bus, so the tests genuinely encrypt a message on one computer and decrypt it
on another, fetch a web page across the wire, and trip a sensor to watch the
alarm drive a redstone side.

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
    net.lua            encrypted, authenticated rednet framing + discovery
    messages.lua       chat storage and delivery
    web.lua            page markup, site hosting, site discovery
    defense.lua        redstone devices, sensors, alarm, remote alerts
  lib/
    util.lua           helpers
    syntax.lua         Lua + Markdown highlighters
    formula.lua        spreadsheet formula engine
    bitops.lua         32-bit ops across bit32 / native / arithmetic backends
    crypto.lua         XXTEA encryption and message authentication
    knowledge.lua      what Aria knows about Minecraft
    aria.lua           the assistant's intent matching and memory
    slang/parser.lua   SimpleLang lexer and parser
    slang/compiler.lua AST -> assembly, and assembly -> program
    slang/vm.lua       the stack machine and its host functions
    slang/init.lua     build, load, run, package
  apps/                the sixteen bundled applications
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
