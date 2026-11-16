local P = require('harmony.probe')
local D = require('harmony.drive')

--- The IDE draws its own things in its own graphics state: a
--- program that set a scissor, wireframe and a colour leaves
--- the console's key card, its output and its status line as
--- they were before the run, whether the program was stopped
--- with Ctrl+Q, paused, stopped itself from love.draw or runs
--- on (the device nights of November 16, 2026: the card was
--- clipped to the program's scissor, with a red wireframe
--- outline, after a stop and during a pause).

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

--- the blocks of `after` match those of `before`
local function same(before, after, what, at)
  for _, p in ipairs(at or { { 600, 120 }, { 800, 400 }, { 40, 40 } }) do
    local want, got = ground(before, p[1], p[2]),
        ground(after, p[1], p[2])
    assert(P.near(got, want), string.format(
      '%s at %d,%d: %s, before the run %s', what, p[1], p[2],
      P.show(got), P.show(want)))
  end
end

--- a project holding `text` as its main.lua, open, the field
--- empty, and the card's picture before any run
local function project(wait, name, text)
  D.enter(wait, string.format('project(%q)', name))
  P.put(name, 'main.lua', text)
  D.key(wait, 'escape')
  D.key(wait, 'C-l')
  wait(.2)
  return card(wait)
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
  same(clean, after, 'the card')
  hm_done()
end)

scenario('card-while-paused', function(wait)
  wait(.1)
  local clean = project(wait, 'h-reset-p', DIRTY)
  D.enter(wait, 'run()')
  wait(.3)
  D.key(wait, 'C-pause')
  wait(.3)
  D.in_state('inspect')
  local paused = card(wait)
  D.shot(wait, 'card-paused')
  same(clean, paused, 'the card during a pause')
  -- the program's state is its own: continue() resumes it
  D.enter(wait, 'continue()')
  wait(.2)
  D.in_state('running')
  D.key(wait, 'C-q')
  wait(.2)
  hm_done()
end)

scenario('card-after-stop-from-draw', function(wait)
  wait(.1)
  local clean = project(wait, 'h-reset-d', DIRTY
    .. 'function love.draw() stop() end\n')
  D.enter(wait, 'run()')
  wait(.4)
  D.in_state('ready')
  local after = card(wait)
  D.shot(wait, 'card-stop-from-draw')
  same(clean, after, 'the card after a stop from love.draw')
  hm_done()
end)

--- a program with no draw of its own runs over the console:
--- the output and the status line are the IDE's, unclipped
scenario('console-while-running', function(wait)
  wait(.1)
  D.enter(wait, string.format('project(%q)', 'h-reset-r'))
  P.put('h-reset-r', 'main.lua', DIRTY)
  D.key(wait, 'escape')
  D.key(wait, 'C-l')
  wait(.2)
  local before = P.capture(wait)
  D.enter(wait, 'run()')
  wait(.4)
  D.in_state('running')
  D.key(wait, 'C-l')
  wait(.2)
  local running = P.capture(wait)
  D.shot(wait, 'console-running')
  local v = P.cc().cfg.view
  local l = require('view.layout')(v)
  local status = v.h - l.bottom - v.fh - l.status_h
  same(before, running, 'the console while a program runs',
    { { 600, 120 }, { 800, 300 }, { 40, 40 } })
  -- the status line takes the running theme's ground, whole
  local bg = (P.colors(running, 600, status, 120, l.status_h))
  assert(P.near(bg, v.colors.statusline.user.bg), string.format(
    'the status line while a program runs: %s, the theme has %s',
    P.show(bg), P.show(v.colors.statusline.user.bg)))
  D.key(wait, 'C-q')
  wait(.2)
  hm_done()
end)
