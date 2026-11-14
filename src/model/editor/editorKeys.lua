--- The file editor's keys, one table per state (Keymap): what
--- each chord does in the browsing, inserting and replacing
--- states, whether it repeats while held, and what the key
--- card says of it. A chord no state binds does nothing; Ctrl
--- with Enter is not Enter (the maintainer's ruling of
--- November 14, 2026: every chord is its own key).
---
--- An action names EditorController's (`ACTIONS` in
--- editorController.lua); 'field' hands the key to the shared
--- text field, and 'none' takes it and does nothing (Ctrl+Q,
--- which the gate acts on, and the help key).
---
--- A key repeats while held only if it writes nothing and
--- changes no state (the ruling of November 14, 2026, "Which
--- keys repeat while held"); Ctrl+Z, Ctrl+Y and a cut stop
--- where their rules say (IS6.6, IS6.2).
local Keymap = require('model.input.keymap')

--- @alias EditorStateName 'browsing'|'inserting'|'replacing'
local STATES = { 'browsing', 'inserting', 'replacing' }

--- @param act string
--- @param b string? --- the card's words while browsing
--- @param i string? --- while inserting
--- @param r string? --- while replacing
--- @return table
local function each(act, b, i, r)
  return {
    browsing = { act = act, words = b },
    inserting = { act = act, words = i },
    replacing = { act = act, words = r },
  }
end

--- @param def table
--- @param fields table
local function with(def, fields)
  for k, v in pairs(fields) do def[k] = v end
  return def
end

--- Up and Down browse while the draft is empty (IS2.1), and
--- move the cursor a row in a draft (IS3.8)
local function rows(empty)
  return empty and 'browse blocks' or 'row up/down'
end

local DEFS = {
  --- IS4.1, IS4.2, IS4.3, IS5.3
  with(each('submit', 'add empty line', 'insert text',
    'replace block'),
    { chords = { 'return', 'kpenter' }, card = 'Enter' }),
  --- IS6.4; with no draft to keep it is Enter (ruling 2.6)
  with(each('submit_and_retain', 'add empty line',
    'insert, keep', 'replace, keep'),
    { chords = { 'shift+insert' }, card = 'Shift+Ins' }),
  --- IS3.15
  with(each('field', 'break the line', 'break the line',
    'break the line'),
    { chords = { 'shift+return', 'alt+return', 'shift+kpenter',
      'alt+kpenter' }, card = 'Shift/Alt+Enter',
      repeats = true }),
  --- IS5.1, IS5.5, IS5.6; refused while inserting
  with(each('edit_block', 'edit the block', nil,
    'reload/switch'),
    { chords = { 'f2' }, card = 'F2' }),
  --- IS1.6, IS5.7
  with(each('escape', 'leave the file', 'drop the text',
    'drop the edit'),
    { chords = { 'escape' }, card = 'Esc' }),
  --- the gate acts on it, and refuses it during an edit
  with(each('none', 'to the console'),
    { chords = { 'ctrl+q' }, card = 'Ctrl+Q' }),
  --- IS2.1, IS2.3
  with(each('browse', 'browse blocks', 'browse blocks',
    'browse blocks'),
    { chords = { 'ctrl+up', 'ctrl+down' },
      card = 'Ctrl+Up/Down', repeats = true }),
  with(each('vertical', rows, rows, rows),
    { chords = { 'up', 'down' }, card = 'Up/Down',
      repeats = true }),
  --- IS3.8, the draft's own keys: nothing to move in an
  --- empty field
  with(each('field', nil, 'a character', 'a character'),
    { chords = { 'left', 'right' }, card = 'Left/Right',
      repeats = true }),
  with(each('field', nil, 'a word', 'a word'),
    { chords = { 'ctrl+left', 'ctrl+right' },
      card = 'Ctrl+Left/Right', repeats = true }),
  with(each('field', nil, 'row start/end', 'row start/end'),
    { chords = { 'home', 'end' }, card = 'Home/End',
      repeats = true }),
  with(each('field', nil, 'text start/end', 'text start/end'),
    { chords = { 'ctrl+home', 'ctrl+end' },
      card = 'Ctrl+Home/End', repeats = true }),
  --- IS3.12
  with(each('field', nil, 'remove a char', 'remove a char'),
    { chords = { 'backspace', 'delete' }, card = 'Bksp/Delete',
      repeats = true }),
  with(each('field', nil, 'delete to end', 'delete to end'),
    { chords = { 'ctrl+k' }, card = 'Ctrl+K', repeats = true }),
  --- IS6.1
  with(each('copy_block', 'copy block in', 'copy block in',
    'copy block in'),
    { chords = { 'ctrl+insert' }, card = 'Ctrl+Ins' }),
  --- IS6.2; refused during an edit
  with(each('cut_block', 'cut the block'),
    { chords = { 'ctrl+delete' }, card = 'Ctrl+Delete',
      repeats = true }),
  --- IS6.5; refused while replacing
  with(each('move_block', 'move the block', 'move the block'),
    { chords = { 'alt+up', 'alt+down' },
      card = 'Alt+Up/Down' }),
  --- IS6.6
  with(each('undo', 'undo', 'undo', 'undo'),
    { chords = { 'ctrl+z' }, card = 'Ctrl+Z', repeats = true }),
  with(each('redo', 'redo', 'redo', 'redo'),
    { chords = { 'ctrl+y' }, card = 'Ctrl+Y', repeats = true }),
  --- IS1.5; refused during an edit
  with(each('follow_require', 'follow a link'),
    { chords = { 'ctrl+j' }, card = 'Ctrl+J' }),
  --- IS3.16: its press brings up the card
  with(each('none', 'this card', 'this card', 'this card'),
    { chords = { 'f1' }, card = 'F1 (hold)' }),

  --- not on the card --------------------------------------
  --- Shift+Delete cuts as well, in the browsing state only;
  --- with a draft it is the field's Delete
  { chords = { 'shift+delete' }, repeats = true,
    browsing = { act = 'cut_block' },
    inserting = { act = 'field' },
    replacing = { act = 'field' } },
  --- PgUp and PgDn browse ten blocks (PR #28, D-PAGING)
  with(each('page'), { chords = { 'pageup', 'pagedown' },
    repeats = true }),
  --- Alt with a page or edge key moves the view alone (PR
  --- #28, D-ALT-LOOK)
  with(each('peek'), { chords = { 'alt+pageup', 'alt+pagedown',
    'alt+left', 'alt+right', 'alt+home', 'alt+end' },
    repeats = true }),
  --- the draft's word deletions (D-WORD-DELETE), its line
  --- duplicated (D-DUPLICATE-LINE) or moved past its
  --- neighbor, a Backspace with Shift still held, and Shift
  --- with a move, which moves the cursor: the field has no
  --- selection here
  with(each('field'), { chords = { 'ctrl+backspace',
    'alt+backspace', 'ctrl+w', 'ctrl+d', 'alt+shift+up',
    'alt+shift+down', 'shift+backspace',
    'shift+left', 'shift+right', 'shift+up', 'shift+down',
    'shift+home', 'shift+end', 'ctrl+shift+left',
    'ctrl+shift+right', 'ctrl+shift+home', 'ctrl+shift+end' },
    repeats = true }),
  --- the whole file formatted, from the browsing state (PR
  --- #28, D-FORMAT-FILE)
  { chords = { 'ctrl+shift+f' },
    browsing = { act = 'format_file' } },
  --- deprecated: leaves the editor, refused during an edit
  with(each('leave'), { chords = { 'ctrl+shift+s' } }),
  --- with love.debug: the view drawn anew, the file split
  --- anew with Ctrl
  with(each('debug_refresh'), { chords = { 'f5', 'ctrl+f5' } }),
}

return Keymap.new(DEFS, STATES)
