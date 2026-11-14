require("model.interpreter.eval.evaluator")
require("controller.userInputController")
require("view.input.customStatus")
require("model.input.cursor")

local class = require('util.class')
local Syntax = require('model.syntax')
local KeyCard = require('model.editor.keyCard')
local EditorKeys = require('model.editor.editorKeys')

--- A write refused because the file changed outside the
--- editor (_refuse_stale), and a file that changed while
--- hidden to text the editor does not take
local OUTSIDE_NOTICE =
    'The file changed outside the editor, so nothing is saved.'

--- @param M EditorModel
--- @oaram CC ConsoleController
local function new(M, CC)
  return {
    -- Host chrome, not a transient widget: always_shown makes
    -- hide() refuse rather than leave the editor without an
    -- input line.
    input = UserInputController(M.input)
        :always_shown(),
    model = M,
    console = CC,
    view = nil,
    --- the keys whose press reached the editor since it came
    --- to the front, until their release
    pressed = {},
  }
end

--- @class EditorController
--- @field model EditorModel
--- @field input UserInputController
--- @field console ConsoleController
--- @field view EditorView?
--- @field pressed table<string, boolean>
EditorController = class.create(new)

--- A whole-editor exit (Ctrl+T, Ctrl+Q and Ctrl+R at the
--- gate) is taken from the browsing state. During an edit it
--- is refused with a notice, and no question is asked
--- (H-NFR4.6): the field may hold a cut block's only copy
--- (IS6.2), so the edit is submitted or aborted first
--- (FR1.2). The chord's own key reaches the editor after the
--- gate, and must not dismiss the notice (_held_back).
--- @return boolean refused
function EditorController:refuse_to_leave()
  if not self:get_active_buffer() then return false end
  if self:state_name() == 'browsing' then return false end
  self:refuse({
    'Finish the text first: Enter keeps it, Esc drops it.'
  })
  self._gate_key = true
  return true
end

--- A key press comes in at the gate
function EditorController:key_begins()
  self._in_key = true
end

--- The editor comes to the front. During a key press, that
--- key is not the editor's: the gate's Ctrl+T, or the key a
--- program's hook opened a file on. It does nothing there,
--- and leaves the notice the editor came with (IS3.14).
function EditorController:came_forward()
  if self._in_key then self._gate_key = true end
  self.pressed = {}
end

--- The gate has passed its chord's key on: whether or not
--- the key reached the editor, no later key is the chord's
function EditorController:gate_key_done()
  self._gate_key = nil
  self._in_key = nil
end

--- @param k string
function EditorController:key_released(k)
  self.pressed[k] = nil
end

--- @param v EditorView
function EditorController:init_view(v)
  self.view = v
  self.input:init_view(self.view.input)
end

--- @private
--- The field shows and edits the front file's own draft
--- @param b BufferModel
function EditorController:_front(b)
  self.input.model = b.input
end

--- @param name string
--- @param content str?
--- @param save function
--- @param key string? --- the file's identity, project and
--- name (_find_buffer)
function EditorController:open(name, content, save, key)
  --- the file's syntax, by its name (model.syntax), is all
  --- that knows its language
  local syntax = Syntax.for_name(name)
  local b = BufferModel(name, content, save, syntax)
  b.key = key
  --- what the file held when it was read, missing included:
  --- a later change from outside is told from it (_baseline)
  if type(content) == 'table' then
    --- lines given, no text read: the card says what it holds
    b.disk_seen = self:_disk_text(b)
  else
    self:_note_read(b, content)
  end
  --- the file's own field: its draft and the draft's changes
  --- stay with it while another file is in front (IS1.5,
  --- IS6.6)
  b.input = UserInputModel(self.model.cfg, syntax.evaluator(),
    nil, true)
  self.model.buffers:push_front(b)
  self:_front(b)
  self.view:open(b)
  --- a file opens ready to append, at its end position
  --- (IS1.1)
  b:set_selection(b:get_content_length() + 1)
  self.view:get_current_buffer():follow_selection()
  self:update_status()
  self.input:update_view()
end

--- Ctrl+J follows the file the viewed block names with
--- require or dofile (IS1.5). A refusal leaves the file and
--- the state as they are, and says why.
function EditorController:follow_require()
  local buf = self:get_active_buffer()
  --- an edit in progress is resolved first (FR1.2)
  if self:state_name() ~= 'browsing' then
    return self:refuse({
      'Finish the text first: Enter keeps it, Esc drops it.'
    })
  end
  local bn = buf:get_selection()
  if bn > buf:get_content_length() then
    return self:refuse({
      'End of file. Move onto a line with require or dofile.'
    })
  end
  local reqs = buf.semantic and buf.semantic.requires or {}
  local reqsel = table.find_by_v(reqs, function(r)
    return r.block == bn
  end)
  if not reqsel then
    return self:refuse({
      'No file named here. Ctrl+J needs require or dofile.'
    })
  end
  self.console:edit(reqsel.file, true)
end

function EditorController:pop_buffer()
  local bs = self.model.buffers
  local n_buffers = bs:length()
  if n_buffers < 2 then return end
  local out = bs:pop_front()
  self:_let_go(out)
  local b = bs:first()
  self:_front(b)
  local bv = self.view:get_current_buffer()
  --- the caller comes back as it was left: the buffer
  --- keeps its position, and the view its rows (IS1.6) —
  --- open() alone parks the view at the end
  local off = bv:get_offset()
  bv:open(b)
  bv:scroll_to(off)
  self:_take_outside_change()
  self:update_status()
end

--- @private
--- @param key string
--- @return BufferModel?
function EditorController:_find_buffer(key)
  for _, b in ipairs(self.model.buffers) do
    if b.key == key then return b end
  end
end

--- @private
--- A buffer gone from the stack takes its view with it
--- @param b BufferModel
function EditorController:_let_go(b)
  for _, open in ipairs(self.model.buffers) do
    if open == b then return end
  end
  self.view.buffers[b:get_id()] = nil
end

--- Step back from the file (IS1.6): to its caller, or from
--- the last file to the console
function EditorController:close_buffer()
  local bs = self.model.buffers
  local n_buffers = bs:length()
  if n_buffers < 2 then
    self.console:finish_edit()
  else
    self:pop_buffer()
  end
end

--- One sound for every refused action (spec 2.4.3):
--- a knock means "no further this way". With words, a
--- notice too (IS3.14): it names what was refused and the
--- action that would work.
--- @param msg (string|string[])? --- the notice's words
--- @param kind MessageKind? --- 'error': the parser's message
function EditorController:refuse(msg, kind)
  --- required here, not at the top: util.audio builds
  --- its sources on load and needs love.audio ready
  require("util.audio").knock()
  if msg then self:notice(msg, kind) end
end

--- What a message in the band is: a notice says why an
--- action was refused and what would work; an error is the
--- parser's message for a draft that is not valid Lua. The
--- band draws each in its own colour.
--- @alias MessageKind 'notice'|'error'

--- Show a message in the message band (IS3.14): a notice,
--- unless `kind` says it is an error. It blocks no input and
--- changes no state; the next key press dismisses it
--- (_held_back).
--- @param msg string|string[]
--- @param kind MessageKind?
function EditorController:notice(msg, kind)
  local model = self.input.model
  local w = model.visible and model.visible.wrap_w or 64
  local rows = { }
  local parts = type(msg) == 'table' and msg or { msg }
  for _, part in ipairs(parts) do
    --- a word wider than a row is left to the field's wrap
    local wrapped = string.wrap_words(tostring(part), w)
    for _, row in ipairs(wrapped) do
      rows[#rows + 1] = row
    end
  end
  model:set_error(rows)
  if model.error then
    model.error.notice = true
    model.error.kind = kind or 'notice'
  end
end

--- The kind of the message the band shows, nil when none
--- shows. A message shown another way than through `notice`
--- is an error.
--- @return MessageKind?
function EditorController:message_kind()
  local e = self.input.model.error
  if type(e) ~= 'table' or #e == 0 then return nil end
  return e.kind or 'error'
end

--- A key that does nothing on its own: a modifier, a lock or
--- the help key. It dismisses no notice (IS3.14).
local LOCKS = {
  capslock = true,
  numlock = true,
  scrolllock = true,
  lgui = true,
  rgui = true,
  [KeyCard.KEY] = true,
}

--- @param k string
--- @return boolean
local function lone_key(k)
  return Key.is_mod(k) or LOCKS[k] == true
end

--- Whether a key press is held back from the editor's keys:
--- every key while the key card shows (IS3.16), and a gate
--- chord's own key. Ctrl+Escape is the gate's on its release,
--- and exits whether or not the card shows. A message is a hint that blocks nothing
--- (IS3.14): any other key dismisses it here and then does
--- its ordinary work, Escape included, which aborts the edit
--- or steps back from the file in the same press.
--- @param k string? --- nil for typed text
--- @return boolean
function EditorController:_held_back(k)
  if KeyCard.shows(self.pressed) then return true end
  --- a gate chord's own key reaches the editor after the
  --- gate refused the exit, or the key the editor came to
  --- the front on (came_forward): it must not dismiss the
  --- notice
  if self._gate_key and k and not Key.is_mod(k) then
    self._gate_key = nil
    return true
  end
  --- a modifier or a lock on its own leaves it showing. The
  --- glyph a modifier chord leaks on the device leaves it
  --- showing too, because it never comes here: the event gate
  --- stops it (Key.chord_text)
  local lone = k and lone_key(k)
  if self.input:has_error() and not lone then
    self.input:clear_error()
  end
  return false
end

--- The editor's state: a loaded block is replaced, a draft
--- alone is inserted, an empty field browses. A draft of
--- spaces or of empty lines is a draft. Every guard that
--- depends on the state asks here.
--- @return EditorStateName
function EditorController:state_name()
  local buf = self:get_active_buffer()
  if buf and buf.loaded then return 'replacing' end
  if self:_draft_is_empty() then return 'browsing' end
  return 'inserting'
end

--- @private
--- @return boolean
function EditorController:_draft_is_empty()
  local t = self.input:get_text()
  if type(t) == 'table' then t = table.concat(t, '\n') end
  return t == nil or t == ''
end

--- Whether the editor is in front and its key card shows:
--- every key is suspended then, the reserved chords too
--- (IS3.16)
--- @return boolean
function EditorController:card_shows()
  return love.state.app_state == 'editor'
      and KeyCard.shows(self.pressed)
end

--- The key card's lines while the help key is held (FR4.9),
--- nil otherwise.
--- @return string[]?
function EditorController:key_card()
  if not self:card_shows() then return nil end
  local card = self.view.key_card
  return card:lines(self:state_name(), self:_draft_is_empty())
end

--- A run of the project hides the editor (IS1.4): its
--- files stay as they are. The key that hides it acts, so it
--- dismisses the message (IS3.14).
function EditorController:hide()
  self.input:clear_error()
end

--- The editor as a run left it, its front file as storage
--- holds it (IS1.4)
function EditorController:show()
  self:_take_outside_change()
  self:update_status()
  self.input:update_view()
end

--- @private
--- The front file, come to the front (shown after a run, or
--- stepped back to with Escape), shows the text storage holds
--- (_baseline): changed, it is read anew and its timeline
--- starts afresh; the browsing position keeps its block
--- number while the file has that block, else it goes to the
--- end position. A file is left only in the browsing state,
--- so no edit is in progress here. Text that is not UTF-8 is
--- not taken (IS1.2), and one that cannot be read is left as
--- it is: the guard refuses the next write (_refuse_stale).
function EditorController:_take_outside_change()
  local buf = self:get_active_buffer()
  if not buf then return end
  --- the text the change is told by is the text taken
  local seen, text = self:_baseline(buf)
  if seen ~= 'changed' then return end
  if type(text) == 'string' and not utf8.len(text) then
    self:notice({ OUTSIDE_NOTICE })
    return
  end
  local last = buf:get_content_length()
  local sel = buf:get_selection()
  buf:reload(text or nil)
  self:_note_read(buf, text or nil)
  self:timeline_forget(buf)
  self.input.model.edit_history:reset()
  if sel > last then sel = buf:get_content_length() + 1 end
  buf:set_selection(sel)
  self:_reuse_show()
end

--- Leave the editor: every file goes, and its timeline
--- (IS6.6)
function EditorController:close()
  self.input.model = self.model.input
  self.model.buffers = Dequeue()
  self.view.buffers = {}
end

--- @return BufferModel
function EditorController:get_active_buffer()
  return self.model.buffers:first()
end

--- @private
--- @param sel integer
--- @return CustomStatus
function EditorController:_generate_status(sel)
  --- @type BufferModel
  local buffer = self:get_active_buffer()
  local len = buffer:get_content_length() + 1
  local bufview = self.view:get_buffer(buffer:get_id())
  --- a block's rows are named where a block may span lines
  local spans = buffer.syntax.spans_lines
  local range = spans and bufview.content:get_block_app_pos(sel)
  local cs = CustomStatus(buffer.name, spans, len, sel,
    range or nil)
  --- the state and the open project, always shown (FR4.6)
  cs.state = self:state_name()
  local projects = self.console and self.console.model
      and self.console.model.projects
  local project = projects and projects.current
  cs.project = project and project.name

  return cs
end

--- The status as it is now, for a status line that follows
--- the draft and the browsing position between updates.
--- @private
--- @return CustomStatus?
function EditorController:_live_status()
  local buffer = self:get_active_buffer()
  if not (buffer and self.view) then return nil end
  local bufview = self.view:get_buffer(buffer:get_id())
  if not (bufview and bufview.content) then return nil end
  return self:_generate_status(buffer:get_selection())
end

function EditorController:update_status()
  local sel = self:get_active_buffer():get_selection()
  local cs = self:_generate_status(sel)
  self.input:set_custom_status(cs)
  local model = self.input.model
  if not model.status_source then
    model.status_source = function()
      return self:_live_status()
    end
  end
end

--- @param t string
function EditorController:textinput(t)
  if self:_held_back() then return end
  self.view:update_input()
  --- typing prepares a draft in the field and opens no
  --- block (IS3.1). A chord's own glyph never comes here:
  --- the event gate stops it (Key.chord_text)
  self.input:textinput(t)
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
  --- the undo timeline notes what the file now holds
  if ok and self._note_saved then self:_note_saved(buf) end
  --- what the notice names (IS1.7)
  self.save_failure = not ok and {
    name = buf.name,
    reason = err,
  } or nil
  return ok, err
end

--- @private
--- Say the write failed (IS1.7): the file, the reason the
--- storage gave, and that the text is still in the field
function EditorController:_refuse_unsaved()
  local f = self.save_failure or {}
  local name = f.name or self:get_active_buffer().name
  local reason = type(f.reason) == 'string' and f.reason ~= ''
      and string.format(' (%s)', f.reason) or ''
  self:refuse({ string.format(
    'Could not save %s%s. Your text is kept: try Enter again.',
    name, reason
  ) })
end

---------------------------
---  keyboard handlers  ---
---------------------------

--- @private
--- The file's syntax gives the verdict (model.syntax). An
--- accepted draft goes to go as the syntax's blocks. One that
--- fails gets the cursor before the failing character (IS3.4).
--- Any other is shown as the syntax returns it, as one
--- undoable change, the cursor where the syntax puts it or
--- where it stood, under the syntax's notice if it gives one
--- (IS3.2, IS3.3, IS3.5, IS3.9).
--- @param go fun(newtext: Block[]): boolean
--- @return boolean accepted --- go's verdict, or false
--- when the draft is not taken
function EditorController:_handle_submit(go)
  local inter = self.input
  local raw = inter:get_text()
  local buf = self:get_active_buffer()
  local verdict = buf.syntax.submit(raw,
    self.model.cfg.view.drawableChars, self:_size_limit())
  --- an accepted draft goes as the syntax's blocks; one that
  --- fails to land (a write refused) stays as typed
  if verdict.blocks then return go(verdict.blocks) end
  local failure = verdict.failure
  if failure then
    --- IS3.4: the cursor goes before the failing character,
    --- where the red text starts, and the parser's message
    --- shows (NFR4.3)
    self:refuse({ tostring(failure) }, 'error')
    inter.model:move_cursor(failure.l, failure.c or 1)
    inter:update_view()
    return false
  end
  if verdict.formatted or verdict.cursor then
    inter.model:reformat(verdict.lines, verdict.cursor)
  end
  if verdict.refusal then self:refuse({ verdict.refusal }) end
  inter:update_view()
  return false
end

--- A click goes to the field alone: a click on a block no
--- longer browses to it (PR #28, D-MOUSE-BROWSE: the mouse
--- needs a design of its own)
--- @param x number
--- @param y number
--- @param btn integer
--- @param touch boolean?
--- @param presses integer? --- 2 on a double click
function EditorController:mousepressed(x, y, btn, touch, presses)
  self.input:mousepressed(x, y, btn, touch, presses)
end

--- @return integer --- the block size limit (IS1.3), which
--- only a submission is held to
function EditorController:_size_limit()
  return self.view:get_current_buffer():get_max_size()
end

--- @param buf BufferModel
--- @param bn integer
--- @return integer --- how many blocks with text stand before
--- block `bn`
local function text_blocks_before(buf, bn)
  local n = 0
  for i = 1, bn - 1 do
    if buf:block_lines(i) then n = n + 1 end
  end
  return n
end

--- @param buf BufferModel
--- @param n integer
--- @return integer? --- the block that has `n` blocks with
--- text before it and text of its own
local function nth_text_block(buf, n)
  local seen = 0
  for i = 1, buf:get_content_length() do
    if buf:block_lines(i) then
      if seen == n then return i end
      seen = seen + 1
    end
  end
end

--- Format the whole open file (Alt+F, browsing) as
--- its syntax formats it. It is the one place blank lines
--- outside a block change: the user asked, and every run of
--- them becomes one. The selection stays on the block with
--- text it was on, counted among the blocks with text, or on
--- the next one from an empty line. A refusal says why in a
--- notice, as every refusal does: during an edit, and in a
--- file the syntax leaves as it is.
function EditorController:format_file()
  local buf = self:get_active_buffer()
  local state = self:state_name()
  if state == 'inserting' then
    return self:refuse({ 'Finish the text first: Enter adds it,'
      .. ' Esc drops it.' })
  end
  if state == 'replacing' then
    return self:refuse({ 'Finish editing first: Enter keeps it,'
      .. ' Esc drops it.' })
  end
  --- text the editor cannot read has no tidy form: it stays
  --- as it is, line for line
  if buf.invalid then
    return self:refuse({
      'The editor cannot split this file into blocks,'
      .. ' so it stays as it is.'
    })
  end
  if self:_refuse_stale(buf) then return end
  local snap = buf:snapshot()
  local before = snap.lines
  local after, formatted, why = buf.syntax.format(before,
    self.model.cfg.view.drawableChars)
  if not formatted then
    return self:refuse({ 'The file ' .. why .. '.' })
  end
  if string.unlines(after) == string.unlines(before) then
    return
  end

  --- which block with text the selection is on, or above
  local nth = text_blocks_before(buf, buf:get_selection())

  local sel_before = buf:get_selection()
  buf:replace_text(after)
  if not self:save(buf) then
    --- the screen keeps showing the file, so trying again
    --- formats it again. A failed save leaves the file as it
    --- was (FS.replace), and so the buffer goes back
    buf:restore(snap)
    buf:set_selection(sel_before)
    buf:analyze()
    self.view:refresh()
    return self:refuse({
      'Could not save the file.'
      .. ' Check the storage and try again.'
    })
  end

  local sel = nth_text_block(buf, nth)
      or buf:get_content_length()
  buf:set_selection(sel)
  buf:push_history(snap, sel_before, sel)
  self.view:refresh()
  self.view:get_current_buffer():follow_selection()
  self:update_status()
end

--- blocks a page key browses

--- The undo timeline (controller.editorReuse) hears of each
--- action twice: _record_action(kind) while the state it
--- takes back is still in place, _action_done(kind) once it
--- has landed. The kinds: 'insert', 'replace', 'empty_line',
--- 'abort', 'begin', 'switch', 'reload'.

--- @private
--- Browse blocks (IS2.1): the draft, its cursor and the
--- replacement target stay as they are (IS2.3)
--- @param dir VerticalDir
function EditorController:_browse(dir)
  local buf = self:get_active_buffer()
  --- a block taller than the view scrolls by a row first
  --- (IS2.2)
  local bv = self.view:get_current_buffer()
  if bv:scroll_block(dir) then return end
  if buf:move_selection(dir) then
    bv:follow_selection()
    self:update_status()
  end
end

--- @private
--- PgDn and PgUp browse a page at a time (the maintainer's
--- ruling of November 14, 2026; BufferView:page): the
--- browsing position moves with the page and stays in view,
--- and the draft and the target stay (IS2.3)
--- @param dir VerticalDir
function EditorController:_page(dir)
  local bv = self.view:get_current_buffer()
  local b, top = bv:page(dir)
  if b then self:get_active_buffer():set_selection(b) end
  if top then
    bv:show_from(top)
  else
    bv:follow_selection()
  end
  self:update_status()
end

--- @private
--- Load a block into the field as the draft, the cursor at
--- its end (FR1.5), and make it the replacement target
--- @param bn integer
--- @param lines string[]
function EditorController:_load_target(bn, lines)
  local buf = self:get_active_buffer()
  buf:set_loaded(bn)
  self.input:set_text(lines)
  self:update_status()
end

--- @private
--- A block's text as Edit loads it: formatted as its syntax
--- formats it, as far as it can, so a line over the limit
--- may come back within it (ruling: F2 opens a block that
--- breaks a limit); as it stands when it does not format.
--- Loading is no change to the draft (IS5.6).
--- @param lines string[]
--- @return string[]
function EditorController:_as_loaded(lines)
  return (self:get_active_buffer().syntax.format(lines,
    self.model.cfg.view.drawableChars))
end

--- @private
--- @return boolean --- the draft is not the text Edit loaded
--- for the replacement target (IS5.6), whatever the draft's
--- steps hold: text typed and deleted again is no change,
--- and a change stays one when a change from outside has
--- ended the steps (_timeline_ready)
function EditorController:_draft_modified()
  local buf = self:get_active_buffer()
  local target = buf.loaded
  if not target then return false end
  local lines = buf:block_lines(target)
  local loaded = lines and self:_as_loaded(lines) or {}
  return table.concat(loaded, '\n')
      ~= table.concat(self.input:get_text(), '\n')
end

--- @private
--- @param bn integer
--- @return string[]? lines --- the block Edit may open
--- @return string? why --- the notice when it may not
function EditorController:_editable_lines(bn)
  local buf = self:get_active_buffer()
  if bn > buf:get_content_length() then
    return nil, 'End of file: no block to edit here.'
        .. ' Move up onto one.'
  end
  local lines = buf:block_lines(bn)
  if not lines then
    return nil, 'An empty line has nothing to edit.'
        .. ' Move onto a block.'
  end
  --- whatever the block holds, a block over the limit or a
  --- line of a file the editor cannot split into blocks: the
  --- language's check judges the submission (ruling of
  --- November 14, 2026, over IS1.3)
  return self:_as_loaded(lines)
end

--- Edit: begin a replacement (IS5.1), restore the target's
--- text (IS5.5) or switch the target (IS5.6)
function EditorController:edit_block()
  local buf = self:get_active_buffer()
  local sel = buf:get_selection()
  local target = buf.loaded
  if self:state_name() == 'inserting' then
    return self:refuse({
      'Finish the text first: Enter adds it, Esc drops it.'
    })
  end
  local modified = target and self:_draft_modified()
  if target == sel then
    --- one change to the draft, which Ctrl+Z takes back; an
    --- unmodified draft only gets its cursor at the end
    if modified then
      self:_record_action('reload')
      self.input.model:reformat(
        self:_as_loaded(buf:block_lines(sel)))
    end
    self.input.model:jump_end()
    self.input:update_view()
    if modified then self:_action_done('reload') end
    return
  end
  if modified then
    return self:refuse({
      'Already editing a block:'
      .. ' Enter keeps it, Esc drops it.'
    })
  end
  local lines, why = self:_editable_lines(sel)
  if not lines then return self:refuse({ why }) end
  local kind = target and 'switch' or 'begin'
  self:_record_action(kind)
  self:_load_target(sel, lines)
  self:_action_done(kind)
end

--- Abort the edit at once (IS5.7): the draft and the
--- replacement target go, the browsing position stays
function EditorController:cancel_edit()
  self:_record_action('abort')
  self:get_active_buffer():clear_loaded()
  self.input:clear()
  self:update_status()
  self:_action_done('abort')
end

--- The guard every write passes: the file is written only
--- when it can be read and holds what the editor last read
--- or wrote there (_baseline). Otherwise the action is
--- refused with a notice, and nothing changes (IS3.11).
--- @param buf BufferModel
--- @return boolean refused
function EditorController:_refuse_stale(buf)
  local seen = self:_baseline(buf)
  if seen == 'same' then return false end
  if seen == 'unknown' then
    self:refuse({ string.format(
      'Could not read %s, so nothing is saved.'
      .. ' Check the SD card.', buf.name) })
  else
    self:refuse({ OUTSIDE_NOTICE })
  end
  return true
end

--- @private
--- Put accepted lines into the file: in the replacement
--- target's place (IS5.3), else before the browsing position
--- (IS4.1) or at the end (IS4.2). The position ends on the
--- block after them (FR3.5, IS5.4).
--- A Lua file stays one chunk whose blocks read as they
--- stand (IS3.7): text that would stop the file loading, or
--- join a neighbor into one statement, is refused.
--- @param lines string[]
--- @param kind string
--- @param n integer? --- the blocks the lines make on their
--- own
--- @return boolean landed
--- @return string[]? lines --- the lines landed
function EditorController:_land(lines, kind, n)
  local buf = self:get_active_buffer()
  local target = buf.loaded
  local sel = buf:get_selection()
  local count = buf:get_content_length() - (target and 1 or 0)
  local before = buf:snapshot()
  if self:_refuse_stale(buf) then return false end
  local whole = self:_reads_whole()
  --- the buffer goes back to what the file holds, and the
  --- edit stays open
  local function put_back()
    buf:restore(before)
    buf:_text_change()
    buf:analyze()
    buf:set_selection(sel)
    self.view:refresh()
  end
  local pos
  if target then
    pos = buf:replace_lines(target, lines)
  else
    pos = buf:insert_lines(sel, lines)
  end
  local why = self:_reuse_refusal(whole, n and count + n,
    'This would merge with the block next to it'
    .. ' into one statement.')
  if why then
    put_back()
    self:refuse({ why })
    return false
  end
  if not self:save(buf) then
    --- a failed write must not read as accepted
    put_back()
    self:_refuse_unsaved()
    return false
  end
  --- the timeline hears of the action once nothing can
  --- refuse it, and before its step is pushed
  self:_record_action(kind)
  local top = buf.history[#buf.history]
  buf:push_history(before, sel, pos)
  local step = buf.history[#buf.history]
  if step ~= top then
    --- undone, the position is the first restored block, or
    --- where the removed ones stood (IS6.6)
    step.pos_undone = target or sel
  end
  buf:clear_loaded()
  buf:set_selection(pos)
  self.input:clear()
  self.view:refresh()
  self.view:get_current_buffer():follow_selection()
  self:update_status()
  self:_action_done(kind)
  return true, lines
end

--- Enter: submit the draft (IS4.1, IS4.2, IS5.3); an empty
--- one is an empty line (IS4.3)
--- @return boolean accepted
--- @return string[]? lines --- the lines the file took
function EditorController:submit()
  local buf = self:get_active_buffer()
  if self:_draft_is_empty() then
    return self:_land({ '' },
      buf.loaded and 'replace' or 'empty_line', 1)
  end
  local kind = buf.loaded and 'replace' or 'insert'
  return self:_handle_submit(function(blocks)
    return self:_land(BufferModel.lines_of(blocks), kind,
      #blocks)
  end)
end

--- What the key tables' actions do (editorKeys.lua), each
--- called with the controller, the key and whether it is a
--- repeat
local ACTIONS = {
  none = function() end,
  submit = function(ec) ec:submit() end,
  submit_and_retain = function(ec) ec:submit_and_retain() end,
  edit_block = function(ec) ec:edit_block() end,
  escape = function(ec)
    if ec:state_name() == 'browsing' then
      --- stepping back from a file (IS1.6)
      ec:close_buffer()
    else
      ec:cancel_edit()
    end
  end,
  browse = function(ec, k) ec:_browse(k) end,
  --- browsing with an empty draft (IS2.1), a row in one
  vertical = function(ec, k)
    if ec:_draft_is_empty() then
      ec:_browse(k)
    else
      ec.input:keypressed(k)
    end
  end,
  --- with an empty field: Home to the first block, End to the
  --- end position
  file_edge = function(ec, k)
    local buf = ec:get_active_buffer()
    local to = k == 'home' and 1 or buf:get_content_length() + 1
    buf:set_selection(to)
    ec.view:get_current_buffer():follow_selection()
    ec:update_status()
  end,
  --- while replacing: the browsing position to the target,
  --- shown as browsing to it shows it; the draft stays
  to_target = function(ec)
    local buf = ec:get_active_buffer()
    if buf:get_selection() == buf.loaded then return end
    buf:set_selection(buf.loaded)
    ec.view:get_current_buffer():follow_selection()
    ec:update_status()
  end,
  page = function(ec, k)
    ec:_page(k == 'pageup' and 'up' or 'down')
  end,
  copy_block = function(ec) ec:copy_block() end,
  cut_block = function(ec) ec:cut_block() end,
  move_block = function(ec, k) ec:move_block(k) end,
  undo = function(ec, _, rep) ec:timeline_undo(rep) end,
  redo = function(ec, _, rep) ec:timeline_redo(rep) end,
  follow_require = function(ec) ec:follow_require() end,
  format_file = function(ec) ec:format_file() end,
  --- with love.debug: the view drawn anew, and with Ctrl the
  --- file split anew
  debug_refresh = function(ec)
    if not love.debug then return end
    local buf = ec:get_active_buffer()
    local bufview = ec.view:get_buffer(buf:get_id())
    if Key.ctrl() then buf:rechunk() end
    bufview:refresh()
  end,
}

--- A key is looked up by its full chord in the table of the
--- state in front (editorKeys.lua), then in the text field's
--- (fieldKeys.lua); a chord neither names does nothing.
--- @param k string
--- @param _ string? --- LÖVE's scancode, unused
--- @param isrepeat boolean? --- the key is held
function EditorController:keypressed(k, _, isrepeat)
  local chord = Key.combo(k)
  local entry = EditorKeys:lookup(self:state_name(), chord)
  local field = not entry and self.input:names(chord)
  local bound = entry or field
  --- a held key repeats only if its entry says so, and only
  --- where its press acted: one held since before the editor
  --- came to the front, a program's, does nothing in it
  local repeats = bound and bound.repeats and self.pressed[k]
  if isrepeat and not repeats then return end
  if self:_held_back(k) then return end
  --- only a bare F1 is the help key (KeyCard.shows)
  if k ~= KeyCard.KEY or chord == KeyCard.KEY then
    self.pressed[k] = true
  end
  if not bound then return end
  self.input:update_view()
  if entry then
    ACTIONS[entry.act](self, k, isrepeat)
  else
    self.input:keypressed(k, nil, isrepeat)
  end
end

require("controller.editorReuse")
