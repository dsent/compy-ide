require("model.lang.lua.error")
require("model.lang.highlight")
local ct = require("conf.lua")
require("util.debug")
require("util.string.string")
require("util.dequeue")

--- @class luaAST : token

--- @class Comment
--- @field text string
--- @field position CommentPos
--- @field idf integer
--- @field idl integer
--- @field first Cursor
--- @field last Cursor
--- @field multiline boolean
--- @field prepend_newline boolean

return function(lib)
  local l = lib or 'metalua'
  local add_paths = {
    '',
    'lib/' .. l .. '/?.lua',
    'lib/?.lua',
    -- 'lib/lua/5.1/?'
  }
  if love and not TESTING then
    local love_paths = string.join(add_paths, ';')
    love.filesystem.setRequirePath(
      love.filesystem.getRequirePath() .. love_paths)
  else
    local lib_paths = string.join(add_paths, ';src/')
    package.path = lib_paths .. ';' .. package.path
  end

  local mlc = require('metalua.metalua.compiler').new()
  local a2s_module = 'metalua.metalua.compiler.ast_to_src'
  local long_brackets = require(a2s_module).long_brackets

  --- Iterates over lexstream
  --- @param stream table
  --- @return table tokens
  local realize_stream = function(stream)
    local tokens = Dequeue.typed('string')
    local n
    repeat
      n = stream:next()
      tokens:append(n)
    until n.tag == 'Eof'
    return tokens
  end

  --- Parses text table to lexstream
  --- @param code str
  --- @return table lexstream
  local stream_tokens = function(code)
    local c = string.unlines(code)
    local lexstream = mlc:src_to_lexstream(c)
    return lexstream
  end

  --- Parses text table to tokens
  --- @param code str
  --- @return table
  local tokenize = function(code)
    local stream = stream_tokens(code)
    return realize_stream(stream)
  end

  --- Parses lexstream to AST
  --- @param stream table
  --- @return ParseResult
  local parse_stream = function(stream)
    return mlc:lexstream_to_ast(stream)
  end

  --- Finds error location and message in parse result
  --- @param result string
  --- @return Error
  local get_error = function(result)
    local err_lines = string.lines(result)
    local err_first_line = err_lines[1]
    local err_second_line = err_lines[2]
    local colons = string.split(err_first_line, ':')
    local colons2 = string.split(err_second_line, ':')
    local match2 = string.gmatch(colons2[2] or '', '%d+')
    local line = tonumber(match2() or '') or -1
    local char = tonumber(match2() or '') or -1
    local errmsg = string.trim(colons[4])
    return Error(errmsg, char, line)
  end

  --- Read lexstream and determine highlighting
  --- @param tokens luaAST
  --- @return SyntaxColoring
  local syntax_hl = function(tokens)
    if not tokens then return {} end

    --- @type SyntaxColoring
    local colored_tokens = SyntaxColoring()

    --- @param tag string
    --- @param single boolean
    --- @return TokenType?
    local function getType(tag, single)
      if tag == 'Keyword' then
        if single then
          return 'kw_single'
        else
          return 'kw_multi'
        end
      elseif tag == 'Number' then
        return 'number'
      elseif tag == 'String' then
        return 'string'
      elseif tag == 'Id' then
        return 'identifier'
      else
        return nil
      end
    end

    --- @param first Cursor
    --- @param last Cursor
    --- @param text string
    --- @param lex_t LexType
    --- @param tl integer
    local function multiline(first, last, text, lex_t, tl)
      local ls = first.l
      local le = last.l
      local cs = first.c
      local ce = last.c
      local lines = string.lines(text)

      local n_lines = #lines
      local till = le + 1 - ls
      -- if the first line has no text after the block starter,
      -- we need to add an empty line on the front
      if n_lines + 1 == till then
        table.insert(lines, 1, '')
      end

      -- first line
      for i = cs, cs + string.ulen(lines[1]) + tl do
        colored_tokens[ls][i] = ct[lex_t]
      end
      for i = 2, till - 1 do
        local e = string.ulen(lines[i])
        for j = 1, e + 2 do
          colored_tokens[ls + i - 1][j] = ct[lex_t]
        end
      end
      -- last line
      for i = 1, ce do
        colored_tokens[le][i] = ct[lex_t]
      end
    end

    --- @param t token
    --- @return SyntaxColoring?
    local function colorize(t)
      local text     = t[1]
      local tag      = t.tag
      local lfi      = t.lineinfo.first
      local lla      = t.lineinfo.last
      local first    = { l = lfi.line, c = lfi.column }
      local last     = { l = lla.line, c = lla.column }
      -- local first_f = lfi.facing
      -- local last_f  = lla.facing
      local comments = {}
      local function add_comment(c)
        local id = c.lineinfo.first.id
        if not comments[id] then
          local comment_text = c[1]
          if string.sub(comment_text, 1, 2) == '[[' then
            -- TODO unclosed comment block
            -- orig_print(Debug.terse_t(c))
          end

          local cfi    = c.lineinfo.first
          local cla    = c.lineinfo.last
          local cfirst = { l = cfi.line, c = cfi.column }
          local clast  = { l = cla.line, c = cla.column }
          local li     = {
            first = cfirst,
            last = clast,
            text = comment_text,
          }
          comments[id] = li
        end
      end
      if lfi.comments then
        for _, c in ipairs(lfi.comments) do
          add_comment(c)
        end
      end
      if lla.comments then
        for _, c in ipairs(lla.comments) do
          add_comment(c)
        end
      end

      -- normal tokens
      if first.l == last.l then
        local l = first.l
        local single = false
        if string.ulen(text) == 1 then
          single = true
        end
        for i = first.c, last.c do
          local typ            = getType(tag, single)
          colored_tokens[l][i] = ct[typ]
        end
      else
        local tl = 2 --- a string block starts with '[['
        multiline(first, last, text, 'string', tl)
      end

      -- comments
      for _, co in pairs(comments) do
        local ls = co.first.l
        local le = co.last.l
        local cs = co.first.c
        local ce = co.last.c
        if ls == le then
          for i = cs, ce do
            colored_tokens[ls][i] = ct['comment']
          end
        else
          --- a block comment starts with '--' and its long
          --- bracket, '[[' or one with a level, '[==['
          local tl = 2 + #long_brackets(co.text)
          multiline(co.first, co.last, co.text, 'comment', tl)
        end
      end
    end -- colorize

    if tokens.next then
      repeat
        local t = tokens:next()
        colorize(t)
      until t.tag == 'Eof'
    else
      for _, t in pairs(tokens) do
        colorize(t)
      end
    end
    return colored_tokens
  end

  --------------------
  ---    Public    ---
  --------------------

  --- @param ast luaAST
  --- @param ... any
  --- @return string
  local ast_to_src = function(ast, ...)
    local a2s = mlc:a2s(...)
    return a2s:run(ast)
  end

  --- The token the parser stopped at: the lexstream's current
  --- one after a failed parse. Nil when the lexer itself
  --- failed and has no token to show.
  --- @param stream table
  --- @return {l: integer, c: integer, eof: boolean}?
  local failed_token = function(stream)
    --- the parser fails with the lexer between tokens, right
    --- after the last one it took or at the end; the lexer
    --- fails inside a token, having read on into it
    local last = stream.lineinfo_last_extracted
    local between = stream.i == last.offset + 1
        or last.offset > #stream.src
    if not between then return nil end
    local ok, tok = pcall(stream.peek, stream)
    local li = ok and type(tok) == 'table' and tok.lineinfo
    local first = li and li.first
    if not first or not first.line then return nil end
    return {
      l = first.line, c = first.column, eof = tok.tag == 'Eof'
    }
  end

  --- Parses code to AST
  --- @param code str
  --- @return boolean success
  --- @return ParseResult<luaAST>
  local parse = function(code)
    local stream = stream_tokens(code)
    local ok, res = pcall(parse_stream, stream)
    local ret = res
    if not ok then
      ---@diagnostic disable-next-line: param-type-mismatch
      ret = get_error(res)
      ret.token = failed_token(stream)
    end
    return ok, ret
  end

  --- @param code string[]
  --- @return string[]?
  local pprint = function(code, wrap)
    local w = wrap or 80
    local ok, r = parse(code)
    if ok then
      --- @diagnostic disable-next-line: param-type-mismatch
      local src = ast_to_src(r, {}, w)
      local lines = string.lines(src)
      --- a comment closing the code leaves the newline meant
      --- for a statement after it; that is no blank line
      while #lines > 1 and string.match(lines[#lines], '^%s*$') do
        table.remove(lines)
      end
      return lines
    end
  end

  --- The text of every comment in the code, in order
  --- @param code str
  --- @return string[]?
  local comments = function(code)
    local ok, tokens = pcall(tokenize, code)
    if not ok then return end
    local found, seen = {}, {}
    local function add(list)
      for _, c in ipairs(list or {}) do
        local id = c.lineinfo.first.id
        if not seen[id] then
          seen[id] = true
          table.insert(found, c)
        end
      end
    end
    for _, t in ipairs(tokens) do
      add(t.lineinfo.first.comments)
      add(t.lineinfo.last.comments)
    end
    table.sort(found, function(a, b)
      local fa, fb = a.lineinfo.first, b.lineinfo.first
      if fa.line ~= fb.line then return fa.line < fb.line end
      return fa.column < fb.column
    end)
    local texts = {}
    for _, c in ipairs(found) do table.insert(texts, c[1]) end
    return texts
  end

  --- Highlight string array
  --- @param code str
  --- @return SyntaxColoring
  local highlighter = function(code)
    local ok, tokens = pcall(tokenize, code)
    if not ok then
      return SyntaxColoring()
    end
    return syntax_hl(tokens)
  end

  --- The source lines of every comment in the code. A long
  --- comment is one span; a run of `--` lines, which the lexer
  --- hands over as one comment, is a span per line.
  --- @param code str
  --- @return integer[][] --- {first, last} line pairs
  local comment_spans = function(code)
    local ok, tokens = pcall(tokenize, code)
    if not ok then return {} end
    local spans, seen = {}, {}
    local function add(list)
      for _, c in ipairs(list or {}) do
        local li = c.lineinfo
        if not seen[li.first.id] then
          seen[li.first.id] = true
          local f, l = li.first.line, li.last.line
          if c[2] then
            table.insert(spans, { f, l })
          else
            for ln = f, l do table.insert(spans, { ln, ln }) end
          end
        end
      end
    end
    for _, t in ipairs(tokens) do
      add(t.lineinfo.first.comments)
      add(t.lineinfo.last.comments)
    end
    return spans
  end

  --- Blocks of source lines, every line in exactly one block,
  --- in order, as it is written: a block is the lines of
  --- statements and comments that share a line, so that no
  --- line boundary divides them; a blank line is an empty
  --- block of its own; a line nothing claims (a `#!` first
  --- line, which the parser skips) is a block of its own.
  --- @param lines string[]
  --- @param ast luaAST
  --- @return Dequeue<Block>
  local source_blocks = function(lines, ast)
    local spans = comment_spans(lines)
    for _, v in ipairs(ast) do
      local li = v.lineinfo
      table.insert(spans, { li.first.line, li.last.line })
    end
    table.sort(spans, function(a, b) return a[1] < b[1] end)
    local n = #lines
    local ret = Dequeue.typed('block')
    local ln = 1
    --- the lines from `ln` up to `stop`, which no span holds
    local function single_lines(stop)
      while ln < stop do
        if string.match(lines[ln], '^%s*$') then
          ret:push_back(Empty(ln))
        else
          ret:push_back(Chunk({ lines[ln] }, Range.singleton(ln)))
        end
        ln = ln + 1
      end
    end
    local i = 1
    while i <= #spans do
      local s, e = spans[i][1], spans[i][2]
      i = i + 1
      while i <= #spans and spans[i][1] <= e do
        e = math.max(e, spans[i][2])
        i = i + 1
      end
      s, e = math.max(s, ln), math.min(e, n)
      if s <= e then
        single_lines(s)
        ret:push_back(Chunk(table.slice(lines, s, e), Range(s, e)))
        ln = e + 1
      end
    end
    single_lines(n + 1)
    return ret
  end

  --- @param text string[]
  --- @param _ integer --- the width; no block is wrapped to it
  --- @param single boolean
  --- @return boolean ok
  --- @return Block[]
  --- @return ParseResult<luaAST>
  local chunker = function(text, _, single)
    require("model.editor.content")
    if string.is_non_empty_string_array(text) then
      local ok, r = parse(text)
      if ok then
        local lines = type(text) == 'string'
            and string.lines(text) or text
        local ret = source_blocks(lines, r)
        --- blank lines typed at the end of the block are one
        --- empty block
        while single and #ret > 1 and ret:last():is_empty()
          and ret[#ret - 1]:is_empty() do
          ret:pop_back()
        end
        return true, ret, r
      else
        --- content is not valid lua
        return false, Dequeue(text, 'string'), r
      end
    else
      --- a file of blank lines keeps every one of them
      local empties = Dequeue.typed('block')
      local n = (not single and type(text) == 'table') and #text or 1
      for ln = 1, math.max(n, 1) do
        empties:push_back(Empty(ln))
      end
      return true, empties, r
    end
  end

  --- @param code str
  --- @param n integer?
  --- @return string[]?
  local function trunc(code, n)
    local lines = n or 1
    if lines == 1 then
      local txt = string.lines(code)
      local line1 = txt[1]:sub(1, -1) .. '…'
      return { line1 }
    end
  end

  return {
    parse       = parse,
    pprint      = pprint,
    comments    = comments,
    highlighter = highlighter,
    ast_to_src  = ast_to_src,
    chunker     = chunker,
    trunc       = trunc,
  }
end
