--- The key card's content (IS3.16, FR4.9): the keys the
--- editor's state admits and what each does, then the
--- editor's other keys. It reads state and changes none.
local KeyCard = { }

--- The width of one column of the card, in characters.
local COLUMN = 32

--- The help key: the card shows while it is held.
KeyCard.KEY = 'f1'

--- @alias EditorStateName 'browsing'|'inserting'|'replacing'

--- @return boolean
function KeyCard.held()
  local kb = love.keyboard
  --- by scancode too: under LÖVE on SDL3's SDL2 layer isDown
  --- answers false for a held function key
  if kb.isDown(KeyCard.KEY) then return true end
  local by_scancode = kb.isScancodeDown
  return by_scancode ~= nil and by_scancode(KeyCard.KEY)
end

--- @param state EditorStateName
--- @param empty boolean --- the draft is empty
--- @return table[] --- { key, what it does, admitted }
local function keys(state, empty)
  local browsing = state == 'browsing'
  local inserting = state == 'inserting'
  local replacing = state == 'replacing'
  local function pick(b, i, r)
    if browsing then return b end
    if inserting then return i end
    return r
  end
  local rows = empty and 'browse blocks' or 'row up/down'
  local enter = pick('add empty line', 'insert text',
    'replace block')
  --- with no draft to keep, Shift+Ins is Enter (IS6.4)
  local keep = pick('add empty line', 'insert, keep',
    'replace, keep')
  local edit = pick('edit the block', 'edit the block',
    'reload/switch')
  local esc = pick('leave the file', 'drop the text',
    'drop the edit')
  return {
    { 'Enter', enter, true },
    { 'Shift+Ins', keep, true },
    { 'Shift/Alt+Enter', 'break the line', true },
    { 'F2', edit, not inserting },
    { 'Esc', esc, true },
    { 'Ctrl+Q', 'to the console', browsing },
    { 'Ctrl+Up/Down', 'browse blocks', true },
    { 'Up/Down', rows, true },
    { 'Left/Right', 'a character', not browsing },
    { 'Ctrl+Left/Right', 'a word', not browsing },
    { 'Home/End', 'row start/end', not browsing },
    { 'Ctrl+Home/End', 'text start/end', not browsing },
    { 'Bksp/Delete', 'remove a char', not browsing },
    { 'Ctrl+K', 'delete to end', not browsing },
    { 'Ctrl+Ins', 'copy block in', true },
    { 'Ctrl+Delete', 'cut the block', browsing },
    { 'Alt+Up/Down', 'move the block', not replacing },
    { 'Ctrl+Z', 'undo', true },
    { 'Ctrl+Y', 'redo', true },
    { 'Ctrl+J', 'follow a link', browsing },
    { 'F1 (hold)', 'this card', true },
  }
end

--- The card's cells in reading order: the state's keys
--- under a heading naming the state, then the other keys.
--- @param state EditorStateName
--- @param empty boolean
--- @return table[] --- { heading = s } or { key = k, what = w }
function KeyCard.cells(state, empty)
  local now = { { heading = 'Keys now, ' .. state .. ':' } }
  local other = { }
  for _, k in ipairs(keys(state, empty)) do
    local to = k[3] and now or other
    to[#to + 1] = { key = k[1], what = k[2] }
  end
  if #other > 0 then
    now[#now + 1] = { heading = 'Other keys:' }
  end
  for _, c in ipairs(other) do
    now[#now + 1] = c
  end
  return now
end

--- The console's card: the keys of the console input context.
--- Ctrl+Q is on it only while a program idles behind the
--- console: with none it does nothing there.
--- @param live boolean? --- a program is not stopped
--- @return table[]
function KeyCard.console_cells(live)
  local cells = {
    { heading = 'Keys now, console:' },
    { key = 'Enter', what = 'run the line' },
    { key = 'Shift/Alt+Enter', what = 'break the line' },
    { key = 'Esc', what = 'clear the line' },
    { key = 'Up/Down', what = 'earlier/later' },
    { key = 'Left/Right', what = 'a character' },
    { key = 'Ctrl+Left/Right', what = 'a word' },
    { key = 'Home/End', what = 'row start/end' },
    { key = 'Ctrl+Home/End', what = 'text start/end' },
    { key = 'Bksp/Delete', what = 'remove a char' },
  }
  if live then
    cells[#cells + 1] = {
      key = 'Ctrl+Q', what = 'stop program',
    }
  end
  cells[#cells + 1] = { key = 'F1 (hold)', what = 'this card' }
  return cells
end

--- The cells laid out in as few columns as fit `rows`, each
--- column of even length.
--- @param cells table[]
--- @param rows integer --- the card's height
--- @param width integer --- its width, in characters
--- @return table[][] grid --- grid[row][column] is a cell
--- @return integer col_w --- a column's width
--- @return integer key_w --- the widest key's width
--- @return integer cols --- the number of columns
function KeyCard.layout(cells, rows, width)
  local max_cols = math.max(1, math.floor(width / COLUMN))
  local cols = math.ceil(#cells / math.max(1, rows))
  cols = math.min(math.max(1, cols), max_cols)
  local per_col = math.min(math.ceil(#cells / cols), rows)
  local key_w = 0
  for _, c in ipairs(cells) do
    if c.key then key_w = math.max(key_w, #c.key) end
  end
  local grid = { }
  for r = 1, per_col do
    grid[r] = { }
    for c = 1, cols do
      grid[r][c] = cells[(c - 1) * per_col + r]
    end
  end
  return grid, (cols > 1 and COLUMN or width), key_w, cols
end

--- The file editor's card as plain text, a string per row.
--- @param state EditorStateName
--- @param empty boolean
--- @param rows integer
--- @param width integer
--- @return string[]
function KeyCard.lines(state, empty, rows, width)
  local cells = KeyCard.cells(state, empty)
  return KeyCard.lines_of(cells, rows, width)
end

--- Cells as plain text, a string per row.
--- @param cells table[]
--- @param rows integer
--- @param width integer
--- @return string[]
function KeyCard.lines_of(cells, rows, width)
  local grid, col_w, key_w, cols =
      KeyCard.layout(cells, rows, width)
  local out = { }
  for r, row in ipairs(grid) do
    local line = ''
    for c = 1, cols do
      local cell = row[c]
      local text = ''
      if cell and cell.heading then
        text = ' ' .. cell.heading
      elseif cell then
        local pad = string.rep(' ', key_w - #cell.key)
        text = ' ' .. cell.key .. pad .. ' ' .. cell.what
      end
      text = text:sub(1, col_w)
      line = line .. text .. string.rep(' ', col_w - #text)
    end
    out[r] = (line:gsub('%s+$', ''))
  end
  return out
end

return KeyCard
