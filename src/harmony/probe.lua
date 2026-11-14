--- What a scenario reads from the running IDE to check what a
--- person meets: the editor's state in the specification's
--- terms, the console, the files on storage, and the text drawn
--- on screen. It reads and changes nothing.
local Probe = {}

local cc

--- The console controller. The IDE keeps it in the closures of
--- its LÖVE handlers alone, so it is read from the key
--- handler's upvalues.
--- @return ConsoleController
function Probe.cc()
  if cc then return cc end
  local f = Controller._defaults.keypressed
  local i = 1
  while true do
    local name, v = debug.getupvalue(f, i)
    if not name then break end
    if name == 'CC' then
      cc = v
      return cc
    end
    i = i + 1
  end
  error('the console controller was not found')
end

--- @return EditorController
function Probe.ed()
  return Probe.cc().editor
end

--- @return BufferModel?
function Probe.buffer()
  return Probe.ed():get_active_buffer()
end

--- "browsing", "inserting" or "replacing"
--- @return string
function Probe.state()
  return Probe.ed():state_name()
end

--- The open file's name, nil when none is open
--- @return string?
function Probe.file()
  local b = Probe.buffer()
  return b and b.name
end

--- The number of blocks in the open file
--- @return integer
function Probe.blocks()
  return Probe.buffer():get_content_length()
end

--- The browsing position: a block's number, or "end"
--- @return integer|string
function Probe.position()
  local sel = Probe.buffer():get_selection()
  if Probe.blocks() < sel then return 'end' end
  return sel
end

--- The replacement target's block number, or nil
--- @return integer?
function Probe.target()
  return Probe.buffer().loaded
end

--- @param input UserInputController
--- @return string
local function text_of(input)
  local t = input:get_text()
  if type(t) == 'table' then return table.concat(t, '\n') end
  return t or ''
end

--- The editor's draft, its lines joined with a line break
--- @return string
function Probe.draft()
  return text_of(Probe.ed().input)
end

--- The console's draft
--- @return string
function Probe.console_draft()
  return text_of(Probe.cc().input)
end

--- The editor's cursor
--- @return integer line, integer column
function Probe.cursor()
  return Probe.ed().input.model:get_cursor_pos()
end

--- @param e any
--- @return string?
local function message_of(e)
  if type(e) ~= 'table' then return e and tostring(e) end
  if #e == 0 then return nil end
  local out = {}
  for i, v in ipairs(e) do
    out[i] = type(v) == 'table' and tostring(v.msg or v[1])
        or tostring(v)
  end
  return table.concat(out, ' ')
end

--- The message over the editor's field, nil when none shows
--- @return string?
function Probe.message()
  return message_of(Probe.ed().input.model.error)
end

--- "notice" for a refusal's message, "error" for the
--- parser's, nil when none shows
--- @return string?
function Probe.message_kind()
  return Probe.ed():message_kind()
end

--- The console's error message, nil when none shows
--- @return string?
function Probe.console_message()
  return message_of(Probe.cc().input.model.error)
end

--- Whether a key card shows, the console's or the editor's
--- @return boolean
function Probe.card()
  return Probe.cc():card_shows()
end

--- The console's text: its rows, then what is still being
--- printed
--- @return string
function Probe.console_text()
  local term = Probe.cc().model.output.terminal
  local rows, pending = {}, {}
  for y, row in ipairs(term.buffer) do
    rows[y] = table.concat(row):gsub('%s+$', '')
  end
  for _, c in ipairs(term.stdin) do
    if type(c) == 'string' then pending[#pending + 1] = c end
  end
  return table.concat(rows, '\n') .. table.concat(pending)
end

--- A project's file as storage holds it, nil when it is not
--- there
--- @param project string
--- @param file string
--- @return string?
function Probe.stored(project, file)
  local path = FS.join_path(
    love.harmony.tmpdir, 'projects', project, file)
  if not FS.exists(path) then return nil end
  return FS.read(path)
end

--- Write a project's file directly to storage, as a test
--- fixture: the editor has not seen it
--- @param project string
--- @param file string
--- @param text string
function Probe.put(project, file, text)
  local path = FS.join_path(
    love.harmony.tmpdir, 'projects', project, file)
  assert(FS.write(path, text), 'cannot write ' .. path)
end

local recording

--- Record the text the screen draws while `wait` runs for
--- `t` seconds, a frame or more
--- @param wait function
--- @param t number?
--- @return string[] --- each string drawn, in order
function Probe.drawn(wait, t)
  local gfx = love.graphics
  local print_, printf_ = gfx.print, gfx.printf
  recording = {}
  local got = recording
  local function rec(text, ...)
    got[#got + 1] = tostring(text)
  end
  gfx.print = function(text, ...)
    rec(text)
    return print_(text, ...)
  end
  gfx.printf = function(text, ...)
    rec(text)
    return printf_(text, ...)
  end
  wait(t or .05)
  gfx.print, gfx.printf = print_, printf_
  recording = nil
  return got
end

--- Whether any string drawn holds `s`, as plain text
--- @param drawn string[]
--- @param s string
--- @return boolean
function Probe.shows(drawn, s)
  for _, d in ipairs(drawn) do
    if string.find(d, s, 1, true) then return true end
  end
  return false
end

return Probe
