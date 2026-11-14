--- The key card (IS3.16, FR4.9): every key the surface in
--- front takes, those its state admits first, with what each
--- does, laid out to fit the screen. The words come from the
--- tables the keys are looked up in, so the card cannot
--- disagree with them: the surface's own (editorKeys.lua,
--- consoleKeys.lua), then the text field's (fieldKeys.lua),
--- then the gate's reserved chords (reservedKeys.lua). It
--- reads state and changes none.
local EditorKeys = require('model.editor.editorKeys')
local ConsoleKeys = require('model.input.consoleKeys')
local FieldKeys = require('model.input.fieldKeys')
local Reserved = require('model.input.reservedKeys')

local KeyCard = { }

--- The width of one column of the card, in characters.
local COLUMN = 32

--- The help key: the card shows while it is held.
KeyCard.KEY = 'f1'

--- @return boolean
function KeyCard.held()
  local kb = love.keyboard
  --- by scancode too: under LÖVE on SDL3's SDL2 layer isDown
  --- answers false for a held function key
  if kb.isDown(KeyCard.KEY) then return true end
  local by_scancode = kb.isScancodeDown
  return by_scancode ~= nil and by_scancode(KeyCard.KEY)
end

--- Whether a surface's card shows (IS3.16): while the help
--- key is held and its press, a bare F1, reached the
--- surface's own key handler, which records it in `pressed`
--- until the release. A press a program took is recorded
--- nowhere: the program gives its own help, and nothing is
--- suspended. While the file editor's card shows, its keys and
--- the reserved chords do nothing, Ctrl+Escape apart; the
--- console's holds back the console's own keys alone.
--- @param pressed table<string, true> --- the surface's record
--- @return boolean
function KeyCard.shows(pressed)
  return pressed[KeyCard.KEY] == true and KeyCard.held()
end

--- Rows { key, what it does, admitted } as cells: the
--- admitted keys under a heading naming the context, then the
--- other keys under their own.
--- @param context string --- a state's or the console's name
--- @param rows table[]
--- @return table[] --- { heading = s } or { key = k, what = w }
local function split(context, rows)
  local now = { { heading = 'Keys now, ' .. context .. ':' } }
  local other = { }
  for _, k in ipairs(rows) do
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

--- A surface's rows in `state`: its own keys, the text
--- field's that it does not take for itself and that its field
--- has, then the reserved chords it gives words to
--- @param keys table --- the surface's keymap
--- @param state string
--- @param empty boolean?
--- @return table[] --- { key, what it does, admitted }
function KeyCard.rows(keys, state, empty)
  local rows = keys:card_rows(state, empty)
  local now = keys.field_now[state] == true
  local field = FieldKeys:card_rows('field', empty, function(d)
    return not keys:binds(d)
        and (not d.only or keys.allows[d.only] == true)
  end)
  for _, r in ipairs(field) do
    rows[#rows + 1] = { r[1], r[2], now }
  end
  for _, r in ipairs(Reserved) do
    local words = r.card and r[keys.surface]
    if words then
      local w = words[state]
      if not w then
        for _, st in ipairs(keys.states) do
          w = w or words[st]
        end
      end
      rows[#rows + 1] = { r.card, w, words[state] ~= nil }
    end
  end
  return rows
end

--- The file editor's card in reading order: the keys its
--- state admits, under a heading naming the state, then its
--- other keys.
--- @param state EditorStateName
--- @param empty boolean
--- @return table[] --- { heading = s } or { key = k, what = w }
function KeyCard.cells(state, empty)
  return split(state, KeyCard.rows(EditorKeys, state, empty))
end

--- The console's card: Ctrl+Q exits a program that runs, is
--- paused or idles behind the console; with none it does
--- nothing, and the card lists it among the other keys.
--- @param live boolean? --- a program is not stopped
--- @return table[]
function KeyCard.console_cells(live)
  return split('console',
    KeyCard.rows(ConsoleKeys, live and 'live' or 'idle'))
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
