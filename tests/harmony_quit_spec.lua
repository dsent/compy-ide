--- Harmony's own love.run hands love.quit the quit event's
--- value and ends with the status its tag holds, as the IDE's
--- love.run does (util.application)
local mock = require('tests.mock')

local function setup_harmony()
  package.loaded['harmony.init'] = nil
  _G.Harmony = nil
  mock.mock_love({
    event = { },
    handlers = { },
    state = { app_state = 'running' },
    window = {
      getTitle = function() return 'test' end,
      setTitle = function() end,
    },
  })
  package.loaded['view.view'] = nil
  package.preload['view.view'] = function()
    View = {
      clear_snapshot = function() end,
      draw = function() end,
      drawFPS = function() end,
    }
  end
  require('util.key')
  require('controller.controller')
  local harmony = require('harmony.init')
  harmony(true)
  return harmony
end

describe('harmony run quits #harmony', function()
  local Application = require('util.application')

  --- the loop over these events, love.quit answering stay
  local function looped(events, stay)
    local given = {}
    love.load = nil
    love.timer = nil
    love.graphics = { isActive = function() return false end }
    love.arg = { parseGameArguments = function() end }
    love.event.pump = function() end
    love.event.poll = function()
      return function()
        local e = table.remove(events, 1)
        if e then return e[1], e[2] end
      end
    end
    love.quit = function(v)
      given[#given + 1] = v
      return stay
    end
    local loop = love.run()
    return loop(), given
  end

  it('ends with the status of a tagged quit', function()
    setup_harmony()
    local tag = Application.quit_tag('restart')
    local r, given = looped({ { 'quit', tag } })
    assert.same('restart', r)
    assert.same({ tag }, given)
  end)

  it('ends on its own quit event, untagged, with 0', function()
    local harmony = setup_harmony()
    local r = looped({ { harmony.pre .. 'quit' } })
    assert.same(0, r)
  end)
end)
