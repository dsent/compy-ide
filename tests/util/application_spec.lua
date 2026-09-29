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
