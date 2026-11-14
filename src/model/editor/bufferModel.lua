require("model.editor.content")
local analyzer = require("model.lang.lua.analyze")
local bsi = require("model.editor.bufferSemanticInfo")

local class = require('util.class')
require('util.table')
require('util.range')
require('util.string.string')
require('util.dequeue')
local textfile = require('util.textfile')

--- The lines of a block as the file holds them: an empty
--- line keeps the spaces it was read with
--- @param b Block
--- @return string[]
local function own_lines(b)
  if b:is_empty() then return { b.text or '' } end
  return b.lines
end

--- Convert Blocks to string array
--- @param blocks Block[]
--- @return Dequeue<string>
local function render_blocks(blocks)
  local ret = Dequeue.typed('string')
  for _, v in ipairs(blocks) do
    ret:append_all(own_lines(v))
  end
  return ret
end

--- The blocks hold the file's lines 1 to n, each once, in
--- order and as they are: written back, a file the user did
--- not touch is the file that was read (FR3.1)
--- @param blocks Block[]
--- @param lines string[] --- what the chunker was given
--- @return boolean
local function tiles(blocks, lines)
  local ln = 1
  for _, b in ipairs(blocks) do
    local p = b.pos
    if not p or p.start ~= ln then return false end
    local own = own_lines(b)
    if #own ~= p:len() then return false end
    for i = 1, #own do
      if own[i] ~= lines[ln + i - 1] then return false end
    end
    ln = p.fin + 1
  end
  return ln == #lines + 1
end

--- A Lua file's lines as blocks. Text that does not parse is
--- no reason to keep a file shut: it comes a line per block,
--- every line as it is, so that it can be repaired (IS1.2).
--- Blocks that would not give back every line as read come
--- the same way: a line lost on opening is lost on the next
--- save.
--- @param chunker Chunker
--- @param lines string[]
--- @return Dequeue<Block> blocks
--- @return boolean invalid --- the text did not parse, or
--- its blocks would not keep it
local function file_blocks(chunker, lines)
  local ok, blocks = chunker(lines)
  if ok then
    for _, b in ipairs(blocks) do
      local l = b:is_empty() and b.pos and lines[b.pos.start]
      if l and l ~= '' then b.text = l end
    end
    if tiles(blocks, lines) then return blocks, false end
  end
  local out = Dequeue.typed('block')
  for ln, l in ipairs(lines) do
    if l == '' then
      out:push_back(Empty(ln))
    else
      out:push_back(Chunk(l, Range.singleton(ln)))
    end
  end
  return out, true
end

--- A text's lines, each with the line ending after it in the
--- text, '' after a last line that has none
--- @param text string
--- @return string[] lines
--- @return string[] ends
local function ended_lines(text)
  local lines, ends = {}, {}
  local i, n = 1, #text
  while i <= n do
    local p = string.find(text, '[\r\n]', i)
    if not p then
      lines[#lines + 1] = string.sub(text, i)
      ends[#ends + 1] = ''
      break
    end
    local e = string.sub(text, p, p)
    if e == '\r' and string.sub(text, p + 1, p + 1) == '\n' then
      e = '\r\n'
    end
    lines[#lines + 1] = string.sub(text, i, p - 1)
    ends[#ends + 1] = e
    i = p + #e
  end
  return lines, ends
end

--- The line ending most lines of a text end with; of two as
--- frequent, the one that comes first in the text; a newline
--- when there is none
--- @param ends string[]
--- @return string
local function main_ending(ends)
  local count, order = {}, {}
  for _, e in ipairs(ends) do
    if e ~= '' then
      if not count[e] then
        count[e] = 0
        order[#order + 1] = e
      end
      count[e] = count[e] + 1
    end
  end
  local best
  for _, e in ipairs(order) do
    if not best or count[e] > count[best] then best = e end
  end
  return best or '\n'
end

--- The text to write: every line with its own ending, and
--- the file's main ending for a line that has none, the last
--- one too (util.textfile)
--- @param lines string[]
--- @param ends string[]
--- @param eol string --- the file's main ending
--- @return string
local function file_text(lines, ends, eol)
  local out = {}
  for i, l in ipairs(lines) do
    local e = ends[i]
    if not e or e == '' then e = eol end
    out[i] = l .. e
  end
  return table.concat(out)
end

--- @param n integer
--- @return string[] --- the ending of `n` new lines: none of
--- their own, so each is written with the main one
local function no_ends(n)
  local ends = {}
  for i = 1, n do ends[i] = '' end
  return ends
end

--- Todo: convert to class, store revmap
--- @alias Content Dequeue<string>|Dequeue<Block>

--- @param name string
--- @param content str --- the file's text, or its lines
--- @param save function
--- @param chunker Chunker?
--- @param highlighter Highlighter?
--- @param printer Printer?
--- @param truncer function?
--- @return BufferModel?
local function new(
    name,
    content,
    save,
    chunker,
    highlighter,
    printer,
    truncer)
  local _content, sel, ct, semantic
  local invalid = false
  --- every line keeps the ending it was read with; lines are
  --- held without it, in blocks, drafts and checks, and their
  --- endings beside them (`ends`, file_text). The newline
  --- ending the last line is no line of its own.
  local eol = '\n'
  local stored, lines, ends
  if type(content) == 'string' then
    stored = content
    lines, ends = ended_lines(content)
    eol = main_ending(ends)
  else
    lines = type(content) == 'table' and string.lines(content)
        or textfile.lines(content)
    ends = no_ends(#lines)
  end

  local function plaintext()
    ct = 'plain'
    --- a block per line (IS8)
    _content = Dequeue(lines, 'string')
    sel = 1
  end
  --- only passing this around so the linter shuts up about nil
  --- @param chk function
  local function luacontent(chk)
    ct = 'lua'
    _content, invalid = file_blocks(chk, lines)
    sel = 1
  end

  if type(chunker) == "function" then
    luacontent(chunker)
  elseif type(highlighter) == 'function' then
    plaintext()
    ct = 'md'
  else
    plaintext()
  end

  local self = {
    name = name or 'untitled',
    content = _content,
    content_type = ct,
    save_file = save,
    chunker = chunker,
    highlighter = highlighter,
    printer = printer,
    truncer = truncer,
    revmap = {},
    semantic = semantic,
    selection = sel,
    active_line = 1,
    invalid = invalid,
    eol = eol,
    ends = ends,
    stored = stored,
    history = {},
    redo_history = {}
  }
  local id = tostring(self):gsub('table: ', '')
  self.id = id
  return self
end

--- @param self BufferModel
local function lateinit(self)
  self:analyze()
end

--- @class BufferModel : Object
--- @field name string
--- @field content Dequeue -- Content
--- @field content_type ContentType
--- @field save_file function
--- @field selection integer
--- @field active_line integer --- source line inside the selection
--- @field loaded integer?
--- @field key string? --- the file's identity, project and name
--- @field input UserInputModel --- the file's own editor field
--- @field eol string --- the file's main line ending, which a
--- line without one of its own is written with
--- @field ends string[] --- each line's own ending, '' for
--- none
--- @field invalid boolean --- a Lua file whose text does not
--- parse: its blocks are its lines, until it parses again
--- @field semantic BufferSemanticInfo?
--- @field revmap table?
---
--- @field chunker Chunker
--- @field highlighter Highlighter
--- @field printer Printer
--- @field truncer function
--- @field move_selection function
--- @field get_selection function
--- @field get_selected_text function
--- @field delete_selected_text function
--- @field replace_selected_text function
--- @field get_text_content function
BufferModel = class.create(new, lateinit)

function BufferModel:get_id()
  return self.id
end

--- The block-level undo (1.1): every file operation since
--- the file was opened, none dropped, since every action
--- stays undoable while the file is open (IS6.6). A step is
--- a trimmed diff — the common prefix and suffix of the file
--- before/after are cut, so what remains is exactly the
--- affected line range, whatever the operation was (accept,
--- move, delete, insert, discard pair): the timeline grows
--- with the text changed, and goes when the file is left.
--- Applying a step is a splice; the caller re-chunks and
--- saves, the same path every write takes. A step carries
--- each line's ending, so that undo and redo give a line
--- back the one it had.

--- The file's lines and their endings, as a change found
--- them: what it is undone to (push_history), and what a
--- refused one puts back (restore)
--- @class TextState
--- @field lines string[]
--- @field ends string[]

--- @return TextState
function BufferModel:snapshot()
  local lines = {}
  for i, l in ipairs(self:get_text_content()) do lines[i] = l end
  return { lines = lines, ends = table.clone(self.ends) }
end

--- @param a TextState
--- @param i integer
--- @param b TextState
--- @param j integer
--- @return boolean --- line `i` of `a` is line `j` of `b`,
--- its ending included
local function same_line(a, i, b, j)
  return a.lines[i] == b.lines[j] and a.ends[i] == b.ends[j]
end

--- @param before TextState --- the file pre-operation
--- @param after TextState --- the file post-operation
--- @param sel_b integer --- selection before
--- @param sel_a integer --- selection after
--- @return table? --- nil when nothing changed
local function make_step(before, after, sel_b, sel_a)
  local nb, na = #before.lines, #after.lines
  local head = 0
  while head < nb and head < na
      and same_line(before, head + 1, after, head + 1) do
    head = head + 1
  end
  local tail = 0
  while tail < nb - head and tail < na - head
      and same_line(before, nb - tail, after, na - tail) do
    tail = tail + 1
  end
  if head + tail == nb and nb == na then return end
  local step = {
    start = head + 1,
    removed = {},
    removed_ends = {},
    inserted = {},
    inserted_ends = {},
    sel_before = sel_b,
    sel_after = sel_a,
  }
  for i = head + 1, nb - tail do
    table.insert(step.removed, before.lines[i])
    table.insert(step.removed_ends, before.ends[i])
  end
  for i = head + 1, na - tail do
    table.insert(step.inserted, after.lines[i])
    table.insert(step.inserted_ends, after.ends[i])
  end
  return step
end

--- Record the change from `before` to the file as it is now
--- @param before TextState
--- @param sel_b integer
--- @param sel_a integer
function BufferModel:push_history(before, sel_b, sel_a)
  local step = make_step(before, self:snapshot(), sel_b, sel_a)
  if not step then return end
  table.insert(self.history, step)
  self.redo_history = {}
end

--- @private
--- Splice lines into the content and re-chunk. Lines given
--- without their endings take, at either edge of the lines
--- they replace, the ending of a line they are the same as;
--- the others have none of their own.
--- The re-chunk may split the file anew: a file that starts
--- or stops parsing turns from lines into statements or
--- back. So the browsing position is kept as a line, not a
--- block number: it ends on the block that holds the line it
--- stood on, or, that line gone, the line after the new ones.
--- @param start integer
--- @param n_out integer --- lines to remove
--- @param lines_in string[]
--- @param ends_in string[]?
function BufferModel:_splice(start, n_out, lines_in, ends_in)
  local lines = self:snapshot().lines
  local ends = self.ends
  local n_in = #lines_in
  local function carry(ln)
    if ln < start then return ln end
    if ln >= start + n_out then return ln - n_out + n_in end
    return start + n_in
  end
  local at = carry((self:_span_of(self.selection)))
  if not ends_in then
    ends_in = no_ends(n_in)
    local head = 0
    while head < n_out and head < n_in
        and lines[start + head] == lines_in[head + 1] do
      ends_in[head + 1] = ends[start + head]
      head = head + 1
    end
    local tail = 0
    local last = start + n_out - 1
    while tail < n_out - head and tail < n_in - head
        and lines[last - tail] == lines_in[n_in - tail] do
      ends_in[n_in - tail] = ends[last - tail]
      tail = tail + 1
    end
  end
  for _ = 1, n_out do
    table.remove(lines, start)
    table.remove(ends, start)
  end
  for i = n_in, 1, -1 do
    table.insert(lines, start, lines_in[i])
    table.insert(ends, start, ends_in[i] or '')
  end
  if self.content_type == 'lua' then
    self.content, self.invalid = file_blocks(self.chunker, lines)
  else
    self.content = Dequeue(lines)
  end
  self:set_selection(self:_position_of_line(at))
end

--- Replace the whole text and re-chunk it
--- @param lines string[]
--- @param ends string[]? --- their endings (_splice)
function BufferModel:replace_text(lines, ends)
  self:_splice(1, #self:get_text_content(), lines, ends)
end

--- Put the file back as a snapshot holds it
--- @param state TextState
function BufferModel:restore(state)
  self:replace_text(state.lines, state.ends)
end

--- @return table? --- the applied step, nil when empty
function BufferModel:undo()
  local n = #self.history
  if n == 0 then return end
  local step = self.history[n]
  table.remove(self.history, n)
  self:_splice(step.start, #step.inserted, step.removed,
    step.removed_ends)
  table.insert(self.redo_history, step)
  return step
end

--- @return table? --- the applied step, nil when empty
function BufferModel:redo()
  local n = #self.redo_history
  if n == 0 then return end
  local step = self.redo_history[n]
  table.remove(self.redo_history, n)
  self:_splice(step.start, #step.removed, step.inserted,
    step.inserted_ends)
  table.insert(self.history, step)
  return step
end

function BufferModel:analyze()
  if self.content_type ~= 'lua' then return end
  local lines = string.lines(self:get_text_content())
  local ok, blocks, ast = self.chunker(lines)
  if not ok then return end
  local anaok, ana = pcall(analyzer.analyze, ast)
  if not anaok then return end
  for bi, v in ipairs(blocks) do
    if (v.pos) then
      for _, l in ipairs(v.pos:enumerate()) do
        self.revmap[l] = bi
      end
    end
  end
  self.semantic = bsi.convert(ana, self.revmap)
end

function BufferModel:rechunk()
  if self.content_type ~= 'lua' then return end
  local content = self:get_text_content()
  self.content, self.invalid = file_blocks(self.chunker, content)
end

--- A file is written as its lines, each with its line
--- ending (file_text)
function BufferModel:save()
  self:_text_change()
  local text = self:get_text_content()
  self:analyze()
  local out = file_text(text, self.ends, self.eol)
  local ok, err = self.save_file(out)
  if ok then self.stored = out end
  return ok, err
end

function BufferModel:highlight()
  if self.highlighter then
    local text = self:get_text_content()
    self.hl = self.highlighter(text)
  end
end

--- @return Dequeue
function BufferModel:get_content()
  return self.content
end

--- Return the buffer content as a string array
--- @return string[] content
function BufferModel:get_text_content()
  --- TODO require
  require = _G.o_require or _G.require
  if self.content_type == 'lua'
  then
    return render_blocks(self.content)
  else
    return self.content:items()
  end
end

--- @return SyntaxColoring? hl
function BufferModel:get_highlight()
  if self.highlighter
  then
    return self.hl
  end
end

--- Returns number of lines/blocks
--- @return integer
function BufferModel:get_content_length()
  return #(self.content) or 0
end

--- @param dir VerticalDir
--- @param by integer
--- @param warp boolean?
--- @param move boolean?
--- @return boolean moved
function BufferModel:move_selection(dir, by, warp, move)
  local l = self:get_content_length()
  local last = (function()
    if move then return l end
    return l
  end)()
  if warp then
    if dir == 'up' then
      self.selection = 1
      self:clamp_active_line()
      return true
    end
    if dir == 'down' then
      self.selection = last
      --- the file's last line, which ends its last block
      self.active_line = self:get_selection_lines().fin
      self:clamp_active_line()
      return true
    end
    return false
  end

  local cur = self.selection
  local by = by or 1
  if dir == 'up' then
    if (cur - by) >= 1 then
      self.selection = cur - by
      self:clamp_active_line()
      return true
    end
  end
  if dir == 'down' then
    if (cur + by) <= last + 1 then
      self.selection = cur + by
      self:clamp_active_line()
      return true
    end
  end
  return false
end

--- @param sel integer
function BufferModel:set_selection(sel)
  local max = self:get_content_length() + 1
  if not sel or sel < 1 then sel = 1 end
  if sel > max then sel = max end
  self.selection = sel
  self:clamp_active_line()
end

--- Get index of selected line/block
--- @return integer blocknum
function BufferModel:get_selection()
  return self.selection
end

--- @private
--- @return Block?
function BufferModel:_get_selected_block()
  if self.content_type == 'plain' then return end

  local sel = self.selection
  if sel == self:get_content_length() + 1 then
    local last = self.content:last()
    local ln = (last and last.pos.fin or 0) + 1
    return Empty(ln)
  end
  return self.content[sel]
end

--- Get the line number of selection first line
--- @return integer
function BufferModel:get_selection_start_line()
  if self.content_type == 'lua' then
    local b = self:_get_selected_block()
    if b then
      local ln = b.pos.start
      return ln
    end
  end
  return self.selection
end

--- Source-line span of the selected block
--- @return Range
function BufferModel:get_selection_lines()
  if self.content_type == 'lua' then
    local b = self:_get_selected_block()
    if b and b.pos then return b.pos end
  end
  return Range.singleton(self.selection)
end

--- @return integer
function BufferModel:get_active_line()
  return self.active_line
end

--- The block owning a source line
--- @param ln integer
--- @return integer? block index
function BufferModel:block_at_line(ln)
  if self.content_type ~= 'lua' then
    if ln >= 1 and ln <= self:get_content_length() then
      return ln
    end
    return nil
  end
  for i, b in ipairs(self.content) do
    if b.pos and b.pos:inc(ln) then return i end
  end
  return nil
end

--- @param ln integer
function BufferModel:set_active_line(ln)
  self.active_line = ln
  self:clamp_active_line()
end

--- Pull the active line into the selected block
function BufferModel:clamp_active_line()
  local span = self:get_selection_lines()
  local ln = self.active_line
  if ln < span.start or ln > span.fin then
    self.active_line = span.start
  end
end

--- Block-wise movement of the active line (spec 2.2):
--- down lands on the next block's first line; up lands
--- on the current block's first line, or on the
--- previous block's when already there
--- @param dir VerticalDir
--- @return boolean moved
function BufferModel:jump_block(dir)
  local span = self:get_selection_lines()
  if dir == 'up' and self.active_line > span.start then
    self.active_line = span.start
    return true
  end
  if not self:move_selection(dir) then return false end
  self.active_line = self:get_selection_lines().start
  return true
end

--- Move the active line, crossing block boundaries
--- @param dir VerticalDir
--- @return boolean moved
function BufferModel:move_line(dir)
  local span = self:get_selection_lines()
  local ln = self.active_line
  if dir == 'up' then
    if ln > span.start then
      self.active_line = ln - 1
      return true
    end
    if self:move_selection('up') then
      self.active_line = self:get_selection_lines().fin
      return true
    end
  end
  if dir == 'down' then
    if ln < span.fin then
      self.active_line = ln + 1
      return true
    end
    if self:move_selection('down') then
      self.active_line = self:get_selection_lines().start
      return true
    end
  end
  return false
end

--- Return the selection as string array
--- @return string[]
function BufferModel:get_selected_text()
  local sel = self.selection
  if self.content_type == 'lua' then
    --- @type Block
    local s = self.content[sel]
    if table.is_instance(s, 'chunk') then
      return table.clone(s.lines)
    else
      return {}
    end
  else
    return self.content[sel] or {}
  end
end

------------------
---   modify   ---
------------------

--- @param rechunk boolean?
function BufferModel:_text_change(rechunk)
  if self.content_type == 'lua' then
    if rechunk then
      self:rechunk()
      self:rechunk()
    end
  else
    self:highlight()
  end
end

function BufferModel:delete_selected_text()
  local sel = self.selection
  --- the block open in the input is gone; what the input
  --- holds now is new text for this place
  if self.loaded == sel then self:clear_loaded() end
  if not self.content[sel] then return end
  local start, len = self:_span_of(sel)
  self:_splice(start, len, {}, {})
  self:_text_change()
  --- the content shrank under the selection, so the
  --- active line still points into the block that was
  --- just removed; left stale it drags the cursor
  --- outside whatever is opened next
  self:clamp_active_line()
end

--- @param t string[]|Block[]
--- @param coord integer?
--- @return boolean insert
--- @return integer? inserted_lines
function BufferModel:replace_content(t, coord)
  if self.content_type == 'lua' then
    local chunks = t
    local n = #chunks
    if n == 0 then
      return false
    end
    local blocknum = coord or self:get_selection()
    local rechunk = false
    --- content start and original length
    local cs, ol = (function()
      local current = self.content[blocknum]
      if current then
        return current.pos.start, self.content[blocknum].pos:len()
      end
      local last = self.content:last()
      if last then
        return self.content:last().pos.fin + 1, 0
      else --- empty file
        return 1, 0
      end
    end)()

    if n == 1 then
      local c = chunks[1]
      local nr = c.pos:translate(cs - 1)
      c.pos = nr
      self.content[blocknum] = chunks[1]
    else
      --- remove old chunk
      self.content:remove(blocknum)
      --- insert new version of the chunk(s)
      for i = #chunks, 1, -1 do
        local c = chunks[i]
        local nr = c.pos:translate(cs - 1)
        c.pos = nr
        self.content:insert(c, blocknum)
      end
      rechunk = true
    end
    --- move subsequent chunks down
    local diff = chunks[n].pos:len() - ol
    if diff ~= 0 then
      for i = blocknum + 1, self:get_content_length() do
        local b = self.content[i]
        b.pos = b.pos:translate(diff)
      end
    end

    self:_text_change(rechunk)
    return true, n
  else
    local linenum = coord or self:get_selection()
    local clen = #(self.content)
    local ti = linenum
    if #t == 1 then
      self.content[ti] = t[1]
      if ti > clen then
        self:_text_change()
        return true, 1
      end
    else
      self.content:remove(ti)
      for i = #t, 1, -1 do
        self.content:insert(t[i], ti)
      end
      self:_text_change()
      return true, #t
    end
    return false
  end
end

--- Insert a new line or empty block _before_ the selection
--- Returns true if a block/line was inserted
--- @param i integer?
--- @return boolean?
function BufferModel:insert_newline(i)
  --- block or line number
  local bln = i or self:get_selection()
  if self.content_type == 'lua' then
    local b = self.content[bln]
    if not b then return end

    local prev_b = self.content[bln - 1]
    -- disallow consecutive empties
    local prev_empty = prev_b and prev_b:is_empty()
    local sel_empty = b:is_empty()
    local cons = prev_empty or sel_empty
    if cons then return end

    local ln = self:get_selection_start_line()
    self.content:insert(Empty(ln), bln)
    self:_text_change(true)
    return true
  else
    self.content:insert('', bln)
    self:_text_change()
    return true
  end
end

--- Insert new lines or blocks
--- Returns success flag and number of inserted
--- @param t string[]|Block[]
--- @param lbn integer?
--- @return boolean?
--- @return integer? inserted_lines
function BufferModel:insert_content(t, lbn)
  local num = lbn or self:get_selection()
  local len = self:get_content_length() + 1
  if num < 1 or num > len then
    return false
  end
  if self.content_type == 'lua' then
    local chunks = t
    local n = #chunks
    if n == 0 then
      return false
    end
    --- content start and original length
    local cs, ol = (function()
      local current = self.content[num]
      if current then
        return current.pos.start,
            self.content[num].pos:len()
      end
      local last = self.content:last()
      if last then
        return self.content:last().pos.fin + 1, 0
      else --- empty file
        return 1, 0
      end
    end)()

    local oldlen = self:get_content_length()

    for i = #chunks, 1, -1 do
      local c = chunks[i]
      local nr = c.pos:translate(cs - 1)
      c.pos = nr
      self.content:insert(c, num)
    end

    --- move subsequent chunks down
    local diff = chunks[n].pos:len() - ol
    if diff ~= 0 then
      for i = num + 1, self:get_content_length() do
        local b = self.content[i]
        b.pos = b.pos:translate(diff)
      end
    end

    self:_text_change(true)
    -- rechunk in #text_change may erase some new empty blocks
    -- so factual n of blocks added should be recalculated
    local newlen = self:get_content_length()
    return true, (newlen - oldlen)
  else
    local ti = num
    for i = #t, 1, -1 do
      self.content:insert(t[i], ti)
    end
    self:_text_change()
    return true, #t
  end
end

--- Block `i` goes to place `npos`, its lines with their
--- endings, and the browsing position with it: on the block
--- that holds its first line once the file is split anew
--- @param i integer
--- @param npos integer
function BufferModel:move(i, npos)
  local si, li = self:_span_of(i)
  local sj, lj = self:_span_of(npos)
  local now = self:snapshot()
  local lines, ends = now.lines, now.ends
  local moved, moved_ends = {}, {}
  for _ = 1, li do
    table.insert(moved, table.remove(lines, si))
    table.insert(moved_ends, table.remove(ends, si))
  end
  --- before the block it passes going up, after it going
  --- down, which stands `li` lines higher by now
  local at = npos < i and sj or sj - li + lj
  for k = li, 1, -1 do
    table.insert(lines, at, moved[k])
    table.insert(ends, at, moved_ends[k])
  end
  self:replace_text(lines, ends)
  self:_text_change()
  self:set_selection(self:_position_of_line(at))
end

--------------------------
---   line-level edits ---
--------------------------

--- The lines blocks render to; lines pass as they are
--- @param t Block[]|string[]
--- @return string[]
function BufferModel.lines_of(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == 'string' then
      out[#out + 1] = v
    elseif v:is_empty() then
      out[#out + 1] = ''
    else
      for _, l in ipairs(v.lines) do out[#out + 1] = l end
    end
  end
  return out
end

--- @param bn integer
--- @return integer start --- the block's first line; for
--- the end position, the line after the last
--- @return integer len --- its lines, 0 at the end position
function BufferModel:_span_of(bn)
  local n = self:get_content_length()
  if self.content_type ~= 'lua' then
    if bn > n then return n + 1, 0 end
    return bn, 1
  end
  local b = self.content[bn]
  if b then return b.pos.start, b.pos:len() end
  local last = self.content[n]
  return (last and last.pos.fin or 0) + 1, 0
end

--- @private
--- @param ln integer
--- @return integer --- the block holding the line, or the
--- end position
function BufferModel:_position_of_line(ln)
  return self:block_at_line(ln)
      or self:get_content_length() + 1
end

--- @return boolean --- the file's text loads as a Lua chunk:
--- blocks that each parse may still not run together, as
--- with code after a final `return`
--- @return string? err --- Lua's reason when it does not
function BufferModel:loads()
  if self.content_type ~= 'lua' then return true end
  local text = table.concat(self:get_text_content(), '\n')
  local chunk, err = loadstring(text)
  return chunk ~= nil, err
end

--- The lines of the block at `bn`; nil for an empty line
--- and for the end position
--- @param bn integer
--- @return string[]?
function BufferModel:block_lines(bn)
  local b = self.content[bn]
  if self.content_type ~= 'lua' then
    if b == nil or b == '' then return nil end
    return { b }
  end
  if b == nil or b:is_empty() then return nil end
  return table.clone(b.lines)
end

--- Insert lines before block `bn`, or append them at the
--- end position
--- @param bn integer
--- @param lines string[]
--- @return integer --- where the block that stood at `bn`
--- stands now, or the end position
function BufferModel:insert_lines(bn, lines)
  local start = self:_span_of(bn)
  self:_splice(start, 0, lines)
  self:_text_change()
  return self:_position_of_line(start + #lines)
end

--- Put lines in the place of block `bn`
--- @param bn integer
--- @param lines string[]
--- @return integer --- the first block after them, or the
--- end position
function BufferModel:replace_lines(bn, lines)
  local start, len = self:_span_of(bn)
  self:_splice(start, len, lines)
  self:_text_change()
  return self:_position_of_line(start + #lines)
end

------------------
---   loaded   ---
------------------

--- Record index of selection loaded into input
--- @param i integer?
function BufferModel:set_loaded(i)
  local n = i or self:get_selection()
  self.loaded = n
end

function BufferModel:clear_loaded()
  self.loaded = nil
end
