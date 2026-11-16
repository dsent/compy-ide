local P = require('harmony.probe')
local D = require('harmony.drive')

--- A run that ends for good leaves no graphics state behind:
--- after a program that set a scissor, wireframe and a colour
--- is stopped with Ctrl+Q, the console's key card is drawn as
--- before the run, whole and in its own colours (the device
--- night of November 16, 2026: the card was clipped to the
--- program's scissor, with a red wireframe outline).

local PROJECT = 'h-reset'
local DIRTY = 'gfx.setScissor(0, 0, 300, 300)\n'
    .. 'gfx.setWireframe(true)\n'
    .. 'gfx.setColor(1, 0, 0, 1)\n'
    .. 'function love.update() end\n'

--- the card's picture, read from the screen
local function card(wait)
  local img
  D.with_card(wait, function()
    assert(P.card(), 'the card shows')
    img = P.capture(wait)
  end)
  return img
end

--- the colour most pixels of a block have, in `img`
local function ground(img, x, y)
  return (P.colors(img, x, y, 120, 60))
end

scenario('card-after-stop', function(wait)
  wait(.1)
  D.enter(wait, string.format('project(%q)', PROJECT))
  P.put(PROJECT, 'main.lua', DIRTY)
  D.key(wait, 'escape')
  local clean = card(wait)
  D.shot(wait, 'card-before')
  D.enter(wait, 'run()')
  wait(.3)
  D.in_state('running')
  D.key(wait, 'C-q')
  wait(.2)
  D.in_state('ready')
  local after = card(wait)
  D.shot(wait, 'card-after')
  -- outside the program's 300 px scissor, and inside it
  for _, at in ipairs({ { 600, 120 }, { 800, 400 }, { 40, 40 } }) do
    local want, got = ground(clean, at[1], at[2]),
        ground(after, at[1], at[2])
    assert(P.near(got, want), string.format(
      'the card at %d,%d: %s, before the run %s', at[1], at[2],
      P.show(got), P.show(want)))
  end
  hm_done()
end)
