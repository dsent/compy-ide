local Application = require('util.application')
local mock = require('tests.mock')

describe('application lifecycle #util', function()
  local quit
  local minimizes

  local function mock_platform(name)
    Application.consume_application_exit_request()
    quit = nil
    minimizes = 0
    mock.mock_love({
      event = {
        quit = function(...)
          quit = { ... }
          quit.n = select('#', ...)
        end,
      },
      system = {
        getOS = function() return name end,
      },
      window = {
        minimize = function() minimizes = minimizes + 1 end,
      },
    })
  end

  it('requests an ordinary exit, tagged as asked for', function()
    mock_platform('Android')

    Application.request_exit()

    assert.same(1, quit.n)
    assert.same({ true, nil }, { Application.untag(quit[1]) })
  end)

  it('keeps a quit\'s status in its tag', function()
    for _, status in ipairs({ 0, 1, -2, 2.5, 'restart', '' }) do
      local tag = Application.quit_tag(status)
      assert.same({ true, status }, { Application.untag(tag) })
      assert.same(tag, Application.quit_tag(tag))
    end
    assert.same({ true, nil },
      { Application.untag(Application.quit_tag(true)) })
    -- Android's own quit carries no tag
    assert.same({ false, nil }, { Application.untag(nil) })
    assert.same({ false, 'restart' },
      { Application.untag('restart') })
  end)

  --- the IDE's love.run: love.quit gets the event's value, and
  --- the run ends with the status the quit was asked with
  describe('run', function()
    local function looped(events, quit)
      local handled = {}
      mock.mock_love({
        event = {
          pump = function() end,
          poll = function()
            return function()
              local e = table.remove(events, 1)
              if e then return e[1], e[2] end
            end
          end,
        },
        handlers = setmetatable({}, { __index = function(_, name)
          return function(a) handled[#handled + 1] = { name, a } end
        end }),
        quit = quit,
        arg = { parseGameArguments = function() end },
        graphics = { isActive = function() return false end },
      })
      local loop = Application.run()
      return loop(), handled
    end

    it('ends with the status a tagged quit holds', function()
      local got
      local r = looped({ { 'quit', Application.quit_tag('restart') } },
        function(v) got = v end)
      assert.same('restart', r)
      assert.same({ true, 'restart' }, { Application.untag(got) })
      assert.same(7, (looped({ { 'quit', Application.quit_tag(7) } },
        function() end)))
      assert.same(0, (looped({ { 'quit', Application.quit_tag() } },
        function() end)))
    end)

    it('ends with an untagged quit\'s own value, or 0', function()
      assert.same(0, (looped({ { 'quit' } }, function() end)))
      assert.same(5, (looped({ { 'quit', 5 } }, function() end)))
    end)

    it('goes on when love.quit says to stay', function()
      local r, handled = looped({ { 'quit', Application.quit_tag() } },
        function() return true end)
      assert.is_nil(r)
      assert.same('quit', handled[1][1])
    end)

    --- Frames of the loop with no events, on a clock that only
    --- the loop's parts move: each frame's update by its
    --- `update` seconds, its present by its `present` seconds
    --- (nil: the window is inactive and nothing is presented),
    --- and the sleep by what it was asked; a frame's `hz` is the
    --- refresh rate the window reports from that frame on.
    --- Returns the sleeps each frame took, and how many times
    --- the window's mode was read.
    --- @param hz number --- the refresh rate the window reports
    --- @param frames { update: number?, present: number?,
    ---   hz: number? }[]
    --- @return integer[] slept
    --- @return integer reads
    local function run(hz, frames)
      local now, i, slept, reads = 100, 0, { }, 0
      mock.mock_love({
        event = {
          pump = function() end,
          poll = function() return function() end end,
        },
        arg = { parseGameArguments = function() end },
        update = function() now = now + (frames[i].update or 0) end,
        timer = {
          step = function() return 0 end,
          getTime = function() return now end,
          sleep = function(s)
            slept[i] = slept[i] + 1
            now = now + s
          end,
        },
        graphics = {
          isActive = function() return frames[i].present ~= nil end,
          origin = function() end,
          clear = function() end,
          getBackgroundColor = function() return 0, 0, 0, 1 end,
          present = function() now = now + frames[i].present end,
        },
        window = {
          getMode = function()
            reads = reads + 1
            return 64, 64, { refreshrate = hz }
          end,
        },
      })
      local loop = Application.run()
      for k = 1, #frames do
        i = k
        slept[k] = 0
        hz = frames[k].hz or hz
        loop()
      end
      return slept, reads
    end

    --- the sleeps of one frame that presents after `present`
    local function one(present, hz)
      return run(hz or 60, { { present = present } })[1]
    end

    it("sleeps after a frame shorter than seven eighths of the "
      .. "display's period, and only then", function()
        -- a present that did not wait, as with vsync off
        assert.same(1, one(0.001))
        assert.same(1, one(0.0145))
        -- one that waited the period, or a frame longer than it
        assert.same(0, one(0.0147))
        assert.same(0, one(1 / 60))
        assert.same(0, one(0.020))
        -- a period of the frame's own work, the present at once
        assert.same({ 0 }, run(60, { { update = 1 / 60, present = 0 } }))
      end)

    it("sleeps after a frame that presented nothing, however long "
      .. "it took", function()
        assert.same({ 1, 1 }, run(60, { { update = 0 },
          { update = 1 / 60 } }))
      end)

    it("does not count the frame before's sleep into a frame",
      function()
        -- the second frame falls short of 14.58 ms by half a
        -- millisecond, which the first frame's sleep would make up
        assert.same({ 1, 1 }, run(60, { { present = 0 },
          { present = 7 / 8 / 60 - 0.0005 } }))
      end)

    it("takes the period from the window's refresh rate, 60 Hz "
      .. 'where it reports none', function()
        assert.same(0, one(1 / 144, 144))
        assert.same(1, one(1 / 144, 60))
        assert.same(0, one(1 / 60, 0))
        assert.same(1, one(1 / 144, 0))
        -- a fast frame under a high rate still sleeps
        assert.same(1, one(0.0001, 500))
        assert.same(1, one(0.0001, 1000))
        assert.same(0, one(0.002, 500))
      end)

    --- the call costs 416 to 430 µs on a Compy
    it("reads the window's mode once, as the loop starts, and "
      .. 'keeps its period for the run', function()
        local slept, reads = run(60, { { present = 1 / 60 },
          { present = 1 / 144, hz = 144 },
          { present = 1 / 144 } })
        assert.same({ 0, 1, 1 }, slept)
        assert.same(1, reads)
      end)
  end)

  it('requests a one-shot full application exit', function()
    mock_platform('Android')

    Application.request_application_exit()

    assert.same(1, quit.n)
    assert.is_true(Application.consume_application_exit_request())
    assert.is_false(Application.consume_application_exit_request())
  end)

  it('returns through Android HOME before exit', function()
    mock_platform('Android')

    Application.return_home_before_exit()

    assert.same(1, minimizes)
  end)

  it('does not minimize a desktop window before exit', function()
    mock_platform('Linux')

    Application.return_home_before_exit()

    assert.same(0, minimizes)
  end)
end)
