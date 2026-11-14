--- The text field's keys (Keymap, one state): the same in
--- the console, the file editor and a program's input field
--- (the maintainer's ruling of November 14, 2026: one text
--- field everywhere). A surface's own table names only its own
--- keys; a chord it does not name comes here, and a chord this
--- table does not name either does nothing.
---
--- An action names one of the field's (`ACT` in
--- userInputController.lua). `only = 'duplicate'`: where the
--- field's owner switches it on (allow_duplicate_line). The
--- words are what a key card says of the key; an alias of a
--- key with words has none. There is no selection: the
--- clipboard that needed one is gone.
local Keymap = require('model.input.keymap')

--- @param act string
--- @param words string?
--- @return table
local function key(act, words)
  return { field = { act = act, words = words } }
end

local function with(def, fields)
  for k, v in pairs(fields) do def[k] = v end
  return def
end

local DEFS = {
  --- IS3.15
  with(key('line_feed', 'break the line'),
    { chords = { 'shift+return', 'alt+return' },
      card = 'Shift/Alt+Enter', repeats = true }),
  with(key('line_feed'),
    { chords = { 'shift+kpenter', 'alt+kpenter' },
      repeats = true }),
  --- IS3.8
  with(key('char', 'a character'),
    { chords = { 'left', 'right' }, card = 'Left/Right',
      repeats = true }),
  with(key('word', 'a word'),
    { chords = { 'ctrl+left', 'ctrl+right' },
      card = 'Ctrl+Left/Right', repeats = true }),
  --- the ends of the cursor's row; with Ctrl, of the draft
  with(key('edge', 'row start/end'),
    { chords = { 'home', 'end' }, card = 'Home/End',
      repeats = true }),
  with(key('whole', 'text start/end'),
    { chords = { 'ctrl+home', 'ctrl+end' },
      card = 'Ctrl+Home/End', repeats = true }),
  with(key('vertical', 'a row'),
    { chords = { 'up', 'down' }, card = 'Up/Down',
      repeats = true }),
  --- IS3.12
  with(key('backspace', 'remove a char'),
    { chords = { 'backspace' }, card = 'Bksp/Delete',
      repeats = true }),
  with(key('delete', 'remove a char'),
    { chords = { 'delete' }, card = 'Bksp/Delete',
      repeats = true }),
  --- with Shift still held from a capital
  with(key('backspace'),
    { chords = { 'shift+backspace' }, repeats = true }),
  --- PR #28, D-WORD-DELETE
  with(key('backspace_word', 'delete a word'),
    { chords = { 'ctrl+backspace', 'ctrl+w' },
      card = 'Ctrl+Bksp/W', repeats = true }),
  with(key('backspace_word'),
    { chords = { 'alt+backspace' }, repeats = true }),
  with(key('kill', 'delete to end'),
    { chords = { 'ctrl+k' }, card = 'Ctrl+K', repeats = true }),
  --- the cursor's line moves past its neighbor
  with(key('move_line', 'move the line'),
    { chords = { 'alt+shift+up', 'alt+shift+down' },
      card = 'Alt+Shift+Up/Dn', repeats = true }),
  --- PR #28, D-DUPLICATE-LINE
  with(key('duplicate', 'copy the line'),
    { chords = { 'ctrl+d' }, card = 'Ctrl+D', repeats = true,
      only = 'duplicate' }),
  --- D-UNDO-KEYS
  with(key('undo', 'undo'),
    { chords = { 'ctrl+z' }, card = 'Ctrl+Z', repeats = true }),
  with(key('redo', 'redo'),
    { chords = { 'ctrl+y' }, card = 'Ctrl+Y', repeats = true }),
  --- the widget's own submit and cancel (D-EDIT-LIFECYCLE)
  with(key('submit', 'submit'),
    { chords = { 'return' }, card = 'Enter' }),
  with(key('submit'), { chords = { 'kpenter' } }),
  with(key('cancel', 'cancel'),
    { chords = { 'escape' }, card = 'Esc' }),
}

return Keymap.new(DEFS, { 'field' })
