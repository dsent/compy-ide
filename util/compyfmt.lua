--- compyfmt: the editor's formatting, gates and lints for Lua
--- files, from the command line. Run it from the repository root
--- with Lua 5.1 or LuaJIT:
---
---   luajit util/compyfmt.lua [--fix] [--strict] <file.lua>...
---
--- By default it changes no file. It reports every file that
--- formatting would change, then what formatting cannot
--- resolve: the editor's gates (a line too long, an error, a
--- block too large) and the lints. Their line numbers are
--- those of the file as it would be formatted.
---
--- --fix formats each file in place, the way the editor writes
--- code on a Compy, then reports the gates and lints left.
---
--- --strict reports the strict lints as well: conventions much
--- existing code breaks.
---
--- A report line reads `file:line: what`. Both modes exit 1
--- when they report anything and 2 when a file cannot be read
--- or an argument is an option other than --fix and --strict.

local home = os.getenv("HOME") or ''
package.path = "./src/?.lua;./src/?/init.lua;" .. package.path
    .. ";" .. home .. "/.luarocks/share/lua/5.1/?.lua"
    .. ";" .. home .. "/.luarocks/share/lua/5.1/?/init.lua"
package.cpath = package.cpath .. ";"
    .. home .. "/.luarocks/lib/lua/5.1/?.so"

require("util.string.string")
require("util.table")
local parser = require("model.lang.lua.parser")()
local check = require("model.lang.lua.check")
local lint = require("model.lang.lua.lint")
local display = require("conf.display")

local M = {}

--- What compyfmt says about one file's text, and the text the
--- file should hold
--- @param lines string[]
--- @param strict boolean? --- report the strict lints too
--- @return string[] text --- formatted, with a final newline;
--- the text as it was when it does not format
--- @return string[] reports --- `line: what`, in line order
--- @return boolean formatted --- the text formatted
function M.inspect(lines, strict)
  local verdict = check.gate(lines, display.columns)
  local text = verdict.lines
  if verdict.formatted and text[#text] ~= '' then
    text = table.clone(text)
    table.insert(text, '')
  end
  local found = {}
  local function add(l, what)
    table.insert(found, { l = l or 1, n = #found, what = what })
  end

  if not verdict.formatted and parser.parse(lines) then
    add(1, 'cannot be formatted without changing what the'
      .. ' code does; left as it is')
  end
  for _, e in ipairs(verdict.errors) do
    add(e.l, e.msg)
  end
  for _, i in ipairs(verdict.oversized) do
    local b = verdict.blocks[i]
    add(b.pos.start, string.format(
      'block of %d lines, %d over the limit of %d',
      b.pos:len(), check.excess(verdict, i), verdict.max_block))
  end
  --- lints read any text that parses, beside the gates
  local parsed, ast = parser.parse(text)
  if parsed then
    for _, f in ipairs(lint.lint(text, ast, strict)) do
      add(f.l, f.msg .. ' (' .. f.rule .. ')')
    end
  end

  --- by line; on one line, gates before lints, as added
  table.sort(found, function(a, b)
    if a.l ~= b.l then return a.l < b.l end
    return a.n < b.n
  end)
  local reports = {}
  for _, f in ipairs(found) do
    table.insert(reports, f.l .. ': ' .. f.what)
  end
  return text, reports, verdict.formatted
end

--- @param path string
--- @return string[]? --- nil when the file cannot be read
local function read_lines(path)
  local f = io.open(path, 'rb')
  if not f then return end
  local s = f:read('*a')
  f:close()
  if s then return string.lines(s) end
end

--- Write beside the file, then put that in its place, so a
--- write that fails leaves the file as it was
--- @param path string
--- @param lines string[]
--- @return boolean
local function write_lines(path, lines)
  local tmp = path .. '.compyfmt~'
  local f = io.open(tmp, 'wb')
  if not f then return false end
  local written = f:write(string.unlines(lines))
  local closed = f:close()
  if not (written and closed and os.rename(tmp, path)) then
    os.remove(tmp)
    return false
  end
  return true
end

local USAGE = 'Usage: luajit util/compyfmt.lua'
  .. ' [--fix] [--strict] <file.lua>...\n'
  .. 'Reports what the editor would change or refuse in each'
  .. ' file.\nWith --fix, formats the files in place first.\n'
  .. 'With --strict, also reports the strict lints.\n'

--- @class CompyfmtOptions
--- @field fix boolean
--- @field strict boolean
--- @field files string[]

--- @param args string[]
--- @return CompyfmtOptions? --- nil for any other option
local function options(args)
  local o = { fix = false, strict = false, files = {} }
  for _, a in ipairs(args) do
    if a == '--fix' or a == '--strict' then
      o[string.sub(a, 3)] = true
    elseif string.match(a, '^%-') then
      io.stderr:write(a .. ' is not an option.\n')
      return
    else
      table.insert(o.files, a)
    end
  end
  return o
end

--- @param args string[]
--- @return integer --- the exit status
function M.main(args)
  local o = options(args)
  if not o or #o.files == 0 then
    io.stderr:write(USAGE)
    return 2
  end
  local fix, files = o.fix, o.files

  local status = 0
  for _, path in ipairs(files) do
    local lines = read_lines(path)
    if not lines then
      io.stderr:write(path .. ': cannot be read\n')
      status = 2
    else
      local text, reports = M.inspect(lines, o.strict)
      local changed = string.unlines(text) ~= string.unlines(lines)
      if changed and fix and not write_lines(path, text) then
        io.stderr:write(path .. ': cannot be written\n')
        status = 2
      end
      if changed and not fix then
        print(path .. ': not formatted')
      end
      for _, r in ipairs(reports) do
        print(path .. ':' .. r)
      end
      if status == 0 and (#reports > 0 or changed and not fix) then
        status = 1
      end
    end
  end
  return status
end

--- run as a script, not required as a module
if arg and arg[0] and string.match(arg[0], 'compyfmt%.lua$') then
  os.exit(M.main(arg))
end
return M
