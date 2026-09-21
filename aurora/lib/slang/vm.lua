--[[ aurora.lib.slang.vm ----------------------------------------------------
     SimpleLang: the virtual machine, and the host functions it can reach.

     A small stack machine.  Labels are resolved once at load time, then the
     interpreter is a flat loop over the instruction list.  Host functions are
     what make the language useful: they are how a .sl program talks to
     Aurora's screen, files, network and peripherals.
----------------------------------------------------------------------------]]

local util = arequire("lib.util")

local vm = {}

vm.STEP_LIMIT = 2000000    -- stops a runaway loop from freezing the computer

local function fail(state, message)
  error({ slang = true, runtime = true, line = state.line or 0, message = message }, 0)
end

local function truthy(value)
  return value ~= nil and value ~= false
end

function vm.describe(value)
  local kind = type(value)
  if kind == "nil" then return "nothing" end
  if kind == "string" then return '"' .. value .. '"' end
  if kind == "table" then return "a list of " .. #value end
  return tostring(value)
end

--- How SimpleLang prints a value.
function vm.tostring(value)
  if value == nil then return "nothing" end
  if type(value) == "boolean" then return value and "true" or "false" end
  if type(value) == "number" then
    if value == math.floor(value) and math.abs(value) < 1e14 then
      return tostring(math.floor(value))
    end
    local text = ("%.6f"):format(value)
    text = text:gsub("0+$", "")
    text = text:gsub("%.$", "")
    return text
  end
  if type(value) == "table" then
    local parts = {}
    for _, item in ipairs(value) do parts[#parts + 1] = vm.tostring(item) end
    return "[" .. table.concat(parts, ", ") .. "]"
  end
  return tostring(value)
end

local function asNumber(state, value, what)
  local number = tonumber(value)
  if not number then
    fail(state, (what or "this") .. " needs a number, not " .. vm.describe(value))
  end
  return number
end

----------------------------------------------------------------- loading ---

--- Resolve labels to instruction indices.  Returns program, or nil + error.
function vm.link(program)
  for name, fn in pairs(program.funcs) do
    local labels, code = {}, {}
    for _, instruction in ipairs(fn.code) do
      if instruction.label then
        labels[instruction.label] = #code + 1
      else
        code[#code + 1] = instruction
      end
    end
    for _, instruction in ipairs(code) do
      local op = instruction.op
      if op == "JMP" or op == "JMPF" or op == "JMPT" then
        local target = labels[instruction.a]
        if not target then
          return nil, { line = instruction.line or 0,
                        message = op .. " points at a missing label "
                                  .. tostring(instruction.a) .. " in " .. name }
        end
        instruction.target = target
      end
    end
    fn.linked = code
    fn.labels = labels
  end
  return program
end

------------------------------------------------------------ host bindings --

--- Build the table of host functions a program can call.
--- `io` supplies the screen and input; everything else is optional.
function vm.hostFunctions(io)
  io = io or {}
  local host = {}

  local function output(text)
    if io.write then io.write(text) else print(text) end
  end

  host.say = function(state, args)
    local parts = {}
    for _, value in ipairs(args) do parts[#parts + 1] = vm.tostring(value) end
    output(table.concat(parts, " "))
    return nil
  end

  host.ask = function(state, args)
    if io.ask then return io.ask(vm.tostring(args[1] or "")) end
    return ""
  end

  host.wait = function(state, args)
    local seconds = tonumber(args[1]) or 0
    if io.wait then io.wait(seconds) else os.sleep(seconds) end
    return nil
  end

  host.clear = function() if io.clear then io.clear() end return nil end

  host.draw = function(state, args)
    if io.draw then
      io.draw(tonumber(args[1]) or 1, tonumber(args[2]) or 1,
              vm.tostring(args[3] or ""), args[4], args[5])
    end
    return nil
  end

  host.colour = function(state, args)
    if io.colour then io.colour(args[1], args[2]) end
    return nil
  end
  host.color = host.colour

  host.key = function() return io.key and io.key() or nil end
  host.width = function() return io.size and (select(1, io.size())) or 51 end
  host.height = function() return io.size and (select(2, io.size())) or 19 end

  -- numbers and text -------------------------------------------------------
  host.random = function(state, args)
    local low, high = tonumber(args[1]), tonumber(args[2])
    if low and high then return math.random(math.floor(low), math.floor(high)) end
    if low then return math.random(1, math.floor(low)) end
    return math.random()
  end
  host.floor = function(state, args) return math.floor(asNumber(state, args[1], "floor")) end
  host.round = function(state, args) return math.floor(asNumber(state, args[1], "round") + 0.5) end
  host.abs = function(state, args) return math.abs(asNumber(state, args[1], "abs")) end
  host.min = function(state, args)
    local best
    for _, value in ipairs(args) do
      local n = asNumber(state, value, "min")
      if not best or n < best then best = n end
    end
    return best
  end
  host.max = function(state, args)
    local best
    for _, value in ipairs(args) do
      local n = asNumber(state, value, "max")
      if not best or n > best then best = n end
    end
    return best
  end
  host.number = function(state, args) return tonumber(args[1]) end
  host.text = function(state, args) return vm.tostring(args[1]) end
  host.upper = function(state, args) return vm.tostring(args[1]):upper() end
  host.lower = function(state, args) return vm.tostring(args[1]):lower() end
  host.len = function(state, args)
    if type(args[1]) == "table" then return #args[1] end
    return #vm.tostring(args[1])
  end
  host.length = host.len
  host.piece = function(state, args)
    return vm.tostring(args[1]):sub(math.floor(tonumber(args[2]) or 1),
                                    math.floor(tonumber(args[3]) or -1))
  end
  host.find = function(state, args)
    return vm.tostring(args[1]):find(vm.tostring(args[2]), 1, true) or 0
  end

  -- lists ------------------------------------------------------------------
  host.add = function(state, args)
    if type(args[1]) ~= "table" then fail(state, "add needs a list") end
    args[1][#args[1] + 1] = args[2]
    return args[1]
  end
  host.removeat = function(state, args)
    if type(args[1]) ~= "table" then fail(state, "removeat needs a list") end
    return table.remove(args[1], math.floor(tonumber(args[2]) or #args[1]))
  end
  host.list = function() return {} end

  -- the computer -----------------------------------------------------------
  host.readfile = function(state, args) return util.readFile(vm.tostring(args[1])) end
  host.writefile = function(state, args)
    return util.writeFile(vm.tostring(args[1]), vm.tostring(args[2] or ""))
  end
  host.exists = function(state, args) return fs.exists(vm.tostring(args[1])) end
  host.listdir = function(state, args)
    local path = vm.tostring(args[1] or "/home")
    if not fs.isDir(path) then return {} end
    local out = {}
    for _, name in ipairs(fs.list(path)) do out[#out + 1] = name end
    return out
  end
  host.now = function() return os.clock() end
  host.time = function() return util.clock() end
  host.myid = function() return os.getComputerID() end

  host.notify = function(state, args)
    arequire("shell.desktop").notify(vm.tostring(args[1] or "SimpleLang"),
                                     vm.tostring(args[2] or ""))
    return nil
  end

  host.send = function(state, args)
    local id = tonumber(args[1])
    if not id then fail(state, "send needs a computer id") end
    return (arequire("svc.messages").send(id, vm.tostring(args[2] or "")))
  end

  host.run = function(state, args)
    return arequire("svc.apps").launch(vm.tostring(args[1])) ~= nil
  end

  if io.extra then
    for name, fn in pairs(io.extra) do host[name] = fn end
  end

  return host
end

------------------------------------------------------------------ running --

local ARITH = {
  ADD = function(a, b) return a + b end,
  SUB = function(a, b) return a - b end,
  MUL = function(a, b) return a * b end,
  DIV = function(a, b) return a / b end,
  MOD = function(a, b) return a % b end,
}

--- Run a linked program.  Returns true, or false plus an error table.
function vm.run(program, opts)
  opts = opts or {}
  local host = opts.host or vm.hostFunctions(opts.io)
  local globals = opts.globals or {}
  local stepLimit = opts.stepLimit or vm.STEP_LIMIT
  local state = { line = 0, steps = 0 }

  local function call(name, args, depth)
    if depth > 64 then fail(state, "too many nested calls") end
    local fn = program.funcs[name]
    if not fn then fail(state, "there is no action called " .. tostring(name)) end

    local locals = {}
    for index, param in ipairs(fn.params) do locals[param] = args[index] end

    local stack, top, pc = {}, 0, 1
    local code = fn.linked or fn.code

    local function push(value) top = top + 1 stack[top] = value end
    local function pop()
      if top < 1 then fail(state, "the program ran out of values to work with") end
      local value = stack[top]
      stack[top] = nil
      top = top - 1
      return value
    end

    while true do
      state.steps = state.steps + 1
      if state.steps > stepLimit then
        fail(state, "this program ran too long, so it was stopped")
      end

      local instruction = code[pc]
      if not instruction then return nil end
      state.line = instruction.line or state.line
      local op = instruction.op
      pc = pc + 1

      if op == "PUSH" then push(instruction.a)
      elseif op == "PUSHNIL" then push(nil)
      elseif op == "POP" then pop()
      elseif op == "DUP" then
        local value = pop()
        push(value)
        push(value)

      elseif op == "LOAD" then
        local key = instruction.a
        if locals[key] ~= nil then push(locals[key])
        elseif globals[key] ~= nil then push(globals[key])
        else push(nil) end

      elseif op == "STORE" then
        local value = pop()
        locals[instruction.a] = value
        globals[instruction.a] = value

      elseif ARITH[op] then
        local right, left = pop(), pop()
        if op == "ADD" and (type(left) == "string" or type(right) == "string") then
          push(vm.tostring(left) .. vm.tostring(right))
        else
          local a = asNumber(state, left, op:lower())
          local b = asNumber(state, right, op:lower())
          if (op == "DIV" or op == "MOD") and b == 0 then
            fail(state, "you cannot divide by zero")
          end
          push(ARITH[op](a, b))
        end

      elseif op == "CONCAT" then
        local right, left = pop(), pop()
        push(vm.tostring(left) .. vm.tostring(right))

      elseif op == "EQ" then local b, a = pop(), pop() push(a == b)
      elseif op == "NE" then local b, a = pop(), pop() push(a ~= b)
      elseif op == "LT" or op == "LE" or op == "GT" or op == "GE" then
        local right, left = pop(), pop()
        local a, b
        if type(left) == "string" and type(right) == "string" then
          a, b = left, right
        else
          a = asNumber(state, left, "comparing")
          b = asNumber(state, right, "comparing")
        end
        if op == "LT" then push(a < b)
        elseif op == "LE" then push(a <= b)
        elseif op == "GT" then push(a > b)
        else push(a >= b) end

      elseif op == "NOT" then push(not truthy(pop()))
      elseif op == "NEG" then push(-asNumber(state, pop(), "minus"))

      elseif op == "JMP" then pc = instruction.target
      elseif op == "JMPF" then if not truthy(pop()) then pc = instruction.target end
      elseif op == "JMPT" then if truthy(pop()) then pc = instruction.target end

      elseif op == "NEWLIST" then push({})
      elseif op == "APPEND" then
        local value = pop()
        local list = stack[top]
        if type(list) ~= "table" then fail(state, "you can only add to a list") end
        list[#list + 1] = value
      elseif op == "INDEX" then
        local index, target = pop(), pop()
        if type(target) == "table" then
          push(target[math.floor(tonumber(index) or 0)])
        elseif type(target) == "string" then
          local at = math.floor(tonumber(index) or 0)
          push(target:sub(at, at))
        else
          fail(state, "only lists and text can be indexed")
        end
      elseif op == "SETINDEX" then
        local value, index, target = pop(), pop(), pop()
        if type(target) ~= "table" then
          fail(state, "only lists can be changed by position")
        end
        target[math.floor(tonumber(index) or 0)] = value

      elseif op == "CALL" then
        local count = instruction.b or 0
        local args2 = {}
        for i = count, 1, -1 do args2[i] = pop() end
        push(call(instruction.a, args2, depth + 1))

      elseif op == "HOST" then
        local count = instruction.b or 0
        local args2 = {}
        for i = count, 1, -1 do args2[i] = pop() end
        local fnHost = host[instruction.a]
        if fnHost then
          push(fnHost(state, args2))
        elseif program.funcs[instruction.a] then
          -- The compiler could not see this action yet -- it came from a
          -- library linked in afterwards -- so resolve it now.
          push(call(instruction.a, args2, depth + 1))
        else
          fail(state, "there is no action called " .. tostring(instruction.a))
        end

      elseif op == "RET" then return pop()
      elseif op == "HALT" then return nil
      else fail(state, "unknown instruction " .. tostring(op))
      end
    end
  end

  local ok, err = pcall(call, program.main or "main", {}, 0)
  if ok then return true end
  if type(err) == "table" and err.slang then return false, err end
  return false, { line = state.line, message = tostring(err), runtime = true }
end

return vm
