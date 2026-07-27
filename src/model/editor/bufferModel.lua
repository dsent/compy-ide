require("model.editor.content")
local analyzer = require("model.lang.lua.analyze")
local bsi = require("model.editor.bufferSemanticInfo")

local class = require('util.class')
require('util.table')
require('util.range')
require('util.string.string')
require('util.dequeue')

--- Convert Blocks to string array
--- @param blocks Block[]
--- @return Dequeue<string>
local function render_blocks(blocks)
  local ret = Dequeue.typed('string')
  for _, v in ipairs(blocks) do
    if v:is_empty() then
      ret:append('')
    else
      ret:append_all(v.lines)
    end
  end
  return ret
end

--- Todo: convert to class, store revmap
--- @alias Content Dequeue<string>|Dequeue<Block>

--- @param name string
--- @param content str
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
  local readonly = false

  local lines = string.lines(content or '')

  local function plaintext()
    ct = 'plain'
    _content = Dequeue(lines, 'string')
    if _content:last() ~= '' then
      _content:push('')
    end
    sel = 1
  end
  --- only passing this around so the linter shuts up about nil
  --- @param chk function
  local function luacontent(chk)
    ct = 'lua'
    local ok, blocks = chk(lines)
    if ok then
      sel = 1
    else
      readonly = true
      sel = 1
    end
    _content = blocks
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
    readonly = readonly,
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
--- @field readonly boolean
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

--- The block-level undo (1.1): a 32-step ring of file
--- operations. A step is a trimmed diff — the common
--- prefix and suffix of the file before/after are cut,
--- so what remains is exactly the affected line range,
--- whatever the operation was (accept, move, delete,
--- insert, discard pair). Applying a step is a splice;
--- the caller re-chunks and saves, the same path every
--- write takes.
BLOCK_HISTORY_CAP = 32

--- @param before string[] --- file lines pre-operation
--- @param after string[] --- file lines post-operation
--- @param sel_b integer --- selection before
--- @param sel_a integer --- selection after
--- @return table? --- nil when nothing changed
local function make_step(before, after, sel_b, sel_a)
  local nb, na = #before, #after
  local head = 0
  while head < nb and head < na
      and before[head + 1] == after[head + 1] do
    head = head + 1
  end
  local tail = 0
  while tail < nb - head and tail < na - head
      and before[nb - tail] == after[na - tail] do
    tail = tail + 1
  end
  if head + tail == nb and nb == na then return end
  local removed, inserted = {}, {}
  for i = head + 1, nb - tail do
    table.insert(removed, before[i])
  end
  for i = head + 1, na - tail do
    table.insert(inserted, after[i])
  end
  return {
    start = head + 1,
    removed = removed,
    inserted = inserted,
    sel_before = sel_b,
    sel_after = sel_a,
  }
end

--- @param before string[]
--- @param after string[]
--- @param sel_b integer
--- @param sel_a integer
function BufferModel:push_history(before, after, sel_b, sel_a)
  local step = make_step(before, after, sel_b, sel_a)
  if not step then return end
  table.insert(self.history, step)
  if #self.history > BLOCK_HISTORY_CAP then
    table.remove(self.history, 1)
  end
  self.redo_history = {}
end

--- @private
--- Splice a step's lines into the content and re-chunk
--- @param start integer
--- @param n_out integer --- lines to remove
--- @param lines_in string[]
function BufferModel:_splice(start, n_out, lines_in)
  local lines = string.lines(
    string.unlines(self:get_text_content()))
  for _ = 1, n_out do
    table.remove(lines, start)
  end
  for i = #lines_in, 1, -1 do
    table.insert(lines, start, lines_in[i])
  end
  if self.content_type == 'lua' then
    local _, blocks = self.chunker(lines)
    self.content = blocks
  else
    self.content = Dequeue(lines)
  end
end

--- @return table? --- the applied step, nil when empty
function BufferModel:undo()
  local n = #self.history
  if n == 0 then return end
  local step = self.history[n]
  table.remove(self.history, n)
  self:_splice(step.start, #step.inserted, step.removed)
  table.insert(self.redo_history, step)
  return step
end

--- @return table? --- the applied step, nil when empty
function BufferModel:redo()
  local n = #self.redo_history
  if n == 0 then return end
  local step = self.redo_history[n]
  table.remove(self.redo_history, n)
  self:_splice(step.start, #step.removed, step.inserted)
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
  local _, blocks = self.chunker(content)
  self.content = blocks
end

function BufferModel:save()
  self:_text_change()
  local text = self:get_text_content()
  self:analyze()
  return self.save_file(text)
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
    local ll = self.content:last()
    if ll ~= '' then
      -- Log.warn('asd')
      self.content:push('')
    end
  end
end

function BufferModel:delete_selected_text()
  local sel = self.selection
  if self.content_type == 'lua' then
    local sb = self.content[sel]
    if not sb then return end

    self.content:remove(sel)
    self:rechunk()
  else
    self.content:remove(sel)
  end
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

--- @param i integer
--- @param npos integer
function BufferModel:move(i, npos)
  self.content:move(i, npos)
  self:_text_change(true)
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

--- Check whether the current selection is the same as the one
--- loaded previously. The default value if nothing is loaded
--- is use-case dependent, so it's supplied via parameter.
--- @param default boolean
--- @return boolean
function BufferModel:loaded_is_sel(default)
  --- only check if there is in fact something to compare to
  if not self.loaded then
    return default
  end
  return self.loaded == self.selection
end

--- Change selection to previously loaded
function BufferModel:select_loaded()
  local l = self.loaded
  if l then
    self.selection = l
  end
end
