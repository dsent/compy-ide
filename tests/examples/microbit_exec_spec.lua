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

local WRAP = "do local R,G=rawget,_G local f,e=R(G,'loadstring')([=["
--- how the last line exec sends begins; the rest runs the file
--- and says how it ended
local UNWRAP = ']=],"@f.lua")'

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
    for _ = 1, 5 do board() end
    board('1\r\n' .. framed('ok'), '> ')
    serial:update(0.25)
  end

  --- @return integer
  local function sent()
    return #backend.sent
  end

  --- Everything said, a line after another, as one text: a long
  --- line is said broken between words
  --- @return string
  local function allSaid()
    return table.concat(said, ' ')
  end

  --- A command refused in words: no error panel, no line
  --- number, and the words given among what it said
  --- @param command function
  --- @param ... string words it is to say
  local function refusedPlainly(command, ...)
    said = {}
    assert.has_no_error(command)
    local told = table.concat(said, ' ')
    assert.is_nil(told:find('%.lua:%d+:'), told)
    for _, words in ipairs({ ... }) do
      assert.truthy(told:find(words, 1, true), told)
    end
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
      assert.equal(6, #backend.sent)
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
    assert.same({ WRAP:gsub('%[=%[$', '[==[') .. '\r' },
      backend.sent)
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
    for _ = 1, count + 3 do board() end
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

  --- The cable carries about 60 characters a second, and the
  --- board's port holds 254: what exec adds to every file stays
  --- short, and each of its lines well within the port
  it('adds under 440 characters to a file, none of its lines 200',
    function()
      files['g.lua'] = 'x = 1\n'
      local tools = load_tools()
      local chunk = sentChunk(tools, 'g.lua')
      local added = #chunk - #'x = 1'
      assert.is_true(added < 440, added)
      for line in chunk:gmatch('[^\n]+') do
        assert.is_true(#line < 200, line)
      end
    end)

  --- the board's words for a mistake name the file, and exec
  --- does not call a file that stopped on one "on the board"
  it('says a file that stopped on a mistake was run', function()
    local tools = load_tools()
    tools.exec('f.lua')
    for _ = 1, 5 do board() end
    board('Runtime error: f.lua:2: boom\r\n' .. framed('error'),
      '> ')
    serial:update(0.25)
    assert.same('Runtime error: f.lua:2: boom', said[#said - 1])
    assert.same('f.lua was run, and stopped on the mistake above',
      said[#said])
  end)

  --- a file the board could not compile never ran
  it('says a file with a mistake in how it is written could not'
    .. ' run', function()
      local tools = load_tools()
      tools.exec('f.lua')
      for _ = 1, 5 do board() end
      board('Compile error: f.lua:1: unexpected symbol\r\n'
        .. framed('compile'), '> ')
      serial:update(0.25)
      assert.same('f.lua could not run, because of the mistake'
        .. ' above', said[#said])
      assert.is_nil(table.concat(said, ' '):find('was run', 1, true))
    end)

  it('takes a program\'s own words for its answer', function()
    local tools = load_tools()
    tools.exec('f.lua')
    for _ = 1, 5 do board() end
    board('seen: Runtime error: none\r\nRuntime error: mine'
      .. '\r\nall done\r\n' .. framed('ok'), '> ')
    serial:update(0.25)
    assert.same('f.lua is on the board', said[#said])
  end)

  it('says the board has not said how a file went without a'
    .. ' status, and gives echo the frame', function()
      local tools = load_tools()
      tools.exec('f.lua')
      for _ = 1, 5 do board() end
      board('1\r\n', '> ')
      serial:update(0.25)
      -- the chunk may have failed before the file ran, or the
      -- "> " is the program's own
      local words = 'the board has not said how f.lua went. It may'
        .. ' still be running; if the board does not answer, type'
        .. ' restart_microbit(), then try again.'
      assert.equal(words, allSaid():sub(-#words))
      assert.equal(framed('ok'):match('^\r\n(.-)ok\r\n$'), handed)
    end)

  --- The chunk exec sends, run as the board runs it: what it
  --- prints, with the board's print ending lines in CRLF
  --- @param tools table
  --- @param filename string
  --- @return string printed
  --- A board's globals, as the chunk exec sends finds them
  --- through _G, and what the board has said, a line ending in
  --- CR LF
  --- @return table board { env, out }
  local function newBoard()
    local out = {}
    local function write(text)
      out[#out + 1] = (text:gsub('\n', '\r\n'))
    end
    local env = setmetatable({ print = function(...)
      local parts = {}
      for i = 1, select('#', ...) do
        parts[i] = tostring(select(i, ...))
      end
      write(table.concat(parts, '\t') .. '\n')
    end, io = { write = write }, pcall = pcall, tostring = tostring,
      microbit = { serial = { send = function(text)
        out[#out + 1] = text
      end } } }, { __index = _G })
    env._G = env
    env.loadstring = function(code, name)
      local fn, err = loadstring(code, name)
      if fn then setfenv(fn, env) end
      return fn, err
    end
    return { env = env, out = out }
  end

  --- The chunk exec sends for a file, run as the board runs it:
  --- what it prints, with the board's print ending lines in
  --- CR LF. A board given goes on from what earlier files left
  --- in its globals.
  --- @param tools table
  --- @param filename string
  --- @param on table? a board from newBoard
  --- @return string printed
  local function ranOnBoard(tools, filename, on)
    local before = #backend.sent
    tools.exec(filename)
    local count = 0
    for _ in files[filename]:gmatch('[^\n]*\n') do
      count = count + 1
    end
    for _ = 1, count + 3 do board() end
    local lines = {}
    for i = before + 1, #backend.sent do
      lines[#lines + 1] = backend.sent[i]:gsub('\r$', '')
    end
    on = on or newBoard()
    for i = #on.out, 1, -1 do on.out[i] = nil end
    local chunk = assert(loadstring(table.concat(lines, '\n')))
    setfenv(chunk, on.env)
    chunk()
    return table.concat(on.out)
  end

  --- a program that puts its own print or takes pcall away in
  --- the board's globals: the next exec still says how its file
  --- ended
  for _, text in ipairs({ 'print = function() end', 'print = nil',
    'pcall = nil' }) do
    it('reads the next file\'s end after a program runs ' .. text,
      function()
        local on = newBoard()
        files['g.lua'] = text .. '\n'
        local tools = load_tools()
        board(ranOnBoard(tools, 'g.lua', on), '> ')
        serial:update(0.25)
        files['h.lua'] = 'x = 1\n'
        said = {}
        board(ranOnBoard(tools, 'h.lua', on), '> ')
        serial:update(0.25)
        assert.equal('h.lua is on the board', said[#said])
      end)
  end

  --- the verdict comes from this exec's frame at the end,
  --- never from what the program printed; a frame of the
  --- program's own is shown as it is
  for _, case in ipairs({
    { 'print("Runtime error: practice")\n', 'is on the board' },
    { 'error("first\\nsecond")\n', 'stopped on the mistake' },
    { 'print(1)\nerror("Compile error: no")\n',
      'stopped on the mistake' },
    { 'x = = 1\n', 'could not run, because of the mistake above' },
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
    assert.equal(12, sent())
    assert.is_nil(port.onBytes)
    assert.equal(RAN, said[#said])
  end)

  it('takes what came before the echo for none of its own',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      --- the greeting of a board just reset, as the bundled
      --- firmware gives it: an empty line first
      backend:rx('\r\nmicro:bit\r\nLua 5.1 REPL\r\nfirmware'
        .. ' 0a975a4\r\n> ')
      serial:update(0)
      assert.equal(1, sent())
      board()
      assert.equal(2, sent())
    end)

  it('waits for the board to be quiet after the last prompt',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      for _ = 1, 5 do board() end
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

  --- the same line said again reads as stuck
  it('says each line it gets to once', function()
    local tools = load_tools()
    tools.exec('f.lua')
    -- the board takes the first line, then goes on sending
    backend:rx(backend.sent[1]:gsub('\r$', '') .. '\r\r\n')
    said = {}
    for _ = 1, 8 do
      backend:rx('.')
      serial:update(1)
    end
    local _, n = table.concat(said, '\n'):gsub('exec: line', '')
    assert.equal(1, n)
  end)

  --- a program from upload runs on the board: it may send all
  --- the while and never echo what exec sends
  it('says a board that sends but never takes the line has not'
    .. ' taken it, waits a minute, then stops, and says upload()'
    .. ' brings the Compy back', function()
      local tools = load_tools()
      tools.exec('f.lua')
      said = {}
      for _ = 1, 7 do
        backend:rx('alive\r\n')
        serial:update(1)
      end
      local told = table.concat(said, ' ')
      assert.truthy(told:find('has not taken line 1 of 2 of f.lua'
        .. ' yet, and exec is still waiting; restart_microbit()'
        .. ' stops it', 1, true))
      assert.truthy(told:find('upload() puts the Compy\'s'
        .. ' firmware back', 1, true))
      assert.is_not_nil(port.onBytes)
      for _ = 1, 54 do
        backend:rx('alive\r\n')
        serial:update(1)
      end
      told = table.concat(said, ' ')
      local _, n = told:gsub('has not taken', '')
      assert.equal(1, n)
      assert.truthy(allSaid():find('did not take it. Type'
        .. ' restart_microbit(), then try again. If a program of'
        .. ' yours is on it from upload, upload() puts the Compy\'s'
        .. ' firmware back.', 1, true))
      assert.is_nil(port.onBytes)
      assert.equal(1, sent())
    end)

  --- the board's prompt waits behind a handler that prints and
  --- sleeps: the line is taken once the handler ends
  it('waits for a board busy with a handler, and goes on once it'
    .. ' takes the line', function()
      local tools = load_tools()
      tools.exec('f.lua')
      said = {}
      for _ = 1, 8 do
        backend:rx('healthy\r\n')
        serial:update(1)
      end
      board()
      assert.equal(2, sent())
      local told = table.concat(said, ' ')
      assert.truthy(told:find('has not taken line 1', 1, true))
      assert.is_nil(told:find('stopped', 1, true))
      assert.is_not_nil(port.onBytes)
    end)

  --- a program of the board's own prints while the line waits
  it('shows what a busy board prints while the line waits',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      said = {}
      for i = 1, 3 do
        backend:rx('busy' .. i .. '\r\n')
        serial:update(1)
      end
      local shown = {}
      for _, line in ipairs(said) do
        if not line:find('^exec:') then shown[#shown + 1] = line end
      end
      assert.same({ 'busy1', 'busy2', 'busy3' }, shown)
      board()
      assert.equal(2, sent())
      assert.is_nil(table.concat(said, ' '):find('loadstring', 1,
        true))
    end)

  --- an echo coming in slowly is the board taking the line
  it('waits on an echo that keeps coming, however slowly',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      said = {}
      local echo = WRAP .. '\r\r\n'
      for at = 1, #echo, 5 do
        backend:rx(echo:sub(at, at + 4))
        serial:update(1)
      end
      assert.is_true(#echo > 5 * 6)
      backend:rx('>> ')
      serial:update(0)
      assert.equal(2, sent())
      assert.is_nil(table.concat(said, ' '):find('has not taken', 1,
        true))
    end)

  --- The last line's echo, then the file printing every half
  --- second until just before exec's wait is over
  --- @param tools table
  local function printingUntilLate(tools)
    tools.exec('f.lua')
    for _ = 1, 5 do board() end
    backend:rx(backend.sent[#backend.sent]:gsub('\r$', '')
      .. '\r\r\n')
    serial:update(0)
    for _ = 1, 9 do
      backend:rx('1\r\n')
      serial:update(0.5)
    end
    serial:update(0.4)
  end

  --- a file that ends as the wait runs out has ended
  it('reads the end of a file that ends just before the wait is'
    .. ' over', function()
      local tools = load_tools()
      printingUntilLate(tools)
      backend:rx(framed('ok') .. '> ')
      serial:update(0.15)
      serial:update(0.25)
      assert.equal('f.lua is on the board', said[#said])
      assert.is_nil(table.concat(said, '\n'):find('\30', 1, true))
    end)

  it('waits for an end line the wait cut in two', function()
    local tools = load_tools()
    printingUntilLate(tools)
    local line = framed('ok')
    backend:rx(line:sub(1, 8))
    serial:update(0.15)
    assert.is_not_nil(port.onBytes)
    backend:rx(line:sub(9) .. '> ')
    serial:update(0)
    serial:update(0.25)
    assert.equal('f.lua is on the board', said[#said])
    assert.is_nil(table.concat(said, '\n'):find('\30', 1, true))
  end)

  --- its status cut after the o, and the prompt after the wait
  it('waits for an end line the wait cut in its status',
    function()
      local tools = load_tools()
      printingUntilLate(tools)
      local line = framed('ok')
      backend:rx(line:sub(1, -4))
      serial:update(0.3)
      assert.is_not_nil(port.onBytes)
      backend:rx(line:sub(-3) .. '> ')
      serial:update(0)
      serial:update(0.25)
      assert.equal('f.lua is on the board', said[#said])
      assert.is_nil(table.concat(said, '\n'):find('\30', 1, true))
    end)

  --- The console's own echo, over the port's console table, as
  --- the console gives it: echo takes what exec had not shown
  --- @param tools table
  local function consoleEcho(tools)
    local function say(text) said[#said + 1] = text end
    serial.echo = Echo.new(say, say)
    local console = serial:table_for('console')
    tools.echo = function(on, frame, rest)
      echoes[#echoes + 1] = on ~= false
      if on == false then
        serial.echo:off()
        console.onBytes = nil
        return
      end
      serial.echo:on()
      if frame then serial.echo:expect(frame) end
      console.onBytes = function(chunk) serial.echo:bytes(chunk) end
      if rest then serial.echo:bytes(rest) end
      return true
    end
  end

  --- the board quiet in the middle of its end line: echo holds
  --- the start and reads the line whole once the rest comes
  it('hands an end line cut in two over to echo, which reads it'
    .. ' whole', function()
      local tools = load_tools()
      consoleEcho(tools)
      tools.exec('f.lua')
      for _ = 1, 5 do board() end
      local line = framed('ok')
      backend:rx(backend.sent[#backend.sent]:gsub('\r$', '')
        .. '\r\r\n1\r\n' .. line:sub(1, -4))
      serial:update(0)
      for _ = 1, 6 do serial:update(1) end
      assert.is_nil(port.onBytes)
      backend:rx(line:sub(-3) .. '> ')
      serial:update(0)
      serial:update(0.25)
      local told = table.concat(said, '\n')
      assert.is_nil(told:find('\30', 1, true))
      local one = told:find('1\n', 1, true)
      local running = told:find('f.lua is on the board and still'
        .. ' running\nThe program on the micro:bit has ended.', 1,
        true)
      assert.truthy(one and running and one < running, told)
    end)

  --- an on_event of the file's prints on after its end, within
  --- the settle each time: all of it shows, after the verdict
  it('shows what the board prints after the file\'s end',
    function()
      local tools = load_tools()
      consoleEcho(tools)
      tools.exec('f.lua')
      for _ = 1, 5 do board() end
      backend:rx(backend.sent[#backend.sent]:gsub('\r$', '')
        .. '\r\r\n' .. framed('ok') .. '> ')
      serial:update(0)
      for i = 1, 60 do
        backend:rx('tick' .. i .. '\r\n')
        serial:update(0.1)
      end
      local told = table.concat(said, '\n')
      assert.truthy(told:find('f.lua is on the board\ntick1\ntick2\n',
        1, true), told)
      assert.truthy(told:find('tick59\ntick60', 1, true))
      assert.is_nil(told:find('\30', 1, true))
    end)

  --- the end line, the prompt and an on_event's line in one
  --- chunk, just past the wait (Codex round 11, M1)
  it('shows a line that comes with the end line in one piece',
    function()
      local tools = load_tools()
      consoleEcho(tools)
      printingUntilLate(tools)
      backend:rx(framed('ok') .. '> callback fired\r\n')
      serial:update(0.15)
      local told = table.concat(said, '\n')
      assert.truthy(told:find('f.lua is on the board\ncallback fired',
        1, true), told)
    end)

  --- a line that begins as this exec's frame and goes on as no
  --- end line does is the program's own (Codex round 11, m1)
  for _, word in ipairs({ 'oops', 'errands', 'okay' }) do
    it('takes the frame and ' .. word .. ' for the program\'s own',
      function()
        local tools = load_tools()
        consoleEcho(tools)
        printingUntilLate(tools)
        local frame = framed('ok'):match('^\r\n(.-)ok\r\n$')
        backend:rx('\r\n' .. frame .. word .. '\r\n')
        serial:update(0.15)
        local told = table.concat(said, '\n')
        assert.is_nil(told:find('has not said', 1, true))
        assert.is_nil(told:find('is on the board\n', 1, true))
        backend:rx(framed('ok') .. '> ')
        serial:update(0)
        serial:update(0.25)
        told = table.concat(said, '\n')
        assert.truthy(told:find(word, 1, true), told)
        assert.truthy(told:find('f.lua is on the board', 1, true)
          or told:find('has ended', 1, true), told)
      end)
  end

  --- a program that writes a "> " of its own and waits: exec
  --- cannot tell, and echo says the end when it comes
  it('lets echo say the end of a file whose own "> " came first',
    function()
      local tools = load_tools()
      consoleEcho(tools)
      tools.exec('f.lua')
      for _ = 1, 5 do board() end
      backend:rx(backend.sent[#backend.sent]:gsub('\r$', '')
        .. '\r\r\nYour name> ')
      serial:update(0)
      serial:update(0.25)
      assert.truthy(allSaid():find('It may still be running', 1,
        true))
      backend:rx('Ada\r\n' .. framed('ok') .. '> ')
      serial:update(0)
      serial:update(0.3)
      local told = table.concat(said, '\n')
      assert.truthy(told:find('The program on the micro:bit has'
        .. ' ended.', 1, true), told)
      assert.is_nil(told:find('\30', 1, true))
    end)

  --- a file still printing after the wait goes on in echo
  it('hands a file that keeps printing over to echo', function()
    local tools = load_tools()
    tools.exec('f.lua')
    for _ = 1, 5 do board() end
    backend:rx(backend.sent[#backend.sent]:gsub('\r$', '')
      .. '\r\r\n')
    serial:update(0)
    for _ = 1, 7 do
      backend:rx('1\r\n')
      serial:update(1)
    end
    assert.equal('f.lua is on the board and still running',
      said[#said])
    assert.is_nil(port.onBytes)
  end)

  it('waits a minute for a board that says nothing, then stops',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      board()
      said = {}
      for _ = 1, 6 do serial:update(1) end
      assert.truthy(allSaid():find('has not taken line 1', 1,
        true))
      assert.is_not_nil(port.onTick)
      for _ = 1, 55 do serial:update(1) end
      assert.equal(2, sent())
      assert.truthy(allSaid():find('did not take it', 1, true))
      assert.is_nil(port.onBytes)
      assert.is_nil(port.onTick)
    end)

  it('stops when the board takes a line and stops answering',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      board()
      board(nil, '')
      for _ = 1, 6 do serial:update(1) end
      assert.equal(2, sent())
      assert.truthy(allSaid():find('stopped answering', 1, true))
      assert.is_nil(port.onTick)
    end)

  it('stops when the last line never reaches the board', function()
    local tools = load_tools()
    tools.exec('f.lua')
    for _ = 1, 5 do board() end
    for _ = 1, 61 do serial:update(1) end
    assert.truthy(allSaid():find('did not take it', 1, true))
  end)

  --- t_slow on UE174: a sleep, then a line; the line showed only
  --- with the verdict, 2.4 s late
  it('shows what the file prints as it comes, once, and its end',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      for _ = 1, 5 do board() end
      backend:rx(backend.sent[#backend.sent]:gsub('\r$', '')
        .. '\r\r\n')
      serial:update(0)
      serial:update(2.5)
      backend:rx('tick 1\r\n')
      serial:update(0.1)
      assert.equal('tick 1', said[#said])
      assert.is_not_nil(port.onTick)
      backend:rx('tick 2\r\n' .. framed('ok') .. '> ')
      serial:update(0)
      serial:update(0.25)
      local told = table.concat(said, '\n')
      assert.truthy(told:find('tick 1\ntick 2\nf.lua is on the board',
        1, true), told)
      local _, n = told:gsub('tick 1', '')
      assert.equal(1, n)
      assert.is_nil(told:find('\30', 1, true))
    end)

  --- a program that loops never brings the prompt back
  it('hands a file that keeps running over to echo', function()
    local tools = load_tools()
    tools.exec('f.lua')
    for _ = 1, 5 do board() end
    backend:rx(backend.sent[#backend.sent]:gsub('\r$', '')
      .. '\r\r\n1\r\n')
    serial:update(0)
    -- what the file prints shows as it comes
    assert.equal('1', said[#said])
    for _ = 1, 4 do serial:update(1) end
    assert.is_not_nil(port.onBytes)
    serial:update(2)
    assert.equal('f.lua is on the board and still running',
      said[#said])
    local _, ones = table.concat(said, '\n'):gsub('%f[^\n%z]1%f[\n%z]',
      '')
    assert.equal(1, ones)
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
      assert.truthy(allSaid():find('Compile error', 1, true))
      assert.truthy(allSaid():find('before its end, and did not'
        .. ' run it', 1, true))
      assert.truthy(allSaid():find('restart_microbit()', 1, true))
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
    for _ = 1, 61 do serial:update(1) end
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

  --- a refusal in words, as upload's others are: no error
  --- panel with a line number
  it('holds upload and a second exec back while it sends',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      files['MICROBIT.hex'] = ':00000001FF\n'
      said = {}
      assert.has_no_error(function() tools.upload() end)
      assert.has_no_error(function() tools.exec('f.lua') end)
      assert.is_false(flashed)
      assert.equal(1, sent())
      local told = table.concat(said, ' ')
      local _, n = told:gsub('exec is still sending f.lua', '')
      assert.equal(2, n)
      assert.truthy(told:find('restart_microbit() to stop it', 1,
        true))
    end)

  --- its lines would land in the middle of the file exec sends
  --- send waits for each line's prompt as exec does: the
  --- board keeps what comes while it runs a line in 254
  --- characters, and lost the rest (UE174, 20 lines of a sleep
  --- and a print)
  describe('send', function()
    --- the lines of a file of n steps, each a sleep and a print
    local function steps(n)
      local lines = {}
      for i = 1, n do
        lines[i] = ('microbit.sleep(400) print("step %02d")'):format(i)
      end
      return table.concat(lines, '\n') .. '\n'
    end

    it('sends a line once the board has answered the one before,'
      .. ' and leaves echo on', function()
        files['s.lua'] = steps(20)
        local tools = load_tools()
        echoes = {}
        tools.send('s.lua')
        for i = 1, 20 do
          assert.equal(i, sent())
          assert.equal(('microbit.sleep(400) print("step %02d")\r')
            :format(i), backend.sent[i])
          serial:update(0.4)
          assert.equal(i, sent())
          if i < 20 then
            board(('step %02d\r\n'):format(i), '> ')
          end
        end
        -- the last line is sent: send is done once it is taken
        board()
        assert.same({}, echoes)
        assert.is_nil(port.onTick)
        assert.has_no_error(function() tools.exec('f.lua') end)
        assert.equal(21, sent())
      end)

    it('sends a blank line, and a chunk\'s open lines, each after'
      .. ' its prompt', function()
        files['s.lua'] = 'for i = 1, 2 do\n\nprint(i)\nend\n'
        local tools = load_tools()
        tools.send('s.lua')
        board(nil, '>> ')
        board(nil, '>> ')
        board(nil, '>> ')
        assert.same({ 'for i = 1, 2 do\r', '\r', 'print(i)\r',
          'end\r' }, backend.sent)
      end)

    --- a line that loops keeps the board without a prompt
    it('says a line still running, and stops at a minute with the'
      .. ' rest unsent', function()
        files['s.lua'] = 'x = 1\nwhile true do end\nprint(3)\n'
        local tools = load_tools()
        tools.send('s.lua')
        board(nil, '> ')
        board(nil, '')
        said = {}
        for _ = 1, 6 do serial:update(1) end
        assert.truthy(allSaid():find('send: line 2 of 3 of s.lua is'
          .. ' still running; send waits for its end before the next'
          .. ' line, and restart_microbit() stops it.', 1, true))
        assert.is_not_nil(port.onTick)
        for _ = 1, 55 do serial:update(1) end
        assert.truthy(allSaid():find('send stopped at line 2 of 3 of'
          .. ' s.lua: that line was still running after a minute,'
          .. ' and the rest was not sent. Type restart_microbit(),'
          .. ' then try again.', 1, true), allSaid())
        assert.equal(2, sent())
        assert.is_nil(port.onTick)
      end)

    it('says a line the board never takes, in its own name',
      function()
        files['s.lua'] = 'x = 1\n'
        local tools = load_tools()
        tools.send('s.lua')
        said = {}
        for _ = 1, 61 do serial:update(1) end
        local all = allSaid()
        assert.truthy(all:find('send: the board has not taken line 1'
          .. ' of 1 of s.lua yet, and send is still waiting', 1, true),
          all)
        assert.truthy(all:find('send stopped at line 1 of 1 of s.lua:'
          .. ' the board did not take it', 1, true), all)
      end)

    it('holds exec and upload back while it sends', function()
      files['s.lua'] = steps(2)
      local tools = load_tools()
      tools.send('s.lua')
      said = {}
      tools.exec('f.lua')
      assert.equal(1, sent())
      assert.truthy(allSaid():find('send is still sending s.lua', 1,
        true))
    end)
  end)

  it('holds send back while it sends, in the same words',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      local before = sent()
      said = {}
      assert.has_no_error(function() tools.send('f.lua') end)
      assert.equal(before, sent())
      local told = table.concat(said, ' ')
      assert.truthy(told:find('exec is still sending f.lua', 1, true))
      assert.truthy(told:find('restart_microbit() to stop it', 1,
        true))
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

    it('upload says in words to plug the board in when no drive'
      .. ' is found', function()
        local tools = load_tools()
        tools.detect_microbit = function() return nil end
        files['MICROBIT.hex'] = ':00000001FF\n'
        refusedPlainly(function() tools.upload('MICROBIT.hex') end,
          'No micro:bit is plugged in', 'with a data cable',
          'unplug it and plug it', 'then run upload again.')
        assert.is_false(flashed)
      end)

    it('upload says in words why the drive did not take the file',
      function()
        local tools = load_tools()
        tools.flash_microbit = function()
          return nil, 'The micro:bit drive is full.'
        end
        files['MICROBIT.hex'] = ':00000001FF\n'
        refusedPlainly(function() tools.upload() end,
          'The micro:bit drive is full.')
      end)

    it('upload says a damaged hex file is damaged', function()
      local tools = load_tools()
      files['bad.hex'] = ':0000000'
      refusedPlainly(function() tools.upload('bad.hex') end,
        'bad.hex is damaged', 'Copy it onto the Compy again.')
      assert.is_false(flashed)
    end)

    --- a mistake of the tools' own still shows as one
    it('upload lets an error that is no refusal through',
      function()
        local tools = load_tools()
        tools.flash_microbit = function() error('boom') end
        files['MICROBIT.hex'] = ':00000001FF\n'
        local ok, err = pcall(tools.upload)
        assert.is_false(ok)
        assert.truthy(tostring(err):find('boom', 1, true))
      end)

    --- without a board no hex file is written for a script
    it('writes no hex for a lua file without a board', function()
      local tools = load_tools()
      tools.detect_microbit = function() return nil end
      local f = assert(io.open('src/examples/microbit/MICROBIT.hex'))
      files['MICROBIT.hex'] = f:read('*a')
      f:close()
      files['robot.lua'] = 'print(1)\n'
      refusedPlainly(function() tools.upload('robot.lua') end,
        'No micro:bit is plugged in')
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
        -- a short one goes on as a Lua file of another name,
        -- with upload's checks
        assert.truthy(told:find('Give your script another name', 1,
          true))
        assert.truthy(told:find('writefile("mine.lua", readfile("'
          .. script .. '"))', 1, true))
        assert.truthy(told:find('upload("mine.lua")', 1, true))
        assert.is_nil(told:find('embed("mine.hex"', 1, true))
      end)
  end

  --- the firmware the scripts go into
  local function firmware()
    local f = assert(io.open('src/examples/microbit/MICROBIT.hex'))
    files['MICROBIT.hex'] = f:read('*a')
    f:close()
  end

  --- the Compy's own script, taken out with extract, is a Lua
  --- file like any other: the advice upload gives for
  --- MICROBIT.lua puts it on the board as it is
  it('puts the Compy\'s own script back on the way upload says',
    function()
      local tools = load_tools()
      local hex = require('examples.microbit.hex')
      firmware()
      tools.extract()
      local script = files['MICROBIT.lua']
      said = {}
      tools.upload('MICROBIT.lua')
      assert.is_false(flashed)
      local told = table.concat(said, '\n')
      local copy = told:match('writefile%b()')
      local upload = told:match('upload%("mine.lua"%)')
      assert.truthy(copy and upload)
      local sent
      tools.flash_microbit = function(data)
        sent = data
        flashed = true
        return true
      end
      setfenv(assert(loadstring(copy)), tools)()
      setfenv(assert(loadstring(upload)), tools)()
      assert.is_true(flashed)
      assert.equal(script, hex.script(hex.parse(sent)))
    end)

  --- the advice for MICROBIT.lua takes the place of no file
  it('names a Lua file the project does not use yet for'
    .. ' MICROBIT.lua', function()
      local tools = load_tools()
      files['MICROBIT.lua'] = 'print(1)\n'
      files['mine.lua'] = 'my own\n'
      files['mine2.hex'] = ':00000001FF\n'
      said = {}
      tools.upload('MICROBIT.lua')
      local told = table.concat(said, ' ')
      assert.truthy(told:find('writefile("mine3.lua", readfile('
        .. '"MICROBIT.lua"))', 1, true))
      assert.truthy(told:find('upload("mine3.lua")', 1, true))
      assert.equal('my own\n', files['mine.lua'])
    end)

  it('says only that there is no MICROBIT.lua when there is none',
    function()
      local tools = load_tools()
      refusedPlainly(function() tools.upload('microbit.lua') end,
        'This project has no file called microbit.lua.')
      assert.is_nil(table.concat(said, ' '):find('would overwrite', 1,
        true))
    end)

  --- embed is the other way onto the board: it checks the file
  --- as upload does
  it('embed refuses a file upload would refuse', function()
    local tools = load_tools()
    firmware()
    for name, text in pairs({ ['bad.lua'] = 'x = = 1\n',
      ['blank.lua'] = '\n', ['hash.lua'] = '#!/bin/lua\nx = 1\n' }) do
      files[name] = text
      said = {}
      assert.has_no_error(function() tools.embed('mine.hex', name) end)
      assert.is_nil(files['mine.hex'], name)
      assert.truthy(table.concat(said, ' '):find(name, 1, true))
    end
  end)

  it('extract will not write over the firmware', function()
    local tools = load_tools()
    firmware()
    local shipped = files['MICROBIT.hex']
    refusedPlainly(function()
      tools.extract('MICROBIT.hex', 'microbit.HEX')
    end, 'MICROBIT.hex is the robots\' firmware and is never written',
      'extract("MICROBIT.hex", "mine.lua")')
    assert.equal(shipped, files['MICROBIT.hex'])
  end)

  --- the name was right: the project lacks the firmware
  it('says what a project without MICROBIT.hex needs', function()
    local tools = load_tools()
    files['x.lua'] = 'print(1)\n'
    for _, call in ipairs({
      function() tools.upload() end,
      function() tools.upload('x.lua') end,
      function() tools.embed('mine.hex', 'x.lua') end,
    }) do
      refusedPlainly(call, 'This project has no MICROBIT.hex, which'
        .. ' upload and', 'clone("microbit", "myboard")')
    end
    assert.is_nil(files['x.hex'])
    assert.is_nil(files['mine.hex'])
    assert.is_false(flashed)
  end)

  --- UE174: a line longer than the console, 64 wide, breaks
  --- mid-word; the tools break their long ones between words
  it('says nothing wider than the console', function()
    local name = 'a_long_program_name_for_the_board.lua'
    files[name] = 'x = 1\n'
    local tools = load_tools()
    said = {}
    tools.exec(name)
    for _ = 1, 61 do serial:update(1) end
    tools.exec(name)
    for _ = 1, 4 do board() end
    board('1\r\n', '> ')
    serial:update(0.25)
    backend.refuse = 'break -1'
    tools.restart_microbit()
    backend:detach()
    serial:update(0)
    tools.exec(name)
    files['MICROBIT.hex'] = nil
    tools.upload('x.lua')
    assert.truthy(#said > 10)
    for _, line in ipairs(said) do
      assert.is_true(#line <= 64, line)
    end
    local all = allSaid()
    assert.truthy(all:find('did not take it', 1, true))
    assert.truthy(all:find('has not said how ' .. name, 1, true))
    assert.truthy(all:find('did not restart', 1, true))
    assert.truthy(all:find('No micro:bit is plugged in', 1, true))
  end)

  it('says in words that a command needs a file name', function()
    local tools = load_tools()
    for _, call in ipairs({
      function() tools.exec() end,
      function() tools.send() end,
      function() tools.upload(42) end,
      function() tools.hexmap(42) end,
      function() tools.embed('mine.hex', 42) end,
    }) do
      refusedPlainly(call, 'Name the file in quotes, such as'
        .. ' "blink.lua".')
    end
    --- a file to write, named wrong (Codex round 11, M3)
    refusedPlainly(function() tools.embed(4) end,
      'Name the file to write, such as embed("mine.hex").')
    refusedPlainly(function() tools.extract('MICROBIT.hex', 4) end,
      'Name the file to write, such as extract("MICROBIT.hex",'
      .. ' "mine.lua").')
    assert.equal(0, sent())
    assert.is_false(flashed)
  end)

  --- the card does not tell microbit.hex from MICROBIT.hex
  it('embed will not write microbit.hex in any case', function()
    local tools = load_tools()
    firmware()
    local shipped = files['MICROBIT.hex']
    files['x.lua'] = 'print(1)\n'
    for _, name in ipairs({ 'MICROBIT.hex', 'microbit.hex',
      'MicroBit.HEX' }) do
      refusedPlainly(function() tools.embed(name, 'x.lua') end,
        'MICROBIT.hex is the robots\' firmware and is never',
        'embed("mine.hex")')
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

  --- A Lua file upload makes the file the board's whole
  --- program, in place of the Compy's own script (00a5ad02):
  --- the board runs it at every start, and has a prompt only
  --- when the file makes one.
  describe('a lua file upload', function()
      local hex = require('examples.microbit.hex')

      --- The room the bundled firmware has for a script: the
      --- largest file upload takes
      --- @return integer
      local function room()
        local f = assert(io.open('src/examples/microbit/MICROBIT.hex'))
        local blocks = hex.parse(f:read('*a'))
        f:close()
        return hex.room(hex.meta(blocks))
      end

      --- The program a hex file carries
      --- @param data string a hex file
      --- @return string
      local function program(data)
        return hex.script(hex.parse(data))
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

      before_each(firmware)

      --- what the board runs, the way the Compy's own lessons
      --- write it
      local SAMPLES = {
        'require("microbit.serial")\n'
          .. 'microbit.serial.send("blink-ok\\r\\n")\n',
        'require("microbit")\nrequire("microbit.display")\n'
          .. 'while true do\n  microbit.display.scroll("hi")\n'
          .. '  microbit.sleep(500)\nend\n',
        'require("tpbot")\n'
          .. 'robot_move(50, 50, 1)\nturn(3)\nstraight(2)\n',
        'require("microbit")\nrequire("microbit.display")\n'
          .. 'function on_event(source, value)\n'
          .. '  if source == microbit.DEVICE_ID_BUTTON_A then\n'
          .. '    microbit.display.scroll("A")\n  end\nend\n',
      }

      for _, text in ipairs(SAMPLES) do
        it('makes the file the board\'s program, byte for byte ('
          .. text:match('^[^\n]*') .. ')', function()
            local tools = load_tools()
            files['robot.lua'] = text
            local sent = uploaded(tools)
            assert.is_true(flashed)
            assert.equal(files['robot.hex'], sent)
            assert.equal(text, program(sent))
          end)

        --- the board's Lua is 5.1 itself, stricter than LuaJIT
        it('builds a program the board\'s Lua reads ('
          .. text:match('^[^\n]*') .. ')', function()
            local compiler = luac()
            if not compiler then
              pending('luac5.1 is not installed')
              return
            end
            local tools = load_tools()
            files['robot.lua'] = text
            uploaded(tools)
            assert.equal('', luacSays(compiler,
              program(files['robot.hex'])))
          end)
      end

      it('puts the board\'s own line endings in', function()
        local tools = load_tools()
        files['robot.lua'] = 'x = 1\r\ny = 2\rprint(x + y)\n'
        uploaded(tools)
        assert.equal('x = 1\ny = 2\nprint(x + y)\n',
          program(files['robot.hex']))
      end)

      --- a file with a syntax error would stop the board at
      --- every start
      for _, case in ipairs({
        { 'x = = 1\n', '1' },
        { 'print("one")\nprint(\n', '3' },
        { 'for i = 1, 3 do\n  print(i)\n', '3' },
      }) do
        it('refuses a file with a mistake, naming its line ('
          .. case[1]:gsub('\n', ' ') .. ')', function()
            local tools = load_tools()
            files['robot.lua'] = case[1]
            said = {}
            assert.has_no_error(function() uploaded(tools) end)
            assert.is_false(flashed)
            assert.is_nil(files['robot.hex'])
            local told = table.concat(said, ' ')
            assert.truthy(told:find('robot.lua has a mistake on line '
              .. case[2] .. ':', 1, true))
            assert.truthy(told:find('every time it starts', 1, true))
            assert.truthy(told:find('edit("robot.lua")', 1, true))
          end)
      end

      --- LuaJIT skips both; the board's Lua 5.1 does not
      it('refuses a file that begins with a byte order mark, and'
        .. ' the words take it off', function()
          local tools = load_tools()
          files['robot.lua'] = '\239\187\191print(1)\n'
          said = {}
          uploaded(tools)
          assert.is_false(flashed)
          assert.is_nil(files['robot.hex'])
          local told = table.concat(said, '\n')
          assert.truthy(told:find('robot.lua begins with an invisible'
            .. ' mark', 1, true))
          local off = assert(told:match('writefile%b()'))
          setfenv(assert(loadstring(off)), tools)()
          uploaded(tools)
          assert.is_true(flashed)
          assert.equal('print(1)\n', program(files['robot.hex']))
        end)

      it('refuses a file whose first line starts with #', function()
        local tools = load_tools()
        files['robot.lua'] = '#!/usr/bin/lua\nprint(1)\n'
        said = {}
        uploaded(tools)
        assert.is_false(flashed)
        assert.is_nil(files['robot.hex'])
        local told = table.concat(said, ' ')
        assert.truthy(told:find('begins with a line that starts with'
          .. ' #', 1, true))
        assert.truthy(told:find('edit("robot.lua")', 1, true))
      end)

      --- no margin under the firmware's room: memory is the
      --- program's to spend, and a sad face with 020 says it ran out
      it('takes a file as long as the firmware has room for',
        function()
          local tools = load_tools()
          local most = room()
          local tail = 'print("end")\n'
          local code = ('-- a comment line\n'):rep(math.floor(
            (most - #tail) / 18)) .. tail
          code = (' '):rep(most - #code) .. code
          assert.equal(most, #code)
          files['robot.lua'] = code
          uploaded(tools)
          assert.is_true(flashed)
          assert.equal(code, program(files['robot.hex']))
        end)

      --- CRs go before the file is measured
      it('measures a file with CRLF endings as the board reads it',
        function()
          local tools = load_tools()
          local code = ('x = 1\n'):rep(math.floor(room() / 6))
          files['robot.lua'] = code:gsub('\n', '\r\n')
          assert.is_true(room() < #files['robot.lua'])
          uploaded(tools)
          assert.is_true(flashed)
        end)

      it('refuses a file one byte longer than the room, in words',
        function()
          local tools = load_tools()
          local most = room()
          files['robot.lua'] = ('-'):rep(most + 1)
          said = {}
          assert.has_no_error(function() uploaded(tools) end)
          assert.is_false(flashed)
          assert.is_nil(files['robot.hex'])
          local told = table.concat(said, ' ')
          assert.is_nil(told:find('%.lua:%d+:'), told)
          assert.truthy(told:find(('robot.lua is %d bytes, and'
            .. ' MICROBIT.hex has room for %d.'):format(most + 1, most),
            1, true))
          assert.truthy(told:find('Make it shorter', 1, true))
        end)

      --- UE174 at 44305c21: the note came before the file was
      --- read; it belongs once the board has taken it
      it('says what a board out of memory shows once the board has'
        .. ' taken a Lua file, and not before', function()
          local tools = load_tools()
          local hooks
          tools.flash_microbit = function(_, on)
            hooks = on
            flashed = true
            return true
          end
          files['robot.lua'] = 'print("robot")\n'
          said = {}
          tools.upload('robot.lua')
          assert.is_nil(table.concat(said, ' '):find('020', 1, true))
          tools.print('The micro:bit took the file.')
          hooks.took()
          local told = table.concat(said, ' ')
          assert.truthy(told:find('The micro:bit took the file. A sad'
            .. ' face and 020 on the micro:bit mean your program ran out'
            .. ' of the board\'s memory; upload() puts the Compy\'s'
            .. ' firmware back.', 1, true), told)
        end)

      it('says nothing of memory for a firmware file, or a refused'
        .. ' Lua file', function()
          local tools = load_tools()
          said = {}
          tools.upload()
          files['robot.lua'] = ''
          uploaded(tools)
          assert.is_nil(table.concat(said, ' '):find('020', 1, true))
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
        local _, n = table.concat(said, '\n'):gsub('written', '')
        assert.equal(1, n)
        assert.equal('robot.hex written', said[1])
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
        assert.truthy(told:find('The lines above say why', 1, true))
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
          said = {}
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
          assert.equal(files['robot.lua'], program(sent))
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
        assert.equal(files['robot.lua'], program(sent))
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
    assert.truthy(told:find('upload() puts the Compy\'s firmware'
      .. ' back', 1, true))
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
      assert.truthy(allSaid():find('the board was restarted', 1,
        true))
      assert.is_nil(port.onBytes)
      assert.is_nil(port.onTick)
    end)

  it('a refused restart_microbit still turns echo on', function()
    local tools = load_tools()
    tools.echo(false)
    echoes = {}
    backend.refuse = 'break -1, end -1'
    assert.has_no_error(function() tools.restart_microbit() end)
    assert.same({ true }, echoes)
  end)

  it('restart_microbit refused while exec sends says so',
    function()
      local tools = load_tools()
      tools.exec('f.lua')
      board()
      said = {}
      backend.refuse = 'break -1, end -1'
      assert.has_no_error(function() tools.restart_microbit() end)
      assert.truthy(allSaid():find('did not restart', 1, true))
      assert.is_nil(port.onTick)
    end)

  it('restart_microbit says to press the button when refused', function()
    local tools = load_tools()
    backend.refuse = 'break -1'
    refusedPlainly(function() tools.restart_microbit() end,
      'The micro:bit did not restart. Press its reset button')
  end)

  it('a board that stops answering points to restart_microbit', function()
    local tools = load_tools()
    tools.exec('f.lua')
    board()
    said = {}
    for _ = 1, 6 do serial:update(1) end
    assert.truthy(allSaid():find('restart_microbit()', 1, true))
  end)

  it('says in words to plug the board in while none is connected',
    function()
      local tools = load_tools()
      backend:detach()
      serial:update(0)
      for command, call in pairs({
        ['exec'] = function() tools.exec('f.lua') end,
        ['send'] = function() tools.send('f.lua') end,
        ['restart_microbit()'] = tools.restart_microbit,
      }) do
        refusedPlainly(call, 'No micro:bit is plugged in',
          'with a data cable', 'then run ' .. command .. ' again.')
      end
      assert.equal(0, sent())
      assert.equal(0, backend.resets)
    end)

  it('says in words that a file is not in the project', function()
    local tools = load_tools()
    firmware()
    --- the console says nothing of the missing file itself
    local loud = 0
    tools.readfile = function(name, quiet)
      if not files[name] and not quiet then loud = loud + 1 end
      return files[name]
    end
    for _, call in ipairs({
      function() tools.exec('none.lua') end,
      function() tools.send('none.lua') end,
      function() tools.upload('none.lua') end,
      function() tools.hexmap('none.lua') end,
      function() tools.extract('none.lua') end,
      function() tools.embed('mine.hex', 'none.lua') end,
    }) do
      refusedPlainly(call,
        'This project has no file called none.lua.',
        'Check the name, then try again.')
    end
    assert.equal(0, loud)
    assert.equal(0, sent())
    assert.is_false(flashed)
  end)

  it('says in words that a hex file is damaged', function()
    local tools = load_tools()
    files['bad.hex'] = ':0000000'
    for _, call in ipairs({
      function() tools.hexmap('bad.hex') end,
      function() tools.extract('bad.hex') end,
    }) do
      refusedPlainly(call, 'bad.hex is damaged')
    end
    files['MICROBIT.hex'] = ':1000'
    files['x.lua'] = 'print(1)\n'
    refusedPlainly(function() tools.embed('mine.hex', 'x.lua') end,
      'MICROBIT.hex is damaged')
    refusedPlainly(function() tools.upload('x.lua') end,
      'MICROBIT.hex is damaged')
    assert.is_nil(files['mine.hex'])
    assert.is_false(flashed)
  end)

  it('says in words that a hex file has no place for Lua',
    function()
      local tools = load_tools()
      files['plain.hex'] = ':00000001FF\n'
      refusedPlainly(function() tools.extract('plain.hex') end,
        'plain.hex has no place for a Lua program')
      assert.is_nil(files['MICROBIT.lua'])
    end)

  --- metadata cut short before its space word (Codex round 11,
  --- M4, its truncated-metadata.hex)
  it('says in words that firmware with metadata cut short has no'
    .. ' place for Lua', function()
      local tools = load_tools()
      files['MICROBIT.hex'] = ':020000040000FA\n'
        .. ':100000003141554C64000000650000000100000013\n'
        .. ':01006400207B\n:00000001FF\n'
      files['x.lua'] = 'print(1)\n'
      refusedPlainly(function() tools.hexmap() end,
        'no Lua script inside')
      refusedPlainly(function() tools.embed('mine.hex', 'x.lua') end,
        'MICROBIT.hex has no place for a Lua program')
      refusedPlainly(function() tools.upload('x.lua') end,
        'MICROBIT.hex has no place for a Lua program')
      assert.is_nil(files['mine.hex'])
      assert.is_false(flashed)
    end)

  it('embed says in words what it needs', function()
    local tools = load_tools()
    firmware()
    refusedPlainly(function() tools.embed() end,
      'Name the file to write, such as embed("mine.hex").')
    files['big.lua'] = ('-'):rep(300000)
    refusedPlainly(function() tools.embed('mine.hex', 'big.lua') end,
      'big.lua is 300000 bytes, and MICROBIT.hex has room for',
      'Make it shorter')
    assert.is_nil(files['mine.hex'])
  end)
end)
