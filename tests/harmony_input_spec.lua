local mock = require('tests.mock')

local function event_name(name)
  return string.sub(name, string.len('sazed_') + 1)
end

local function stub_view()
  package.loaded['view.view'] = nil
  package.preload['view.view'] = function()
    View = {
      clear_snapshot = function() end,
      draw = function() end,
      drawFPS = function() end,
    }
  end
end

local function mock_state()
  mock.mock_love({
    event = { },
    handlers = { },
    state = { app_state = 'running' },
    window = {
      getTitle = function() return 'test' end,
      setTitle = function() end,
    },
  })
end

--- Real LOVE semantics: push only enqueues; drain()
--- later calls the handlers, mirroring main_loop's poll
--- step, which runs a frame before love.update.
local function queue_recorder()
  local events, queue = { }, { }
  love.event.push = function(name, key)
    local n = event_name(name)
    events[#events + 1] = n .. ':' .. key
    queue[#queue + 1] = { n, key }
  end
  local function drain()
    for _, e in ipairs(queue) do
      love.handlers[e[1]](e[2])
    end
    queue = { }
  end
  return events, drain
end

local function setup_harmony()
  package.loaded['harmony.init'] = nil
  _G.Harmony = nil
  mock_state()
  local events, drain = queue_recorder()
  stub_view()
  require('util.key')
  require('controller.controller')
  local harmony = require('harmony.init')
  harmony(true)
  harmony.load()
  return harmony, events, drain
end

local function gateway()
  local calls = { }
  local cc = {
    cfg = { mode = 'dev' },
    edit = function() calls.edit = true end,
    stop_project_run = function() calls.stop = true end,
    card_shows = function() return false end,
    key_released = function() end,
  }
  Controller.setup_callback_handlers(cc)
  return calls
end

describe('harmony input', function()
  it('queues on push, drains before the app sees it', function()
    local harmony, _, drain = setup_harmony()
    local calls = gateway()

    harmony.utils.love_key('C-t')
    assert.same({ }, calls)

    drain()
    assert.same({ edit = true, stop = true }, calls)
  end)

  it('puts only the trigger key on the event stream', function()
    local harmony, events, drain = setup_harmony()
    gateway()

    harmony.utils.love_key('C-t')
    drain()

    assert.same({
      'keypressed:t',
      'keyreleased:t',
    }, events)
  end)

  it('keeps the modifier held until release_keys', function()
    local harmony, _, drain = setup_harmony()
    gateway()

    harmony.utils.love_key('C-t')
    drain()
    assert.is_true(Key.ctrl())

    harmony.utils.release_keys()
    local ctrl = Key.ctrl()
    assert.is_falsy(ctrl)
  end)

  it('answers false, not nothing, for an unheld modifier', function()
    local harmony = setup_harmony()

    local isDown = love.keyboard.isDown('lctrl')
    assert.is_boolean(isDown)
    assert.is_false(isDown)
  end)
end)
