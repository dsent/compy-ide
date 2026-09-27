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
local textfile = require("util.textfile")

local M = {}

--- What compyfmt says about one file's lines, and the lines
--- the file should hold (util.textfile)
--- @param lines string[]
--- @param strict boolean? --- report the strict lints too
--- @return string[] text --- formatted; the lines as they were
--- when they do not format
--- @return string[] reports --- `line: what`, in line order
--- @return boolean formatted --- the text formatted
function M.inspect(lines, strict)
  local verdict = check.gate(lines, display.columns)
  local text = verdict.lines
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
--- @return string? --- nil when the file cannot be read
local function read_file(path)
  local f = io.open(path, 'rb')
  if not f then return end
  local s = f:read('*a')
  f:close()
  return s
end

--- the error number of a file that is not there
local ENOENT = 2

--- The copy --fix writes beside a file before the file itself
--- @param path string
--- @return string
local function copy_path(path)
  return path .. '.compyfmt~'
end

--- Whether something is at `path`; what cannot be opened for
--- another reason than being absent counts as there
--- @param path string
--- @return boolean
local function is_there(path)
  local f, _, code = io.open(path, 'rb')
  if f then
    f:close()
    return true
  end
  return code ~= ENOENT
end

--- @param f file*
--- @param text string
--- @return boolean --- written and closed
local function write_to(f, text)
  local written = f:write(text)
  local closed = f:close()
  return (written and closed) and true or false
end

--- Take the copy beside `path` before the file is read: it is
--- created new ('x') and held until the file is written, so
--- while one run holds it no other reads a file that run may
--- have cut short part way through its write. A directory that
--- takes no new file gives nothing to hold, and nothing can be
--- written there.
--- @param path string
--- @return file*? held
--- @return boolean taken --- another run's copy is there
local function hold_copy(path)
  --- @diagnostic disable-next-line: param-type-mismatch
  local c = io.open(copy_path(path), 'wbx')
  if c then return c, false end
  return nil, is_there(copy_path(path))
end

--- @param path string
--- @param held file*?
local function release_copy(path, held)
  if not held then return end
  held:close()
  os.remove(copy_path(path))
end

--- Write into the held copy first, so a disk that cannot take
--- the text fails with the file as it was; then write the same
--- text into the file itself, which keeps its mode, owner and
--- inode. When that second write fails part way, the text stays
--- beside the file, and while it is there the file is not
--- written again: it may be the only whole copy of the program.
--- @param path string
--- @param text string
--- @param held file*? --- the copy, from hold_copy
--- @return boolean written
--- @return string? kept --- the copy left beside the file
local function write_file(path, text, held)
  if not held then return false end
  local tmp = copy_path(path)
  if not write_to(held, text) then
    os.remove(tmp)
    return false
  end
  local f = io.open(path, 'wb')
  if not f then
    os.remove(tmp)
    return false
  end
  if not write_to(f, text) then return false, tmp end
  os.remove(tmp)
  return true
end

--- @param path string
local function report_left(path)
  local kept = copy_path(path)
  io.stderr:write(path .. ': not written, because ' .. kept
    .. ' is there: another --fix is writing ' .. path
    .. ', or one stopped part way and ' .. kept
    .. ' may hold the only whole copy of the program. When no'
    .. ' --fix is running, compare the two, keep the whole one'
    .. ' as ' .. path .. ', and remove ' .. kept .. '\n')
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

--- @param path string
--- @param o CompyfmtOptions
--- @return integer --- 0, 1 for a report, 2 for a file that
---   cannot be read or written
local function check_file(path, o)
  local held, taken
  if o.fix then held, taken = hold_copy(path) end
  if taken then
    --- whatever the file holds now, even text that needs no
    --- formatting, it may be cut short
    report_left(path)
    return 2
  end
  local s = read_file(path)
  if not s then
    release_copy(path, held)
    io.stderr:write(path .. ': cannot be read\n')
    return 2
  end
  local lines = textfile.lines(s)
  local done, text, reports, formatted = xpcall(function()
    return M.inspect(lines, o.strict)
  end, debug.traceback)
  if not done then
    release_copy(path, held)
    error(text, 0)
  end
  --- written as the editor writes a file; one that does not
  --- format stays byte for byte
  local new = formatted and textfile.text(text) or s
  local changed = new ~= s
  local status = 0
  if changed and o.fix then
    local written, kept = write_file(path, new, held)
    if not written then
      io.stderr:write(path .. ': cannot be written'
        .. (kept and ('; its formatted text is in ' .. kept)
          or '') .. '\n')
      status = 2
    end
  else
    release_copy(path, held)
  end
  if changed and not o.fix then
    print(path .. ': not formatted')
  end
  for _, r in ipairs(reports) do
    print(path .. ':' .. r)
  end
  if status == 0
      and (#reports > 0 or changed and not o.fix) then
    status = 1
  end
  return status
end

--- @param args string[]
--- @return integer --- the exit status
function M.main(args)
  local o = options(args)
  if not o or #o.files == 0 then
    io.stderr:write(USAGE)
    return 2
  end
  local status = 0
  for _, path in ipairs(o.files) do
    status = math.max(status, check_file(path, o))
  end
  return status
end

--- run as a script, not required as a module
if arg and arg[0] and string.match(arg[0], 'compyfmt%.lua$') then
  os.exit(M.main(arg))
end
return M
