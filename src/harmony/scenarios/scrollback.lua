local P = require('harmony.probe')
local D = require('harmony.drive')

--- The console's scrollback (the maintainer's ruling "Console
--- scrollback, first version"), read from the screen's pixels
--- against the theme (conf/colors.lua): the screen at rest, a
--- row up, a page up and the oldest row, each with the editor's
--- continuation cue at a cut edge and none at rest; the first
--- step from a nearly empty screen, which fills it; the echo of
--- an entered line in blue and its error after it in the
--- output's error color; the key card's rows; the seventeenth
--- row behind a program; and a row printed in one print against
--- a print for each of its cells.

--- @return table
local function theme() return P.cc().cfg.view.colors end

local function view() return P.cc().cfg.view end

--- where the output's first row starts
local function top()
  return require('view.layout')(view()).top
end

local function output() return P.cc().model.output end

local function rows() return output().terminal.height end

--- `c` blended over `under` at opacity `a`
local function over(under, c, a)
  return {
    under[1] * (1 - a) + c[1] * a,
    under[2] * (1 - a) + c[2] * a,
    under[3] * (1 - a) + c[3] * a,
  }
end

local function is(c, want, what)
  assert(P.near(c, want), string.format('%s: %s, the theme makes %s',
    what, P.show(c), P.show(want)))
end

--- whether the output's row `r` carries the cue's mark: its
--- last cell is the mark's box with the mark on it
local function cue_at(img, r)
  local t, v = theme(), view()
  local cue = t.editor.cue
  local box = over(t.terminal.bg, cue.box, cue.box_alpha)
  local bg, fg = P.cell(img, v.drawableChars, r, top())
  return P.near(bg, box)
      and P.near(fg, over(box, cue.mark, cue.mark_alpha))
end

--- the cue on the top edge and on the bottom edge, as drawn
local function cues(img)
  return { cue_at(img, 1), cue_at(img, rows()) }
end

local function same(got, want, what)
  D.eq(tostring(got[1]) .. '/' .. tostring(got[2]),
    tostring(want[1]) .. '/' .. tostring(want[2]), what)
end

--- the output takes its time: 800 characters a second
local function settle(wait) wait(1) end

scenario('views', function(wait)
  wait(.1)
  D.key(wait, 'C-l')
  D.enter(wait, "for i = 1, 60 do print('line ' .. i) end")
  settle(wait)
  local img = P.capture(wait)
  D.shot(wait, 'at-rest')
  same(cues(img), { false, false }, 'no cue at rest')

  D.key(wait, 'C-up')
  assert(output():is_scrolled(), 'Ctrl+Up scrolls')
  img = P.capture(wait)
  D.shot(wait, 'one-row-up')
  same(cues(img), { true, false }, 'one row up: older rows above')

  D.key(wait, 'pageup')
  img = P.capture(wait)
  D.shot(wait, 'page-up')
  same(cues(img), { true, true }, 'a page up: rows on both sides')

  D.key(wait, 'home')
  img = P.capture(wait)
  D.shot(wait, 'oldest-row')
  same(cues(img), { false, true }, 'at the oldest kept row')
  D.eq(output().view_top, output().kept.first, 'the oldest row on top')

  D.key(wait, 'end')
  assert(not output():is_scrolled(), 'End: the screen at rest')
  hm_done()
end)

scenario('filled', function(wait)
  wait(.1)
  D.key(wait, 'C-l')
  D.enter(wait, "for i = 1, 40 do print('line ' .. i) end")
  settle(wait)
  D.enter(wait, 'compy.terminal.clear()')
  D.enter(wait, "print('after the clear')")
  settle(wait)
  D.key(wait, 'C-up')
  local img = P.capture(wait)
  D.shot(wait, 'first-step-after-clear')
  local t, v = theme(), view()
  --- every row of the filled view holds text: a dark glyph in
  --- its first cells
  for r = 1, rows() do
    local _, fg = P.colors(img, 0, top() + (r - 1) * v.fh,
      6 * v.fw, v.fh)
    assert(fg, 'row ' .. r .. ' of the filled view holds text')
  end
  local _, last = P.cell(img, 1, rows(), top())
  is(last, t.terminal.fg, 'the newest row at the bottom')
  D.key(wait, 'end')
  hm_done()
end)

scenario('echo', function(wait)
  local t = theme()
  wait(.1)
  D.key(wait, 'C-l')
  D.enter(wait, "print('hi') error('boom')")
  settle(wait)
  local img = P.capture(wait)
  D.shot(wait, 'echo-with-error')
  local _, echo = P.cell(img, 1, 1, top())
  is(echo, t.terminal.echo, 'the echo is blue')
  local _, out = P.cell(img, 1, 2, top())
  is(out, t.terminal.fg, 'what it printed is in the output\'s color')
  local _, err = P.cell(img, 1, 3, top())
  is(err, t.terminal.error, 'its error is in the output\'s error color')
  assert(P.console_text():find('boom', 1, true), 'the error is written')
  assert(P.console_message() == nil, 'the error is not in the band')
  -- the line that ran left the field, error or not
  D.eq(P.console_draft(), '', 'the field, emptied')
  hm_done()
end)

scenario('card', function(wait)
  wait(.1)
  -- Home and End are listed while the field is empty
  D.eq(P.console_draft(), '', 'the field')
  D.with_card(wait, function()
    D.shot(wait, 'key-card')
    assert(P.card(), 'the card shows')
    local card = table.concat(P.cc():key_card() or { }, '\n')
    assert(card:find('scroll a row', 1, true), 'Ctrl+Up/Down on the card')
    assert(card:find('oldest/newest', 1, true), 'Home/End on the card')
  end)
  hm_done()
end)

--- An empty print makes a blank row: entered in the console and
--- printed by a program, the two lines around it have a row
--- between them. A line as wide as the screen makes none: the
--- line after it is on the next row.
scenario('blank-row', function(wait)
  wait(.1)
  D.key(wait, 'escape')
  D.key(wait, 'C-l')

  --- the output's rows from the row that is `first` to the row
  --- that is `last`
  local function from_to(first, last)
    local t, out = output().terminal, nil
    for _, chars in ipairs(t.buffer) do
      local r = table.concat(chars):gsub('%s+$', '')
      if r == first then out = { } end
      if out then out[#out + 1] = r end
      if out and r == last then return table.concat(out, '|') end
    end
    return out and table.concat(out, '|') or 'no row ' .. first
  end

  D.enter(wait, "print('one') print('') print('two')")
  settle(wait)
  D.eq(from_to('one', 'two'), 'one||two', 'print(\'\') in the console')
  D.enter(wait, "print('three') print() print('four')")
  settle(wait)
  D.eq(from_to('three', 'four'), 'three||four',
    'print() in the console')
  D.enter(wait, "io.write('five') io.write('\\n\\n') io.write('six\\n')")
  settle(wait)
  D.eq(from_to('five', 'six'), 'five||six', 'io.write of two line ends')
  D.shot(wait, 'blank-rows')

  -- a line as wide as the screen takes its row and no more: the
  -- next line is right under it, and one empty print makes one
  -- blank row
  D.key(wait, 'C-l')
  local full = string.rep('x', output().terminal.width)
  D.enter(wait, "print(('x'):rep(64)) print('under')")
  settle(wait)
  D.eq(from_to(full, 'under'), full .. '|under',
    'a line of 64 characters, then a line')
  D.key(wait, 'C-l')
  D.enter(wait, "print(('x'):rep(64)) print('') print('under')")
  settle(wait)
  D.eq(from_to(full, 'under'), full .. '||under',
    'a line of 64 characters, an empty print, then a line')
  D.shot(wait, 'full-row')

  D.enter(wait, "project('h-blank')")
  P.put('h-blank', 'main.lua',
    "print('seven')\nprint('')\nprint('eight')\n")
  D.enter(wait, 'run_project()')
  settle(wait)
  D.eq(from_to('seven', 'eight'), 'seven||eight',
    'print(\'\') in a program')
  D.key(wait, 'C-q')
  hm_done()
end)

--- The field's row is the output's while no input field is
--- drawn (the maintainer's ruling of November 17, 2026): behind a
--- program that owns the input and shows no field the grid has
--- 17 rows, text shows on the seventeenth, and the status line is
--- the screen's last row, naming the project, the file and that
--- it runs. Once the field is back the grid has 16, and what was
--- on the seventeenth row has scrolled up.
scenario('seventeenth-row', function(wait)
  wait(.1)
  D.key(wait, 'escape')
  D.key(wait, 'C-l')
  D.enter(wait, "project('h-rows')")
  P.put('h-rows', 'main.lua',
    "for i = 1, 16 do print('row ' .. i) end\n"
    .. "compy.terminal.gotoxy(1, 17)\n"
    .. "io.write('the seventeenth')\n"
    .. "compy.input.hooks.keypressed = function() return true end\n"
    .. "function love.update() end\n")
  D.enter(wait, 'run_project()')
  settle(wait)
  local t, th, v = output().terminal, theme(), view()
  local lay = require('view.layout')(v)

  --- the grid's row `y`, spaces at its end left out
  local function row(y)
    return (table.concat(t.buffer[y]):gsub('%s+$', ''))
  end

  D.eq(t.height, 17, 'rows behind a program that owns the input')
  D.eq(row(17), 'the seventeenth', 'the seventeenth row')
  local img = P.capture(wait)
  local says = P.drawn(wait)
  D.shot(wait, 'seventeen-rows')
  local _, ink = P.cell(img, 1, 17, top())
  is(ink, th.terminal.fg, 'the text on the seventeenth row')
  local first = P.band(img, th.statusline.user.bg)
  D.eq(first, v.h - lay.bottom - lay.status_h,
    "the status line's first pixel row")
  for _, word in ipairs({ 'h-rows', 'main.lua', 'running' }) do
    assert(P.shows(says, word), 'the status line does not say ' .. word)
  end
  assert(not P.shows(says, 'L1'), 'the status line shows a position')

  D.key(wait, 'C-q')
  wait(.2)
  D.eq(t.height, 16, 'rows once the field is back')
  D.eq(row(16), 'the seventeenth', 'the seventeenth row, scrolled up')
  img = P.capture(wait)
  D.shot(wait, 'sixteen-rows-again')
  first = P.band(img, th.statusline.console.bg)
  D.eq(first, v.h - lay.bottom - v.fh - lay.status_h,
    "the status line's first pixel row over the field")
  hm_done()
end)

--- The first `rows` rows of the grid as the screen should show
--- them: every background, then each cell's character at its
--- own place, as bytes of pixels
--- @param t table --- the terminal
--- @param rows integer
--- @return string
local function grid_picture(t, rows)
  local gfx = love.graphics
  local cw, ch = t.char_width, t.char_height
  local canvas = gfx.newCanvas(t.width * cw, rows * ch)
  gfx.push('all')
  gfx.setCanvas(canvas)
  gfx.origin()
  gfx.clear(0, 0, 0, 1)
  gfx.setFont(t.font)
  for pass = 1, 2 do
    for y = 1, rows do
      for x, char in ipairs(t.buffer[y]) do
        local st = t.state_buffer[y][x]
        local back, fore = st.backcolor, st.color
        if st.reversed then back, fore = fore, back end
        local left, up = (x - 1) * cw, (y - 1) * ch
        if pass == 1 then
          gfx.setColor(back)
          gfx.rectangle('fill', left, up, cw, ch)
        else
          gfx.setColor(fore)
          gfx.print(char, left, up)
        end
      end
    end
  end
  gfx.pop()
  return canvas:newImageData():getString()
end

--- The screen's pixels over the grid's first `rows` rows
--- @param img love.ImageData
--- @param t table
--- @param rows integer
--- @return string
local function screen_rows(img, t, rows)
  local w, h = t.width * t.char_width, rows * t.char_height
  local part = love.image.newImageData(w, h)
  part:paste(img, 0, 0, 0, top(), w, h)
  return part:getString()
end

--- How many pixels of two pictures differ
local function differ(a, b)
  if a == b then return 0 end
  local n = 0
  for i = 1, #a, 4 do
    if a:sub(i, i + 3) ~= b:sub(i, i + 3) then n = n + 1 end
  end
  return n
end

--- A program that draws nothing of its own has no picture but
--- the output. When it pauses, and when it runs again after
--- continue(), the screen shows the grid's rows as they are, each
--- once: the pause's screenshot is the picture of a program
--- that draws, and laid under the output of one that does not
--- it showed every row twice, a row apart once the grid had
--- rolled for the field (seen on a Compy on November 17, 2026).
--- This is checked here and not in the unit tests: their
--- fixture's captureScreenshot never delivers, so no pause there
--- has a screenshot and nothing is drawn over one; what a pause
--- shows, pixel by pixel, is Harmony's to check.
scenario('paused-output', function(wait)
  wait(.1)
  D.key(wait, 'escape')
  D.key(wait, 'C-l')
  D.enter(wait, "project('h-paused')")
  P.put('h-paused', 'main.lua',
    "for i = 1, 16 do print(string.format('ROW %02d', i)) end\n"
    .. "io.write('ROW 17 holds text')\n"
    .. "function love.update() end\n")
  D.key(wait, 'C-l')
  D.enter(wait, 'run_project()')
  settle(wait)
  local t = output().terminal
  D.eq(t.height, 17, 'rows while the program runs')
  -- once to bring every glyph into the font's texture
  grid_picture(t, 17)

  D.key(wait, 'C-pause')
  wait(.5)
  D.in_state('inspect')
  D.eq(t.height, 16, 'rows at the pause')
  local img = P.capture(wait)
  D.shot(wait, 'paused-output')
  -- the notice band lies over the last row
  D.eq(differ(screen_rows(img, t, 15), grid_picture(t, 15)), 0,
    'pixels of the paused output that are not the grid\'s rows')

  D.key(wait, 'escape')
  D.enter(wait, 'continue()')
  settle(wait)
  D.in_state('running')
  D.eq(t.height, 17, 'rows once it runs again')
  img = P.capture(wait)
  D.shot(wait, 'continued-output')
  D.eq(differ(screen_rows(img, t, 17), grid_picture(t, 17)), 0,
    'pixels of the continued output that are not the grid\'s rows')

  D.key(wait, 'C-q')
  wait(.2)
  D.in_state('ready')
  hm_done()
end)

--- The output's view draws a row in runs: a rectangle for each
--- run of one background, a print for each run of one color
--- (view/canvas/terminalView.lua). Its picture is, pixel for
--- pixel, the one that all the backgrounds and then a print for
--- each cell at its own place make: a print of a run puts a
--- character where a print of its own puts it as long as the
--- character advances by a cell's width, as the letters and
--- signs of ASCII, Latin-1 and Russian and the box and block
--- characters do, and the view prints at its own cell one that
--- does not, as an arrow of the icon font or a CJK character.
--- A terminal of its own is filled and drawn by the view here,
--- and read twice: from its canvas, and from the screen, where
--- the view puts the canvas at the place it is given.
scenario('runs', function(wait)
  wait(.1)
  local utf8 = require('utf8')
  local Terminal = require('lib.terminal')
  local gfx = love.graphics
  local v = P.cc().cfg.view
  local font, cw, ch = v.font, v.fw, v.fh
  local colors = theme().terminal

  --- the characters `from` to `to`, in rows of 64
  local function range(from, to)
    local rows, row = { }, { }
    for code = from, to do
      row[#row + 1] = utf8.char(code)
      if #row == 64 or code == to then
        rows[#rows + 1] = table.concat(row)
        row = { }
      end
    end
    return rows
  end

  local sets = {
    { 'ASCII', range(0x20, 0x7E) },
    { 'Latin-1', range(0xA1, 0xFF) },
    { 'Russian', range(0x410, 0x451) },
    { 'box characters', range(0x2500, 0x257F) },
    { 'block characters', range(0x2580, 0x259F) },
  }
  local term = Terminal(64 * cw, 16 * ch, font, nil, ch)
  term:hide_cursor()
  term:set_cursor_color(unpack(colors.fg))
  term:set_cursor_backcolor(unpack(colors.bg))
  term:clear()
  for _, set in ipairs(sets) do
    for _, row in ipairs(set[2]) do
      for _, code in utf8.codes(row) do
        local char = utf8.char(code)
        D.eq(font:getWidth(char), cw,
          'the advance of ' .. char .. ' (' .. set[1] .. ')')
      end
      term:print(row .. (utf8.len(row) < 64 and '\n' or ''))
    end
  end
  -- characters that advance by more than a cell, among letters
  for _, char in ipairs({ '→', '日' }) do
    assert(font:getWidth(char) ~= cw,
      char .. ' advances by a cell: it tests no placing by cell')
  end
  term:print('ab→cd 日ef → 日 gh→→日日ij\n')
  -- runs of several colors and backgrounds, spaces among them
  term:print('black ')
  term:set_cursor_color(unpack(colors.echo))
  term:print('blue  blue ')
  term:set_cursor_backcolor(unpack(colors.fg))
  term:print(' on black ')
  term:reverse_cursor(true)
  term:print('reversed → and back')
  term:reverse_cursor(false)
  term:set_cursor_color(unpack(colors.fg))
  term:set_cursor_backcolor(unpack(colors.bg))
  term:print(' end\n')
  term:update(1000)
  assert(#term.stdin == 0, 'the terminal has written everything')

  --- the terminal as the view draws it
  local function by_view()
    term.dirty = true
    TerminalView.draw(term, term.canvas)
    return term.canvas:newImageData():getString()
  end

  --- the same cells: every background, then a print for each
  --- cell at its own place
  local function by_cell()
    local canvas = gfx.newCanvas(term.canvas:getDimensions())
    gfx.push('all')
    gfx.setCanvas(canvas)
    gfx.origin()
    gfx.clear(term.clear_color_alpha)
    gfx.setFont(font)
    for pass = 1, 2 do
      for y, chars in ipairs(term.buffer) do
        for x, char in ipairs(chars) do
          local st = term.state_buffer[y][x]
          local back, fore = st.backcolor, st.color
          if st.reversed then back, fore = fore, back end
          local left, top = (x - 1) * cw, (y - 1) * ch
          if pass == 1 then
            gfx.setColor(back)
            gfx.rectangle('fill', left, top, cw, ch)
          else
            gfx.setColor(fore)
            gfx.print(char, left, top)
          end
        end
      end
    end
    gfx.pop()
    return canvas:newImageData():getString()
  end

  -- once each to bring every glyph into the font's texture
  by_view()
  by_cell()
  local view, cells = by_view(), by_cell()
  if view ~= cells then
    local differ, first = 0, nil
    for i = 1, #view, 4 do
      if view:sub(i, i + 3) ~= cells:sub(i, i + 3) then
        differ = differ + 1
        first = first or (i - 1) / 4
      end
    end
    local w = 64 * cw
    error(string.format('the view\'s picture differs from a print a'
      .. ' cell in %d pixels, the first in row %d, column %d',
      differ, math.floor(first / w / ch) + 1,
      math.floor(first % w / cw) + 1))
  end

  -- On the screen: the view draws the terminal over the frame,
  -- 40 pixels down, and the screen holds the same picture there,
  -- on the frame's own pixels above and below it.
  local down = 40
  local w, h = term.canvas:getDimensions()
  local function strip(img, y, rows)
    local part = love.image.newImageData(w, rows)
    part:paste(img, 0, 0, 0, y, w, rows)
    return part:getString()
  end
  local frame = P.capture(wait)
  local draw = love.draw
  love.draw = function()
    draw()
    -- as the console's view calls it: no transform, no tint
    gfx.push('all')
    gfx.reset()
    term.dirty = true
    TerminalView.draw(term, term.canvas, nil, down)
    gfx.pop()
  end
  wait(.05)
  local shown = P.capture(wait)
  love.draw = draw
  local on_screen = strip(shown, down, h)
  if on_screen ~= cells then
    local differ = 0
    for i = 1, #cells, 4 do
      if on_screen:sub(i, i + 3) ~= cells:sub(i, i + 3) then
        differ = differ + 1
      end
    end
    error(string.format('the screen %d pixels down differs from the'
      .. ' terminal\'s picture in %d pixels', down, differ))
  end
  assert(strip(shown, 0, down) == strip(frame, 0, down),
    'the view drew above the place it was given')
  local under = shown:getHeight() - down - h
  assert(strip(shown, down + h, under) == strip(frame, down + h, under),
    'the view drew below the terminal\'s picture')
  hm_done()
end)
