--- The Lua syntax: the syntax processor for `.lua` files
--- (rulings.md, "The syntax processor"). It answers the syntax
--- API (model.syntax) around the Lua language layer
--- (model.lang.lua): its parser, formatter and gate decide
--- what is Lua and what a block may hold. Its own parts: where
--- a failure shows (IS3.4, IS3.5), which reason a refusal
--- names, and the files a text names (IS1.5).

require('util.string.string')
require('model.lang.lua.error')
require('util.tree')
local check = require('model.lang.lua.check')
local format = require('model.lang.lua.format')
local cursor_map = require('model.input.cursorMap')
require('model.editor.content')
require('util.dequeue')

local M = {
  name = 'lua',
  --- a block may span lines: a statement, a comment
  spans_lines = true,
}

--- The parser is built on first use
local base
local function get_parser()
  base = base or require('model.lang.lua.parser')()
  return base
end

--- @param s string
--- @param byte integer --- a byte offset in `s`
--- @return integer --- the column of the character there
local char_col = function(s, byte)
  local pre = string.sub(s, 1, byte - 1)
  return (string.ulen(pre) or #pre) + 1
end

--- @param lines string[]
--- @param ln integer
--- @param at integer --- the byte the comment opens at
--- @return integer ln --- where the text goes on after it
--- @return integer col
local skip_comment = function(lines, ln, at)
  local eq = string.match(lines[ln], '^%-%-%[(=*)%[', at)
  if not eq then return ln + 1, 1 end
  local close = ']' .. eq .. ']'
  local from = at + 4 + #eq
  while ln <= #lines do
    local _, e = string.find(lines[ln], close, from, true)
    if e then return ln, e + 1 end
    ln, from = ln + 1, 1
  end
  return ln, 1
end

--- @param lines string[]
--- @param l integer
--- @param c integer --- a byte column
--- @return boolean --- the text before l:c ends in a comment
local after_comment = function(lines, l, c)
  local before = {}
  for i = 1, l - 1 do before[i] = lines[i] end
  before[l] = string.sub(lines[l], 1, c - 1)
  local els = cursor_map.elements(table.concat(before, '\n'))
  local last = els[#els]
  return last ~= nil and string.sub(last.text, 1, 2) == '--'
end

--- @param lines string[]
--- @param err Error
--- @return Error --- `err`, placed after the last character
local at_end = function(lines, err)
  local last = lines[#lines] or ''
  err.l = math.max(#lines, 1)
  err.c = (string.ulen(last) or #last) + 1
  err.at_end = true
  return err
end

--- @param lines string[]
--- @param tok table --- the parser's current token
--- @param err Error
--- @return Error --- `err`, placed at the element before `tok`
local before_token = function(lines, tok, err)
  local plain, upto = {}, 0
  for i = 1, #lines do
    plain[i] = lines[i]
    if i < tok.l then upto = upto + #lines[i] + 1 end
  end
  local text = table.concat(plain, '\n')
  upto = tok.eof and #text + 1 or upto + tok.c - 1
  local found
  for _, el in ipairs(cursor_map.elements(text)) do
    local comment = string.sub(el.text, 1, 2) == '--'
    if el.s < upto and not comment then found = el end
  end
  if not found then return at_end(lines, err) end
  err.l, err.c = cursor_map.position(plain, found.s)
  return err
end

--- The failure boundary (IS3.4, IS3.5): the first character
--- of the token the parser failed on, or the end of the text
--- when it failed for want of more, which `at_end` says. It
--- reads the token the parser stopped at (`err.token`).
--- @param code str
--- @param parse_err Error --- as parse returns it
--- @return Error --- a new one, at the boundary
function M.failure(code, parse_err)
  local lines = code
  if type(code) == 'string' then lines = string.lines(code) end
  local l = parse_err.l
  local err = Error(parse_err.msg, parse_err.c, l)
  if type(lines) ~= 'table' then return err end
  --- an expression where a statement belongs fails as a
  --- whole, and the parser has read past it by then; every
  --- other failure is at the token the parser stopped at
  local msg = err.msg or ''
  local misplaced = string.find(msg,
    'statement was expected', 1, true)
  local tok = not misplaced and parse_err.token
  --- an invalid assignment target already names the target's
  --- first character; the parser stopped at `=` after it
  if string.find(msg, 'can go before =', 1, true)
      and lines[l] then
    err.c = char_col(lines[l], err.c)
    return err
  end
  --- these two the parser raises after reading the token
  --- that failed: it is the one before the current token
  local no_expr = string.find(msg,
    "can't start an expression", 1, true)
  local no_keyword = string.find(msg,
    'A keyword was expected', 1, true)
  --- a keyword missing at the end names no token read: the
  --- error's own position says where the text stopped
  if no_keyword and tok and tok.eof then tok = nil end
  if tok and (no_expr or no_keyword) then
    return before_token(lines, tok, err)
  end
  if tok and not tok.eof and lines[tok.l] then
    err.l, err.c = tok.l, char_col(lines[tok.l], tok.c)
    return err
  end
  if tok and tok.eof then return at_end(lines, err) end
  if not lines[l] then return err end
  --- the lexer failed, or an expression is misplaced: the
  --- error names the last token taken before the failure,
  --- and none when the text opens with it
  local col = err.c + 1
  local opens = l == 1 and err.c == 1 and misplaced
  if opens then col = 1 end
  --- after a comment, or on a bad string escape, the parser
  --- names the failing token itself
  if after_comment(lines, l, err.c)
      or string.find(msg, 'invalid escape sequence', 1, true)
  then
    col = err.c
  end
  local ln = l
  while ln <= #lines do
    local s = lines[ln]
    local at = string.find(s, '%S', col)
    if not at then
      ln, col = ln + 1, 1
    elseif string.sub(s, at, at + 1) ~= '--' then
      err.l, err.c = ln, char_col(s, at)
      return err
    else
      --- a comment is no failure: the text goes on after it
      ln, col = skip_comment(lines, ln, at)
    end
  end
  return at_end(lines, err)
end


--- What a draft that does not parse comes to (IS3.4, IS3.5):
--- its failure, at the failing character; or, when it is
--- only unfinished, no failure: it goes on, on a new line at
--- its end, the cursor there
--- @param lines string[]
--- @param failure Error --- as M.failure places it
--- @return Unparsed
local went_on = function(lines, failure)
  if not failure.at_end then
    return { lines = lines, formatted = false,
      failure = failure }
  end
  local out = {}
  for i, l in ipairs(lines) do out[i] = l end
  out[#out + 1] = ''
  return { lines = out, formatted = true,
    cursor = { l = #out, c = 1 } }
end

--- @class Unparsed
--- @field failure Error? --- where the draft fails, if it does
--- @field lines string[] --- the draft to show
--- @field formatted boolean --- `lines` differ from the draft
--- @field cursor {l: integer, c: integer}? --- where the cursor
--- goes in `lines`; nil: it follows the text it stood at

--- What a draft that does not parse comes to, as the field
--- shows it
--- @param code str
--- @param parse_err Error --- as parse returns it
--- @return Unparsed
function M.unparsed(code, parse_err)
  local lines = code
  if type(code) == 'string' then lines = string.lines(code) end
  return went_on(lines, M.failure(lines, parse_err))
end

--- The language layer's parser, with `unparsed` beside it:
--- the parser of the console's field and the file editor's
--- @return table
function M.parser()
  return setmetatable({ unparsed = M.unparsed },
    { __index = function(_, k) return get_parser()[k] end })
end

--- @class SubmissionVerdict: GateVerdict
--- @field failure Error? --- the parse failure, at the failing
--- character, or `at_end` when the draft is only unfinished
--- @field long_line table? --- {l, len}: the line over the
--- limit a refusal names

--- The language layer's verdict on a draft (check.gate), as
--- the editor shows it. A draft that is no Lua where it lands
--- is refused with its failure, before anything is measured
--- (IS3.2). An accepted draft is the gate's text and blocks,
--- the empty lines the formatter leaves included (the ruling
--- "The formatter decides a draft's empty lines"). A refusal
--- for a line names that line and its length.
--- @param lines string[]
--- @param width integer
--- @param max_block integer
--- @return SubmissionVerdict
function M.submission(lines, width, max_block)
  local parses, err = get_parser().parse(lines)
  if not parses then
    local failure = M.failure(lines, err)
    return {
      ok = false,
      failure = failure,
      errors = { failure },
      lines = lines,
      formatted = false,
      oversized = {},
      max_block = max_block,
    }
  end
  local verdict = check.gate(lines, width, max_block)
  local first = verdict.errors[1]
  if first then
    local l = first.l or 1
    local line = verdict.lines[l] or ''
    verdict.long_line = {
      l = l, len = string.ulen(line) or string.len(line),
    }
  end
  return verdict
end

--- @param node luaAST
--- @return table[] --- {line, name, file}
local function reference(node)
  if type(node) ~= 'table' or node.tag ~= 'Call' then
    return {}
  end
  local fn, arg = node[1], node[2]
  local name = fn and fn.tag == 'Id' and fn[1]
  if name ~= 'require' and name ~= 'dofile' then return {} end
  --- a name written out; dofile's is the file itself
  if type(arg) ~= 'table' or arg.tag ~= 'String' then
    return {}
  end
  --- require names a module, a dot for each folder on the way
  local file = arg[1]
  if name == 'require' and not string.match(file, '%.lua$') then
    file = string.gsub(file, '%.', '/') .. '.lua'
  end
  local li = arg.lineinfo
  return { {
    line = li and li.first and li.first.line,
    name = arg[1],
    file = file,
  } }
end

--- The files a text names (IS1.5): `require` and `dofile`
--- with the name written out; none in a text that does not
--- parse
--- @param lines string[]
--- @return table[] --- {line, name, file}
function M.references(lines)
  local ok, ast = get_parser().parse(lines)
  if not ok then return {} end
  return table.flatten(Tree.preorder(ast, reference))
end

--- A file's blocks: its statements and comments, a blank
--- line each an empty-line block; nil when the text does not
--- parse
--- @param lines string[]
--- @return Dequeue<Block>?
function M.blocks(lines)
  if #lines == 0 then return Dequeue.typed('block') end
  local ok, blocks = get_parser().chunker(lines, nil, false)
  if ok then return blocks end
end

--- @class SyntaxVerdict
--- @field blocks Block[]? --- what an accepted draft lands as
--- @field lines string[] --- the draft as the syntax writes it
--- @field formatted boolean --- `lines` differ from the draft
--- @field failure Error? --- where the draft fails to parse
--- @field cursor {l: integer, c: integer}? --- where the cursor
--- goes in `lines` when the draft is not taken; nil: it
--- follows the text it stood at
--- @field refusal string? --- the notice of a rule it breaks

--- A draft as Lua takes it (IS3.2 to IS3.5): refused where it
--- does not parse, gone on on a new line when it is only
--- unfinished, or refused with a notice for a line over the
--- limit or a block over the size limit; accepted as the
--- gate's formatted blocks
--- @param lines string[]
--- @param width integer
--- @param max_block integer
--- @param first_line integer? --- file line of the draft's first row
--- @return SyntaxVerdict
function M.submit(lines, width, max_block, first_line)
  local v = M.submission(lines, width, max_block)
  if v.failure then return went_on(v.lines, v.failure) end
  local out = { lines = v.lines, formatted = v.formatted }
  --- every error the gate gives sets long_line (M.submission)
  local long = v.long_line
  if long then
    out.refusal = string.format(
      'Line %d has %d characters, the limit is %d.'
      .. ' Shorten or break it, then press Enter',
      long.l + (first_line or 1) - 1, long.len,
      check.max_line_length)
    return out
  end
  local first = v.oversized[1]
  if first then
    out.refusal = string.format(
      'Block of %d lines, the limit is %d.'
      .. ' Shorten or split it, then press Enter',
      v.blocks[first].pos:len(), v.max_block)
    return out
  end
  out.blocks = v.blocks
  return out
end

--- A file formatted, as Alt+F and `tidy()` format it
--- @param lines string[]
--- @param width integer
--- @return string[] text --- as given when it does not format
--- @return boolean ok
--- @return string? why --- what keeps it as it is, to follow
--- the file's name or "The file"
function M.format(lines, width)
  local text, formatted = format.format(lines, width)
  if formatted then return text, true end
  local parsed, err = get_parser().parse(lines)
  if not parsed and err and err.l and err.l > 0 then
    return lines, false, string.format(
      'has an error on line %d, so it stays as it is', err.l)
  end
  return lines, false, 'cannot be tidied without changing'
      .. ' what it does, so it stays as it is'
end

--- Whether the file runs after a change: Lua loads it
--- @param lines string[]
--- @return boolean ok
--- @return string? why --- the notice when it does not
--- @return boolean? merges --- it does not because a line now
--- reads as one statement with the line before it
function M.loads(lines)
  local chunk, err = loadstring(table.concat(lines, '\n'))
  if chunk then return true end
  err = tostring(err)
  --- Lua reads a line starting with `(` as a call of the line
  --- before it, and says so
  if err:find('ambiguous', 1, true) then
    return false, nil, true
  end
  if err:find("'<eof>' expected", 1, true) then
    return false, 'Lua stops at a return or break;'
        .. ' nothing can follow one.'
  end
  return false, 'Lua could not run the file after this,'
      .. ' so it stays as it is.'
end

--- The text's colors
--- @param lines string[]
--- @return SyntaxColoring
function M.highlight(lines)
  return get_parser().highlighter(lines)
end

--- The editor field's evaluator for this syntax
--- @return Evaluator
function M.evaluator()
  require('model.interpreter.eval.evaluator')
  return LuaEditorEval
end

return M
