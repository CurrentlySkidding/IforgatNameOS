#!/usr/bin/env python3
"""Boot Aurora, run a script, then dump the kernel log and process table.

    python tools/debug.py "f1,click:5:17"
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from boot_test import build, parse_script, screen  # noqa: E402

PROBE = b"""
function(env)
  local nl = string.char(10)
  local out = {}
  local log = env.arequire("kernel.log")
  for _, e in ipairs(log.entries) do
    out[#out + 1] = ("[%s] %s: %s"):format(e.level, e.source, e.message)
  end
  local sched = env.arequire("kernel.sched")
  out[#out + 1] = ("-- procs %d, stack %d, focus %s, dirty %s"):format(
    #sched.procs, #sched.stack,
    sched.focus and sched.focus.name or "none", tostring(sched.dirty))
  for _, p in ipairs(sched.procs) do
    out[#out + 1] = ("   #%d %s win=%s dead=%s crashed=%s"):format(p.pid, p.name,
      p.win and ("%d,%d %dx%d"):format(p.win.x, p.win.y, p.win.w, p.win.h) or "none",
      tostring(p.dead), tostring(p.crashed))
  end
  local apps = env.arequire("svc.apps")
  out[#out + 1] = "-- apps: " .. table.concat(apps.order, ", ")
  local desktop = env.arequire("shell.desktop")
  out[#out + 1] = ("-- overview %s, grid %s, dashRects %d"):format(
    tostring(desktop.overview), tostring(desktop.appGrid),
    desktop.dashRects and #desktop.dashRects or -1)
  for _, r in ipairs(desktop.dashRects or {}) do
    out[#out + 1] = ("   dash %s at %d,%d %dx%d"):format(
      r.manifest and r.manifest.id or "grid-button", r.x, r.y, r.w, r.h)
  end
  return table.concat(out, nl)
end
"""


def main():
    script = sys.argv[1] if len(sys.argv) > 1 else ""
    show = "--screen" in sys.argv
    lua, emu, machine, _printed = build()
    machine.boot(b"startup.lua")
    machine.pump(800)

    for step in parse_script(script):
        if step[0] == "key":
            machine.push(b"key", step[1], False)
            machine.pump(800)
            machine.push(b"key_up", step[1])
        elif step[0] == "char":
            machine.push(b"char", step[1].encode())
        elif step[0] == "wait":
            pass
        else:
            machine.push(step[0].encode(), *step[1:])
        machine.pump(800)

    if machine.error:
        print("ERROR: %s" % machine.error.decode("utf-8", "replace"))

    probe = lua.eval(PROBE)
    print(probe(machine.env).decode("utf-8", "replace"))

    if show:
        print()
        print(screen(lua, machine, colour=False))


if __name__ == "__main__":
    main()
