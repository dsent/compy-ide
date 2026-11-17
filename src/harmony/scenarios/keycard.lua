local P = require('harmony.probe')
local D = require('harmony.drive')

--- The key card (IS3.16, the key card rulings): while F1 is
--- held it shows the keys of the editor's state, or of the
--- console, and every other key does nothing; it goes when F1
--- is let go. A running program shows none; a paused one
--- shows the console's.

local PROJECT = 'h-card'
--- a program that owns the screen: one that draws nothing
--- leaves the console showing, and the keys it does not take
--- go to the console, F1 included
local DRAWS = [[
function love.draw()
  love.graphics.setColor(1, 0.5, 0)
  love.graphics.rectangle('fill', 100, 100, 300, 200)
end
]]

--- hold F1, check the card names `heading`, press `keys`,
--- check that `same` still holds, and let F1 go
--- @param wait function
--- @param tag string
--- @param heading string
--- @param keys string[]
--- @param same function --- the check that nothing changed
local function card(wait, tag, heading, keys, same)
  D.with_card(wait, function()
    assert(P.card(), 'F1 held shows no card: ' .. tag)
    local drawn = P.drawn(wait)
    assert(P.shows(drawn, heading),
      'the card does not say ' .. heading)
    D.shot(wait, tag)
    for _, k in ipairs(keys) do
      if #k == 1 then D.type(wait, k) else D.key(wait, k) end
    end
    same()
  end)
  assert(not P.card(), 'the card stays after F1: ' .. tag)
  local drawn = P.drawn(wait)
  assert(not P.shows(drawn, heading),
    'the card is drawn after F1: ' .. tag)
end

scenario('editor', function(wait)
  local f = 'card.lua'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = 'a = 1\nb = 2\n' })
  local function browsing()
    D.in_state('editor')
    D.eq(P.state(), 'browsing', 'browsing under the card')
    D.eq(P.position(), 'end', 'the position under the card')
  end
  card(wait, 'browsing', 'Keys now, browsing:',
    { 'escape', 'C-q', 'up', 'return', 'q' }, browsing)
  browsing()
  D.eq(P.stored(PROJECT, f), 'a = 1\nb = 2\n', 'nothing was written')

  D.type(wait, 'z')
  card(wait, 'inserting', 'Keys now, inserting:',
    { 'escape', 'return', 'backspace' }, function()
      D.eq(P.draft(), 'z', 'the draft under the card')
    end)
  D.key(wait, 'escape')

  D.key(wait, 'up')
  D.key(wait, 'f2')
  card(wait, 'replacing', 'Keys now, replacing:',
    { 'escape', 'C-delete' }, function()
      D.eq(P.state(), 'replacing', 'replacing under the card')
      D.eq(P.draft(), 'b = 2', 'the draft under the card')
    end)
  -- with F1 let go the keys act again
  D.key(wait, 'escape')
  D.eq(P.state(), 'browsing', 'Escape acts once F1 is let go')
  D.leave(wait)
  hm_done()
end)

scenario('console', function(wait)
  wait(.1)
  D.type(wait, 'print("held")')
  card(wait, 'console', 'Keys now, console:',
    { 'return', 'escape' }, function()
      D.in_state('ready')
      D.eq(P.console_draft(), 'print("held")',
        'the console line under the card')
    end)
  D.key(wait, 'escape')
  D.eq(P.console_draft(), '', 'Escape clears the line')
  hm_done()
end)

scenario('program', function(wait)
  wait(.1)
  D.enter(wait, string.format('project(%q)', PROJECT))
  P.put(PROJECT, 'main.lua', DRAWS)
  D.enter(wait, 'run_project()')
  D.in_state('running')
  D.with_card(wait, function()
    assert(not P.card(), 'a card over a running program')
    assert(not P.shows(P.drawn(wait), 'Keys now'),
      'a card is drawn over a running program')
    D.shot(wait, 'running')
  end)
  -- paused, the console shows its card
  D.key(wait, 'C-pause')
  D.in_state('inspect')
  card(wait, 'paused', 'Keys now, console:', {}, function()
    D.in_state('inspect')
  end)
  D.key(wait, 'C-q')
  D.in_state('ready')
  hm_done()
end)
