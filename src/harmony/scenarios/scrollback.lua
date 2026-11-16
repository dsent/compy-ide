local P = require('harmony.probe')
local D = require('harmony.drive')

--- The console's scrollback (the maintainer's ruling "Console
--- scrollback, first version"), read from the screen's pixels
--- against the theme (conf/colors.lua): the screen at rest, a
--- row up, a page up and the oldest row, each with the editor's
--- continuation cue at a cut edge and none at rest; the first
--- step from a nearly empty screen, which fills it; the echo of
--- an entered line in blue and its error after it in the
--- output's error color; the key card's rows; and a row printed
--- in one print against a print for each of its cells.

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
  -- the line kept in the field goes
  D.key(wait, 'escape')
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

--- The output prints a row's text in runs, a print for each
--- (view/canvas/terminalView.lua). That puts a character where a
--- print of its own at its cell put it, pixel for pixel, as long
--- as it advances by a cell's width: so do the letters and
--- signs of ASCII, Latin-1 and Russian and the box and block
--- characters. A fallback font's character does not, and the
--- view prints it at its own cell.
scenario('runs', function(wait)
  wait(.1)
  local utf8 = require('utf8')
  local gfx = love.graphics
  local v = P.cc().cfg.view
  local font, cw, ch = v.font, v.fw, v.fh

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

  --- `text` on a row, in one print or a print for each cell
  local function picture(text, by_cell)
    local canvas = gfx.newCanvas(64 * cw, ch)
    gfx.push('all')
    gfx.setCanvas(canvas)
    gfx.origin()
    gfx.clear(0.75, 0.75, 0.75, 1)
    gfx.setFont(font)
    gfx.setColor(0, 0, 0, 1)
    if by_cell then
      local x = 0
      for _, code in utf8.codes(text) do
        gfx.print(utf8.char(code), x * cw, 0)
        x = x + 1
      end
    else
      gfx.print(text, 0, 0)
    end
    gfx.pop()
    return canvas:newImageData():getString()
  end

  local sets = {
    { 'ASCII', range(0x20, 0x7E) },
    { 'Latin-1', range(0xA1, 0xFF) },
    { 'Russian', range(0x410, 0x451) },
    { 'box characters', range(0x2500, 0x257F) },
    { 'block characters', range(0x2580, 0x259F) },
  }
  for _, set in ipairs(sets) do
    for _, row in ipairs(set[2]) do
      for _, code in utf8.codes(row) do
        local char = utf8.char(code)
        D.eq(font:getWidth(char), cw,
          'the advance of ' .. char .. ' (' .. set[1] .. ')')
      end
      -- once to bring the row's glyphs into the font's texture
      picture(row, true)
      assert(picture(row, true) == picture(row, false),
        set[1] .. ': one print differs from a print a cell: ' .. row)
    end
  end
  -- an arrow from the icon font and a CJK character advance by
  -- more than a cell
  for _, char in ipairs({ '→', '日' }) do
    assert(font:getWidth(char) ~= cw,
      char .. ' advances by a cell: the view would print it in a run')
  end
  hm_done()
end)
