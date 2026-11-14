local P = require('harmony.probe')
local D = require('harmony.drive')

--- Opening files and following references (IS1.2, IS1.5),
--- an empty file (IS2.1), and the document view over a block
--- taller than the view and over many blocks (IS2.2, the
--- ruling on PgUp and PgDn).

local PROJECT = 'h-open'

--- @param name string
--- @return string?
local function stored(name)
  return P.stored(PROJECT, name)
end

-- A file that is not UTF-8 is refused at the console, which
-- names it; a file whose last line has no line end opens,
-- and gets one with the first submission
scenario('admit', function(wait)
  wait(.1)
  D.enter(wait, string.format('project(%q)', PROJECT))
  P.put(PROJECT, 'latin.lua', 'x = "\233t\233"\n')
  D.enter(wait, 'edit("latin.lua")')
  D.in_state('ready')
  D.shot(wait, 'refused')
  assert(string.find(P.console_text(), 'latin.lua is not UTF-8', 1,
    true), 'the refusal does not name the file')
  D.eq(stored('latin.lua'), 'x = "\233t\233"\n', 'nothing was written')

  local f = 'open-end.lua'
  D.open(wait, PROJECT, f, { [f] = 'a = 1\nb = 2' })
  D.eq(P.blocks(), 2, 'the last line is a block')
  D.eq(stored(f), 'a = 1\nb = 2', 'opening writes nothing')
  D.enter(wait, 'c = 3')
  D.eq(stored(f), 'a = 1\nb = 2\nc = 3\n',
    'the first submission ends every line')
  D.leave(wait)
  hm_done()
end)

-- Ctrl+J on a require of a file the project lacks, or of one
-- that cannot be opened, is refused with a notice and the
-- file stays as it was (IS1.5, IS3.11)
scenario('follow-refused', function(wait)
  local f = 'caller.lua'
  local text = 'm = require("nowhere")\nl = require("latin")\n'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = text })
  D.press(wait, 'up', 2)
  D.key(wait, 'C-j')
  D.shot(wait, 'missing')
  D.eq(P.file(), f, 'a missing file opens nothing')
  D.eq(P.message_kind(), 'notice', 'the refusal is said')
  D.eq(P.position(), 1, 'the position stays')
  D.key(wait, 'down')
  D.key(wait, 'C-j')
  D.shot(wait, 'not-utf8')
  D.eq(P.file(), f, 'a file that is not UTF-8 opens nothing')
  D.eq(P.message_kind(), 'notice', 'that refusal is said')
  D.eq(stored(f), text, 'nothing was written')
  D.leave(wait)
  hm_done()
end)

-- An empty file has one position, its end: browsing keeps it,
-- and F2 there is refused
scenario('empty', function(wait)
  local f = 'void.lua'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = '' })
  D.eq(P.blocks(), 0, 'no block')
  for _, k in ipairs({ 'up', 'down', 'C-up', 'C-down', 'pageup',
    'pagedown' }) do
    D.key(wait, k)
    D.eq(P.position(), 'end', k .. ' in an empty file')
  end
  D.key(wait, 'f2')
  D.eq(P.message_kind(), 'notice', 'F2 in an empty file is refused')
  D.shot(wait, 'empty')
  D.eq(stored(f), '', 'nothing was written')
  D.leave(wait)
  hm_done()
end)

-- A block taller than the view: arriving from below shows its
-- last rows, and Up scrolls a row at a time until its first
-- row shows, then browses on; from above, Down does the same
-- the other way (IS2.2)
scenario('tall', function(wait)
  local f = 'tall.lua'
  local fn = { 'function tall()' }
  for i = 1, 22 do fn[#fn + 1] = '  t' .. i .. ' = ' .. i end
  fn[#fn + 1] = 'end'
  local text = 'a = 1\n' .. table.concat(fn, '\n') .. '\nz = 1\n'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = text })
  D.press(wait, 'up', 2)
  D.eq(P.position(), 2, 'on the tall block')
  local rows, shown = P.rows_shown(2)
  D.eq(rows, 24, 'the block has 24 rows')
  assert(shown < rows, 'the tall block fits the view')
  D.shot(wait, 'from-below')
  local hidden = rows - shown
  local top = P.offset()
  for i = 1, hidden do
    D.key(wait, 'up')
    D.eq(P.position(), 2, 'Up ' .. i .. ' scrolls, it does not browse')
    D.eq(P.offset(), top - i, 'Up ' .. i .. ' scrolls one row')
  end
  D.shot(wait, 'scrolled-up')
  D.eq(select(2, P.rows_shown(2)), shown, 'the view keeps its height')
  D.key(wait, 'up')
  D.eq(P.position(), 1, 'once the first row shows, Up browses')
  D.key(wait, 'down')
  D.eq(P.position(), 2, 'Down browses onto the tall block')
  top = P.offset()
  for i = 1, hidden do
    D.key(wait, 'down')
    D.eq(P.position(), 2, 'Down ' .. i .. ' scrolls, it does not browse')
    D.eq(P.offset(), top + i, 'Down ' .. i .. ' scrolls one row')
  end
  D.shot(wait, 'scrolled-down')
  D.key(wait, 'down')
  D.eq(P.position(), 3, 'once the last row shows, Down browses')
  D.eq(stored(f), text, 'nothing was written')
  D.leave(wait)
  hm_done()
end)

-- PgUp brings the block hidden just above the view to its
-- bottom and browses to it; PgDn brings the one hidden just
-- below to its top; at the file's start or end they go there
scenario('page', function(wait)
  local f = 'many.lua'
  local lines = {}
  for i = 1, 45 do lines[i] = 'v' .. i .. ' = ' .. i end
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = table.concat(lines, '\n') .. '\n' })
  local first = P.blocks_in_view()
  D.key(wait, 'pageup')
  D.shot(wait, 'up-1')
  D.eq(P.position(), first - 1, 'PgUp browses to the block above the view')
  local _, last = P.blocks_in_view()
  D.eq(last, first - 1, 'and shows it at the bottom')
  first = P.blocks_in_view()
  D.key(wait, 'pageup')
  D.eq(P.position(), first - 1, 'a second PgUp pages on')
  D.press(wait, 'pageup', 3)
  D.eq(P.position(), 1, 'at the start PgUp goes to the first block')
  D.shot(wait, 'start')
  _, last = P.blocks_in_view()
  D.key(wait, 'pagedown')
  D.shot(wait, 'down-1')
  D.eq(P.position(), last + 1, 'PgDn browses to the block below the view')
  first = P.blocks_in_view()
  D.eq(first, last + 1, 'and shows it at the top')
  D.press(wait, 'pagedown', 4)
  D.eq(P.position(), 'end', 'at the end PgDn goes to the end')
  D.leave(wait)
  hm_done()
end)
