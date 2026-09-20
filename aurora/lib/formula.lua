--[[ aurora.lib.formula ------------------------------------------------------
     The spreadsheet formula engine.

     A formula is any cell whose text starts with "=".  References (A1, $B$2),
     ranges (A1:B9) and a library of functions are compiled into a Lua
     expression and evaluated in a sandbox, with cycle detection so a formula
     that refers to itself reports #CYCLE instead of hanging the computer.
----------------------------------------------------------------------------]]

local util = arequire("lib.util")

local formula = {}

---------------------------------------------------------------- addresses ---

--- "A" -> 1, "Z" -> 26, "AA" -> 27
function formula.columnToIndex(name)
  local n = 0
  for i = 1, #name do
    n = n * 26 + (name:byte(i) - 64)
  end
  return n
end

function formula.indexToColumn(index)
  local name = ""
  while index > 0 do
    local remainder = (index - 1) % 26
    name = string.char(65 + remainder) .. name
    index = math.floor((index - 1) / 26)
  end
  return name
end

function formula.parseRef(ref)
  local col, row = ref:upper():match("^%$?(%a+)%$?(%d+)$")
  if not col then return nil end
  return formula.columnToIndex(col), tonumber(row)
end

function formula.makeRef(col, row)
  return formula.indexToColumn(col) .. row
end

----------------------------------------------------------------- library ----

local function toNumbers(values)
  local out = {}
  for _, v in ipairs(values) do
    local n = tonumber(v)
    if n then out[#out + 1] = n end
  end
  return out
end

local LIB = {}

function LIB.SUM(...)
  local total = 0
  for _, n in ipairs(toNumbers(LIB.__flatten(...))) do total = total + n end
  return total
end

function LIB.AVERAGE(...)
  local numbers = toNumbers(LIB.__flatten(...))
  if #numbers == 0 then return 0 end
  local total = 0
  for _, n in ipairs(numbers) do total = total + n end
  return total / #numbers
end
LIB.AVG = LIB.AVERAGE
LIB.MEAN = LIB.AVERAGE

function LIB.MIN(...)
  local numbers = toNumbers(LIB.__flatten(...))
  if #numbers == 0 then return 0 end
  local best = numbers[1]
  for _, n in ipairs(numbers) do best = math.min(best, n) end
  return best
end

function LIB.MAX(...)
  local numbers = toNumbers(LIB.__flatten(...))
  if #numbers == 0 then return 0 end
  local best = numbers[1]
  for _, n in ipairs(numbers) do best = math.max(best, n) end
  return best
end

function LIB.COUNT(...)
  return #toNumbers(LIB.__flatten(...))
end

function LIB.COUNTA(...)
  local n = 0
  for _, v in ipairs(LIB.__flatten(...)) do
    if v ~= nil and v ~= "" then n = n + 1 end
  end
  return n
end

function LIB.PRODUCT(...)
  local numbers = toNumbers(LIB.__flatten(...))
  local total = 1
  for _, n in ipairs(numbers) do total = total * n end
  return total
end

function LIB.MEDIAN(...)
  local numbers = toNumbers(LIB.__flatten(...))
  if #numbers == 0 then return 0 end
  table.sort(numbers)
  local mid = math.floor(#numbers / 2)
  if #numbers % 2 == 1 then return numbers[mid + 1] end
  return (numbers[mid] + numbers[mid + 1]) / 2
end

function LIB.IF(condition, whenTrue, whenFalse)
  if condition and condition ~= 0 and condition ~= "" then return whenTrue end
  return whenFalse
end

function LIB.ROUND(value, places)
  places = places or 0
  local factor = 10 ^ places
  return math.floor((tonumber(value) or 0) * factor + 0.5) / factor
end

function LIB.ABS(v) return math.abs(tonumber(v) or 0) end
function LIB.FLOOR(v) return math.floor(tonumber(v) or 0) end
function LIB.CEIL(v) return math.ceil(tonumber(v) or 0) end
function LIB.SQRT(v) return math.sqrt(math.max(0, tonumber(v) or 0)) end
function LIB.POW(a, b) return (tonumber(a) or 0) ^ (tonumber(b) or 0) end
function LIB.LEN(v) return #tostring(v or "") end
function LIB.UPPER(v) return tostring(v or ""):upper() end
function LIB.LOWER(v) return tostring(v or ""):lower() end
function LIB.TRIM(v) return util.trim(tostring(v or "")) end

function LIB.CONCAT(...)
  local parts = {}
  for _, v in ipairs(LIB.__flatten(...)) do parts[#parts + 1] = tostring(v) end
  return table.concat(parts)
end

function LIB.PI() return math.pi end

function LIB.__flatten(...)
  local out = {}
  local function push(value)
    if type(value) == "table" then
      for _, v in ipairs(value) do push(v) end
    elseif value ~= nil then
      out[#out + 1] = value
    end
  end
  for _, value in ipairs(table.pack(...)) do push(value) end
  return out
end

formula.functions = LIB

--------------------------------------------------------------- evaluation ---

local ERROR_PREFIX = "#"

--- Rewrite a formula body (everything after "=") into a Lua expression.
--- Cell references become __cell("A1") and ranges become __range("A1","B9").
--- Returns the Lua source and the list of references it touches.
local function translate(body)
  local refs = {}
  local slots = {}

  -- Park string literals and ranges in numbered slots first.  "@n@" contains
  -- no letters, so the cell-reference pattern below cannot match inside one,
  -- which is what stops =SUM(A1:A3) rewriting the A1 inside __range("A1",...).
  local function park(text)
    slots[#slots + 1] = text
    return "@" .. #slots .. "@"
  end

  local expression = body:gsub('"[^"]*"', park):gsub("'[^']*'", park)

  expression = expression:gsub("(%$?%a+%$?%d+)%s*:%s*(%$?%a+%$?%d+)", function(a, b)
    if not (formula.parseRef(a) and formula.parseRef(b)) then return nil end
    refs[#refs + 1] = { kind = "range", from = a, to = b }
    return park(("__range(%q,%q)"):format(a, b))
  end)

  expression = expression:gsub("(%$?%a+%$?%d+)", function(ref)
    if formula.parseRef(ref) then
      refs[#refs + 1] = { kind = "cell", ref = ref }
      return ("__cell(%q)"):format(ref)
    end
    return ref
  end)

  -- spreadsheet operators -> Lua
  expression = expression:gsub("<>", "~=")
  expression = expression:gsub("([^=~<>])=([^=])", "%1==%2")
  expression = expression:gsub("&", "..")

  -- put the parked pieces back
  expression = expression:gsub("@(%d+)@", function(index)
    return slots[tonumber(index)]
  end)

  return expression, refs
end

formula.translate = translate

--- Check a formula without evaluating it.  Returns true, or false + message.
function formula.check(body)
  local expression = translate(body)
  local chunk, err = load("return " .. expression, "=formula", "t", {})
  if chunk then return true end
  return false, tostring(err):gsub("^.-:%d+:%s*", "")
end

--- Evaluate a sheet cell.
--- @param sheet table  { cells = { ["A1"] = { text = }, ... } }
--- @param ref string
--- @param visiting table internal cycle tracker
function formula.evaluate(sheet, ref, visiting)
  ref = ref:upper():gsub("%$", "")
  visiting = visiting or {}

  local cell = sheet.cells[ref]
  if not cell or cell.text == nil or cell.text == "" then return "" end

  local text = cell.text
  if text:sub(1, 1) ~= "=" then
    local number = tonumber(text)
    return number or text
  end

  if visiting[ref] then return ERROR_PREFIX .. "CYCLE" end
  visiting[ref] = true

  local env = {
    math = math, string = string, table = table, tonumber = tonumber,
    tostring = tostring, TRUE = true, FALSE = false,
  }
  for name, fn in pairs(LIB) do
    if not name:match("^__") then env[name] = fn end
  end

  env.__cell = function(cellRef)
    local value = formula.evaluate(sheet, cellRef, visiting)
    if type(value) == "string" and value:sub(1, 1) == ERROR_PREFIX then
      error(value, 0)
    end
    if value == "" then return 0 end
    return value
  end

  env.__range = function(from, to)
    local c1, r1 = formula.parseRef(from)
    local c2, r2 = formula.parseRef(to)
    if not c1 or not c2 then error(ERROR_PREFIX .. "REF", 0) end
    if c1 > c2 then c1, c2 = c2, c1 end
    if r1 > r2 then r1, r2 = r2, r1 end
    local values = {}
    for row = r1, r2 do
      for col = c1, c2 do
        local value = formula.evaluate(sheet, formula.makeRef(col, row), visiting)
        if type(value) == "string" and value:sub(1, 1) == ERROR_PREFIX then
          error(value, 0)
        end
        if value ~= "" then values[#values + 1] = value end
      end
    end
    return values
  end

  local expression = translate(text:sub(2))
  local chunk = load("return " .. expression, "=formula", "t", env)

  local result
  if not chunk then
    result = ERROR_PREFIX .. "SYNTAX"
  else
    local ok, value = pcall(chunk)
    if not ok then
      local message = tostring(value)
      result = message:sub(1, 1) == ERROR_PREFIX and message or (ERROR_PREFIX .. "ERROR")
    elseif type(value) == "table" then
      -- a bare range collapses to its sum, like most spreadsheets
      result = LIB.SUM(value)
    elseif value == nil then
      result = ""
    else
      result = value
    end
  end

  visiting[ref] = nil
  return result
end

--- Format a computed value for display in a cell.
function formula.format(value, width, align)
  if value == nil then return "" end
  if type(value) == "boolean" then return value and "TRUE" or "FALSE" end
  if type(value) == "number" then
    if value ~= value then return "#NAN" end
    if value == math.floor(value) and math.abs(value) < 1e10 then
      return tostring(math.floor(value))
    end
    local text = string.format("%.4f", value):gsub("0+$", ""):gsub("%.$", "")
    return text
  end
  return tostring(value)
end

return formula
