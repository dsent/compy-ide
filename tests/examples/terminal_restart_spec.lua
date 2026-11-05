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

describe('terminal Ctrl+C and Ctrl+D #microbit', function()
  local function connected(sent)
    return {
      send = function(bytes)
        sent[#sent + 1] = bytes
        return true
      end,
      isConnected = function() return true end,
    }
  end

  it('sends Ctrl+C as one byte and drops the line typed',
    function()
      local sent = {}
      local input = load_terminal(connected(sent))
      local cleared = 0
      input.clear = function() cleared = cleared + 1 end
      assert.is_true(input.shortcuts.keypressed['ctrl+c']())
      assert.same({ '\3' }, sent)
      assert.same(1, cleared)
      assert.is_true(input.shortcuts.textinput['ctrl+c']())
    end)

  it('sends Ctrl+D as one byte and keeps the line typed',
    function()
      local sent = {}
      local input = load_terminal(connected(sent))
      input.clear = function() error('Ctrl+D cleared the line') end
      assert.is_true(input.shortcuts.keypressed['ctrl+d']())
      assert.same({ '\4' }, sent)
      assert.is_true(input.shortcuts.textinput['ctrl+d']())
    end)

  it('says so when the byte cannot be sent', function()
    local serial = {
      send = function() return false, 'no board' end,
      isConnected = function() return false end,
    }
    local input, said = load_terminal(serial)
    input.shortcuts.keypressed['ctrl+c']()
    assert.same('[send failed: no board]', said[#said])
  end)
end)
