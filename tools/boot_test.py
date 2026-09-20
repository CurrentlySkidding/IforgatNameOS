#!/usr/bin/env python3
"""Boot Aurora inside the CraftOS emulator and drive it.

    python tools/boot_test.py                       boot and render the desktop
    python tools/boot_test.py --script overview
    python tools/boot_test.py --script "click:5:1,click:10:16"
    python tools/boot_test.py --monitors 1 --script overview

Aurora's screen uses CP437 plus CC's 2x3 "teletext" glyphs, so the dump maps
those to shade characters and paints real 24-bit colour from the live palette.
"""
import argparse
import io
import os
import sys

import lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".git", "__pycache__", "tools", "docs"}
SHADES = " .:-=+*#%@"

# A few CP437 glyphs Aurora leans on, mapped to something visible.
CP437 = {
    4: "*", 7: "o", 15: "*", 16: ">", 17: "<", 22: "P", 24: "^", 25: "v",
    27: "<", 30: "^", 31: "v", 127: "H", 171: "=", 174: "<", 175: ">",
    179: "|", 196: "-", 215: "x", 218: "+", 191: "+", 192: "+", 217: "+",
    233: "T", 250: ".", 251: "v", 254: "#", 246: "/", 183: "-", 151: "-",
    126: "~", 140: "_", 149: "|",
}


FAKE_SHELL = b"""
-- minimal stand-in for /rom/programs/shell.lua
local line = ""
term.write("> ")
while true do
  local event, a = os.pullEvent()
  if event == "char" then
    line = line .. a
    term.write(a)
  elseif event == "key" and a == keys.enter then
    local _, y = term.getCursorPos()
    local w, h = term.getSize()
    if y >= h then term.scroll(1) term.setCursorPos(1, h)
    else term.setCursorPos(1, y + 1) end
    if line == "exit" then return end
    if line ~= "" then term.write("sh: " .. line .. ": not found") end
    local _, y2 = term.getCursorPos()
    if y2 >= h then term.scroll(1) term.setCursorPos(1, h)
    else term.setCursorPos(1, y2 + 1) end
    term.write("> ")
    line = ""
  end
end
"""


def repo_files():
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in sorted(names):
            if name.endswith((".lua", ".cfg", ".md", ".txt")) or name == "manifest":
                full = os.path.join(base, name)
                rel = os.path.relpath(full, ROOT).replace("\\", "/")
                with io.open(full, "rb") as handle:
                    yield rel, handle.read()


MAKE_PRINTER = b"""
function(store)
  local page = nil
  local handle = {
    getPageSize = function() return 25, 21 end,
    getInkLevel = function() return 60 end,
    getPaperLevel = function() return 40 end,
    newPage = function() page = { title = "", lines = {} } return true end,
    setPageTitle = function(t) if page then page.title = t end end,
    setCursorPos = function(x, y) if page then page.y = y end end,
    write = function(text)
      if page then page.lines[page.y or 1] = tostring(text) end
    end,
    endPage = function()
      if not page then return false end
      store[#store + 1] = page
      page = nil
      return true
    end,
  }
  return { type = "printer", handle = handle }
end
"""


def build(width=51, height=19, monitors=0, printer=False):
    # encoding=None keeps Lua strings as raw bytes, which is what a CC screen
    # buffer really is.
    lua = lupa.LuaRuntime(unpack_returned_tuples=False, encoding=None)
    with io.open(os.path.join(ROOT, "tools", "craftos.lua"), "rb") as handle:
        emu = lua.execute(handle.read())

    mount = lua.eval(b"function(vfs, path, data) vfs.write(path, data) end")
    for rel, data in repo_files():
        mount(emu.vfs, rel.encode("utf-8"), data)
    lua.eval(b"function(vfs) vfs.mkdir('rom/programs') end")(emu.vfs)
    # A stand-in for CraftOS's shell, so the Terminal app's plumbing (term
    # redirection into a window buffer) can be exercised here too.
    mount(emu.vfs, b"rom/programs/shell.lua", FAKE_SHELL)

    opts = lua.table_from({b"width": width, b"height": height})
    peripherals = lua.eval(b"function() return {} end")()
    machine_printed = None
    if printer:
        machine_printed = lua.eval(b"function() return {} end")()
        peripherals[b"printer_0"] = lua.eval(MAKE_PRINTER)(machine_printed)
        opts[b"peripherals"] = peripherals
    if monitors:
        make = lua.eval(
            b"""
            function(n, w, h)
              local list = {}
              for i = 1, n do
                local mon = {
                  getSize = function() return w, h end,
                  setTextScale = function() end,
                  isColour = function() return true end,
                  isColor = function() return true end,
                  setCursorPos = function() end,
                  setCursorBlink = function() end,
                  blit = function() end,
                  write = function() end,
                  clear = function() end,
                  clearLine = function() end,
                  scroll = function() end,
                  getCursorPos = function() return 1, 1 end,
                  setTextColour = function() end,
                  setBackgroundColour = function() end,
                  setPaletteColour = function() end,
                  getPaletteColour = function() return 0, 0, 0 end,
                }
                list["monitor_" .. i] = { type = "monitor", handle = mon }
              end
              return list
            end
            """
        )
        merge = lua.eval(b"function(into, from) for k, v in pairs(from) do into[k] = v end end")
        merge(peripherals, make(monitors, 41, 19))
        opts[b"peripherals"] = peripherals

    machine = emu.build(opts)
    machine_printed_ref = machine_printed
    return lua, emu, machine, machine_printed_ref


def palette_of(lua, native):
    """Read the live palette back out of the emulated terminal."""
    grab = lua.eval(
        b"""
        function(t)
          local out = {}
          for i = 0, 15 do
            local packed = t.palette[2 ^ i] or 0
            out[i + 1] = packed
          end
          return out
        end
        """
    )
    packed = grab(native)
    palette = {}
    for i in range(16):
        value = int(packed[i + 1] or 0)
        palette[i] = ((value >> 16) & 255, (value >> 8) & 255, value & 255)
    return palette


def screen(lua, machine, colour=True):
    native = machine.native
    palette = palette_of(lua, native)
    rows = []
    height = int(native.h)
    for y in range(1, height + 1):
        text = native.text[y]
        fgs = native.fgs[y].decode("ascii")
        bgs = native.bgs[y].decode("ascii")
        row = []
        for x, code in enumerate(text):
            if 32 <= code <= 126:
                shown = chr(code)
            elif 128 <= code <= 159:
                bits = bin(code - 128).count("1")
                shown = SHADES[min(len(SHADES) - 1, bits * 2)]
            else:
                shown = CP437.get(code, " " if code < 32 else "?")
            if colour:
                fr, fg_, fb = palette[int(fgs[x], 16)]
                br, bg_, bb = palette[int(bgs[x], 16)]
                row.append(
                    "\x1b[38;2;%d;%d;%dm\x1b[48;2;%d;%d;%dm%s" % (fr, fg_, fb, br, bg_, bb, shown)
                )
            else:
                row.append(shown)
        rows.append("".join(row) + ("\x1b[0m" if colour else ""))
    return "\n".join(rows)


KEY = {
    "f1": 59, "f2": 60, "f5": 63, "f11": 87, "escape": 1, "enter": 28,
    "tab": 15, "down": 208, "up": 200, "left": 203, "right": 205,
    "backspace": 14, "delete": 211,
}


def parse_script(text):
    steps = []
    for token in filter(None, (t.strip() for t in text.split(","))):
        if token in KEY:
            steps.append(("key", KEY[token]))
        elif token.startswith("click:"):
            _, x, y = token.split(":")
            steps.append(("mouse_click", 1, int(x), int(y)))
        elif token.startswith("type:"):
            for ch in token[5:]:
                steps.append(("char", ch))
        elif token.startswith("wait"):
            steps.append(("wait", None))
        else:
            raise SystemExit("unknown script step: %s" % token)
    return steps


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--script", default="")
    parser.add_argument("--no-colour", action="store_true")
    parser.add_argument("--monitors", type=int, default=0)
    parser.add_argument("--steps", type=int, default=800)
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("--launch", default="", help="comma separated app ids")
    args = parser.parse_args()

    lua, emu, machine, _printed = build(monitors=args.monitors)

    machine.boot(b"startup.lua")
    machine.pump(args.steps)

    if args.launch:
        launch = lua.eval(b'function(env, id) env.arequire("svc.apps").launch(id) end')
        for app_id in args.launch.split(","):
            launch(machine.env, app_id.strip().encode())
            machine.pump(args.steps)
    if machine.error:
        print("RUNTIME ERROR during boot:\n  %s" % machine.error.decode("utf-8", "replace"))
        return 1

    for step in parse_script(args.script):
        if step[0] == "key":
            machine.push(b"key", step[1], False)
            machine.pump(args.steps)
            machine.push(b"key_up", step[1])
        elif step[0] == "char":
            machine.push(b"char", step[1].encode())
        elif step[0] == "wait":
            pass
        else:
            machine.push(step[0].encode(), *step[1:])
        machine.pump(args.steps)
        if machine.error:
            print("RUNTIME ERROR after %s:\n  %s"
                  % (step, machine.error.decode("utf-8", "replace")))
            print(screen(lua, machine, colour=not args.no_colour))
            return 1

    if not args.quiet:
        print(screen(lua, machine, colour=not args.no_colour))
        print()
    print("ok - booted and ran %d script step(s) with no runtime errors"
          % len(parse_script(args.script)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
