require('model.interpreter.eval.filter')
require('model.lang.lua.error')
local display = require('conf.display')
local format = require('model.lang.lua.format')

--- The gates: what the Compy editor refuses in Lua source.
---
--- This is the single statement of those rules. check() holds the
--- rules on text as given, which the editor's input reads through
--- LuaEditorEval; gate() is the editor's whole verdict on accepting
--- a block, and what any tool asks to get that verdict.
---
--- @class LuaCheck
--- @field max_line_length integer
--- @field max_block_lines integer
--- @field line_validators ValidatorFilter[]
--- @field ast_validators AstValidatorFilter[]

--- A Compy line is as wide as its screen, and the editor refuses a
--- longer one rather than wrapping it out of sight.
local MAX_LINE_LENGTH = display.columns

--- A block holds no more lines than the input shows at once.
local MAX_BLOCK_LINES = display.input_lines

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
  max_block_lines = MAX_BLOCK_LINES,
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

--- @class GateVerdict
--- @field ok boolean
--- @field lines string[] --- the text as the editor writes it:
--- formatted, or as given when it does not format
--- @field formatted boolean
--- @field errors Error[] --- line and parse rules, on `lines`
--- @field blocks Block[]? --- `lines` chunked, once they pass
--- @field oversized integer[] --- every block over the limit
--- @field max_block integer

--- The editor's verdict on accepting a block: format it, check
--- the formatted text, then chunk it and measure every block.
--- The checks read the formatted text, so a long line the
--- formatter wraps is no refusal.
--- @param lines string[]
--- @param width integer? --- format width; a Compy's by default
--- @param max_block integer? --- a Compy's limit by default
--- @return GateVerdict
function M.gate(lines, width, max_block)
  width = width or display.columns
  max_block = max_block or MAX_BLOCK_LINES
  local text, formatted = format.format(lines, width)
  local ok, errors = M.check(text)
  --- @type GateVerdict
  local verdict = {
    ok = ok,
    lines = text,
    formatted = formatted,
    errors = errors,
    oversized = {},
    max_block = max_block,
  }
  if not ok then return verdict end
  local _, blocks = get_parser().chunker(text, width, true)
  verdict.blocks = blocks
  for i, b in ipairs(blocks) do
    if M.excess(verdict, i) > 0 then
      verdict.ok = false
      table.insert(verdict.oversized, i)
    end
  end
  return verdict
end

--- Lines a block of the verdict has over the limit
--- @param verdict GateVerdict
--- @param i integer --- the block
--- @return integer
function M.excess(verdict, i)
  local b = verdict.blocks[i]
  local n = b and b.pos and b.pos:len() or 0
  return n - verdict.max_block
end

return M
