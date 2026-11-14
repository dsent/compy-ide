--- The file editor's own keys, one table per state (Keymap):
--- what each chord does in the browsing, inserting and
--- replacing states, whether it repeats while held, and what
--- the key card says of it. A chord these tables do not name
--- goes to the text field's (fieldKeys.lua), and does nothing
--- if that does not name it either: every chord is its own
--- key (the maintainer's ruling of November 14, 2026).
---
--- An action names EditorController's (`ACTIONS` in
--- editorController.lua); 'field' hands the key to the text
--- field, and 'none' takes it and does nothing (the help
--- key). The gate's reserved chords are in reservedKeys.lua.
---
--- A key repeats while held only if it writes nothing and
--- changes no state (the ruling of November 14, 2026, "Which
--- keys repeat while held"); Ctrl+Z and Ctrl+Y stop at the
--- draft's changes (IS6.6).
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

--- Up and Down browse while the draft is empty (IS2.1); in a
--- draft they move the cursor a row (IS3.8), which needs no
--- word on the card
local function rows(empty)
  return empty and 'browse blocks' or nil
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
  --- IS5.1, IS5.5, IS5.6; refused while inserting
  with(each('edit_block', 'edit the block', nil,
    'reload/switch'),
    { chords = { 'f2' }, card = 'F2' }),
  --- IS1.6, IS5.7
  with(each('escape', 'leave the file', 'drop the text',
    'drop the edit'),
    { chords = { 'escape' }, card = 'Esc' }),
  --- IS2.1, IS2.3
  with(each('browse', 'browse blocks', 'browse blocks',
    'browse blocks'),
    { chords = { 'ctrl+up', 'ctrl+down' },
      card = 'Ctrl+Up/Down', repeats = true }),
  --- the field's Up and Down, which browse while the draft is
  --- empty
  with(each('vertical', 'browse blocks', nil, rows),
    { chords = { 'up', 'down' }, card = 'Up/Down',
      repeats = true }),
  --- with an empty field Home and End move through the file:
  --- to the first block, and to the end position, where new
  --- text goes (PR #28, D-PAGING; the maintainer's ruling of
  --- November 14, 2026). In a draft they are the field's.
  { chords = { 'home', 'end' }, card = 'Home/End',
    browsing = { act = 'file_edge', words = 'file start/end' } },
  --- a page at a time, the position with it (the
  --- maintainer's ruling of November 14, 2026); trivial, off
  --- the card
  with(each('page'), { chords = { 'pagedown', 'pageup' },
    repeats = true, trivial = true }),
  --- IS6.1
  with(each('copy_block', 'copy block in', 'copy block in',
    'copy block in'),
    { chords = { 'ctrl+insert' }, card = 'Ctrl+Ins' }),
  --- IS6.2; refused during an edit. It writes, so it acts
  --- once per press
  with(each('cut_block', 'cut the block'),
    { chords = { 'ctrl+delete' }, card = 'Ctrl+Delete' }),
  --- IS6.5; refused while replacing
  with(each('move_block', 'move the block', 'move the block'),
    { chords = { 'alt+up', 'alt+down' },
      card = 'Alt+Up/Down' }),
  --- IS6.6: the file's timeline, through the draft's changes
  with(each('undo', 'undo', 'undo', 'undo'),
    { chords = { 'ctrl+z' }, card = 'Ctrl+Z', repeats = true }),
  with(each('redo', 'redo', 'redo', 'redo'),
    { chords = { 'ctrl+y' }, card = 'Ctrl+Y', repeats = true }),
  --- IS1.5; refused during an edit
  with(each('follow_require', 'follow a link'),
    { chords = { 'ctrl+j' }, card = 'Ctrl+J' }),
  --- the whole file formatted, from the browsing state (PR
  --- #28, D-FORMAT-FILE); refused with a notice in an edit
  with(each('format_file', 'format the file'),
    { chords = { 'alt+f' }, card = 'Alt+F' }),
  --- IS3.16: its press brings up the card
  with(each('none', 'this card', 'this card', 'this card'),
    { chords = { 'f1' }, card = 'F1 (hold)' }),
  --- with love.debug: the view drawn anew, the file split
  --- anew with Ctrl
  with(each('debug_refresh'), { chords = { 'f5', 'ctrl+f5' } }),
}

--- The field's keys are the draft's: on the card among the
--- keys now while there is a draft to edit
local keymap = Keymap.new(DEFS, STATES)
keymap.field_now = { inserting = true, replacing = true }
keymap.surface = 'editor'
return keymap
