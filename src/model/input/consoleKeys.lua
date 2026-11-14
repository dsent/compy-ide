--- The console's keys (Keymap): one table while no program
--- lives behind the console, one while a program runs, is
--- paused or idles there, so that the card lists Ctrl+Q,
--- which stops it, among the keys now. A chord neither binds
--- does nothing: Ctrl with Enter is not Enter, Ctrl with Up
--- is not Up (the maintainer's ruling of November 14, 2026).
---
--- An action names ConsoleController's (`ACTIONS` in
--- consoleController.lua); 'field' hands the key to the
--- console's text field, 'none' takes it and does nothing
--- (Ctrl+Q, which the gate acts on, and the help key). A key
--- repeats while held only if it writes nothing and changes
--- no state (the ruling "Which keys repeat while held").
local Keymap = require('model.input.keymap')

local STATES = { 'idle', 'live' }

--- @param act string
--- @param words string?
--- @return table
local function both(act, words)
  return {
    idle = { act = act, words = words },
    live = { act = act, words = words },
  }
end

local function with(def, fields)
  for k, v in pairs(fields) do def[k] = v end
  return def
end

local DEFS = {
  --- IS3.6
  with(both('run', 'run the line'),
    { chords = { 'return', 'kpenter' }, card = 'Enter' }),
  --- a submission that retains the draft (the spec's
  --- *submission*)
  with(both('run_and_keep', 'run it, keep it'),
    { chords = { 'shift+insert' }, card = 'Shift+Ins' }),
  --- IS3.15
  with(both('field', 'break the line'),
    { chords = { 'shift+return', 'alt+return', 'shift+kpenter',
      'alt+kpenter' }, card = 'Shift/Alt+Enter',
      repeats = true }),
  with(both('field', 'clear the line'),
    { chords = { 'escape' }, card = 'Esc' }),
  --- the gate stops the program
  { chords = { 'ctrl+q' }, card = 'Ctrl+Q',
    idle = { act = 'none' },
    live = { act = 'none', words = 'exit program' } },
  --- IS7.8: at the first or last row, the history
  with(both('field', 'earlier/later'),
    { chords = { 'up', 'down' }, card = 'Up/Down',
      repeats = true }),
  with(both('field', 'a character'),
    { chords = { 'left', 'right' }, card = 'Left/Right',
      repeats = true }),
  with(both('field', 'a word'),
    { chords = { 'ctrl+left', 'ctrl+right' },
      card = 'Ctrl+Left/Right', repeats = true }),
  with(both('field', 'row start/end'),
    { chords = { 'home', 'end' }, card = 'Home/End',
      repeats = true }),
  with(both('field', 'text start/end'),
    { chords = { 'ctrl+home', 'ctrl+end' },
      card = 'Ctrl+Home/End', repeats = true }),
  with(both('field', 'remove a char'),
    { chords = { 'backspace', 'delete' }, card = 'Bksp/Delete',
      repeats = true }),
  --- the draft's undo and redo (D-UNDO-KEYS)
  with(both('field', 'undo'),
    { chords = { 'ctrl+z' }, card = 'Ctrl+Z', repeats = true }),
  with(both('field', 'redo'),
    { chords = { 'ctrl+y' }, card = 'Ctrl+Y', repeats = true }),
  --- IS3.16: its press brings up the card
  with(both('none', 'this card'),
    { chords = { 'f1' }, card = 'F1 (hold)' }),

  --- not on the card --------------------------------------
  --- the history a whole entry at a time
  with(both('history'), { chords = { 'pageup', 'pagedown' },
    repeats = true }),
  --- the terminal cleared
  with(both('clear_terminal'), { chords = { 'ctrl+l' } }),
  --- Shift with a move selects; a selection, or a character
  --- with Shift still held, is deleted; Alt+Up and Alt+Down
  --- move the cursor's line
  with(both('field'), { chords = { 'shift+left', 'shift+right',
    'shift+up', 'shift+down', 'shift+home', 'shift+end',
    'ctrl+shift+left', 'ctrl+shift+right', 'ctrl+shift+home',
    'ctrl+shift+end', 'shift+backspace', 'shift+delete',
    'alt+up', 'alt+down', 'alt+shift+up', 'alt+shift+down' },
    repeats = true }),
  --- with love.DEBUG: the terminal test
  with(both('terminal_test'), { chords = { 'ctrl+alt+t' } }),
}

return Keymap.new(DEFS, STATES)
