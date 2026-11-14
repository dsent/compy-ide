--- Which keys repeat while held, in the console and in the
--- file editor. A key repeats only if it writes nothing to a
--- file and changes no state: it moves the cursor, browses,
--- or edits the draft. Every other key acts once per press,
--- and its repeats are dropped: Enter, Escape, F2, Shift+Ins,
--- Ctrl+Ins, moving a block, every command. Typed text comes
--- as text, which this table does not see. A program's own
--- input field is not covered: it keeps the repeats it has.
local HeldKeys = {}

--- move the cursor, browse, look around, delete in the draft
local MOVES = {
  left = true,
  right = true,
  up = true,
  down = true,
  home = true,
  ['end'] = true,
  pageup = true,
  pagedown = true,
  backspace = true,
  delete = true,
  --- typed as text on the web build (UserInputController)
  space = true,
}

--- Shift+Enter or Alt+Enter: a line break in the draft
--- @return boolean
local function line_break()
  return (Key.shift() or Key.alt()) and not Key.ctrl()
end

--- @return boolean
local function ctrl_alone()
  return Key.ctrl() and not Key.alt() and not Key.shift()
end

--- The file editor. Ctrl+Z and Ctrl+Y repeat through the
--- draft's changes and stop there, and a held Ctrl+Delete
--- stops at the first block it cuts into the field (IS6.6,
--- IS6.2): those keys say so themselves. Alt+Up and Alt+Down
--- move a block, and act once.
--- @param k string
--- @return boolean
function HeldKeys.editor(k)
  if Key.is_enter(k) then return line_break() end
  local alt_alone = Key.alt() and not Key.ctrl()
  if alt_alone and (k == 'up' or k == 'down') then
    return false
  end
  if MOVES[k] then return true end
  --- undo, redo, the word and line deletions, the line's
  --- duplicate: the draft's
  local draft = k == 'z' or k == 'y' or k == 'w' or k == 'k'
      or k == 'd'
  return draft and ctrl_alone()
end

--- The console's line. Alt+Up and Alt+Down move a line of
--- the draft there, and Ctrl+Y deletes one.
--- @param k string
--- @return boolean
function HeldKeys.console(k)
  if Key.is_enter(k) then return line_break() end
  if MOVES[k] then return true end
  return k == 'y' and Key.ctrl()
end

return HeldKeys
