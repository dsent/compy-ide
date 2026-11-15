local P = require('harmony.probe')
local D = require('harmony.drive')

--- The two marks at the screen's edges (the maintainer's
--- rulings of November 15, 2026), read from its pixels against
--- the theme (conf/colors.lua): the continuation cue, the edge
--- row's fade and the mark in its last column (FR4.8), and a
--- wrapped line's marks at the top right of each row that
--- goes on and the bottom left of each row that continues it,
--- on gray, white and yellow rows and in the field.

local PROJECT = 'h-edges'

--- @return table
local function theme() return P.cc().cfg.view.colors end

--- `c` blended over `under` at opacity `a`
--- @return number[]
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

--- @param img love.ImageData
--- @return number[]
local function px(img, x, y)
  local r, g, b = img:getPixel(x, y)
  return { r, g, b }
end

--- the darkest pixel's brightness in a band of pixel rows
local function darkest(img, x0, x1, y0, y1)
  local min = 1
  for y = y0, y1 do
    for x = x0, x1 do
      local r, g, b = img:getPixel(x, y)
      min = math.min(min, (r + g + b) / 3)
    end
  end
  return min
end

--- where the document view's wrapped row `v` starts
local function row_y(v)
  local bv = P.view()
  return bv:top() + (v - bv.content.offset - 1)
      * P.cc().cfg.view.fh
end

scenario('cue', function(wait)
  local t = theme()
  local cue = t.editor.cue
  local v = P.cc().cfg.view
  local fh = v.fh
  local lines = { 'a = 1', 'function f()' }
  for i = 1, 22 do lines[#lines + 1] = '  v' .. i .. ' = ' .. i end
  lines[#lines + 1] = 'end'
  lines[#lines + 1] = 'b = 2'
  wait(.1)
  D.open(wait, PROJECT, 'cue.lua',
    { ['cue.lua'] = table.concat(lines, '\n') .. '\n' })
  -- onto the tall block from below, then on up by rows until
  -- it goes on beyond both edges
  D.press(wait, 'up', 2)
  local bv = P.view()
  for _ = 1, 4 do D.key(wait, 'up') end
  D.eq(P.position(), 2, 'the browsed block')
  local rows = bv:_block_rows(2)
  local r = bv.content.range
  assert(rows[1] < r.start and r.fin < rows[#rows],
    'the block goes on beyond both edges')
  local img = P.capture(wait)
  D.shot(wait, 'both-edges')
  local box = over(t.editor.highlight, cue.box, cue.box_alpha)
  for _, edge in ipairs({ { 'top', r.start }, { 'bottom', r.fin } }) do
    local y = row_y(edge[2])
    local bg, fg = P.colors(img, (v.drawableChars - 1) * v.fw, y,
      v.fw, fh)
    is(bg, box, 'the mark\'s box at the ' .. edge[1])
    is(fg, over(box, cue.mark, cue.mark_alpha),
      'the mark at the ' .. edge[1])
    -- the edge row fades: its text in the middle of the row
    -- is lighter than the row beside it, on the same white
    local inner = edge[1] == 'top' and y + fh or y - fh
    local faded = darkest(img, 0, 15 * v.fw, y + 12, y + 20)
    local plain = darkest(img, 0, 15 * v.fw, inner + 12,
      inner + 20)
    assert(plain < .15 and .25 < faded, string.format(
      'the %s row fades: its darkest %.2f, the next row\'s %.2f',
      edge[1], faded, plain))
    is(P.cell(img, 30, 1, y), t.editor.highlight,
      'the faded row\'s background at the ' .. edge[1])
  end
  D.leave(wait)
  hm_done()
end)

scenario('wrap-mark', function(wait)
  local t = theme()
  local v = P.cc().cfg.view
  local fh = v.fh
  local right = v.drawableChars * v.fw
  local dots = string.rep('.', 150)
  local low = string.rep('_', 80)
  wait(.1)
  D.open(wait, PROJECT, 'marks.txt', { ['marks.txt'] =
    table.concat({ dots, 'one', dots, dots, 'end', low }, '\n')
    .. '\n' })
  -- line 4 the target, line 3 browsed, line 1 plain
  D.press(wait, 'up', 3)
  D.key(wait, 'f2')
  D.key(wait, 'C-up')
  D.eq(P.target(), 4, 'the target')
  D.eq(P.position(), 3, 'the browsed line')
  local img = P.capture(wait)
  D.shot(wait, 'marks')
  local mark = t.editor.wrap_mark
  local fwd = P.view().content.wrap_forward
  local function on(x, y) return P.near(px(img, x, y), mark.color) end
  --- the end mark: the top right corner of the row at y
  local function ends(y, what)
    is(px(img, right - 1, y), mark.color, what .. ', its corner')
    is(px(img, right - 5, y), mark.color, what .. ', along the top')
    is(px(img, right - 1, y + 4), mark.color, what .. ', down the edge')
    assert(not on(right - 3, y + 3), what .. ': hollow inside')
  end
  --- the start mark: the bottom left corner of the row at y
  local function starts(y, what)
    local b = y + fh - 1
    is(px(img, 0, b), mark.color, what .. ', its corner')
    is(px(img, 4, b), mark.color, what .. ', along the bottom')
    is(px(img, 0, b - 4), mark.color, what .. ', up the edge')
    assert(not on(2, b - 2), what .. ': hollow inside')
  end
  for _, l in ipairs({ { 1, 'gray' }, { 3, 'white' },
    { 4, 'yellow' } }) do
    local rows = fwd[l[1]]
    D.eq(#rows, 3, 'the rows of line ' .. l[1])
    local what = 'the ' .. l[2] .. ' line'
    local y1, y2, y3 = row_y(rows[1]), row_y(rows[2]), row_y(rows[3])
    ends(y1, what .. ', row 1 goes on')
    ends(y2, what .. ', row 2 goes on')
    starts(y2, what .. ', row 2 continues')
    starts(y3, what .. ', row 3 continues')
    assert(not on(0, y1 + fh - 1), what .. ': row 1 continues nothing')
    assert(not on(right - 1, y3), what .. ': row 3 goes on to nothing')
  end
  local one = row_y(fwd[2][1])
  assert(not on(0, one + fh - 1) and not on(right - 1, one),
    'a line of one row has no mark')
  -- under the text: on the row that continues a line of _, the
  -- underscore's ink keeps its colour over the mark, and the
  -- mark shows around it
  local u = row_y(fwd[6][2])
  local ink, shown = 0, 0
  for x = 0, 4 do
    for y = u + fh - 5, u + fh - 1 do
      local c = px(img, x, y)
      if P.near(c, t.editor.fg) then ink = ink + 1 end
      if P.near(c, mark.color) then shown = shown + 1 end
    end
  end
  assert(0 < ink, 'the underscore\'s ink over the mark')
  assert(0 < shown, 'the mark around the underscore')
  -- the draft in the field: line 4, three rows under the
  -- status line
  local _, bottom = P.band(img, t.statusline.editor.bg)
  local first = bottom + 1
  ends(first, 'the field, row 1')
  starts(first + fh, 'the field, row 2')
  assert(not on(0, first + fh - 1), 'the field: row 1 continues nothing')
  D.leave(wait)
  hm_done()
end)
