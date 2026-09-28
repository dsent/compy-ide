require('model.serial.init')
require('model.serial.backend_fake')

local function make()
  local b = FakeBackend.new()
  return Serial.new(b), b
end

describe('Serial', function()
  it('mutes the console while a program runs', function()
    local s, b = make()
    local heard = {}
    s:table_for('console').onBytes = function(c)
      heard[#heard + 1] = c
    end
    b:attach({ name = 'mb' })
    s:update(0)
    b:rx('one')
    s:update(0)
    assert.same({ 'one' }, heard)

    s:programStarted()
    b:rx('two')
    s:update(0)
    assert.same({ 'one' }, heard)

    s:programEnded()
    b:rx('three')
    s:update(0)
    assert.same({ 'one', 'three' }, heard)
  end)

  it('hears again when the program falls idle', function()
    local s, b = make()
    local heard = {}
    s:table_for('console').onBytes = function(c)
      heard[#heard + 1] = c
    end
    local kept = function() end
    b:attach({ name = 'mb' })
    s:update(0)

    s:programStarted()
    s:table_for('program').onBytes = kept
    b:rx('one')
    s:update(0)
    assert.same({}, heard)

    s:programIdle()
    b:rx('two')
    s:update(0)
    assert.same({ 'two' }, heard)
    assert.equal(kept, s:table_for('program').onBytes)
  end)

  it('starts disconnected', function()
    local s = make()
    assert.is_false(s:isConnected())
    local ok, err = s:send('PING')
    assert.is_nil(ok)
    assert.same('no device connected', err)
  end)

  it('connects on attach, fires on update', function()
    local s, b = make()
    local info
    s:table_for('console').onConnect = function(i) info = i end
    b:attach({ name = 'mb' })
    assert.is_true(s:isConnected())
    assert.is_nil(info)
    s:update()
    assert.same('mb', info.name)
  end)

  it('sends the line as given', function()
    local s, b = make()
    b:attach()
    assert.is_true(s:send('COMMAND 41 M 40 40 1000\r'))
    assert.same({ 'COMMAND 41 M 40 40 1000\r' }, b.sent)
  end)

  it('adds no terminator of its own', function()
    local s, b = make()
    b:attach()
    assert.is_true(s:send('PING'))
    assert.same({ 'PING' }, b.sent)
  end)

  it('assembles lines across reads', function()
    local s, b = make()
    local got = {}
    s:table_for('console').onLine = function(l) got[#got + 1] = l end
    b:attach()
    b:rx('ACK ')
    b:rx('41\nACK 42\n')
    s:update()
    assert.same({ 'ACK 41', 'ACK 42' }, got)
  end)

  it('passes raw chunks through', function()
    local s, b = make()
    local got = {}
    s:table_for('console').onBytes = function(c) got[#got + 1] = c end
    b:attach()
    b:rx('AC')
    b:rx('K 41\n')
    s:update()
    assert.same({ 'AC', 'K 41\n' }, got)
  end)

  it('sends bytes before the lines built from them', function()
    local s, b = make()
    local order = {}
    s:table_for('console').onBytes = function() order[#order + 1] = 'b' end
    s:table_for('console').onLine = function() order[#order + 1] = 'l' end
    b:attach()
    b:rx('OK\n')
    s:update()
    assert.same({ 'b', 'l' }, order)
  end)

  it('drops a partial line on detach', function()
    local s, b = make()
    local got = {}
    s:table_for('console').onLine = function(l) got[#got + 1] = l end
    b:attach()
    b:rx('PART')
    b:detach()
    b:attach()
    b:rx('OK\n')
    s:update()
    assert.same({ 'OK' }, got)
  end)

  it('reports disconnect', function()
    local s, b = make()
    local down = false
    s:table_for('console').onDisconnect = function() down = true end
    b:attach()
    b:detach()
    s:update()
    assert.is_true(down)
    assert.is_false(s:isConnected())
  end)

  it('mutes a paused program, not the console', function()
    local s, b = make()
    local con, prg = {}, {}
    s:table_for('console').onLine = function(l) con[#con + 1] = l end
    s:table_for('program').onLine = function(l) prg[#prg + 1] = l end
    b:attach()
    s:programPaused()
    b:rx('A\n')
    s:update()
    assert.same({ 'A' }, con)
    assert.same({}, prg)
  end)

  it('resumes without replaying the gap', function()
    local s, b = make()
    local prg = {}
    s:table_for('program').onLine = function(l) prg[#prg + 1] = l end
    b:attach()
    s:programPaused()
    b:rx('MISSED\n')
    s:update()
    s:programContinued()
    b:rx('B\n')
    s:update()
    assert.same({ 'B' }, prg)
  end)

  it('clears a paused program that ended', function()
    local s, b = make()
    local n = 0
    s:table_for('program').onLine = function() n = n + 1 end
    s:programPaused()
    s:programEnded()
    s:table_for('program').onLine = function() n = n + 10 end
    b:attach()
    b:rx('X\n')
    s:update()
    assert.same(10, n)
  end)

  it('keeps delivering after a handler fails', function()
    local s, b = make()
    local reached = false
    s:table_for('program').onLine = function() error('boom') end
    s:table_for('console').onLine = function() reached = true end
    b:attach()
    b:rx('X\n')
    local errors = s:update()
    assert.is_true(reached)
    assert.same(1, #errors)
  end)
end)

describe('Serial faults', function()
  it('reports overlong input through update', function()
    local b = FakeBackend.new()
    local s = Serial.new(b, 4)
    b:attach()
    b:rx('TOOLONG\n')
    local errors = s:update()
    assert.same(1, #errors)
    assert.same('serial', errors[1].env)
  end)
end)

describe('Serial backend faults', function()
  it('surfaces a backend fault through update', function()
    local s, b = make()
    b:attach()
    b:breaks('extra micro:bit ignored')
    local errors = s:update()
    assert.same(1, #errors)
    assert.same('serial', errors[1].env)
    assert.same('extra micro:bit ignored', errors[1].err)
  end)

  it('polls the backend once per update', function()
    local s, b = make()
    b:attach()
    b:breaks('once')
    assert.same(1, #s:update())
    assert.same(0, #s:update())
  end)
end)

--- What was sent and has not left yet would reach the board
--- where it no longer makes sense
describe('Serial unsent output', function()
  it('goes from the backend on drop', function()
    local s, b = make()
    b:attach()
    s:drop()
    assert.same(1, b.drops)
  end)

  --- the IDE drops it where a run stops, around its hooks
  it('stays through the program\'s own states', function()
    local s, b = make()
    b:attach()
    s:programStarted()
    s:programIdle()
    s:programPaused()
    s:programContinued()
    s:programEnded()
    assert.same(0, b.drops)
  end)

  it('leaves the Android queue empty when dropped', function()
    require('model.serial.backend_android')
    local b = AndroidBackend.new()
    b.state = 'open'
    assert.is_true(b:send('print(1)\r'))
    assert.same('print(1)\r', b.tx)
    b:drop()
    assert.same('', b.tx)
  end)
end)

--- Time passing, for a wait on the board that has to end when
--- it stops answering
describe('Serial ticks', function()
  it('tick every update with the seconds since the last',
    function()
      local s = make()
      local ticks = {}
      s:table_for('console').onTick = function(dt)
        ticks[#ticks + 1] = dt
      end
      s:update(0.5)
      s:update(0.25)
      assert.same({ 0.5, 0.25 }, ticks)
    end)

  it('come after the bytes of the same update', function()
    local s, b = make()
    local heard = {}
    local t = s:table_for('program')
    t.onBytes = function() heard[#heard + 1] = 'bytes' end
    t.onTick = function() heard[#heard + 1] = 'tick' end
    b:attach()
    s:update(0)
    heard = {}
    b:rx('> ')
    s:update(0.1)
    assert.same({ 'bytes', 'tick' }, heard)
  end)

  it('skip a suspended environment', function()
    local s = make()
    local ticks = { console = 0, program = 0 }
    for env in pairs(ticks) do
      s:table_for(env).onTick = function()
        ticks[env] = ticks[env] + 1
      end
    end
    s:programStarted()
    s:update(0.1)
    assert.same({ console = 0, program = 1 }, ticks)
  end)
end)

describe('Serial tick faults', function()
  it('take a failing tick handler off after one error', function()
    local s = make()
    local t = s:table_for('console')
    t.onTick = function() error('boom') end
    local errors = s:update(0.1)
    assert.same(1, #errors)
    assert.truthy(errors[1].err:find('onTick is taken off', 1, true))
    assert.is_nil(t.onTick)
    assert.same(0, #s:update(0.1))
  end)

  it('keep a failing bytes handler', function()
    local s, b = make()
    local t = s:table_for('console')
    local fail = function() error('boom') end
    t.onBytes = fail
    b:attach()
    b:rx('x')
    s:update(0)
    assert.equal(fail, t.onBytes)
  end)
end)
