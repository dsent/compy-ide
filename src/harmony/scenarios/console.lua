local h = love.harmony.utils or error()
local P = require('harmony.probe')
local D = require('harmony.drive')

local function console()
  scenario('1', function(wait)
    wait(.1)
    h.love_text('print("1")')
    wait(.1)
    h.love_key('return')
    wait(.1)

    hm_done()
  end)

  scenario('2', function(wait)
    wait(.1)
    h.love_text('print("2")')
    wait(.1)
    h.love_key('return')
    wait(.1)
    h.screenshot('after-2')
    wait(.1)

    hm_done()
  end)

  scenario('for', function(wait)
    h.love_key('C-l')
    wait(.1)
    h.release_keys()

    wait(.1)
    h.love_text('for i = 1,17 do print("line " .. i) end')
    wait(.1)
    h.love_key('return')
    wait(.1)
    h.screenshot('for')
    wait(.5)

    hm_done()
  end)

  scenario('syntax_error', function(wait)
    wait(.3)
    h.love_key('C-l')
    wait(.1)
    h.release_keys()

    wait(.1)
    h.love_text('for i = 1 do print("line " .. i) end')
    wait(.1)
    h.screenshot('bad-code')
    wait(.1)
    h.love_key('return')
    wait(.1)
    h.screenshot('code-error')
    wait(.1)
    h.love_key('down')
    wait(.1)
    h.screenshot('error-hl')
    wait(.5)
    h.love_key('down')
    wait(.1)

    hm_done()
  end)

  -- Enter runs the line and empties the field (IS3.6);
  -- Shift+Enter and Alt+Enter break it, and Enter then runs
  -- both lines (IS3.15, the ruling on Alt+Enter)
  scenario('lines', function(wait)
    D.key(wait, 'escape')
    D.key(wait, 'C-l')
    D.enter(wait, 'print("ran " .. 6 * 7)')
    D.eq(P.console_draft(), '', 'Enter empties the field')
    assert(string.find(P.console_text(), 'ran 42', 1, true),
      'the line did not run')
    D.type(wait, 'x = 41')
    D.key(wait, 'S-return')
    D.eq(P.console_draft(), 'x = 41\n', 'Shift+Enter breaks the line')
    D.type(wait, 'print("shift " .. x + 1)')
    D.key(wait, 'return')
    D.type(wait, 'y = 9')
    D.key(wait, 'A-return')
    D.eq(P.console_draft(), 'y = 9\n', 'Alt+Enter breaks the line')
    D.type(wait, 'print("alt " .. y * 11)')
    D.shot(wait, 'two-lines')
    D.key(wait, 'return')
    D.shot(wait, 'ran')
    local out = P.console_text()
    assert(string.find(out, 'shift 42', 1, true),
      'the Shift+Enter lines did not run')
    assert(string.find(out, 'alt 99', 1, true),
      'the Alt+Enter lines did not run')
    hm_done()
  end)

  -- Up and Down walk the history of run lines; Escape clears
  -- the field, and on an empty field does nothing and keeps the
  -- project open (IS1.6)
  scenario('history', function(wait)
    D.enter(wait, 'print("first")')
    D.enter(wait, 'print("second")')
    D.key(wait, 'up')
    D.eq(P.console_draft(), 'print("second")', 'Up recalls the last')
    D.key(wait, 'up')
    D.eq(P.console_draft(), 'print("first")', 'Up again, the one before')
    D.shot(wait, 'recalled')
    D.key(wait, 'down')
    D.eq(P.console_draft(), 'print("second")', 'Down, the later one')
    D.key(wait, 'escape')
    D.eq(P.console_draft(), '', 'Escape clears the field')
    local open = P.cc().model.projects.current.name
    D.key(wait, 'escape')
    D.in_state('ready')
    D.eq(P.cc().model.projects.current.name, open,
      'Escape on an empty field keeps the project')
    --- the output's rows that print("second") wrote: its echo
    --- (the scrollback's) reads print("second")
    local function seconds()
      local n = 0
      for row in (P.console_text() .. '\n'):gmatch('(.-)\n') do
        if row:match('^second%s*$') then n = n + 1 end
      end
      return n
    end
    local before = seconds()
    D.key(wait, 'up')
    D.key(wait, 'return')
    D.eq(seconds(), before + 1, 'a recalled line runs')
    hm_done()
  end)

  -- What a scenario reads as the console's text holds a line
  -- whole while the terminal is still writing it: read at every
  -- frame of the writing, the line is there each time. A check
  -- made a few frames after Enter met a line cut in two, its
  -- start on the screen and its rest still waiting, and failed
  -- by the frame's length.
  scenario('text-while-printing', function(wait)
    D.key(wait, 'escape')
    -- on a cleared screen: what waits is written at the cursor,
    -- rows above the screen's last
    D.key(wait, 'C-l')
    local line = 'printed-' .. ('x'):rep(40) .. '-whole'
    D.enter(wait, 'print("' .. line .. '")')
    local term = P.cc().model.output.terminal
    local read, midway = 0, 0
    repeat
      local n = 0
      for _ in term:waiting() do n = n + 1 end
      local at = term.cursor_x
      assert(string.find(P.console_text(), '\n' .. line .. '\n', 1, true),
        'the printed line is cut with ' .. n .. ' characters waiting')
      read = read + 1
      if n > 0 and at > 1 then midway = midway + 1 end
      wait(.001)
    until n == 0
    assert(midway > 0, 'the line was never read while being written, '
      .. 'in ' .. read .. ' readings')
    hm_done()
  end)

  -- The walk is the classic shell's: the line being typed
  -- waits below the newest line and comes back on Down, an
  -- edit to a recalled line stays until Enter, and the history
  -- holds only the lines that ran
  scenario('history-walk', function(wait)
    D.key(wait, 'escape')
    D.enter(wait, 'print("old " .. 1)')
    D.type(wait, 'draft')
    D.shot(wait, 'walk-1-draft')
    D.key(wait, 'up')
    D.eq(P.console_draft(), 'print("old " .. 1)', 'Up, the last line')
    D.key(wait, 'backspace')
    D.key(wait, 'backspace')
    D.type(wait, '2)')
    D.eq(P.console_draft(), 'print("old " .. 2)', 'edited')
    D.shot(wait, 'walk-2-edited')
    D.key(wait, 'down')
    D.eq(P.console_draft(), 'draft', 'Down, the draft back')
    D.shot(wait, 'walk-3-draft-back')
    D.key(wait, 'down')
    D.eq(P.console_draft(), 'draft', 'Down on the draft, no change')
    D.key(wait, 'up')
    D.eq(P.console_draft(), 'print("old " .. 2)', 'Up, the edit kept')
    D.shot(wait, 'walk-4-edit-kept')
    D.key(wait, 'return')
    -- the echo of the line goes first, and the output takes
    -- its time: 800 characters a second
    wait(.5)
    assert(string.find(P.console_text(), 'old 2', 1, true),
      'the edited line did not run')
    D.key(wait, 'up')
    D.eq(P.console_draft(), 'print("old " .. 2)', 'Up, the edit that ran')
    D.shot(wait, 'walk-5-ran')
    D.key(wait, 'up')
    D.eq(P.console_draft(), 'print("old " .. 1)', 'Up, the original')
    D.shot(wait, 'walk-6-original')
    D.key(wait, 'escape')
    hm_done()
  end)

  -- Shift+Ins does nothing in the console (the maintainer's
  -- ruling of November 14, 2026), though the spec's
  -- *submission* names it there
  scenario('run-keep', function(wait)
    D.key(wait, 'escape')
    D.type(wait, 'print("kept " .. 5 * 5)')
    D.key(wait, 'S-insert')
    D.shot(wait, 'kept')
    assert(not string.find(P.console_text(), 'kept 25', 1, true),
      'Shift+Ins ran the line')
    D.eq(P.console_draft(), 'print("kept " .. 5 * 5)',
      'Shift+Ins leaves the line')
    D.key(wait, 'escape')
    hm_done()
  end)

  -- eval, print_eval and loadstring run in the console/program
  -- environment, and eval reports an error in the string
  scenario('eval-env', function(wait)
    D.key(wait, 'escape')
    D.key(wait, 'C-l')
    D.enter(wait, 'x = 5')
    D.enter(wait, 'print("ev=" .. eval("x"))')
    D.enter(wait, 'print_eval("x + 1")')
    D.enter(wait, 'loadstring("y = x * 2")()')
    D.enter(wait, 'print("y=" .. y)')
    D.enter(wait, 'eval("10 / ")')
    local out = P.console_text()
    assert(string.find(out, 'ev=5', 1, true), 'eval did not see x')
    assert(string.find(out, '\n6\n', 1, true), 'print_eval did not print 6')
    assert(string.find(out, 'y=10', 1, true), 'loadstring did not set y')
    assert(string.find(out, 'unexpected symbol', 1, true),
      'eval error was not reported')
    hm_done()
  end)

  -- tty.setEcho(on) switches echoing of accepted console lines
  -- from the next line on, keeping history and printed output
  scenario('set-echo', function(wait)
    D.key(wait, 'escape')
    D.key(wait, 'C-l')
    D.enter(wait, 'tty.setEcho(false)')
    D.enter(wait, 'print("quiet-out")')
    D.enter(wait, 'tty.setEcho(true)')
    D.enter(wait, 'print("loud-out")')
    local out = P.console_text()
    local function has_row(want)
      for row in (out .. '\n'):gmatch('(.-)\n') do
        if row:match('^%s*(.-)%s*$') == want then return true end
      end
      return false
    end
    assert(string.find(out, 'tty.setEcho(false)', 1, true),
      'calling line was not echoed')
    assert(not string.find(out, 'print("quiet-out")', 1, true),
      'line while echo off was echoed')
    assert(has_row('quiet-out'),
      'printed output while echo off did not appear on its own row')
    assert(not string.find(out, 'tty.setEcho(true)', 1, true),
      'setEcho(true) was echoed')
    assert(string.find(out, 'print("loud-out")', 1, true),
      'line after echo on was not echoed')
    assert(has_row('loud-out'),
      'printed output after echo on did not appear on its own row')
    D.key(wait, 'up')
    D.eq(P.console_draft(), 'print("loud-out")', 'history kept last')
    D.key(wait, 'up')
    D.eq(P.console_draft(), 'tty.setEcho(true)', 'history kept setEcho(true)')
    D.key(wait, 'up')
    D.eq(P.console_draft(), 'print("quiet-out")', 'history kept quiet line')
    D.key(wait, 'escape')
    hm_done()
  end)

  -- compy.screen.showNotice(text) shows a notice in the band
  -- above the status line; the next key dismisses it
  scenario('show-notice', function(wait)
    D.key(wait, 'escape')
    D.key(wait, 'C-l')
    D.enter(wait, 'compy.screen.showNotice("Press Space to jump")')
    D.eq(P.console_message(), 'Press Space to jump',
      'showNotice sets the console notice')
    D.eq(P.console_message_kind(), 'notice',
      'showNotice sets kind notice')
    assert(P.shows(P.drawn(wait), 'Press Space to jump'),
      'the band draws the notice')
    D.key(wait, 'lshift')
    D.eq(P.console_message(), 'Press Space to jump',
      'a lone modifier keeps the notice')
    --- x as a Compy sends it: its text, then its key press
    D.type(wait, 'x')
    D.key(wait, 'x')
    D.eq(P.console_message(), nil,
      'the next key dismisses the notice')
    D.eq(P.console_draft(), 'x', 'and still acts')
    assert(not P.shows(P.drawn(wait), 'Press Space to jump'),
      'the band no longer draws the notice')
    D.key(wait, 'escape')
    hm_done()
  end)
end

console()
