--[[ aurora.lib.syntax -------------------------------------------------------
     Line-based syntax highlighting.  Each highlighter takes a line of text and
     returns a blit foreground string of the same length, so TextView can hand
     it straight to term.blit.
----------------------------------------------------------------------------]]

local Surface = arequire("gfx.surface")
local theme   = arequire("gfx.theme")

local syntax = {}

local LUA_KEYWORDS = {}
for word in ([[and break do else elseif end false for function goto if in local
nil not or repeat return then true until while]]):gmatch("%S+") do
  LUA_KEYWORDS[word] = true
end

local LUA_BUILTINS = {}
for word in ([[assert collectgarbage dofile error getmetatable ipairs load
loadstring next pairs pcall print rawequal rawget rawlen rawset require select
setmetatable tonumber tostring type unpack xpcall coroutine string table math os
io fs term colours colors peripheral redstone rednet http textutils keys
parallel vector window paintutils settings shell multishell disk gps help
commands turtle pocket aurora arequire self]]):gmatch("%S+") do
  LUA_BUILTINS[word] = true
end

--- Build a run of one colour.
local function run(colour, n)
  return string.rep(Surface.blitChar(colour), n)
end

--- Lua highlighter.
--- Handles comments, strings (including [[ ]]), numbers, keywords, builtins
--- and function-call names.  Multi-line strings are approximated per line,
--- which is the right trade-off for a character-cell editor.
function syntax.lua(text)
  local c = theme.c
  local out = {}
  local i = 1
  local len = #text

  local colourText   = c.text
  local colourKey    = c.accent
  local colourStr    = c.success
  local colourNum    = c.warning
  local colourCmt    = c.dim
  local colourBuiltin = c.accentSoft
  local colourOp     = c.dim

  while i <= len do
    local rest = text:sub(i)

    -- long comment / long string
    local longOpen = rest:match("^%-%-%[=*%[") or nil
    if longOpen then
      out[#out + 1] = run(colourCmt, len - i + 1)
      break
    end

    -- line comment
    if rest:sub(1, 2) == "--" then
      out[#out + 1] = run(colourCmt, len - i + 1)
      break
    end

    -- long string
    local bracket = rest:match("^%[=*%[")
    if bracket then
      out[#out + 1] = run(colourStr, len - i + 1)
      break
    end

    -- quoted string
    local quote = rest:sub(1, 1)
    if quote == '"' or quote == "'" then
      local j = i + 1
      while j <= len do
        local ch = text:sub(j, j)
        if ch == "\\" then j = j + 2
        elseif ch == quote then j = j + 1 break
        else j = j + 1 end
      end
      out[#out + 1] = run(colourStr, math.min(j, len + 1) - i)
      i = j
    else
      local word = rest:match("^[%a_][%w_]*")
      if word then
        local colour = colourText
        if LUA_KEYWORDS[word] then colour = colourKey
        elseif LUA_BUILTINS[word] then colour = colourBuiltin
        elseif text:sub(i + #word):match("^%s*[%(\"'{]") then colour = c.accentSoft end
        out[#out + 1] = run(colour, #word)
        i = i + #word
      else
        local number = rest:match("^0[xX]%x+") or rest:match("^%d+%.?%d*[eE]?[%+%-]?%d*")
        if number and #number > 0 then
          out[#out + 1] = run(colourNum, #number)
          i = i + #number
        else
          local symbol = rest:match("^[%+%-%*/%%%^#=~<>%(%)%{%}%[%];:,%.]+")
          if symbol then
            out[#out + 1] = run(colourOp, #symbol)
            i = i + #symbol
          else
            out[#out + 1] = run(colourText, 1)
            i = i + 1
          end
        end
      end
    end
  end

  local result = table.concat(out)
  if #result < len then result = result .. run(colourText, len - #result) end
  return result:sub(1, len)
end

--- Markdown highlighter for Writer's source view.
function syntax.markdown(text)
  local c = theme.c
  local len = #text
  if len == 0 then return "" end
  if text:match("^%s*#") then return run(c.accent, len) end
  if text:match("^%s*[%-%*%+]%s") then
    return run(c.accentSoft, 2) .. run(c.text, len - 2)
  end
  if text:match("^%s*>") then return run(c.dim, len) end
  if text:match("^%s*|") then return run(c.success, len) end

  -- inline emphasis and code
  local out = {}
  local i = 1
  while i <= len do
    local ch = text:sub(i, i)
    if ch == "*" or ch == "_" then
      local closing = text:find(ch, i + 1, true)
      if closing then
        out[#out + 1] = run(c.warning, closing - i + 1)
        i = closing + 1
      else
        out[#out + 1] = run(c.text, 1)
        i = i + 1
      end
    elseif ch == "`" then
      local closing = text:find("`", i + 1, true)
      if closing then
        out[#out + 1] = run(c.success, closing - i + 1)
        i = closing + 1
      else
        out[#out + 1] = run(c.text, 1)
        i = i + 1
      end
    else
      out[#out + 1] = run(c.text, 1)
      i = i + 1
    end
  end
  return table.concat(out):sub(1, len)
end

--- Pick a highlighter from a filename.
function syntax.forPath(path)
  local ext = (fs.getName(path):match("%.([%w_]+)$") or ""):lower()
  if ext == "lua" then return syntax.lua end
  if ext == "md" or ext == "adoc" then return syntax.markdown end
  return nil
end

syntax.names = {
  { id = "none", label = "Plain text", fn = nil },
  { id = "lua", label = "Lua", fn = syntax.lua },
  { id = "markdown", label = "Markdown", fn = syntax.markdown },
}

return syntax
