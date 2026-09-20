#!/usr/bin/env python3
"""Syntax-check every Lua source in the repository.

CC:Tweaked runs Cobalt (Lua 5.1 plus a few 5.2/5.3 borrowings).  Lupa gives us
a real Lua, which is close enough to catch every parse error the game would.
"""
import io
import os
import sys

import lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".git", "__pycache__", "tools"}


def lua_files():
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in sorted(names):
            if name.endswith(".lua"):
                yield os.path.join(base, name)


def main():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    # Wrap load() so we always get a plain (ok, message) pair back.
    check = lua.eval("""
      function(src, name)
        local chunk, err = load(src, name)
        if chunk then return true, "" end
        return false, tostring(err)
      end
    """)

    failures = []
    count = 0
    for path in lua_files():
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        src = io.open(path, encoding="utf-8", errors="surrogateescape").read()
        count += 1
        ok, err = check(src, "@" + rel)
        if not ok:
            failures.append((rel, err))
            print("FAIL %s\n     %s" % (rel, err))

    print("\n%d files checked, %d failed" % (count, len(failures)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
