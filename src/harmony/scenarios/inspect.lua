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

    -- a run asked for while one is paused is refused with a
    -- notice above the status line, until the next key
    wait(.4)
    h.love_text('run()')
    wait(.1)
    h.love_key('return')
    wait(.4)
    h.screenshot('run-refused')
    wait(.1)
    local said = P.console_message() or ''
    assert(said:find('already running', 1, true),
      'no notice for the refused run: ' .. said)
    assert(P.cc().input:message_kind() == 'notice',
      'the refused run is not a notice')
    h.love_key('backspace')
    wait(.1)
    assert(P.console_message() == nil,
      'the next key leaves the notice')

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
