local LANG = require("util.eval")
require("model.interpreter.eval.evaluator")

--- @param expr string
--- @param result any?
local function test_case(expr, result)
  return {
    expr = expr,
    result = result,
  }
end

local function invalid(expr)
  return test_case(expr)
end

local tests = {
  ------------
  --- good ---
  ------------

  --- lit
  test_case('1', 1),
  test_case('"asd"', 'asd'),
  test_case('true', true),
  test_case('false', false),

  --- arith
  test_case('1 + 1', 2),
  test_case('3 + 2', 5),

  test_case('1 - 1', 0),

  test_case('3 * 2', 6),

  test_case('10 / 2', 5),

  test_case('2 ^ 3', 8),

  test_case('9 * (25 - 15) + 2', 92),

  --- logic
  test_case('2 > 3', false),
  test_case('2 < 3', true),

  --- table
  test_case('{ 1 }', { 1 }),
  test_case('{ a = "a" }', { a = 'a' }),

  ---------------
  --- no good ---
  ---------------
  invalid('10 / '),
  invalid(' / '),
  invalid('_'),

  ------------------------
  -- fun with functions --
  ------------------------
  test_case("(function() return 1 end)()", 1),
  test_case("(function() return 1 < 3 end)()", true),
  test_case("(function() return 1 + 1 end)()", 2),
  -- side effecting
  test_case("(function() print(2); return 1 end)()", 1),
}

describe('expression eval', function()
  local eval = LANG.eval

  for i, v in ipairs(tests) do
    it('#' .. i, function()
      local expected = v.result
      local expr = v.expr
      local res = eval(expr)
      if expected then
        assert.truthy(res)
        assert.same(expected, res)
      else
        assert.falsy(res)
      end
    end)
  end
end)

local msg_tests = {
  -- {
  --   fullmsg = '',
  --   line = 0,
  --   error = '',
  -- },
  {
    fullmsg = [[[string "x()"]:1: attempt to call global 'x' (a nil value)]],
    line = 1,
    error = [[attempt to call global 'x' (a nil value)]]
  },
  {
    fullmsg = '[string "--- @diagnostic disable duplicate-set-field,l..."]:43: e',
    line = 43,
    error = 'e'
  },
  {
    fullmsg = '[string "--- @diagnostic disable: duplicate-set-field,l..."]:43: e',
    line = 43,
    error = 'e'
  },
}

describe('extracts error message info', function()
  local pce = LANG.parse_call_error
  require('util.debug')

  for i, v in ipairs(msg_tests) do
    it('#' .. i, function()
      local expected = v.error
      local e = v.fullmsg
      local eln = v.line
      local ln, err = pce(e)

      assert.same(expected, err)
      assert.same(eln, ln)
    end)
  end
end)

describe('Lua editor eval', function()
  it('rejects overlong lines', function()
    local line = string.rep('a', 65) .. ' = 1'
    local ok, errors = LuaEditorEval:apply({ line })

    assert.is_false(ok)
    assert.truthy(string.find(tostring(errors[1]), 'line too long!', 1, true))
  end)
end)
