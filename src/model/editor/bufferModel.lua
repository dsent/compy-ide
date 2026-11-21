require("model.editor.content")
local Syntax = require('model.syntax')
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
--- @param syntax table --- the file's syntax (model.syntax)
--- @param lines string[]
--- @return Dequeue<Block> blocks
--- @return boolean invalid --- the syntax could not split the
--- text, or its blocks would not keep it
--- @return boolean broken --- the file does not load as its syntax
local function file_blocks(syntax, lines)
  local broken = not syntax.loads(lines)
  local blocks = syntax.blocks(lines)
  if blocks then
    for _, b in ipairs(blocks) do
      local l = b:is_empty() and b.pos and lines[b.pos.start]
      if l and l ~= '' then b.text = l end
    end
    if tiles(blocks, lines) then return blocks, false, broken end
  end
  local out = Dequeue.typed('block')
  for ln, l in ipairs(lines) do
    if l == '' then
      out:push_back(Empty(ln))
    else
      out:push_back(Chunk(l, Range.singleton(ln)))
    end
  end
  return out, true, broken
end

--- Todo: convert to class, store revmap
--- @alias Content Dequeue<string>|Dequeue<Block>

--- @param name string
--- @param content str --- the file's text, or its lines
--- @param save function
--- @param syntax table? --- the file's syntax (model.syntax);
--- by the name's extension when not given
--- @return BufferModel?
local function new(name, content, save, syntax)
  if type(syntax) ~= 'table' or not syntax.blocks then
    syntax = Syntax.for_name(name)
  end
  --- lines are held without their line ends (textfile.lines
  --- reads LF, CRLF and a lone CR); the first save writes the
  --- file with LF ends (textfile.text). `stored`
  --- is the text as read, which tells whether the file on
  --- storage is still the one the editor read
  local stored, lines
  if type(content) == 'string' then
    stored = content
    lines = textfile.lines(content)
  else
    lines = type(content) == 'table' and string.lines(content)
        or textfile.lines(content)
  end
  local blocks, invalid, broken = file_blocks(syntax, lines)

  local self = {
    name = name or 'untitled',
    content = blocks,
    syntax = syntax,
    save_file = save,
    revmap = {},
    selection = 1,
    active_line = 1,
    invalid = invalid,
    broken = broken,
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
--- @field save_file function
--- @field selection integer
--- @field active_line integer --- source line inside the selection
--- @field loaded integer?
--- @field key string? --- the file's identity, project and name
--- @field input UserInputModel --- the file's own editor field
--- @field syntax table --- the file's syntax (model.syntax)
--- @field invalid boolean --- a file whose syntax cannot split
--- it: its blocks are its lines, until the syntax can again
--- @field broken boolean --- a file whose syntax reports it does
--- not load
--- @field semantic BufferSemanticInfo?
--- @field revmap table?
---
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
--- saves, the same path every write takes.

--- The file's lines, as a change found them: what it is
--- undone to (push_history), and what a refused one puts
--- back (restore)
--- @class TextState
--- @field lines string[]

--- @return TextState
function BufferModel:snapshot()
  local lines = {}
  for i, l in ipairs(self:get_text_content()) do lines[i] = l end
  return { lines = lines }
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
      and before.lines[head + 1] == after.lines[head + 1] do
    head = head + 1
  end
  local tail = 0
  while tail < nb - head and tail < na - head
      and before.lines[nb - tail] == after.lines[na - tail] do
    tail = tail + 1
  end
  if head + tail == nb and nb == na then return end
  local step = {
    start = head + 1,
    removed = {},
    inserted = {},
    sel_before = sel_b,
    sel_after = sel_a,
  }
  for i = head + 1, nb - tail do
    table.insert(step.removed, before.lines[i])
  end
  for i = head + 1, na - tail do
    table.insert(step.inserted, after.lines[i])
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
--- Splice lines into the content and re-chunk.
--- The re-chunk may split the file anew: a file that starts
--- or stops parsing turns from lines into statements or
--- back. So the browsing position is kept as a line, not a
--- block number: it ends on the block that holds the line it
--- stood on, or, that line gone, the line after the new ones.
--- @param start integer
--- @param n_out integer --- lines to remove
--- @param lines_in string[]
function BufferModel:_splice(start, n_out, lines_in)
  local lines = self:snapshot().lines
  local n_in = #lines_in
  local function carry(ln)
    if ln < start then return ln end
    if ln >= start + n_out then return ln - n_out + n_in end
    return start + n_in
  end
  local at = carry((self:_span_of(self.selection)))
  for _ = 1, n_out do table.remove(lines, start) end
  for i = n_in, 1, -1 do table.insert(lines, start, lines_in[i]) end
  self.content, self.invalid, self.broken =
      file_blocks(self.syntax, lines)
  self:set_selection(self:_position_of_line(at))
end

--- Replace the whole text and re-chunk it
--- @param lines string[]
function BufferModel:replace_text(lines)
  self:_splice(1, #self:get_text_content(), lines)
end

--- Put the file back as a snapshot holds it
--- @param state TextState
function BufferModel:restore(state)
  self:replace_text(state.lines)
end

--- what a file read anew replaces (reload)
local READ_FIELDS = {
  'content', 'invalid', 'broken', 'stored', 'revmap',
  'semantic',
}

--- Take the file's text anew, as storage holds it, read as
--- an opening reads it; its timeline goes. The browsing
--- position is the caller's to set.
--- @param content string? --- nil: the file is missing
function BufferModel:reload(content)
  local fresh = BufferModel(self.name, content, self.save_file,
    self.syntax)
  for _, k in ipairs(READ_FIELDS) do
    self[k] = fresh[k]
  end
  self.history = {}
  self.redo_history = {}
  self:_text_change()
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

--- The files the text names (IS1.5), each with its block
function BufferModel:analyze()
  local lines = self:snapshot().lines
  local anaok, refs = pcall(self.syntax.references, lines)
  if not anaok then return end
  for bi, v in ipairs(self.content) do
    if (v.pos) then
      for _, l in ipairs(v.pos:enumerate()) do
        self.revmap[l] = bi
      end
    end
  end
  self.semantic = bsi.convert(refs, self.revmap)
end

function BufferModel:rechunk()
  local content = self:snapshot().lines
  self.content, self.invalid, self.broken =
      file_blocks(self.syntax, content)
end

--- A file is written as its lines, each with an LF line
--- end, the last one too (textfile.text)
function BufferModel:save()
  self:_text_change()
  self:analyze()
  local out = textfile.text(self:snapshot().lines)
  local ok, err = self.save_file(out)
  if ok then self.stored = out end
  return ok, err
end

function BufferModel:highlight()
  self.hl = self.syntax.highlight(self:snapshot().lines)
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
  return render_blocks(self.content)
end

--- @return SyntaxColoring? hl
function BufferModel:get_highlight()
  if self.hl == nil then self:highlight() end
  return self.hl
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
  local sel = self.selection
  if sel == self:get_content_length() + 1 then
    return Empty(self:line_count() + 1)
  end
  return self.content[sel]
end

--- Get the line number of selection first line
--- @return integer
function BufferModel:get_selection_start_line()
  local b = self:_get_selected_block()
  if b and b.pos then return b.pos.start end
  return self.selection
end

--- Source-line span of the selected block
--- @return Range
function BufferModel:get_selection_lines()
  local b = self:_get_selected_block()
  if b and b.pos then return b.pos end
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
  --- @type Block
  local s = self.content[self.selection]
  if table.is_instance(s, 'chunk') then
    return table.clone(s.lines)
  end
  return {}
end

------------------
---   modify   ---
------------------

--- @param rechunk boolean?
function BufferModel:_text_change(rechunk)
  if rechunk then self:rechunk() end
  --- colored again when asked (get_highlight)
  self.hl = nil
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

--- Block `i` goes to place `npos`, its lines and the
--- browsing position with it: on the block
--- that holds its first line once the file is split anew
--- @param i integer
--- @param npos integer
function BufferModel:move(i, npos)
  local si, li = self:_span_of(i)
  local sj, lj = self:_span_of(npos)
  local now = self:snapshot()
  local lines = now.lines
  local moved = {}
  for _ = 1, li do
    table.insert(moved, table.remove(lines, si))
  end
  --- before the block it passes going up, after it going
  --- down, which stands `li` lines higher by now
  local at = npos < i and sj or sj - li + lj
  for k = li, 1, -1 do
    table.insert(lines, at, moved[k])
  end
  self:replace_text(lines)
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

--- The file's line count, 0 for an empty file
--- @return integer
function BufferModel:line_count()
  local last = self.content[self:get_content_length()]
  return last and last.pos.fin or 0
end

--- The first file line of block `bn`, or the line after the
--- last at the end position
--- @param bn integer
--- @return integer
function BufferModel:block_line(bn)
  return (self:_span_of(bn))
end

--- @param bn integer
--- @return integer start --- the block's first line; for
--- the end position, the line after the last
--- @return integer len --- its lines, 0 at the end position
function BufferModel:_span_of(bn)
  local b = self.content[bn]
  if b then return b.pos.start, b.pos:len() end
  return self:line_count() + 1, 0
end

--- @private
--- @param ln integer
--- @return integer --- the block holding the line, or the
--- end position
function BufferModel:_position_of_line(ln)
  return self:block_at_line(ln)
      or self:get_content_length() + 1
end

--- Whether the file holds together as its syntax reads it:
--- for Lua, blocks that each parse may still not run
--- together, as with code after a final `return`
--- @return boolean ok
--- @return string? why --- the syntax's notice when it does
--- not
--- @return boolean? merges --- it does not because two blocks
--- now read as one
function BufferModel:loads()
  return self.syntax.loads(self:snapshot().lines)
end

--- The lines of the block at `bn`; nil for an empty line
--- and for the end position
--- @param bn integer
--- @return string[]?
function BufferModel:block_lines(bn)
  local b = self.content[bn]
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
