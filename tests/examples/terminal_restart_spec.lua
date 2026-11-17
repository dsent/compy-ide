--- The terminal example's Ctrl+M on a Compy from before files
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

describe('terminal Ctrl+M #microbit', function()
  it('restarts the board on an older Compy', function()
    local resets = 0
    local serial = {
      send = function() return true end,
      reset = function() resets = resets + 1 return true end,
      isConnected = function() return true end,
    }
    local input, said = load_terminal(serial)
    assert.has_no_error(function()
      input.shortcuts.keypressed['ctrl+m']()
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
    input.shortcuts.keypressed['ctrl+m']()
    assert.truthy(said[#said]:find('on its way to the micro:bit',
      1, true))
  end)
end)

-- Through the IDE's own route: Ctrl+M is no key of the IDE's
-- (not reserved, not in the field's table), so it reaches the
-- program's shortcut ahead of the input field, and its letter,
-- which the device also sends as text before or after the
-- press, does not reach the line that goes to the board. Alt+R,
-- the restart of the day before, does nothing.
describe('terminal Ctrl+M through the IDE #microbit', function()
  local F = require('tests.helpers.input_fixture')
  setup(F.setup)
  teardown(F.teardown)
  before_each(F.reset)

  --- the terminal on the project route, over a board that
  --- counts its resets and keeps what it is sent
  local function terminal()
    local board = { resets = 0, sent = { } }
    local serial = {
      send = function(s)
        board.sent[#board.sent + 1] = s
        return true
      end,
      reset = function()
        board.resets = board.resets + 1
        return true
      end,
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
    return board
  end

  --- `mod` with `key`, its letter sent as text `order` the press
  local function chord(mod, key, order)
    F.session.press(mod)
    if order == 'before' then F.session.type(key) end
    F.session.press(key)
    if order == 'after' then F.session.type(key) end
    F.session.release(key)
    F.session.release(mod)
  end

  --- type "x" and Enter: what reaches the board
  local function send_x(board)
    F.session.type('x')
    F.session.press('return')
    F.session.release('return')
    return board.sent
  end

  for _, order in ipairs({ 'before', 'after' }) do
    it('Ctrl+M restarts the board, its m typed nowhere, the '
        .. 'text ' .. order .. ' the key press', function()
      local board = terminal()
      chord('lctrl', 'm', order)
      assert.same(1, board.resets)
      assert.same({ 'x\r' }, send_x(board))
    end)

    it('Alt+R restarts nothing and types nothing, the text '
        .. order .. ' the key press', function()
      local board = terminal()
      chord('lalt', 'r', order)
      assert.same(0, board.resets)
      assert.same({ 'x\r' }, send_x(board))
    end)
  end
end)
