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
local RAN = 'f.lua is on the board'

describe('micro:bit exec #microbit', function()
  local serial, backend, port, said, echoes, files, flashed
  local os_name = 'Android'

  --- tools.lua loaded into an environment of its own, with what
  --- the console gives it
  local function load_tools()
    local env = setmetatable({
      compy = { serial = port, audio = { hyperjump = function() end } },
      echo = function(on) echoes[#echoes + 1] = on ~= false end,
      readfile = function(name) return files[name] end,
      print = function(text) said[#said + 1] = text end,
      require = function(name)
        return require('examples.microbit.' .. name)
      end,
      utf8 = require('lua-utf8'),
      detect_microbit = function() return '/mb' end,
      flash_microbit = function() flashed = true return true end,
      love = { system = { getOS = function() return os_name end } },
    }, { __index = _G })
    local path = 'src/examples/microbit/tools.lua'
    setfenv(assert(loadfile(path)), env)()
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

  --- The file in, the board prompting after each line, and
  --- quiet after the last
  --- @param tools table
  local function run(tools)
    tools.exec('f.lua')
    for _ = 1, 3 do board() end
    board('1\r\n', '> ')
    serial:update(0.25)
  end

  --- @return integer
  local function sent()
    return #backend.sent
  end

  before_each(function()
    backend = FakeBackend.new()
    serial = Serial.new(backend)
    port = serial:table_for('program')
    said, echoes, flashed = {}, {}, false
    files = { ['f.lua'] = 'a = 1\nprint(a)\n' }
    backend:attach()
    serial:update(0)
  end)

  it('sends a line, and the next only after its prompt', function()
    local tools = load_tools()
    tools.exec('f.lua')
    assert.same({ WRAP .. '\r' }, backend.sent)
    serial:update(0)
    backend:rx(WRAP .. '\r\r\n')
    serial:update(0)
    assert.equal(1, sent())
    backend:rx('>> ')
    serial:update(0)
    assert.same('a = 1\r', backend.sent[2])
  end)

  it('shows the answer, hides the echo, puts the handlers back',
    function()
      local tools = load_tools()
      local mine, gone = function() end, function() end
      port.onBytes, port.onDisconnect = mine, gone
      said = {}
      run(tools)
      assert.same({ WRAP .. '\r', 'a = 1\r', 'print(a)\r',
        UNWRAP .. '\r' }, backend.sent)
      assert.same({ '1', RAN }, said)
      assert.equal(mine, port.onBytes)
      assert.equal(gone, port.onDisconnect)
      assert.is_nil(port.onTick)
      --- on when loaded, off while sending, on again after
      assert.same({ true, false, true }, echoes)
    end)

  it('runs a second time the same way', function()
    local tools = load_tools()
    run(tools)
    run(tools)
    assert.equal(8, sent())
    assert.is_nil(port.onBytes)
    assert.equal(RAN, said[#said])
  end)

  it('takes what came before the echo for none of its own',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      --- the greeting of a board just reset
      backend:rx('micro:bit\r\nLua 5.1 REPL\r\n> ')
      serial:update(0)
      assert.equal(1, sent())
      board()
      assert.equal(2, sent())
    end)

  it('waits for the board to be quiet after the last prompt',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      for _ = 1, 3 do board() end
      --- a line the program prints starts with "> ", and the
      --- chunk ends just after it
      board('x\r\n> ', '')
      serial:update(0.1)
      assert.is_not_nil(port.onBytes)
      backend:rx('y\r\n> ')
      serial:update(0)
      serial:update(0.25)
      assert.same({ 'x', '> y', RAN },
        { said[#said - 2], said[#said - 1], said[#said] })
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

  it('stops when the last line never reaches the board', function()
    local tools = load_tools()
    tools.exec('f.lua')
    for _ = 1, 3 do board() end
    for _ = 1, 6 do serial:update(1) end
    assert.truthy(said[#said]:find('stopped answering', 1, true))
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
    assert.same({ '1', 'f.lua is on the board and still running' },
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

  --- stop() fires compy.before_exit before it clears the handlers
  it('stops when stop() is typed, and runs the hook it held',
    function()
      local tools = load_tools()
      local hooked = false
      tools.compy.before_exit = function() hooked = true end
      tools.exec('f.lua')
      board()
      tools.compy.before_exit()
      assert.truthy(said[#said]:find('it was stopped', 1, true))
      assert.is_true(hooked)
      assert.is_nil(port.onBytes)
      assert.same({ true, false, true }, echoes)
      assert.has_no_error(function() tools.exec('f.lua') end)
    end)

  it('leaves a handler something else has taken over', function()
    local tools = load_tools()
    tools.exec('f.lua')
    board()
    local other = function() end
    port.onBytes = other
    for _ = 1, 6 do serial:update(1) end
    assert.equal(other, port.onBytes)
    assert.is_nil(port.onTick)
  end)

  it('starts again after a stop cleared its handlers', function()
    local tools = load_tools()
    tools.exec('f.lua')
    serial:programEnded()
    assert.has_no_error(function() tools.exec('f.lua') end)
    assert.equal(2, sent())
  end)

  it('holds upload back while it sends', function()
    local tools = load_tools()
    tools.exec('f.lua')
    files['MICROBIT.hex'] = ':00000001FF\n'
    assert.has_error(function() tools.upload() end)
    assert.is_false(flashed)
  end)

  it('upload says which firmware it put on the board', function()
    local tools = load_tools()
    local hex = require('examples.microbit.hex')
    files['v.hex'] = hex.write({ {
      addr = 0,
      data = 'microbit-lua firmware abc1234\0',
    } })
    tools.upload('v.hex')
    assert.is_true(flashed)
    assert.equal('v.hex holds firmware abc1234', said[#said])
  end)

  it('upload refuses a damaged hex before flashing, in plain'
    .. ' words', function()
      for _, bad in ipairs({ ':00000001FE\n',
        ':00000004FC\n:00000001FF\n' }) do
        local tools = load_tools()
        files['bad.hex'] = bad
        said = {}
        assert.has_no_error(function() tools.upload('bad.hex') end)
        assert.is_false(flashed)
        assert.truthy(table.concat(said, ' '):find('damaged', 1,
          true))
      end
    end)

  it('upload looks for no drive, and says plainly why a flash'
    .. ' did not start', function()
      local tools = load_tools()
      tools.detect_microbit = function()
        error('the drive was looked for')
      end
      local sounds = 0
      tools.compy.audio.hyperjump = function() sounds = sounds + 1 end
      tools.flash_microbit = function()
        return nil, 'No micro:bit is plugged in.'
      end
      files['MICROBIT.hex'] = ':00000001FF\n'
      assert.has_no_error(function() tools.upload() end)
      assert.equal('No micro:bit is plugged in.', said[#said])
      assert.equal(0, sounds)
    end)

  it('send and exec wait while a file goes to the board',
    function()
      local tools = load_tools()
      serial.job = { step = function() return 'running' end }
      assert.has_no_error(function() tools.exec('f.lua') end)
      assert.has_no_error(function() tools.send('f.lua') end)
      serial.job = nil
      assert.same({}, backend.sent)
      local told = table.concat(said, ' ')
      local _, n = told:gsub('taking a file', '')
      assert.equal(2, n)
      assert.has_no_error(function() tools.exec('f.lua') end)
      assert.same({ WRAP .. '\r' }, backend.sent)
    end)

  --- a computer copies the file onto the board's drive, as it
  --- always has
  describe('on a computer', function()
    before_each(function() os_name = 'Linux' end)
    after_each(function() os_name = 'Android' end)

    it('upload looks for the drive, sounds, copies, and says so',
      function()
        local tools = load_tools()
        local order = {}
        tools.detect_microbit = function()
          order[#order + 1] = 'detect'
          return '/mb'
        end
        tools.compy.audio.hyperjump = function()
          order[#order + 1] = 'sound'
        end
        tools.flash_microbit = function()
          order[#order + 1] = 'flash'
          return true
        end
        files['MICROBIT.hex'] = ':00000001FF\n'
        said = {}
        tools.upload()
        assert.same({ 'detect', 'sound', 'flash' }, order)
        assert.same({
          "MICROBIT.hex is sent. The micro:bit's light blinks",
          'while it writes it, then it restarts with it.',
          'MICROBIT.hex holds firmware too old to say its version',
        }, said)
      end)

    it('upload stops when no drive is found', function()
      local tools = load_tools()
      tools.detect_microbit = function() return nil end
      files['MICROBIT.hex'] = ':00000001FF\n'
      local ok, err = pcall(tools.upload)
      assert.is_false(ok)
      assert.truthy(tostring(err):find('no micro:bit plugged in',
        1, true))
      assert.is_false(flashed)
    end)
  end)

  it('restart_microbit waits while a file goes to the board',
    function()
      local tools = load_tools()
      serial.job = { step = function() return 'running' end }
      tools.restart_microbit()
      serial.job = nil
      assert.equal(0, backend.resets)
      assert.truthy(table.concat(said, ' '):find('taking a file',
        1, true))
    end)

  it('restart_microbit restarts the board', function()
    local tools = load_tools()
    tools.restart_microbit()
    assert.equal(1, backend.resets)
    local told = table.concat(said, ' ')
    assert.truthy(told:find('restarts', 1, true))
    assert.truthy(told:find('reset button', 1, true))
  end)

  it('restart_microbit turns echo back on for the greeting',
    function()
      local tools = load_tools()
      tools.echo(false)
      echoes = {}
      tools.restart_microbit()
      assert.same({ true }, echoes)
    end)

  it('restart_microbit stops an exec first, with what was queued',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      board()
      said = {}
      tools.restart_microbit()
      assert.equal(1, backend.resets)
      assert.equal(1, backend.drops)
      assert.truthy(said[1]:find('the board was restarted', 1,
        true))
      assert.is_nil(port.onBytes)
      assert.is_nil(port.onTick)
    end)

  it('a refused restart_microbit still turns echo on', function()
    local tools = load_tools()
    tools.echo(false)
    echoes = {}
    backend.refuse = 'break -1, end -1'
    assert.has_error(function() tools.restart_microbit() end)
    assert.same({ true }, echoes)
  end)

  it('restart_microbit refused while exec sends says so',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      board()
      said = {}
      backend.refuse = 'break -1, end -1'
      assert.has_error(function() tools.restart_microbit() end)
      assert.truthy(said[1]:find('did not restart', 1, true))
      assert.is_nil(port.onTick)
    end)

  it('restart_microbit says to press the button when refused', function()
    local tools = load_tools()
    backend.refuse = 'break -1'
    local ok, err = pcall(tools.restart_microbit)
    assert.is_false(ok)
    assert.truthy(tostring(err):find('reset button', 1, true))
  end)

  it('a board that stops answering points to restart_microbit', function()
    local tools = load_tools()
    tools.exec('f.lua')
    board()
    said = {}
    for _ = 1, 6 do serial:update(1) end
    assert.truthy(said[#said]:find('restart_microbit()', 1, true))
  end)

  it('refuses while no board is connected', function()
    local tools = load_tools()
    backend:detach()
    serial:update(0)
    assert.has_error(function() tools.exec('f.lua') end)
    assert.has_error(function() tools.restart_microbit() end)
    assert.equal(0, sent())
    assert.equal(0, backend.resets)
  end)
end)
