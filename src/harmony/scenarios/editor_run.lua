local P = require('harmony.probe')
local D = require('harmony.drive')

--- Running the project from the file editor and coming back:
--- Ctrl+T and Ctrl+Q refused during an edit (the ruling on
--- Ctrl+T, the proposed shortcut map), Ctrl+T there and back
--- with the position and the undo timeline kept (IS1.4),
--- Ctrl+Q from the editor, from a program and from the
--- console, and a program that opens a file with edit().

local PROJECT = 'h-run'
--- a program that runs until it is stopped
local RUNS = 'n = 0\nfunction love.update() n = n + 1 end\n'
--- a program that idles behind the console, and opens a file
--- on F3
local OPENS_ON_F3 = [[
compy.input.hooks.keypressed = function(k)
  if k == 'f3' then edit('notes.txt') end
  return true
end
]]

--- @return string
local function project()
  return P.cc().model.projects.current.name
end

-- During an insertion and a replacement, Ctrl+T and Ctrl+Q
-- are refused with a notice, and the draft stays
scenario('refused', function(wait)
  wait(.1)
  D.open(wait, PROJECT, 'main.lua', { ['main.lua'] = RUNS })
  D.type(wait, 'x = 1')
  D.key(wait, 'C-t')
  D.shot(wait, 'run-refused')
  D.in_state('editor')
  D.eq(P.message_kind(), 'notice', 'Ctrl+T during an insertion')
  D.eq(P.draft(), 'x = 1', 'the draft stays')
  D.key(wait, 'C-q')
  D.in_state('editor')
  D.eq(P.message_kind(), 'notice', 'Ctrl+Q during an insertion')
  D.eq(P.draft(), 'x = 1', 'the draft stays')
  D.key(wait, 'escape')
  D.key(wait, 'up')
  D.key(wait, 'f2')
  D.key(wait, 'C-t')
  D.in_state('editor')
  D.eq(P.message_kind(), 'notice', 'Ctrl+T during a replacement')
  D.eq(P.state(), 'replacing', 'the replacement stays')
  D.eq(P.stored(PROJECT, 'main.lua'), RUNS, 'nothing was written')
  D.leave(wait)
  hm_done()
end)

-- Ctrl+T runs the project from the browsing state, and Ctrl+T
-- comes back to the same file, at the same block, with its
-- undo timeline (IS1.4)
scenario('there-and-back', function(wait)
  wait(.1)
  D.open(wait, PROJECT, 'main.lua', { ['main.lua'] = RUNS })
  -- end, the function, n = 0: insert before n = 0
  D.press(wait, 'up', 2)
  D.enter(wait, 'm = 1')
  D.eq(P.stored(PROJECT, 'main.lua'), 'm = 1\n' .. RUNS,
    'the insertion is written')
  D.eq(P.position(), 2, 'on n = 0')
  D.key(wait, 'C-t')
  D.in_state('running')
  wait(.2)
  D.shot(wait, 'running')
  D.key(wait, 'C-t')
  D.in_state('editor')
  D.shot(wait, 'back')
  D.eq(P.file(), 'main.lua', 'the same file')
  D.eq(P.position(), 2, 'the same block')
  D.key(wait, 'C-z')
  D.eq(P.stored(PROJECT, 'main.lua'), RUNS,
    'Ctrl+Z after the run takes the insertion back')

  -- Ctrl+Q stops the program, the project stays open, and
  -- Ctrl+T from the console comes back to the file
  D.key(wait, 'down')
  D.eq(P.position(), 2, 'on n = 0 again')
  D.key(wait, 'C-t')
  D.in_state('running')
  D.key(wait, 'C-q')
  D.in_state('ready')
  D.eq(project(), PROJECT, 'Ctrl+Q leaves the project open')
  D.key(wait, 'C-t')
  D.in_state('editor')
  D.eq(P.position(), 2, 'Ctrl+T comes back to the block')

  -- from the editor Ctrl+Q leaves for the console with every
  -- file, and Ctrl+T then opens the main file anew
  D.key(wait, 'C-q')
  D.in_state('ready')
  D.eq(P.file(), nil, 'Ctrl+Q closes the files')
  D.eq(project(), PROJECT, 'and keeps the project open')
  D.shot(wait, 'console')
  -- with nothing running Ctrl+Q does nothing in the console
  D.key(wait, 'C-q')
  D.in_state('ready')
  D.eq(project(), PROJECT, 'the project is still open')
  D.key(wait, 'C-t')
  D.in_state('editor')
  D.eq(P.file(), 'main.lua', 'Ctrl+T opens the main file')
  D.eq(P.position(), 'end', 'at its end')
  D.leave(wait)
  hm_done()
end)

-- A program's own edit() opens a file in the editor and stops
-- the program; the editor's keys and text then reach the
-- editor
scenario('program-edit', function(wait)
  wait(.1)
  D.open(wait, PROJECT, 'main.lua', {
    ['main.lua'] = OPENS_ON_F3,
    ['notes.txt'] = 'a\nb\n',
  })
  D.key(wait, 'C-t')
  D.in_state('ready')
  assert(P.cc().run_live, 'the program idles behind the console')
  D.key(wait, 'f3')
  D.in_state('editor')
  D.shot(wait, 'opened')
  D.eq(P.file(), 'notes.txt', 'edit() opens the file')
  assert(not P.cc().run_live, 'the program is stopped')
  D.eq(P.position(), 'end', 'at its end')
  D.key(wait, 'up')
  D.eq(P.position(), 2, 'Up reaches the editor')
  D.type(wait, 'new')
  D.eq(P.draft(), 'new', 'text reaches the editor')
  D.leave(wait)
  hm_done()
end)
