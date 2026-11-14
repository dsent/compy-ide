local P = require('harmony.probe')
local D = require('harmony.drive')

--- The maintainer's rulings of November 14 that a file meets:
--- the formatter decides a Lua draft's empty lines, while a
--- text file keeps them; a refused formatting says why.

local PROJECT = 'h-rulings'

scenario('empty-lines', function(wait)
  wait(.1)
  D.open(wait, PROJECT, 'gaps.lua', { ['gaps.lua'] = 'a = 1\n' })
  D.type(wait, 'p = 1')
  D.press(wait, 'S-return', 3)
  D.type(wait, 'q = 2')
  D.key(wait, 'return')
  D.eq(P.stored(PROJECT, 'gaps.lua'), 'a = 1\np = 1\n\nq = 2\n',
    'a run of empty lines lands as one in Lua')
  D.leave(wait)
  D.open(wait, PROJECT, 'gaps.txt', { ['gaps.txt'] = 'a\n' })
  D.type(wait, 'p')
  D.press(wait, 'S-return', 3)
  D.type(wait, 'q')
  D.key(wait, 'return')
  D.eq(P.stored(PROJECT, 'gaps.txt'), 'a\np\n\n\nq\n',
    'a text file keeps every empty line')
  D.leave(wait)
  hm_done()
end)

scenario('format-refused', function(wait)
  local f = 'tidy.lua'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = 'x=1\n' })
  D.type(wait, 'z = 0')
  D.key(wait, 'C-S-f')
  D.shot(wait, 'during-edit')
  D.eq(P.message_kind(), 'notice', 'formatting during an edit says why')
  D.eq(P.draft(), 'z = 0', 'the draft stays')
  D.eq(P.stored(PROJECT, f), 'x=1\n', 'nothing was written')
  D.key(wait, 'escape')
  D.leave(wait)
  D.open(wait, PROJECT, 'notes.txt', { ['notes.txt'] = 'x=1\n' })
  D.key(wait, 'C-S-f')
  D.shot(wait, 'text-file')
  D.eq(P.message_kind(), 'notice', 'formatting a text file says why')
  D.eq(P.stored(PROJECT, 'notes.txt'), 'x=1\n', 'nothing was written')
  D.leave(wait)
  hm_done()
end)
