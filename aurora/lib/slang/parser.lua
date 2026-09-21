--[[ aurora.lib.slang.parser ------------------------------------------------
     SimpleLang: lexer and parser.

     The language reads like instructions you would give a person:

        set score to 0
        to greet with who
          say "hi " + who
        end
        call greet with "kai"
        repeat 3 times
          set score to score + 1
        end

     This file turns source text into an abstract syntax tree.  Errors carry a
     line number and a plain-English message.
----------------------------------------------------------------------------]]

local util = arequire("lib.util")

local parser = {}

----------------------------------------------------------------- the lexer --

local KEYWORDS = {}
for word in ([[set to say ask if then else end while repeat times for from with
call give stop and or not true false nothing use forever do]]):gmatch("%S+") do
  KEYWORDS[word] = true
end
parser.keywords = KEYWORDS

local SYMBOLS = {
  "==", "~=", "!=", "<=", ">=", "..",
  "+", "-", "*", "/", "%", "<", ">", "=", "(", ")", "[", "]", ",", ":",
}

local function fail(line, message)
  error({ slang = true, line = line, message = message }, 0)
end

--- Turn source into tokens:
--- { kind = "name"|"number"|"string"|"keyword"|"symbol"|"eof", value, line }
function parser.lex(source)
  source = tostring(source or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local tokens = {}
  local i, line = 1, 1
  local length = #source

  local function push(kind, value)
    tokens[#tokens + 1] = { kind = kind, value = value, line = line }
  end

  while i <= length do
    local char = source:sub(i, i)

    if char == "\n" then
      line = line + 1
      i = i + 1
    elseif char == " " or char == "\t" then
      i = i + 1
    elseif char == "#" then
      while i <= length and source:sub(i, i) ~= "\n" do i = i + 1 end
    elseif char:match("%d") then
      local start = i
      while i <= length and source:sub(i, i):match("[%d%.]") do i = i + 1 end
      local text = source:sub(start, i - 1)
      local number = tonumber(text)
      if not number then fail(line, text .. " is not a number") end
      push("number", number)
    elseif char:match("[%a_]") then
      local start = i
      while i <= length and source:sub(i, i):match("[%w_]") do i = i + 1 end
      local word = source:sub(start, i - 1)
      push(KEYWORDS[word] and "keyword" or "name", word)
    elseif char == '"' or char == "'" then
      local quote = char
      i = i + 1
      local out = {}
      while true do
        if i > length then fail(line, "this text is missing its closing quote") end
        local c = source:sub(i, i)
        if c == quote then i = i + 1 break end
        if c == "\n" then fail(line, "this text is missing its closing quote") end
        if c == "\\" then
          local nextChar = source:sub(i + 1, i + 1)
          local map = { n = "\n", t = "\t" }
          out[#out + 1] = map[nextChar] or nextChar
          i = i + 2
        else
          out[#out + 1] = c
          i = i + 1
        end
      end
      push("string", table.concat(out))
    else
      local matched
      for _, symbol in ipairs(SYMBOLS) do
        if source:sub(i, i + #symbol - 1) == symbol then matched = symbol break end
      end
      if not matched then
        fail(line, "I do not understand " .. char .. " here")
      end
      push("symbol", matched)
      i = i + #matched
    end
  end

  tokens[#tokens + 1] = { kind = "eof", value = "<end>", line = line }
  return tokens
end

---------------------------------------------------------------- the parser --

local Parser = util.class()

function Parser:init(tokens)
  self.tokens = tokens
  self.pos = 1
end

function Parser:peek(offset)
  return self.tokens[self.pos + (offset or 0)] or self.tokens[#self.tokens]
end

function Parser:next()
  local token = self:peek()
  self.pos = self.pos + 1
  return token
end

function Parser:check(kind, value)
  local token = self:peek()
  if token.kind ~= kind then return false end
  if value ~= nil and token.value ~= value then return false end
  return true
end

function Parser:accept(kind, value)
  if self:check(kind, value) then return self:next() end
  return nil
end

function Parser:expect(kind, value, what)
  if self:check(kind, value) then return self:next() end
  local token = self:peek()
  fail(token.line, "expected " .. (what or value or kind)
       .. " but found " .. tostring(token.value))
end

function Parser:kw(word) return self:accept("keyword", word) end

------------------------------------------------------------- expressions ---

local COMPARISONS = {
  ["=="] = "eq", ["~="] = "ne", ["!="] = "ne",
  ["<"] = "lt", ["<="] = "le", [">"] = "gt", [">="] = "ge",
}

function Parser:parseExpression() return self:parseOr() end

function Parser:parseOr()
  local left = self:parseAnd()
  while self:check("keyword", "or") do
    local line = self:next().line
    left = { kind = "logic", op = "or", left = left, right = self:parseAnd(), line = line }
  end
  return left
end

function Parser:parseAnd()
  local left = self:parseComparison()
  while self:check("keyword", "and") do
    local line = self:next().line
    left = { kind = "logic", op = "and", left = left,
             right = self:parseComparison(), line = line }
  end
  return left
end

function Parser:parseComparison()
  local left = self:parseSum()
  local token = self:peek()
  -- a lone "=" where a comparison belongs is a common slip; accept it
  if token.kind == "symbol" and (COMPARISONS[token.value] or token.value == "=") then
    self:next()
    return { kind = "compare", op = COMPARISONS[token.value] or "eq",
             left = left, right = self:parseSum(), line = token.line }
  end
  return left
end

function Parser:parseSum()
  local left = self:parseProduct()
  while true do
    local token = self:peek()
    if token.kind == "symbol"
       and (token.value == "+" or token.value == "-" or token.value == "..") then
      self:next()
      local op = token.value == "+" and "add"
                 or (token.value == "-" and "sub" or "concat")
      left = { kind = "binary", op = op, left = left,
               right = self:parseProduct(), line = token.line }
    else
      return left
    end
  end
end

function Parser:parseProduct()
  local left = self:parseUnary()
  while true do
    local token = self:peek()
    if token.kind == "symbol"
       and (token.value == "*" or token.value == "/" or token.value == "%") then
      self:next()
      local op = token.value == "*" and "mul"
                 or (token.value == "/" and "div" or "mod")
      left = { kind = "binary", op = op, left = left,
               right = self:parseUnary(), line = token.line }
    else
      return left
    end
  end
end

function Parser:parseUnary()
  local token = self:peek()
  if token.kind == "keyword" and token.value == "not" then
    self:next()
    return { kind = "unary", op = "not", value = self:parseUnary(), line = token.line }
  end
  if token.kind == "symbol" and token.value == "-" then
    self:next()
    return { kind = "unary", op = "neg", value = self:parseUnary(), line = token.line }
  end
  return self:parsePostfix()
end

function Parser:parsePostfix()
  local expression = self:parsePrimary()
  while self:check("symbol", "[") do
    local line = self:next().line
    local index = self:parseExpression()
    self:expect("symbol", "]", "a closing bracket")
    expression = { kind = "index", target = expression, index = index, line = line }
  end
  return expression
end

function Parser:parseArguments()
  local args = {}
  self:expect("symbol", "(", "an opening bracket")
  if not self:check("symbol", ")") then
    repeat
      args[#args + 1] = self:parseExpression()
    until not self:accept("symbol", ",")
  end
  self:expect("symbol", ")", "a closing bracket")
  return args
end

function Parser:parsePrimary()
  local token = self:peek()

  if token.kind == "number" then
    self:next()
    return { kind = "number", value = token.value, line = token.line }
  end
  if token.kind == "string" then
    self:next()
    return { kind = "string", value = token.value, line = token.line }
  end
  if token.kind == "keyword" then
    if token.value == "true" or token.value == "false" then
      self:next()
      return { kind = "boolean", value = token.value == "true", line = token.line }
    end
    if token.value == "nothing" then
      self:next()
      return { kind = "nothing", line = token.line }
    end
  end
  if self:check("symbol", "(") then
    self:next()
    local inner = self:parseExpression()
    self:expect("symbol", ")", "a closing bracket")
    return inner
  end
  if self:check("symbol", "[") then
    local line = self:next().line
    local items = {}
    if not self:check("symbol", "]") then
      repeat
        items[#items + 1] = self:parseExpression()
      until not self:accept("symbol", ",")
    end
    self:expect("symbol", "]", "a closing bracket")
    return { kind = "list", items = items, line = line }
  end
  if token.kind == "name" then
    self:next()
    if self:check("symbol", "(") then
      return { kind = "call", name = token.value,
               args = self:parseArguments(), line = token.line }
    end
    return { kind = "name", name = token.value, line = token.line }
  end

  fail(token.line, "I did not expect " .. tostring(token.value) .. " here")
end

-------------------------------------------------------------- statements ---

function Parser:parseBlock(...)
  local stops = {}
  for _, word in ipairs({ ... }) do stops[word] = true end
  local body = {}
  while true do
    local token = self:peek()
    if token.kind == "eof" then break end
    if token.kind == "keyword" and stops[token.value] then break end
    body[#body + 1] = self:parseStatement()
  end
  return body
end

function Parser:parseStatement()
  local token = self:peek()

  if token.kind == "keyword" then
    local word = token.value

    if word == "set" then
      self:next()
      local target = self:parsePostfix()
      self:expect("keyword", "to", "the word 'to'")
      local value = self:parseExpression()
      if target.kind == "name" then
        return { kind = "assign", name = target.name, value = value, line = token.line }
      elseif target.kind == "index" then
        return { kind = "setindex", target = target.target, index = target.index,
                 value = value, line = token.line }
      end
      fail(token.line, "you can only set a name or a list item")

    elseif word == "say" then
      self:next()
      local args = { self:parseExpression() }
      while self:accept("symbol", ",") do
        args[#args + 1] = self:parseExpression()
      end
      return { kind = "say", args = args, line = token.line }

    elseif word == "ask" then
      self:next()
      local name = self:expect("name", nil, "a name to keep the answer in").value
      local prompt
      if self:check("string") then prompt = self:next().value end
      return { kind = "ask", name = name, prompt = prompt, line = token.line }

    elseif word == "if" then
      self:next()
      local condition = self:parseExpression()
      self:kw("then")
      local body = self:parseBlock("else", "end")
      local otherwise
      if self:kw("else") then
        if self:check("keyword", "if") then
          -- "else if" chains without needing an extra end
          return { kind = "if", condition = condition, body = body,
                   otherwise = { self:parseStatement() }, line = token.line }
        end
        otherwise = self:parseBlock("end")
      end
      self:expect("keyword", "end", "the word 'end'")
      return { kind = "if", condition = condition, body = body,
               otherwise = otherwise, line = token.line }

    elseif word == "while" then
      self:next()
      local condition = self:parseExpression()
      self:kw("do")
      local body = self:parseBlock("end")
      self:expect("keyword", "end", "the word 'end'")
      return { kind = "while", condition = condition, body = body, line = token.line }

    elseif word == "forever" then
      self:next()
      local body = self:parseBlock("end")
      self:expect("keyword", "end", "the word 'end'")
      return { kind = "while", condition = { kind = "boolean", value = true },
               body = body, line = token.line }

    elseif word == "repeat" then
      self:next()
      local count = self:parseExpression()
      self:expect("keyword", "times", "the word 'times'")
      local body = self:parseBlock("end")
      self:expect("keyword", "end", "the word 'end'")
      return { kind = "repeat", count = count, body = body, line = token.line }

    elseif word == "for" then
      self:next()
      local name = self:expect("name", nil, "a loop name").value
      self:expect("keyword", "from", "the word 'from'")
      local from = self:parseExpression()
      self:expect("keyword", "to", "the word 'to'")
      local to = self:parseExpression()
      local body = self:parseBlock("end")
      self:expect("keyword", "end", "the word 'end'")
      return { kind = "for", name = name, from = from, to = to,
               body = body, line = token.line }

    elseif word == "to" then
      self:next()
      local name = self:expect("name", nil, "a name for this action").value
      local params = {}
      if self:kw("with") then
        repeat
          params[#params + 1] = self:expect("name", nil, "a parameter name").value
        until not self:accept("symbol", ",")
      end
      local body = self:parseBlock("end")
      self:expect("keyword", "end", "the word 'end'")
      return { kind = "function", name = name, params = params,
               body = body, line = token.line }

    elseif word == "call" then
      self:next()
      local name = self:expect("name", nil, "the name of an action").value
      local args = {}
      if self:kw("with") then
        repeat
          args[#args + 1] = self:parseExpression()
        until not self:accept("symbol", ",")
      elseif self:check("symbol", "(") then
        args = self:parseArguments()
      end
      return { kind = "callstmt", name = name, args = args, line = token.line }

    elseif word == "give" then
      self:next()
      local value
      if not (self:check("keyword", "end") or self:peek().kind == "eof") then
        value = self:parseExpression()
      end
      return { kind = "give", value = value, line = token.line }

    elseif word == "stop" then
      self:next()
      return { kind = "stop", line = token.line }

    elseif word == "use" then
      self:next()
      local name = self:next()
      return { kind = "use", name = tostring(name.value), line = token.line }
    end
  end

  local expression = self:parseExpression()
  return { kind = "expression", value = expression, line = token.line }
end

------------------------------------------------------------------ public ---

--- Parse source into an AST, or return nil plus an error table.
function parser.parse(source)
  local ok, result = pcall(function()
    local p = Parser(parser.lex(source))
    local body = p:parseBlock()
    if p:peek().kind ~= "eof" then
      fail(p:peek().line, "unexpected " .. tostring(p:peek().value))
    end
    return body
  end)
  if ok then return result end
  if type(result) == "table" and result.slang then return nil, result end
  return nil, { line = 0, message = tostring(result) }
end

return parser
