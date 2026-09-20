--[[ aurora/boot.lua ---------------------------------------------------------
     Bootloader.  Installs the module loader, paints the splash, hands over to
     the kernel, and decides what to do when the kernel returns.
----------------------------------------------------------------------------]]

local ROOT = "/aurora"

-------------------------------------------------------------- module loader --

-- A tiny require() that keeps every Aurora module in one cache and gives
-- modules the real globals.  Exposed as a global so processes can use it too.
do
  local cache = {}
  local loading = {}

  local function arequire(name)
    local cached = cache[name]
    if cached ~= nil then return cached end
    if loading[name] then
      error("circular module dependency: " .. name, 2)
    end

    local path = ROOT .. "/" .. name:gsub("%.", "/") .. ".lua"
    if not fs.exists(path) then
      error("module not found: " .. name .. " (" .. path .. ")", 2)
    end

    local handle = fs.open(path, "r")
    local source = handle.readAll()
    handle.close()

    local chunk, err = load(source, "@" .. path, "t", _G)
    if not chunk then
      error("could not compile " .. name .. ": " .. tostring(err), 2)
    end

    loading[name] = true
    local ok, result = pcall(chunk, name)
    loading[name] = nil
    if not ok then
      error("error loading " .. name .. ": " .. tostring(result), 2)
    end

    cache[name] = result == nil and true or result
    return cache[name]
  end

  _G.arequire = arequire
  _G.aureload = function(name)
    cache[name] = nil
    return arequire(name)
  end
end

--------------------------------------------------------------- boot splash --

local function splash()
  local Surface = arequire("gfx.surface")
  local theme   = arequire("gfx.theme")
  local pixel   = arequire("gfx.pixel")

  theme.load()
  local out = term.native()
  theme.applyTo(out)

  local w, h = out.getSize()
  local surface = Surface(w, h, theme.c.desktop, theme.c.text)
  local prev = { t = {}, f = {}, b = {} }

  local function present()
    for y = 1, h do
      if surface.t[y] ~= prev.t[y] or surface.f[y] ~= prev.f[y] or surface.b[y] ~= prev.b[y] then
        out.setCursorPos(1, y)
        out.blit(surface.t[y], surface.f[y], surface.b[y])
        prev.t[y], prev.f[y], prev.b[y] = surface.t[y], surface.f[y], surface.b[y]
      end
    end
  end

  pcall(out.setCursorBlink, false)

  local logoW = math.min(w - 4, 24)
  local logoX = math.floor((w - logoW) / 2) + 1
  local logoY = math.max(2, math.floor(h / 2) - 3)

  local function paint(step, fraction, failure)
    surface:clear(theme.c.desktop, theme.c.text)

    local canvas = pixel.Canvas(logoW, 3, theme.c.desktop)
    local tw = pixel.textWidth("AURORA")
    canvas:text(math.floor((canvas.w - tw) / 2) + 1, 2, "AURORA", theme.c.accent)
    canvas:render(surface, logoX, logoY)

    surface:writeCentered(logoY + 4, "operating system", theme.c.dim, theme.c.desktop)

    -- progress track
    local barW = math.min(w - 8, 30)
    local barX = math.floor((w - barW) / 2) + 1
    local barY = math.min(h - 3, logoY + 7)
    surface:fill(barX, barY, barW, 1, "\140", theme.c.active, theme.c.desktop)
    local filled = math.floor(barW * (fraction or 0) + 0.5)
    if filled > 0 then
      surface:fill(barX, barY, filled, 1, "\140", theme.c.accent, theme.c.desktop)
    end

    surface:writeCentered(barY + 2, step or "", failure and theme.c.destructive or theme.c.dim,
                          theme.c.desktop)
    present()
  end

  return paint
end

------------------------------------------------------------------- run it --

local function main()
  -- Tells /startup.lua not to boot us again from a nested CraftOS shell.
  _G.AURORA_RUNNING = true

  local paint = splash()
  local kernel = arequire("kernel.init")
  local log = arequire("kernel.log")

  log.info("boot", ("Aurora %s (%s) starting on computer %d")
    :format(kernel.VERSION, kernel.CODENAME, os.getComputerID()))

  local reason = kernel.start(function(step, fraction, failure)
    paint(step, fraction, failure)
    if failure then os.sleep(0.6) end
  end)

  return reason
end

local ok, result = pcall(main)
_G.AURORA_RUNNING = nil

if not ok then
  local kernelOk, kernel = pcall(arequire, "kernel.init")
  if kernelOk and kernel and kernel.panic then
    kernel.panic(result)
    kernel.teardown()
  else
    term.native().setBackgroundColour(colours.black)
    term.native().setTextColour(colours.red)
    term.native().clear()
    term.native().setCursorPos(1, 1)
    print("Aurora failed to start:")
    print(tostring(result))
  end
  return
end

if result == "restart" then
  os.reboot()
elseif result == "shutdown" then
  os.shutdown()
end
-- "exit" simply falls through to the CraftOS shell
