--- The board's output read by transfers kept in the kernel:
--- what comes back is handed on in order and posted again,
--- and reads that stop leave the output to the next reader
--- only once none is left in the kernel.

require('model.serial.serial_in')

local EP = 0x84

--- The kernel as SerialIn sees it: posted transfers, of
--- which the test finishes some
local function kernel()
  local k = { posted = 0, done = {}, logs = {} }
  k.io = {
    submit = function(_, ep, size)
      assert.same(EP, ep)
      assert.same(SerialIn.SIZE, size)
      if k.refuse then return nil, 'submit errno 19' end
      k.posted = k.posted + 1
      return true
    end,
    reap = function()
      if k.reapError then return nil, k.reapError end
      return table.remove(k.done, 1)
    end,
  }
  --- the chip answers n transfers, each with data
  function k.answer(...)
    for _, data in ipairs({ ... }) do
      assert.is_true(k.posted > 0, 'a transfer answered unposted')
      k.posted = k.posted - 1
      k.done[#k.done + 1] = { endpoint = EP, status = 0,
        actual = #data, data = data }
    end
  end
  function k.fail(status)
    k.posted = k.posted - 1
    k.done[#k.done + 1] = { endpoint = EP, status = status,
      actual = 0 }
  end
  k.log = function(line) k.logs[#k.logs + 1] = line end
  return k
end

describe('SerialIn #serial', function()
  it('posts COUNT transfers and keeps them posted', function()
    local k = kernel()
    local reads = SerialIn.new(k.io, EP, k.log)
    assert.is_true(reads:start())
    assert.same(SerialIn.COUNT, k.posted)
    k.answer('ab', 'c', 'de')
    assert.same('abcde', reads:take())
    assert.same(SerialIn.COUNT, k.posted)
    assert.same('', reads:take())
  end)

  it('says how many came back between two polls as it doubles,'
    .. ' and the first time all did', function()
      local k = kernel()
      local reads = SerialIn.new(k.io, EP, k.log)
      reads:start()
      for _ = 1, 15 do k.answer('x') end
      reads:take()
      assert.same({}, k.logs)
      for _ = 1, 40 do k.answer('x') end
      reads:take()
      for _ = 1, 50 do k.answer('x') end
      reads:take()
      assert.same({ '40 serial reads came back between two polls,'
        .. ' of ' .. SerialIn.COUNT }, k.logs)
      for _ = 1, 2 do
        for _ = 1, SerialIn.COUNT do k.answer('x') end
        reads:take()
      end
      assert.same(2, #k.logs)
      assert.truthy(k.logs[2]:find('output may have been lost', 1,
        true))
    end)

  it('posts no failed transfer again, and stops when none is'
    .. ' left', function()
      local k = kernel()
      local reads = SerialIn.new(k.io, EP, k.log)
      reads:start()
      k.fail(-71)
      k.answer('a')
      assert.same('a', reads:take())
      assert.same(SerialIn.COUNT - 1, k.posted)
      for _ = 1, SerialIn.COUNT - 1 do k.fail(-108) end
      assert.same('', reads:take())
      assert.is_nil(reads:take())
      assert.same({ 'serial read status -71',
        'serial reads stopped: ' .. SerialIn.COUNT
        .. ' reads failed, the last with status -108' },
        { k.logs[1], k.logs[2] })
    end)

  it('takes what is still in the kernel once posting fails,'
    .. ' then gives the output up', function()
      local k = kernel()
      local reads = SerialIn.new(k.io, EP, k.log)
      reads:start()
      k.refuse = true
      k.answer('a', 'b')
      assert.same('ab', reads:take())
      assert.same(SerialIn.COUNT - 2, k.posted)
      for _ = 1, SerialIn.COUNT - 2 do k.answer('c') end
      assert.same(('c'):rep(SerialIn.COUNT - 2), reads:take())
      assert.is_nil(reads:take())
    end)

  it('gives the output up at once when reaping fails', function()
    local k = kernel()
    local reads = SerialIn.new(k.io, EP, k.log)
    reads:start()
    k.reapError = 'reap errno 19'
    assert.same('', reads:take())
    assert.is_nil(reads:take())
  end)

  it('keeps what it posted before a refusal', function()
    local k = kernel()
    local reads = SerialIn.new(k.io, EP, k.log)
    local submit = k.io.submit
    k.io.submit = function(io, ep, size)
      if k.posted == 3 then return nil, 'submit errno 12' end
      return submit(io, ep, size)
    end
    local ok, err = reads:start()
    assert.is_nil(ok)
    assert.same('submit errno 12', err)
    assert.same(3, reads.posted)
    k.answer('x', 'y', 'z')
    assert.same('xyz', reads:take())
    assert.is_nil(reads:take())
  end)
end)
