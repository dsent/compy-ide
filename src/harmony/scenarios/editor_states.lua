local P = require('harmony.probe')
local D = require('harmony.drive')

--- The file editor's three states and the keys that move
--- between them: F2 on an ordinary block, on one over the
--- limits, and on a line of a file that does not parse (IS5,
--- the F2 ruling); Escape in each state (IS5.7, IS1.6);
--- browsing with a draft (IS2.1, IS2.3, IS3.8); a draft
--- continued by Enter (IS3.5); a syntax error (IS3.4); and a
--- message the next key dismisses and still acts (the
--- ruling on messages, IS3.14).

local PROJECT = 'h-states'

--- @param name string
--- @return string?
local function stored(name)
  return P.stored(PROJECT, name)
end

-- F2 opens the browsed block for replacement with the cursor
-- at its end (IS5.1); F2 again on it reloads it (IS5.5); on
-- another block it switches while the draft is unchanged
-- (IS5.6) and is refused once it is changed; browsing leaves
-- the target where it is (IS2.3)
scenario('f2', function(wait)
  local f = 'f2.lua'
  local text = 'a = 1\nb = 2\n\nc = 3\n'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = text })
  D.key(wait, 'f2')
  D.eq(P.state(), 'browsing', 'F2 at the end opens nothing')
  D.eq(P.message_kind(), 'notice', 'F2 at the end is refused')
  -- the next key dismisses the notice and still browses
  D.key(wait, 'up')
  D.eq(P.message(), nil, 'Up dismisses the notice')
  D.eq(P.position(), 4, 'and browses')
  D.key(wait, 'up')
  D.key(wait, 'f2')
  D.eq(P.state(), 'browsing', 'F2 on an empty line opens nothing')
  D.eq(P.message_kind(), 'notice', 'F2 on an empty line is refused')
  D.shot(wait, 'empty-refused')

  D.key(wait, 'up')
  D.eq(P.position(), 2, 'on b')
  D.key(wait, 'f2')
  D.shot(wait, 'loaded')
  D.eq(P.state(), 'replacing', 'F2 opens b')
  D.eq(P.target(), 2, 'b is the target')
  D.eq(P.draft(), 'b = 2', 'the draft is b')
  local _, col = P.cursor()
  D.eq(col, 6, 'the cursor at the end of b')

  D.type(wait, '0')
  D.key(wait, 'f2')
  D.eq(P.draft(), 'b = 2', 'F2 on the target reloads it')
  D.key(wait, 'C-z')
  D.eq(P.draft(), 'b = 20', 'Ctrl+Z takes the reload back')

  -- browsing with a changed draft moves the white position
  -- alone, and F2 there is refused
  D.key(wait, 'C-up')
  D.eq(P.position(), 1, 'Ctrl+Up browses while replacing')
  D.eq(P.target(), 2, 'the target stays')
  D.eq(P.draft(), 'b = 20', 'the draft stays')
  D.shot(wait, 'browse-away')
  D.key(wait, 'f2')
  D.shot(wait, 'switch-refused')
  D.eq(P.message_kind(), 'notice', 'F2 elsewhere on a changed draft')
  D.eq(P.target(), 2, 'the refusal keeps the target')
  -- one Escape dismisses the notice and drops the edit
  D.key(wait, 'escape')
  D.eq(P.message(), nil, 'Escape dismisses the notice')
  D.eq(P.state(), 'browsing', 'and drops the edit')
  D.eq(P.position(), 1, 'the position stays')
  D.eq(stored(f), text, 'nothing was written')

  -- an unchanged draft switches to the browsed block, and
  -- Ctrl+Z switches back
  D.key(wait, 'f2')
  D.eq(P.target(), 1, 'a is the target')
  D.key(wait, 'C-down')
  D.key(wait, 'f2')
  D.shot(wait, 'switched')
  D.eq(P.target(), 2, 'F2 switches the target to b')
  D.eq(P.draft(), 'b = 2', 'with b as the draft')
  D.key(wait, 'C-z')
  D.eq(P.target(), 1, 'Ctrl+Z returns the target to a')
  D.eq(P.draft(), 'a = 1', 'and its text')
  D.eq(P.position(), 2, 'the position stays where it is')
  D.key(wait, 'escape')
  D.eq(P.target(), nil, 'Escape drops the edit')
  D.eq(stored(f), text, 'nothing was written')
  D.leave(wait)
  hm_done()
end)

-- F2 opens a block whatever it holds (the F2 ruling): one of
-- fifteen lines and a line of 71 characters written outside
-- the editor, both shown wrapped or cut by the view; Enter
-- then refuses them with the limit, and the file stays
scenario('f2-limits', function(wait)
  local f = 'limits.lua'
  local fn = { 'function tall()' }
  for i = 1, 13 do fn[#fn + 1] = '  t' .. i .. ' = ' .. i end
  fn[#fn + 1] = 'end'
  local name = 'w' .. string.rep('m', 70)
  local text = table.concat(fn, '\n') .. '\n'
      .. name .. ' = 1\n' .. 'z = 0\n'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = text })
  D.shot(wait, 'open')
  -- end, z, the long line
  D.press(wait, 'up', 2)
  D.shot(wait, 'long-browsed')
  D.key(wait, 'f2')
  D.eq(P.state(), 'replacing', 'F2 opens the long line')
  D.key(wait, 'return')
  D.shot(wait, 'long-refused')
  D.eq(P.message_kind(), 'notice', 'Enter refuses the long line')
  D.eq(P.state(), 'replacing', 'the replacement stays')
  D.eq(stored(f), text, 'nothing was written')
  D.key(wait, 'escape')

  D.key(wait, 'up')
  D.eq(P.position(), 1, 'on the tall block')
  D.shot(wait, 'tall-browsed')
  D.key(wait, 'f2')
  D.shot(wait, 'tall-loaded')
  D.eq(P.state(), 'replacing', 'F2 opens the tall block')
  D.eq(P.draft(), table.concat(fn, '\n'), 'the draft is the block')
  D.key(wait, 'return')
  D.shot(wait, 'tall-refused')
  D.eq(P.message_kind(), 'notice', 'Enter refuses the tall block')
  assert(string.find(P.message(), '14', 1, true),
    'the notice does not name 14: ' .. tostring(P.message()))
  D.eq(stored(f), text, 'nothing was written')
  -- cut down to fourteen lines, it is taken
  D.key(wait, 'C-home')
  D.key(wait, 'down')
  D.key(wait, 'C-k')
  D.key(wait, 'delete')
  D.key(wait, 'return')
  table.remove(fn, 2)
  D.eq(stored(f), table.concat(fn, '\n') .. '\n' .. name
    .. ' = 1\nz = 0\n', 'the block of 15 lines is refused, of 14 taken')
  D.leave(wait)
  hm_done()
end)

-- A file that does not parse opens a line to a block; F2
-- opens any line, and a corrected line is taken
scenario('f2-unparsed', function(wait)
  local f = 'broken.lua'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = 'x = = 1\ny = 2\n' })
  D.eq(P.blocks(), 2, 'a line to a block')
  D.shot(wait, 'open')
  D.press(wait, 'up', 2)
  D.key(wait, 'f2')
  D.eq(P.draft(), 'x = = 1', 'F2 opens the broken line')
  D.shot(wait, 'loaded')
  D.key(wait, 'return')
  D.eq(P.message_kind(), 'error', 'the broken line is refused')
  D.shot(wait, 'error')
  D.eq(stored(f), 'x = = 1\ny = 2\n', 'nothing was written')
  -- the cursor stands before the second `=`: Delete twice
  D.press(wait, 'delete', 2)
  D.eq(P.message(), nil, 'Delete dismisses the error')
  D.eq(P.draft(), 'x = 1', 'and deletes')
  D.key(wait, 'return')
  D.shot(wait, 'fixed')
  D.eq(stored(f), 'x = 1\ny = 2\n', 'the corrected line is taken')
  D.leave(wait)
  hm_done()
end)

-- Escape drops an insertion and a replacement, and the next
-- steps back from the file (IS5.7, IS1.6); Ctrl+Z after the
-- abort brings the edit back (IS6.6)
scenario('escape', function(wait)
  local f = 'escape.lua'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = 'a = 1\nb = 2\n' })
  D.type(wait, 'n = 0')
  D.key(wait, 'escape')
  D.eq(P.state(), 'browsing', 'Escape drops an insertion')
  D.eq(P.draft(), '', 'the field is empty')
  D.key(wait, 'C-z')
  D.eq(P.draft(), 'n = 0', 'Ctrl+Z brings the insertion back')
  D.key(wait, 'escape')

  D.key(wait, 'up')
  D.key(wait, 'f2')
  D.type(wait, '9')
  D.key(wait, 'escape')
  D.eq(P.state(), 'browsing', 'Escape drops a replacement')
  D.eq(P.target(), nil, 'and its target')
  D.eq(P.position(), 2, 'the position stays')
  D.key(wait, 'C-z')
  D.eq(P.target(), 2, 'Ctrl+Z brings the replacement back')
  D.eq(P.draft(), 'b = 29', 'with its draft')
  D.key(wait, 'escape')
  D.eq(stored(f), 'a = 1\nb = 2\n', 'nothing was written')

  D.key(wait, 'escape')
  D.in_state('ready')
  D.eq(P.console_draft(), '', 'the console field is empty')
  D.shot(wait, 'console')
  hm_done()
end)

-- With a draft, Up and Down move the cursor between its rows,
-- and Ctrl+Up and Ctrl+Down browse, the draft and the cursor
-- staying (IS2.1, IS3.8); Shift+Enter and Alt+Enter break a
-- line (IS3.15)
scenario('browse-draft', function(wait)
  local f = 'browse.lua'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = 'a = 1\nb = 2\nc = 3\n' })
  D.type(wait, 'p = 1')
  D.key(wait, 'S-return')
  D.type(wait, 'q = 2')
  D.key(wait, 'A-return')
  D.type(wait, 'r = 3')
  D.eq(P.draft(), 'p = 1\nq = 2\nr = 3', 'two line breaks')
  D.eq(stored(f), 'a = 1\nb = 2\nc = 3\n', 'a break writes nothing')
  D.key(wait, 'up')
  local l = P.cursor()
  D.eq(l, 2, 'Up moves the cursor a row up')
  D.eq(P.position(), 'end', 'Up with a draft does not browse')
  D.key(wait, 'C-up')
  D.key(wait, 'C-up')
  D.shot(wait, 'browsed')
  D.eq(P.position(), 2, 'Ctrl+Up browses with a draft')
  D.eq(P.draft(), 'p = 1\nq = 2\nr = 3', 'the draft stays')
  l = P.cursor()
  D.eq(l, 2, 'the cursor stays')
  D.key(wait, 'C-down')
  D.eq(P.position(), 3, 'Ctrl+Down browses back')
  D.key(wait, 'return')
  D.eq(stored(f), 'a = 1\nb = 2\np = 1\nq = 2\nr = 3\nc = 3\n',
    'the draft goes in before the browsed block')
  D.leave(wait)
  hm_done()
end)

-- An unfinished draft takes a line break on Enter (IS3.5)
-- with no red and no message, and is taken once finished;
-- a draft that fails before its end shows the failure in red
-- with the parser's message (IS3.4)
scenario('continue', function(wait)
  local f = 'continue.lua'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = 'a = 1\n' })
  D.type(wait, 'if a then')
  D.key(wait, 'return')
  D.eq(P.draft(), 'if a then\n', 'Enter adds a line break')
  D.eq(P.message(), nil, 'with no message')
  D.type(wait, 'b = 1')
  D.key(wait, 'return')
  D.shot(wait, 'unfinished')
  D.eq(P.draft(), 'if a then\nb = 1\n', 'and another')
  D.eq(stored(f), 'a = 1\n', 'an unfinished draft is not written')
  D.type(wait, 'end')
  D.key(wait, 'return')
  D.shot(wait, 'finished')
  D.eq(stored(f), 'a = 1\nif a then\n  b = 1\nend\n',
    'the finished draft is written formatted')

  -- the failure is the second `=`, before the end
  D.type(wait, 'y = = 2')
  D.key(wait, 'return')
  D.shot(wait, 'error')
  D.eq(P.message_kind(), 'error', 'the parser\'s message shows')
  local _, col = P.cursor()
  D.eq(col, 5, 'the cursor goes to the failure')
  -- the next key dismisses it and still acts
  D.key(wait, 'right')
  D.eq(P.message(), nil, 'Right dismisses the message')
  _, col = P.cursor()
  D.eq(col, 6, 'and moves the cursor')
  D.leave(wait)
  hm_done()
end)

-- The cursor keys in a draft (IS3.8), Ctrl+K and the deletion
-- keys at the draft's edges (IS3.12), Ctrl+Ins, which copies
-- the browsed block into the draft on lines of its own
-- (IS6.1), and Ctrl+J during the edit; none writes the file
scenario('cursor', function(wait)
  local f = 'cursor.lua'
  local text = 'a = 1\nb = 2\n'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = text })
  D.type(wait, 'alpha = beta_2 + 3')
  D.key(wait, 'C-left')
  local _, col = P.cursor()
  D.eq(col, 18, 'Ctrl+Left to the start of the word 3')
  D.key(wait, 'C-left')
  _, col = P.cursor()
  D.eq(col, 9, 'Ctrl+Left again, to beta_2')
  D.key(wait, 'C-right')
  _, col = P.cursor()
  D.eq(col, 15, 'Ctrl+Right to the end of beta_2')
  D.key(wait, 'home')
  _, col = P.cursor()
  D.eq(col, 1, 'Home to the row start')
  D.key(wait, 'backspace')
  D.eq(P.draft(), 'alpha = beta_2 + 3', 'Backspace at the start')
  D.key(wait, 'end')
  D.key(wait, 'delete')
  D.eq(P.draft(), 'alpha = beta_2 + 3', 'Delete at the end')
  D.press(wait, 'left', 4)
  D.key(wait, 'C-k')
  D.eq(P.draft(), 'alpha = beta_2', 'Ctrl+K deletes to the end')
  D.key(wait, 'C-home')
  D.key(wait, 'right')
  -- at the end there is no block to copy
  D.key(wait, 'C-insert')
  D.eq(P.message_kind(), 'notice', 'Ctrl+Ins at the end is refused')
  D.key(wait, 'C-up')
  D.eq(P.position(), 2, 'Ctrl+Up browses to b')
  D.key(wait, 'C-insert')
  D.shot(wait, 'copied')
  D.eq(P.draft(), 'a\nb = 2\nlpha = beta_2',
    'Ctrl+Ins copies b on lines of its own')
  local l
  l, col = P.cursor()
  D.eq(l .. ':' .. col, '2:6', 'the cursor after the copy')
  -- Ctrl+J is refused during an edit (IS1.5)
  D.key(wait, 'C-j')
  D.eq(P.message_kind(), 'notice', 'Ctrl+J during an insertion')
  D.eq(P.file(), f, 'the file stays')
  D.eq(P.stored(PROJECT, f), text, 'nothing was written')
  D.leave(wait)
  hm_done()
end)

-- Formatting keeps the cursor at the same place in the text
-- (IS3.9): in a draft kept with Shift+Ins, and in a draft a
-- line over the limit sends back formatted
scenario('cursor-format', function(wait)
  local f = 'format-cursor.lua'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = 'a = 1\n' })
  D.type(wait, 'x=1+2')
  D.key(wait, 'left')
  local _, col = P.cursor()
  D.eq(col, 5, 'the cursor between + and 2')
  D.key(wait, 'S-insert')
  D.eq(P.draft(), 'x = 1 + 2', 'the kept draft is formatted')
  -- a boundary two elements share keeps to the end of the
  -- first: after +
  _, col = P.cursor()
  D.eq(col, 8, 'the cursor is still after +')
  D.key(wait, 'escape')

  local name = 'v' .. string.rep('n', 70)
  D.type(wait, name .. ' =1')
  D.key(wait, 'left')
  D.key(wait, 'return')
  D.eq(P.draft(), name .. '\n    = 1', 'the refused draft is formatted')
  local l
  l, col = P.cursor()
  D.eq(l .. ':' .. col, '2:6', 'the cursor is still after =')
  D.shot(wait, 'refused')
  D.leave(wait)
  hm_done()
end)
