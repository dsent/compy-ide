local P = require('harmony.probe')
local D = require('harmony.drive')
local KeyCard = require('model.editor.keyCard')

--- The key card says what each key does (IS3.16): for each
--- row among the keys now of the editor's card in each state,
--- and of the console's with and without a program behind it,
--- the key the row names is pressed and what the row says is
--- checked. A row there with no check fails the scenario, so
--- that the card cannot gain such a row the scenario does not
--- try. The rows under "Other keys" are not pressed: each is a
--- key now in another state, tried there. Ctrl+Esc's row is
--- read and its key not pressed, since it would end the run.
--- The trivial keys (the arrows in a draft, Home and End on its
--- row, Backspace, Delete, paging) are on no card (the ruling
--- of November 14, late); fields.lua tries them, and
--- scrollback.lua the console's PgUp, PgDn, and Home and End
--- with the field empty. Also: Ctrl+Q is held back while the
--- card shows, in the console as in the editor (IS3.16, the
--- ruling of November 16).

local PROJECT = 'h-rows'
local FILE = 'rows.lua'
local TEXT = 'a = 1\nb = 2\nc = 3\nm = require("other")\n'
local OTHER = 'o = 1\n'
--- a program behind the console: it hooks no key, so the
--- console takes them
local IDLES = 'n = 0\nfunction love.update() n = n + 1 end\n'
--- a program that ends its code and stays live behind the
--- console with its picture, able to do nothing more: the console
--- keeps its keys and its card (a program that can act owns all
--- input, November 17)
local ENDS = 'n = 0\n'

local function stored() return P.stored(PROJECT, FILE) end
local function col()
  local l, c = P.cursor()
  return l .. ':' .. c
end

--- the editor on the fixture, at block 2, in `state`
--- @param wait function
--- @param state string
local function fresh(wait, state)
  if love.state.app_state == 'editor' then D.leave(wait) end
  D.open(wait, PROJECT, FILE, { [FILE] = TEXT,
    ['other.lua'] = OTHER, ['main.lua'] = IDLES })
  D.press(wait, 'up', 3)
  if state == 'inserting' then D.type(wait, 'q = 9') end
  if state == 'replacing' then D.key(wait, 'f2') end
  D.eq(P.state(), state, 'the state to try')
  D.eq(P.position(), 2, 'on block 2')
end

--- Ctrl+Esc ends the IDE, and the run with it: its row is
--- read, and the key is not pressed
local function quits() end

--- a run of the project, stopped again
--- @param wait function
--- @param chord string
local function runs(wait, chord)
  D.key(wait, chord)
  D.in_state('running')
  D.key(wait, 'C-q')
  D.in_state('ready')
end

local function card_shows(wait)
  local shows
  D.with_card(wait, function() shows = P.card() end)
  assert(shows, 'F1 held shows no card')
end

--- what each row says, tried in each state: [state][key] is
--- { words, check }
local EDITOR = {
  browsing = {
    ['Enter'] = { 'add empty line', function(wait)
      D.key(wait, 'return')
      D.eq(stored(), 'a = 1\n\nb = 2\nc = 3\nm = require("other")\n',
        'an empty line')
    end },
    ['Shift+Ins'] = { 'add empty line', function(wait)
      D.key(wait, 'S-insert')
      D.eq(stored(), 'a = 1\n\nb = 2\nc = 3\nm = require("other")\n',
        'an empty line')
    end },
    ['Shift/Alt+Enter'] = { 'break the line', function(wait)
      D.key(wait, 'S-return')
      D.eq(P.draft(), '\n', 'Shift+Enter breaks the line')
      D.key(wait, 'A-return')
      D.eq(P.draft(), '\n\n', 'Alt+Enter breaks the line')
      D.eq(stored(), TEXT, 'nothing written')
    end },
    ['F2'] = { 'edit the block', function(wait)
      D.key(wait, 'f2')
      D.eq(P.target(), 2, 'b is the target')
      D.eq(P.draft(), 'b = 2', 'and the draft')
    end },
    ['Esc'] = { 'leave the file', function(wait)
      D.key(wait, 'escape')
      D.in_state('ready')
    end },
    ['Ctrl+Q'] = { 'to the console', function(wait)
      D.key(wait, 'C-q')
      D.in_state('ready')
      D.eq(P.file(), nil, 'no file stays open')
    end },
    ['Ctrl+Up/Down'] = { 'browse blocks', function(wait)
      D.key(wait, 'C-up')
      D.eq(P.position(), 1, 'Ctrl+Up')
      D.key(wait, 'C-down')
      D.eq(P.position(), 2, 'Ctrl+Down')
    end },
    ['Up/Down'] = { 'browse blocks', function(wait)
      D.key(wait, 'up')
      D.eq(P.position(), 1, 'Up')
      D.key(wait, 'down')
      D.eq(P.position(), 2, 'Down')
    end },
    ['Ctrl+Ins'] = { 'copy block in', function(wait)
      D.key(wait, 'C-insert')
      D.eq(P.draft(), 'b = 2', 'the copy')
      D.eq(stored(), TEXT, 'nothing written')
    end },
    ['Ctrl+Delete'] = { 'cut the block', function(wait)
      D.key(wait, 'C-delete')
      D.eq(P.draft(), 'b = 2', 'the cut block')
      D.eq(stored(), 'a = 1\nc = 3\nm = require("other")\n', 'cut')
    end },
    ['Alt+Up/Down'] = { 'move the block', function(wait)
      D.key(wait, 'A-up')
      D.eq(stored(), 'b = 2\na = 1\nc = 3\nm = require("other")\n',
        'Alt+Up')
      D.key(wait, 'A-down')
      D.eq(stored(), TEXT, 'Alt+Down')
    end },
    ['Ctrl+Z'] = { 'undo', function(wait)
      D.key(wait, 'return')
      D.key(wait, 'C-z')
      D.eq(stored(), TEXT, 'the empty line undone')
    end },
    ['Ctrl+Y'] = { 'redo', function(wait)
      D.key(wait, 'return')
      D.key(wait, 'C-z')
      D.key(wait, 'C-y')
      D.eq(stored(), 'a = 1\n\nb = 2\nc = 3\nm = require("other")\n',
        'the empty line redone')
    end },
    ['Ctrl+J'] = { 'follow a link', function(wait)
      D.press(wait, 'down', 2)
      D.key(wait, 'C-j')
      D.eq(P.file(), 'other.lua', 'Ctrl+J opens the required file')
    end },
    ['F1 (hold)'] = { 'this card', card_shows },
    ['Ctrl+T'] = { 'run the project', function(wait)
      runs(wait, 'C-t')
    end },
    ['Ctrl+R'] = { 'run anew', function(wait)
      runs(wait, 'C-r')
    end },
    ['Ctrl+Esc'] = { 'quit the IDE', quits },
    ['Alt+F'] = { 'format the file', function(wait)
      D.leave(wait)
      D.open(wait, PROJECT, FILE, { [FILE] = 'a=1\n' .. TEXT:sub(7) })
      D.key(wait, 'A-f')
      D.eq(stored(), TEXT, 'the file formatted')
    end },
    ['Home/End'] = { 'file start/end', function(wait)
      D.key(wait, 'end')
      D.eq(P.position(), 'end', 'End, to the end position')
      D.key(wait, 'home')
      D.eq(P.position(), 1, 'Home, to the first block')
      D.eq(P.draft(), '', 'no text')
    end },
  },
}

--- the draft's own keys, the same while inserting and
--- replacing; `d` is the draft the state starts with
--- @param d string
local function draft_rows(d)
  local n = #d + 1
  return {
    ['Shift/Alt+Enter'] = { 'break the line', function(wait)
      D.key(wait, 'S-return')
      D.eq(P.draft(), d .. '\n', 'Shift+Enter')
      D.key(wait, 'A-return')
      D.eq(P.draft(), d .. '\n\n', 'Alt+Enter')
    end },
    ['Ctrl+Up/Down'] = { 'browse blocks', function(wait)
      D.key(wait, 'C-up')
      D.eq(P.position(), 1, 'Ctrl+Up')
      D.eq(P.draft(), d, 'the draft stays')
    end },
    ['Ctrl+Left/Right'] = { 'a word', function(wait)
      D.key(wait, 'C-left')
      D.eq(col(), '1:' .. (n - 1), 'Ctrl+Left to the word start')
      D.key(wait, 'C-left')
      D.eq(col(), '1:1', 'and the one before')
      D.key(wait, 'C-right')
      D.eq(col(), '1:2', 'Ctrl+Right to the word end')
    end },
    ['Ctrl+Home/End'] = { 'text start/end', function(wait)
      D.key(wait, 'S-return')
      D.type(wait, 'zz')
      D.key(wait, 'C-home')
      D.eq(col(), '1:1', 'Ctrl+Home, the text\'s start')
      D.key(wait, 'C-end')
      D.eq(col(), '2:3', 'Ctrl+End, its end')
    end },
    ['Ctrl+K'] = { 'delete to end', function(wait)
      D.key(wait, 'home')
      D.key(wait, 'right')
      D.key(wait, 'C-k')
      D.eq(P.draft(), d:sub(1, 1), 'Ctrl+K')
    end },
    ['Ctrl+Ins'] = { 'copy block in', function(wait)
      D.key(wait, 'C-insert')
      D.eq(P.draft(), d .. '\nb = 2', 'the copy on a line of its own')
    end },
    ['Ctrl+Z'] = { 'undo', function(wait)
      D.type(wait, '8')
      D.key(wait, 'C-z')
      D.eq(P.draft(), d, 'the typing undone')
    end },
    ['Ctrl+Y'] = { 'redo', function(wait)
      D.type(wait, '8')
      D.key(wait, 'C-z')
      D.key(wait, 'C-y')
      D.eq(P.draft(), d .. '8', 'the typing redone')
    end },
    ['F1 (hold)'] = { 'this card', card_shows },
    ['Ctrl+Esc'] = { 'quit the IDE', quits },
    ['Ctrl+Bksp/W'] = { 'delete a word', function(wait)
      -- a word of letters after a space: what a word is
      -- around punctuation is fields.lua's question
      D.type(wait, ' ab')
      D.key(wait, 'C-backspace')
      D.eq(P.draft(), d .. ' ', 'Ctrl+Backspace')
      D.type(wait, 'cd')
      D.key(wait, 'C-w')
      D.eq(P.draft(), d .. ' ', 'Ctrl+W')
    end },
    ['Alt+Shift+Up/Dn'] = { 'move the line', function(wait)
      D.key(wait, 'S-return')
      D.type(wait, 'zz')
      D.key(wait, 'A-S-up')
      D.eq(P.draft(), 'zz\n' .. d, 'Alt+Shift+Up')
      D.key(wait, 'A-S-down')
      D.eq(P.draft(), d .. '\nzz', 'Alt+Shift+Down')
    end },
  }
end

EDITOR.inserting = draft_rows('q = 9')
EDITOR.inserting['Enter'] = { 'insert text', function(wait)
  D.key(wait, 'return')
  D.eq(stored(), 'a = 1\nq = 9\nb = 2\nc = 3\nm = require("other")\n',
    'inserted before b')
end }
EDITOR.inserting['Shift+Ins'] = { 'insert, keep', function(wait)
  D.key(wait, 'S-insert')
  D.eq(stored(), 'a = 1\nq = 9\nb = 2\nc = 3\nm = require("other")\n',
    'inserted before b')
  D.eq(P.draft(), 'q = 9', 'and kept')
end }
EDITOR.inserting['Esc'] = { 'drop the text', function(wait)
  D.key(wait, 'escape')
  D.eq(P.draft(), '', 'dropped')
  D.in_state('editor')
end }
EDITOR.inserting['Alt+Up/Down'] = { 'move the block', function(wait)
  D.key(wait, 'A-up')
  D.eq(stored(), 'b = 2\na = 1\nc = 3\nm = require("other")\n',
    'moved')
  D.eq(P.draft(), 'q = 9', 'the draft stays')
end }

EDITOR.replacing = draft_rows('b = 2')
EDITOR.replacing['Enter'] = { 'replace block', function(wait)
  D.type(wait, '0')
  D.key(wait, 'return')
  D.eq(stored(), 'a = 1\nb = 20\nc = 3\nm = require("other")\n',
    'replaced')
end }
EDITOR.replacing['Shift+Ins'] = { 'replace, keep', function(wait)
  D.type(wait, '0')
  D.key(wait, 'S-insert')
  D.eq(stored(), 'a = 1\nb = 20\nc = 3\nm = require("other")\n',
    'replaced')
  D.eq(P.draft(), 'b = 20', 'and kept')
  D.eq(P.target(), nil, 'the replacement is finished')
end }
EDITOR.replacing['F2'] = { 'reload/switch', function(wait)
  D.type(wait, '0')
  D.key(wait, 'f2')
  D.eq(P.draft(), 'b = 2', 'reloaded')
end }
EDITOR.replacing['Esc'] = { 'drop the edit', function(wait)
  D.key(wait, 'escape')
  D.eq(P.target(), nil, 'dropped')
  D.in_state('editor')
end }
EDITOR.replacing['Ctrl+G'] = { 'go to the edit', function(wait)
  D.key(wait, 'C-up')
  D.eq(P.position(), 1, 'browsed away')
  D.key(wait, 'C-g')
  D.eq(P.position(), 2, 'back on the target')
  D.eq(P.target(), 2, 'the target stays')
  D.eq(P.draft(), 'b = 2', 'and the draft')
end }

--- the card's admitted rows, the keys now, as the card lists
--- them
--- @param cells table[]
--- @return table[] --- { key, what }
local function keys_now(cells)
  local out = {}
  for i, c in ipairs(cells) do
    if c.heading and i > 1 then break end
    if c.key then out[#out + 1] = c end
  end
  return out
end

--- each row the card shows, drawn as it says
--- @param wait function
--- @param rows table[]
local function drawn(wait, rows)
  D.with_card(wait, function()
    local d = P.drawn(wait)
    for _, r in ipairs(rows) do
      assert(P.shows(d, r.key) and P.shows(d, r.what),
        'the card does not draw ' .. r.key .. ': ' .. r.what)
    end
  end)
end

scenario('editor', function(wait)
  wait(.1)
  for _, state in ipairs({ 'browsing', 'inserting', 'replacing' }) do
    fresh(wait, state)
    local rows = keys_now(KeyCard.cells(state, state == 'browsing'))
    drawn(wait, rows)
    for _, r in ipairs(rows) do
      local t = EDITOR[state][r.key]
      assert(t, 'no check for the ' .. state .. ' card row '
        .. r.key .. ': ' .. r.what)
      D.eq(r.what, t[1], 'the ' .. state .. ' card row ' .. r.key)
      fresh(wait, state)
      t[2](wait)
    end
  end
  if love.state.app_state == 'editor' then D.leave(wait) end
  hm_done()
end)

--- the console's rows: a draft `D0` with history behind it
local D0 = 'x = 7'
local CONSOLE = {
  ['Enter'] = { 'run the line', function(wait)
    D.key(wait, 'escape')
    D.type(wait, 'print("row " .. 6 * 7)')
    D.key(wait, 'return')
    -- the echo of the line goes first, and the output takes
    -- its time: 800 characters a second
    wait(.5)
    assert(string.find(P.console_text(), 'row 42', 1, true), 'not run')
  end },
  ['Shift/Alt+Enter'] = { 'break the line', function(wait)
    D.key(wait, 'S-return')
    D.key(wait, 'A-return')
    D.eq(P.console_draft(), D0 .. '\n\n', 'two breaks')
  end },
  ['Esc'] = { 'clear the line', function(wait)
    D.key(wait, 'escape')
    D.eq(P.console_draft(), '', 'cleared')
  end },
  ['Up/Down'] = { 'earlier/later', function(wait)
    D.key(wait, 'escape')
    D.enter(wait, 'print("history")')
    D.key(wait, 'up')
    D.eq(P.console_draft(), 'print("history")', 'Up, the last line')
    D.key(wait, 'down')
    D.eq(P.console_draft(), '', 'Down, back')
  end },
  ['Ctrl+Left/Right'] = { 'a word', function(wait)
    D.key(wait, 'C-left')
    D.eq(select(2, P.field_cursor('console')), 5, 'Ctrl+Left')
    D.key(wait, 'C-left')
    D.eq(select(2, P.field_cursor('console')), 1, 'again')
    D.key(wait, 'C-right')
    D.eq(select(2, P.field_cursor('console')), 2, 'Ctrl+Right')
  end },
  ['Ctrl+Z'] = { 'undo', function(wait)
    D.type(wait, '8')
    D.key(wait, 'C-z')
    D.eq(P.console_draft(), D0, 'undone')
  end },
  ['Ctrl+Y'] = { 'redo', function(wait)
    D.type(wait, '8')
    D.key(wait, 'C-z')
    D.key(wait, 'C-y')
    D.eq(P.console_draft(), D0 .. '8', 'redone')
  end },
  ['Ctrl+Q'] = { 'exit program', function(wait)
    D.key(wait, 'C-q')
    assert(not P.cc().run_live, 'the program still lives')
  end },
  ['F1 (hold)'] = { 'this card', card_shows },
  ['Ctrl+Esc'] = { 'quit the IDE', quits },
  ['Ctrl+T'] = { 'to the editor', function(wait)
    D.key(wait, 'C-t')
    D.in_state('editor')
    D.leave(wait)
  end },
  --- the program behind the console ends its code again, its
  --- picture staying (ENDS)
  ['Ctrl+R'] = { 'run anew', function(wait)
    D.key(wait, 'escape')
    D.key(wait, 'C-r')
    D.in_state('ready')
    assert(P.cc().run_live, 'Ctrl+R did not run it anew')
    D.key(wait, 'C-q')
    D.in_state('ready')
  end },
  ['Ctrl+Up/Down'] = { 'scroll a row', function(wait)
    D.key(wait, 'escape')
    D.enter(wait, "for i = 1, 40 do print('row ' .. i) end")
    wait(1)
    D.type(wait, D0)
    local out = P.cc().model.output
    D.key(wait, 'C-up')
    assert(out:is_scrolled(), 'Ctrl+Up did not scroll')
    local t = out:top()
    D.key(wait, 'C-up')
    D.eq(out:top(), t - 1, 'Ctrl+Up, a row older')
    D.key(wait, 'C-down')
    D.eq(out:top(), t, 'Ctrl+Down, a row newer')
    D.eq(P.console_draft(), D0, 'the draft stays')
    D.key(wait, 'escape')
    assert(out:is_scrolled(), 'Esc moved the scrolled view')
    D.key(wait, 'end')
    assert(not out:is_scrolled(),
      'End on an empty field left the view scrolled')
  end },
  ['Ctrl+L'] = { 'clear screen', function(wait)
    D.key(wait, 'escape')
    D.enter(wait, 'print("on screen")')
    D.key(wait, 'C-l')
    assert(not string.find(P.console_text(), 'on screen', 1, true),
      'Ctrl+L left the output')
  end },
  ['Ctrl+Bksp/W'] = { 'delete a word', function(wait)
    D.type(wait, ' ab')
    D.key(wait, 'C-backspace')
    D.eq(P.console_draft(), D0 .. ' ', 'Ctrl+Backspace')
  end },
  ['Ctrl+K'] = { 'delete to end', function(wait)
    D.key(wait, 'home')
    D.key(wait, 'C-k')
    D.eq(P.console_draft(), '', 'Ctrl+K')
  end },
  ['Ctrl+Home/End'] = { 'text start/end', function(wait)
    D.key(wait, 'S-return')
    D.type(wait, 'zz')
    D.key(wait, 'C-home')
    D.eq(table.concat({ P.field_cursor('console') }, ':'), '1:1',
      'Ctrl+Home')
    D.key(wait, 'C-end')
    D.eq(table.concat({ P.field_cursor('console') }, ':'), '2:3',
      'Ctrl+End')
  end },
  ['Alt+Shift+Up/Dn'] = { 'move the line', function(wait)
    D.key(wait, 'S-return')
    D.type(wait, 'zz')
    D.key(wait, 'A-S-up')
    D.eq(P.console_draft(), 'zz\n' .. D0, 'Alt+Shift+Up')
  end },
}

--- @param wait function
--- @param live boolean
local function console_rows(wait, live)
  local function start()
    D.key(wait, 'escape')
    if live and not P.cc().run_live then
      D.enter(wait, 'run_project()')
      wait(.1)
      assert(P.cc().run_live, 'no program behind the console')
    end
    D.type(wait, D0)
  end
  start()
  local rows = keys_now(KeyCard.console_cells(live))
  drawn(wait, rows)
  for _, r in ipairs(rows) do
    local t = CONSOLE[r.key]
    assert(t, 'no check for the console card row ' .. r.key
      .. ': ' .. r.what)
    D.eq(r.what, t[1], 'the console card row ' .. r.key)
    start()
    t[2](wait)
  end
  D.key(wait, 'escape')
end

scenario('console', function(wait)
  wait(.1)
  D.enter(wait, string.format('project(%q)', PROJECT))
  P.put(PROJECT, 'main.lua', ENDS)
  D.key(wait, 'escape')
  console_rows(wait, false)
  console_rows(wait, true)
  if P.cc().run_live then D.key(wait, 'C-q') end
  D.in_state('ready')
  hm_done()
end)

-- Ctrl+Q while F1 is held: the card holds it back, in the
-- console as in the editor (IS3.16); released, it acts
scenario('ctrl-q-held', function(wait)
  wait(.1)
  D.enter(wait, string.format('project(%q)', PROJECT))
  P.put(PROJECT, 'main.lua', ENDS)
  D.enter(wait, 'run_project()')
  wait(.1)
  assert(P.cc().run_live, 'no program behind the console')
  D.with_card(wait, function()
    assert(P.card(), 'the console card shows')
    D.key(wait, 'C-q')
    assert(P.cc().run_live, 'Ctrl+Q under F1 stopped the program')
  end)
  D.key(wait, 'C-q')
  assert(not P.cc().run_live, 'Ctrl+Q did not stop the program')
  fresh(wait, 'browsing')
  D.with_card(wait, function()
    assert(P.card(), 'the editor card shows')
    D.key(wait, 'C-q')
    D.in_state('editor')
  end)
  D.key(wait, 'C-q')
  D.in_state('ready')
  hm_done()
end)
