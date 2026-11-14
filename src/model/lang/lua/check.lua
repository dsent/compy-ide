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

--- A line is as wide as its characters: an accented letter or a
--- dash takes one column however many bytes it is. Bytes that are
--- not UTF-8 have no length in characters and count one each.
--- @param n integer
--- @return ValidatorFilter
local max_length = function(n)
  return function(s)
    if (string.ulen(s) or string.len(s)) <= n then
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

--- @param l string
--- @return boolean
local function is_blank(l)
  return string.match(l, '^%s*$') ~= nil
end

--- The runs of blank lines among lines `from` to `to`
--- @param lines string[]
--- @param from integer
--- @param to integer
--- @return table[] --- {at, n}: first line and length
local function blank_runs(lines, from, to)
  local runs, run = {}, nil
  for i = from, to do
    if not is_blank(lines[i]) then
      run = nil
    elseif run then
      run.n = run.n + 1
    else
      run = { at = i, n = 1 }
      runs[#runs + 1] = run
    end
  end
  return runs
end

--- The line ranges around the statements of a text: before
--- the first, between each two, after the last
--- @param lines string[]
--- @return table[]? --- {from, to}; nil when it does not parse
local function gaps(lines)
  local ok, ast = get_parser().parse(lines)
  if not ok then return nil end
  local out, last = {}, 0
  for _, st in ipairs(ast) do
    local li = st.lineinfo
    if not li then return nil end
    out[#out + 1] = { last + 1, li.first.line - 1 }
    last = li.last.line
  end
  out[#out + 1] = { last + 1, #lines }
  return out
end

--- Every empty line of a draft becomes an empty-line block
--- (IS3.7), and the formatter leaves one of a run: the runs
--- between statements get their lines back.
--- @param given string[] --- the draft
--- @param text string[] --- the draft formatted
--- @return string[]
local function keep_empty_lines(given, text)
  local a, b = gaps(given), gaps(text)
  if not a or not b or #a ~= #b then return text end
  local add = {}
  for i = 1, #a do
    local ra = blank_runs(given, a[i][1], a[i][2])
    local rb = blank_runs(text, b[i][1], b[i][2])
    if #ra == #rb then
      for j = 1, #ra do add[rb[j].at] = ra[j].n - rb[j].n end
    end
  end
  local out = {}
  for i, l in ipairs(text) do
    for _ = 1, add[i] or 0 do out[#out + 1] = '' end
    out[#out + 1] = l
  end
  return out
end

--- @param lines string[]
--- @return boolean --- a `#!` line opens the text
local function shebang(lines)
  return lines[1] ~= nil and string.match(lines[1], '^#!') ~= nil
end

--- @param lines string[]
--- @return string[] --- the lines below an empty one
local function below_a_line(lines)
  local below = { '' }
  for i, l in ipairs(lines) do below[i + 1] = l end
  return below
end

--- A draft read as Lua reads it: a `#!` line is skipped at
--- the top of a file alone, which a draft is not, so the
--- draft is read below a line, where the `#!` fails. The
--- parser the editor's field checks and colors with, so
--- that the red text and a refused submission agree (IS3.4).
--- @type table
M.draft_parser = setmetatable({
  parse = function(lines)
    if not shebang(lines) then return get_parser().parse(lines) end
    return get_parser().parse(below_a_line(lines))
  end,
  --- @param lines string[]
  --- @param err Error --- as parse above returned it
  --- @return Error
  failure = function(lines, err)
    if not shebang(lines) then
      return get_parser().failure(lines, err)
    end
    local failure = get_parser().failure(below_a_line(lines), err)
    failure.l = failure.l - 1
    return failure
  end,
}, { __index = function(_, k) return get_parser()[k] end })

--- @param at_head boolean?
--- @return table --- the parser a draft is read with where it
--- lands: at the file's head a `#!` line opens it
local function draft_parser(at_head)
  return at_head and get_parser() or M.draft_parser
end

--- The parser of a draft whose landing place can change: it
--- reads the draft as gate() will, at the file's head or below
--- it, as `at_head` answers at each reading, so that the red
--- text and the verdict agree. `context` lets a memo of a
--- reading tell that the answer changed.
--- @param at_head fun(): boolean
--- @return table
function M.placed_parser(at_head)
  return setmetatable({
    parse = function(lines)
      return draft_parser(at_head()).parse(lines)
    end,
    failure = function(lines, err)
      return draft_parser(at_head()).failure(lines, err)
    end,
    context = at_head,
  }, { __index = function(_, k) return get_parser()[k] end })
end

--- The text as the editor writes it: formatted, or as given
--- when it does not format. A draft's empty lines between
--- statements stay when `keep_empty` asks (IS3.7). A draft
--- that opens with `#!` does not parse, so it does not format.
--- @param lines string[]
--- @param width integer
--- @param keep_empty boolean?
--- @return string[] text
--- @return boolean formatted
function M.formatted(lines, width, keep_empty)
  if shebang(lines) then return lines, false end
  local text, formatted = format.format(lines, width)
  if formatted and keep_empty then
    text = keep_empty_lines(lines, text)
  end
  return text, formatted
end

--- A whole file formatted, as Ctrl+Shift+F and `tidy()`
--- format it: a `#!` first line is no Lua, and stays as it is
--- above the rest
--- @param lines string[]
--- @param width integer
--- @return string[] text --- as given when it does not format
--- @return boolean formatted
function M.tidied(lines, width)
  local head = shebang(lines) and { lines[1] } or {}
  local rest = {}
  for i = #head + 1, #lines do rest[#rest + 1] = lines[i] end
  local out, formatted = format.format(rest, width)
  if not formatted then return lines, false end
  for _, l in ipairs(out) do head[#head + 1] = l end
  return head, true
end

--- @param lines string[]
--- @return table? --- {l, len}: the first line over the limit
local function long_line(lines)
  for i, l in ipairs(lines) do
    local len = string.ulen(l) or string.len(l)
    if len > MAX_LINE_LENGTH then return { l = i, len = len } end
  end
end

--- @class GateVerdict
--- @field ok boolean
--- @field failure Error? --- the parse failure, at the failing
--- character, or `at_end` when the draft is only unfinished
--- @field long_line table? --- {l, len}: a line over the limit
--- @field lines string[] --- the text as the editor writes it:
--- formatted, or as given when it does not format
--- @field formatted boolean
--- @field errors Error[] --- line and parse rules, on `lines`
--- @field blocks Block[]? --- `lines` chunked, when they parse
--- @field oversized integer[] --- every block over the limit
--- @field max_block integer

--- The editor's verdict on accepting a block: format it, check
--- the formatted text, then chunk it and measure every block.
--- The checks read the formatted text, so a long line the
--- formatter wraps is no refusal. Blocks are measured whenever
--- the text parses, so a report can name them beside a long
--- line; the editor refuses the line first.
--- @param lines string[]
--- @param width integer? --- format width; a Compy's by default
--- @param max_block integer? --- a Compy's limit by default
--- @param keep_empty boolean? --- a draft's submission: every
--- empty line between statements stays (IS3.7)
--- @param at_head boolean? --- the draft lands as the file's
--- first lines, where a `#!` line opens a file as LuaJIT
--- reads it
--- @return GateVerdict
function M.gate(lines, width, max_block, keep_empty, at_head)
  width = width or display.columns
  max_block = max_block or MAX_BLOCK_LINES
  local text, formatted = M.formatted(lines, width, keep_empty)
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
  --- syntax comes before size: the line check counts
  --- formatted lines (IS3.2), which a failed parse has none of
  local draft = draft_parser(at_head)
  local parses, failure = draft.parse(lines)
  if not parses then
    verdict.failure = draft.failure(lines, failure)
    verdict.errors = { verdict.failure }
    return verdict
  end
  verdict.long_line = long_line(text)
  local parsed, blocks = get_parser().chunker(text, width, true)
  if not parsed then return verdict end
  verdict.blocks = blocks
  for i in ipairs(blocks) do
    if M.excess(verdict, i) > 0 then
      verdict.ok = false
      table.insert(verdict.oversized, i)
    end
  end
  return verdict
end

--- A draft of blank lines alone is accepted as that many
--- empty-line blocks (IS3.7; the principles name no draft
--- without a statement, and Luditor's chunker does this). One
--- line holding nothing is an empty draft, which is no
--- submission of text.
--- @param lines string[]
--- @return Block[]? --- nil when the draft holds text
function M.empty_blocks(lines)
  if #lines < 2 and lines[1] == '' then return nil end
  if #lines == 0 then return nil end
  require('model.editor.content')
  local blocks = {}
  for i, l in ipairs(lines) do
    if not is_blank(l) then return nil end
    blocks[i] = Empty(i)
  end
  return blocks
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
