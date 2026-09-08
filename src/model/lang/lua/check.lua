require('model.interpreter.eval.filter')
require('model.lang.lua.error')

--- The checks the Compy editor applies to Lua source.
---
--- This is the single statement of those rules. The editor reads it
--- through LuaEditorEval; a linter reads it directly and gets the same
--- verdict the editor would give, without restating a rule.
---
--- @class LuaCheck
--- @field max_line_length integer
--- @field line_validators ValidatorFilter[]
--- @field ast_validators AstValidatorFilter[]

--- A Compy line is 64 columns wide, and the editor refuses a longer
--- one rather than wrapping it out of sight.
local MAX_LINE_LENGTH = 64

--- @param n integer
--- @return ValidatorFilter
local max_length = function(n)
  return function(s)
    if string.len(s) <= n then
      return true
    end
    return false, 'line too long!'
  end
end

--- @type ValidatorFilter
local line_length = max_length(MAX_LINE_LENGTH)

--- Accepts every AST the parser accepted. Parsing is the check;
--- this is the seam an AST-level rule is added on.
--- @param ast luaAST
--- @return boolean
--- @return string|Error?
--- @diagnostic disable-next-line: unused-local
local well_formed = function(ast)
  return true
end

local M = {
  max_line_length = MAX_LINE_LENGTH,
  line_validators = { line_length },
  ast_validators  = { well_formed },
}

--- The parser is built on first use, so a caller that only wants the
--- rule tables pays nothing for the Lua front end.
local parser
local function get_parser()
  parser = parser or require('model.lang.lua.parser')()
  return parser
end

--- Check Lua source the way the editor checks it: line rules first,
--- then a parse, then the AST rules. Stops at the first stage that
--- fails, which is what the editor's own pass does.
--- @param s string[]
--- @return boolean ok
--- @return Error[] errors
--- @return luaAST? ast
function M.check(s)
  local valid, errors = Filters.validate(M.line_validators, s)
  if not valid then
    return false, errors
  end

  local ok, result = get_parser().parse(s)
  if not ok then
    return false, { Error.wrap(result) }
  end

  local ast = result
  for _, av in ipairs(M.ast_validators) do
    local passed, verr = av(ast)
    if not passed and verr then
      table.insert(errors, Error.wrap(verr))
    end
  end
  if #errors > 0 then
    return false, errors, ast
  end
  return true, errors, ast
end

return M
