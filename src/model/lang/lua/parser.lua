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
  local cursor_map = require('model.lang.lua.cursor_map')
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

  --- @param ast luaAST
  --- @param ... any
  --- @return Comment[]
  local ast_extract_comments = function(ast, ...)
    local a2s = mlc:a2s(...)
    return a2s:extract_comments(ast)
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
  --- when it failed for want of more, which `at_end` says.
  --- @param code str
  --- @param parse_err Error --- as parse returns it
  --- @return Error --- a new one, at the boundary
  local locate_failure = function(code, parse_err)
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

  --- @param text string[]
  --- @param w integer
  --- @param single boolean
  --- @return boolean ok
  --- @return Block[]
  --- @return ParseResult<luaAST>
  local chunker = function(text, w, single)
    require("model.editor.content")
    if string.is_non_empty_string_array(text) then
      local wrap = w
      local ret = Dequeue.typed('block')
      local ok, r = parse(text)

      local has_lines = false
      if ok then
        local idx = 1  -- block number
        local last = 0 -- last line number
        local comment_ids = {}
        local comment_lines = {}
        --- Create chunk from comment text and pos
        --- @param ctext str
        --- @param c Comment
        --- @param range Range
        local add_comment_block = function(ctext, c, range)
          ret:insert(
            Chunk.new(ctext, range),
            idx)
          comment_ids[c.idf] = true
          comment_ids[c.idl] = true
          comment_lines[c.first.l] = true
        end
        --- Take ownership of the comments the statement's own chunk
        --- already carries. The chunk is sliced from the source
        --- lines, so a comment starting inside its range is on
        --- screen already; a block of its own would draw over the
        --- code and grow the file on every render.
        --- @param comments Comment[]
        --- @param sfl integer --- statement's first line
        --- @param sll integer --- statement's last line
        local claim_own_comments = function(comments, sfl, sll)
          for _, c in ipairs(comments) do
            local cfl = c.first.l
            if cfl >= sfl and cfl <= sll then
              comment_ids[c.idf] = true
              comment_ids[c.idl] = true
              comment_lines[cfl] = true
            end
          end
        end
        --- One empty block per blank line before `ln', so a
        --- run of blank lines stays a run
        --- @param ln integer
        local add_empties_before = function(ln)
          for el = last + 1, ln - 1 do
            ret:insert(Empty(el), idx)
            idx = idx + 1
          end
        end
        --- @param comments Comment[]
        --- @param pos CommentPos
        local get_comments = function(comments, pos)
          for _, c in ipairs(comments) do
            -- Log.warn('c', c.position)
            -- Log.warn(Debug.terse_t(c, nil, nil, true))
            if c.position == pos
                and not (comment_ids[c.idl] or comment_ids[c.idf]
                    or comment_lines[c.first.l])
            then
              local cfl, cll = c.first.l, c.last.l
              add_empties_before(cfl)
              if cfl == cll then
                local ctext = '--' .. c.text
                add_comment_block(ctext, c, Range.singleton(cfl))
                idx = idx + 1
                last = cll
              else
                local lines = string.lines(c.text)
                if c.multiline then
                  if c.prepend_newline then
                    table.insert(lines, 1, '')
                  end
                  local open, close = long_brackets(c.text)
                  local l1 = lines[1] or ''
                  if #lines == 1 then
                    lines[1] = '--' .. open .. l1 .. close
                  else
                    local llast = lines[#lines] or ''
                    lines[1] = '--' .. open .. l1
                    lines[#lines] = llast .. close
                  end
                  local wrapped = string.wrap_array(lines, wrap)
                  local w_t = string.unlines(wrapped)

                  add_comment_block(wrapped, c, Range(cfl, cll))
                  idx = idx + 1
                  last = cll
                else
                  for i, l in ipairs(lines) do
                    local ln = cfl + i - 1
                    local ctext = '--' .. l
                    add_comment_block(ctext, c, Range.singleton(ln))
                    idx = idx + 1
                    last = cll
                  end
                end
              end
            end
          end
        end

        for _, v in ipairs(r) do
          has_lines = true
          local li = v.lineinfo
          local fl, ll = li.first.line, li.last.line

          local comments = ast_extract_comments(v, {}, wrap)

          claim_own_comments(comments, fl, ll)
          get_comments(comments, 'first')
          add_empties_before(fl)
          --- a statement starting on the line the one before
          --- it ends on shares that one's block: no line
          --- boundary divides them (FR3.1)
          local prev = ret[idx - 1]
          if fl <= last and prev and prev.tag == 'chunk' then
            local pfl = prev.pos.start
            ll = math.max(ll, last)
            prev.lines = Dequeue(table.slice(text or {}, pfl, ll))
            prev.pos = Range(pfl, ll)
          else
            local tex = table.slice(text or {}, fl, ll)
            local chunk = Chunk(tex, Range(fl, ll))
            ret:insert(chunk, idx)
            idx = idx + 1
          end
          last = ll

          get_comments(comments, 'last')
        end

        if not has_lines then
          --- @diagnostic disable-next-line: param-type-mismatch
          local single_comment = ast_extract_comments(r, {}, wrap)
          get_comments(single_comment, 'first')
        end

        if not single then
          --- the blank lines ending the file; its final
          --- newline ends its last line and is no block
          add_empties_before(#text + 1)
        elseif ret:last().tag ~= 'empty' then
          --- blank lines typed at the end of the block: one
          --- empty block for each (IS3.7)
          for ln = last + 1, #string.lines(text) do
            ret:push_back(Empty(ln))
          end
        end
        return true, ret, r
      else
        --- content is not valid lua
        return false, Dequeue(text, 'string'), r
      end
    else
      --- a file of blank lines keeps every one of them
      local empties = Dequeue.typed('block')
      local whole = not single and type(text) == 'table'
      --- a file of no lines has no block (IS1.1)
      if whole and #text == 0 then return true, empties, r end
      local n = whole and #text or 1
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
    failure     = locate_failure,
    pprint      = pprint,
    comments    = comments,
    highlighter = highlighter,
    ast_to_src  = ast_to_src,
    chunker     = chunker,
    trunc       = trunc,
  }
end
