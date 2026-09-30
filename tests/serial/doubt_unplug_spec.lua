--- A flash that learns the board's id itself, on a board whose
--- id the port did not give, and an unplug past the erase: the
--- doubt goes with the id the flash learned, so a success on
--- that board ends it, and another board is not in doubt
--- (Codex round 11, M2, from its disconnect-identity probe).
--- The Android backend runs as it does on a Compy, over a fake
--- DAPLink, with its JNI calls answered here.

package.preload['utf8'] = package.preload['utf8']
    or function() return { len = function(s) return #s end } end

require('model.serial.init')
require('model.serial.backend_android')
local F = require('tests.helpers.fake_daplink')

local function quiet() end

local STUBBED = { jniDropGlobal = quiet,
  jniCallBool = function() return true end, jniCallVoid = quiet }

describe('Serial doubt across an unplug #microbit', function()
  local saved, log

  before_each(function()
    saved = {}
    for name, stub in pairs(STUBBED) do
      saved[name] = _G[name]
      _G[name] = stub
    end
    log = Dap.log
    Dap.log = quiet
  end)

  after_each(function()
    for name in pairs(STUBBED) do _G[name] = saved[name] end
    Dap.log = log
  end)

  it('keeps the doubt with the id the flash learned, and lets a'
    .. ' success on that board end it', function()
      local chip = F.chip({ latency = 0.001, id = '9904AAAAAAAA' })
      local b = AndroidBackend.new()
      b.start = function(self, sink)
        self.sink = sink
        self.state = 'idle'
      end
      b.read = function() return '' end
      b.write = quiet
      b.answers = function() return true end
      b.present = function() return not chip.gone end
      b.openDevice = function()
        local link = DapLink.new(F.bus(chip), 5, 0x85, quiet,
          function() return chip.now end)
        link:start()
        return { link = link, storageTaken = true, claimed = false,
          msc = 'drive' }
      end
      b.serialOf = function() return nil end
      local s = Serial.new(b)
      s.clock = function() return chip.now end

      local function plug()
        b.dev = { name = 'modeled CDC device', dev = 'dev' }
        assert.is_falsy((b:openReady()))
        b.due = math.huge
      end
      local function tick()
        s:update(1 / 30)
        chip.now = chip.now + 1 / 30
      end
      --- the words the Compy's closing gives while a file is read
      local function stopWords()
        local said = {}
        assert.is_true(s:flash(F.hex(400),
          function(l) said[#said + 1] = l end))
        s:abandon()
        return table.concat(said, '\n')
      end

      plug()
      local said = {}
      assert.is_nil(s:boardKey())
      assert.is_true(s:flash(F.hex(300),
        function(l) said[#said + 1] = l end))
      for _ = 1, 10000 do
        tick()
        local job = s.job
        if job and job.phase == 'write'
            and job.sent > job.eraseChunk + 20 then
          break
        end
      end
      assert.equal('write', s.job.phase)
      assert.equal(chip.id, s.job.id)
      -- unplugged past the erase
      chip.gone = true
      b.due = 0
      tick()
      assert.is_false(s:isFlashing())
      assert.truthy(table.concat(said, '\n'):find('may be gone', 1,
        true))
      assert.same({ [chip.id] = true }, s.doubt)

      -- the same board back, and a file it takes
      chip.gone, chip.stream, chip.queue = false, 'CLOSED', {}
      plug()
      said = {}
      assert.is_true(s:flash(F.hex(40),
        function(l) said[#said + 1] = l end))
      for _ = 1, 10000 do
        if not s:isFlashing() then break end
        tick()
      end
      assert.truthy(table.concat(said, '\n'):find('took the file', 1,
        true))
      assert.same({}, s.doubt)
      assert.truthy(stopWords():find('keeps its program', 1, true))

      -- another board, known by its id
      b:closePort(true)
      chip.id, chip.stream, chip.queue = '9904BBBBBBBB', 'CLOSED', {}
      plug()
      for _ = 1, 1000 do
        tick()
        if s:boardKey() == chip.id then break end
      end
      assert.equal(chip.id, s:boardKey())
      assert.truthy(stopWords():find('keeps its program', 1, true))
    end)
end)
