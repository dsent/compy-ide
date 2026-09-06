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
        --- the editor keeps one empty line at the end
        local expected = table.clone(text)
        table.insert(expected, '')
        assert.same(expected, render(text))
      end
    end)

    it('survives repeated rendering unchanged', function()
      for _, text in ipairs({ single, multi, inner }) do
        local once = render(text)
        assert.same(once, render(once))
      end
    end)
  end)
end)
