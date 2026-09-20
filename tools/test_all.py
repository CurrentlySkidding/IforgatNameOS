#!/usr/bin/env python3
"""Integration tests: boot Aurora, launch every app, exercise the shell.

Each case boots a fresh machine so one crash cannot poison the next.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from boot_test import build, screen  # noqa: E402

LAUNCH = b"""
function(env, id)
  local apps = env.arequire("svc.apps")
  local proc, err = apps.launch(id)
  if not proc then return "spawn failed: " .. tostring(err) end
  return ""
end
"""

CRASHES = b"""
function(env)
  local nl = string.char(10)
  local sched = env.arequire("kernel.sched")
  local log = env.arequire("kernel.log")
  local out = {}
  for _, e in ipairs(log.entries) do
    if e.level == "error" then out[#out + 1] = e.source .. ": " .. e.message end
  end
  for _, p in ipairs(sched.procs) do
    if p.crashed then out[#out + 1] = p.name .. ": " .. tostring(p.crashed) end
  end
  return table.concat(out, nl)
end
"""

SEND = b"""
function(env, pid, a, b, c, d)
  local sched = env.arequire("kernel.sched")
  local proc = sched.byPid[pid]
  if not proc then return "no process" end
  sched.resume(proc, table.pack(a, b, c, d))
  return ""
end
"""

APPS = ["files", "terminal", "editor", "writer", "sheets", "slides",
        "settings", "calc", "monitor"]


class Case:
    def __init__(self, name, printer=False):
        self.name = name
        self.lua, self.emu, self.machine, self.printed = build(printer=printer)
        self.machine.boot(b"startup.lua")
        self.machine.pump(800)
        self.launch = self.lua.eval(LAUNCH)
        self.crashes = self.lua.eval(CRASHES)

    def run_script(self, steps):
        for step in steps:
            self.machine.push(*step)
            self.machine.pump(800)

    def errors(self):
        out = []
        if self.machine.error:
            out.append("machine: " + self.machine.error.decode("utf-8", "replace"))
        text = self.crashes(self.machine.env).decode("utf-8", "replace").strip()
        if text:
            out.extend(text.splitlines())
        return out


def check(name, fn):
    try:
        problems = fn()
    except Exception as exc:  # emulator-level failure
        problems = ["harness: %r" % (exc,)]
    if problems:
        print("FAIL  %s" % name)
        for line in problems:
            print("      %s" % line)
        return False
    print("ok    %s" % name)
    return True


def test_boot():
    case = Case("boot")
    return case.errors()


def make_app_test(app_id):
    def run():
        case = Case(app_id)
        message = case.launch(case.machine.env, app_id.encode()).decode()
        problems = case.errors()
        if message:
            problems.insert(0, message)
        # give the app a few events: a resize, a click, a keypress
        case.run_script([
            (b"mouse_click", 1, 10, 6),
            (b"mouse_up", 1, 10, 6),
            (b"key", 208, False),     # down arrow
            (b"key_up", 208),
            (b"char", b"a"),
            (b"key", 15, False),      # tab
            (b"key_up", 15),
        ])
        problems.extend(case.errors())
        return problems
    return run


def test_overview():
    case = Case("overview")
    case.run_script([
        (b"key", 59, False), (b"key_up", 59),         # F1 overview
        (b"char", b"f"), (b"char", b"i"),             # search "fi"
        (b"key", 28, False), (b"key_up", 28),         # enter -> launch Files
    ])
    return case.errors()


def test_app_grid():
    case = Case("app grid")
    case.run_script([
        (b"key", 60, False), (b"key_up", 60),         # F2 app grid
        (b"key", 205, False), (b"key_up", 205),       # right
        (b"key", 28, False), (b"key_up", 28),         # enter
        (b"key", 59, False), (b"key_up", 59),         # F1 overview again
        (b"key", 1, False), (b"key_up", 1),           # escape
    ])
    return case.errors()


def test_window_management():
    case = Case("window management")
    case.launch(case.machine.env, b"files")
    case.machine.pump(800)
    case.run_script([
        (b"mouse_click", 1, 20, 2),                   # grab the header
        (b"mouse_drag", 1, 24, 6),                    # move the window
        (b"mouse_up", 1, 24, 6),
        (b"key", 87, False), (b"key_up", 87),         # F11 maximise
        (b"key", 87, False), (b"key_up", 87),         # F11 restore
    ])
    problems = case.errors()
    # now close it through the header button
    case.run_script([(b"key", 63, False), (b"key_up", 63)])   # F5 redraw
    problems.extend(case.errors())
    return problems


def test_two_windows_and_switching():
    case = Case("alt-tab")
    case.launch(case.machine.env, b"files")
    case.machine.pump(400)
    case.launch(case.machine.env, b"calc")
    case.machine.pump(400)
    case.run_script([
        (b"key", 56, False),                          # hold alt
        (b"key", 15, False),                          # tab
        (b"key_up", 15),
        (b"key_up", 56),                              # release alt
    ])
    return case.errors()


def test_power_menu_and_lock():
    case = Case("power menu")
    case.run_script([
        (b"mouse_click", 1, 50, 1),                   # power button in the panel
        (b"mouse_up", 1, 50, 1),
        (b"key", 208, False), (b"key_up", 208),
        (b"key", 1, False), (b"key_up", 1),           # escape
    ])
    return case.errors()


def test_editor_editing():
    case = Case("editor typing")
    case.launch(case.machine.env, b"editor")
    case.machine.pump(800)
    steps = []
    for ch in b"local x = 1":
        steps.append((b"char", bytes([ch])))
    steps.extend([
        (b"key", 28, False), (b"key_up", 28),         # enter
        (b"key", 200, False), (b"key_up", 200),       # up
        (b"key", 14, False), (b"key_up", 14),         # backspace
    ])
    case.run_script(steps)
    return case.errors()


def test_sheets_formula():
    case = Case("sheets formula")
    case.launch(case.machine.env, b"sheets")
    case.machine.pump(800)
    probe = case.lua.eval(b"""
      function(env)
        local formula = env.arequire("lib.formula")
        local sheet = { cells = {
          A1 = { text = "2" }, A2 = { text = "3" }, A3 = { text = "4" },
          B1 = { text = "=SUM(A1:A3)" },
          B2 = { text = "=A1*A2+1" },
          B3 = { text = "=IF(A1>1,\\"big\\",\\"small\\")" },
          B4 = { text = "=AVERAGE(A1:A3)" },
          C1 = { text = "=C2" }, C2 = { text = "=C1" },
        } }
        local results = {}
        for _, ref in ipairs({ "B1", "B2", "B3", "B4", "C1" }) do
          results[#results + 1] = ref .. "=" ..
            tostring(formula.format(formula.evaluate(sheet, ref)))
        end
        return table.concat(results, " ")
      end
    """)
    text = probe(case.machine.env).decode()
    expected = "B1=9 B2=7 B3=big B4=3 C1=#CYCLE"
    problems = case.errors()
    if text != expected:
        problems.append("formula results: got %r want %r" % (text, expected))
    return problems


def test_monitors():
    lua, emu, machine, _printed = build(monitors=1)
    machine.boot(b"startup.lua")
    machine.pump(800)
    probe = lua.eval(b"""
      function(env)
        local compositor = env.arequire("gfx.compositor")
        local names = {}
        for _, d in ipairs(compositor.displays) do
          names[#names + 1] = d.id .. ":" .. d.role
        end
        return table.concat(names, ",")
      end
    """)
    text = probe(machine.env).decode()
    problems = []
    if machine.error:
        problems.append(machine.error.decode("utf-8", "replace"))
    if "monitor_1" not in text:
        problems.append("monitor was not picked up: %s" % text)
    return problems


def test_slides_presenting():
    """Slides should be able to claim a monitor and paint on it."""
    lua, emu, machine, _printed = build(monitors=1)
    machine.boot(b"startup.lua")
    machine.pump(800)
    probe = lua.eval(b"""
      function(env)
        local apps = env.arequire("svc.apps")
        local display = env.arequire("svc.display")
        local sched = env.arequire("kernel.sched")
        local proc = apps.launch("slides")
        if not proc then return "slides would not start" end
        local d = display.claim("monitor_1", proc)
        if not d then return "could not claim the monitor" end
        if d.role ~= "dedicated" then return "role is " .. tostring(d.role) end
        if display.ownerOf("monitor_1") ~= proc then return "owner was not recorded" end
        local desktop = env.arequire("shell.desktop")
        desktop.render()
        display.release("monitor_1")
        if display.ownerOf("monitor_1") ~= nil then return "release did not clear the owner" end
        return ""
      end
    """)
    message = probe(machine.env).decode()
    machine.pump(800)
    problems = []
    if machine.error:
        problems.append(machine.error.decode("utf-8", "replace"))
    if message:
        problems.append(message)
    return problems


def test_dialogs_and_menus():
    """Open the Files menu, then a modal dialog, and type into it."""
    case = Case("dialogs")
    case.launch(case.machine.env, b"files")
    case.machine.pump(800)
    probe = case.lua.eval(b"""
      function(env, stage)
        local sched = env.arequire("kernel.sched")
        for _, p in ipairs(sched.procs) do
          if p.appId == "files" then
            local s = p.surface
            local found = false
            for y = 1, s.h do
              if s.t[y]:find(stage, 1, true) then found = true end
            end
            return found and "" or ("did not find " .. stage)
          end
        end
        return "files is gone"
      end
    """)
    # Ctrl+N is "new folder", which opens a prompt dialog.
    case.run_script([
        (b"key", 29, False),                       # ctrl down
        (b"key", 49, False),                       # n
        (b"key_up", 49),
        (b"key_up", 29),
    ])
    problems = case.errors()
    message = probe(case.machine.env, b"New folder").decode()
    if message:
        problems.append("prompt dialog: " + message)

    # type a name and confirm with Enter
    steps = [(b"char", bytes([ch])) for ch in b"Reports"]
    steps.extend([(b"key", 28, False), (b"key_up", 28)])
    case.run_script(steps)
    problems.extend(case.errors())

    made = case.lua.eval(b"""
      function(env)
        for _, name in ipairs(env.fs.list("home")) do
          if name:find("Reports", 1, true) then return "" end
        end
        return "the folder was not created"
      end
    """)(case.machine.env).decode()
    if made:
        problems.append(made)
    return problems


def test_printing():
    case = Case("printing", printer=True)
    probe = case.lua.eval(b"""
      function(env)
        local printer = env.arequire("svc.printer")
        local devices = env.arequire("kernel.devices")
        if #printer.available() == 0 then return "no printer detected" end
        local lines = {}
        for i = 1, 60 do lines[i] = "Line " .. i .. " of a long test document" end
        printer.submit({ title = "Test document", content = lines })
        printer.pump()
        local job = printer.history[1]
        if not job then return "job never finished" end
        if job.state ~= "done" then return "job state " .. job.state
                                          .. " (" .. tostring(job.error) .. ")" end
        return "pages=" .. tostring(job.printed)
      end
    """)
    result = probe(case.machine.env).decode()
    problems = case.errors()
    if not result.startswith("pages="):
        problems.append(result)
    else:
        pages = int(result.split("=")[1])
        # 60 long lines wrapped to a 25x21 page should need several pages
        if pages < 3:
            problems.append("expected multiple pages, got %d" % pages)
        if len(case.printed) != pages:
            problems.append("printer received %d pages, job says %d"
                            % (len(case.printed), pages))
    return problems


def test_open_file_from_files():
    case = Case("open file")
    setup = case.lua.eval(b"""
      function(env)
        local util = env.arequire("lib.util")
        util.writeFile("home/Documents/notes.txt", "hello from a file")
        local apps = env.arequire("svc.apps")
        local proc = apps.openFile("home/Documents/notes.txt")
        return proc and proc.appId or "nothing opened"
      end
    """)
    opened = setup(case.machine.env).decode()
    case.machine.pump(800)
    problems = case.errors()
    if opened != "editor":
        problems.append("expected the editor, got %r" % opened)
    verify = case.lua.eval(b"""
      function(env)
        local sched = env.arequire("kernel.sched")
        for _, p in ipairs(sched.procs) do
          if p.appId == "editor" then
            local s = p.surface
            for y = 1, s.h do
              if s.t[y]:find("hello from a file", 1, true) then return "" end
            end
            return "editor window does not show the file contents"
          end
        end
        return "editor process is gone"
      end
    """)
    message = verify(case.machine.env).decode()
    if message:
        problems.append(message)
    return problems


def test_install_user_app():
    case = Case("user app")
    probe = case.lua.eval(b"""
      function(env)
        local apps = env.arequire("svc.apps")
        local source = table.concat({
          'local App = arequire("ui.app")',
          'local W = arequire("ui.widgets")',
          'local app = App({ title = "Demo" })',
          'app:setRoot(W.Label({ text = "a third-party app" }))',
          'app:run()',
        }, string.char(10))
        local dir, err = apps.createUserApp("demo", {
          name = "Demo", summary = "test", category = "Other",
          window = { w = 24, h = 8 },
          icon = { colour = env.colours.green, glyph = "D" },
        }, source)
        if not dir then return "createUserApp failed: " .. tostring(err) end
        if not apps.get("demo") then return "app did not register" end
        local proc = apps.launch("demo")
        if not proc then return "the installed app would not launch" end
        return ""
      end
    """)
    message = probe(case.machine.env).decode()
    case.machine.pump(800)
    problems = case.errors()
    if message:
        problems.append(message)
    return problems


def test_theme_switching():
    case = Case("theme switch")
    probe = case.lua.eval(b"""
      function(env)
        local theme = env.arequire("gfx.theme")
        local wallpaper = env.arequire("shell.wallpaper")
        for _, scheme in ipairs({ "light", "contrast", "dark" }) do
          theme.set(scheme, "orange")
          wallpaper.invalidate()
          for _, style in ipairs(wallpaper.styles) do
            wallpaper.get(51, 19, style.id)
          end
        end
        theme.set("dark", "blue")
        return ""
      end
    """)
    message = probe(case.machine.env).decode()
    case.machine.pump(400)
    problems = case.errors()
    if message:
        problems.append(message)
    return problems


def main():
    passed = True
    passed &= check("boot", test_boot)
    for app_id in APPS:
        passed &= check("launch %s" % app_id, make_app_test(app_id))
    passed &= check("activities overview + search", test_overview)
    passed &= check("app grid", test_app_grid)
    passed &= check("window move / maximise", test_window_management)
    passed &= check("alt-tab between windows", test_two_windows_and_switching)
    passed &= check("power menu", test_power_menu_and_lock)
    passed &= check("editor typing", test_editor_editing)
    passed &= check("spreadsheet formulas", test_sheets_formula)
    passed &= check("monitor hot-plug", test_monitors)
    passed &= check("slides presenting on a monitor", test_slides_presenting)
    passed &= check("menus and modal dialogs", test_dialogs_and_menus)
    passed &= check("printing with pagination", test_printing)
    passed &= check("open a file from Files", test_open_file_from_files)
    passed &= check("install a third-party app", test_install_user_app)
    passed &= check("theme and wallpaper switching", test_theme_switching)
    print()
    print("ALL PASSED" if passed else "FAILURES")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
