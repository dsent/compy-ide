--- Warranted under the testing policy: every save of a Lua
--- file goes through these two functions, so a mistake here
--- changes the bytes of every file the editor, tidy and
--- compyfmt write.

local textfile = require("util.textfile")

describe('textfile #textfile', function()
  it('reads a file as its lines, the final newline in the last',
    function()
      assert.same({}, textfile.lines(''))
      assert.same({ 'x = 1' }, textfile.lines('x = 1\n'))
      assert.same({ 'x = 1' }, textfile.lines('x = 1'))
      assert.same({ 'x = 1', '' }, textfile.lines('x = 1\n\n'))
      assert.same({ '' }, textfile.lines('\n'))
    end)

  it('writes a newline after every line, the last one too',
    function()
      assert.same('', textfile.text({}))
      assert.same('x = 1\n', textfile.text({ 'x = 1' }))
      assert.same('x = 1\n\n', textfile.text({ 'x = 1', '' }))
      assert.same('\n', textfile.text({ '' }))
    end)

  it('gives back a file that ends in a newline byte for byte',
    function()
      local files = { '', '\n', 'a\n', 'a\n\nb\n', 'a\n\n' }
      for _, text in ipairs(files) do
        assert.same(text, textfile.text(textfile.lines(text)))
      end
    end)
end)
