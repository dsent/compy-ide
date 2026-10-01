require('model.serial.dispatcher')

describe('Dispatcher', function()
  it('keeps event order', function()
    local d = Dispatcher.new()
    local got = {}
    local t = d:table_for('console')
    t.onLine = function(l) got[#got + 1] = l end
    d:push('line', 'A')
    d:push('line', 'B')
    d:pump()
    assert.same({ 'A', 'B' }, got)
  end)

  it('waits for pump', function()
    local d = Dispatcher.new()
    local got = {}
    d:table_for('console').onLine = function(l)
      got[#got + 1] = l
    end
    d:push('line', 'A')
    assert.same({}, got)
  end)

  it('reads the field at delivery, not at assignment',
  function()
    local d = Dispatcher.new()
    local t = d:table_for('console')
    local got = {}
    t.onLine = function() got[#got + 1] = 'old' end
    d:push('line', 'X')
    t.onLine = function() got[#got + 1] = 'new' end
    d:pump()
    assert.same({ 'new' }, got)
  end)

  --- the microbit tools' exec hears the board in the program's
  --- table and turns the console's echo on as it ends: the
  --- chunk it ended on never reaches the echo too
  it('goes to the console first, then the program', function()
    local d = Dispatcher.new()
    local console = d:table_for('console')
    local got = {}
    d:table_for('program').onBytes = function(b)
      got[#got + 1] = 'program ' .. b
      console.onBytes = function(c) got[#got + 1] = 'console ' .. c end
    end
    d:push('bytes', 'A')
    d:push('bytes', 'B')
    d:pump()
    assert.same({ 'program A', 'console B', 'program B' }, got)
  end)

  it('a nil field delivers nothing', function()
    local d = Dispatcher.new()
    d:push('line', 'X')
    assert.same({}, d:pump())
  end)

  it('clears one env only', function()
    local d = Dispatcher.new()
    local con, prg = 0, 0
    d:table_for('console').onLine = function() con = con + 1 end
    d:table_for('program').onLine = function() prg = prg + 1 end
    d:clear_env('program')
    d:push('line', 'X')
    d:pump()
    assert.same(1, con)
    assert.same(0, prg)
  end)

  it('clearing keeps the non-handler fields', function()
    local d = Dispatcher.new()
    local t = d:table_for('program')
    t.send = function() return true end
    t.onLine = function() end
    d:clear_env('program')
    assert.is_nil(t.onLine)
    assert.is_function(t.send)
  end)

  it('suspends without touching the table', function()
    local d = Dispatcher.new()
    local prg = 0
    d:table_for('program').onLine = function() prg = prg + 1 end
    d:suspend_env('program')
    d:push('line', 'X')
    d:pump()
    assert.same(0, prg)
    d:resume_env('program')
    d:push('line', 'Y')
    d:pump()
    assert.same(1, prg)
  end)

  it('survives a failing handler', function()
    local d = Dispatcher.new()
    local reached = false
    d:table_for('program').onLine = function() error('boom') end
    d:table_for('console').onLine = function() reached = true end
    d:push('line', 'X')
    local errors = d:pump()
    assert.is_true(reached)
    assert.same(1, #errors)
    assert.same('program', errors[1].env)
  end)

  it('defers what a handler pushes', function()
    local d = Dispatcher.new()
    local got = {}
    d:table_for('console').onLine = function(l)
      got[#got + 1] = l
      if l == 'A' then d:push('line', 'B') end
    end
    d:push('line', 'A')
    d:pump()
    assert.same({ 'A' }, got)
    d:pump()
    assert.same({ 'A', 'B' }, got)
  end)

  it('rejects unknown names', function()
    local d = Dispatcher.new()
    assert.has_error(function() d:push('noise') end)
    assert.has_error(function() d:table_for('kernel') end)
  end)
end)

describe('Dispatcher env checks', function()
  it('rejects an unknown env on suspend and resume', function()
    local d = Dispatcher.new()
    assert.has_error(function() d:suspend_env('kernel') end)
    assert.has_error(function() d:resume_env('kernel') end)
  end)
end)
