--- Where the text cursor stands after the formatter rewrites
--- a draft (IS3.9, FR3.6): the cursor follows the text element
--- it was in or beside, the same occurrence of it.
---
--- A text element is a name, keyword, number, quoted string,
--- comment, operator or punctuation; the spaces inside a string
--- or a comment belong to it.

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

--- @param s string
--- @param i integer
--- @return integer --- the last byte of the element at `i`
local function element_end(s, i)
  if string.sub(s, i, i + 1) == '--' then return comment(s, i) end
  local c = string.sub(s, i, i)
  if c == '"' or c == "'" then return quoted(s, i) end
  local long = c == '[' and long_bracket(s, i)
  if long then return long end
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

--- The table of a longest common subsequence costs a cell for
--- each pair of elements; past this many the pairing is greedy
local MAX_CELLS = 40000

--- How far ahead the greedy pairing looks for a match
local LOOKAHEAD = 8

--- @param list table[]
--- @param from integer
--- @param to integer
--- @param text string
--- @return integer? --- the nearest index holding `text`
local function find_ahead(list, from, to, text)
  for k = from, math.min(to, from + LOOKAHEAD) do
    if list[k].text == text then return k end
  end
end

--- Pair a[i0..i1] with b[j0..j1] in one pass: equal elements
--- pair, and an unequal one is skipped on the side where the
--- other's text turns up soonest.
local function pair_greedy(a, b, map, i0, i1, j0, j1)
  local i, j = i0, j0
  while i <= i1 and j <= j1 do
    if a[i].text == b[j].text then
      map[i] = j
      i, j = i + 1, j + 1
    else
      local bj = find_ahead(b, j + 1, j1, a[i].text)
      local ai = find_ahead(a, i + 1, i1, b[j].text)
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
--- subsequence of their texts.
local function pair_lcs(a, b, map, i0, i1, j0, j1)
  local len = {}
  for i = i1 + 1, i0, -1 do
    len[i] = {}
    for j = j1 + 1, j0, -1 do
      if i > i1 or j > j1 then
        len[i][j] = 0
      elseif a[i].text == b[j].text then
        len[i][j] = len[i + 1][j + 1] + 1
      else
        len[i][j] = math.max(len[i + 1][j], len[i][j + 1])
      end
    end
  end
  local i, j = i0, j0
  while i <= i1 and j <= j1 do
    if a[i].text == b[j].text then
      map[i] = j
      i, j = i + 1, j + 1
    elseif len[i + 1][j] >= len[i][j + 1] then
      i = i + 1
    else
      j = j + 1
    end
  end
end

--- Pair the elements that survive, so a repeated text keeps
--- its occurrence. Formatting keeps almost every element: the
--- common start and end pair off first, and only what lies
--- between them is searched.
--- @param a table[]
--- @param b table[]
--- @return table<integer, integer> --- index in a to index in b
local function pair(a, b)
  local n, m = #a, #b
  local map, lo, hi = {}, 0, 0
  while lo < n and lo < m and a[lo + 1].text == b[lo + 1].text do
    lo = lo + 1
    map[lo] = lo
  end
  while hi < n - lo and hi < m - lo
      and a[n - hi].text == b[m - hi].text do
    map[n - hi] = m - hi
    hi = hi + 1
  end
  local rest_a, rest_b = n - lo - hi, m - lo - hi
  if rest_a == 0 or rest_b == 0 then return map end
  local search = pair_lcs
  if rest_a * rest_b > MAX_CELLS then search = pair_greedy end
  search(a, b, map, lo + 1, n - hi, lo + 1, m - hi)
  return map
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

--- @param old string
--- @param new string
--- @param at integer --- byte offset in `old`, 0 at its start
--- @return integer --- byte offset in `new`
function M.map(old, new, at)
  if at <= 0 then return 0 end
  if at >= #old then return #new end
  local a, b = M.elements(old), M.elements(new)
  local m = pair(a, b)
  for i, el in ipairs(a) do
    --- the end of the element before the cursor comes first
    if el.e == at and m[i] then return b[m[i]].e end
    if el.s == at and m[i] then return b[m[i]].s end
    local inside = el.s < at and at < el.e
    if inside and m[i] then
      local t = b[m[i]]
      return math.min(t.s + (at - el.s), t.e)
    end
    if at <= el.s or inside then
      --- in a gap before `el`, or in an element that is gone
      local prev = a[i - 1]
      local gap = prev and m[i - 1] and m[i]
          and m[i] == m[i - 1] + 1 and not inside
          and string.sub(old, prev.e + 1, el.s)
          == string.sub(new, b[m[i - 1]].e + 1, b[m[i]].s)
      if gap then return b[m[i - 1]].e + (at - prev.e) end
      return before_next(a, b, m, i) or #new
    end
  end
  return #new
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
