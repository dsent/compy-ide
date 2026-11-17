-- What a project's validator returns, as the message the
-- widget shows: an Error, a string, or a table with a `msg`
-- (the shape doc/development/internals/user_input.md gives).

local F = require("tests.helpers.input_fixture")

describe("the validator message #input", function()
  setup(function()
    F.setup()
  end)
  teardown(function()
    F.teardown()
  end)
  before_each(function()
    F.reset()
  end)

  --- Submit `text` to a widget whose validator refuses with
  --- `errors`; return the lines the widget's error shows.
  local function refused_with(errors)
    local input = F.activate_project()
    function input.callbacks.validator()
      return false, errors
    end
    input.show({ text = "abc" })
    F.session.press("return")
    return F.widget.model:get_wrapped_error()
  end

  it("shows a { msg = ... } table by its message", function()
    local shown = refused_with({ { msg = "too short" } })
    assert.same({
      "Errors:",
      "too short"
    }, shown)
  end)

  it("shows a { msg, l, c } table with its position", function()
    local shown = refused_with({ {
      msg = "too short",
      l = 1,
      c = 3
    } })
    assert.same({
      "Errors:",
      "L1:3:too short"
    }, shown)
  end)

  it("shows a string as it is", function()
    assert.same({
      "Errors:",
      "too short"
    }, refused_with({ "too short" }))
  end)

  it("shows an Error with its position", function()
    local shown = refused_with({ Error("too short", 2, 1) })
    assert.same({
      "Errors:",
      "L1:2:too short"
    }, shown)
  end)
end)
