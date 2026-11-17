local h = love.harmony.utils or error()
local P = require('harmony.probe')
local D = require('harmony.drive')

local PROJECT = 'h-stopped'

--- draws its own screen and pauses itself
local PAUSES = [[
local start, paused = love.timer.getTime(), false

function love.update()
  if love.timer.getTime() - start > 0.3 and not paused then
    paused = true
    pause('look here')
  end
end

function love.draw()
  love.graphics.clear(0.1, 0.3, 0.5)
  love.graphics.setColor(1, 0.8, 0.2)
  love.graphics.rectangle('fill', 100, 100, 300, 200)
end
]]

local function inspect()
  scenario('turtle', function(wait)
    wait(.1)
    h.love_text('run("turtle")')
    wait(.1)
    h.love_key('return')

    h.screenshot('running')
    wait(.3)
    h.love_key('C-pause')
    wait(.1)
    h.release_keys()
    wait(.1)
    h.screenshot('paused')

    wait(.1)
    h.love_key('space')
    wait(.1)
    h.screenshot('console')
    wait(.4)
    h.love_text('tx = 50')
    wait(.1)
    h.screenshot('console-with-text')
    wait(.1)
    h.love_key('return')
    wait(.4)
    h.love_text('ty = 100')
    wait(.1)
    h.love_key('return')
    wait(.1)
    h.screenshot('console-emptied')

    -- a run asked for while one is paused is refused in the
    -- output, in its refusal color, and the band stays empty
    -- (the maintainer's rulings of November 15, 2026)
    wait(.4)
    h.love_text('run()')
    wait(.1)
    h.love_key('return')
    wait(.6)
    h.screenshot('run-refused')
    wait(.1)
    local said = P.console_text()
    assert(said:find('already running', 1, true),
      'the refused run is not in the output: ' .. said)
    assert(P.console_message() == nil,
      'the refused run is in the band')
    local t = P.cc().model.output.terminal
    local want = P.cc().cfg.view.colors.terminal.refusal
    local found
    for y, r in ipairs(t.buffer) do
      if table.concat(r):find('already running', 1, true) then
        local c = t.state_buffer[y][1].color
        found = P.near(c, want)
      end
    end
    assert(found, 'the refused run is not in the refusal color')

    wait(.4)
    h.love_text('continue()')
    wait(.1)
    h.love_key('return')
    wait(.1)
    h.screenshot('modified')

    wait(1)
    h.love_key('C-q')
    wait(.1)
    hm_done()
  end)

  --- A paused program's console is drawn over the program's
  --- picture: faint, with no ground of its own. Once Ctrl+Q
  --- has stopped the program the output stands on its own
  --- ground again, in its own colors, at once: nothing has to
  --- be written first.
  scenario('stopped', function(wait)
    wait(.1)
    h.release_keys()
    D.key(wait, 'escape')
    D.enter(wait, string.format('project(%q)', PROJECT))
    P.put(PROJECT, 'main.lua', PAUSES)
    D.enter(wait, 'run_project()')
    for _ = 1, 50 do
      if love.state.app_state == 'inspect' then break end
      wait(.1)
    end
    D.in_state('inspect')
    wait(.2)
    D.key(wait, 'C-q')
    D.in_state('ready')
    local img = P.capture(wait)
    D.shot(wait, 'stopped')
    local cc = P.cc()
    local theme = cc.cfg.view.colors.terminal
    local top = require('view.layout')(cc.cfg.view).top
    local t = cc.model.output.terminal
    local ground = P.cell(img, t.width - 2, t.height - 2, top)
    assert(P.near(ground, theme.bg), 'the output\'s ground after'
      .. ' Ctrl+Q is ' .. P.show(ground) .. ', the theme makes '
      .. P.show(theme.bg))
    --- a row that holds text, and its first character's color
    local row
    for y, chars in ipairs(t.buffer) do
      if chars[1] ~= ' ' then row = y end
    end
    assert(row, 'the output holds no text to read a color from')
    local _, ink = P.cell(img, 1, row, top)
    local want = t.state_buffer[row][1].color
    assert(P.near(ink, want), 'the output\'s text after Ctrl+Q is '
      .. P.show(ink) .. ', written in ' .. P.show(want))
    hm_done()
  end)
end

inspect()
