--- The file editor's own keys, one table per state (Keymap):
--- what each chord does in the browsing, inserting and
--- replacing states, whether it repeats while held, and what
--- the key card says of it. A chord these tables do not name
--- goes to the text field's (fieldKeys.lua), and does nothing
--- if that does not name it either: every chord is its own
--- key (the maintainer's ruling of November 14, 2026).
---
--- An action names EditorController's (`ACTIONS` in
--- editorController.lua); 'none' takes the key and does
--- nothing (the help key). The gate's reserved chords are in
--- reservedKeys.lua.
---
--- A held key repeats, and each is safe to hold because it
--- reaches a natural stop (the maintainer's ruling of November
--- 16, 2026, which adopts the specification's and Luditor's);
--- Ctrl+Z and Ctrl+Y stop at the draft's changes (IS6.6).
--- Shift+Ins and Ctrl+Ins act once per press: each repeat
--- would add another copy, with no stop. So does Escape: held
--- after a cut, it would drop the edit and then leave the
--- file, whose timeline holds the cut block's only copy; Ctrl+Q
--- leaves every file at once. And so does Ctrl+J: rushing
--- through files at repeat speed confuses (the user's ruling
--- of November 16, 2026).
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
--- draft they move the cursor a row (IS3.8), a trivial key
--- with no word and no row on the card
local function rows(empty)
  return empty and 'browse blocks' or nil
end

local DEFS = {
  --- IS4.1, IS4.2, IS4.3, IS5.3
  with(each('submit', 'add empty line', 'insert text',
    'replace block'),
    { chords = { 'return', 'kpenter' }, card = 'Enter',
      repeats = true }),
  --- IS6.4; with no draft to keep it is Enter (ruling 2.6)
  with(each('submit_and_retain', 'add empty line',
    'insert, keep', 'replace, keep'),
    { chords = { 'shift+insert' }, card = 'Shift+Ins' }),
  --- IS5.1, IS5.5, IS5.6; refused while inserting
  with(each('edit_block', 'edit the block', nil,
    'reload/switch'),
    { chords = { 'f2' }, card = 'F2', repeats = true }),
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
  with(each('vertical', 'browse blocks', rows, rows),
    { chords = { 'up', 'down' }, card = 'Up/Down',
      repeats = true }),
  --- with an empty field Home and End move through the file:
  --- to the first block, and to the end position, where new
  --- text goes (PR #28, D-PAGING; the maintainer's ruling of
  --- November 14, 2026). In a draft they are the field's.
  { chords = { 'home', 'end' }, card = 'Home/End',
    repeats = true,
    browsing = { act = 'file_edge', words = 'file start/end' } },
  --- what Home and End do with an empty field, in every state,
  --- the draft kept (the maintainer's ruling of November 17,
  --- 2026: "the Home/End for scrolling/document view when
  --- there's text in the draft area")
  with(each('file_edge', 'file start/end', 'file start/end',
    'file start/end'),
    { chords = { 'ctrl+pageup', 'ctrl+pagedown' },
      card = 'Ctrl+PgUp/PgDn', repeats = true }),
  --- while replacing, the browsing position to the target
  --- (the maintainer's ruling of November 14, 2026)
  { chords = { 'ctrl+g' }, card = 'Ctrl+G', repeats = true,
    replacing = { act = 'to_target', words = 'go to the edit' } },
  --- a page at a time, the position with it (the
  --- maintainer's ruling of November 14, 2026); trivial, off
  --- the card
  with(each('page'), { chords = { 'pagedown', 'pageup' },
    repeats = true, trivial = true }),
  --- IS6.1
  with(each('copy_block', 'copy block in', 'copy block in',
    'copy block in'),
    { chords = { 'ctrl+insert' }, card = 'Ctrl+Ins' }),
  --- IS6.2; refused during an edit. Held, it removes the empty
  --- lines down to the first block with text, cuts it and
  --- stops (IS6.2's note)
  with(each('cut_block', 'cut the block'),
    { chords = { 'ctrl+delete' }, card = 'Ctrl+Delete',
      repeats = true }),
  --- IS6.5; refused while replacing
  with(each('move_block', 'move the block', 'move the block'),
    { chords = { 'alt+up', 'alt+down' },
      card = 'Alt+Up/Down', repeats = true }),
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
    { chords = { 'alt+f' }, card = 'Alt+F', repeats = true }),
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
