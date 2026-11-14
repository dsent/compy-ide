--- Reusing, removing and reordering blocks, and the timeline
--- of undo and redo (editor principles IS6). This file adds
--- methods to EditorController; editorController.lua requires
--- it once the class exists.
---
--- The timeline of one open file is three stores read as one:
---  * the draft's changes, in the input model's edit history
---    (typing, deletion, a copy with Ctrl+Ins);
---  * `buf.history`: every accepted change to the file, put
---    there by `buf:push_history`, and the state steps (an
---    abort, the opening or switch of a replacement), which
---    carry a `kind`;
---  * `buf.redo_history`: what was undone, draft changes
---    included, latest last.
--- Ctrl+Z takes the draft's changes back first and reaches
--- `buf.history` once the draft holds none (IS6.6).

--- the steps of `buf.history` that change no file
local STATE_STEP = { abort = true, open = true, switch = true }

local NOTICE = {
  cut_inserting = 'Finish the text first: Enter adds it,'
      .. ' Esc drops it.',
  replacing = 'Finish editing first: Enter keeps it,'
      .. ' Esc drops it.',
  cut_end = 'End of file: no block to cut here.'
      .. ' Move up onto one.',
  move_end = 'End of file: no block to move here.'
      .. ' Move up onto one.',
  copy_none = 'No block to copy here.'
      .. ' Move onto a block with text first.',
  merge_cut = 'Cutting this would merge its neighbors into'
      .. ' one statement.',
  merge_move = 'Moving this would merge it with a neighbor'
      .. ' into one statement.',
  after_return = 'Lua stops at a return or break;'
      .. ' nothing can follow one.',
}

--- @param buf BufferModel
--- @param i integer
--- @return string[] --- the lines of block `i`, {} when it is
--- an empty line or there is none
local function block_lines(buf, i)
  local b = buf:get_content()[i]
  if not b then return {} end
  if type(b) == 'string' then
    if b == '' then return {} end
    return { b }
  end
  if b.is_empty and b:is_empty() then return {} end
  return table.clone(b.lines or {})
end

--- @param lines string[]
--- @return boolean
local function blank(lines)
  for _, l in ipairs(lines) do
    if l ~= '' then return false end
  end
  return true
end

--- @param text string[]
--- @return boolean --- the field holds no draft
local function no_draft(text)
  return #text == 0 or (#text == 1 and text[1] == '')
end

--- @param list table[]
--- @return table[] --- a new list of the same items
local function copy_list(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  return out
end

------------------
---   field    ---
------------------

--- The editor field as it is: draft, cursor, the draft's
--- undoable changes, and the replacement target
--- @return table
function EditorController:_field_snapshot()
  local im = self.input.model
  local l, c = im:get_cursor_pos()
  return {
    text = table.clone(im:get_text()),
    l = l,
    c = c,
    steps = copy_list(im.edit_history.steps),
    target = self:get_active_buffer().loaded,
  }
end

--- Put the field back as a snapshot holds it
--- @param snap table
function EditorController:_field_restore(snap)
  local buf = self:get_active_buffer()
  local im = self.input.model
  if no_draft(snap.text) then
    self.input:clear()
  else
    self.input:set_text(table.clone(snap.text))
    im:move_cursor(snap.l, snap.c)
  end
  im.edit_history.steps = copy_list(snap.steps)
  if snap.target then
    buf:set_loaded(snap.target)
  else
    buf:clear_loaded()
  end
  self:_reuse_sync()
end

--- Empty the field and leave any replacement: the browsing
--- state
function EditorController:_field_empty()
  self:get_active_buffer():clear_loaded()
  self.input:clear()
  self:_reuse_sync()
end

--- Load block `i` into the field as the replacement of it
--- @param i integer
function EditorController:_field_load_target(i)
  local buf = self:get_active_buffer()
  local lines = block_lines(buf, i)
  buf:set_loaded(i)
  if blank(lines) then
    self.input:clear()
  else
    self.input:set_text(lines)
    self.input.model:move_cursor(#lines,
      string.ulen(lines[#lines]) + 1)
  end
  self:_reuse_sync()
end

--- @private
--- The view and the status line follow the field
function EditorController:_reuse_sync()
  self.input:update_view()
  self:update_status()
end

--- @private
--- Show the file as the buffer now holds it, the browsing
--- position in view
function EditorController:_reuse_show()
  self.view:refresh()
  self.view:get_current_buffer():follow_selection()
  self:update_status()
end

--------------------
---   timeline   ---
--------------------

--- @private
--- A new action drops what could be redone. The draft's own
--- history starts a new redo list on every change to it, so
--- its identity tells whether one happened since the last
--- undo or redo.
--- @param buf BufferModel
function EditorController:_timeline_sync(buf)
  local mark = self.input.model.edit_history.redo_steps
  if buf.redo_mark ~= mark then
    buf.redo_history = {}
  end
end

--- @private
--- @param buf BufferModel
function EditorController:_timeline_mark(buf)
  buf.redo_mark = self.input.model.edit_history.redo_steps
end

--- Record an accepted change to the file: call it after the
--- change is saved. `before` is the file's lines before it
--- (`table.clone(buf:get_text_content())`), `sel_before` the
--- browsing position before it. The same as
--- `buf:push_history(before, after, sel_before, sel_after)`,
--- which stays valid.
--- @param before string[]
--- @param sel_before integer
--- @param extra table? --- fields added to the step
--- @return table? step --- nil when the file did not change
function EditorController:timeline_record(before, sel_before,
                                          extra)
  local buf = self:get_active_buffer()
  local n = #buf.history
  local top = buf.history[n]
  buf:push_history(before,
    table.clone(buf:get_text_content()),
    sel_before, buf:get_selection())
  local step = buf.history[#buf.history]
  if step == top then return nil end
  for k, v in pairs(extra or {}) do step[k] = v end
  return step
end

--- @private
--- @param kind 'abort'|'open'|'switch'
function EditorController:_timeline_state_step(kind)
  local buf = self:get_active_buffer()
  if not buf then return end
  table.insert(buf.history, {
    kind = kind,
    field = self:_field_snapshot(),
  })
  if #buf.history > BLOCK_HISTORY_CAP then
    table.remove(buf.history, 1)
  end
  buf.redo_history = {}
end

--- Call just before Escape drops an edit (IS5.7): one Ctrl+Z
--- brings it back, draft, cursor and target included
function EditorController:timeline_abort()
  self:_timeline_state_step('abort')
end

--- Call just before Edit opens a replacement (IS5.1)
function EditorController:timeline_open()
  self:_timeline_state_step('open')
end

--- Call just before Edit switches the replacement target
--- (IS5.6)
function EditorController:timeline_switch()
  self:_timeline_state_step('switch')
end

--- The timeline goes when the user leaves the file (IS6.6)
--- @param buf BufferModel?
function EditorController:timeline_forget(buf)
  buf = buf or self:get_active_buffer()
  if not buf then return end
  buf.history = {}
  buf.redo_history = {}
  buf.redo_mark = nil
end

--- @private
--- The browsing position an undone or redone change to the
--- file leaves: the block at `line`, or the end position
--- @param buf BufferModel
--- @param line integer
--- @return integer
local function position_at(buf, line)
  return buf:block_at_line(line)
      or buf:get_content_length() + 1
end

--- @private
--- Undo or redo a state step
--- @param step table
--- @param forward boolean
function EditorController:_replay_state(step, forward)
  local buf = self:get_active_buffer()
  local kind = step.kind
  if not forward then
    --- what a redo brings back
    step.to = buf.loaded
    if kind == 'switch' then
      --- the previous target, its text reloaded; the browsing
      --- position stays (IS6.6)
      self:_field_load_target(step.field.target)
    else
      self:_field_restore(step.field)
    end
    return
  end
  if kind == 'abort' then
    self:_field_empty()
  elseif step.to then
    --- as the opening or the switch left it: the browsing
    --- position on the target
    buf:set_selection(step.to)
    self:_field_load_target(step.to)
    self:_reuse_show()
  end
end

--- @private
--- @param buf BufferModel
--- @return string? --- the file's text as the card holds it
function EditorController:_disk_text(buf)
  local con = self.console
  local projects = con and con.model and con.model.projects
  local readable = projects and projects.current
      and con._readfile
  if not readable then return nil end
  local text = con:_readfile(buf.name, true)
  return type(text) == 'string' and text or nil
end

--- @private
--- Called after each successful save: what the card holds
--- now is what the timeline's latest action left
--- @param buf BufferModel
function EditorController:_note_saved(buf)
  buf.disk_seen = self:_disk_text(buf)
end

--- @private
--- @param buf BufferModel
--- @return boolean --- the file is as the editor's last save
--- left it; true as well when it cannot be read
function EditorController:_file_matches(buf)
  if buf.unsaved then return true end
  local now = self:_disk_text(buf)
  if buf.disk_seen == nil then
    --- no baseline yet: the file as it stands is one
    buf.disk_seen = now
    return true
  end
  return now == buf.disk_seen
end

--- @private
--- The notice of a write that failed: the file, the reason,
--- and what did not happen
--- @param outcome string
--- @return string
function EditorController:_unsaved_notice(outcome)
  local f = self.save_failure or {}
  local name = f.name or self:get_active_buffer().name
  local has_reason = type(f.reason) == 'string'
      and f.reason ~= ''
  local reason = has_reason
      and string.format(' (%s)', f.reason) or ''
  return string.format('Could not save %s%s. %s',
    name, reason, outcome)
end

--- @private
--- A file changed from outside ends every action on its
--- timeline, the draft's changes included: none matches the
--- file any more, and the key does nothing (IS6.6). Actions
--- from now on are measured against the file as it stands.
--- @param buf BufferModel
--- @return boolean outdated
function EditorController:_timeline_outdated(buf)
  --- once ended, new changes to the draft and aborts undo
  --- again; none of them writes the file
  if buf.outdated then return false end
  if self:_file_matches(buf) then return false end
  buf.outdated = true
  --- the baseline stays: the buffer still holds the text
  --- from before the change, so every later write is
  --- refused until the file is opened again
  self:timeline_forget(buf)
  self.input.model.edit_history:reset()
  return true
end

--- @private
--- Undo or redo a change to the file
--- @param step table
--- @param forward boolean
--- @return boolean done
function EditorController:_replay_file(step, forward)
  local buf = self:get_active_buffer()
  if not self:_file_matches(buf) then
    --- changed from outside: no action matches the file any
    --- more, so they all go and the key does nothing (IS6.6)
    self:timeline_forget(buf)
    return false
  end
  local found = self:_field_snapshot()
  local was_unsaved = buf.unsaved
  --- the action undone just before this one
  local later = buf.redo_history[#buf.redo_history]
  if forward then buf:redo() else buf:undo() end
  if not self:save(buf) then
    --- the file is as it was: so is the buffer, and it is
    --- as unsaved as before, so that the next undo still
    --- reads the file for a change from outside
    if forward then buf:undo() else buf:redo() end
    buf:analyze()
    buf.unsaved = was_unsaved
    self.view:refresh()
    self:refuse({ self:_unsaved_notice(
      forward and 'Nothing redone.' or 'Nothing undone.') })
    return false
  end
  local last = buf:get_content_length() + 1
  if forward then
    local pos = step.pos_done or step.sel_after
    buf:set_selection(math.min(pos, last))
    if step.field then
      self:_field_restore(step.field)
    else
      buf:clear_loaded()
      self:_reuse_sync()
    end
  else
    --- the first restored block, or where the removed ones
    --- stood (IS6.6)
    local pos = step.pos_undone
    if not pos and #step.removed == 0 then
      --- an insertion: where it went in
      pos = step.sel_before
    end
    pos = pos or position_at(buf, step.start)
    buf:set_selection(math.min(pos, last))
    local both_moves = step.kind == 'move' and later
        and later.kind == 'move' and later.field
    if both_moves and no_draft(found.text) then
      --- the undo of the later move emptied the field: this
      --- move left the field that one found
      found = later.field
    end
    if step.kind == 'move' or not step.field then
      --- a redo brings back the field this undo found: after
      --- a move, the draft the move left alone
      step.field = {
        text = found.text,
        l = found.l,
        c = found.c,
        steps = {},
      }
    end
    if step.field_before then
      --- the field as the action found it, empty, with the
      --- draft changes that came before the action
      self:_field_restore(step.field_before)
    else
      self:_field_empty()
    end
  end
  self:_reuse_show()
  return true
end

--- Ctrl+Z: undo the latest action that can still be undone
--- (IS6.6). A held key repeats only through the draft's
--- changes.
--- @param isrepeat boolean?
function EditorController:timeline_undo(isrepeat)
  local buf = self:get_active_buffer()
  local im = self.input.model
  if self:_timeline_outdated(buf) then return end
  self:_timeline_sync(buf)
  if #im.edit_history.steps > 0 then
    local found = self:_field_snapshot()
    im:undo_edit()
    table.insert(buf.redo_history,
      { kind = 'draft', field = found })
    self:_timeline_mark(buf)
    self:_reuse_sync()
    return
  end
  if isrepeat then return end
  local n = #buf.history
  local step = buf.history[n]
  if not step then return end
  if STATE_STEP[step.kind] then
    table.remove(buf.history, n)
    self:_replay_state(step, false)
    table.insert(buf.redo_history, step)
  else
    self:_replay_file(step, false)
  end
  self:_timeline_mark(buf)
end

--- Ctrl+Y: redo the latest undone action (IS6.6)
--- @param isrepeat boolean?
function EditorController:timeline_redo(isrepeat)
  local buf = self:get_active_buffer()
  if self:_timeline_outdated(buf) then return end
  self:_timeline_sync(buf)
  local n = #buf.redo_history
  local step = buf.redo_history[n]
  if not step then return end
  if step.kind == 'draft' then
    table.remove(buf.redo_history, n)
    self:_field_restore(step.field)
  elseif isrepeat then
    return
  elseif STATE_STEP[step.kind] then
    table.remove(buf.redo_history, n)
    self:_replay_state(step, true)
    table.insert(buf.history, step)
  else
    self:_replay_file(step, true)
  end
  self:_timeline_mark(buf)
end

-----------------
---   reuse   ---
-----------------

--- @private
--- @return 'browsing'|'inserting'|'replacing'
function EditorController:_reuse_state()
  if self:get_active_buffer().loaded then return 'replacing' end
  if self.input:is_empty() then return 'browsing' end
  return 'inserting'
end

--- @private
--- A Lua file stays one chunk whose blocks read as they
--- stand (IS3.7): a cut or a move that would stop the file
--- loading, or join two blocks into one statement, is
--- refused. A file that did not load before is exempt, so
--- that it can be repaired.
--- @param ran boolean --- the file loaded before the change
--- @param count integer --- the blocks it should hold now
--- @param joined string --- the notice for a merge
--- @return string? why
function EditorController:_reuse_refusal(ran, count, joined)
  local buf = self:get_active_buffer()
  if not ran or buf.content_type ~= 'lua' then return nil end
  local loads, err = buf:loads()
  if not loads then
    --- Lua reads a line starting with `(` as a call of the
    --- line before it, and says so
    local joins = tostring(err):find('ambiguous', 1, true)
    return joins and joined or NOTICE.after_return
  end
  if buf:get_content_length() ~= count then return joined end
  return nil
end

--- @private
--- The buffer goes back to what the file holds, and the
--- change is refused
--- @param back table --- {before, sel, was_unsaved}
--- @param why string
function EditorController:_reuse_put_back(back, why)
  local buf = self:get_active_buffer()
  buf:replace_text(back.before)
  buf:_text_change()
  buf:analyze()
  buf:set_selection(back.sel)
  buf.unsaved = back.was_unsaved
  self.view:refresh()
  self:refuse({ why })
end

--- Ctrl+Ins: the block at the browsing position goes into the
--- draft at the cursor, on lines of its own (IS6.1)
function EditorController:copy_block()
  local buf = self:get_active_buffer()
  local lines = block_lines(buf, buf:get_selection())
  if blank(lines) then
    return self:refuse({ NOTICE.copy_none })
  end
  local im = self.input.model
  local text = table.clone(im:get_text())
  local l, c = im:get_cursor_pos()
  local line = text[l] or ''
  local pre = string.usub(line, 1, c - 1)
  local post = string.usub(line, c)
  local out = {}
  for i = 1, l - 1 do out[#out + 1] = text[i] end
  if pre ~= '' then out[#out + 1] = pre end
  for _, bl in ipairs(lines) do out[#out + 1] = bl end
  local cl = #out
  if post ~= '' then out[#out + 1] = post end
  for i = l + 1, #text do out[#out + 1] = text[i] end
  --- one change to the draft, undone by one Ctrl+Z
  im:reformat(out)
  im:move_cursor(cl, string.ulen(out[cl]) + 1)
  im:_note_edit()
  self:_reuse_sync()
end

--- Ctrl+Delete: the block at the browsing position leaves
--- the file, its text in the field (IS6.2)
--- @param isrepeat boolean? --- a held key stops, without a
--- notice, at the first block it cuts into the field
function EditorController:cut_block(isrepeat)
  local buf = self:get_active_buffer()
  local state = self:_reuse_state()
  if isrepeat and state ~= 'browsing' then return end
  if state == 'inserting' then
    return self:refuse({ NOTICE.cut_inserting })
  end
  if state == 'replacing' then
    return self:refuse({ NOTICE.replacing })
  end
  local sel = buf:get_selection()
  if sel > buf:get_content_length() then
    --- a held key that ran out of empty lines stops quietly
    if isrepeat then return end
    return self:refuse({ NOTICE.cut_end })
  end
  if self:_refuse_stale(buf) then return end
  local lines = block_lines(buf, sel)
  local before = table.clone(buf:get_text_content())
  local back = {
    before = before,
    sel = sel,
    was_unsaved = buf.unsaved,
  }
  local ran, count = buf:loads(), buf:get_content_length()
  --- empty, with the changes typed and deleted there
  local field_before = self:_field_snapshot()
  buf:delete_selected_text()
  local why = self:_reuse_refusal(ran, count - 1,
    NOTICE.merge_cut)
  if why then return self:_reuse_put_back(back, why) end
  if not self:save(buf) then
    return self:_reuse_put_back(back,
      self:_unsaved_notice('Nothing cut.'))
  end
  --- the next block took the cut one's number; past the last
  --- block it is the end position
  buf:set_selection(sel)
  if blank(lines) then
    --- the field stays empty; what was typed and deleted
    --- there before is no longer a change to undo
    self.input:clear()
  else
    self.input:set_text(lines)
    self.input.model:move_cursor(#lines,
      string.ulen(lines[#lines]) + 1)
  end
  self:_reuse_sync()
  --- undoing the cut restores the block as an insertion
  --- would (IS6.3)
  self:timeline_record(before, sel, {
    kind = 'cut',
    pos_undone = sel + 1,
    pos_done = sel,
    field = self:_field_snapshot(),
    field_before = field_before,
  })
  self:_reuse_show()
end

--- Alt+Up, Alt+Down: the block at the browsing position moves
--- past its neighbor, the highlight with it (IS6.5)
--- @param dir VerticalDir
function EditorController:move_block(dir)
  local buf = self:get_active_buffer()
  if self:_reuse_state() == 'replacing' then
    return self:refuse({ NOTICE.replacing })
  end
  local n = buf:get_content_length()
  local i = buf:get_selection()
  if i > n then
    return self:refuse({ NOTICE.move_end })
  end
  local to = dir == 'up' and i - 1 or i + 1
  --- toward the edge, nothing changes
  if to < 1 or to > n then return end
  if self:_refuse_stale(buf) then return end
  local before = table.clone(buf:get_text_content())
  local back = {
    before = before,
    sel = i,
    was_unsaved = buf.unsaved,
  }
  local ran = buf:loads()
  buf:move(i, to)
  local why = self:_reuse_refusal(ran, n, NOTICE.merge_move)
  if why then return self:_reuse_put_back(back, why) end
  if not self:save(buf) then
    return self:_reuse_put_back(back,
      self:_unsaved_notice('Nothing moved.'))
  end
  buf:set_selection(to)
  self:timeline_record(before, i, {
    kind = 'move',
    pos_undone = i,
    pos_done = to,
  })
  self:_reuse_show()
end

--- Shift+Ins: submit as Enter does and keep the draft in the
--- field, in the inserting state (IS6.4)
function EditorController:submit_and_retain()
  local buf = self:get_active_buffer()
  local im = self.input.model
  local had = {}
  for _, st in ipairs(buf.history) do had[st] = true end
  local kept = self:_field_snapshot()
  if not self:submit() then return end
  if no_draft(kept.text) then return end
  --- the draft as accepted: formatted where it formats; the
  --- cursor keeps its place as far as the text allows (IS3.9)
  local text = buf.printer and buf.printer(kept.text)
  if not text or blank(text) then
    --- a draft of empty lines stays as it is
    text = kept.text
  end
  buf:clear_loaded()
  self.input:set_text(table.clone(text))
  --- the cursor follows the text element it stood at
  local l, c = require('model.lang.lua.cursor_map').cursor(
    kept.text, text, kept.l, kept.c)
  im:move_cursor(l, c)
  self:_reuse_sync()
  local step = buf.history[#buf.history]
  if step and not had[step] then
    --- a redo leaves the editor as the action did
    step.field = self:_field_snapshot()
  end
end

--- @private
--- The hook of the state machine: an action is about to
--- happen, the state it takes back still in place
--- @param kind string
function EditorController:_record_action(kind)
  if kind == 'abort' then
    self:timeline_abort()
  elseif kind == 'begin' then
    self:timeline_open()
  elseif kind == 'switch' then
    self:timeline_switch()
  elseif kind == 'replace' then
    local buf = self:get_active_buffer()
    local h = buf.history
    self._top_before = h[#h]
    self._replaced = buf.loaded
  end
end

--- @private
--- The hook of the state machine: the action is done. An
--- accepted replacement takes the place of its edit's steps
--- on the timeline, the opening and the switches, so that
--- undoing it never reaches into the edit (IS6.6).
--- @param kind string
function EditorController:_action_done(kind)
  if kind ~= 'replace' then return end
  local h = self:get_active_buffer().history
  local accepted
  if h[#h] ~= self._top_before then
    accepted = table.remove(h)
    --- undone, the position is on the restored block
    accepted.pos_undone = self._replaced
  end
  self._top_before, self._replaced = nil, nil
  while h[#h] and h[#h].kind == 'switch' do
    table.remove(h)
  end
  if h[#h] and h[#h].kind == 'open' then
    table.remove(h)
  end
  h[#h + 1] = accepted
end

--- @private
--- The keys of IS6. Called from keypressed before the mode's
--- own keys.
--- @param k string
--- @param isrepeat boolean?
--- @return boolean handled
function EditorController:_reuse_keys(k, isrepeat)
  if isrepeat == nil then isrepeat = self.key_repeat end
  local buf = self:get_active_buffer()
  if buf and buf.disk_seen == nil and not buf.unsaved then
    --- what the file holds before the first action on it
    buf.disk_seen = self:_disk_text(buf)
  end
  --- every change to a draft stays undoable, so that Ctrl+Z
  --- reaches the file only once the draft holds none
  local eh = self.input.model.edit_history
  if eh.cap < 1000 then eh.cap = 1000 end
  --- coming back to a file (IS1.5, IS1.6) empties the field,
  --- which is no new action on it: what could be redone
  --- there still can, until the draft changes
  local came_back = buf and self._timeline_buf ~= buf
  if came_back then
    self._timeline_buf = buf
    if #eh.steps == 0 then self:_timeline_mark(buf) end
  end
  if self.mode ~= 'nav' then return false end
  local ctrl, shift, alt = Key.ctrl(), Key.shift(), Key.alt()
  if ctrl and not shift and not alt then
    if k == 'z' then
      self:timeline_undo(isrepeat)
      return true
    end
    if k == 'y' then
      self:timeline_redo(isrepeat)
      return true
    end
    if k == 'insert' then
      self:copy_block()
      return true
    end
    if k == 'delete' then
      self:cut_block(isrepeat)
      return true
    end
  end
  if alt and not ctrl and not shift then
    if k == 'up' or k == 'down' then
      --- one move per press: a held key would push the
      --- timeline's older steps out, a step per repeat
      if not isrepeat then self:move_block(k) end
      return true
    end
  end
  if shift and not ctrl and not alt and k == 'insert' then
    if not isrepeat then self:submit_and_retain() end
    return true
  end
  --- Shift+Delete cuts as well, in the browsing state only:
  --- the spec names Ctrl+Delete alone, and with a draft the
  --- key stays the field's Delete
  if shift and not ctrl and not alt and k == 'delete'
      and self:_reuse_state() == 'browsing' then
    self:cut_block(isrepeat)
    return true
  end
  return false
end
