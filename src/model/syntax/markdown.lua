--- The Markdown syntax: the syntax processor for `.md`
--- files (rulings.md, "The syntax processor"). It is the text
--- syntax with Markdown's colors (IS8.3).

local text = require('model.syntax.text')

local M = setmetatable({ name = 'markdown' }, { __index = text })

--- @param lines string[]
--- @return SyntaxColoring
function M.highlight(lines)
  return require('model.lang.md.parser').highlighter(lines)
end

--- @return Evaluator
function M.evaluator()
  require('model.interpreter.eval.evaluator')
  return MdEval()
end

return M
