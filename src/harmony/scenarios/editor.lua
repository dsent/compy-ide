local h = love.harmony.utils or error()

--- The file editor's scenarios, with its keys (the key card,
--- model/editor/keyCard.lua): a file opens at its end; Up and
--- Down browse the blocks while the field is empty, Ctrl+Up
--- and Ctrl+Down always; typing starts a draft that Enter
--- inserts before the browsed block; F2 loads the browsed
--- block for replacement; Escape drops an edit, and while
--- browsing steps back from the file; Ctrl+Q leaves the
--- editor for the console.
---
--- A scenario that changes a file checks what the editor
--- saved. The turtle example is run by later scenarios, so a
--- scenario that edits it works on a clone, or takes its
--- changes back with Ctrl+Z and checks that it did.

--- the lines of a project's file, as the editor saved it
--- @param project string
--- @param file string
--- @return string[]
local function saved(project, file)
  local path = FS.join_path(
    love.harmony.tmpdir, 'projects', project, file)
  return string.lines(FS.read(path) or '')
end

--- @param lines string[]
--- @param text string
--- @return integer? --- the first line that is `text`
local function find(lines, text)
  for i, l in ipairs(lines) do
    if l == text then return i end
  end
end

--- @param a string[]
--- @param b string[]
--- @return boolean
local function same(a, b)
  return table.concat(a, '\n') == table.concat(b, '\n')
end

--- @param want string --- love.state.app_state
local function in_state(want)
  local st = love.state.app_state
  assert(st == want,
    string.format('expected %s, the IDE is %s', want, st))
end

--- `keys`, with its modifiers let go once it has landed: a
--- modifier stays held until release_keys, and a key or text
--- sent while it is held is a chord
--- @param wait function
--- @param keys string
local function chord(wait, keys)
  h.love_key(keys)
  wait(.05)
  h.release_keys()
  wait(.05)
end

--- a screenshot of the screen as it is now: it is taken a
--- frame later, so the next key waits for it
--- @param wait function
--- @param tag string
local function shot(wait, tag)
  h.screenshot(tag)
  wait(.1)
end

--- `key`, `n` times
--- @param wait function
--- @param key string
--- @param n integer
local function press(wait, key, n)
  for _ = 1, n do
    h.love_key(key)
    wait(.05)
  end
end

--- browse to the file's first block: a page key moves ten
--- blocks, and every line of a comment is a block
--- @param wait function
local function to_top(wait)
  press(wait, 'pageup', 12)
end

--- type a line into the console, or a draft into the editor,
--- and submit it with Enter
--- @param wait function
--- @param text string
local function enter(wait, text)
  h.love_text(text)
  wait(.1)
  h.love_key('return')
  wait(.2)
end

local function editor()
  scenario('open-close', function(wait)
    wait(.1)
    enter(wait, 'project("create")')
    enter(wait, 'edit()')
    in_state('editor')
    shot(wait, 'open')
    wait(.5)
    -- Escape while browsing steps back from the file, here
    -- to the console
    h.love_key('escape')
    wait(.2)
    in_state('ready')

    enter(wait, 'list_contents()')
    wait(.5)
    -- no key closes a project: the console command does
    enter(wait, 'close_project()')

    hm_done('edit')
  end)

  scenario('add', function(wait)
    wait(.1)
    enter(wait, 'project("test-add")')
    enter(wait, 'edit()')
    in_state('editor')

    -- at the end of the file, a draft is added there, as
    -- the formatter lays it out
    h.love_text('for i=1,5 do print(i) end')
    wait(.1)
    shot(wait, 'input')
    wait(.1)
    h.love_key('return')
    wait(.2)
    shot(wait, 'added')
    local loop = 'for i = 1, 5 do'
    local lines = saved('test-add', 'main.lua')
    local at = find(lines, loop)
    assert(at and lines[at + 1] == '  print(i)'
      and lines[at + 2] == 'end', 'the loop was not added')

    -- Up browses onto the new block, and a draft goes in
    -- before it
    h.love_key('up')
    wait(.1)
    shot(wait, 'sel-up')
    enter(wait, 'print("count")')
    -- Enter with no draft adds an empty line
    h.love_key('return')
    wait(.2)
    shot(wait, 'newline')
    lines = saved('test-add', 'main.lua')
    at = find(lines, loop)
    assert(at and lines[at - 1] == ''
      and lines[at - 2] == 'print("count")',
      'expected print, an empty line and the loop')

    -- Ctrl+Ins copies the browsed block into the draft, and
    -- Enter adds the copy before it
    chord(wait, 'C-insert')
    shot(wait, 'copied')
    h.love_key('return')
    wait(.2)
    lines = saved('test-add', 'main.lua')
    assert(lines[at] == loop and lines[at + 3] == loop,
      'expected the loop twice')

    h.love_key('escape')
    wait(.2)
    in_state('ready')

    hm_done()
  end)

  scenario('change', function(wait)
    local file = 'drawing.lua'
    local function body()
      return saved('turtlemod', file)[2]
    end
    --- browse to line 2, the body's color, and load it
    local function load_body()
      -- the blocks of the file's top are its single lines
      to_top(wait)
      h.love_key('down')
      wait(.1)
      h.love_key('f2')
      wait(.1)
    end

    wait(.1)
    enter(wait, 'clone("turtle", "turtlemod")')
    shot(wait, 'clone')
    enter(wait, 'project("turtlemod")')
    enter(wait, 'edit("' .. file .. '")')
    in_state('editor')
    shot(wait, 'open')
    wait(.2)
    -- Ctrl+T runs the project, and again returns to the file
    chord(wait, h.shortcuts.toggle)
    in_state('running')
    wait(1.5)
    shot(wait, 'before')
    chord(wait, h.shortcuts.toggle)
    in_state('editor')

    press(wait, 'up', 7)
    shot(wait, 'sel-up')
    h.love_key('pageup')
    wait(.1)
    shot(wait, 'page-up')

    load_body()
    shot(wait, 'loaded')
    assert(body() == 'body_color = Color.green')
    -- F2 puts the cursor at the end of the block
    press(wait, 'backspace', 5)
    h.love_text('red')
    wait(.1)
    h.love_key('return')
    wait(.2)
    shot(wait, 'edited')
    assert(body() == 'body_color = Color.red',
      'the change was not saved')
    chord(wait, h.shortcuts.toggle)
    in_state('running')
    wait(.3)
    shot(wait, 'after')

    wait(.4)
    chord(wait, h.shortcuts.toggle)
    in_state('editor')
    load_body()
    press(wait, 'backspace', 3)
    h.love_text('blue')
    wait(.1)
    h.love_key('return')
    wait(.2)
    shot(wait, 'edited-2')
    assert(body() == 'body_color = Color.blue',
      'the second change was not saved')
    chord(wait, h.shortcuts.toggle)
    in_state('running')
    wait(.3)
    shot(wait, 'after-2')

    wait(.5)
    -- Ctrl+Q stops the program; the project stays open
    chord(wait, 'C-q')
    in_state('ready')
    wait(.1)

    hm_done()
  end)

  scenario('move', function(wait)
    local file = 'action.lua'
    local fn = 'function pause_game(msg)'
    wait(.1)
    enter(wait, 'project("turtle")')
    local original = saved('turtle', file)
    enter(wait, 'edit("' .. file .. '")')
    in_state('editor')
    shot(wait, 'open')

    wait(.2)
    -- from the end: the return, the table, the pause function
    press(wait, 'up', 5)
    shot(wait, 'sel-up')
    local from = find(original, fn)

    -- Alt+Up moves the browsed block past the one above it
    chord(wait, 'A-up')
    shot(wait, 'move-up')
    chord(wait, 'A-up')
    shot(wait, 'move-done')
    local moved = saved('turtle', file)
    local to = find(moved, fn)
    assert(to and from and to < from, 'the block did not move up')

    -- Ctrl+Z takes the moves back one at a time, Ctrl+Y
    -- makes one again
    chord(wait, 'C-z')
    chord(wait, 'C-z')
    shot(wait, 'undone')
    assert(same(saved('turtle', file), original),
      'two undos did not restore the file')
    chord(wait, 'C-y')
    shot(wait, 'redone')
    local redone = find(saved('turtle', file), fn)
    assert(redone and redone < from, 'redo did not move it')
    chord(wait, 'C-z')
    assert(same(saved('turtle', file), original),
      'the undo after the redo did not restore the file')

    wait(.5)
    h.love_key('escape')
    wait(.2)
    in_state('ready')
    hm_done()
  end)

  scenario('delete', function(wait)
    local function main()
      return saved('turtlecut', 'main.lua')
    end
    wait(.1)
    enter(wait, 'clone("turtle", "turtlecut")')
    enter(wait, 'project("turtlecut")')
    enter(wait, 'edit("main.lua")')
    in_state('editor')
    shot(wait, 'open')

    wait(.2)
    to_top(wait)
    shot(wait, 'up')
    -- from the first line down to `incr = 10`
    press(wait, 'down', 6)
    shot(wait, 'move-down')

    -- Ctrl+Delete cuts the browsed block into the draft, and
    -- Escape drops it
    chord(wait, 'C-delete')
    shot(wait, 'cut')
    assert(not find(main(), 'incr = 10'), 'nothing was cut')
    h.love_key('escape')
    wait(.2)
    shot(wait, 'delete')
    assert(not find(main(), 'incr = 10'))

    wait(.2)
    h.love_text('incr = 20')
    wait(.1)
    shot(wait, 'input')
    h.love_key('return')
    wait(.2)
    shot(wait, 'added')
    assert(find(main(), 'incr = 20'), 'the new line is missing')

    wait(.5)
    chord(wait, 'C-q')
    in_state('ready')
    shot(wait, 'leave')

    enter(wait, 'print("let\'s check back")')
    shot(wait, 'msg')
    -- the console's history: the print, then the edit
    h.love_key('up')
    wait(.1)
    shot(wait, 'history-1')
    h.love_key('up')
    wait(.1)
    shot(wait, 'history-2')
    h.love_key('return')
    wait(.2)
    in_state('editor')
    to_top(wait)
    shot(wait, 'reopen')

    wait(.5)
    h.love_key('escape')
    wait(.2)
    in_state('ready')
    shot(wait, 'exit')

    hm_done()
  end)

  -- The view follows the browsing position; Alt with a page
  -- or edge key scrolls the view alone. A loaded block stays
  -- the target while the position moves, and the editor is
  -- not left while it is loaded.
  scenario('scroll', function(wait)
    local file = 'drawing.lua'
    wait(.1)
    enter(wait, 'project("turtle")')
    local original = saved('turtle', file)
    enter(wait, 'edit("' .. file .. '")')
    in_state('editor')
    shot(wait, 'end')

    press(wait, 'pageup', 2)
    shot(wait, 'page-up')
    chord(wait, 'A-end')
    shot(wait, 'peek-end')
    chord(wait, 'A-pageup')
    shot(wait, 'peek-up')
    -- a browse brings the view back to the position
    chord(wait, 'C-down')
    shot(wait, 'follow-back')

    h.love_key('f2')
    wait(.1)
    chord(wait, 'C-down')
    chord(wait, 'C-down')
    chord(wait, 'C-down')
    shot(wait, 'loaded-browse')
    -- Ctrl+Q is refused during an edit, with a notice
    chord(wait, 'C-q')
    in_state('editor')
    shot(wait, 'loaded-protect')

    wait(.5)
    -- the first Escape drops the edit and the notice, the
    -- second leaves the file
    h.love_key('escape')
    wait(.2)
    in_state('editor')
    shot(wait, 'dropped')
    h.love_key('escape')
    wait(.2)
    in_state('ready')
    assert(same(saved('turtle', file), original),
      'the file changed')

    hm_done()
  end)

  -- Ctrl+J opens the file a require names; Escape steps back
  -- to the file that named it
  scenario('follow', function(wait)
    wait(.1)
    enter(wait, 'project("turtle")')
    enter(wait, 'edit("main.lua")')
    in_state('editor')
    -- the first line: actions = require("action")
    to_top(wait)
    shot(wait, 'require')
    chord(wait, 'C-j')
    in_state('editor')
    shot(wait, 'followed')

    wait(.3)
    -- still in the editor after one Escape: Ctrl+J opened a
    -- second file, and a refusal would have opened none
    h.love_key('escape')
    wait(.2)
    in_state('editor')
    shot(wait, 'back')
    h.love_key('escape')
    wait(.2)
    in_state('ready')

    hm_done()
  end)
end

editor()
