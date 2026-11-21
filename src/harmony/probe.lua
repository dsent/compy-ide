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

--- "notice" for a notice, "error" for a parser or load error,
--- nil when none shows over the console's field
--- @return string?
function Probe.console_message_kind()
  return Probe.cc().input:message_kind()
end

--- Whether a key card shows, the console's or the editor's
--- @return boolean
function Probe.card()
  return Probe.cc():card_shows()
end

--- The console's text: its rows with what is still being
--- printed put where it will be written, at the cursor. A
--- line the terminal is in the middle of writing reads whole
--- then: its start on the cursor's row, its rest still waiting
--- (the terminal writes 800 characters a second, so a check
--- made 30 ms after Enter meets it mid-line).
--- @return string
function Probe.console_text()
  local term = Probe.cc().model.output.terminal
  local function row(y)
    return (table.concat(term.buffer[y]):gsub('%s+$', ''))
  end
  local pending = {}
  for c in term:waiting() do
    if type(c) == 'string' then pending[#pending + 1] = c end
  end
  local rows = {}
  for y = 1, #term.buffer do rows[y] = row(y) end
  if #pending > 0 then
    --- the cursor's row up to the cursor, then what waits; a
    --- full row's cursor waits past its last column, and what
    --- comes next starts the next row
    local y = math.min(term.cursor_y, #term.buffer)
    local before = math.min(term.cursor_x - 1, term.width)
    local head = table.concat(term.buffer[y], '', 1, before)
    local wraps = term.cursor_x > term.width and pending[1] ~= '\n'
    rows[y] = head .. (wraps and '\n' or '') .. table.concat(pending)
  end
  return table.concat(rows, '\n')
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

--- The three text fields: the editor's, the console's, and a
--- running program's (nil when it shows none)
--- @param which 'editor'|'console'|'program'
--- @return UserInputController?
function Probe.field(which)
  if which == 'editor' then return Probe.ed().input end
  if which == 'console' then return Probe.cc().input end
  local ui = love.state.user_input
  return ui and ui.C
end

--- A field's draft, its lines joined with a line break
--- @param which 'editor'|'console'|'program'
--- @return string
function Probe.text(which)
  return text_of(Probe.field(which))
end

--- A field's cursor
--- @param which 'editor'|'console'|'program'
--- @return integer line, integer column
function Probe.field_cursor(which)
  return Probe.field(which).model:get_cursor_pos()
end

--- The document view of the open file
--- @return BufferView
function Probe.view()
  return Probe.ed().view:get_current_buffer()
end

--- How many rows block `b` has, and how many the document
--- view shows
--- @param b integer
--- @return integer rows, integer shown
function Probe.rows_shown(b)
  local bv = Probe.view()
  local content = bv.content
  local rows = {}
  if 0 < b and b <= #content.v_blocks then
    local pos = content:get_block_pos(b)
    for _, l in ipairs(pos and pos:enumerate() or {}) do
      for _, r in ipairs(content.wrap_forward[l] or {}) do
        rows[#rows + 1] = r
      end
    end
  end
  local shown = 0
  for _, r in ipairs(rows) do
    if content.range:inc(r) then shown = shown + 1 end
  end
  return #rows, shown
end

--- Every row of block `b` is in the document view
--- @param b integer
--- @return boolean
function Probe.in_view(b)
  local rows, shown = Probe.rows_shown(b)
  return 0 < rows and rows == shown
end

--- The first and the last block wholly in the document view
--- @return integer? first, integer? last
function Probe.blocks_in_view()
  local first, last
  for b = 1, Probe.blocks() do
    if Probe.in_view(b) then
      first = first or b
      last = b
    end
  end
  return first, last
end

--- The document view's first row
--- @return integer
function Probe.offset()
  return Probe.view():get_offset()
end

-- what the screen shows, as pixels ------------------------

--- The screen as it is drawn now, as image data
--- @param wait function
--- @return love.ImageData
function Probe.capture(wait)
  local got
  love.graphics.captureScreenshot(function(img) got = img end)
  for _ = 1, 50 do
    if got then return got end
    wait(.02)
  end
  error('no screenshot came back')
end

--- @param img love.ImageData
--- @param x integer
--- @param y integer
--- @return string --- the pixel as 'r,g,b', 0 to 255
local function pixel(img, x, y)
  local r, g, b = img:getPixel(x, y)
  return string.format('%d,%d,%d', math.floor(r * 255 + .5),
    math.floor(g * 255 + .5), math.floor(b * 255 + .5))
end

--- @param key string
--- @return number[]
local function rgb(key)
  local t = {}
  for n in string.gmatch(key, '%d+') do t[#t + 1] = n / 255 end
  return t
end

--- The pixel rectangle of a cell: `col` and `row` count from
--- 1, `top` is the y of the first row of the grid the cell is
--- on
--- @param col integer
--- @param row integer
--- @param top integer?
--- @return integer x, integer y, integer w, integer h
function Probe.cell_rect(col, row, top)
  local v = Probe.cc().cfg.view
  return (col - 1) * v.fw, (top or 0) + (row - 1) * v.fh,
      v.fw, v.fh
end

--- A rectangle's background, the colour most of its pixels
--- have, and its glyph's, the colour most of the others have
--- (nil when there are none)
--- @param img love.ImageData
--- @param x integer
--- @param y integer
--- @param w integer
--- @param h integer
--- @return number[] bg, number[]? fg
function Probe.colors(img, x, y, w, h)
  local count = {}
  for py = y, math.min(y + h, img:getHeight()) - 1 do
    for px = x, math.min(x + w, img:getWidth()) - 1 do
      local k = pixel(img, px, py)
      count[k] = (count[k] or 0) + 1
    end
  end
  local bg, most = nil, -1
  for k, n in pairs(count) do
    if n > most then bg, most = k, n end
  end
  local bgc = rgb(bg)
  --- the glyph: the commonest colour well apart from the
  --- background, so that an edge blended with it is skipped
  local fg, fmost = nil, 0
  for k, n in pairs(count) do
    local c = rgb(k)
    local far = math.abs(c[1] - bgc[1]) + math.abs(c[2] - bgc[2])
        + math.abs(c[3] - bgc[3])
    if far > .45 and n > fmost then fg, fmost = k, n end
  end
  return bgc, fg and rgb(fg)
end

--- A cell's background and glyph colours
--- @param img love.ImageData
--- @param col integer
--- @param row integer
--- @param top integer?
--- @return number[] bg, number[]? fg
function Probe.cell(img, col, row, top)
  return Probe.colors(img, Probe.cell_rect(col, row, top))
end

--- Whether colour `c` is the theme's `want`, within a margin
--- for antialiasing and rounding
--- @param c number[]?
--- @param want number[]
--- @return boolean
function Probe.near(c, want)
  if not c then return false end
  for i = 1, 3 do
    if math.abs(c[i] - want[i]) > .1 then return false end
  end
  return true
end

--- @param c number[]?
--- @return string
function Probe.show(c)
  if not c then return 'none' end
  return string.format('#%02X%02X%02X', math.floor(c[1] * 255 + .5),
    math.floor(c[2] * 255 + .5), math.floor(c[3] * 255 + .5))
end

--- The status line's band: the first and last pixel rows,
--- read down the screen's left column, of the longest run of
--- `color`
--- @param img love.ImageData
--- @param color number[]
--- @return integer? first, integer? last
function Probe.band(img, color)
  local best_a, best_b, a
  for y = 0, img:getHeight() - 1 do
    local on = Probe.near(rgb(pixel(img, 1, y)), color)
    if on and not a then a = y end
    if a and (not on or y == img:getHeight() - 1) then
      local b = on and y or y - 1
      if not best_a or b - a > best_b - best_a then
        best_a, best_b = a, b
      end
      a = nil
    end
  end
  return best_a, best_b
end

local recording

--- Record the text the screen draws while `wait` runs for
--- `t` seconds, a frame or more. A status line the console's
--- field kept from an earlier frame (UserInputView:draw) is
--- rendered anew first, so that its text is among it. That
--- hides a kept line gone stale: what this records is the
--- line as a fresh render makes it, and a picture of the
--- screen taken before this call is the one that shows what
--- was kept.
--- @param wait function
--- @param t number?
--- @return string[] --- each string drawn, in order
function Probe.drawn(wait, t)
  local gfx = love.graphics
  Probe.cc().view.input.bare_drawn = nil
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
