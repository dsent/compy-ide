--- The file editor's way into the Lua language layer: the
--- editor's own rules on Lua text, around the language
--- layer's parser, formatter and gate (model.lang.lua), which
--- decide what is Lua and what a block may hold. Here are the
--- editor's: a draft is no file's top, so a `#!` line in it
--- is no Lua; a draft's empty lines stay (IS3.7); a whole file
--- keeps its `#!` first line through formatting; where a failure
--- shows (IS3.4, IS3.5); which reason a refusal names; and the
--- files a block names (IS1.5).

require('util.string.string')
require('model.lang.lua.error')
require('util.tree')
local check = require('model.lang.lua.check')
local format = require('model.lang.lua.format')
local analyzer = require('model.lang.lua.analyze')
local cursor_map = require('model.input.cursorMap')

local M = {
  --- the language layer's line limit, which notices name
  max_line_length = check.max_line_length,
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

--- A lexer failure the lexer names no place for, such as an
--- escape a string may not hold: the first quoted or long
--- string the parser does not read on its own
--- @param lines string[]
--- @return integer? l
--- @return integer? c
local failing_string = function(lines)
  local text = table.concat(lines, '\n')
  for _, el in ipairs(cursor_map.elements(text)) do
    local t = el.text
    local quoted = string.match(t, '^["\']') or string.match(t, '^%[=*%[')
    if quoted and not get_parser().parse('local _ = ' .. t) then
      return cursor_map.position(lines, el.s)
    end
  end
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
  if not l or l < 1 then
    local fl, fc = failing_string(lines)
    if fl then
      err.l, err.c = fl, fc
      return err
    end
  end
  --- an expression where a statement belongs fails as a
  --- whole, and the parser has read past it by then; every
  --- other failure is at the token the parser stopped at
  local msg = err.msg or ''
  local misplaced = string.find(msg,
    'statement was expected', 1, true)
  local tok = not misplaced and parse_err.token
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
  --- after a comment the parser names the failing token
  --- itself, the first one past the comment
  if after_comment(lines, l, err.c) then col = err.c end
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


--- The language layer's parser, with `failure` beside it:
--- the parser of the console's field and the file editor's
--- @return table
function M.parser()
  return setmetatable({ failure = M.failure },
    { __index = function(_, k) return get_parser()[k] end })
end

--- @param l string
--- @return boolean
local function is_blank(l)
  return string.match(l, '^%s*$') ~= nil
end

--- @param lines string[]
--- @return string[] --- the lines below an empty one
local function below_a_line(lines)
  local below = { '' }
  for i, l in ipairs(lines) do below[i + 1] = l end
  return below
end

--- A draft read as Lua reads it where it lands, below the
--- file's first line: a `#!` line, which the parser skips at
--- a file's top, is no Lua in it. The parser
--- the editor's field checks and colors with, so that the red
--- text and a refused submission agree (IS3.4).
--- @type table
M.draft_parser = setmetatable({
  --- @param lines string[]
  parse = function(lines)
    if type(lines) ~= 'table' or not M.is_header(lines[1]) then
      return get_parser().parse(lines)
    end
    return get_parser().parse(below_a_line(lines))
  end,
  --- @param lines string[]
  --- @param err Error --- as parse above returned it
  --- @return Error
  failure = function(lines, err)
    if type(lines) ~= 'table' or not M.is_header(lines[1]) then
      return M.failure(lines, err)
    end
    local failure = M.failure(below_a_line(lines), err)
    failure.l = failure.l - 1
    return failure
  end,
}, { __index = function(_, k) return get_parser()[k] end })

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
--- @return integer[]? --- where each line of `text` is now
local function keep_empty_lines(given, text)
  local a, b = gaps(given), gaps(text)
  if not a or not b or #a ~= #b then return text, nil end
  local add = {}
  for i = 1, #a do
    local ra = blank_runs(given, a[i][1], a[i][2])
    local rb = blank_runs(text, b[i][1], b[i][2])
    if #ra == #rb then
      for j = 1, #ra do add[rb[j].at] = ra[j].n - rb[j].n end
    end
  end
  local out, at = {}, {}
  for i, l in ipairs(text) do
    for _ = 1, add[i] or 0 do out[#out + 1] = '' end
    out[#out + 1] = l
    at[i] = #out
  end
  return out, at
end

--- The formatter's text at `width`, or nil when it does not
--- format: BufferModel's pretty printer
--- @param lines string[]
--- @param width integer
--- @return string[] text
--- @return boolean formatted
function M.format(lines, width)
  return format.format(lines, width)
end

--- A draft as the editor writes it: formatted, or as given
--- when it does not format or is no Lua where it lands. A
--- draft's empty lines between statements stay when
--- `keep_empty` asks (IS3.7).
--- @param lines string[]
--- @param width integer
--- @param keep_empty boolean?
--- @return string[] text
--- @return boolean formatted
function M.formatted(lines, width, keep_empty)
  if not M.draft_parser.parse(lines) then return lines, false end
  local text, formatted = format.format(lines, width)
  if formatted and keep_empty then
    text = keep_empty_lines(lines, text)
  end
  return text, formatted
end

--- Whether a file's first line is a header the language
--- skips: a `#!` line, as the parser and LuaJIT skip it. The
--- one answer the editor's header rules, whole-file
--- formatting and the reading of a draft share.
--- @param line string?
--- @return boolean
function M.is_header(line)
  return line ~= nil and string.match(line, '^#!') ~= nil
end

--- A file's blocks, or a draft's (`single`), as the language
--- layer's chunker splits them; a file of no lines has none
--- (IS1.1)
--- @param text str
--- @param width integer
--- @param single boolean?
--- @return boolean ok
--- @return Dequeue<Block>|string[]
--- @return any
function M.chunker(text, width, single)
  if not single and type(text) == 'table' and #text == 0 then
    require('util.dequeue')
    return true, Dequeue.typed('block')
  end
  return get_parser().chunker(text, width, single)
end

--- A whole file formatted, as Ctrl+Shift+F and `tidy()`
--- format it: a header line (is_header) stays as it is above
--- the rest, and the rest is formatted as a draft is
--- @param lines string[]
--- @param width integer
--- @return string[] text --- as given when it does not format
--- @return boolean formatted
function M.tidied(lines, width)
  local head = M.is_header(lines[1]) and { lines[1] } or {}
  local rest = {}
  for i = #head + 1, #lines do rest[#rest + 1] = lines[i] end
  --- a header alone has nothing below it to format
  if #rest == 0 then return lines, true end
  local out, formatted = M.formatted(rest, width)
  if not formatted then return lines, false end
  for _, l in ipairs(out) do head[#head + 1] = l end
  return head, true
end

--- @class SubmissionVerdict: GateVerdict
--- @field failure Error? --- the parse failure, at the failing
--- character, or `at_end` when the draft is only unfinished
--- @field long_line table? --- {l, len}: the line over the
--- limit a refusal names

--- The language layer's verdict on a draft (check.gate), as
--- the editor shows it. A draft that is no Lua where it lands
--- is refused with its failure, before anything is measured
--- (IS3.2). An accepted draft keeps its empty lines between
--- statements (IS3.7), each an empty-line block. A refusal
--- for a line names that line and its length.
--- @param lines string[]
--- @param width integer
--- @param max_block integer
--- @return SubmissionVerdict
function M.submission(lines, width, max_block)
  local draft = M.draft_parser
  local parses, err = draft.parse(lines)
  if not parses then
    local failure = draft.failure(lines, err)
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
  if verdict.blocks then
    --- every empty line of the draft is an empty-line block,
    --- those at its end too: the text is chunked as a file's,
    --- where each blank line is a block of its own
    local text, at = verdict.lines, nil
    if verdict.formatted then
      text, at = keep_empty_lines(lines, verdict.lines)
    end
    local long = verdict.long_line
    if long and at then long.l = at[long.l] end
    local _, blocks = M.chunker(text, width)
    verdict.lines, verdict.blocks = text, blocks
    verdict.oversized = {}
    for i in ipairs(blocks) do
      if check.excess(verdict, i) > 0 then
        table.insert(verdict.oversized, i)
      end
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
  local li = arg.lineinfo
  return { {
    line = li and li.first and li.first.line,
    name = arg[1],
    file = name == 'dofile' or nil,
  } }
end

--- The files a text names (IS1.5): `require` and `dofile`
--- with the name written out
--- @param ast luaAST
--- @return table[] --- {line, name, file}
function M.references(ast)
  return table.flatten(Tree.preorder(ast, reference))
end

--- The language layer's analysis of a parsed file, its
--- definitions, with the files it names
--- @param ast luaAST
--- @return SemanticInfo
function M.analyze(ast)
  local info = analyzer.analyze(ast)
  info.requires = M.references(ast)
  return info
end

return M
