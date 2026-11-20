require('util.string.string')
require('util.table')

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

--- LuaJIT's stripped bytecode for `lines`, or nil when LuaJIT
--- does not load it. Returns the chunk too so its interned
--- strings stay pinned: LuaJIT dumps template-table keys in
--- hash order, which can change if GC collects and re-interns
--- a string between two compiles.
--- @param lines string[]
--- @return string?
--- @return function?
local function bytecode(lines)
  local fn = loadstring(table.concat(lines, '\n'))
  if not fn then return nil end
  return string.dump(fn, true), fn
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

--- @param lines string[]
--- @param width integer
--- @return string[] formatted
--- @return boolean ok
local function format_code(lines, width)
  local p = get_parser()
  if not p.parse(lines) then return lines, false end
  local before, pinned = bytecode(lines)
  if not before then return lines, false end
  local comments = comment_text(lines)
  local out, settled = lines, false
  for _ = 1, MAX_PASSES do
    local printed, next_out = pcall(p.pprint, out, width)
    if not printed or not next_out then return lines, false end
    local after = bytecode(next_out)
    if not after or after ~= before
        or comment_text(next_out) ~= comments then
      return lines, false
    end
    settled = table.concat(next_out, '\n') == table.concat(out, '\n')
    out = next_out
    if settled then break end
  end
  if not settled or not pinned then return lines, false end
  --- a run of blank lines ending the text follows no token
  --- the printer measures from; one is kept here
  local has_code = string.is_non_empty_string_array(lines)
  if has_code and is_blank(lines[#lines])
      and not is_blank(out[#out]) then
    table.insert(out, '')
  end
  return out, true
end

--- Format Lua source. Text that does not parse comes back as
--- it is; so does text the printer would change the meaning
--- of, drop a comment from, or never settle on, which no
--- caller may write. A `#!` first line, which LuaJIT and the
--- parser skip, is no program the printer prints: it stays
--- as it is, and the rest is formatted.
--- @param lines string[]
--- @param width integer --- the line width to wrap at
--- @return string[] formatted --- the input when not ok
--- @return boolean ok --- the text parsed and was formatted
function M.format(lines, width)
  local header = lines[1]
  if not (header and string.match(header, '^#!')) then
    return format_code(lines, width)
  end
  --- the whole text is what must parse: below its first
  --- line, a `#!` line is no Lua
  if not get_parser().parse(lines) then return lines, false end
  if #lines == 1 then return lines, true end
  local out, ok = format_code(table.slice(lines, 2, #lines),
    width)
  if not ok then return lines, false end
  table.insert(out, 1, header)
  return out, true
end

return M
