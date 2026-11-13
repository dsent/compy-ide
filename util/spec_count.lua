--- spec_count: how many tests check each spec item, and how
--- many of them mark a gap or a deviation
--- (tests/helpers/spec_marks.lua). Run it from the repository
--- root with Lua 5.1 or LuaJIT:
---
---   luajit util/spec_count.lua tests/editor/spec/*.lua
---
--- It reads the files and runs nothing. A mark is a call of
--- spec_it, spec_gap or spec_deviation whose first argument is
--- a string literal opening with the item's id; comments are
--- skipped. One line per item: its marks (every test), of them
--- the gaps, and of them the deviations; then the totals.
--- A call it cannot read (a name that is not a literal, or has
--- no id) is reported as `file:line`, and the exit is 1.
--- Exits 2 when a file cannot be read.

local M = { }

local KINDS = {
  spec_it = "tests",
  spec_gap = "gaps",
  spec_deviation = "deviations"
}

local ID = "^(%u[%u%-]*%d+%.?%d*) "
local BACKSLASH = string.char(92)

--- The text of a long bracket (two square brackets, any `=`
--- between them) opening at `i`, and the index after it; nil
--- when none opens there.
local function bracket_text(src, i, eq)
  local from = i + 2 + #eq
  local s, e = src:find("]" .. eq .. "]", from, true)
  if not s then
    return src:sub(from), #src + 1
  end
  return src:sub(from, s - 1), e + 1
end

local function long_bracket(src, i)
  local eq = src:match("^%[(=*)%[", i)
  if eq then
    return bracket_text(src, i, eq)
  end
end

--- A quoted string opening at `i`: its text, escapes read as
--- the escaped character, and the index after it.
local function quoted(src, i)
  local q, j = src:sub(i, i), i + 1
  while j <= #src do
    local c = src:sub(j, j)
    if c == q then
      break
    end
    j = j + (c == BACKSLASH and 2 or 1)
  end
  local text = src:sub(i + 1, j - 1)
  return (text:gsub(BACKSLASH .. "(.)", "%1")), j + 1
end

--- The index after the comment at `i` (it opens with --).
local function skip_comment(src, i)
  local _, after = long_bracket(src, i + 2)
  if after then
    return after
  end
  local nl = src:find("\n", i, true)
  return nl and nl + 1 or #src + 1
end

--- The index of the next token at or after `i`.
local function skip_space(src, i)
  while true do
    i = src:find("[^%s]", i) or #src + 1
    if src:sub(i, i + 1) ~= "--" then
      return i
    end
    i = skip_comment(src, i)
  end
end

local QUOTES = {
  ["\""] = true,
  ["'"] = true
}

--- A string literal's text at `i` and the index after it, or
--- nil when none opens there.
local function string_at(src, i)
  if QUOTES[src:sub(i, i)] then
    return quoted(src, i)
  end
  return long_bracket(src, i)
end

--- The token at `i`: its kind, its text, the index after it.
local function token(src, i)
  local name = src:match("^[%a_][%w_]*", i)
  if name then
    return "name", name, i + #name
  end
  local text, after = string_at(src, i)
  if after then
    return "string", text, after
  end
  return "punct", src:sub(i, i), i + 1
end

--- The source's tokens, comments skipped, each with its line.
local function tokens(src)
  local out, i = { }, skip_space(src, 1)
  while i <= #src do
    local kind, text, after = token(src, i)
    local _, nl = src:sub(1, i):gsub("\n", "")
    out[#out + 1] = {
      kind = kind,
      text = text,
      line = nl + 1
    }
    i = skip_space(src, after)
  end
  return out
end

--- The mark a call at token `k` makes, or false when the call
--- cannot be read; nil when it is no mark call.
-- a call without parentheses: f "name" or f { ... }; it
-- cannot carry a body, so it is reported
local function bare_call(open)
  return open.kind == "string" or open.text == "{"
end

--- The mark's kind when token `k` calls one with
--- parentheses; false when it calls one otherwise; nil when
--- it calls none.
local function call_kind(toks, k)
  local t, open = toks[k], toks[k + 1]
  local kind = t.kind == "name" and KINDS[t.text]
  if not (kind and open) then
    return nil
  end
  if bare_call(open) then
    return false
  end
  return open.text == "(" and kind or nil
end

local function mark_at(toks, k)
  local kind, arg = call_kind(toks, k), toks[k + 2]
  if not kind then
    return kind
  end
  local id = arg and arg.kind == "string"
       and arg.text:match(ID)
  return id and {
    id = id,
    kind = kind
  } or false
end

--- The marks in a file's source, in order, and the lines of
--- the mark calls it cannot read.
--- @param src string
--- @return { id: string, kind: string }[], integer[]
function M.scan(src)
  local toks, marks, unread = tokens(src), { }, { }
  for k = 1, #toks do
    local m = mark_at(toks, k)
    if m then
      marks[#marks + 1] = m
    end
    if m == false then
      unread[#unread + 1] = toks[k].line
    end
  end
  return marks, unread
end

local COLUMNS = {
  "tests",
  "gaps",
  "deviations"
}

local function new_row(id)
  return {
    id = id,
    tests = 0,
    gaps = 0,
    deviations = 0
  }
end

local function bump(by_id, order, mark)
  local row = by_id[mark.id]
  if not row then
    row = new_row(mark.id)
    by_id[mark.id] = row
    order[#order + 1] = row
  end
  row.tests = row.tests + 1
  if mark.kind ~= "tests" then
    row[mark.kind] = row[mark.kind] + 1
  end
end

--- One row per item, in the order first seen; every mark is a
--- test, and a gap or a deviation is counted again as such.
--- @param marks { id: string, kind: string }[]
function M.tally(marks)
  local by_id, order = { }, { }
  for _, mark in ipairs(marks) do
    bump(by_id, order, mark)
  end
  return order
end

local ROW = "%-10s %5d %5d %5d"
local HEADER = string.format(
  "%-10s %5s %5s %5s",
  "item",
  "marks",
  "gaps",
  "devs"
)

local function row_line(r)
  return string.format(ROW, r.id, r.tests, r.gaps, r.deviations)
end

local function add(sum, r)
  for _, k in ipairs(COLUMNS) do
    sum[k] = sum[k] + r[k]
  end
end

--- The report's lines: a header, the items, the totals.
function M.report(rows)
  local lines, sum = { HEADER }, new_row("total")
  for _, r in ipairs(rows) do
    lines[#lines + 1] = row_line(r)
    add(sum, r)
  end
  lines[#lines + 1] = row_line(sum)
  lines[#lines + 1] = string.format("items: %d", #rows)
  return lines
end

local function read(path)
  local f = io.open(path, "r")
  if not f then
    io.stderr:write("cannot read " .. path .. "\n")
    os.exit(2)
  end
  local src = f:read("*a")
  f:close()
  return src
end

local function scan_file(path, marks)
  local found, unread = M.scan(read(path))
  for _, m in ipairs(found) do
    marks[#marks + 1] = m
  end
  for _, line in ipairs(unread) do
    print(
      path .. ":" .. line .. ": a mark the count cannot read"
    )
  end
  return #unread
end

local function main(paths)
  local marks, unread = { }, 0
  for _, path in ipairs(paths) do
    unread = unread + scan_file(path, marks)
  end
  for _, l in ipairs(M.report(M.tally(marks))) do
    print(l)
  end
  if 0 < unread then
    os.exit(1)
  end
end

local script = arg and arg[0] or ""
if string.match(script, "spec_count%.lua$") then
  main(arg)
end

return M
