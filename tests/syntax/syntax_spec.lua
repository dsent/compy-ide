local Syntax = require('model.syntax')

--- The syntax processors (rulings.md, "The syntax processor"):
--- chosen by a file's name, and what each answers
describe('the syntax processors #syntax', function()
  it('chooses a file\'s syntax by its name\'s extension',
    function()
      assert.same('lua', Syntax.for_name('main.lua').name)
      assert.same('markdown', Syntax.for_name('notes.md').name)
      assert.same('text', Syntax.for_name('notes.txt').name)
      assert.same('text', Syntax.for_name('README').name)
      assert.same('text', Syntax.for_name('main.lua.~save').name)
      assert.same('text', Syntax.for_name(nil).name)
    end)

  it('takes a syntax registered for an extension', function()
    local mine = { name = 'mine' }
    Syntax.register('t4', mine)
    finally(function() Syntax.register('t4', nil) end)
    assert.equal(mine, Syntax.for_name('a.t4'))
    Syntax.register('t4', nil)
    assert.same('text', Syntax.for_name('a.t4').name)
  end)

  for _, name in ipairs({ 'notes.txt', 'notes.md' }) do
    describe(name, function()
      local syntax = Syntax.for_name(name)

      it('makes a block of every line, empty or not', function()
        local blocks = syntax.blocks({ 'a', '', '  ' })
        assert.same(3, #blocks)
        assert.same({ 'a' }, blocks[1].lines)
        assert.is_true(blocks[2]:is_empty())
        assert.same({ '  ' }, blocks[3].lines)
        assert.is_false(syntax.spans_lines)
      end)

      it('takes a draft as typed, and refuses none', function()
        local v = syntax.submit({ 'a', '', '', 'b' }, 64, 14)
        assert.same({ 'a', '', '', 'b' }, v.lines)
        assert.same(4, #v.blocks)
        assert.is_nil(v.failure)
        assert.is_nil(v.refusal)
      end)

      it('has nothing to format, and always loads', function()
        local text, ok, why = syntax.format({ 'a  b' }, 64)
        assert.same({ 'a  b' }, text)
        assert.is_false(ok)
        assert.same('has nothing to format', why)
        assert.is_true(syntax.loads({ 'end end' }))
        assert.same({}, syntax.references({ 'require("x")' }))
      end)
    end)
  end

  it('colors Markdown and leaves text plain', function()
    assert.is_nil(Syntax.for_name('notes.txt').highlight({ '# a' }))
    assert.is_table(Syntax.for_name('notes.md').highlight({ '# a' }))
  end)

  describe('main.lua', function()
    local lua = Syntax.for_name('main.lua')

    it('splits statements into blocks that may span lines',
      function()
        local blocks = lua.blocks({ 'function f()', 'end', 'x = 1' })
        assert.same(2, #blocks)
        assert.is_true(lua.spans_lines)
        assert.is_nil(lua.blocks({ 'x = = 1' }))
      end)

    it('refuses a draft with a notice for a rule it breaks',
      function()
        local long = string.rep('a', 70) .. ' = 1'
        local v = lua.submit({ long }, 64, 14)
        assert.truthy(v.refusal:find('the limit is 64', 1, true))
        local big = { 'function f()' }
        for i = 1, 13 do big[#big + 1] = '  x' .. i .. ' = 1' end
        big[#big + 1] = 'end'
        v = lua.submit(big, 64, 14)
        assert.truthy(v.refusal:find('Block of 15 lines', 1, true))
        v = lua.submit({ 'x = = 1' }, 64, 14)
        assert.is_not_nil(v.failure)
        v = lua.submit({ 'x=1' }, 64, 14)
        assert.same({ 'x = 1' }, v.lines)
        assert.same(1, #v.blocks)
      end)

    it('says why a file is not formatted', function()
      local _, ok, why = lua.format({ 'x = = 1' }, 64)
      assert.is_false(ok)
      assert.same('has an error on line 1, so it stays as it is', why)
    end)

    it('says why a file does not load', function()
      assert.is_true(lua.loads({ 'x = 1' }))
      local ok, why = lua.loads({ 'return 1', 'x = 1' })
      assert.is_false(ok)
      assert.truthy(why:find('Lua stops at a return', 1, true))
      local _, _, merges = lua.loads({ 'f = g', '(h)()' })
      assert.is_true(merges)
    end)
  end)
end)
