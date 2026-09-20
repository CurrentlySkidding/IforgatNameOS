# How Aurora works

Aurora has four layers stacked on CC: Tweaked's raw APIs.

```
  apps/          Files, Terminal, Editor, Writer, Sheets, Slides, Builder, …
  ─────────────────────────────────────────────────────────────────────────
  ui/            widget tree, layout, dialogs, menus, per-app event loop
  shell/         top panel, Activities overview, dash, window management
  svc/           app registry, display roles, print spooler
  ─────────────────────────────────────────────────────────────────────────
  kernel/        processes, event routing, terminal redirection, devices, VFS
  gfx/           surfaces, compositor, theme, sub-pixel canvas
  ─────────────────────────────────────────────────────────────────────────
  CC: Tweaked    term, fs, os, peripheral, coroutines
```

## Boot

1. CC runs `/startup.lua` at power-on.
2. It loads `/aurora/boot.lua`, which installs `arequire` — a tiny module
   loader that compiles each Aurora module against the real `_G` and caches it
   system-wide.
3. `boot.lua` paints the splash: the AURORA wordmark drawn with the 5x7 bitmap
   font through the sub-pixel canvas, plus a progress bar.
4. `kernel.start()` brings up subsystems in a fixed order, reporting each step
   to the splash: filesystems → theme → compositor → peripherals → displays →
   app registry → services → shell.
5. The kernel enters its event loop. It only returns when something asks to
   restart, shut down, or drop back to CraftOS.

`startup.lua` checks a global guard (`AURORA_RUNNING`) and bails out if it is
set. This matters because the Terminal app runs a *real* CraftOS shell, and
that shell re-runs the startup scripts — without the guard, opening a terminal
would boot a second copy of Aurora inside the first.

## Processes

`kernel/sched.lua` is the heart. Every window, every background service and
every ROM program is a coroutine with:

- its own globals table (inherits `_G`, plus an `aurora` handle),
- its own `Surface` — a character buffer the size of its window's client area,
- its own terminal redirect, built by `kernel/termsurf.lua`.

`termsurf` implements the complete CC terminal API on top of a Surface:
`write`, `blit`, `scroll`, cursor, colours, palette. Before resuming a process
the kernel calls `term.redirect(proc.redirect)`, and captures whatever the
process left current when it yields. That is the whole trick behind running
unmodified CraftOS programs in a window — `edit` and `paint` think they own the
screen, and they are writing into a 46x14 buffer.

The kernel also points the `aurora` global at the running process for the
duration of each resume. Shared modules like `ui.app` are compiled once against
the real `_G`, so they cannot see a table that lives only in one process's
environment; scheduling is cooperative, so a "current process" global is safe,
and it is exactly how CC handles `term.redirect` itself.

### Event routing

```
os.pullEventRaw()
        │
        ├─ shell.desktop:handleEvent()      first refusal
        │     hotkeys, panel clicks, the overview, window drag/resize,
        │     monitor touches, peripheral hot-plug
        │
        └─ sched.route()                    whatever the shell did not claim
              key / char / paste / terminate  →  the focused process only
              mouse_*                         →  the window under the pointer,
                                                 translated to window coords
              everything else                 →  broadcast
```

Broadcasting timers, peripheral and network events is what CraftOS programs
expect; they check the id themselves. Keyboard and mouse are exclusive because
a background process should not see your typing.

Processes never resume each other directly. `sched.post(pid, …)` appends to a
per-process inbox that the kernel drains at the top of the next loop
iteration, which keeps the scheduler non-reentrant.

## Drawing

### Surfaces

`gfx/surface.lua` stores a buffer as three parallel arrays of strings — text,
foreground, background — one per row, exactly like CC's own terminal. Writing
is string splicing; presenting a row is a single `term.blit`. Surfaces support
nested clip rectangles, which is what makes scrolled views correct.

### The compositor

`gfx/compositor.lua` owns one `Display` per output: the computer's own screen
plus every attached monitor. Each display keeps the last frame it pushed and
only re-blits rows that changed, so a full-screen repaint costs at most 19
`term.blit` calls and a typical one costs two or three.

Window chrome is drawn here: a one-cell drop shadow, a header bar with the
title and round controls, and rounded outer corners.

### Rounded corners and pills

CC's font contains 32 "teletext" glyphs (128–159) that split a character cell
into a 2×3 sub-pixel grid. Knocking exactly one sub-pixel out of each corner
cell reads, at a glance, as a rounded corner:

```
  bits: tl=1  tr=2  ml=4  mr=8  bl=16      char = 128 + bits
  (bottom-right is expressed by swapping foreground and background)
```

The same trick gives buttons their Adwaita pill shape: both corners of the
first cell and both of the last, at a cost of one cell per end cap.

### The sub-pixel canvas

`gfx/pixel.lua` turns the whole screen into a 102×57 pixel display. A `Canvas`
stores one colour per pixel, then collapses each 2×3 block into a cell: it
takes the bottom-right pixel's colour as the background and sets a bit for
every pixel that differs. It carries a 5×7 bitmap font, so the boot logo, the
lock-screen clock and Slides headings are real typography rather than ASCII art.

App icons are rounded squircles drawn on this canvas with a glyph or a small
pixel-art bitmap on top.

### The theme

Aurora redefines all 16 palette slots: five neutrals (`n0`–`n4`) and eleven
hues. Code never names a slot, only a token — `theme.c.window`, `theme.c.card`,
`theme.c.accent`, `theme.c.dim`. A scheme supplies both the RGB values and the
token mapping, so light mode swaps which slot means "text" without touching a
single call site. Accent colours remap the blue slot and derive a lighter
variant for hover states.

Wallpapers are rendered once per size/theme into a Surface, using ordered
(Bayer) dithering between palette colours to get gradients out of 16 colours.

## The shell

`shell/desktop.lua` is GNOME Shell in one file: the top panel with Activities,
clock and status icons; the Activities overview with window cards, a search
field that matches apps *and* files, and the dash; the paginated app grid; the
Alt-Tab switcher; notifications; the power menu; the lock screen; and all
window management — focus, z-order, drag, resize, maximise, edge snapping.

It renders each display according to that display's role, so a mirrored
monitor gets the same desktop, an extended one gets its own windows, and a
dedicated one gets whichever app claimed it.

## Services

- **`svc/apps.lua`** scans `/aurora/apps` and `/home/apps` for manifests, keeps
  the registry and the dash favourites, launches apps (raising the existing
  window for singletons), and decides which app opens which file type.
- **`svc/display.lua`** assigns monitors a role — mirror, extend, dedicated,
  off — persists that choice, and routes `monitor_touch` to whatever is showing.
- **`svc/printer.lua`** paginates documents to the printer's real page size,
  titles each page, and drains the queue from a background process.

## The UI toolkit

`ui/widget.lua` and `ui/widgets.lua` implement GTK4's model: widgets
**measure** (natural size), get **allocated** a rectangle, then **draw**.
Containers distribute spare space to children that declare `hexpand` or
`vexpand`. Signals are plain callback lists.

`ui/app.lua` is the per-app runtime: the event loop, focus and tab order,
mouse capture and bubbling, modal dialogs with a scrim, popover menus, toasts,
timers and accelerators. It publishes the focused widget's caret so the
compositor can put a real blinking hardware cursor there.

`ui/textview.lua` is a full text editor widget — selection, clipboard, undo,
find and replace, soft wrap, line numbers and pluggable syntax highlighting.
Editor, Writer and the Builder's code view all sit on it.

## Testing

`tools/craftos.lua` is a small CC: Tweaked emulator — filesystem, terminal with
redirects, event queue and virtual timers, colours, keys, textutils,
peripherals. `tools/boot_test.py` mounts the repository into it, boots
`startup.lua`, feeds it scripted input and renders the screen back with real
24-bit colour. `tools/test_all.py` uses that to boot a fresh machine per test
case and check that every app launches, the shell works, formulas evaluate,
printing paginates, and the Builder's generated code compiles.

It is not a general-purpose emulator — it exists so the OS can be driven and
read back without opening Minecraft.
