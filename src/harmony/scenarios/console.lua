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
    local function seconds()
      local _, n = string.gsub(P.console_text(), 'second', '')
      return n
    end
    local before = seconds()
    D.key(wait, 'up')
    D.key(wait, 'return')
    D.eq(seconds(), before + 1, 'a recalled line runs')
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
end

console()
