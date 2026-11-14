--- The terminal example's Alt+R on a Compy from before files
--- went down the cable: its serial table has send, reset and
--- isConnected only, and no isFlashing.

--- A table whose every missing field is a function doing
--- nothing that returns another such table, for the parts of
--- the IDE the terminal only calls at load
local function anything()
  return setmetatable({}, {
    __index = function(t, k)
      local v = function() return anything() end
      rawset(t, k, v)
      return v
    end,
  })
end

local function load_terminal(serial)
  local said = {}
  local input = anything()
  input.shortcuts = { keypressed = {}, textinput = {} }
  input.callbacks = {}
  local env = setmetatable({
    compy = { serial = serial, input = input },
    print = function(text) said[#said + 1] = text end,
    utf8 = require('lua-utf8'),
    love = anything(),
  }, { __index = _G })
  local chunk = assert(loadfile('src/examples/terminal/main.lua'))
  setfenv(chunk, env)()
  return input, said
end

describe('terminal Alt+R #microbit', function()
  it('restarts the board on an older Compy', function()
    local resets = 0
    local serial = {
      send = function() return true end,
      reset = function() resets = resets + 1 return true end,
      isConnected = function() return true end,
    }
    local input, said = load_terminal(serial)
    assert.has_no_error(function()
      input.shortcuts.keypressed['alt+r']()
    end)
    assert.same(1, resets)
    assert.truthy(said[#said]:find('restarting the micro:bit', 1,
      true))
    -- a restart only starts a program from upload again
    assert.truthy(said[#said]:find('upload() in the microbit'
      .. ' project puts the Compy\'s firmware back, or'
      .. ' upload("tpbot.lua") for a robot', 1, true))
  end)

  it('waits while a file goes to the board', function()
    local serial = {
      send = function() return true end,
      reset = function() error('reset while flashing') end,
      isConnected = function() return true end,
      isFlashing = function() return true end,
    }
    local input, said = load_terminal(serial)
    input.shortcuts.keypressed['alt+r']()
    assert.truthy(said[#said]:find('on its way to the micro:bit',
      1, true))
  end)
end)

-- Through the IDE's own route: Alt+R is no key of the IDE's,
-- so it reaches the program's shortcut, and its letter, which
-- the device also sends as text, does not reach the line that
-- goes to the board.
describe('terminal Alt+R through the IDE #microbit', function()
  local F = require('tests.helpers.input_fixture')
  setup(F.setup)
  teardown(F.teardown)
  before_each(F.reset)

  local ORDERS = { 'before', 'after' }

  for _, order in ipairs(ORDERS) do
    it('restarts the board, its r typed nowhere, the text '
        .. order .. ' the key press', function()
      local resets, sent = 0, { }
      local serial = {
        send = function(s) sent[#sent + 1] = s return true end,
        reset = function() resets = resets + 1 return true end,
        isConnected = function() return true end,
      }
      local input = F.activate_project()
      local env = setmetatable({
        compy = { serial = serial, input = input },
        print = function() end,
        io = { write = function() end },
        utf8 = require('lua-utf8'),
        love = setmetatable({ }, { __index = love }),
      }, { __index = _G })
      local chunk =
          assert(loadfile('src/examples/terminal/main.lua'))
      setfenv(chunk, env)()
      F.session.press('lalt')
      if order == 'before' then F.session.type('r') end
      F.session.press('r')
      if order == 'after' then F.session.type('r') end
      F.session.release('r')
      F.session.release('lalt')
      assert.same(1, resets)
      F.session.type('x')
      F.session.press('return')
      F.session.release('return')
      assert.same({ 'x\r' }, sent)
    end)
  end
end)
