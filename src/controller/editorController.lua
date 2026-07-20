require("model.interpreter.eval.evaluator")
require("controller.userInputController")
require("controller.searchController")
require("view.input.customStatus")
require("model.input.cursor")

local class = require('util.class')

--- @param M EditorModel
--- @oaram CC ConsoleController
local function new(M, CC)
  return {
    input = UserInputController(M.input, nil, true),
    model = M,
    search = SearchController(
      M.search,
      UserInputController(M.search.input, nil, true)
    ),
    console = CC,
    view = nil,
    mode = 'nav',
    pos_memory = {},
    pending_confirm = nil,
    accepted_n = 1,
  }
end

--- @alias EditorMode
--- | 'edit' --- default
--- | 'nav' --- navigating between blocks
--- | 'reorder'
--- | 'search'

--- @class EditorController
--- @field model EditorModel
--- @field input UserInputController
--- @field search SearchController
--- @field console ConsoleController
--- @field view EditorView?
--- @field state EditorState?
--- @field mode EditorMode
--- @field pos_memory table<string, {sel:integer, off:integer}>
--- @field pending_confirm string? --- 'overwrite'|'restore'
--- @field accepted_n integer --- blocks the last
--- acceptance produced; the leave gate steps past them
EditorController = class.create(new)

--- @param v EditorView
function EditorController:init_view(v)
  self.view = v
  self.input:init_view(self.view.input)
end

--- @param name string
--- @param content str?
--- @param save function
function EditorController:open(name, content, save)
  local w = self.model.cfg.view.drawableChars
  local is_lua = string.match(name, '.lua$')
  local is_md = string.match(name, '.md$')
  local ch, hl, pp, tr

  if is_lua then
    self.input:set_eval(LuaEditorEval)
    local luaEval = LuaEval()
    local parser = luaEval.parser
    if not parser then return end
    hl = luaEval.highlighter
    --- @param t string
    --- @param single boolean
    ch = function(t, single)
      return parser.chunker(t, w, single)
    end
    pp = function(t)
      return parser.pprint(t, w)
    end
    tr = function(code)
      return parser.trunc(code, self.model.cfg.view.fold_lines)
    end
  elseif is_md then
    local mdEval = MdEval()
    hl = mdEval.highlighter
    self.input:set_eval(mdEval)
  else
    self.input:set_eval(TextEval)
  end

  local b = BufferModel(name, content, save, ch, hl, pp, tr)
  self.model.buffers:push_front(b)
  self.view:open(b)
  self:set_mode('nav')
  if not self:_restore_position(b) then
    self.view:get_current_buffer():follow_selection()
  end
  self:update_status()
  self:set_state()
  self.input:update_view()
end

--- @private
function EditorController:_print_bufferlist()
  for i, v in ipairs(self.model.buffers) do
    Log.debug(i, v.name)
  end
  orig_print()
end

function EditorController:follow_require()
  local buf = self:get_active_buffer()
  if not buf.semantic then return end
  local bn = buf:get_selection()
  local reqs = buf.semantic.requires
  local reqsel = table.find_by_v(reqs, function(r)
    return r.block == bn
  end)

  if reqsel then
    local name = reqsel.name
    self.console:edit(name .. '.lua')
  else
    self:refuse()
  end
end

function EditorController:pop_buffer()
  local bs = self.model.buffers
  local n_buffers = bs:length()
  if n_buffers < 2 then return end
  self:_remember_position()
  bs:pop_front()
  local b = bs:first()
  self.view:get_current_buffer():open(b)
  self:update_status()
end

--- store the active buffer's position by file name
function EditorController:_remember_position()
  local buf = self:get_active_buffer()
  local bv = self.view:get_current_buffer()
  self.pos_memory[buf.name] = {
    sel = buf:get_selection(),
    off = bv:get_offset(),
  }
end

--- restore a remembered position if it is still in range
--- @param buf BufferModel
function EditorController:_restore_position(buf)
  local saved = self.pos_memory[buf.name]
  if saved
      and saved.sel >= 1
      and saved.sel <= buf:get_content_length() then
    buf:set_selection(saved.sel)
    self.view:get_current_buffer():scroll_to(saved.off)
    return true
  end
  return false
end

--- Replace the active buffer with fresh file content
--- @param text string
function EditorController:reload_active(text)
  local old = self:get_active_buffer()
  self.model.buffers:pop_front()
  self:open(old.name, text, old.save_file)
end

function EditorController:close_buffer()
  self:_remember_position()
  local bs = self.model.buffers
  local n_buffers = bs:length()
  if n_buffers < 2 then
    self.console:finish_edit()
  else
    self:pop_buffer()
  end
end

--- @param m EditorMode
--- @return boolean
local function is_normal(m)
  return m == 'nav' or m == 'edit'
end

--- legal mode transitions; anything absent is rejected
local TRANSITIONS = {
  nav = { edit = true, reorder = true, search = true },
  edit = { nav = true },
  reorder = { nav = true },
  search = { nav = true },
}

--- @param mode EditorMode
function EditorController:set_mode(mode)
  local buf = self:get_active_buffer()
  local set_reorg = function()
    self:save_state()
  end
  local init_search = function()
    local db = buf.semantic
    if db then
      self:save_state()
      local ds = db.definitions
      self.search:load(ds)
    end
  end

  local current = self.mode
  if current ~= mode and TRANSITIONS[current][mode] then
    if mode == 'reorder' then
      set_reorg()
    end
    if mode == 'search' then
      init_search()
    end
    self.mode = mode
    Log.info('-- ' .. string.upper(mode) .. ' --')
    self:update_status()
  end
end

--- @return EditorMode
function EditorController:get_mode()
  return self.mode
end

--- @return boolean
function EditorController:is_normal_mode()
  return is_normal(self.mode)
end

--- One sound for every refused action (spec 2.4.3):
--- a knock means "no further this way"
--- @param msg string[]? --- also shown when given
function EditorController:refuse(msg)
  --- required here, not at the top: util.audio builds
  --- its sources on load and needs love.audio ready
  require("util.audio").knock()
  if msg then self.input:set_error(msg) end
end

--- drop the loaded block and the input, return to nav
function EditorController:leave_edit()
  local buf = self:get_active_buffer()
  buf:clear_loaded()
  self.input:clear()
  self:set_mode('nav')
end

--- @param clipboard string
function EditorController:set_clipboard(clipboard)
  self.state.clipboard = clipboard
end

--- @return string
function EditorController:get_clipboard()
  return self.state.clipboard
end

--- @param clipboard string?
function EditorController:set_state(clipboard)
  --- TODO: multibuffer support
  local buf = self:get_active_buffer()
  local bid = buf:get_id()
  local buf_view_state = self.view:get_buffer(bid):get_state()
  if self.state then
    self.state.buffer = buf_view_state
    self.state.moved = buf:get_selection()
    if clipboard then self:set_clipboard(clipboard) end
  else
    self.state = {
      buffer = buf_view_state,
      clipboard = clipboard,
      moved = buf:get_selection()
    }
  end
end

--- @return EditorState
function EditorController:get_state()
  return self.state
end

function EditorController:save_state()
  --- TODO: multibuffer support
  self:set_state(love.system.getClipboardText())
end

--- @param state EditorState?
function EditorController:restore_state(state)
  --- TODO: multibuffer support
  if state then
    local buf = self:get_active_buffer()
    local sel = state.buffer.selection
    local off = state.buffer.offset
    buf:set_selection(sel)
    self.view:get_current_buffer():scroll_to(off)
    local clip = state.clipboard
    if string.is_non_empty_string(clip) then
      love.system.setClipboardText(clip or '')
    end
  end
end

--- @return {name: string, content: string[]}[]
function EditorController:close()
  self.input:clear()
  local bfs = self.model:get_buffers_content()
  self.model.buffers = Dequeue()
  self.view.buffers = {}
  --- TODO is this needed?
  return bfs
end

--- @return BufferModel
function EditorController:get_active_buffer()
  return self.model.buffers:first()
end

--- @return Id
function EditorController:get_active_buffer_id()
  local buf = self:get_active_buffer()
  return buf:get_id()
end

--- @private
--- @param sel integer
--- @return CustomStatus
function EditorController:_generate_status(sel)
  --- @type BufferModel
  local buffer = self:get_active_buffer()
  local len = buffer:get_content_length() + 1
  local bufview = self.view:get_buffer(buffer:get_id())
  local more = bufview.content:get_more()
  local cs
  local m = self.mode
  local ct = bufview.content_type
  if ct == 'lua' then
    local range = bufview.content:get_block_app_pos(sel)
    cs = CustomStatus(buffer.name, ct, len, more, sel, m, range)
  else
    cs = CustomStatus(buffer.name, ct, len, more, sel, m)
  end

  return cs
end

function EditorController:update_status()
  local sel = self:get_active_buffer():get_selection()
  local cs = self:_generate_status(sel)
  self.input:set_custom_status(cs)
end

--- @param t string
function EditorController:textinput(t)
  self.view:update_input()
  if is_normal(self.mode) then
    local input = self.model.input
    if input:has_error() then
      input:clear_error()
    else
      if Key.ctrl() or Key.alt() then
        --- modifier chords leak glyphs on the device
        --- (compy-input-quirks, quirk 3); only Shift
        --- composes real input
        return
      end
      --- typing after a peek returns the view (2.2)
      local bv = self.view:get_current_buffer()
      if self.mode == 'nav' then
        bv:follow_line()
      else
        bv:follow_selection()
      end
      --- NB: on device, textinput precedes keypressed
      --- (see dev/docs/compy-input-quirks.md), so this
      --- transition lands before the same key's press
      if self.mode == 'nav' then
        self:start_typing()
      end
      self.input:textinput(t)
    end
  elseif self.mode == 'search' then
    self.search:textinput(t)
  end
end

--- @return InputDTO
function EditorController:get_input()
  return self.input:get_input()
end

--- @param buf BufferModel
--- @return boolean ok --- the write reached the OS
--- @return string? err
function EditorController:save(buf)
  local ok, err = buf:save()
  if not ok then Log.error("can't save: ", err) end
  return ok, err
end

---------------------------
---  keyboard handlers  ---
---------------------------

--- @private
--- @param go fun(nt: string[]|Block[])
--- @param go fun(newtext: Block[]|string[]): boolean
--- @return boolean accepted --- go's verdict, or false
--- when the input does not evaluate
function EditorController:_handle_submit(go)
  local inter = self.input
  local raw = inter:get_text()

  local buf = self:get_active_buffer()
  local ct = buf.content_type
  if ct == 'lua' then
    if not string.is_non_empty_string_array(raw) then
      local sel = buf:get_selection()
      local block = buf:get_content():get(sel)
      if not block then return true end
    else
      local _, raw_chunks = buf.chunker(raw, true)
      local pretty = buf.printer(raw)
      if pretty then
        inter:set_text(pretty)
      else
        --- fallback to original in case of unparse-able input
        pretty = raw
      end
      local ok, res = inter:evaluate()
      local _, chunks = buf.chunker(pretty, true)
      if ok then
        local newlines_injection_needed = (#chunks > 1)
        if #chunks < #raw_chunks then
          local rc = raw_chunks
          if rc[1]:is_empty() then
            --- Leading empty in raw may be editor padding before the
            --- first real block; do not restore it when pprint already
            --- starts with content.
            local has_leading_content = chunks[1]
                and chunks[1]:is_empty()
            if not has_leading_content then
              table.insert(chunks, 1, Empty(rc[1].pos.start))
            end
          end
          if rc[#rc]:is_empty() then
            local li = chunks[#chunks].pos.fin
            table.insert(chunks, Empty(li + 1))
          end
        end
        if newlines_injection_needed then
          for i = #chunks, 2, -1 do
            local ch=chunks
            local this_nonempty = not(ch[i]:is_empty())
            local prev_nonempty = not(ch[i-1]:is_empty())
            if this_nonempty and prev_nonempty then
              local prev_pos = ch[i-1].pos.fin
              table.insert(ch, i, Empty(prev_pos+1))
            end
          end
        end
        return go(chunks)
      else
        local eval_err = res
        if eval_err then
          self:refuse()
          inter:set_error(eval_err)
          --- spec 2.4.3: the cursor moves to the error
          local first = Error.get_first(eval_err)
              or eval_err
          if type(first) == 'table' and first.l then
            inter.model:move_cursor(first.l, first.c or 1)
            inter:update_view()
          end
        end
        return false
      end
    end
  else
    return go(raw)
  end
  return true
end

--- @private
--- @param dir VerticalDir
--- @param by integer?
--- @param warp boolean?
--- @param moved integer?
--- Shift+Esc out of an open block (1.1). A changed
--- block asks for confirmation — the only irreversible
--- action in the editor gets the same repeated-press
--- guard the checkpoints use. A parseable draft leaves
--- a recoverable pair in the block history: one Ctrl+Z
--- puts the discarded text into the file, another
--- takes it back out.
function EditorController:discard_edit()
  if self.mode ~= 'edit' then
    return self:leave_edit()
  end
  local buf = self:get_active_buffer()
  local draft = self.input:get_text():items()
  local orig = buf:get_selected_text()
  local clean = string.unlines(draft)
      == string.unlines(orig)

  if clean then return self:leave_edit() end

  if self.pending_confirm ~= 'discard' then
    self.pending_confirm = 'discard'
    self.input:set_error({
      'discard the changes?'
      .. ' Shift+Esc again to confirm'
    })
    return
  end
  self.pending_confirm = nil

  --- an unparseable draft cannot go into the file
  --- (it would turn the buffer read-only), so only a
  --- valid one is recoverable — as agreed
  local parses = buf.chunker == nil
      or (buf.chunker(draft, true))
  if parses then
    local span = buf:get_selection_lines()
    local before = table.clone(buf:get_text_content())
    local after = {}
    local drafted = {}
    for i, l in ipairs(before) do after[i] = l end
    for i, l in ipairs(draft) do drafted[i] = l end
    local head = span.start - 1
    local removed = span:len()
    for _ = 1, removed do
      table.remove(after, head + 1)
    end
    for i = #drafted, 1, -1 do
      table.insert(after, head + 1, drafted[i])
    end
    local sel = buf:get_selection()
    --- the pair: undo #1 puts the draft in, undo #2
    --- takes it back out (net zero, like the discard)
    buf:push_history(before, after, sel, sel)
    buf:push_history(after, before, sel, sel)
  end
  self:leave_edit()
end

--- Load the selected block into the input and open it
--- for editing, auto-formatted (9.4), with the cursor
--- on the active line (2.2)
function EditorController:open_block()
  local buf = self:get_active_buffer()
  local input = self.input
  local span = buf:get_selection_lines()
  local row = buf:get_active_line() - span.start + 1

  local t = buf:get_selected_text()
  if string.is_non_empty(t) then
    buf:set_loaded()
  else
    buf:clear_loaded()
  end
  input:set_text(t)
  input:jump_home()

  if buf.content_type == 'lua' then
    --- auto-format on opening (spec 9.4); a block the
    --- formatter changes is dirty from birth (2.4)
    local raw = input:get_text()
    if string.is_non_empty_string_array(raw) then
      local pretty = buf.printer(raw)
      if pretty then
        --- the printer may append a trailing empty
        --- line; that is noise, not formatting
        while #pretty > 1 and pretty[#pretty] == '' do
          table.remove(pretty)
        end
        input:set_text(pretty)
      end
    end
  end
  --- the active line can sit outside the block being
  --- opened (a deletion leaves the selection on the
  --- trailing gap); row 0 detaches the cursor
  local n = #input:get_text()
  if n < 1 then n = 1 end
  if row < 1 then row = 1 end
  if row > n then row = n end
  input:set_cursor(Cursor(row, 1))
  self:set_mode('edit')
end

--- Typing in navigation starts editing at the active
--- line: its block opens and a blank line appears there
--- to type into, pushing the rest down (spec 2.1). On a
--- blank line the text becomes a new block instead, so
--- the input stays empty and acceptance inserts.
function EditorController:start_typing()
  local buf = self:get_active_buffer()
  if buf.content_type ~= 'lua' then
    self:set_mode('edit')
    return
  end
  local block = buf:_get_selected_block()
  if not block or block:is_empty() then
    --- an empty block -- including the gap a deletion
    --- leaves behind -- still has to be opened. Setting
    --- the mode alone anchors the input to no block, so
    --- the typing goes into a detached widget and the
    --- accept drops it on the floor
    self:open_block()
    return
  end

  local ln = buf:get_active_line()
  local span = buf:get_selection_lines()
  local row = ln - span.start + 1
  self:open_block()

  local t = self.input:get_text()
  --- the format on opening may have reshaped the block
  if row < 1 then row = 1 end
  if row > #t then row = #t + 1 end
  table.insert(t, row, '')
  self.input:set_text(t)
  self.input:set_cursor(Cursor(row, 1))
end

--- Open a fresh empty block next to the current one
--- (spec 2.7: Ctrl+Enter below, Ctrl+Shift+Enter
--- above). The block itself appears on acceptance —
--- until then the editor simply composes at that spot.
--- @param below boolean
function EditorController:new_block(below)
  local buf = self:get_active_buffer()
  if buf.readonly then return self:refuse() end
  if below then
    buf:set_selection(buf:get_selection() + 1)
  end
  buf:clear_loaded()
  self.input:clear()
  self:set_mode('edit')
  self.view:get_current_buffer():follow_selection()
  self:update_status()
end

--- Run a file-writing operation and record it in the
--- block history (1.1): the file before and after, the
--- diff trimmed inside push_history
--- @param buf BufferModel
--- @param fn function --- mutates the buffer and saves
--- @return any --- fn's return
function EditorController:record_write(buf, fn)
  local before = table.clone(buf:get_text_content())
  local sel_b = buf:get_selection()
  local ret = fn()
  buf:push_history(
    before,
    table.clone(buf:get_text_content()),
    sel_b,
    buf:get_selection())
  return ret
end

--- @private
--- Apply one block-history step (spec 1.1: navigation
--- undo). The file is written through the same save
--- path every operation uses.
--- @param redo boolean?
function EditorController:_step_history(redo)
  local buf = self:get_active_buffer()
  if buf.readonly then return self:refuse() end
  --- no and/or chain here: redo() legitimately
  --- returns nil, which must not fall through to undo
  local step
  if redo then
    step = buf:redo()
  else
    step = buf:undo()
  end
  if not step then return self:refuse() end
  self:save(buf)
  local sel = redo and step.sel_after or step.sel_before
  local last = buf:get_content_length()
  if sel > last then sel = last end
  buf:set_selection(sel)
  self.view:refresh()
  self.view:get_current_buffer():follow_selection()
  self:update_status()
end

--- @return integer --- the input strip's height (2.7)
function EditorController:_size_limit()
  return self.view:get_current_buffer():get_max_size()
end

--- @param chunks Block[]
--- @return integer? --- index of the first block over
--- the limit, nil when all fit
function EditorController:_first_oversized(chunks)
  if self.view:get_current_buffer().content_type
      ~= 'lua' then
    return
  end
  local limit = self:_size_limit()
  return table.find_by(chunks, function(v)
    return (v and v.pos and v.pos:len() > limit)
  end)
end

--- Refuse an oversized block and point at it (9.6)
--- @param chunks Block[]
--- @param idx integer
function EditorController:_reject_oversized(chunks, idx)
  local block = chunks[idx]
  if not block or not block.pos then return end
  local n = block.pos:len()
  --- the wording follows 1.4: say what to do, not what
  --- the machine measured
  self:refuse({ string.format(
    'Too many lines in a block. Remove %d to save,'
    .. ' or press Shift+Esc to cancel',
    n - self:_size_limit()
  ) })
  self.input.model:move_cursor(block.pos.start, 1)
  self.input:update_view()
end

--- Accept the open block into the file: validate, size
--- check, re-chunk, write (spec 2.4.2). Acceptance in
--- place keeps the block and scrolls back to it.
--- @return boolean accepted
function EditorController:accept_block()
  return self:_handle_submit(function(newtext)
    local buf = self:get_active_buffer()
    local bufv = self.view:get_current_buffer()
    if not bufv:is_selection_visible(true) then
      bufv:follow_selection()
      return false
    end
    if not buf:loaded_is_sel(true) then
      buf:select_loaded()
      bufv:follow_selection()
      return false
    end
    local oversized = self:_first_oversized(newtext)
    if oversized then
      self:_reject_oversized(newtext, oversized)
      return false
    end
    local saved = self:record_write(buf, function()
      local _, n = buf:replace_content(newtext)
      local ok = self:save(buf)
      self.accepted_n = n
      return ok
    end)
    if not saved then
      --- a failed write must not read as accepted (2.6);
      --- keep the block open so the edit is not lost
      self:refuse({
        'Could not save the file.'
        .. ' Check the storage and try again.'
      })
      return false
    end
    self.view:refresh()
    bufv:follow_selection()
    self:leave_edit()
    return true
  end)
end

--- Click semantics (spec 2.9): in nav, select the
--- clicked line's block; while editing, a click inside
--- the open block places the cursor, a click outside
--- it leaves when the block is untouched
--- @param ln integer --- source line
function EditorController:mouse_select(ln)
  local buf = self:get_active_buffer()
  local bi = buf:block_at_line(ln)
  if not bi then return end

  if self.mode == 'edit' then
    local span = buf:get_selection_lines()
    if span:inc(ln) then
      self.input:set_cursor(Cursor(ln - span.start + 1, 1))
      return
    end
    --- leaving for another block goes through the gate
    --- (2.4): untouched leaves, changed is accepted and
    --- written, invalid refuses and keeps the block
    local clean = string.unlines(self.input:get_text())
        == string.unlines(buf:get_selected_text())
    if clean then
      self:leave_edit()
    elseif not self:accept_block() then
      return
    end
  end

  buf:set_selection(bi)
  buf:set_active_line(ln)
  self.view:get_current_buffer():follow_line()
  self:update_status()
end

--- @param x number
--- @param y number
--- @param btn integer
--- @param touch boolean?
--- @param presses integer? --- 2 on a double click
function EditorController:mousepressed(x, y, btn, touch, presses)
  if btn == 1 then
    local ln = self.view:get_current_buffer():line_at(y)
    if ln then
      self:mouse_select(ln)
      --- spec 2.9: a double click opens the block the
      --- first click selected
      if presses and presses > 1
          and self.mode == 'nav' then
        self:open_block()
      end
      return
    end
  end
  self.input:mousepressed(x, y, btn, touch, presses)
end

--- Swap the selected block with its neighbor (spec 2.7:
--- Alt+arrows in navigation), written through like reorder
--- @param dir VerticalDir
function EditorController:_move_block(dir)
  local buf = self:get_active_buffer()
  if self.input:has_error() then return end
  if buf.readonly then return self:refuse() end

  local sel = buf:get_selection()
  local last = buf:get_content_length()
  if sel > last then return self:refuse() end
  local target = sel - 1
  if dir == 'down' then target = sel + 1 end
  if target < 1 or target > last then
    return self:refuse()
  end

  self:record_write(buf, function()
    buf:move(sel, target)
    buf:rechunk()
    self:save(buf)
  end)
  buf:set_selection(target)
  self.view:refresh()
  self.view:get_current_buffer():follow_selection()
  self:update_status()
end

--- Block-wise movement of the active line (spec 2.2)
--- @param dir VerticalDir
function EditorController:_jump_block(dir)
  local buf = self:get_active_buffer()
  if self.input:has_error() then return end
  if buf:jump_block(dir) then
    self.view:get_current_buffer():follow_line()
    self:update_status()
  else
    self:refuse()
  end
end

--- Move the active line by a viewport page
--- @param dir VerticalDir
function EditorController:_move_line_page(dir)
  local buf = self:get_active_buffer()
  if self.input:has_error() then return end
  local bv = self.view:get_current_buffer()
  local moved = 0
  for _ = 1, bv.LINES do
    if not buf:move_line(dir) then break end
    moved = moved + 1
  end
  if moved == 0 then return self:refuse() end
  bv:follow_line()
  self:update_status()
end

--- Move the active line, keep it in view
--- @param dir VerticalDir
function EditorController:_move_line(dir)
  local buf = self:get_active_buffer()
  if self.input:has_error() then return end
  if buf:move_line(dir) then
    self.view:get_current_buffer():follow_line()
    self:update_status()
  else
    --- nowhere further to go
    self:refuse()
  end
end

function EditorController:_move_sel(dir, by, warp, moved)
  local buf = self:get_active_buffer()
  if self.input:has_error() then return end

  --- @type boolean
  local mv = (function()
    if moved then return true end
    return false
  end)()
  local m = buf:move_selection(dir, by, warp, mv)
  if m then
    if mv then self.view:refresh(moved) end
    self.view:get_current_buffer():follow_selection()
    self:update_status()
  else
    self:refuse()
  end
end

--- @private
--- @param dir VerticalDir
--- @param warp boolean?
--- @param by integer?
function EditorController:_scroll(dir, warp, by)
  self.view:get_current_buffer():scroll(dir, by, warp)
  self:update_status()
end

--- @private
--- @param save boolean
function EditorController:_reorg(save)
  local moved = self.state.moved
  if not moved then return end

  local buf = self:get_active_buffer()
  if save then
    local target = buf:get_selection()
    self:record_write(buf, function()
      buf:move(moved, target)
      buf:rechunk()
      self:save(buf)
    end)
  else
    buf:set_selection(moved)
    self:restore_state(self:get_state())
  end
  self.view:refresh()

  self:set_mode('nav')
end

--- @private
--- @param k string
function EditorController:_reorg_mode_keys(k)
  if k == 'escape' then
    self:_reorg(false)
  end
  if Key.is_enter(k) then
    self:_reorg(true)
  end

  local function navigate()
    -- move selection
    if k == "up" then
      self:_move_sel('up', nil, nil, self.state.moved)
    end
    if k == "down" then
      self:_move_sel('down', nil, nil, self.state.moved)
    end
    if k == "home" then
      self:_move_sel('up', nil, true, self.state.moved)
    end
    if k == "end" then
      self:_move_sel('down', nil, true, self.state.moved)
    end

    -- scroll
    if not Key.shift()
        and k == "pageup" then
      self:_scroll('up', Key.ctrl())
    end
    if not Key.shift()
        and k == "pagedown" then
      self:_scroll('down', Key.ctrl())
    end
    if Key.shift()
        and k == "pageup" then
      self:_scroll('up', false, 1)
    end
    if Key.shift()
        and k == "pagedown" then
      self:_scroll('down', false, 1)
    end
  end

  navigate()
end

function EditorController:_search_mode_keys(k)
  if k == 'escape' then
    self:set_mode('nav')
    self.search:clear()
    return
  end

  self.input:update_view()
  local jump = self.search:keypressed(k)
  if jump then
    local buf = self:get_active_buffer()
    local bn = jump.block
    local ln = jump.line - 1
    buf:set_selection(bn)
    self.view:get_current_buffer():scroll_to_line(ln)
    self:set_mode('nav')
    self.search:clear()
  end
end

--- @private
--- @param k string
function EditorController:_normal_mode_keys(k)
  local input          = self.input
  local inputView      = self.view.input
  local is_empty       = input:is_empty()
  local at_limit_start = inputView:is_at_limit('up')
  local at_limit_end   = inputView:is_at_limit('down')
  local passthrough    = true
  local block_input    = function() passthrough = false end
  --- @type BufferModel
  local buf            = self:get_active_buffer()

  local function delete_block()
    local t = string.unlines(buf:get_selected_text())
    self:record_write(buf, function()
      buf:delete_selected_text()
      love.system.setClipboardText(t)
      self:save(buf)
    end)
    self.view:refresh()
  end

  local function paste()
    local t = love.system.getClipboardText()
    input:add_text(t)
  end
  local function copy()
    local t = string.unlines(buf:get_selected_text())
    love.system.setClipboardText(t)
    self:set_clipboard(t)
    block_input()
  end
  local function cut()
    copy()
    delete_block()
  end

  local function copycut()
    if Key.ctrl() then
      if k == "c" or k == "insert" then
        copy()
        block_input()
      end
      if k == "x" then
        cut()
        block_input()
      end
    end
    if Key.shift() then
      if k == "delete" then
        cut()
        block_input()
      end
    end
  end
  local function paste_k()
    if (Key.ctrl() and k == "v")
        or (Key.shift() and k == "insert")
    then
      paste()
      block_input()
    end
  end

  if is_empty then
    copycut()
  end
  paste_k()





  --- handlers
  --- @param force_accept boolean? --- the leave gate
  local function submit(force_accept)
    local bufv = self.view:get_current_buffer()

    --- Insert freshly composed text as new block(s)
    --- @param newtext Block[]
    --- @return boolean accepted
    local function add(newtext)
      if not bufv:is_selection_visible() then
        bufv:follow_selection()
        return false
      end

      local oversized = self:_first_oversized(newtext)
      if oversized then
        self:_reject_oversized(newtext, oversized)
        return false
      end

      local n = self:record_write(buf, function()
        local sel = buf:get_selection()
        local _, added = buf:insert_content(newtext, sel)
        self:save(buf)
        return added
      end)
      self.view:refresh()
      self:_move_sel('down', n)
      self:leave_edit()
      return true
    end

    --- undo/redo (1.1): the mode picks the level —
    --- editing works the text history of the open
    --- block, navigation works the file history
    if Key.ctrl() and not Key.alt() and not Key.shift()
        and (k == 'z' or k == 'y') then
      block_input()
      if self.mode == 'edit' then
        local im = self.input.model
        local done
        if k == 'z' then
          done = im:undo_edit()
        else
          done = im:redo_edit()
        end
        if done then
          self.input:update_view()
        else
          self:refuse()
        end
      else
        self:_step_history(k == 'y')
      end
      return
    end

    --- spec 2.7: Ctrl+Enter opens a fresh block below
    --- in navigation and accepts while editing;
    --- Ctrl+Shift+Enter opens one above
    if Key.ctrl() and not Key.alt() and Key.is_enter(k) then
      block_input()
      if self.mode == 'nav' then
        self:new_block(not Key.shift())
        return
      end
      if not Key.shift() then
        local accepted
        if buf.loaded then
          accepted = self:accept_block()
        else
          accepted = self:_handle_submit(add)
        end
        if not accepted then return end
      end
      return
    end

    if force_accept
        or (not Key.ctrl()
          and not Key.shift()
          and not Key.alt()
          and Key.is_enter(k)) then
      --- replace only what was deliberately opened;
      --- fresh text composed in navigation is inserted
      local accepted
      if buf.loaded then
        accepted = self:accept_block()
      else
        accepted = self:_handle_submit(add)
      end
      if not accepted then block_input() end
    end
  end
  --- open the selected block for editing (spec 2.2: Enter)
  local function open()
    self:open_block()
    block_input()
  end
  --- Leave the open block through the gate (spec 2.4):
  --- untouched leaves freely, changed is accepted and
  --- written, invalid refuses and stays
  --- @param dir VerticalDir
  local function leave(dir)
    local orig = buf:get_selected_text()
    local clean = string.unlines(input:get_text())
        == string.unlines(orig)
    local sel0 = buf:get_selection()

    if clean then
      buf:clear_loaded()
      input:clear()
      self:set_mode('nav')
      --- the cursor crossed the block's edge; sync the
      --- model's line to it so the step leaves the block
      local span = buf:get_selection_lines()
      buf:set_active_line(
        dir == 'up' and span.start or span.fin)
      if buf:move_line(dir) then
        self.view:get_current_buffer():follow_line()
        open()
      else
        self:refuse()
      end
      block_input()
      return
    end

    submit(true)
    if self.mode ~= 'nav' then
      --- refused; the message is set, stay on the block
      block_input()
      return
    end
    --- accepted: open the neighbor, cursor on the near
    --- line — downward its first, upward its last
    --- (2.4.4). Acceptance may have split the block
    --- into several, so step past all of them.
    local target = sel0 - 1
    if dir == 'down' then
      target = sel0 + self.accepted_n
    end
    if target < 1 or target > buf:get_content_length() then
      self:refuse()
      block_input()
      return
    end
    buf:set_selection(target)
    local span = buf:get_selection_lines()
    buf:set_active_line(
      dir == 'down' and span.start or span.fin)
    self.view:get_current_buffer():follow_line()
    open()
    block_input()
  end

  --- Ctrl+K checkpoints, Ctrl+Shift+K restores (2.6);
  --- a second press confirms, anything else cancels
  local function checkpoint_key()
    if not Key.ctrl() or k ~= 'k' then return end
    local con = self.console
    if not con then return end
    block_input()

    if self.mode == 'edit' then
      --- accept the open block first, so the
      --- checkpoint reflects the screen
      submit(true)
      if self.mode ~= 'nav' then return end
    end

    local name = buf.name
    local stamp = function(t)
      return t and os.date('%Y-%m-%d %H:%M', t) or '?'
    end
    local cp_time = con:checkpoint_modtime(name)

    if Key.shift() then
      if not cp_time then
        self:refuse({ 'no checkpoint to restore' })
        return
      end
      if self.pending_confirm == 'restore' then
        self.pending_confirm = nil
        if con:restore_checkpoint(name) then
          local text = con:_readfile(name)
          self:reload_active(text)
        end
        return
      end
      self.pending_confirm = 'restore'
      input:set_error({ string.format(
        'restore from checkpoint %s over file %s?'
        .. ' Ctrl+Shift+K again restores, Esc cancels',
        stamp(cp_time), stamp(con:file_modtime(name))
      ) })
      return
    end

    if cp_time and self.pending_confirm ~= 'overwrite' then
      self.pending_confirm = 'overwrite'
      input:set_error({ string.format(
        'checkpoint from %s exists;'
        .. ' Ctrl+K again overwrites, Esc cancels',
        stamp(cp_time)
      ) })
      return
    end
    self.pending_confirm = nil
    con:write_checkpoint(name)
  end

  --- spec 2.3: Shift+Esc discards the edit; on an empty
  --- input it leaves the buffer / editor
  local function discard()
    if not Key.ctrl() and
        Key.shift() and
        k == "escape" then
      if is_empty and self.mode == 'nav' then
        self:close_buffer()
        block_input()
        return
      end
      self:discard_edit()
      block_input()
    end
  end
  --- spec 2.7: Ctrl+Delete drops the block in
  --- navigation; while editing it is the widget's
  --- delete-next-word
  local function delete()
    if self.mode ~= 'nav' then return end
    --- bare Delete joins in with 1.1: the deletion is
    --- undoable now, which is what gated it (2.7)
    if k == "delete" then
      delete_block()
      block_input()
    end
  end
  local function navigate()
    -- move the block: Alt+arrows in nav (2.7); in
    -- editing Alt passes through to the input widget,
    -- which moves the line
    if Key.alt() and not Key.ctrl() then
      if self.mode == 'nav' then
        if k == "up" then
          self:_move_block('up')
          block_input()
        end
        if k == "down" then
          self:_move_block('down')
          block_input()
        end
      end
      return
    end

    -- peek: the view moves, the selection stays (2.2)
    if Key.ctrl() and Key.alt() then
      if k == "up" then
        self:_scroll('up', false, 1)
        block_input()
      end
      if k == "down" then
        self:_scroll('down', false, 1)
        block_input()
      end
      if k == "pageup" then
        self:_scroll('up', false)
        block_input()
      end
      if k == "pagedown" then
        self:_scroll('down', false)
        block_input()
      end
      --- left/right double the page peek: PgUp/PgDn is
      --- a four-key chord on the device keyboard
      if k == "left" then
        self:_scroll('up', false)
        block_input()
      end
      if k == "right" then
        self:_scroll('down', false)
        block_input()
      end
      return
    end

    -- move selection
    if Key.ctrl() then
      if self.mode == 'edit' then
        --- spec 2.7: accept + block-wise move
        if k == "up" then
          leave('up')
        end
        if k == "down" then
          leave('down')
        end
      else
        if k == "up" then
          self:_jump_block('up')
          block_input()
        end
        if k == "down" then
          self:_jump_block('down')
          block_input()
        end
      end
    elseif self.mode == 'nav' then
      --- spec 2.7: bare Home/End reach the file's first
      --- and last line; Ctrl+Home/End belong to the
      --- input widget while editing
      if k == "home" then
        self:_move_sel('up', nil, true)
        block_input()
      end
      if k == "end" then
        self:_move_sel('down', nil, true)
        block_input()
      end
      --- spec 2.2: bare arrows move by line, bare
      --- pages by a page, Ctrl+arrows (above) by block
      if k == "up" then
        self:_move_line('up')
        block_input()
      end
      if k == "down" then
        self:_move_line('down')
        block_input()
      end
      if k == "pageup" then
        self:_move_line_page('up')
        block_input()
      end
      if k == "pagedown" then
        self:_move_line_page('down')
        block_input()
      end
    elseif self.mode == 'edit' then
      --- crossing the block's edge leaves through the
      --- gate (2.4); inside, arrows stay in the input
      if k == "up" and at_limit_start then
        leave('up')
      end
      if k == "down" and at_limit_end then
        leave('down')
      end
    end

    -- scroll
    if Key.ctrl() and not Key.shift()
        and k == "pageup" then
      self:_scroll('up', true)
    end
    if Key.ctrl() and not Key.shift()
        and k == "pagedown" then
      self:_scroll('down', true)
    end
    if Key.shift()
        and k == "pageup" then
      self:_scroll('up', false, 1)
    end
    if Key.shift()
        and k == "pagedown" then
      self:_scroll('down', false, 1)
    end

    -- step into (spec 2.7: Ctrl+J "jump"; Ctrl+O is
    -- left free for a conventional "open file")
    if Key.ctrl() and not Key.alt() then
      if k == "j" then
        self:follow_require()
      end
    end
  end
  local plain_enter = Key.is_enter(k)
      and not Key.ctrl()
      and not Key.shift()
      and not Key.alt()

  if is_empty and plain_enter then
    if self.mode == 'nav' then open() end
  else
    submit()
  end
  checkpoint_key()
  discard()
  delete()
  navigate()

  if passthrough then
    input:keypressed(k)
  end
end

--- @param k string
function EditorController:keypressed(k)
  self.input:update_view()
  if self.pending_confirm
      and not (Key.ctrl() and k == 'k')
      and not (self.pending_confirm == 'discard'
        and Key.shift() and not Key.ctrl()
        and k == 'escape') then
    --- anything else cancels the confirmation (Esc
    --- included); the message clears with the keypress
    self.pending_confirm = nil
  end
  local mode = self.mode

  if Key.ctrl() then
    if k == "m" then
      self:set_mode('reorder')
    end
    if k == "f" then
      self:set_mode('search')
    end
  end

  if mode == 'reorder' then
    self:_reorg_mode_keys(k)
  elseif mode == 'search' then
    self:_search_mode_keys(k)
  else
    self:_normal_mode_keys(k)
  end

  if love.debug then
    local buf = self:get_active_buffer()
    local bufview = self.view:get_buffer(buf:get_id())
    if k == 'f5' then
      if Key.ctrl() then buf:rechunk() end
      bufview:refresh()
    end
  end
end
