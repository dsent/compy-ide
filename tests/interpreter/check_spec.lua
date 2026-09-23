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

  describe('the gate', function()
    it('checks the text as formatted, so a wrapped line passes',
      function()
        local long = 'local t = { ' .. string.rep('"abcd", ', 8)
            .. '"abcd" }'
        assert.is_true(#long > check.max_line_length)
        assert.is_false((check.check({ long })))

        local verdict = check.gate({ long })
        assert.is_true(verdict.ok)
        assert.is_true(verdict.formatted)
        assert.is_true(#verdict.lines > 1)
        assert.is_true((check.check(verdict.lines)))
      end)

    it('refuses a block over the limit, naming it and the excess',
      function()
        local body = {}
        for i = 1, check.max_block_lines - 1 do
          table.insert(body, '  x' .. i .. ' = ' .. i)
        end
        local lines = { 'x = 0', 'function f()' }
        for _, l in ipairs(body) do table.insert(lines, l) end
        table.insert(lines, 'end')

        local verdict = check.gate(lines)
        assert.is_false(verdict.ok)
        assert.same({}, verdict.errors)
        assert.equal(2, verdict.oversized)
        assert.equal(1, verdict.excess)
      end)

    it('gives back text that does not parse, with the error',
      function()
        local lines = { 'function f(', '  return 1' }
        local verdict = check.gate(lines)
        assert.is_false(verdict.ok)
        assert.is_false(verdict.formatted)
        assert.equal(lines, verdict.lines)
        assert.equal(1, #verdict.errors)
        assert.is_number(verdict.errors[1].l)
      end)

    it('chunks what passes into the blocks the editor writes',
      function()
        local verdict = check.gate({ 'a = 1', '', '', 'b = 2', '' })
        assert.is_true(verdict.ok)
        assert.same({ 'a = 1', '', 'b = 2', '' }, verdict.lines)
        local kinds = {}
        for _, b in ipairs(verdict.blocks) do
          table.insert(kinds, b:is_empty() and 'empty' or 'code')
        end
        assert.same({ 'code', 'empty', 'code', 'empty' }, kinds)
      end)
  end)
end)
