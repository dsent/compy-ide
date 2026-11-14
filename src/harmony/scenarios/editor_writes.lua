local P = require('harmony.probe')
local D = require('harmony.drive')

--- Every key of the file editor that writes the file, with
--- its undo and redo: Enter in the three states (IS4.1, IS4.2,
--- IS4.3, IS5.3), Shift+Ins (IS6.4), cut (IS6.2, IS6.3), move
--- (IS6.5), formatting the file (Ctrl+Shift+F), and the
--- submissions that are refused and leave the file as it was
--- (IS3.3, IS3.4, IS1.7). Each checks the file on storage.
--- Every scenario works on a project of its own.

local PROJECT = 'h-writes'
local ABC = 'a = 1\nb = 2\nc = 3\n'

--- @param name string
--- @return string?
local function stored(name)
  return P.stored(PROJECT, name)
end

--- the file on storage is `want`
--- @param name string
--- @param want string
--- @param what string
local function holds(name, want, what)
  D.eq(stored(name), want, what)
end

--- @param wait function
--- @param name string
--- @param text string
local function open(wait, name, text)
  D.open(wait, PROJECT, name, { [name] = text })
  D.eq(P.position(), 'end', 'a file opens at its end')
  D.eq(P.state(), 'browsing', 'a file opens browsing')
end

-- Enter while inserting: at the end the draft is appended,
-- and on a block it goes in before it, the position staying
-- on that block; Ctrl+Z takes each back, Ctrl+Y makes it again
scenario('enter-insert', function(wait)
  local f = 'insert.lua'
  wait(.1)
  open(wait, f, ABC)
  D.type(wait, 'd = 4')
  D.eq(P.state(), 'inserting', 'typing starts an insertion')
  D.shot(wait, 'draft')
  D.key(wait, 'return')
  D.shot(wait, 'appended')
  holds(f, ABC .. 'd = 4\n', 'Enter at the end appends')
  D.eq(P.position(), 'end', 'the position after an append')
  D.eq(P.draft(), '', 'the field after an append')

  D.key(wait, 'C-z')
  holds(f, ABC, 'Ctrl+Z takes the append back')
  D.key(wait, 'C-y')
  holds(f, ABC .. 'd = 4\n', 'Ctrl+Y appends again')
  D.eq(P.position(), 'end', 'the position after the redo')

  -- end, d, c, b
  D.press(wait, 'up', 3)
  D.eq(P.position(), 2, 'Up browses to b')
  D.type(wait, 'x = 0')
  D.key(wait, 'return')
  D.shot(wait, 'inserted')
  holds(f, 'a = 1\nx = 0\nb = 2\nc = 3\nd = 4\n',
    'Enter on a block inserts before it')
  D.eq(P.position(), 3, 'the position stays on b')
  D.key(wait, 'C-z')
  holds(f, ABC .. 'd = 4\n', 'Ctrl+Z takes the insertion back')
  D.key(wait, 'C-y')
  holds(f, 'a = 1\nx = 0\nb = 2\nc = 3\nd = 4\n',
    'Ctrl+Y inserts again')

  -- two statements on one line become two blocks, and one
  -- undo takes both back
  D.type(wait, 'p = 1 q = 2')
  D.key(wait, 'return')
  holds(f, 'a = 1\nx = 0\np = 1\nq = 2\nb = 2\nc = 3\nd = 4\n',
    'a draft of two statements is two blocks')
  D.key(wait, 'C-z')
  holds(f, 'a = 1\nx = 0\nb = 2\nc = 3\nd = 4\n',
    'one Ctrl+Z takes both blocks back')
  D.leave(wait)
  hm_done()
end)

-- Enter with an empty field while browsing adds an empty line
-- before the browsed block, or at the end (IS4.3)
scenario('enter-browsing', function(wait)
  local f = 'empty.lua'
  wait(.1)
  open(wait, f, ABC)
  D.key(wait, 'return')
  holds(f, ABC .. '\n', 'Enter at the end adds an empty line')
  D.eq(P.position(), 'end', 'the position after the empty line')
  -- end, the empty line, c, b
  D.press(wait, 'up', 3)
  D.eq(P.position(), 2, 'Up browses to b')
  D.key(wait, 'return')
  D.shot(wait, 'empty-line')
  holds(f, 'a = 1\n\nb = 2\nc = 3\n\n',
    'Enter on b adds an empty line before it')
  D.eq(P.position(), 3, 'the position stays on b')
  D.key(wait, 'C-z')
  holds(f, ABC .. '\n', 'Ctrl+Z takes the empty line back')
  D.key(wait, 'C-z')
  holds(f, ABC, 'a second Ctrl+Z takes the first back')
  D.key(wait, 'C-y')
  holds(f, ABC .. '\n', 'Ctrl+Y adds it again')
  D.leave(wait)
  hm_done()
end)

-- Enter while replacing: F2 loads the block, Enter writes the
-- change in its place, and the position goes to the next
-- block; a draft cleared to nothing is an empty line (IS4.3)
scenario('enter-replace', function(wait)
  local f = 'replace.lua'
  wait(.1)
  open(wait, f, ABC)
  -- end, c, b
  D.press(wait, 'up', 2)
  D.key(wait, 'f2')
  D.eq(P.state(), 'replacing', 'F2 opens the block')
  D.eq(P.target(), 2, 'the replacement target')
  D.eq(P.draft(), 'b = 2', 'F2 loads the block')
  D.key(wait, 'backspace')
  D.type(wait, '20')
  D.shot(wait, 'changed')
  holds(f, ABC, 'the file is as it was while replacing')
  D.key(wait, 'return')
  D.shot(wait, 'replaced')
  holds(f, 'a = 1\nb = 20\nc = 3\n', 'Enter replaces the block')
  D.eq(P.state(), 'browsing', 'browsing after a replacement')
  D.eq(P.position(), 3, 'the position goes to the next block')
  D.key(wait, 'C-z')
  holds(f, ABC, 'Ctrl+Z takes the replacement back')
  D.key(wait, 'C-y')
  holds(f, 'a = 1\nb = 20\nc = 3\n', 'Ctrl+Y replaces again')
  D.eq(P.position(), 3, 'the position after the redo')

  -- c is browsed: open it, clear it, and Enter
  D.key(wait, 'f2')
  D.press(wait, 'backspace', 5)
  D.eq(P.draft(), '', 'the draft cleared')
  D.eq(P.state(), 'replacing', 'still replacing')
  D.key(wait, 'return')
  holds(f, 'a = 1\nb = 20\n\n',
    'an empty replacement is an empty line')
  D.eq(P.state(), 'browsing', 'the replacement finished')
  D.key(wait, 'C-z')
  holds(f, 'a = 1\nb = 20\nc = 3\n', 'Ctrl+Z brings c back')
  D.leave(wait)
  hm_done()
end)

-- Shift+Ins submits and keeps the draft (IS6.4): while
-- inserting, while replacing, and with no draft, where it is
-- an empty line
scenario('retain', function(wait)
  local f = 'retain.lua'
  wait(.1)
  open(wait, f, ABC)
  D.type(wait, 'e = 5')
  D.key(wait, 'S-insert')
  D.shot(wait, 'kept')
  holds(f, ABC .. 'e = 5\n', 'Shift+Ins appends')
  D.eq(P.draft(), 'e = 5', 'Shift+Ins keeps the draft')
  D.eq(P.state(), 'inserting', 'inserting after Shift+Ins')
  D.key(wait, 'S-insert')
  holds(f, ABC .. 'e = 5\ne = 5\n', 'a second Shift+Ins appends again')
  D.key(wait, 'C-z')
  holds(f, ABC .. 'e = 5\n', 'Ctrl+Z takes one back')
  D.eq(P.draft(), '', 'the field is empty after the undo')
  D.key(wait, 'C-z')
  holds(f, ABC, 'a second Ctrl+Z takes the other back')
  D.key(wait, 'C-y')
  holds(f, ABC .. 'e = 5\n', 'Ctrl+Y appends again')
  D.eq(P.draft(), 'e = 5', 'Ctrl+Y leaves the field as Shift+Ins did')

  -- end, e, c, b: replace b and keep the draft
  D.key(wait, 'escape')
  D.press(wait, 'up', 3)
  D.eq(P.position(), 2, 'Up browses to b')
  D.key(wait, 'f2')
  D.key(wait, 'backspace')
  D.type(wait, '7')
  D.key(wait, 'S-insert')
  D.shot(wait, 'replaced-kept')
  holds(f, 'a = 1\nb = 7\nc = 3\ne = 5\n', 'Shift+Ins replaces b')
  D.eq(P.draft(), 'b = 7', 'the draft stays')
  D.eq(P.target(), nil, 'the replacement is finished')
  D.eq(P.state(), 'inserting', 'inserting after Shift+Ins')
  D.eq(P.position(), 3, 'the position goes to the next block')
  D.key(wait, 'escape')
  D.eq(P.state(), 'browsing', 'Escape drops the kept draft')
  holds(f, 'a = 1\nb = 7\nc = 3\ne = 5\n', 'Escape writes nothing')

  -- with no draft, Shift+Ins adds an empty line
  D.key(wait, 'S-insert')
  holds(f, 'a = 1\nb = 7\n\nc = 3\ne = 5\n',
    'Shift+Ins with no draft adds an empty line')
  D.leave(wait)
  hm_done()
end)

-- Ctrl+Delete cuts the browsed block into the field (IS6.2);
-- Enter puts it back, Ctrl+Z after an Escape brings back
-- first the draft, then the block (IS6.3, IS6.6); during an
-- edit the cut is refused
scenario('cut', function(wait)
  local f = 'cut.lua'
  local text = 'a = 1\n\nb = 2\nc = 3\n'
  wait(.1)
  open(wait, f, text)
  -- end, c, b
  D.press(wait, 'up', 2)
  D.key(wait, 'C-delete')
  D.shot(wait, 'cut')
  holds(f, 'a = 1\n\nc = 3\n', 'Ctrl+Delete removes b')
  D.eq(P.draft(), 'b = 2', 'the cut block is the draft')
  D.eq(P.state(), 'inserting', 'inserting after a cut')
  D.eq(P.position(), 3, 'the position on the next block')
  D.key(wait, 'return')
  holds(f, text, 'Enter puts the block back')

  D.key(wait, 'up')
  D.key(wait, 'C-delete')
  holds(f, 'a = 1\n\nc = 3\n', 'cut again')
  D.key(wait, 'escape')
  D.eq(P.draft(), '', 'Escape drops the cut block')
  holds(f, 'a = 1\n\nc = 3\n', 'the block stays cut')
  D.key(wait, 'C-z')
  D.eq(P.draft(), 'b = 2', 'Ctrl+Z brings the draft back')
  holds(f, 'a = 1\n\nc = 3\n', 'the file stays cut')
  D.key(wait, 'C-z')
  holds(f, text, 'a second Ctrl+Z restores the block')
  D.eq(P.draft(), '', 'the field is empty once restored')
  -- as an insertion before the block that followed (IS6.3)
  D.eq(P.position(), 4, 'the position after the restored block')
  D.key(wait, 'C-y')
  holds(f, 'a = 1\n\nc = 3\n', 'Ctrl+Y cuts again')
  D.eq(P.draft(), 'b = 2', 'Ctrl+Y leaves the field as the cut did')
  D.key(wait, 'escape')
  D.key(wait, 'C-z')
  D.key(wait, 'C-z')
  holds(f, text, 'restored again')

  -- the empty line above b: cut, and the field stays empty
  D.press(wait, 'up', 2)
  D.eq(P.position(), 2, 'on the empty line')
  D.key(wait, 'C-delete')
  holds(f, 'a = 1\nb = 2\nc = 3\n', 'the empty line is cut')
  D.eq(P.state(), 'browsing', 'an empty line leaves no draft')

  -- a cut during an insertion is refused
  D.type(wait, 'z')
  D.key(wait, 'C-delete')
  D.shot(wait, 'refused')
  D.eq(P.message_kind(), 'notice', 'a cut while inserting is refused')
  D.eq(P.draft(), 'z', 'the draft stays')
  holds(f, 'a = 1\nb = 2\nc = 3\n', 'the refused cut writes nothing')
  D.leave(wait)
  hm_done()
end)

-- Alt+Up and Alt+Down move the browsed block (IS6.5), and an
-- undo takes a move back; at an edge the key does nothing, at
-- the end and while replacing it is refused
scenario('move', function(wait)
  local f = 'move.lua'
  wait(.1)
  open(wait, f, ABC)
  D.press(wait, 'up', 3)
  D.eq(P.position(), 1, 'on a')
  D.key(wait, 'A-down')
  D.shot(wait, 'moved-down')
  holds(f, 'b = 2\na = 1\nc = 3\n', 'Alt+Down moves a down')
  D.eq(P.position(), 2, 'the position follows the block')
  D.key(wait, 'A-down')
  holds(f, 'b = 2\nc = 3\na = 1\n', 'and again')
  D.key(wait, 'A-down')
  holds(f, 'b = 2\nc = 3\na = 1\n', 'the last block moves no further')
  D.key(wait, 'C-z')
  holds(f, 'b = 2\na = 1\nc = 3\n', 'Ctrl+Z takes one move back')
  D.key(wait, 'C-z')
  holds(f, ABC, 'and the other')
  D.key(wait, 'C-y')
  holds(f, 'b = 2\na = 1\nc = 3\n', 'Ctrl+Y moves again')
  D.key(wait, 'A-up')
  holds(f, ABC, 'Alt+Up moves it back up')
  D.key(wait, 'A-up')
  holds(f, ABC, 'the first block moves no further')

  -- with a draft the block still moves, the draft stays
  D.type(wait, 'w = 0')
  D.key(wait, 'A-down')
  holds(f, 'b = 2\na = 1\nc = 3\n', 'Alt+Down while inserting')
  D.eq(P.draft(), 'w = 0', 'the draft stays through a move')
  D.key(wait, 'escape')

  D.key(wait, 'f2')
  D.key(wait, 'A-up')
  D.eq(P.message_kind(), 'notice', 'a move while replacing is refused')
  holds(f, 'b = 2\na = 1\nc = 3\n', 'the refused move writes nothing')
  D.key(wait, 'escape')
  D.press(wait, 'down', 2)
  D.eq(P.position(), 'end', 'at the end')
  D.key(wait, 'A-up')
  D.shot(wait, 'refused-end')
  D.eq(P.message_kind(), 'notice', 'a move at the end is refused')
  holds(f, 'b = 2\na = 1\nc = 3\n', 'nothing moved')
  D.leave(wait)
  hm_done()
end)

-- Ctrl+Shift+F tidies the whole file while browsing, and one
-- Ctrl+Z takes it back
scenario('format', function(wait)
  local f = 'format.lua'
  local untidy = 'x=1\nif x then y=2 end\n'
  wait(.1)
  open(wait, f, untidy)
  D.shot(wait, 'untidy')
  D.key(wait, 'C-S-f')
  D.shot(wait, 'tidy')
  local tidy = stored(f)
  assert(tidy ~= untidy, 'Ctrl+Shift+F changed nothing')
  assert(string.find(tidy, 'x = 1\n', 1, true),
    'Ctrl+Shift+F did not tidy x=1: ' .. tostring(tidy))
  D.key(wait, 'C-z')
  holds(f, untidy, 'Ctrl+Z takes the tidying back')
  D.key(wait, 'C-y')
  holds(f, tidy, 'Ctrl+Y tidies again')
  -- while inserting it is not a command
  D.key(wait, 'C-z')
  D.type(wait, 'z')
  D.key(wait, 'C-S-f')
  holds(f, untidy, 'Ctrl+Shift+F while inserting writes nothing')
  D.leave(wait)
  hm_done()
end)

-- Submissions that are refused leave the file as it was: a
-- syntax error, a line over 64 characters, a block over 14
-- lines, and a file changed on storage since the editor read
-- it (IS1.7, the guard of the SD card ruling)
scenario('refused', function(wait)
  local f = 'refuse.lua'
  wait(.1)
  open(wait, f, ABC)
  D.type(wait, 'x = = 1')
  D.key(wait, 'return')
  D.shot(wait, 'syntax')
  holds(f, ABC, 'a syntax error writes nothing')
  D.eq(P.message_kind(), 'error', 'the parser\'s message shows')
  D.eq(P.draft(), 'x = = 1', 'the draft stays')
  D.key(wait, 'escape')

  -- a name the formatter cannot break: a long string it
  -- would split
  local long = 'v' .. string.rep('l', 70) .. ' = 1'
  D.type(wait, long)
  D.shot(wait, 'long-draft')
  D.key(wait, 'return')
  D.shot(wait, 'long')
  holds(f, ABC, 'a line over 64 characters writes nothing')
  D.eq(P.message_kind(), 'notice', 'the limit is named')
  assert(string.find(P.message(), '64', 1, true),
    'the notice does not name 64: ' .. tostring(P.message()))
  -- formatted as far as it goes (IS3.2)
  D.eq(P.draft(), 'v' .. string.rep('l', 70) .. '\n    = 1',
    'the long draft stays')
  D.key(wait, 'escape')

  -- fifteen statements in one function, typed on one line
  local body = {}
  for i = 1, 13 do body[i] = 'v' .. i .. ' = ' .. i end
  local fn = 'function f() ' .. table.concat(body, ' ') .. ' end'
  D.type(wait, fn)
  D.key(wait, 'return')
  D.shot(wait, 'tall')
  holds(f, ABC, 'a block over 14 lines writes nothing')
  D.eq(P.message_kind(), 'notice', 'the block limit is named')
  assert(string.find(P.message(), '14', 1, true),
    'the notice does not name 14: ' .. tostring(P.message()))
  D.key(wait, 'escape')

  -- the file changes on storage behind the editor's back
  D.type(wait, 'd = 4')
  P.put(PROJECT, f, 'outside = true\n')
  D.key(wait, 'return')
  D.shot(wait, 'stale')
  holds(f, 'outside = true\n', 'a stale file is not written over')
  D.eq(P.draft(), 'd = 4', 'the draft stays for a stale file')
  D.eq(P.message_kind(), 'notice', 'the refusal is said')
  D.leave(wait)
  hm_done()
end)
