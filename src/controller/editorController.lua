require("model.interpreter.eval.evaluator")
require("controller.userInputController")
require("view.input.customStatus")
require("model.input.cursor")

local class = require('util.class')
local lua = require('model.editor.luaLayer')
local KeyCard = require('model.editor.keyCard')
local HeldKeys = require('model.input.heldKeys')

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
    -- input line. Selection is disabled on both surfaces.
    input = UserInputController(M.input, true, true)
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

--- @private
--- DEPRECATED (owner ruling, 2026-09-06). Ctrl+Shift+S
--- leaves the editor and stays bound, but Escape is the
--- supported way out (IS1.6) and this chord is on its way to
--- removal. Its author calls it inherited, absent from the
--- editor spec, and it is undocumented in the editor's own
--- keymap. It is kept only because our shipped guide, the
--- README walkthrough and a spec of ours all carry it.
--- Route-level and not a gate reservation, because the gate
--- binds only what competes with a running project
--- (D-EXACT-RESERVE, "Scope"), and nothing runs while the
--- editor owns the route.
--- @param k string
--- @return boolean handled --- the editor is closed, so the
--- key must reach no mode handler after it
function EditorController:_leave_keys(k)
  if k == "s" and Key.shift() and not Key.alt() then
    if not self:refuse_to_leave(true) then
      self.console:finish_edit()
    end
    return true
  end
  return false
end

--- A whole-editor exit (Ctrl+Shift+S here; Ctrl+T, Ctrl+Q
--- and Ctrl+Alt+R at the gate) is taken from the browsing
--- state. During an edit it
--- is refused with a notice, and no question is asked
--- (H-NFR4.6): the field may hold a cut block's only copy
--- (IS6.2), so the edit is submitted or aborted first
--- (FR1.2).
--- @param own_key boolean? --- the editor is handling the
--- chord's key itself (Ctrl+Shift+S), so no later key is it
--- @return boolean refused
function EditorController:refuse_to_leave(own_key)
  if not self:get_active_buffer() then return false end
  if self:state_name() == 'browsing' then return false end
  self:refuse({
    'Finish the text first: Enter keeps it, Esc drops it.'
  })
  self._gate_key = not own_key or nil
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

--- A file's field reads its draft as the file's type does
--- (IS1.2, IS3.2): the name's ending fixes the type, and any
--- other name is plain text
--- @param name string
--- @return table eval
local function file_eval(name)
  if string.match(name, '%.lua$') then return LuaEditorEval end
  if string.match(name, '%.md$') then return MdEval() end
  return TextEval
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
  local w = self.model.cfg.view.drawableChars
  local is_lua = string.match(name, '%.lua$')
  local is_md = string.match(name, '%.md$')
  local ch, hl, pp, tr
  local eval = file_eval(name)

  if is_lua then
    local luaEval = LuaEval()
    local parser = luaEval.parser
    if not parser then return end
    hl = luaEval.highlighter
    --- @param t string
    --- @param single boolean
    ch = function(t, single)
      return lua.chunker(t, w, single)
    end
    pp = function(t)
      local out, formatted = lua.format(t, w)
      if formatted then return out end
    end
    tr = function(code)
      return parser.trunc(code, self.model.cfg.view.fold_lines)
    end
  elseif is_md then
    hl = eval.highlighter
  end

  local b = BufferModel(name, content, save, ch, hl, pp, tr)
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
  b.input = UserInputModel(self.model.cfg, eval, nil, true)
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
  --- dofile names the file; require names its module, a
  --- dot for each folder on the way
  local name = reqsel.name
  if not reqsel.file and not string.match(name, '%.lua$') then
    name = string.gsub(name, '%.', '/') .. '.lua'
  end
  self.console:edit(name, true)
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
--- chord's own key. A message is a hint that blocks nothing
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

--- The key card's lines while the help key is held (FR4.9),
--- nil otherwise.
--- @return string[]?
function EditorController:key_card()
  if love.state.app_state ~= 'editor' then return nil end
  if not KeyCard.shows(self.pressed) then return nil end
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
  local cs
  local ct = bufview.content_type
  if ct == 'lua' then
    local range = bufview.content:get_block_app_pos(sel)
    cs = CustomStatus(buffer.name, ct, len, sel, range)
  else
    cs = CustomStatus(buffer.name, ct, len, sel)
  end
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
--- The language layer's gate gives the verdict, as
--- model.editor.luaLayer presents it (submission). An
--- accepted draft goes to go as its formatted blocks. A draft
--- unfinished at its end goes on, on a new line (IS3.5); one
--- that fails earlier gets the cursor before the failing
--- character (IS3.4); one with a line over the limit is shown
--- formatted, the cursor kept, under a notice naming the
--- limit (IS3.3). A block too large is go's to refuse, after
--- its own checks.
--- @param go fun(newtext: Block[]|string[], verdict: SubmissionVerdict?): boolean
--- @return boolean accepted --- go's verdict, or false
--- when the input does not evaluate
function EditorController:_handle_submit(go)
  local inter = self.input
  local raw = inter:get_text()

  local buf = self:get_active_buffer()
  local ct = buf.content_type
  if ct == 'lua' then
    --- IS3.7: empty lines alone become empty-line blocks
    local empties = lua.empty_blocks(raw)
    if empties then
      return go(empties)
    elseif not string.is_non_empty_string_array(raw) then
      local sel = buf:get_selection()
      local block = buf:get_content():get(sel)
      if not block then return true end
    else
      local verdict = lua.submission(raw,
        self.model.cfg.view.drawableChars, self:_size_limit())
      --- an accepted draft goes as its formatted blocks; one
      --- that fails to land (a write refused) stays as typed
      if #verdict.errors == 0 then
        return go(verdict.blocks, verdict)
      end
      local failure = verdict.failure
      if failure and failure.at_end then
        --- IS3.5: a draft that is only unfinished goes on, on
        --- a new line at its end
        inter.model:continue_line()
        inter:update_view()
        return false
      end
      if failure then
        --- IS3.4: the cursor goes before the failing character,
        --- where the red text starts, and the parser's message
        --- shows (NFR4.3)
        self:refuse({ tostring(failure) }, 'error')
        inter.model:move_cursor(failure.l, failure.c or 1)
        inter:update_view()
        return false
      end
      --- a draft refused for a line's length is shown
      --- formatted, as one undoable change to it, the cursor
      --- where it stood (IS3.2, IS3.9)
      if verdict.formatted then
        inter.model:reformat(verdict.lines)
      end
      local long = verdict.long_line
      self:refuse(long and { string.format(
        'Line %d has %d characters, the limit is %d.'
        .. ' Shorten or break it, then press Enter',
        long.l, long.len, lua.max_line_length
      ) } or verdict.errors)
      inter:update_view()
      return false
    end
  else
    return go(raw)
  end
  return true
end

--- A click on a block browses to it, as the browse keys do:
--- the draft and the replacement target stay (IS2.3)
--- @param x number
--- @param y number
--- @param btn integer
--- @param touch boolean?
--- @param presses integer? --- 2 on a double click
function EditorController:mousepressed(x, y, btn, touch, presses)
  if btn == 1 then
    local bv = self.view:get_current_buffer()
    local ln = bv:line_at(y)
    local buf = self:get_active_buffer()
    local bi = ln and buf:block_at_line(ln)
    if bi then
      buf:set_selection(bi)
      bv:follow_selection()
      self:update_status()
      return
    end
  end
  self.input:mousepressed(x, y, btn, touch, presses)
end

--- @return integer --- the block size limit (IS1.3), which
--- only a submission is held to
function EditorController:_size_limit()
  return self.view:get_current_buffer():get_max_size()
end

--- Refuse a block the gate found too large, and point
--- at it (9.6)
--- @param verdict SubmissionVerdict?
--- @return boolean refused
function EditorController:_reject_oversized(verdict)
  local first = verdict and verdict.oversized[1]
  if not first then return false end
  local block = verdict.blocks[first]
  --- the refused draft stays shown formatted, as one
  --- undoable change to it, the cursor where it stood
  --- (IS3.2, IS3.9)
  if verdict.formatted then
    self.input.model:reformat(verdict.lines)
  end
  --- IS3.3: the notice names the limit
  self:refuse({ string.format(
    'Block of %d lines, the limit is %d.'
    .. ' Shorten or split it, then press Enter',
    block.pos:len(), verdict.max_block
  ) })
  self.input:update_view()
  return true
end

--- @param lines string[]
--- @return table? --- the statements, when the text parses
local function statements(lines)
  local ok, ast = lua.parser().parse(lines)
  if ok then return ast end
end

--- Format the whole open file (Ctrl+Shift+F in navigation).
--- It is the one place blank lines outside a block change:
--- the user asked, and every run of them becomes one. The
--- selection stays on the statement it was on; from a blank
--- line or a comment it moves to the statement below.
function EditorController:format_file()
  local buf = self:get_active_buffer()
  if buf.content_type ~= 'lua' then
    return self:refuse()
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
  local after, formatted = lua.format(before,
    self.model.cfg.view.drawableChars)
  if not formatted then
    return self:refuse({
      'The file cannot be tidied without changing what'
      .. ' it does, so it stays as it is'
    })
  end
  if string.unlines(after) == string.unlines(before) then
    return
  end

  --- which statement the active line is on, or above
  local nth
  local ln = buf:get_active_line()
  for i, st in ipairs(statements(before) or {}) do
    if st.lineinfo.last.line >= ln then
      nth = i
      break
    end
  end

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

  local target = nth and (statements(after) or {})[nth]
  local sel = target
      and buf:block_at_line(target.lineinfo.first.line)
      or buf:get_content_length()
  buf:set_selection(sel)
  buf:push_history(snap, sel_before, sel)
  self.view:refresh()
  self.view:get_current_buffer():follow_selection()
  self:update_status()
end

--- The Edit key (IS5.1)
local EDIT_KEY = 'f2'
--- blocks a page key browses
local PAGE_BLOCKS = 10

--- The undo timeline (controller.editorReuse) hears of each
--- action twice: _record_action(kind) while the state it
--- takes back is still in place, _action_done(kind) once it
--- has landed. The kinds: 'insert', 'replace', 'empty_line',
--- 'abort', 'begin', 'switch', 'reload'.

--- @private
--- Browse blocks (IS2.1): the draft, its cursor and the
--- replacement target stay as they are (IS2.3)
--- @param dir VerticalDir
--- @param by integer?
function EditorController:_browse(dir, by)
  local buf = self:get_active_buffer()
  --- a block taller than the view scrolls by a row first
  --- (IS2.2)
  local bv = self.view:get_current_buffer()
  if not by and bv:scroll_block(dir) then return end
  local moved = false
  for _ = 1, by or 1 do
    if not buf:move_selection(dir) then break end
    moved = true
  end
  if moved then
    self.view:get_current_buffer():follow_selection()
    self:update_status()
  end
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
--- A block's text as Edit loads it: Lua formatted as a
--- submission formats it, as far as the formatter can, so a
--- line over the limit may come back within it (ruling: F2
--- opens a block that breaks a limit); as it stands when it
--- does not format, and in a text or Markdown file. Loading
--- is no change to the draft (IS5.6).
--- @param lines string[]
--- @return string[]
function EditorController:_as_loaded(lines)
  if self:get_active_buffer().content_type ~= 'lua' then
    return lines
  end
  return (lua.formatted(lines,
    self.model.cfg.view.drawableChars, true))
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
--- own, for a Lua file
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
  --- a draft of empty lines alone is not empty: each of its
  --- lines becomes an empty-line block (IS3.7)
  local is_lua = buf.content_type == 'lua'
  local draft = self.input:get_text()
  --- one line of spaces alone is an empty Lua draft too
  --- (IS4.3); text keeps its spaces as written (IS8.2)
  local blank = is_lua and #draft == 1
      and not string.is_non_empty_string_array(draft)
  if blank or self:_draft_is_empty() then
    return self:_land({ '' },
      buf.loaded and 'replace' or 'empty_line',
      is_lua and 1 or nil)
  end
  local kind = buf.loaded and 'replace' or 'insert'
  return self:_handle_submit(function(newtext, verdict)
    if self:_reject_oversized(verdict) then return false end
    return self:_land(BufferModel.lines_of(newtext), kind,
      is_lua and #newtext or nil)
  end)
end

--- @private
--- @param k string
--- @return boolean handled --- a browsing key
function EditorController:_browse_keys(k)
  if Key.alt() or Key.shift() then return false end
  local vertical = k == 'up' or k == 'down'
  if vertical and (Key.ctrl() or self:_draft_is_empty()) then
    self:_browse(k)
    return true
  end
  if Key.ctrl() then return false end
  if k == 'pageup' or k == 'pagedown' then
    self:_browse(k == 'pageup' and 'up' or 'down', PAGE_BLOCKS)
    return true
  end
  return false
end

--- Alt with a page or edge key moves the document view and
--- nothing else: the browsing position, the draft and the
--- replacement target stay. Alt+Left and Alt+Right page too:
--- PgUp and PgDn are four-key chords on the device keyboard.
local PEEKS = {
  pageup = { 'up' },
  left = { 'up' },
  pagedown = { 'down' },
  right = { 'down' },
  home = { 'up', true },
  ['end'] = { 'down', true },
}

--- @private
--- @param k string
--- @return boolean handled --- a peek key
function EditorController:_peek_keys(k)
  local peek = PEEKS[k]
  local alt_alone = Key.alt() and not Key.ctrl()
      and not Key.shift()
  if not (peek and alt_alone) then return false end
  self.view:get_current_buffer():scroll(peek[1], nil, peek[2])
  self:update_status()
  return true
end

--- @private
--- The keys of the browsing, inserting and replacing states
--- @param k string
--- @param isrepeat boolean?
function EditorController:_normal_mode_keys(k, isrepeat)
  local bare = not Key.ctrl() and not Key.alt()
      and not Key.shift()
  if self:_reuse_keys(k, isrepeat) then return end
  if Key.is_enter(k) then
    if bare then
      self:submit()
      return
    end
    --- Shift+Enter and Alt+Enter break a line in the field
    --- (IS3.15); no other Enter reaches the widget's submit
    if Key.ctrl() then return end
  end
  if bare and k == 'escape' then
    if self:state_name() == 'browsing' then
      --- stepping back from a file (IS1.6)
      self:close_buffer()
    else
      self:cancel_edit()
    end
    return
  end
  --- no other Escape reaches the widget's cancel
  if k == 'escape' then return end
  if bare and k == EDIT_KEY then
    self:edit_block()
    return
  end
  if self:_browse_keys(k) then return end
  if self:_peek_keys(k) then return end
  if Key.ctrl() and not Key.alt() and k == 'j' then
    self:follow_require()
    return
  end
  self.input:keypressed(k)
end

--- @param k string
--- @param _ string? --- LÖVE's scancode, unused
--- @param isrepeat boolean? --- the key is held
function EditorController:keypressed(k, _, isrepeat)
  --- a held key repeats only if it changes nothing beyond
  --- the draft and the view (HeldKeys), and only where its
  --- press acted: one held since before the editor came to
  --- the front, a program's, does nothing in it
  local repeats = self.pressed[k] and HeldKeys.editor(k)
  if isrepeat and not repeats then return end
  if self:_held_back(k) then return end
  self.pressed[k] = true
  --- its press brings up the card (KeyCard.shows)
  if k == KeyCard.KEY then return end
  self.input:update_view()

  if Key.ctrl() then
    --- formatting the whole file is a browsing command
    if k == "f" and Key.shift()
        and self:state_name() == 'browsing' then
      self:format_file()
      return
    end
    if self:_leave_keys(k) then return end
  end

  self:_normal_mode_keys(k, isrepeat)

  --- Escape on the last buffer has closed the editor by
  --- now, so the buffer is asked for only on the key
  --- that uses it
  if love.debug and k == 'f5' then
    local buf = self:get_active_buffer()
    local bufview = self.view:get_buffer(buf:get_id())
    if Key.ctrl() then buf:rechunk() end
    bufview:refresh()
  end
end

require("controller.editorReuse")
