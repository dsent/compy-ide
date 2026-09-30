--- The terminal example's Ctrl+R on a Compy from before files
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

describe('terminal Ctrl+R #microbit', function()
  it('restarts the board on an older Compy', function()
    local resets = 0
    local serial = {
      send = function() return true end,
      reset = function() resets = resets + 1 return true end,
      isConnected = function() return true end,
    }
    local input, said = load_terminal(serial)
    assert.has_no_error(function()
      input.shortcuts.keypressed['ctrl+r']()
    end)
    assert.same(1, resets)
    assert.truthy(said[#said]:find('restarting the micro:bit', 1,
      true))
    -- a restart only starts a program from upload again
    assert.truthy(said[#said]:find('upload() in the microbit'
      .. ' project puts the Compy\'s firmware back', 1, true))
  end)

  it('waits while a file goes to the board', function()
    local serial = {
      send = function() return true end,
      reset = function() error('reset while flashing') end,
      isConnected = function() return true end,
      isFlashing = function() return true end,
    }
    local input, said = load_terminal(serial)
    input.shortcuts.keypressed['ctrl+r']()
    assert.truthy(said[#said]:find('on its way to the micro:bit',
      1, true))
  end)
end)
