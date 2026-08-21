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

  it('requests an ordinary exit', function()
    mock_platform('Android')

    Application.request_exit()

    assert.same(0, quit.n)
  end)

  it('requests a one-shot full application exit', function()
    mock_platform('Android')

    Application.request_application_exit()

    assert.same(0, quit.n)
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
