--- The text syntax: the syntax processor for a file that is
--- neither Lua nor Markdown (rulings.md, "The syntax
--- processor"). Every line is a block of its own, a draft is
--- taken as typed, and there is nothing to check or format
--- (IS8).

require('model.editor.content')
require('util.dequeue')
require('util.range')

local M = {
  name = 'text',
  --- every block is one line
  spans_lines = false,
}

--- @param lines string[]
--- @return Dequeue<Block>
local function line_blocks(lines)
  local out = Dequeue.typed('block')
  for ln, l in ipairs(lines) do
    if l == '' then
      out:push_back(Empty(ln))
    else
      out:push_back(Chunk({ l }, Range.singleton(ln)))
    end
  end
  return out
end

--- A file's blocks: a line each
--- @param lines string[]
--- @return Dequeue<Block>
function M.blocks(lines)
  return line_blocks(lines)
end

--- A draft lands as typed, a block per line (IS8.2)
--- @param lines string[]
--- @return SyntaxVerdict
function M.submit(lines)
  return { lines = lines, formatted = false,
    blocks = line_blocks(lines) }
end

--- @param lines string[]
--- @return string[] text
--- @return boolean ok
--- @return string why
function M.format(lines)
  return lines, false, 'has nothing to format'
end

--- @return boolean
function M.loads()
  return true
end

--- @return nil
function M.highlight()
  return nil
end

--- @return table[]
function M.references()
  return {}
end

--- @return Evaluator
function M.evaluator()
  require('model.interpreter.eval.evaluator')
  return TextEval
end

return M
