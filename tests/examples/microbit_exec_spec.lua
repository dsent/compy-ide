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

local WRAP = 'do local print, file, err = print, loadstring([=['
--- how the last line exec sends begins; the rest runs the file
--- and says how it ended
local UNWRAP = ']=], "@f.lua")'

--- @return string? luac5.1, when installed
local function luac()
  local probe = io.popen('command -v luac5.1')
  local path = probe:read('*l')
  probe:close()
  return path
end

--- What luac5.1 says of a chunk: nothing when the board's Lua,
--- which is 5.1 itself, reads it
--- @param compiler string
--- @param chunk string
--- @return string
local function luacSays(compiler, chunk)
  local path = os.tmpname()
  local f = assert(io.open(path, 'w'))
  f:write(chunk)
  f:close()
  local run = io.popen(compiler .. ' -p ' .. path .. ' 2>&1')
  local said = run:read('*a')
  run:close()
  os.remove(path)
  return said
end
local RAN = 'f.lua is on the board'

describe('micro:bit exec #microbit', function()
  local serial, backend, port, said, echoes, files, flashed
  --- the frame exec last gave echo
  local handed
  local os_name = 'Android'

  --- tools.lua loaded into an environment of its own, with what
  --- the console gives it
  local function load_tools()
    local env = setmetatable({
      compy = { serial = port, audio = { hyperjump = function() end } },
      echo = function(on, frame)
        echoes[#echoes + 1] = on ~= false
        handed = frame
      end,
      readfile = function(name) return files[name] end,
      writefile = function(name, text) files[name] = text end,
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

  --- The line the board says the file's end in, for the exec
  --- whose last line went last: a line break, then the frame
  --- with that exec's mark
  --- @param word string ok or error
  --- @return string
  local function framed(word)
    local mark = backend.sent[#backend.sent]:match('\\30exec (%x+) ')
    return '\r\n\30exec ' .. mark .. ' ' .. word .. '\r\n'
  end

  --- The file in, the board prompting after each line, and
  --- quiet after the last
  --- @param tools table
  local function run(tools)
    tools.exec('f.lua')
    for _ = 1, 3 do board() end
    board('1\r\n' .. framed('ok'), '> ')
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
      assert.same({ WRAP .. '\r', 'a = 1\r', 'print(a)\r' },
        { backend.sent[1], backend.sent[2], backend.sent[3] })
      assert.equal(4, #backend.sent)
      assert.equal(UNWRAP, backend.sent[4]:sub(1, #UNWRAP))
      assert.same({ '1', RAN }, said)
      assert.equal(mine, port.onBytes)
      assert.equal(gone, port.onDisconnect)
      assert.is_nil(port.onTick)
      --- on when loaded, off while sending, on again after
      assert.same({ true, false, true }, echoes)
    end)

  --- the board's Lua refuses a [[ inside [[ ]], and a ]=] in
  --- the file would end [=[ ]=] early
  it('wraps a file in a bracket nothing in it ends', function()
    files['g.lua'] = 'print("]=]")\n'
    local tools = load_tools()
    tools.exec('g.lua')
    assert.same({ 'do local print, file, err = print,'
      .. ' loadstring([==[\r' }, backend.sent)
  end)

  --- The lines exec sends for a file, all of them, as the
  --- board takes them
  --- @param tools table
  --- @param filename string
  --- @return string
  local function sentChunk(tools, filename)
    tools.exec(filename)
    local count = 0
    for _ in files[filename]:gmatch('[^\n]*\n') do
      count = count + 1
    end
    for _ = 1, count + 1 do board() end
    local lines = {}
    for i, line in ipairs(backend.sent) do
      lines[i] = line:gsub('\r$', '')
    end
    return table.concat(lines, '\n')
  end

  for _, text in ipairs({ 'print("[[")\n', '--[[ open\n',
    'print("]]")\nprint("]=]")\n' }) do
    it('sends a chunk the board\'s Lua reads ('
      .. text:gsub('\n', ' ') .. ')', function()
        local compiler = luac()
        if not compiler then
          pending('luac5.1 is not installed')
          return
        end
        files['g.lua'] = text
        local tools = load_tools()
        assert.equal('', luacSays(compiler, sentChunk(tools,
          'g.lua')))
      end)
  end

  --- the board's words for a mistake name the file, and exec
  --- does not call a file that stopped on one "on the board"
  it('says a file that stopped on a mistake was run', function()
    local tools = load_tools()
    tools.exec('f.lua')
    for _ = 1, 3 do board() end
    board('Runtime error: f.lua:2: boom\r\n' .. framed('error'),
      '> ')
    serial:update(0.25)
    assert.same('Runtime error: f.lua:2: boom', said[#said - 1])
    assert.same('f.lua was run, and stopped on the mistake above',
      said[#said])
  end)

  it('takes a program\'s own words for its answer', function()
    local tools = load_tools()
    tools.exec('f.lua')
    for _ = 1, 3 do board() end
    board('seen: Runtime error: none\r\nRuntime error: mine'
      .. '\r\nall done\r\n' .. framed('ok'), '> ')
    serial:update(0.25)
    assert.same('f.lua is on the board', said[#said])
  end)

  it('says the board did not say how a file ended without a'
    .. ' status', function()
      local tools = load_tools()
      tools.exec('f.lua')
      for _ = 1, 3 do board() end
      board('1\r\n', '> ')
      serial:update(0.25)
      assert.same('f.lua was run; the board did not say how it'
        .. ' ended', said[#said])
    end)

  --- The chunk exec sends, run as the board runs it: what it
  --- prints, with the board's print ending lines in CRLF
  --- @param tools table
  --- @param filename string
  --- @return string printed
  local function ranOnBoard(tools, filename)
    tools.exec(filename)
    local count = 0
    for _ in files[filename]:gmatch('[^\n]*\n') do
      count = count + 1
    end
    for _ = 1, count + 1 do board() end
    local lines = {}
    for i, line in ipairs(backend.sent) do
      lines[i] = line:gsub('\r$', '')
    end
    local out = {}
    --- the board's write: a line ends in CR LF
    local function write(text)
      out[#out + 1] = (text:gsub('\n', '\r\n'))
    end
    local env = setmetatable({ print = function(...)
      local parts = {}
      for i = 1, select('#', ...) do
        parts[i] = tostring(select(i, ...))
      end
      write(table.concat(parts, '\t') .. '\n')
    end, io = { write = write } }, { __index = _G })
    local chunk = assert(loadstring(table.concat(lines, '\n')))
    setfenv(chunk, env)
    env.loadstring = function(code, name)
      local fn, err = loadstring(code, name)
      if fn then setfenv(fn, env) end
      return fn, err
    end
    chunk()
    return table.concat(out)
  end

  --- the verdict comes from this exec's frame at the end,
  --- never from what the program printed; a frame of the
  --- program's own is shown as it is
  for _, case in ipairs({
    { 'print("Runtime error: practice")\n', 'is on the board' },
    { 'error("first\\nsecond")\n', 'stopped on the mistake' },
    { 'print(1)\nerror("Compile error: no")\n',
      'stopped on the mistake' },
    { 'x = = 1\n', 'stopped on the mistake' },
    { 'io.write("done ")\n', 'is on the board', 'done ' },
    { 'print("\\30exec ok")\nerror("boom")\n',
      'stopped on the mistake', '\30exec ok' },
    { 'print("prefix \\30exec error suffix")\n', 'is on the board',
      'prefix \30exec error suffix' },
  }) do
    it('reads how ' .. case[1]:gsub('\n', ' ') .. 'ended from its'
      .. ' own frame', function()
        files['g.lua'] = case[1]
        local tools = load_tools()
        local printed = ranOnBoard(tools, 'g.lua')
        board(printed, '> ')
        serial:update(0.25)
        assert.truthy(said[#said]:find(case[2], 1, true))
        local shown = table.concat(said, '\n')
        if case[3] then
          assert.truthy(shown:find(case[3], 1, true))
        end
        assert.is_nil(shown:find('\30exec %x+ ', 1))
      end)
  end

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
      backend:rx('y\r\n' .. framed('ok') .. '> ')
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
    backend:rx(backend.sent[#backend.sent]:gsub('\r$', '')
      .. '\r\r\n1\r\n')
    serial:update(0)
    for _ = 1, 4 do serial:update(1) end
    assert.is_not_nil(port.onBytes)
    serial:update(2)
    assert.same({ '1', 'f.lua is on the board and still running' },
      { said[#said - 1], said[#said] })
    assert.is_nil(port.onBytes)
    assert.same({ true, false, true }, echoes)
    -- echo is to say the end in words when it comes
    assert.equal(framed('ok'):match('^\r\n(.-)ok\r\n$'), handed)
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

  --- this example on a Compy from before files went down the
  --- cable: its serial table has send, reset and isConnected
  --- only (0d8a66d5), and flash_microbit copies to the drive
  describe('on an older Compy', function()
    it('sends, execs and restarts without isFlashing', function()
      local old = {}
      for _, k in ipairs({ 'send', 'reset', 'isConnected' }) do
        old[k] = port[k]
      end
      port = old
      local tools = load_tools()
      assert.has_no_error(function() tools.restart_microbit() end)
      assert.has_no_error(function() tools.send('f.lua') end)
      assert.has_no_error(function() tools.exec('f.lua') end)
    end)

    it('copies to the drive on Android', function()
      local old = {}
      for _, k in ipairs({ 'send', 'reset', 'isConnected' }) do
        old[k] = port[k]
      end
      port = old
      local tools = load_tools()
      local hooks = 'none'
      tools.flash_microbit = function(_, on)
        flashed = true
        hooks = on
        return true
      end
      files['MICROBIT.hex'] = ':00000001FF\n'
      assert.has_no_error(function() tools.upload() end)
      assert.is_true(flashed)
      assert.is_nil(hooks)
      assert.truthy(table.concat(said, ' '):find('is sent', 1, true))
    end)
  end)

  --- the Compy reads the file a share at a time, and tells
  --- the example what it read and when the sending begins
  it('upload says which firmware it read, and sounds as the'
    .. ' sending begins', function()
      local tools = load_tools()
      local hex = require('examples.microbit.hex')
      require('model.serial.intel_hex')
      local on
      tools.flash_microbit = function(_, hooks)
        flashed = true
        on = hooks
        return true
      end
      local sounds = 0
      tools.compy.audio.hyperjump = function() sounds = sounds + 1 end
      files['v.hex'] = hex.write({ {
        addr = 0,
        data = 'microbit-lua firmware abc1234\0',
      } })
      said = {}
      tools.upload('v.hex')
      assert.is_true(flashed)
      assert.same({}, said)
      assert.equal(0, sounds)
      on.read(IntelHex.parse(files['v.hex']))
      assert.equal('v.hex holds firmware abc1234', said[#said])
      assert.equal(0, sounds)
      on.sending()
      assert.equal(1, sounds)
    end)

  --- the example reads nothing itself: a damaged file is the
  --- Compy's to refuse, and nothing is said for it here
  it('upload leaves a damaged hex to the Compy\'s own check',
    function()
      local tools = load_tools()
      local sounds = 0
      tools.compy.audio.hyperjump = function() sounds = sounds + 1 end
      files['bad.hex'] = ':00000001FE\n'
      said = {}
      assert.has_no_error(function() tools.upload('bad.hex') end)
      assert.is_true(flashed)
      assert.same({}, said)
      assert.equal(0, sounds)
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
      local _, n = told:gsub('on its way to the micro:bit', '')
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

    --- without a board no hex file is written for a script
    it('writes no hex for a lua file without a board', function()
      local tools = load_tools()
      tools.detect_microbit = function() return nil end
      local f = assert(io.open('src/examples/microbit/MICROBIT.hex'))
      files['MICROBIT.hex'] = f:read('*a')
      f:close()
      files['robot.lua'] = 'print(1)\n'
      local ok, err = pcall(tools.upload, 'robot.lua')
      assert.is_false(ok)
      assert.truthy(tostring(err):find('no micro:bit plugged in',
        1, true))
      assert.is_nil(files['robot.hex'])
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
      assert.truthy(table.concat(said, ' '):find('on its way to the micro:bit',
        1, true))
    end)

  it('upload puts a lua file into a hex of its name first',
    function()
      local tools = load_tools()
      local hex = require('examples.microbit.hex')
      local f = assert(io.open('src/examples/microbit/MICROBIT.hex'))
      files['MICROBIT.hex'] = f:read('*a')
      f:close()
      files['robot.lua'] = 'print("robot")\n'
      tools.upload('robot.lua')
      assert.is_true(flashed)
      local script = hex.script(hex.parse(files['robot.hex']))
      assert.truthy(script:find(files['robot.lua'], 1, true))
    end)

  --- the card does not tell microbit.hex from MICROBIT.hex
  for _, script in ipairs({ 'MICROBIT.lua', 'microbit.lua' }) do
    it('upload leaves MICROBIT.hex as it is, and says why ('
      .. script .. ')', function()
        local tools = load_tools()
        files['MICROBIT.hex'] = ':00000001FF\n'
        files[script] = 'print(1)\n'
        assert.has_no_error(function() tools.upload(script) end)
        assert.is_false(flashed)
        assert.are.equal(':00000001FF\n', files['MICROBIT.hex'])
        assert.is_nil(files['microbit.hex'])
        local told = table.concat(said, ' ')
        assert.truthy(told:find(script .. ' would overwrite'
          .. ' MICROBIT.hex', 1, true))
        assert.truthy(told:find('Give your script another name', 1,
          true))
        assert.truthy(told:find('writefile("robot.lua", readfile("'
          .. script .. '"))', 1, true))
        assert.truthy(told:find('upload("robot.lua")', 1, true))
      end)
  end

  --- the firmware the scripts go into
  local function firmware()
    local f = assert(io.open('src/examples/microbit/MICROBIT.hex'))
    files['MICROBIT.hex'] = f:read('*a')
    f:close()
  end

  --- the card does not tell microbit.hex from MICROBIT.hex
  it('embed will not write microbit.hex in any case', function()
    local tools = load_tools()
    firmware()
    local shipped = files['MICROBIT.hex']
    files['x.lua'] = 'print(1)\n'
    for _, name in ipairs({ 'MICROBIT.hex', 'microbit.hex',
      'MicroBit.HEX' }) do
      assert.has_error(function() tools.embed(name, 'x.lua') end)
    end
    assert.are.equal(shipped, files['MICROBIT.hex'])
    assert.is_nil(files['microbit.hex'])
    assert.is_nil(files['MicroBit.HEX'])
  end)

  it('upload sends the hex it wrote for a lua file', function()
    local tools = load_tools()
    firmware()
    files['robot.lua'] = 'print("robot")\n'
    local sent
    tools.flash_microbit = function(data)
      sent = data
      return true
    end
    tools.upload('robot.lua')
    assert.is_truthy(files['robot.hex'])
    assert.are.equal(files['robot.hex'], sent)
  end)

  it('upload takes a lua file named in capitals', function()
    local tools = load_tools()
    local hex = require('examples.microbit.hex')
    firmware()
    files['ROBOT.LUA'] = 'print("robot")\n'
    tools.upload('ROBOT.LUA')
    assert.is_true(flashed)
    local script = hex.script(hex.parse(files['ROBOT.HEX']))
    assert.truthy(script:find(files['ROBOT.LUA'], 1, true))
  end)

  --- MICROBIT.hex's script is the board's REPL, print and robot
  --- commands. A hex built from a Lua file that held only that
  --- file left the board silent (00a5ad02): it keeps the
  --- firmware's script, and runs the file in it just before the
  --- prompt, while nothing else can call into Lua. Run after the
  --- prompt, a file that sleeps in a loop let the REPL into the
  --- same Lua state mid-call.
  describe('a lua file upload keeps the firmware\'s script',
    function()
      local hex = require('examples.microbit.hex')

      --- The largest file upload takes
      local CAP = 2500

      --- The script the shipped firmware carries
      --- @return string
      local function runtime()
        return hex.script(hex.parse(files['MICROBIT.hex']))
      end

      --- The firmware's script whole around what was put in it,
      --- just before its prompt; what was put in
      --- @param data string a hex file
      --- @return string
      local function keeps(data)
        local script = hex.script(hex.parse(data))
        local base = runtime()
        local at = base:match('.*()\nserial_session%.prompt%(%)')
        local tail = base:sub(at)
        assert.are.equal(base:sub(1, at - 1), script:sub(1, at - 1))
        assert.are.equal(tail, script:sub(-#tail))
        return script:sub(at, -#tail - 1)
      end

      --- The hex upload built for robot.lua, and what it sent
      --- @param tools table
      --- @return string? sent
      local function uploaded(tools)
        local sent
        tools.flash_microbit = function(data)
          sent = data
          flashed = true
          return true
        end
        tools.upload('robot.lua')
        return sent
      end

      --- Every field of it, and every call's, is another such,
      --- as the firmware's API is to its script here; what the
      --- board is told is not looked at, save the serial port
      --- @return table
      local function anything()
        return setmetatable({}, {
          __index = function(t, k)
            local v = anything()
            rawset(t, k, v)
            return v
          end,
          __call = function() end
        })
      end

      --- Run a hex's script as the firmware does, over a board
      --- that takes any call: what it wrote to the port, the
      --- globals it left, and its error, if it stopped on one
      --- @param data string
      --- @return string out
      --- @return table env
      --- @return string? err
      local function boot(data)
        local out = {}
        local microbit = anything()
        microbit.serial.send = function(c) out[#out + 1] = c end
        microbit.serial.eventAfterAsync = function()
          out[#out + 1] = '<armed>'
        end
        microbit.display.scrollAsync = function(text)
          out[#out + 1] = '<scrolled ' .. tostring(text) .. '>'
        end
        local env = setmetatable({ microbit = microbit },
          { __index = _G })
        env._G = env
        -- a string library of the board's own: a file that
        -- changes it changes nothing outside this board
        env.string = {}
        for k, v in pairs(string) do env.string[k] = v end
        -- the thread's globals are the test run's: level 0 is
        -- left to the runs on Lua 5.1
        env.setfenv = function(f, t)
          if f == 0 then return end
          return setfenv(f, t)
        end
        env.loadstring = function(code, name)
          local fn, err = loadstring(code, name)
          if fn then
            setfenv(fn, env)
          end
          return fn, err
        end
        local chunk = assert(loadstring(
          hex.script(hex.parse(data)), 'embedded'))
        setfenv(chunk, env)
        local ok, err = pcall(chunk)
        env.heard = out
        return table.concat(out), env, not ok and tostring(err)
          or nil
      end

      --- Whether a handler takes what is typed at the board to
      --- the prompt, as the firmware's does: it arms the port
      --- again for the next character
      --- @param env table a booted board
      --- @param handler function
      --- @return boolean
      local function typing(env, handler)
        local before = #env.heard
        handler(env.microbit.DEVICE_ID_SERIAL,
          env.microbit.CODAL_SERIAL_EVT_HEAD_MATCH)
        for i = before + 1, #env.heard do
          if env.heard[i] == '<armed>' then
            return true
          end
        end
        return false
      end

      --- @return string? lua5.1, when installed
      local function lua51()
        local probe = io.popen('command -v lua5.1')
        local path = probe:read('*l')
        probe:close()
        return path
      end

      --- A board for lua5.1: a stub of the firmware's API in the
      --- real globals, the built script run as the firmware
      --- runs it, then what on_event gives
      local BOARD = [==[
local out, write = {}, io.write
local function anything()
  return setmetatable({}, { __index = function(t, k)
    local v = anything() rawset(t, k, v) return v end,
    __call = function() end })
end
microbit = anything()
microbit.serial.send = function(c) out[#out + 1] = c end
local typed, up = TYPED, false
microbit.serial.getCharAsync = function()
  if not up then return nil end
  local c = typed:sub(1, 1)
  typed = typed:sub(2)
  if c ~= '' then return c end
end
-- The firmware's dispatcher: the thread's on_event, or, when
-- that is not a function, the handler given to eventFallback;
-- one Lua call at a time, so an event that comes while Lua
-- runs waits, and goes once the call ends, or at a sleep,
-- each to its end
local fallback, waiting, running = nil, {}, true
microbit.eventFallback = function(f) fallback = fallback or f end
local function handle(source, value)
  local h = rawget(getfenv(0), 'on_event')
  if type(h) ~= 'function' then h = fallback end
  if h then pcall(h, source, value, 0) end
end
local function drain()
  local now = waiting
  waiting = {}
  for _, e in ipairs(now) do handle(e[1], e[2]) end
end
function arrive(source, value)
  if running then
    waiting[#waiting + 1] = { source, value }
  else
    handle(source, value)
  end
end
microbit.sleep = function() drain() end
local f = assert(io.open(arg[1], 'rb'))
local chunk = assert(loadstring(f:read('*a'), 'embedded'))
f:close()
pcall(chunk)
running = false
drain()
up = true
-- what is typed reaches Lua as the firmware sends it
handle(microbit.DEVICE_ID_SERIAL,
  microbit.CODAL_SERIAL_EVT_HEAD_MATCH)
write(table.concat(out))
]==]

      --- What the board said, booted on lua5.1
      --- @param lua string
      --- @param data string a hex file
      --- @return string
      --- @param typed string? typed at the board once it is up
      local function bootOn(lua, data, typed)
        local script, board = os.tmpname(), os.tmpname()
        local f = assert(io.open(script, 'wb'))
        f:write(hex.script(hex.parse(data)))
        f:close()
        f = assert(io.open(board, 'wb'))
        f:write(('local TYPED = %q\n'):format(typed or ''), BOARD)
        f:close()
        local run = io.popen(lua .. ' ' .. board .. ' ' .. script)
        local said = run:read('*a')
        run:close()
        os.remove(script)
        os.remove(board)
        return said
      end

      before_each(firmware)

      it('holds the firmware\'s script whole, the file just'
        .. ' before its prompt', function()
          local tools = load_tools()
          files['robot.lua'] = 'print("blink-ok")\n'
          assert.truthy(keeps(uploaded(tools)):find(
            files['robot.lua'], 1, true))
        end)

      it('runs the file before the prompt', function()
          local tools = load_tools()
          files['robot.lua'] = 'print("blink-ok")\n'
          local out, env, err = boot(uploaded(tools))
          assert.is_nil(err)
          assert.is_function(env.on_event)
          local repl = assert(out:find('Lua 5.1 REPL', 1, true))
          local ran = assert(out:find('blink-ok\r\n', repl, true))
          local prompt = assert(out:find('> ', ran, true))
          assert.truthy(out:find('<armed>', prompt, true))
          assert.truthy(ran < assert(out:find('<armed>', 1, true)))
        end)

      it('lets the file call the firmware\'s on_event', function()
        local tools = load_tools()
        files['robot.lua'] = 'local firmware = on_event\n'
          .. 'function on_event(...) return "mine", firmware end\n'
        local _, env, err = boot(uploaded(tools))
        assert.is_nil(err)
        local mine, firmware = env.on_event()
        assert.equal('mine', mine)
        assert.is_true(typing(env, firmware))
      end)

      it('takes an on_event a function of the file sets later',
        function()
          local tools = load_tools()
          files['robot.lua'] = 'function on_event() return 1 end\n'
            .. 'function start() on_event = function() return 2 end'
            .. ' end\n'
          local _, env, err = boot(uploaded(tools))
          assert.is_nil(err)
          assert.equal(1, env.on_event())
          env.start()
          assert.equal(2, env.on_event())
        end)

      --- the board's globals are the file's: what it set before
      --- a mistake stays
      it('keeps an on_event the file set before a mistake',
        function()
          local tools = load_tools()
          files['robot.lua'] =
            'function on_event() return "mine" end\nerror("oops")\n'
          local out, env, err = boot(uploaded(tools))
          assert.is_nil(err)
          assert.truthy(out:find('oops', 1, true))
          assert.equal('mine', env.on_event())
        end)

      --- The board's Lua is 5.1 itself, stricter than LuaJIT
      --- here: it refuses a [[ inside [[ ]]
      for _, text in ipairs({ 'print("[[")\n', '--[[ open\n',
        'print("]]")\n', 'print([==[ a ]] b ]==])',
        'print([=[ x ]=])\n' }) do
        it('builds a script the board\'s Lua reads ('
          .. text:gsub('\n', ' ') .. ')', function()
            local compiler = luac()
            if not compiler then
              pending('luac5.1 is not installed')
              return
            end
            local tools = load_tools()
            files['robot.lua'] = text
            uploaded(tools)
            assert.equal('', luacSays(compiler,
              hex.script(hex.parse(files['robot.hex']))))
          end)
      end

      --- an on_event the file sets, by any way to the board's
      --- globals: an event that came while the file ran waits
      --- for it to end, then goes to that on_event (the board
      --- runs one Lua call at a time)
      for _, text in ipairs({
        'function on_event(...) return f(...) end',
        '_G.on_event = f',
        'rawset(_G, "on_event", f)',
        'getfenv(0).on_event = f',
        'setfenv(0, { on_event = f })',
        'loadstring("on_event = ...")(f)',
      }) do
        it('hands an event that came while the file ran to an'
          .. ' on_event set by ' .. text .. ', once the file ends',
          function()
            local lua = lua51()
            if not lua then
              pending('lua5.1 is not installed')
              return
            end
            local tools = load_tools()
            files['robot.lua'] = 'local function f(source)'
              .. ' print("event", source) end\n' .. text
              .. '\narrive(7)\nprint("still running")\n'
            local said = bootOn(lua, uploaded(tools))
            local running = assert(said:find('still running', 1,
              true))
            assert.truthy(said:find('event\t7', running, true))
          end)
      end

      --- the coming firmware hands waiting events on at a sleep,
      --- each to its end: the file's code goes on after it
      it('goes on after a sleep that handed an event on',
        function()
          local lua = lua51()
          if not lua then
            pending('lua5.1 is not installed')
            return
          end
          local tools = load_tools()
          files['robot.lua'] = 'function on_event(source)'
            .. ' print("event", source) end\narrive(7)\n'
            .. 'microbit.sleep(10)\nprint("after the sleep")\n'
          local said = bootOn(lua, uploaded(tools), 'print(6*7)\r')
          local event = assert(said:find('event\t7', 1, true))
          assert.truthy(said:find('after the sleep', event, true))
        end)

      --- the board's own Lua, with a command typed once it is
      --- up: the prompt has to answer it
      for _, text in ipairs({ 'setmetatable(_G, { __metatable ='
        .. ' false })', 'getmetatable(_G).__metatable = 1',
        'setfenv(0, {})', 'error("oops")', 'on_event = 5',
        '' }) do
        it('answers print(6*7) after a file that runs ' .. text,
          function()
            local lua = lua51()
            if not lua then
              pending('lua5.1 is not installed')
              return
            end
            local tools = load_tools()
            files['robot.lua'] = text .. '\nprint("ran")\n'
            local said = bootOn(lua, uploaded(tools),
              'print(6*7)\r')
            local prompt = assert(said:find('> ', 1, true))
            assert.truthy(said:find('42\r\n', prompt, true))
          end)
      end

      --- what the wrapper needs after the file is its own
      for _, text in ipairs({ 'rawset = 1', 'rawget = 1',
        'setmetatable = 1', 'pcall = nil', 'tostring = nil',
        'print = nil', 'type = nil', 'microbit.display = nil',
        'string.gmatch = nil', 'string = nil',
        'active_session = { transport = {} }' }) do
        it('brings the prompt after a file that sets ' .. text,
          function()
            local tools = load_tools()
            files['robot.lua'] = text .. '\nerror("oops")\n'
            local out, env, err = boot(uploaded(tools))
            assert.is_nil(err)
            local prompt = assert(out:find('> ', 1, true))
            assert.truthy(out:find('<armed>', prompt, true))
            assert.is_function(env.on_event)
          end)
      end

      it('leaves the file\'s other globals to the prompt',
        function()
          local tools = load_tools()
          files['robot.lua'] = 'answer = 42\n'
          local _, env, err = boot(uploaded(tools))
          assert.is_nil(err)
          assert.equal(42, rawget(env, 'answer'))
        end)

      it('says a file stopped with no message, then the prompt',
        function()
          local tools = load_tools()
          files['robot.lua'] = 'print("before")\nerror()\n'
          local out, env, err = boot(uploaded(tools))
          assert.is_nil(err)
          local at = assert(out:find('before\r\nrobot.lua stopped,'
            .. ' and said nothing more.\r\n', 1, true))
          assert.truthy(out:find('<armed>', at, true))
          assert.is_function(env.on_event)
        end)

      it('shows the prompt when the mistake cannot be said',
        function()
          local tools = load_tools()
          files['robot.lua'] = 'error(setmetatable({}, { __tostring'
            .. ' = function() error("boom") end }))\n'
          local out, env, err = boot(uploaded(tools))
          assert.is_nil(err)
          assert.truthy(out:find('<armed>', 1, true))
          assert.is_function(env.on_event)
        end)

      it('runs a file that holds long brackets as it stands',
        function()
          local tools = load_tools()
          files['robot.lua'] = 'print("a]]b")\nprint("c]=]d")\n'
            .. 'print([[e]])'
          local out, _, err = boot(uploaded(tools))
          assert.is_nil(err)
          assert.truthy(out:find('a]]b\r\nc]=]d\r\ne\r\n', 1,
            true))
        end)

      --- the line a mistake is on, as the file alone would give
      for _, text in ipairs({ 'print("one")\nprint(\n', 'print(',
        'x = ]=', 'print("one")\nerror("two")' }) do
        it('shows a mistake with its line, then the prompt ('
          .. text:gsub('\n', ' ') .. ')', function()
            local tools = load_tools()
            files['robot.lua'] = text
            local out, env, err = boot(uploaded(tools))
            assert.is_nil(err)
            local fn, why = loadstring(text, '@robot.lua')
            if fn then
              _, why = pcall(fn)
            end
            local at = assert(out:find(why .. '\r\n', 1, true))
            local line = why:match(':(%d+):')
            assert.truthy(out:find('<scrolled error, line ' .. line
              .. '>', at, true))
            local prompt = assert(out:find('> ', at, true))
            assert.truthy(out:find('<armed>', prompt, true))
            assert.is_function(env.on_event)
          end)
      end

      --- after the bracket a CR would join the newline, and
      --- every line would be counted one too few
      it('counts lines from a file that starts with a CR',
        function()
          local tools = load_tools()
          files['robot.lua'] = '\rprint('
          local out = boot(uploaded(tools))
          assert.truthy(out:find('robot.lua:2:', 1, true))
          assert.truthy(out:find('<scrolled error, line 2>', 1,
            true))
        end)

      --- the robot's commands say what went wrong with no line
      it('scrolls the first sentence of a mistake with no line',
        function()
          local tools = load_tools()
          files['robot.lua'] =
            'error("The robot does not answer. Check it.", 0)\n'
          local out = boot(uploaded(tools))
          assert.truthy(out:find('<scrolled The robot does not'
            .. ' answer>', 1, true))
        end)

      it('scrolls no line of another file as the file\'s',
        function()
          local tools = load_tools()
          files['robot.lua'] = 'error("lib.lua:340: boom", 0)\n'
          local out = boot(uploaded(tools))
          assert.is_nil(out:find('error, line 340', 1, true))
        end)

      it('sends exactly the hex it wrote', function()
        local tools = load_tools()
        files['robot.lua'] = 'print("robot")\n'
        local sent = uploaded(tools)
        assert.are.equal(files['robot.hex'], sent)
        keeps(sent)
      end)

      it('takes and runs a program as long as the cap',
        function()
          local tools = load_tools()
          local tail = 'print("end")\n'
          local code = ('x = 1\n'):rep(math.floor((CAP - #tail)
            / 6)) .. tail
          code = (' '):rep(CAP - #code) .. code
          assert.equal(CAP, #code)
          files['robot.lua'] = code
          local out, _, err = boot(uploaded(tools))
          assert.is_true(flashed)
          assert.is_nil(err)
          assert.truthy(out:find('end\r\n', 1, true))
        end)

      --- CRs go before the file is counted
      it('counts a file with CRLF endings as the board reads it',
        function()
          local tools = load_tools()
          local code = ('x = 1\n'):rep(math.floor(CAP / 6))
          files['robot.lua'] = code:gsub('\n', '\r\n')
          assert.is_true(CAP < #files['robot.lua'])
          uploaded(tools)
          assert.is_true(flashed)
        end)

      it('refuses a file one character longer, in words',
        function()
          local tools = load_tools()
          files['robot.lua'] = ('-'):rep(CAP + 1)
          said = {}
          assert.has_no_error(function() uploaded(tools) end)
          assert.is_false(flashed)
          assert.is_nil(files['robot.hex'])
          local told = table.concat(said, ' ')
          assert.truthy(told:find('robot.lua is too long', 1, true))
          assert.truthy(told:find(CAP .. ' characters', 1, true))
          assert.truthy(told:find('Make it shorter', 1, true))
        end)

      it('refuses a firmware with no place for the file',
        function()
          local tools = load_tools()
          local blocks = hex.parse(files['MICROBIT.hex'])
          hex.embed(blocks, 'print("another firmware")\n')
          files['MICROBIT.hex'] = hex.write(blocks)
          files['robot.lua'] = 'print("robot")\n'
          said = {}
          assert.has_no_error(function() uploaded(tools) end)
          assert.is_false(flashed)
          assert.is_nil(files['robot.hex'])
          local told = table.concat(said, ' ')
          assert.truthy(told:find('no place for your program', 1,
            true))
          assert.truthy(told:find('embed("robot.hex", "robot.lua")',
            1, true))
          assert.truthy(told:find('upload("robot.hex")', 1, true))
        end)

      it('says once that it wrote the hex', function()
        local tools = load_tools()
        tools.writefile = function(name, text)
          files[name] = text
          tools.print(name .. ' written')
        end
        files['robot.lua'] = 'print("robot")\n'
        said = {}
        uploaded(tools)
        assert.same({ 'robot.hex written' }, said)
      end)

      --- the console's writefile: it says how the write went,
      --- and returns nothing either way
      --- @param tools table
      local function failingWrites(tools)
        tools.writefile = function(name)
          tools.print('cannot write ' .. name)
        end
      end

      it('sends nothing when the hex cannot be saved', function()
        local tools = load_tools()
        failingWrites(tools)
        files['robot.lua'] = 'print("robot")\n'
        said = {}
        uploaded(tools)
        assert.is_false(flashed)
        local told = table.concat(said, ' ')
        assert.truthy(told:find('cannot write robot.hex', 1, true))
        assert.truthy(told:find('robot.hex could not be saved', 1,
          true))
        assert.truthy(told:find('upload it again', 1, true))
        assert.falsy(told:find('written', 1, true))
      end)

      it('sends no older hex left on the card when the write'
        .. ' fails', function()
          local tools = load_tools()
          failingWrites(tools)
          files['robot.hex'] = 'an older build'
          files['robot.lua'] = 'print("robot")\n'
          uploaded(tools)
          assert.is_false(flashed)
          assert.equal('an older build', files['robot.hex'])
        end)

      for _, text in ipairs({ '', ' \n\t\n' }) do
        it('refuses an empty file in words ('
          .. #text .. ' characters)', function()
            local tools = load_tools()
            files['robot.lua'] = text
            said = {}
            assert.has_no_error(function() uploaded(tools) end)
            assert.is_false(flashed)
            assert.is_nil(files['robot.hex'])
            local told = table.concat(said, ' ')
            assert.truthy(told:find('robot.lua is empty', 1, true))
            assert.truthy(told:find('edit("robot.lua")', 1, true))
          end)
      end

      it('says nothing of a version the firmware does not carry',
        function()
          local tools = load_tools()
          require('model.serial.intel_hex')
          local on
          tools.flash_microbit = function(data, hooks)
            flashed = true
            on = hooks
            return true
          end
          -- the shipped firmware, its version mark worn off
          local blocks = hex.parse(files['MICROBIT.hex'])
          for _, b in ipairs(blocks) do
            b.data = b.data:gsub('microbit%-lua firmware ',
              ('-'):rep(22))
          end
          files['MICROBIT.hex'] = hex.write(blocks)
          files['robot.lua'] = 'print("robot")\n'
          said = {}
          tools.upload('robot.lua')
          assert.is_true(flashed)
          on.read(IntelHex.parse(files['robot.hex']))
          assert.same({}, said)
        end)

      describe('onto the drive', function()
        local old_os
        before_each(function()
          old_os = os_name
          os_name = 'Linux'
        end)
        after_each(function() os_name = old_os end)

        it('copies the hex it built, and says so', function()
          local tools = load_tools()
          files['robot.lua'] = 'print("robot")\n'
          said = {}
          local sent = uploaded(tools)
          assert.are.equal(files['robot.hex'], sent)
          keeps(sent)
          assert.same({
            "robot.hex is sent. The micro:bit's light blinks",
            'while it writes it, then it restarts with it.',
          }, { said[1], said[2] })
          assert.truthy(said[3]:match(
            '^robot%.hex holds firmware %x+'))
        end)
      end)

      it('copies to the drive on an older Android Compy', function()
        local old = {}
        for _, k in ipairs({ 'send', 'reset', 'isConnected' }) do
          old[k] = port[k]
        end
        port = old
        local tools = load_tools()
        local hooks = 'none'
        files['robot.lua'] = 'print("robot")\n'
        local sent
        tools.flash_microbit = function(data, on)
          sent, hooks, flashed = data, on, true
          return true
        end
        tools.upload('robot.lua')
        assert.is_nil(hooks)
        assert.are.equal(files['robot.hex'], sent)
        keeps(sent)
      end)
    end)

  --- nothing is built or written while a file is on its way
  it('upload writes nothing while a flash runs', function()
    local tools = load_tools()
    firmware()
    files['x.lua'] = 'print(1)\n'
    serial.job = { step = function() return 'running' end }
    assert.has_no_error(function() tools.upload('x.lua') end)
    serial.job = nil
    assert.is_nil(files['x.hex'])
    assert.is_false(flashed)
    assert.truthy(table.concat(said, ' '):find(
      'on its way to the micro:bit', 1, true))
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
