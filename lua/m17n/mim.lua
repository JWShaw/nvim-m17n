-- m17n .mim file parser (pragmatic subset)
--
-- m17n input method files are Lisp-like s-expressions.  This module reads the
-- subset that is relevant for a transliteration-style input method:
--
--   (input-method ru translit)
--   (map
--    (map
--     ("a" ?а)
--     ("shch" ?щ)
--     ("~~" "Ъ")))
--
-- It understands:
--   * `;` line comments and whitespace
--   * `(...)` lists (nested `(map ...)` groups are flattened)
--   * double quoted strings with the usual escapes
--   * `?x` character literals (single UTF-8 character, or `?\n` style escapes)
--
-- It deliberately ignores everything else (description, title, state, ...).

local M = {}

local uint8 = string.byte

--- Number of bytes of the UTF-8 sequence starting with byte `b`.
local function utf8_len(b)
  if not b then return 0 end
  if b < 0x80 then return 1 end
  if b < 0xC0 then return 1 end -- stray continuation byte
  if b < 0xE0 then return 2 end
  if b < 0xF0 then return 3 end
  return 4
end

local STRING_ESCAPES = {
  n = "\n",
  t = "\t",
  r = "\r",
  ["\\"] = "\\",
  ['"'] = '"',
  ["'"] = "'",
  [" "] = " ",
}

--- Turn source text into a flat list of tokens.
local function tokenize(src)
  local tokens = {}
  local i, n = 1, #src

  while i <= n do
    local c = src:sub(i, i)

    if c == ";" then
      local nl = src:find("\n", i, true)
      i = nl and (nl + 1) or (n + 1)
    elseif c:match("%s") then
      i = i + 1
    elseif c == "(" or c == ")" then
      tokens[#tokens + 1] = { kind = c, value = c }
      i = i + 1
    elseif c == '"' then
      local buf = {}
      i = i + 1
      while i <= n do
        local d = src:sub(i, i)
        if d == "\\" then
          local e = src:sub(i + 1, i + 1)
          buf[#buf + 1] = STRING_ESCAPES[e] or e
          i = i + 2
        elseif d == '"' then
          i = i + 1
          break
        else
          buf[#buf + 1] = d
          i = i + 1
        end
      end
      tokens[#tokens + 1] = { kind = "string", value = table.concat(buf) }
    elseif c == "?" then
      i = i + 1
      local d = src:sub(i, i)
      if d == "\\" then
        local e = src:sub(i + 1, i + 1)
        tokens[#tokens + 1] = { kind = "char", value = STRING_ESCAPES[e] or e }
        i = i + 2
      else
        local len = utf8_len(uint8(d))
        local ch = src:sub(i, i + len - 1)
        tokens[#tokens + 1] = { kind = "char", value = ch }
        i = i + len
      end
    else
      local j = i
      while j <= n do
        local d = src:sub(j, j)
        if d:match("[%s%(%)%;%\"]") then break end
        j = j + 1
      end
      tokens[#tokens + 1] = { kind = "symbol", value = src:sub(i, j - 1) }
      i = j
    end
  end

  return tokens
end

--- Parse tokens into a tree of lists / leaf tables `{ kind, value }`.
local function parse_tokens(tokens)
  local pos = 1

  local function parse_expr()
    local tok = tokens[pos]
    if not tok then return nil end

    if tok.kind == "(" then
      pos = pos + 1
      local list = {}
      while tokens[pos] and tokens[pos].kind ~= ")" do
        list[#list + 1] = parse_expr()
      end
      pos = pos + 1 -- consume ")"
      return list
    elseif tok.kind == ")" then
      return nil
    else
      pos = pos + 1
      return { kind = tok.kind, value = tok.value }
    end
  end

  local forms = {}
  while pos <= #tokens do
    local expr = parse_expr()
    if expr == nil then break end
    forms[#forms + 1] = expr
  end
  return forms
end

local function is_symbol(node, name)
  return type(node) == "table" and node.kind == "symbol" and node.value == name
end

--- Collect `(keys output)` pairs from a `(map ...)` form, descending into
--- nested `(map ...)` forms.  `out` preserves file order.
local function collect_map(node, out)
  for k = 2, #node do
    local child = node[k]
    if is_symbol(child[1], "map") then
      collect_map(child, out)
    elseif child[1] and child[1].kind == "string" and #child >= 2 then
      local rhs = child[2]
      if rhs and (rhs.kind == "char" or rhs.kind == "string") then
        out[#out + 1] = { lhs = child[1].value, rhs = rhs.value }
      end
    end
  end
end

--- Parse `.mim` source text into `{ { lhs = <string>, rhs = <string> }, ... }`.
function M.parse(src)
  local forms = parse_tokens(tokenize(src))
  local entries = {}
  for _, form in ipairs(forms) do
    if is_symbol(form[1], "map") then
      collect_map(form, entries)
    end
  end
  return entries
end

--- Parse a `.mim` file by path.  Returns entries, or `nil, err`.
function M.parse_file(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local src = f:read("*a")
  f:close()
  return M.parse(src)
end

return M
