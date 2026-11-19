require('model.editor.bufferModel')
local parser = require('model.lang.lua.parser')()

require('util.table')

local inputs = require('tests.editor.chunker_inputs')
local TU = require('tests.testutil')


describe('parser.chunker #chunk', function()
  local w = TU.wrap
  local chunker = function(t, single)
    return parser.chunker(t, w, single)
  end

  describe('produces blocks', function()
      for i, test in ipairs(inputs) do
        local str = test[1]
        local blk = test[2]

        it('matches ' .. i, function()
          local ok, output = chunker(str)
          assert.is_true(ok)
          assert.same(blk, output)
        end)
      end
  end)

  --- A comment sharing a line with code is part of that statement's
  --- chunk. Drawn as a block of its own it lands on top of the code
  --- and gains a copy on every render.
  describe('a comment trailing code', function()
    --- @param text string[]
    --- @return string[]
    local render = function(text)
      local buffer = BufferModel(
        'untitled.lua', text, TU.noop, chunker)
      return buffer:get_text_content():items()
    end

    local single = {
      'robot_move(40, 40, 1)',
      'robot_move(40, -40, 1)  -- and back again',
    }
    local multi = {
      'function f()',
      '  return 1',
      'end -- tail',
    }
    local inner = {
      'function f()',
      '  return 1 -- inner',
      'end',
    }

    it('is drawn once, where it was written', function()
      for _, text in ipairs({ single, multi, inner }) do
        assert.same(text, render(text))
      end
    end)

    it('survives repeated rendering unchanged', function()
      for _, text in ipairs({ single, multi, inner }) do
        local once = render(text)
        assert.same(once, render(once))
      end
    end)
  end)

  --- Opening a file splits it into blocks, and saving writes
  --- the blocks back: a line no block holds is gone from the
  --- file, and a line two blocks hold is written twice.
  describe('every line of a file in one block', function()
    local LONG = '--[[ ' .. string.rep('word ', 20)

    --- Pieces of Lua a file is made of: statements, comments
    --- before, between, after and trailing them, runs of `--`
    --- lines, long comments with levels, long strings, blank
    --- lines, and lines of spaces inside a long string or
    --- comment, which are its text
    local PIECES = {
      'x = 1',
      'x = 1 -- speed',
      '-- the player',
      '--- doc\n--- more',
      '--[[ a\nb ]]',
      '--[==[ a\n]] b ]==]',
      '--[[ one line ]]',
      'y = 2 --[[ note\nmore note ]]',
      's = [[\na\n\nb\n]]',
      's = [[\na\n  \nb\n]]',
      '--[[ a\n  \nb ]]',
      'function f()\n  -- inside\n  return 1\nend -- done',
      't = {\n  1, -- one\n  -- two\n  2,\n}',
      LONG .. '\nend ]]',
      '',
      '  ',
    }

    --- Every text of two pieces, on lines of their own and
    --- sharing a line, of three with a blank line between, and
    --- each after a `#!` line
    --- @return string[]
    local function generated()
      local out = {}
      for _, a in ipairs(PIECES) do
        for _, b in ipairs(PIECES) do
          for _, sep in ipairs({ '\n', ' ', '\n\n' }) do
            local text = a .. sep .. b
            table.insert(out, text)
            table.insert(out, a .. sep .. b .. '\n' .. a)
            table.insert(out, '#!/usr/bin/lua\n' .. text)
          end
        end
      end
      return out
    end

    --- The lines the blocks give, with what is wrong with them
    --- against the source: a block's lines are its source lines
    --- exactly, and an empty block, an empty line, stands for a
    --- line of spaces alone; the program they make is the
    --- source's, so no line of spaces is taken out of a string
    --- @param lines string[]
    --- @param blocks Block[]
    --- @return string? --- what is wrong, nil when nothing
    --- @return string[] --- the lines the blocks give
    local function partition(lines, blocks)
      local got, ln = {}, 1
      for i, b in ipairs(blocks) do
        if b.pos.start ~= ln then
          return string.format('block %d starts at %d, not %d',
            i, b.pos.start, ln), got
        end
        local bl = b:is_empty() and { '' } or b.lines:items()
        if #bl ~= b.pos:len() then
          return string.format('block %d: %d lines at %s',
            i, #bl, tostring(b.pos)), got
        end
        for j, l in ipairs(bl) do
          local src = lines[ln + j - 1]
          local blank = b:is_empty()
              and string.match(src or '', '^%s*$')
          if l ~= src and not blank then
            return string.format('line %d: %q, not %q',
              ln + j - 1, l, tostring(src)), got
          end
          table.insert(got, l)
        end
        ln = b.pos.fin + 1
      end
      if ln ~= #lines + 1 then
        return string.format('blocks end at %d of %d',
          ln - 1, #lines), got
      end
      local was = string.unlines(parser.pprint(lines) or {})
      if string.unlines(parser.pprint(got) or {}) ~= was then
        return 'the program changed', got
      end
      return nil, got
    end

    it('give the lines back exactly, once each', function()
      local bad, checked = {}, 0
      for _, text in ipairs(generated()) do
        local lines = string.lines(text)
        local ok, blocks = chunker(lines)
        if ok then
          checked = checked + 1
          local e = partition(lines, blocks)
          if e then
            table.insert(bad, string.format('%q: %s', text, e))
          end
        end
      end
      assert.is_true(checked > 1000, checked)
      assert.same({}, bad)
    end)

    it('are written back as they were read', function()
      local bad, checked = {}, 0
      for _, text in ipairs(generated()) do
        local file = text .. '\n'
        local save, handle = TU.get_save_function('')
        local ok, err = pcall(function()
          if not parser.parse(text) then return end
          checked = checked + 1
          local buffer = BufferModel('main.lua', file, save)
          buffer:save()
          local saved = handle()
          if buffer.invalid then
            table.insert(bad, string.format('%q: invalid', file))
          elseif saved ~= file then
            table.insert(bad, string.format('%q -> %q',
              file, tostring(saved)))
          end
        end)
        if not ok then
          table.insert(bad, string.format('%q: %s', file, err))
        end
      end
      assert.is_true(checked > 1000, checked)
      assert.same({}, bad)
    end)

    it('keep a line comment after a commented statement',
      function()
        local _, blocks = chunker({
          'x = 1 -- speed',
          '-- the player',
          'y = 2',
        })
        assert.same({
          Chunk({ 'x = 1 -- speed' }, Range.singleton(1)),
          Chunk({ '-- the player' }, Range.singleton(2)),
          Chunk({ 'y = 2' }, Range.singleton(3)),
        }, blocks:items())
      end)

    it('keep a long comment as it is written', function()
      local _, blocks = chunker({
        'x = 1',
        '--[==[ a',
        ']] b ]==]',
        'y = 2',
      })
      assert.same({
        Chunk({ 'x = 1' }, Range.singleton(1)),
        Chunk({ '--[==[ a', ']] b ]==]' }, Range(2, 3)),
        Chunk({ 'y = 2' }, Range.singleton(4)),
      }, blocks:items())
    end)

    --- a block is the comment's own lines, not lines wrapped
    --- to the width, so every block after it stays in place
    it('keep a comment line over the width whole', function()
      local _, blocks = chunker({
        LONG, 'end ]]', 'a = 1', 'b = 2',
      })
      assert.same({
        Chunk({ LONG, 'end ]]' }, Range(1, 2)),
        Chunk({ 'a = 1' }, Range.singleton(3)),
        Chunk({ 'b = 2' }, Range.singleton(4)),
      }, blocks:items())
    end)

    it('make a draft\'s blank lines at its end one block',
      function()
        local _, blocks = chunker({ 'x = 1', '', 'y = 2', '', '' },
          true)
        assert.same({
          Chunk({ 'x = 1' }, Range.singleton(1)),
          Empty(2),
          Chunk({ 'y = 2' }, Range.singleton(3)),
          Empty(4),
        }, blocks:items())
      end)

    it('make statements sharing a line one block', function()
      local _, blocks = chunker({ 'x = 1 y = 2', 'z = 3' })
      assert.same({
        Chunk({ 'x = 1 y = 2' }, Range.singleton(1)),
        Chunk({ 'z = 3' }, Range.singleton(2)),
      }, blocks:items())
    end)
  end)
end)
