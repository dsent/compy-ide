--- exec in the micro:bit tools sends a file to the board a line
--- at a time, and puts back the handlers it set aside. Sent all
--- at once, the board dropped bytes and the rest stayed queued;
--- wrapped anew on every call, a second exec overflowed the
--- stack. The tools run here as the console runs them, over the
--- IDE's own Serial and the fake backend, and the board is
--- played by the test: it echoes each line and answers it with a
--- prompt.
--- LÖVE provides utf8; in tests it is the lua-utf8 rock
package.preload['utf8'] = package.preload['utf8']
    or function() return require('lua-utf8') end
require('model.serial.init')
require('model.serial.backend_fake')

local WRAP = 'assert(loadstring[['
local UNWRAP = ']])()'

describe('micro:bit exec #microbit', function()
  local serial, backend, port, said, echoes, files

  --- tools.lua loaded into an environment of its own, with what
  --- the console gives it
  local function load_tools()
    local env = setmetatable({
      compy = { serial = port, audio = {} },
      echo = function(on) echoes[#echoes + 1] = on ~= false end,
      readfile = function(name) return files[name] end,
      print = function(text) said[#said + 1] = text end,
      require = function(name)
        return require('examples.microbit.' .. name)
      end,
      utf8 = require('lua-utf8'),
    }, { __index = _G })
    local chunk = assert(loadfile('src/examples/microbit/tools.lua'))
    setfenv(chunk, env)()
    return env
  end

  --- The board takes the last line sent: its echo, what it has
  --- to say, and a prompt, ">> " unless given another
  --- @param answer string?
  --- @param prompt string?
  local function board(answer, prompt)
    local line = backend.sent[#backend.sent]:gsub('\r$', '')
    backend:rx(line .. '\r\r\n' .. (answer or '')
      .. (prompt or '>> '))
    serial:update(0)
  end

  --- @return integer
  local function sent()
    return #backend.sent
  end

  before_each(function()
    backend = FakeBackend.new()
    serial = Serial.new(backend)
    port = serial:table_for('program')
    said, echoes = {}, {}
    files = { ['f.lua'] = 'a = 1\nprint(a)\n' }
    backend:attach()
    serial:update(0)
  end)

  it('sends a line, and the next only after its prompt', function()
    local tools = load_tools()
    tools.exec('f.lua')
    assert.same({ WRAP .. '\r' }, backend.sent)
    serial:update(0)
    backend:rx('assert(loadstring[[\r\r\n')
    serial:update(0)
    assert.equal(1, sent())
    backend:rx('>> ')
    serial:update(0)
    assert.same('a = 1\r', backend.sent[2])
  end)

  it('shows the answer, hides the echo, puts the handlers back',
    function()
      local tools = load_tools()
      local mine = function() end
      local gone = function() end
      port.onBytes, port.onDisconnect = mine, gone
      said = {}
      tools.exec('f.lua')
      board()
      board()
      board()
      board('1\r\n', '> ')
      assert.same({ WRAP .. '\r', 'a = 1\r', 'print(a)\r',
        UNWRAP .. '\r' }, backend.sent)
      assert.same({ '1', 'f.lua is on the board and has run' },
        said)
      assert.equal(mine, port.onBytes)
      assert.equal(gone, port.onDisconnect)
      assert.is_nil(port.onTick)
      --- on when loaded, off while sending, on again after
      assert.same({ true, false, true }, echoes)
    end)

  it('runs a second time the same way', function()
    local tools = load_tools()
    for _ = 1, 2 do
      tools.exec('f.lua')
      for _ = 1, 3 do board() end
      board('1\r\n', '> ')
    end
    assert.equal(8, sent())
    assert.is_nil(port.onBytes)
  end)

  it('says how far it has got while the board is slow', function()
    local tools = load_tools()
    tools.exec('f.lua')
    board()
    said = {}
    serial:update(3.5)
    assert.same({ 'exec: line 1 of 2 of f.lua' }, said)
  end)

  it('stops when the board stops answering', function()
    local tools = load_tools()
    tools.exec('f.lua')
    board()
    said = {}
    for _ = 1, 6 do serial:update(1) end
    assert.equal(2, sent())
    assert.truthy(said[#said]:find('stopped answering', 1, true))
    assert.is_nil(port.onBytes)
    assert.is_nil(port.onTick)
  end)

  --- a program that loops never brings the prompt back
  it('hands a file that keeps running over to echo', function()
    local tools = load_tools()
    tools.exec('f.lua')
    for _ = 1, 3 do board() end
    backend:rx(UNWRAP .. '\r\r\n1\r\n')
    serial:update(0)
    for _ = 1, 4 do serial:update(1) end
    assert.is_not_nil(port.onBytes)
    serial:update(2)
    assert.same({ '1', 'f.lua is running on the board' },
      { said[#said - 1], said[#said] })
    assert.is_nil(port.onBytes)
    assert.same({ true, false, true }, echoes)
  end)

  it('stops before the end when the board runs the file early',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      board()
      board('Compile error: x\r\n', '> ')
      assert.equal(2, sent())
      assert.truthy(said[#said - 1]:find('Compile error', 1, true))
      assert.truthy(said[#said]:find('before its end', 1, true))
      assert.is_nil(port.onBytes)
    end)

  it('stops when the board is unplugged', function()
    local tools = load_tools()
    tools.exec('f.lua')
    board()
    backend:detach()
    serial:update(0)
    assert.truthy(said[#said]:find('unplugged', 1, true))
    assert.is_nil(port.onDisconnect)
  end)

  it('refuses while no board is connected', function()
    local tools = load_tools()
    backend:detach()
    serial:update(0)
    assert.has_error(function() tools.exec('f.lua') end)
    assert.equal(0, sent())
  end)
end)
