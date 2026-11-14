--- Where the text cursor stands after the formatter rewrites
--- a draft (IS3.9, FR3.6): the cursor follows the text element
--- it was in or beside, the same occurrence of it, and keeps
--- its character offset in an element formatting respells.
---
--- A text element is a name, keyword, number, quoted string,
--- comment, operator or punctuation; the spaces inside a string
--- or a comment belong to it. The elements are the tokens and
--- comments of the parser's lexer, read here because they are
--- also wanted from a draft that does not parse, which that
--- lexer stops at.

local M = {}

local OPERATORS = {
  '...', '..', '==', '~=', '<=', '>=', '::',
}

--- @param s string
--- @param i integer
--- @return integer? --- the last byte of the long bracket
--- opening at `i`, to the end of the text when it never closes
local function long_bracket(s, i)
  local eq = string.match(s, '^%[(=*)%[', i)
  if not eq then return nil end
  local _, fin = string.find(s, ']' .. eq .. ']', i, true)
  return fin or #s
end

--- @param s string
--- @param i integer --- the opening quote
--- @return integer --- the closing quote, or the line's end
local function quoted(s, i)
  local q = string.sub(s, i, i)
  local j = i + 1
  while j <= #s do
    local c = string.sub(s, j, j)
    if c == '\\' then
      j = j + 1
    elseif c == q or c == '\n' then
      return j
    end
    j = j + 1
  end
  return #s
end

--- @param s string
--- @param i integer
--- @return integer --- the last byte of the comment at `i`
local function comment(s, i)
  local long = long_bracket(s, i + 2)
  if long then return long end
  local nl = string.find(s, '\n', i, true)
  return nl and nl - 1 or #s
end

--- The parser's lexer reads a number with these patterns
--- @param s string
--- @param i integer
--- @return integer? --- the last byte of the number at `i`
local function number(s, i)
  local j = string.match(s, '^0[xX]()', i)
  if j then
    j = string.match(s, '^%x+%.?%x*()', j)
        or string.match(s, '^%x*%.%x+()', j)
    j = j and (string.match(s, '^[pP][%+%-]?%d+()', j) or j)
  else
    j = string.match(s, '^%d+%.?%d*()', i)
        or string.match(s, '^%d*%.%d+()', i)
    j = j and (string.match(s, '^[eE][%+%-]?%d+()', j) or j)
  end
  return j and j - 1
end

--- @param s string
--- @param i integer
--- @return integer --- the last byte of the element at `i`
local function element_end(s, i)
  if string.sub(s, i, i + 1) == '--' then return comment(s, i) end
  local c = string.sub(s, i, i)
  if c == '"' or c == "'" then return quoted(s, i) end
  local long = c == '[' and long_bracket(s, i)
  if long then return long end
  local num = number(s, i)
  if num then return num end
  local _, word = string.find(s, '^[%w_\128-\255]+', i)
  if word then return word end
  for _, op in ipairs(OPERATORS) do
    if string.sub(s, i, i + #op - 1) == op then
      return i + #op - 1
    end
  end
  return i
end

--- @param s string
--- @return table[] --- {s, e, text}: byte offsets before the
--- element's first character and after its last
function M.elements(s)
  local out, i = {}, 1
  while true do
    i = string.find(s, '%S', i)
    if not i then break end
    local e = element_end(s, i)
    out[#out + 1] = {
      s = i - 1, e = e, text = string.sub(s, i, e)
    }
    i = e + 1
  end
  return out
end

--- The parser's lexer, loaded once the parser has set its path
local lexer

--- @param text string --- a string, a number or a comment
--- @return string? --- what it holds, as the parser reads it,
--- marked with a byte no other element's text has
local function value(text)
  if not lexer then
    local ok, m = pcall(require, 'metalua.grammar.lexer')
    if not ok then return end
    lexer = m.lexer
  end
  local ok, tok = pcall(function()
    return lexer:newstream(text):next()
  end)
  if not ok then return end
  local cs = tok.lineinfo.first.comments
  if tok.tag == 'Eof' and cs and #cs == 1 then
    local c = cs[1]
    --- `--x` prints as `-- x`
    if c[2] then return '\0[' .. c[1] end
    return '\0-' .. string.gsub(c[1], '^ ', '')
  end
  if tok.lineinfo.last.offset ~= #text then return end
  if tok.tag == 'String' then return '\0s' .. tok[1] end
  if tok.tag == 'Number' then
    return '\0n' .. tostring(tok[1])
  end
end

--- What makes two elements the same one: the text, or for a
--- string, a number or a comment, which formatting respells
--- (`'a'` as `"a"`, `0xff` as `255`), the value
--- @param el table
--- @return string
local function key(el)
  if el.key == nil then
    local t = el.text
    local valued = string.find(t, '^[\'"%d]')
        or string.find(t, '^%.%d') or string.find(t, '^%-%-')
        or string.find(t, '^%[=*%[')
    el.key = valued and value(t) or t
  end
  return el.key
end

--- The table of a longest common subsequence costs a cell for
--- each pair of elements; past this many the pairing is greedy
local MAX_CELLS = 40000

--- How far ahead the greedy pairing looks for a match
local LOOKAHEAD = 8

--- @param list table[]
--- @param from integer
--- @param to integer
--- @param k string --- a key
--- @return integer? --- the nearest index holding `k`
local function find_ahead(list, from, to, k)
  for i = from, math.min(to, from + LOOKAHEAD) do
    if key(list[i]) == k then return i end
  end
end

--- Pair a[i0..i1] with b[j0..j1] in one pass: the same
--- elements pair, and a different one is skipped on the side
--- where the other turns up soonest.
local function pair_greedy(a, b, map, i0, i1, j0, j1)
  local i, j = i0, j0
  while i <= i1 and j <= j1 do
    if key(a[i]) == key(b[j]) then
      map[i] = j
      i, j = i + 1, j + 1
    else
      local bj = find_ahead(b, j + 1, j1, key(a[i]))
      local ai = find_ahead(a, i + 1, i1, key(b[j]))
      if bj and (not ai or bj - j <= ai - i) then
        j = bj
      elseif ai then
        i = ai
      else
        i, j = i + 1, j + 1
      end
    end
  end
end

--- Pair a[i0..i1] with b[j0..j1] by a longest common
--- subsequence of their keys.
local function pair_lcs(a, b, map, i0, i1, j0, j1)
  local len = {}
  for i = i1 + 1, i0, -1 do
    len[i] = {}
    for j = j1 + 1, j0, -1 do
      if i > i1 or j > j1 then
        len[i][j] = 0
      elseif key(a[i]) == key(b[j]) then
        len[i][j] = len[i + 1][j + 1] + 1
      else
        len[i][j] = math.max(len[i + 1][j], len[i][j + 1])
      end
    end
  end
  local i, j = i0, j0
  while i <= i1 and j <= j1 do
    if key(a[i]) == key(b[j]) then
      map[i] = j
      i, j = i + 1, j + 1
    elseif len[i + 1][j] >= len[i][j + 1] then
      i = i + 1
    else
      j = j + 1
    end
  end
end

--- A string too long for a line is printed cut into pieces,
--- `"…" ..` on one line and `"…"` on the next.
--- @param b table[]
--- @param j0 integer
--- @param j1 integer
--- @param k string --- the key of the string
--- @return boolean --- b[j0..j1] are pieces holding `k`
local function pieces(b, j0, j1, k)
  if j1 <= j0 or (j1 - j0) % 2 ~= 0 then return false end
  local parts = {}
  for j = j0, j1, 2 do
    local x = key(b[j])
    if string.sub(x, 1, 2) ~= '\0s'
        or string.sub(b[j].text, 1, 1) ~= '"'
        or j < j1 and b[j + 1].text ~= '..' then
      return false
    end
    parts[#parts + 1] = string.sub(x, 3)
  end
  return '\0s' .. table.concat(parts) == k
end

--- Pair the elements that survive, so a repeated text keeps
--- its occurrence. Formatting keeps almost every element: the
--- common start and end pair off first, and only what lies
--- between them is searched.
--- @param a table[]
--- @param b table[]
--- @return table<integer, integer> --- index in a to index in b
--- @return table<integer, integer> --- index in a of a string
--- cut into pieces to the index in b of its last piece
local function pair(a, b)
  local n, m = #a, #b
  local map, lo, hi = {}, 0, 0
  while lo < n and lo < m and key(a[lo + 1]) == key(b[lo + 1]) do
    lo = lo + 1
    map[lo] = lo
  end
  while hi < n - lo and hi < m - lo
      and key(a[n - hi]) == key(b[m - hi]) do
    map[n - hi] = m - hi
    hi = hi + 1
  end
  local rest_a, rest_b = n - lo - hi, m - lo - hi
  local last = {}
  if rest_a == 0 or rest_b == 0 then return map, last end
  local search = pair_lcs
  if rest_a * rest_b > MAX_CELLS then search = pair_greedy end
  search(a, b, map, lo + 1, n - hi, lo + 1, m - hi)
  --- a string left over pairs with the pieces between its
  --- neighbors' pairs when they hold its value
  local before = lo
  for i = lo + 1, n - hi do
    if map[i] then
      before = map[i]
    elseif string.sub(key(a[i]), 1, 2) == '\0s' then
      local after = m - hi + 1
      for q = i + 1, n do
        if map[q] then
          after = map[q]
          break
        end
      end
      if pieces(b, before + 1, after - 1, key(a[i])) then
        map[i], last[i] = before + 1, after - 1
        before = after - 1
      end
    end
  end
  return map, last
end

--- @param a table[]
--- @param b table[]
--- @param map table<integer, integer>
--- @param from integer --- the first element to look at
--- @return integer? --- offset before the next survivor
local function before_next(a, b, map, from)
  for i = from, #a do
    if map[i] then return b[map[i]].s end
  end
end

--- @param b table[]
--- @param j0 integer --- the first piece of a string
--- @param j1 integer --- its last piece
--- @param k integer --- characters into the string
--- @return integer --- the byte offset `k` characters into
--- the pieces read as one literal, without the cuts
local function into_pieces(b, j0, j1, k)
  if k <= 1 then return b[j0].s + k end
  k = k - 1
  for j = j0, j1, 2 do
    local inner = string.sub(b[j].text, 2, -2)
    local n = string.ulen(inner) or #inner
    if k <= n then
      return b[j].s + 1 + #string.usub(inner, 1, k)
    end
    k = k - n
  end
  return b[j1].e
end

--- @param s string
--- @return integer[] --- where each line of `s` starts, as a
--- byte offset into it
local function line_starts(s)
  local out, i = { 0 }, 1
  while true do
    local nl = string.find(s, '\n', i, true)
    if not nl then return out end
    out[#out + 1] = nl
    i = nl + 1
  end
end

--- The spacing between two elements that survive side by
--- side, or between one and the draft's edge, is unchanged
--- where it has the same lines and the cursor's line of it is
--- the same: a blank line stays one when the formatter
--- respaces the line above it. Lines added or removed replace
--- the spacing.
--- @param g0 string --- the gap in the old text
--- @param g1 string --- the gap in the new text
--- @param k integer --- the cursor, bytes into `g0`
--- @return integer? --- the cursor, bytes into `g1`
local function in_gap(g0, g1, k)
  if g0 == g1 then return k end
  local l0, l1 = line_starts(g0), line_starts(g1)
  if #l0 ~= #l1 then return nil end
  local n = #l0
  while l0[n] > k do n = n - 1 end
  local function line(g, l, j)
    return string.sub(g, l[j] + 1, (l[j + 1] or #g + 1) - 1)
  end
  if line(g0, l0, n) ~= line(g1, l1, n) then return nil end
  return l1[n] + (k - l0[n])
end

--- @param old string
--- @param new string
--- @param at integer --- byte offset in `old`, 0 at its start
--- @return integer --- byte offset in `new`
function M.map(old, new, at)
  --- text that did not change keeps its cursor (IS3.9)
  if old == new then return at end
  if at <= 0 then return 0 end
  if at >= #old then return #new end
  local a, b = M.elements(old), M.elements(new)
  local m, last = pair(a, b)
  --- @param i integer
  --- @return integer? --- the index in b of a[i]'s last piece;
  --- the draft's start, before the first element, is 0
  local function fin(i)
    if i == 0 then return 0 end
    return last[i] or m[i]
  end
  --- @param i integer --- the element after the gap, past the
  --- last one for the gap at the draft's end
  --- @return integer? --- the cursor in the new text
  local function gap(i)
    local j = fin(i - 1)
    local nb = i > #a and #b + 1 or m[i]
    if not j or not nb or nb ~= j + 1 then return nil end
    local s0 = i > 1 and a[i - 1].e or 0
    local s1 = j > 0 and b[j].e or 0
    local e0 = i <= #a and a[i].s or #old
    local e1 = nb <= #b and b[nb].s or #new
    local k = in_gap(string.sub(old, s0 + 1, e0),
      string.sub(new, s1 + 1, e1), at - s0)
    return k and s1 + k
  end
  for i, el in ipairs(a) do
    --- the end of the element before the cursor comes first
    if el.e == at and m[i] then return b[fin(i)].e end
    if el.s == at and m[i] then return b[m[i]].s end
    local inside = el.s < at and at < el.e
    if inside and m[i] then
      --- the same character offset, within the new spelling
      local t = b[m[i]]
      local k = string.ulen(string.sub(old, el.s + 1, at))
          or at - el.s
      if last[i] then return into_pieces(b, m[i], last[i], k) end
      return t.s + #string.usub(t.text, 1, k)
    end
    if at <= el.s or inside then
      --- in a gap before `el`, or in an element that is gone
      return not inside and gap(i)
          or before_next(a, b, m, i) or #new
    end
  end
  --- in the gap after the last element
  return gap(#a + 1) or #new
end

--- @param lines string[]
--- @param l integer
--- @param c integer --- a character column
--- @return integer --- byte offset in the joined text
local function offset(lines, l, c)
  local at = 0
  for i = 1, l - 1 do at = at + #lines[i] + 1 end
  return at + #string.usub(lines[l] or '', 1, c - 1)
end

--- @param lines string[]
--- @param at integer --- byte offset in the joined text
--- @return integer l
--- @return integer c --- a character column
function M.position(lines, at)
  for i, line in ipairs(lines) do
    if at <= #line or i == #lines then
      local pre = string.sub(line, 1, at)
      return i, (string.ulen(pre) or #pre) + 1
    end
    at = at - #line - 1
  end
  return 1, 1
end

--- @param old string[]
--- @param new string[]
--- @param l integer
--- @param c integer
--- @return integer l
--- @return integer c
function M.cursor(old, new, l, c)
  local at = M.map(table.concat(old, '\n'),
    table.concat(new, '\n'), offset(old, l, c))
  return M.position(new, at)
end

return M
