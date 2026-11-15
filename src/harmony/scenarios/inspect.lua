local h = love.harmony.utils or error()
local P = require('harmony.probe')

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
end

inspect()
