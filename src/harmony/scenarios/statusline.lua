local P = require('harmony.probe')
local D = require('harmony.drive')

--- The status line's mode (the maintainer's rulings of November
--- 17, 2026): its colour "clearly indicates the mode (but is
--- never the single differentiating indicator)"; "keep the bar
--- dark gray, just add 'running' in yellow as a status"; a
--- program's own field shows its prompt and the cursor's place
--- alone; and the IDE's own line "always starts with: project
--- file mode", the word in yellow. In each state
--- the line can show, the bar's ground is read from the
--- screen's pixels against the theme (conf/colors.lua) and its
--- words from what is drawn, and the screen is shot under the
--- state's name: the console idle and with its card, the editor
--- in each state and with its card, a program running with an
--- update, with keys alone and with its own field, paused and
--- with the card, and a program that ended by itself.

local PROJECT = 'h-status'

local function theme() return P.cc().cfg.view.colors.statusline end

--- whether the screen's left column has a run of `color` as
--- high as the status line at least: a glyph's pixel in the
--- same colour is no bar
local function has_band(img, color)
  local first, last = P.band(img, color)
  local l = require('view.layout')(P.cc().cfg.view)
  return first ~= nil and last - first + 1 >= l.status_h
end

--- the bar in the colours of `mode`, and no other mode's bar,
--- saying each of `words` and none of `not_words`, shot as
--- `name`. A key card's ground is its surface's colours, the
--- console's under a pause's bar too (`card`).
--- @param wait function
--- @param name string
--- @param mode string --- the theme's name for its colours
--- @param words string[]
--- @param not_words string[]?
--- @param card string? --- the card's ground, by its name
local function bar(wait, name, mode, words, not_words, card)
  local img = P.capture(wait)
  local says = P.drawn(wait)
  D.shot(wait, name)
  assert(has_band(img, theme()[mode].bg),
    name .. ': no bar in the ' .. mode .. ' colours')
  for other, c in pairs(theme()) do
    if other ~= mode and other ~= card then
      assert(not has_band(img, c.bg), name .. ': a bar in the '
        .. other .. ' colours')
    end
  end
  for _, w in ipairs(words) do
    assert(P.shows(says, w), name .. ': the line does not say ' .. w)
  end
  for _, w in ipairs(not_words or { }) do
    assert(not P.shows(says, w), name .. ': the line says ' .. w)
  end
end

--- run `code` as the project's main.lua
local function runs(wait, code)
  P.put(PROJECT, 'main.lua', code)
  D.enter(wait, 'run_project()')
  wait(.3)
end

local function stop(wait)
  D.key(wait, 'C-q')
  wait(.2)
  D.in_state('ready')
end

--- the state word on the screen's pixels in yellow: after the
--- margin, the project's name and, but in the console's own
--- line, the file's, each with its gap of two columns, on the
--- bar of `mode`'s colours
--- @param img love.ImageData
--- @param word string
--- @param mode string
local function word_yellow(img, word, mode)
  local v = P.cc().cfg.view
  local col = 1 + #PROJECT + 2
  if word ~= 'console' then col = col + #'main.lua' + 2 end
  local first, last = P.band(img, theme()[mode].bg)
  assert(first, word .. ': no bar')
  local _, fg = P.colors(img, col * v.fw, first, #word * v.fw,
    last - first + 1)
  assert(P.near(fg, theme()[mode].state), word .. ' in '
    .. P.show(fg) .. ', the theme has '
    .. P.show(theme()[mode].state))
end

--- With no SD card (love.state.has_removable false, read at
--- each draw), `f` runs with the no-card mark in front of the
--- IDE's lines, its bright orange read from the pixels after
--- the margin on the bar of `mode`'s colours
--- @param wait function
--- @param mode string
--- @param f function
local function without_card(wait, mode, f)
  local was = love.state.has_removable
  love.state.has_removable = false
  wait(.1)
  local v = P.cc().cfg.view
  local img = P.capture(wait)
  local first, last = P.band(img, theme()[mode].bg)
  assert(first, 'no bar')
  local _, fg = P.colors(img, v.fw, first, #'[no sd]' * v.fw,
    last - first + 1)
  local ok, e = pcall(function()
    assert(P.near(fg, theme()[mode].mark), 'the mark in '
      .. P.show(fg) .. ', the theme has '
      .. P.show(theme()[mode].mark))
    f()
  end)
  love.state.has_removable = was
  wait(.1)
  assert(ok, e)
end

--- The line of the program's own field, drawn once more with
--- its texts recorded where they start and, measured by the
--- line's own font, where they end: every one on the screen,
--- none running into the next, and the cursor's place whole. A
--- character wider than its cell overruns until the fonts are
--- fixed (Beads compy-ide-fonts-characters-wider-than-a-cell),
--- so these are texts in the main font's cells.
local function field_contained(what)
  local ui = love.state.user_input
  local sl = ui.V.statusline
  local font, w = sl.cfg.font, P.cc().cfg.view.w
  local gfx = love.graphics
  local texts, print_ = { }, gfx.print
  local canvas = gfx.newCanvas(w, 64)
  gfx.push('all')
  gfx.setCanvas(canvas)
  gfx.print = function(t, x)
    t = tostring(t)
    if t:match('%S') then
      texts[#texts + 1] = { t = t, from = x, to = x + font:getWidth(t) }
    end
  end
  local ok, e = pcall(sl.draw, sl, ui.M:get_status(), 0)
  gfx.print = print_
  gfx.setCanvas()
  gfx.pop()
  assert(ok, e)
  table.sort(texts, function(a, b) return a.from < b.from end)
  local whole = { }
  for i, t in ipairs(texts) do
    assert(t.from >= 0 and t.to <= w, what .. ': ' .. t.t
      .. ' ends at ' .. t.to .. ' of ' .. w)
    if i > 1 then
      assert(texts[i - 1].to <= t.from, what .. ': ' .. texts[i - 1].t
        .. ' runs into ' .. t.t)
    end
    whole[t.t] = true
  end
  assert(whole['1:1'], what .. ': the cursor\'s place')
end

--- the IDE's own line: the project, the entry file and the
--- word; the console's own names no file (the maintainer's
--- ruling of November 18, 2026)
--- the mode's labels, which no line under a key card shows
local NO_LABEL = { 'text>F12', 'comb>F12' }

--- the screen's last pixel row takes `want` (under a status line
--- on the last row, the line's ground; under a field, the
--- field's; the maintainer's ruling of November 19, 2026)
local function bottom_row(img, want, what)
  local v = P.cc().cfg.view
  local bg = (P.colors(img, 0, v.h - 1, v.w, 1))
  assert(P.near(bg, want), what .. ': last pixel row in '
    .. P.show(bg) .. ', expected ' .. P.show(want))
end

local function ide_line(word)
  if word == 'console' then return { PROJECT, word, 'text>F12' } end
  return { PROJECT, 'main.lua', word, 'text>F12' }
end

scenario('modes', function(wait)
  wait(.1)
  D.key(wait, 'C-l')
  D.enter(wait, string.format('project(%q)', PROJECT))
  D.key(wait, 'C-l')
  bar(wait, 'console-idle', 'console', ide_line('console'),
    { 'running', 'paused', 'main.lua' })
  local idle = P.capture(wait)
  word_yellow(idle, 'console', 'console')
  bottom_row(idle, P.cc().cfg.view.colors.input.console.bg,
    'console-idle')
  without_card(wait, 'console', function()
    bar(wait, 'console-idle-no-card', 'console',
      { '[no sd]', PROJECT, 'console' }, { 'main.lua' })
  end)
  --- the line under a card names no mode: the card holds F12
  --- back (review r1)
  D.with_card(wait, function()
    bar(wait, 'console-card', 'console',
      { 'Keys now, console:', PROJECT }, NO_LABEL)
  end)
  bar(wait, 'console-card-released', 'console', ide_line('console'))
  --- scrolled back, the line says how far: `L-N` (the
  --- maintainer's ruling of November 18, 2026); at rest nothing
  D.enter(wait, "for i = 1, 40 do print('row ' .. i) end")
  wait(1)
  for _ = 1, 5 do D.key(wait, 'C-up') end
  local back = P.cc().model.output:scrolled_back()
  assert(back and back > 0, 'the output scrolled back')
  bar(wait, 'console-scrolled', 'console',
    { PROJECT, 'console', 'L-' .. back, '1:1' })
  D.key(wait, 'end')
  assert(not P.cc().model.output:is_scrolled(), 'back at rest')
  D.key(wait, 'C-l')

  P.put(PROJECT, 'notes.lua', 'a = 1\nb = 2\n')
  D.enter(wait, 'edit("notes.lua")')
  D.in_state('editor')
  bar(wait, 'editor-browsing', 'editor', { 'notes.lua', 'browsing' })
  without_card(wait, 'editor', function()
    --- the mark is never cut; with the right block packed to
    --- the edge, the names are whole
    bar(wait, 'editor-browsing-no-card', 'editor',
      { '[no sd]', PROJECT, 'notes.lua', 'browsing', 'L3/2' },
      { ':1' })
  end)
  D.with_card(wait, function()
    bar(wait, 'editor-card', 'editor', { 'Keys now, browsing:' })
  end)
  D.type(wait, 'c = 3')
  bar(wait, 'editor-inserting', 'editor',
    { 'inserting', 'L3/2', ':6' })
  D.key(wait, 'escape')
  D.key(wait, 'C-up')
  D.key(wait, 'f2')
  bar(wait, 'editor-replacing', 'editor',
    { 'replacing', 'L2/2', ':6' })
  D.leave(wait)
  P.put(PROJECT, 'broken.lua', 'x = = 1\n')
  D.enter(wait, 'edit("broken.lua")')
  D.in_state('editor')
  bar(wait, 'editor-broken', 'editor',
    { 'broken.lua', '[broken]', 'browsing', 'L2/1' })
  D.leave(wait)
  --- the arrow toward the edit's target while no row of it is in
  --- view (the maintainer's ruling of November 18, 2026)
  local long = { }
  for i = 1, 60 do long[i] = 'line ' .. i end
  P.put(PROJECT, 'long.txt', table.concat(long, '\n') .. '\n')
  D.enter(wait, 'edit("long.txt")')
  D.in_state('editor')
  for _ = 1, 30 do D.key(wait, 'C-up') end
  D.key(wait, 'f2')
  D.eq(P.state(), 'replacing', 'replacing')
  D.key(wait, 'C-pageup')
  bar(wait, 'editor-replacing-target-below', 'editor',
    { 'replacing↓' })
  D.key(wait, 'C-pagedown')
  bar(wait, 'editor-replacing-target-above', 'editor',
    { 'replacing↑' })
  D.key(wait, 'C-g')
  bar(wait, 'editor-replacing-target-in-view', 'editor',
    { 'replacing' }, { 'replacing↑', 'replacing↓' })
  D.leave(wait)
  D.key(wait, 'C-l')

  --- a live program that can act: the console's dark gray,
  --- with an update or without, the bare line saying "running"
  --- in yellow after the project and the file
  local RUNNING = ide_line('running')
  local NOT_CONSOLE = { 'console', 'paused', ':1' }
  runs(wait, 'function love.update() end\n')
  D.in_state('running')
  bar(wait, 'running-update', 'console', RUNNING, NOT_CONSOLE)
  local running = P.capture(wait)
  word_yellow(running, 'running', 'console')
  bottom_row(running, theme().console.bg, 'running-update')
  stop(wait)
  runs(wait, 'function love.keypressed(k) end\n')
  D.in_state('ready')
  bar(wait, 'running-keys-alone', 'console', RUNNING, NOT_CONSOLE)
  word_yellow(P.capture(wait), 'running', 'console')
  stop(wait)
  --- a program's own field draws its own status line over the
  --- console's: its prompt and the cursor's place alone (a kept
  --- render, as below: the words are the unit tests')
  runs(wait, "compy.input.show { prompt = 'Your name?' }\n")
  bar(wait, 'running-own-field', 'console', { }, { 'paused' })
  stop(wait)
  --- a question as long as a child's, and one longer than the
  --- line: cut to fit, the cursor's place whole (review e2). The
  --- field's line is a render it keeps, which P.drawn does not
  --- record: the fit is the unit tests' (console_scrollback_spec,
  --- "the status line's mode"), and the shots show it
  runs(wait, 'compy.ask("Which country would you like to visit '
    .. 'next?", function() end)\n')
  bar(wait, 'running-ask', 'console', { }, { 'paused' })
  stop(wait)
  runs(wait, string.format('compy.ask(%q, function() end)\n',
    string.rep('A long question. ', 8)))
  bar(wait, 'running-ask-long', 'console', { }, { 'paused' })
  field_contained('a long question')
  stop(wait)
  --- a line break: the prompt on its one row (review e3)
  runs(wait, 'compy.ask("Your name?\\nSECOND LINE", function() end)\n')
  bar(wait, 'running-ask-line-break', 'console', { }, { 'paused' })
  field_contained('a line break')
  stop(wait)

  runs(wait, 'function love.update() end\n')
  D.key(wait, 'C-pause')
  wait(.3)
  D.in_state('inspect')
  bar(wait, 'paused', 'inspect', ide_line('paused'),
    { 'running', 'console' })
  word_yellow(P.capture(wait), 'paused', 'inspect')
  D.with_card(wait, function()
    bar(wait, 'paused-card', 'inspect', { 'paused' }, NO_LABEL,
      'console')
  end)
  bar(wait, 'paused-card-released', 'inspect', ide_line('paused'))
  stop(wait)

  runs(wait, "print('done')\n")
  D.in_state('ready')
  bar(wait, 'finished', 'console', ide_line('console'),
    { 'running', 'paused', 'main.lua' })
  D.key(wait, 'C-l')
  hm_done()
end)
