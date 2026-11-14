local P = require('harmony.probe')
local D = require('harmony.drive')

--- Plain text and Markdown files (IS8): every line a block,
--- no syntax check, no formatting and no length limit; and a
--- file that is not there, created by its first submission
--- (IS1.2).

local PROJECT = 'h-text'

--- @param name string
--- @return string?
local function stored(name)
  return P.stored(PROJECT, name)
end

scenario('text', function(wait)
  local f = 'notes.txt'
  local long = string.rep('word ', 20) .. 'end'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = 'one\ntwo\n' })
  D.eq(P.blocks(), 2, 'a line to a block')
  D.enter(wait, 'three')
  D.eq(stored(f), 'one\ntwo\nthree\n', 'Enter appends a line')
  -- not Lua, kept as typed
  D.enter(wait, 'x=1  (y')
  D.eq(stored(f), 'one\ntwo\nthree\nx=1  (y\n',
    'text is taken as typed')
  D.type(wait, 'four')
  D.key(wait, 'S-return')
  D.type(wait, 'five')
  D.key(wait, 'return')
  D.eq(stored(f), 'one\ntwo\nthree\nx=1  (y\nfour\nfive\n',
    'a line break makes two lines')
  D.eq(P.blocks(), 6, 'and two blocks')
  D.enter(wait, long)
  D.shot(wait, 'long')
  D.eq(stored(f), 'one\ntwo\nthree\nx=1  (y\nfour\nfive\n'
    .. long .. '\n', 'a line over 64 characters is taken')
  D.key(wait, 'return')
  D.eq(P.blocks(), 8, 'Enter alone adds an empty line')

  -- end, empty, long, five, four, x=1, three, two
  D.press(wait, 'up', 7)
  D.eq(P.position(), 2, 'on two')
  D.key(wait, 'f2')
  D.eq(P.draft(), 'two', 'F2 loads the line')
  D.press(wait, 'backspace', 3)
  D.enter(wait, 'TWO')
  D.key(wait, 'up')
  D.key(wait, 'C-delete')
  D.eq(P.draft(), 'TWO', 'Ctrl+Delete cuts the line')
  D.key(wait, 'escape')
  D.key(wait, 'C-z')
  D.key(wait, 'C-z')
  -- the position is after the restored line (IS6.3)
  D.key(wait, 'up')
  D.key(wait, 'A-up')
  D.shot(wait, 'moved')
  D.eq(stored(f), 'TWO\none\nthree\nx=1  (y\nfour\nfive\n'
    .. long .. '\n\n', 'replaced, cut, restored and moved')
  -- a text file has no tidy form: Ctrl+Shift+F says so in a
  -- notice and writes nothing
  local before = stored(f)
  D.key(wait, 'C-S-f')
  D.eq(stored(f), before, 'Ctrl+Shift+F writes nothing')
  assert(P.message(), 'Ctrl+Shift+F says nothing')
  D.leave(wait)
  hm_done()
end)

scenario('markdown', function(wait)
  local f = 'doc.md'
  local text = '# Title\n\nSome *text* and `code`.\n'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = text })
  D.eq(P.blocks(), 3, 'a line to a block')
  D.type(wait, '- an **item**')
  D.shot(wait, 'draft')
  D.key(wait, 'return')
  D.eq(stored(f), text .. '- an **item**\n', 'Enter appends')
  D.press(wait, 'up', 4)
  D.key(wait, 'f2')
  D.shot(wait, 'loaded')
  D.eq(P.draft(), '# Title', 'F2 loads the heading')
  D.leave(wait)
  hm_done()
end)

-- A file that is not there opens empty and is created by its
-- first submission; a name with another ending is plain text
scenario('new-file', function(wait)
  local f = 'data.csv'
  wait(.1)
  D.open(wait, PROJECT, f)
  D.eq(P.blocks(), 0, 'a new file is empty')
  D.eq(stored(f), nil, 'opening writes nothing')
  D.enter(wait, 'a,b')
  D.eq(stored(f), 'a,b\n', 'the first submission creates it')
  D.leave(wait)
  hm_done()
end)
