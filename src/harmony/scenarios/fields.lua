local P = require('harmony.probe')
local D = require('harmony.drive')

--- One text field, the same everywhere (the ruling of November
--- 14, 2026): the file editor's, the console's and a running
--- program's field take the same field keys and the same word
--- deletions, a click places
--- the text cursor, Shift with an arrow selects nothing, and
--- a chord nothing binds does nothing, Ctrl+Enter first.

local PROJECT = 'h-fields'
--- a program that shows a field and counts its submissions
local PROMPT = [[
submitted = 0
compy.input.show{
  prompt = 'say:',
  on_text_entered = function() submitted = submitted + 1 end,
}
]]

--- @param which string
--- @return string
local function col_of(which)
  local l, c = P.field_cursor(which)
  return l .. ':' .. c
end

--- The field keys, in field `which`, starting empty
--- @param wait function
--- @param which 'editor'|'console'|'program'
local function field_keys(wait, which)
  local function text() return P.text(which) end
  D.type(wait, 'one two')
  D.key(wait, 'C-backspace')
  D.eq(text(), 'one ', 'Ctrl+Backspace deletes a word in ' .. which)
  D.type(wait, 'three')
  D.key(wait, 'S-return')
  D.type(wait, 'four')
  D.eq(text(), 'one three\nfour', 'the draft in ' .. which)
  D.key(wait, 'A-S-up')
  D.eq(text(), 'four\none three', 'Alt+Shift+Up moves the line in '
    .. which)
  D.key(wait, 'A-S-down')
  D.eq(text(), 'one three\nfour', 'Alt+Shift+Down moves it back in '
    .. which)
  D.key(wait, 'home')
  D.eq(col_of(which), '2:1', 'Home in ' .. which)
  D.key(wait, 'end')
  D.eq(col_of(which), '2:5', 'End in ' .. which)
  D.key(wait, 'C-home')
  D.press(wait, 'right', 3)
  D.key(wait, 'C-k')
  D.eq(text(), 'one\nfour', 'Ctrl+K deletes to the line end in '
    .. which)
  D.key(wait, 'C-z')
  D.eq(text(), 'one three\nfour', 'Ctrl+Z undoes it in ' .. which)
  D.key(wait, 'C-y')
  D.eq(text(), 'one\nfour', 'Ctrl+Y redoes it in ' .. which)
end

--- The word deletions, in field `which`, starting empty:
--- Ctrl+Backspace, Alt+Backspace and Ctrl+W remove exactly
--- what Ctrl+Left moves over (IS3.8, the ruling on word
--- deletion), the non-word characters before the cursor, then
--- the word; at the start of a line, the line break alone.
--- `clear` empties the field again.
--- @param wait function
--- @param which 'editor'|'console'|'program'
--- @param clear function
local function word_keys(wait, which, clear)
  local cases = {
    { 'q = 9', 'q = ' },
    { 'f(x)', 'f(' },
    { 'a.b', 'a.' },
  }
  for _, k in ipairs({ 'C-backspace', 'A-backspace', 'C-w' }) do
    for _, c in ipairs(cases) do
      D.type(wait, c[1])
      D.key(wait, k)
      D.eq(P.text(which), c[2], k .. ' after ' .. c[1] .. ' in ' .. which)
      clear()
    end
    D.type(wait, 'ab')
    D.key(wait, 'S-return')
    D.type(wait, 'cd')
    D.key(wait, 'home')
    D.key(wait, k)
    D.eq(P.text(which), 'abcd', k .. ' at a line\'s start in ' .. which)
    clear()
  end
end

--- Chords nothing binds in a field, and Shift with the arrows:
--- the draft and the cursor stay
--- @param wait function
--- @param which 'editor'|'console'|'program'
--- @param chords string[]
local function unbound(wait, which, chords)
  local text, at = P.text(which), col_of(which)
  for _, k in ipairs(chords) do
    D.key(wait, k)
    D.eq(P.text(which), text, k .. ' changes the draft in ' .. which)
    D.eq(col_of(which), at, k .. ' moves the cursor in ' .. which)
  end
end

--- a click on column 3 of the field's last row places the
--- cursor before its third character
--- @param wait function
--- @param which 'editor'|'console'|'program'
local function click(wait, which)
  local v = P.cc().cfg.view
  D.type(wait, 'abcdef')
  D.click(wait, 2 * v.fw + 4, v.h - v.fh / 2)
  D.eq(col_of(which), '1:3', 'a click places the cursor in ' .. which)
end

local FIELD_CHORDS = { 'C-return', 'C-kpenter', 'S-left', 'S-right',
  'S-home', 'S-end', 'C-a', 'C-S-up', 'A-left', 'A-home' }

scenario('editor', function(wait)
  local f = 'fields.lua'
  local text = 'a = 1\nb = 2\n'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = text })
  field_keys(wait, 'editor')
  D.key(wait, 'escape')
  word_keys(wait, 'editor', function() D.key(wait, 'escape') end)
  -- browsing: chords nothing binds change nothing at all
  for _, k in ipairs({ 'C-return', 'C-a', 'S-up', 'A-left',
    'A-pageup', 'A-end', 'C-S-s', 'S-f2' }) do
    D.key(wait, k)
    D.in_state('editor')
    D.eq(P.state(), 'browsing', k .. ' while browsing')
    D.eq(P.position(), 'end', k .. ' keeps the position')
  end
  D.type(wait, 'c = 3')
  D.key(wait, 'left')
  unbound(wait, 'editor', FIELD_CHORDS)
  -- typing after Shift+Left replaces nothing
  D.type(wait, '0')
  D.eq(P.draft(), 'c = 03', 'nothing was selected')
  D.key(wait, 'escape')
  click(wait, 'editor')
  D.shot(wait, 'clicked')
  -- a click on the document view browses nothing
  D.key(wait, 'escape')
  D.key(wait, 'up')
  D.click(wait, 40, 10)
  D.eq(P.position(), 2, 'a click on a block does not browse')
  D.eq(P.state(), 'browsing', 'a click on a block opens nothing')
  D.eq(P.stored(PROJECT, f), text, 'nothing was written')
  D.leave(wait)
  hm_done()
end)

scenario('console', function(wait)
  wait(.1)
  D.key(wait, 'escape')
  field_keys(wait, 'console')
  D.key(wait, 'escape')
  word_keys(wait, 'console', function() D.key(wait, 'escape') end)
  local out = P.console_text()
  D.type(wait, 'print("chord")')
  D.key(wait, 'left')
  unbound(wait, 'console', FIELD_CHORDS)
  unbound(wait, 'console', { 'C-up', 'C-down', 'S-insert',
    'C-insert', 'A-up' })
  D.eq(P.console_text(), out, 'no chord ran the line')
  D.key(wait, 'escape')
  click(wait, 'console')
  D.shot(wait, 'clicked')
  D.key(wait, 'escape')
  hm_done()
end)

scenario('program', function(wait)
  wait(.1)
  D.enter(wait, string.format('project(%q)', PROJECT))
  P.put(PROJECT, 'main.lua', PROMPT)
  D.enter(wait, 'run_project()')
  wait(.2)
  assert(P.field('program'), 'the program shows no field')
  local env = P.cc():get_project_env()
  field_keys(wait, 'program')
  D.key(wait, 'C-home')
  D.key(wait, 'C-k')
  D.key(wait, 'delete')
  D.key(wait, 'C-k')
  D.eq(P.text('program'), '', 'the field emptied')
  -- Escape does not empty a program's field: its draft goes
  -- with Ctrl+Home, Ctrl+K, Delete and Ctrl+K
  word_keys(wait, 'program', function()
    D.key(wait, 'C-home')
    D.key(wait, 'C-k')
    D.key(wait, 'delete')
    D.key(wait, 'C-k')
  end)
  D.eq(P.text('program'), '', 'the field emptied again')
  D.type(wait, 'hello')
  D.key(wait, 'left')
  unbound(wait, 'program', FIELD_CHORDS)
  unbound(wait, 'program', { 'A-up', 'C-insert', 'S-insert' })
  D.eq(env.submitted, 0, 'no chord submitted the field')
  D.key(wait, 'return')
  D.eq(env.submitted, 1, 'Enter submits it')
  click(wait, 'program')
  D.shot(wait, 'clicked')
  D.key(wait, 'C-q')
  D.in_state('ready')
  hm_done()
end)
