local P = require('harmony.probe')
local D = require('harmony.drive')

--- The colours a person reads state by, read from the screen's
--- pixels and compared with the theme (conf/colors.lua) within
--- a margin for antialiasing: the white highlight on the
--- browsed block, the yellow on the replacement target and the
--- white strips beside it when one block is both (ruling 2.4),
--- the red from a syntax error's failing character and the
--- parser's message (IS3.4, ruling 1.1), the notice's orange
--- (ruling 2.5), a Markdown heading (IS8.3), and the block
--- cursor at its cell. Also the layout: the status line's band
--- with a field of one row and of eight, in the console and
--- the editor, and the strip under the field in the field's
--- background (the ruling of November 14, late: 4 pixels for
--- the status line, 2 at the bottom).

local PROJECT = 'h-colors'

--- @return table
local function theme() return P.cc().cfg.view.colors end

--- `c` is the theme's `want`, or the scenario fails naming both
--- @param c number[]?
--- @param want number[]
--- @param what string
local function is(c, want, what)
  assert(P.near(c, want), string.format('%s: %s, the theme has %s',
    what, P.show(c), P.show(want)))
end

--- `c` is not `want`
local function is_not(c, want, what)
  assert(not P.near(c, want), what .. ': ' .. P.show(c))
end

--- the status line's band: its first and last pixel rows
--- @param img love.ImageData
--- @param color number[]
--- @return integer top, integer bottom
local function band(img, color)
  local a, b = P.band(img, color)
  assert(a, 'no status line band of ' .. P.show(color))
  return a, b
end

scenario('highlights', function(wait)
  local t = theme()
  wait(.1)
  D.open(wait, PROJECT, 'hl.lua', { ['hl.lua'] = 'a = 1\nb = 2\nc = 3\n' })
  D.press(wait, 'up', 2)
  local img = P.capture(wait)
  D.shot(wait, 'browsed')
  is(P.cell(img, 30, 2), t.editor.highlight, 'the browsed block')
  is_not(P.cell(img, 30, 1), t.editor.highlight, 'the block above it')

  D.key(wait, 'f2')
  img = P.capture(wait)
  D.shot(wait, 'both')
  is(P.cell(img, 30, 2), t.editor.highlight_loaded,
    'the target that is browsed, inside')
  is(P.cell(img, 1, 2), t.editor.highlight,
    'the white strip at its left')
  is(P.cell(img, 64, 2), t.editor.highlight,
    'the white strip at its right')

  D.key(wait, 'C-up')
  img = P.capture(wait)
  D.shot(wait, 'apart')
  is(P.cell(img, 30, 1), t.editor.highlight, 'the browsed block')
  is(P.cell(img, 30, 2), t.editor.highlight_loaded, 'the target')
  is(P.cell(img, 1, 2), t.editor.highlight_loaded,
    'no strip on a target that is not browsed')
  D.leave(wait)
  hm_done()
end)

scenario('messages', function(wait)
  local t = theme()
  wait(.1)
  D.open(wait, PROJECT, 'msg.lua', { ['msg.lua'] = 'a = 1\n' })
  D.type(wait, 'x = = 1')
  D.key(wait, 'return')
  local img = P.capture(wait)
  D.shot(wait, 'syntax')
  local top, bottom = band(img, t.statusline.editor.bg)
  local field = bottom + 1
  local _, fg = P.cell(img, 1, 1, field)
  is_not(fg, t.input.error, 'x, before the failure')
  _, fg = P.cell(img, 7, 1, field)
  is(fg, t.input.error, 'the 1 after the failure')
  -- the parser's message, in the band right above the status
  -- line, on its last row
  local bg
  bg, fg = P.colors(img, 0, top - P.cc().cfg.view.fh,
    P.cc().cfg.view.fw * 6, P.cc().cfg.view.fh)
  is(bg, t.input.error_bg, 'the band')
  is(fg, t.input.error, 'the parser\'s message')

  D.key(wait, 'escape')
  D.key(wait, 'f2')
  img = P.capture(wait)
  D.shot(wait, 'notice')
  top = band(img, t.statusline.editor.bg)
  bg, fg = P.colors(img, 0, top - P.cc().cfg.view.fh,
    P.cc().cfg.view.fw * 6, P.cc().cfg.view.fh)
  is(bg, t.input.error_bg, 'the band')
  is(fg, t.statusline.editor.warning, 'the notice')
  D.leave(wait)
  hm_done()
end)

scenario('markdown-cursor', function(wait)
  local t = theme()
  wait(.1)
  D.open(wait, PROJECT, 'doc.md', { ['doc.md'] = '# Title\nplain\n' })
  local img = P.capture(wait)
  D.shot(wait, 'markdown')
  -- the Markdown syntax colours a heading's marker, its text
  -- stays plain
  local _, fg = P.cell(img, 1, 1)
  is(fg, t.md_syntax.colors.heading, 'the heading\'s #')
  _, fg = P.cell(img, 3, 1)
  is(fg, t.md_syntax.colors.default, 'the heading\'s text')
  _, fg = P.cell(img, 1, 2)
  is(fg, t.md_syntax.colors.default, 'the plain line')
  D.leave(wait)

  D.open(wait, PROJECT, 'cur.lua', { ['cur.lua'] = 'a = 1\n' })
  D.type(wait, 'abc')
  img = P.capture(wait)
  D.shot(wait, 'cursor')
  local _, bottom = band(img, t.statusline.editor.bg)
  local bg = P.cell(img, 4, 1, bottom + 1)
  is(bg, t.input.cursor, 'the cursor after abc')
  bg = P.cell(img, 2, 1, bottom + 1)
  is_not(bg, t.input.cursor, 'b')
  D.leave(wait)
  hm_done()
end)

--- the status band with a field of one row and of eight
--- @param wait function
--- @param where string
--- @param color number[]
--- @param eight function --- makes the field eight rows
local function layout(wait, where, color, eight)
  local img = P.capture(wait)
  D.shot(wait, where .. '-1')
  local a, b = band(img, color)
  print(string.format('LAYOUT %s, a field of 1 row: the status'
    .. ' line takes pixel rows %d to %d', where, a, b))
  local view = P.cc().cfg.view
  local h, fh = view.h, view.fh
  local l = require('view.layout')(view)
  D.eq(b - a + 1, l.status_h, where .. ': the status line\'s height')
  D.eq(b, h - l.bottom - fh - 1,
    where .. ': the status line ends above one row and the strip')
  for y = h - l.bottom, h - 1 do
    for _, x in ipairs({ 1, img:getWidth() - 2 }) do
      local r, g, bl = img:getPixel(x, y)
      is({ r, g, bl }, view.colors.input.console.bg,
        where .. ': the strip at the bottom, pixel row ' .. y)
    end
  end
  eight()
  img = P.capture(wait)
  D.shot(wait, where .. '-8')
  local a8, b8 = band(img, color)
  print(string.format('LAYOUT %s, a field of 8 rows: the status'
    .. ' line takes pixel rows %d to %d', where, a8, b8))
  D.eq(b8, h - l.bottom - 8 * fh - 1,
    where .. ': the status line ends above 8 rows and the strip')
  D.eq(b8 - a8, b - a, where .. ': the band keeps its height')
end

-- The console shows an error as the editor does (the ruling
-- of November 15, 2026): the message in the band right above
-- the status line, the field under it with the draft red from
-- the failure, the status line where it was; the next key
-- takes the band away. The band's ground is the status line's
-- black, so the rows are found from the layout, not the band.
scenario('console-messages', function(wait)
  local t = theme()
  wait(.1)
  if love.state.app_state == 'editor' then D.leave(wait) end
  D.key(wait, 'escape')
  local view = P.cc().cfg.view
  local l = require('view.layout')(view)
  local field = view.h - l.bottom - view.fh
  local status = field - l.status_h
  D.type(wait, 'x = = 1')
  D.key(wait, 'return')
  local img = P.capture(wait)
  D.shot(wait, 'console-syntax')
  local _, fg = P.cell(img, 1, 1, field)
  is_not(fg, t.input.error, 'x, before the failure')
  _, fg = P.cell(img, 7, 1, field)
  is(fg, t.input.error, 'the 1 after the failure')
  local bg
  bg = P.colors(img, 0, status, view.fw * 6, view.fh)
  is(bg, t.statusline.console.bg, 'the status line, where it was')
  bg, fg = P.colors(img, 0, status - view.fh, view.fw * 6, view.fh)
  is(bg, t.input.error_bg, 'the band')
  is(fg, t.input.error, 'the parser\'s message')
  D.key(wait, 'right')
  img = P.capture(wait)
  D.shot(wait, 'console-dismissed')
  bg = P.colors(img, 0, status - view.fh, view.fw * 6, view.fh)
  is_not(bg, t.input.error_bg, 'the band, gone with the key')
  _, fg = P.cell(img, 7, 1, field)
  is(fg, t.input.error, 'the draft, still red from the failure')
  D.key(wait, 'escape')
  hm_done()
end)

scenario('layout', function(wait)
  local t = theme()
  wait(.1)
  D.key(wait, 'escape')
  local function rows(n)
    return function()
      D.type(wait, 'r1')
      for i = 2, n do
        D.key(wait, 'S-return')
        D.type(wait, 'r' .. i)
      end
    end
  end
  layout(wait, 'console', t.statusline.console.bg, rows(8))
  D.key(wait, 'escape')
  D.open(wait, PROJECT, 'layout.lua', { ['layout.lua'] = 'a = 1\n' })
  layout(wait, 'editor', t.statusline.editor.bg, rows(8))
  D.leave(wait)
  hm_done()
end)
