#!/usr/bin/env python3
"""Measure how much work a frame costs.

Counts term.blit calls (the only thing that actually touches the screen in
CC) and elapsed time for common interactions, with the damage-aware render
path on and forced off, so the difference is visible.
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from boot_test import build  # noqa: E402


def take(fn):
    """blits() returns (term calls, cells composited)."""
    return fn(True)

COUNTER = b"""
function(machine, env)
  -- term.blit is what reaches the screen; Surface:blit is the compositing
  -- work behind it, and that is where the cost actually lives.
  local native = machine.native
  local realTerm = native.blit
  local terms = 0
  native.blit = function(...) terms = terms + 1 return realTerm(...) end

  local Surface = env.arequire("gfx.surface")
  local realSurface = Surface.blit
  local cells = 0
  Surface.blit = function(self, x, y, text, fg, bg)
    cells = cells + #text
    return realSurface(self, x, y, text, fg, bg)
  end

  return function(reset)
    local a, b = terms, cells
    if reset then terms, cells = 0, 0 end
    return a, b
  end
end
"""

FORCE_FULL = b"""
function(env, on)
  local desktop = env.arequire("shell.desktop")
  if on then
    if not desktop.__fastRender then desktop.__fastRender = desktop.fastRender end
    desktop.fastRender = function() return false end
    desktop.renderPanelOnly = desktop.renderFull
  elseif desktop.__fastRender then
    desktop.fastRender = desktop.__fastRender
  end
end
"""


def scenario(force_full, label):
    lua, emu, machine, _ = build()
    machine.boot(b"startup.lua")
    machine.pump(800)
    lua.eval(b'function(env, id) env.arequire("svc.apps").launch(id) end')(
        machine.env, b"editor")
    machine.pump(800)

    if force_full:
        lua.eval(FORCE_FULL)(machine.env, True)

    blits = lua.eval(COUNTER)(machine, machine.env)
    results = {}

    # 1. typing
    blits(True)
    start = time.perf_counter()
    for ch in b"the quick brown fox jumps":
        machine.push(b"char", bytes([ch]))
        machine.pump(4)
    elapsed = time.perf_counter() - start
    results["typing (25 chars)"] = (blits(True), elapsed)

    # 2. idle clock ticks
    start = time.perf_counter()
    for _ in range(10):
        machine.push(b"timer", 1)
        machine.pump(2)
    elapsed = time.perf_counter() - start
    results["10 idle frames"] = (blits(True), elapsed)

    # 3. moving a window (forces full frames either way)
    start = time.perf_counter()
    machine.push(b"mouse_click", 1, 20, 2)
    machine.pump(4)
    for x in range(20, 30):
        machine.push(b"mouse_drag", 1, x, 4)
        machine.pump(4)
    machine.push(b"mouse_up", 1, 30, 4)
    machine.pump(4)
    elapsed = time.perf_counter() - start
    results["drag a window"] = (blits(True), elapsed)

    return results


def main():
    fast = scenario(False, "damage-aware")
    full = scenario(True, "always full")

    print("%-22s   %16s %16s   %s" % ("", "full repaint", "damage-aware", "saved"))
    for name in fast:
        (f_term, f_cells), f_time = full[name]
        (d_term, d_cells), d_time = fast[name]
        saved = "-" if not f_cells else "%d%%" % round((1 - d_cells / f_cells) * 100)
        print("%-22s   %10d cells %10d cells   %s" % (name, f_cells, d_cells, saved))
    print()
    print("%-22s   %16s %16s   %s" % ("", "full repaint", "damage-aware", "saved"))
    for name in fast:
        f_time, d_time = full[name][1], fast[name][1]
        saved = "-" if not f_time else "%d%%" % round((1 - d_time / f_time) * 100)
        print("%-22s   %13.0f ms %13.0f ms   %s" % (name, f_time * 1000, d_time * 1000, saved))


if __name__ == "__main__":
    main()
