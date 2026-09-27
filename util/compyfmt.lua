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

--- Write beside the file first, so a disk that cannot take the
--- text fails with the file as it was; then write the same text
--- into the file itself, which keeps its mode, owner and inode.
--- When that second write fails part way, the text stays beside
--- the file, and while it is there the file is not written again:
--- it may be the only whole copy of the program. The copy is
--- only ever created ('x'), so one that another run made in the
--- meantime is never written over.
--- @param path string
--- @param text string
--- @return boolean written
--- @return string? kept --- the copy beside the file, if any
--- @return 'left'|'partial'|nil --- found there, or left just now
local function write_file(path, text)
  local tmp = copy_path(path)
  --- @diagnostic disable-next-line: param-type-mismatch
  local c = io.open(tmp, 'wbx')
  if not c then
    if is_there(tmp) then return false, tmp, 'left' end
    return false
  end
  if not write_to(c, text) then
    os.remove(tmp)
    return false
  end
  local f = io.open(path, 'wb')
  if not f then
    os.remove(tmp)
    return false
  end
  if not write_to(f, text) then return false, tmp, 'partial' end
  os.remove(tmp)
  return true
end

--- @param path string
--- @param kept string
local function report_left(path, kept)
  io.stderr:write(path .. ': not written, because ' .. kept
    .. ' is there from an earlier --fix that did not finish'
    .. ' and may hold the only whole copy of the program;'
    .. ' compare the two, keep the whole one as ' .. path
    .. ', and remove ' .. kept .. '\n')
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
    local s = read_file(path)
    if fix and is_there(copy_path(path)) then
      --- whatever the file holds now, even text that needs no
      --- formatting, it may be cut short
      report_left(path, copy_path(path))
      status = 2
    elseif not s then
      io.stderr:write(path .. ': cannot be read\n')
      status = 2
    else
      local lines = textfile.lines(s)
      local text, reports, formatted =
          M.inspect(lines, o.strict)
      --- written as the editor writes a file; one that does not
      --- format stays byte for byte
      local new = formatted and textfile.text(text) or s
      local changed = new ~= s
      local written, kept, why = true, nil, nil
      if changed and fix then
        written, kept, why = write_file(path, new)
      end
      if why == 'left' then
        report_left(path, copy_path(path))
        status = 2
      elseif not written then
        io.stderr:write(path .. ': cannot be written'
          .. (kept and ('; its formatted text is in ' .. kept)
            or '') .. '\n')
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
