require('util.string.string')

--- Formatting: Lua source rewritten the way the editor writes
--- it. It rewrites and never refuses; the editor's refusals
--- are the gates in model.lang.lua.check, and conventions the
--- editor lets through are lints.
---
--- Blank lines follow the editor's rule: a run between two
--- statements or comments, or leading the text, becomes one
--- blank line, and so does a run ending it; the start and end
--- of an indented body keep none. Text is already formatted
--- when format(text) equals it.

local M = {}

--- The parser is built on first use, so requiring this module
--- costs nothing until something is formatted.
local parser
local function get_parser()
  parser = parser or require('model.lang.lua.parser')()
  return parser
end

--- @param l string?
--- @return boolean
local function is_blank(l)
  return l ~= nil and string.match(l, '^%s*$') ~= nil
end

--- The node a comparison looks at: parentheses the printer
--- keeps or adds are not the program, it writes
--- `not (a == b)` as `a ~= b`, and it splits a long string
--- into pieces joined with `..`
--- @param n any
--- @return any
local function plain(n)
  while type(n) == 'table' and n.tag == 'Paren' do n = n[1] end
  if type(n) ~= 'table' or n.tag ~= 'Op' then return n end
  if n[1] == 'not' then
    local inner = plain(n[2])
    if type(inner) == 'table' and inner.tag == 'Op'
        and inner[1] == 'eq' then
      return { tag = 'Op', 'ne', inner[2], inner[3] }
    end
  elseif n[1] == 'concat' then
    local a, b = plain(n[2]), plain(n[3])
    if type(a) == 'table' and a.tag == 'String'
        and type(b) == 'table' and b.tag == 'String' then
      return { tag = 'String', a[1] .. b[1] }
    end
  end
  return n
end

--- Two ASTs are the same program: same tags, same values,
--- positions aside
--- @param a any
--- @param b any
--- @return boolean
local function same_program(a, b)
  a, b = plain(a), plain(b)
  if type(a) ~= 'table' or type(b) ~= 'table' then
    return a == b
  end
  if a.tag ~= b.tag or #a ~= #b then return false end
  for i = 1, #a do
    if not same_program(a[i], b[i]) then return false end
  end
  return true
end

--- The printer re-wraps comments, so their text is compared
--- with the whitespace taken out
--- @param code string[]
--- @return string?
local function comment_text(code)
  local texts = get_parser().comments(code)
  if not texts then return end
  return (string.gsub(table.concat(texts), '%s', ''))
end

--- The printer does not always settle in one pass (a string it
--- splits prints differently once split), so formatting runs
--- it until its output stops changing
local MAX_PASSES = 4

--- Format Lua source. Text that does not parse comes back as
--- it is; so does text the printer would change the meaning
--- of, drop a comment from, or never settle on, which no
--- caller may write.
--- @param lines string[]
--- @param width integer --- the line width to wrap at
--- @return string[] formatted --- the input when not ok
--- @return boolean ok --- the text parsed and was formatted
function M.format(lines, width)
  local p = get_parser()
  local ok, ast = p.parse(lines)
  if not ok then return lines, false end
  local comments = comment_text(lines)
  local out, settled = lines, false
  for _ = 1, MAX_PASSES do
    local printed, next_out = pcall(p.pprint, out, width)
    if not printed or not next_out then return lines, false end
    local ok2, ast2 = p.parse(next_out)
    if not ok2 or not same_program(ast, ast2)
        or comment_text(next_out) ~= comments then
      return lines, false
    end
    settled = table.concat(next_out, '\n') == table.concat(out, '\n')
    out = next_out
    if settled then break end
  end
  if not settled then return lines, false end
  --- a run of blank lines ending the text follows no token
  --- the printer measures from; one is kept here
  local has_code = string.is_non_empty_string_array(lines)
  if has_code and is_blank(lines[#lines])
      and not is_blank(out[#out]) then
    table.insert(out, '')
  end
  return out, true
end

return M
