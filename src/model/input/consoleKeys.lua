--- The console's own keys (Keymap): one table while no
--- program lives behind the console, one while a program
--- runs, is paused or idles there. A chord these tables do not
--- name goes to the text field's (fieldKeys.lua), and does
--- nothing if that does not name it either: Ctrl with Enter is
--- not Enter, Ctrl with Up is not Up (the maintainer's ruling
--- of November 14, 2026). Shift+Ins, the file editor's
--- submit-and-keep, does nothing here (his ruling of the same
--- day).
---
--- An action names ConsoleController's (`ACTIONS` in
--- consoleController.lua); 'field' hands the key to the
--- console's text field, 'none' takes it and does nothing
--- (the help key). The gate's reserved chords are in
--- reservedKeys.lua. A held key repeats to its natural stop
--- (the maintainer's ruling of November 16, 2026); Enter acts
--- once per press.
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
  --- once per press: a repeat would run the line again, or
  --- the next line typed, at repeat speed
  with(both('run', 'run the line'),
    { chords = { 'return', 'kpenter' }, card = 'Enter' }),
  --- the field's Escape, which clears the line (its
  --- clear_on_cancel)
  with(both('field', 'clear the line'),
    { chords = { 'escape' }, card = 'Esc', repeats = true }),
  --- the field's Up and Down, which walk the history at the
  --- first and last row (IS7.8, as the classic shell's)
  with(both('field', 'earlier/later'),
    { chords = { 'up', 'down' }, card = 'Up/Down',
      repeats = true }),
  --- the output and its kept rows scrolled, a row at a time;
  --- the draft stays (the maintainer's ruling "Console
  --- scrollback, first version")
  with(both('scroll_row', 'scroll a row'),
    { chords = { 'ctrl+up', 'ctrl+down' }, card = 'Ctrl+Up/Down',
      repeats = true }),
  --- a page of 15 rows, one carried over ("PgUp and PgDn page
  --- by the view")
  with(both('scroll_page'),
    { chords = { 'pageup', 'pagedown' }, repeats = true,
      trivial = true }),
  --- with the field empty, the oldest and the newest row; with
  --- text in it, the field's own keys (trivial there)
  with(both('scroll_end', function(empty)
      return empty and 'oldest/newest' or nil
    end),
    { chords = { 'home', 'end' }, card = 'Home/End',
      repeats = true }),
  --- the oldest and the newest row, draft or no draft; the
  --- draft stays (the maintainer's ruling of November 17,
  --- 2026: "the Home/End for scrolling/document view when
  --- there's text in the draft area")
  with(both('output_edge', 'oldest/newest'),
    { chords = { 'ctrl+pageup', 'ctrl+pagedown' },
      card = 'Ctrl+PgUp/PgDn', repeats = true }),
  --- the screen and the kept rows cleared
  with(both('clear_terminal', 'clear screen'),
    { chords = { 'ctrl+l' }, card = 'Ctrl+L', repeats = true }),
  --- IS3.16: its press brings up the card
  with(both('none', 'this card'),
    { chords = { 'f1' }, card = 'F1 (hold)' }),
  --- with love.DEBUG: the terminal test
  with(both('terminal_test'), { chords = { 'ctrl+alt+t' } }),
}

--- The field's keys are the line's, in either state
local keymap = Keymap.new(DEFS, STATES)
keymap.field_now = { idle = true, live = true }
keymap.surface = 'console'
return keymap
