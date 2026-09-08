local check = require("model.lang.lua.check")
require("model.interpreter.eval.evaluator")

--- @param n integer
--- @return string
local function line_of(n)
  return string.rep('a', n)
end

describe('lua check #check', function()
  it('is the rule set the editor runs', function()
    --- The point of the module: one statement of the rules. If the
    --- editor ever grows a private copy, these stop being the same
    --- tables and the linter starts disagreeing with the editor.
    assert.equal(check.line_validators, LuaEditorEval.line_validators)
    assert.equal(check.ast_validators, LuaEditorEval.astValidators)
  end)

  it('accepts a line at the limit', function()
    local ok, errors = check.check({ '--' .. line_of(check.max_line_length - 2) })
    assert.is_true(ok)
    assert.same({}, errors)
  end)

  it('rejects a line over the limit', function()
    local over = '--' .. line_of(check.max_line_length - 1)
    local ok, errors = check.check({ over })
    assert.is_false(ok)
    assert.equal(1, #errors)
    assert.equal('line too long!', errors[1].msg)
  end)

  it('numbers the offending line in a multi-line text', function()
    local ok, errors = check.check({
      'local x = 1',
      '--' .. line_of(check.max_line_length - 1),
    })
    assert.is_false(ok)
    assert.equal(1, #errors)
    assert.equal(2, errors[1].l)
  end)

  it('reports a parse error with its position', function()
    local ok, errors = check.check({ 'local x =' })
    assert.is_false(ok)
    assert.equal(1, #errors)
    assert.is_string(errors[1].msg)
    assert.is_number(errors[1].l)
    assert.is_number(errors[1].c)
  end)

  it('returns the AST of source that passes', function()
    local ok, errors, ast = check.check({ 'local x = 1' })
    assert.is_true(ok)
    assert.same({}, errors)
    assert.is_table(ast)
    assert.equal('Local', ast[1].tag)
  end)

  it('checks lines before it parses', function()
    --- A too-long line that is also invalid Lua reports the line
    --- rule, not a parse error, exactly as the editor's pass does.
    local ok, errors = check.check({ 'local x = ' .. line_of(60) .. ' ..' })
    assert.is_false(ok)
    assert.equal('line too long!', errors[1].msg)
  end)
end)
