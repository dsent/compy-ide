local P = require('harmony.probe')
local D = require('harmony.drive')

--- The screen shows the console's text and a program's picture
--- in one of three modes (model/screenModel.lua): text,
--- combined (the text over the picture) and the full picture.
--- A run that draws shows its picture whole; a stop shows the
--- console, the picture kept; a typed line that draws shows
--- the text over the picture; a pause shows the console;
--- reset() clears the picture. Each mode is read from the
--- screen's pixels, and the combined mode's two looks are shot
--- for the maintainer to choose (decision 5 of November 17,
--- 2026).

local YELLOW = { 1, .8, .2 }

--- a program that draws once and ends: its natural end is a stop
local DRAWS = [[
love.graphics.setColor(1, .8, .2)
love.graphics.rectangle('fill', 300, 150, 300, 200)
]]

--- the same, live behind the console until it is stopped
local DRAWS_LIVE = DRAWS .. 'function love.update() end\n'

--- a program that draws its own screen and pauses itself
local PAUSES = [[
local start, paused = love.timer.getTime(), false

function love.update()
  if love.timer.getTime() - start > 0.3 and not paused then
    paused = true
    pause('look here')
  end
end

function love.draw()
  love.graphics.setColor(1, .8, .2)
  love.graphics.rectangle('fill', 300, 150, 300, 200)
end
]]

--- the screen's mode
local function mode()
  return P.cc().model.screen:get()
end

--- the colour most pixels of the picture's rectangle have
local function at_picture(img)
  return (P.colors(img, 400, 200, 100, 100))
end

--- a project holding `text` as its main.lua, open, the output
--- emptied, and the screen as it shows then
local function project(wait, name, text)
  D.enter(wait, string.format('project(%q)', name))
  P.put(name, 'main.lua', text)
  D.key(wait, 'escape')
  D.key(wait, 'C-l')
  wait(.2)
  return P.capture(wait)
end

scenario('picture-then-console', function(wait)
  wait(.1)
  local before = project(wait, 'h-screen-a', DRAWS_LIVE)
  local ground = at_picture(before)
  D.enter(wait, 'run()')
  wait(.3)
  assert(mode() == 'picture', 'a run that drew shows its '
    .. 'picture, the mode is ' .. mode())
  local shown = P.capture(wait)
  D.shot(wait, 'picture')
  assert(P.near(at_picture(shown), YELLOW), 'the picture whole: '
    .. P.show(at_picture(shown)))
  D.key(wait, 'C-q')
  wait(.2)
  assert(mode() == 'text', 'a stop shows the console, the mode '
    .. 'is ' .. mode())
  assert(P.cc().model.output:is_drawn(), 'the picture is kept')
  local console = P.capture(wait)
  D.shot(wait, 'text-after-stop')
  assert(P.near(at_picture(console), ground), 'the console on its '
    .. 'ground: ' .. P.show(at_picture(console)) .. ', before the '
    .. 'run ' .. P.show(ground))
  hm_done()
end)

--- F12 steps through the modes over a kept picture, the status
--- line naming each but the picture's, and any key goes back
--- from the full picture to the text, typing nothing
scenario('f12-and-any-key', function(wait)
  wait(.1)
  project(wait, 'h-screen-e', DRAWS)
  D.enter(wait, 'run()')
  wait(.3)
  D.eq(mode(), 'picture', 'a run that drew shows its picture')
  D.key(wait, 'a')
  D.eq(mode(), 'text', 'a key goes back to the text')
  D.eq(P.console_draft(), '', 'the key typed nothing')
  D.eq(P.cc().input:get_status().mode, 'text',
    'the status line names the text')
  assert(P.shows(P.drawn(wait), 'text>F12'),
    'the status line prints text>F12')
  D.shot(wait, 'text-status')
  D.key(wait, 'f12')
  D.eq(mode(), 'combined', 'F12, combined')
  D.eq(P.cc().input:get_status().mode, 'combined',
    'the status line names combined')
  assert(P.shows(P.drawn(wait), 'comb>F12'),
    'the status line prints comb>F12')
  D.shot(wait, 'combined-status')
  D.key(wait, 'f12')
  D.eq(mode(), 'picture', 'F12 again, the picture')
  local shown = P.capture(wait)
  assert(P.near(at_picture(shown), YELLOW), 'the kept picture '
    .. 'whole: ' .. P.show(at_picture(shown)))
  D.key(wait, 'b')
  D.eq(mode(), 'text', 'a key goes back to the text, past '
    .. 'combined')
  D.eq(P.console_draft(), '', 'the key typed nothing')
  hm_done()
end)

--- a program that drew and ended by itself is stopped, and leaves
--- its picture on show (decision 1 of November 17, 2026);
--- back() is what any key does once the key gate takes it
--- (stage 2)
scenario('natural-end-shows-picture', function(wait)
  wait(.1)
  local before = project(wait, 'h-screen-d', DRAWS)
  local ground = at_picture(before)
  D.enter(wait, 'run()')
  wait(.3)
  assert(not P.cc().run_live, 'the program ended by itself')
  assert(mode() == 'picture', 'its picture shows, the mode is '
    .. mode())
  local shown = P.capture(wait)
  D.shot(wait, 'picture-after-natural-end')
  assert(P.near(at_picture(shown), YELLOW), 'the picture whole: '
    .. P.show(at_picture(shown)))
  P.cc().model.screen:back()
  wait(.1)
  assert(mode() == 'text', 'back to the console, the mode is '
    .. mode())
  local console = P.capture(wait)
  assert(P.near(at_picture(console), ground), 'the console on its '
    .. 'ground: ' .. P.show(at_picture(console)))
  hm_done()
end)

--- the console's output over a picture in the combined mode, in
--- both looks: the picture dimmed under whole text, and
--- half-transparent text over the whole picture
local function both_looks(wait, tag)
  local theme = P.cc().cfg.view.colors.screen.combined
  local ground, text = theme.ground, theme.text
  D.shot(wait, 'combined-dimmed-' .. tag)
  theme.ground, theme.text = 0, .5
  wait(.1)
  D.shot(wait, 'combined-half-text-' .. tag)
  theme.ground, theme.text = ground, text
  wait(.1)
end

scenario('combined-from-a-typed-line', function(wait)
  wait(.1)
  local before = project(wait, 'h-screen-b', 'print("x")\n')
  local ground = at_picture(before)
  for i = 1, 8 do
    D.enter(wait, string.format(
      'print("line %d of the output, over the picture")', i))
  end
  D.enter(wait, "love.graphics.setColor(1, .8, .2)")
  assert(mode() == 'text', 'a line that draws nothing leaves the '
    .. 'text, the mode is ' .. mode())
  D.enter(wait,
    "love.graphics.rectangle('fill', 300, 150, 300, 200)")
  wait(.1)
  assert(mode() == 'combined', 'a typed line that drew shows the '
    .. 'text over the picture, the mode is ' .. mode())
  local img = P.capture(wait)
  local c = at_picture(img)
  assert(not P.near(c, ground) and not P.near(c, YELLOW),
    'the picture under the output\'s translucent ground: '
    .. P.show(c))
  both_looks(wait, 'plain')
  --- a busy picture: circles in many colours
  D.enter(wait, 'for i = 0, 60 do '
    .. 'love.graphics.setColor(i % 3 / 2, i % 5 / 4, i % 7 / 6) '
    .. 'love.graphics.circle("fill", (i * 97) % 1000, '
    .. '(i * 53) % 560, 70) end')
  wait(.1)
  both_looks(wait, 'busy')
  D.enter(wait, 'reset()')
  wait(.2)
  assert(mode() == 'text', 'reset() shows the console, the mode '
    .. 'is ' .. mode())
  assert(not P.cc().model.output:is_drawn(), 'reset() clears the '
    .. 'picture')
  hm_done()
end)

scenario('pause-shows-console', function(wait)
  wait(.1)
  local before = project(wait, 'h-screen-c', PAUSES)
  local ground = at_picture(before)
  D.enter(wait, 'run()')
  wait(.1)
  assert(mode() == 'picture', 'a program that draws shows its '
    .. 'picture, the mode is ' .. mode())
  wait(.5)
  D.in_state('inspect')
  assert(mode() == 'text', 'a pause shows the console, the mode '
    .. 'is ' .. mode())
  D.eq(P.console_message(), 'look here (F12 shows the picture)',
    'the pause\'s text, and how to see the picture')
  local paused = P.capture(wait)
  D.shot(wait, 'paused')
  assert(P.near(at_picture(paused), ground), 'the console on its '
    .. 'ground while paused: ' .. P.show(at_picture(paused)))
  D.key(wait, 'f12')
  D.key(wait, 'f12')
  D.eq(mode(), 'picture', 'F12 twice while paused: the paused '
    .. 'frame')
  local frozen = P.capture(wait)
  D.shot(wait, 'paused-picture')
  assert(P.near(at_picture(frozen), YELLOW), 'the paused frame: '
    .. P.show(at_picture(frozen)))
  D.key(wait, 'a')
  D.eq(mode(), 'text', 'a key goes back to the text')
  D.eq(P.console_draft(), '', 'the key typed nothing')
  D.enter(wait, 'continue()')
  wait(.1)
  assert(mode() == 'picture', 'continue() brings back the '
    .. 'picture, the mode is ' .. mode())
  D.key(wait, 'C-q')
  wait(.2)
  hm_done()
end)
