#!/usr/bin/env python3
"""Compile and run a .sl file inside the emulator.

    python tools/slcheck.py tools/sample.sl
    python tools/slcheck.py tools/sample.sl --asm

Always runs the program by round-tripping through the assembly text, so the
.as file is proven to be what actually executes.
"""
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from boot_test import build  # noqa: E402

PROBE = b"""
function(env, source, showAssembly)
  local nl = string.char(10)
  local slang = env.arequire("lib.slang.init")
  local out = {}

  local built, err = slang.build(source, "test")
  if not built then return "COMPILE ERROR: " .. slang.errorText(err) end

  if showAssembly then
    out[#out+1] = built.assembly
    out[#out+1] = "--- output ---"
  end

  -- Round-trip: run exactly what the .as file says, not the in-memory tree.
  local reread, rerr = slang.compiler.fromAssembly(built.assembly)
  if not reread then return "ASSEMBLY REREAD FAILED: " .. slang.errorText(rerr) end
  local linked, lerr = slang.vm.link(reread)
  if not linked then return "LINK FAILED: " .. slang.errorText(lerr) end

  local printed = {}
  local io_ = {
    write = function(text) printed[#printed+1] = text end,
    ask = function() return "42" end,
    wait = function() end,
    clear = function() end,
    size = function() return 51, 19 end,
  }
  local ok, runErr = slang.vm.run(linked, { io = io_ })
  for _, line in ipairs(printed) do out[#out+1] = line end
  if not ok then
    out[#out+1] = "RUNTIME ERROR: " .. slang.errorText(runErr)
  end
  return table.concat(out, nl)
end
"""


def main():
    path = sys.argv[1]
    show = "--asm" in sys.argv
    source = io.open(path, encoding="utf-8").read()
    lua, emu, machine, _ = build()
    machine.boot(b"startup.lua")
    machine.pump(400)
    probe = lua.eval(PROBE)
    print(probe(machine.env, source.encode("utf-8"), show).decode("utf-8", "replace"))


if __name__ == "__main__":
    main()
