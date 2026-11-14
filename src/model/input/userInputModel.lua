require("model.input.inputText")
require("model.input.selection")
require("model.input.history")
require("model.input.editHistory")
require("model.lang.lua.error")
require("view.editor.visibleContent")

local class = require('util.class')
local cursor_map = require('model.input.cursorMap')
require("util.wrapped_text")
require("util.dequeue")
require("util.string.string")
require("util.debug")
require("util.lua")

--- @class UserInputModel
--- @field entered InputText
--- @field history History
--- @field edit_history EditHistory
--- @field evaluator Evaluator
--- @field cursor Cursor
--- @field error string[]?
--- @field visible VisibleContent
--- @field selection InputSelection
--- @field cfg Config
--- @field custom_status CustomStatus?
--- @field custom_label PromptLabel?
--- @field _memo table
--- methods
--- @field new function
--- @field get_label fun(self): PromptLabel?
--- @field init_visible function
--- @field add_text fun(self, string)
--- @field set_text fun(self, string, boolean)
--- @field line_feed fun(self)
--- @field get_text fun(self): InputText
--- @field get_text_line fun(self, integer): string
--- @field get_n_text_lines fun(self): integer
--- @field get_wrapped_text fun(self): VisibleContent
--- @field get_wrapped_error fun(self): string[]?
--- @field swap_lines function
UserInputModel = class.create()


--- @param cfg Config
--- @param eval Evaluator
--- @param custom_label PromptLabel?
--- @param editing boolean? --- the file editor's field: its
--- height (half the rows it shares with the document view),
--- Up on its first row and Down on its last going to the
--- draft's ends (IS3.8), and a notice that blocks no key. The
--- keys are every field's (fieldKeys.lua).
function UserInputModel.new(cfg, eval, custom_label, editing)
  local self = setmetatable({
    editing = editing or false,
    entered = InputText(),
    history = History(cfg.input_history),
    edit_history = EditHistory(),
    evaluator = eval,
    cursor = Cursor(),
    selection = InputSelection(),
    custom_status = nil,
    custom_label = custom_label,
    --- @private
    _memo = {},

    cfg = cfg,
  }, UserInputModel)

  UserInputModel.init_visible(self, { '' })

  return self
end

--- @return PromptLabel?
function UserInputModel:get_label()
  local cl = self.custom_label
  if cl then return cl end

  local eval = self.evaluator
  if eval and eval.label then return eval.label end
end

--- @param text string[]
function UserInputModel:init_visible(text)
  local w = self.cfg.view.drawableChars
  local s = self.cfg.view.input_max
  if self.editing then
    --- the editor field takes at most half the rows it
    --- shares with the document view (IS3.13)
    s = math.floor((self.cfg.view.lines + 1) / 2)
  end
  self.visible = VisibleContent(w, text, 1, s)
  self.visible:set_default_range()
end

--- Drop bytes that do not form valid UTF-8
--- @param s string
--- @return string
local function sanitize_utf8(s)
  local r = s
  local n, pos = utf8.len(r)
  while not n do
    r = string.sub(r, 1, pos - 1) .. string.sub(r, pos + 1)
    n, pos = utf8.len(r)
  end
  return r
end

--- Text as it enters a field: valid UTF-8, its line breaks
--- each a newline, whichever spelling it came with (CRLF, or
--- a lone CR, as a program may pass), so that no line of a
--- draft holds a carriage return
--- @param s string
--- @return string
local function entered_text(s)
  return (sanitize_utf8(s):gsub('\r\n?', '\n'))
end

----------------
--  entered   --
----------------

--- @param text string
--- @private
--- @return table --- {text, cursor} for the edit history
function UserInputModel:_edit_snapshot()
  local cl, cc = self:get_cursor_pos()
  return {
    text = table.clone(self:get_text()),
    cursor = { l = cl, c = cc },
  }
end

--- @private
--- Record the pre-mutation state in the edit history
--- @param kind string
--- @param boundary boolean?
function UserInputModel:_record_edit(kind, boundary)
  self.edit_history:record(
    self:_edit_snapshot(), kind, boundary or false)
end

--- @private
--- Remember where the mutation left the cursor
function UserInputModel:_note_edit()
  local cl, cc = self:get_cursor_pos()
  self.edit_history:note_cursor(cl, cc)
end

--- Undo one edit step inside the open block (1.1)
--- @return boolean --- false when there is nothing to undo
function UserInputModel:undo_edit()
  local snap = self.edit_history:undo(self:_edit_snapshot())
  if not snap then return false end
  self:_apply_edit_snapshot(snap)
  return true
end

--- Redo one edit step
--- @return boolean --- false when there is nothing to redo
function UserInputModel:redo_edit()
  local snap = self.edit_history:redo(self:_edit_snapshot())
  if not snap then return false end
  self:_apply_edit_snapshot(snap)
  return true
end

--- @private
--- @param snap table
function UserInputModel:_apply_edit_snapshot(snap)
  self.entered = InputText(table.clone(snap.text))
  self:text_change()
  self:move_cursor(snap.cursor.l, snap.cursor.c)
  self:clear_selection()
end

function UserInputModel:add_text(text)
  if type(text) == 'string' then
    text = entered_text(text)
    --- nothing to add: no step (IS6.6)
    if text == '' then return end
    local single = string.ulen(text) == 1
    if single then
      --- a whitespace starts a new step, so undo eats
      --- word by word, not letter by letter
      self:_record_edit('insert',
        string.match(text, '^%s$') ~= nil)
    else
      self:_record_edit('text', true)
    end
    self:pop_selected_text()
    local sl, cc    = self:get_cursor_pos()
    local cur_line  = self:get_text_line(sl)
    local pre, post = string.split_at(cur_line, cc)
    local lines     = string.lines(text)
    local n_added   = #lines
    if n_added == 1 then
      local nval = string.interleave(pre, text, post)
      self:_set_text_line(nval, sl, true)
      self:_advance_cursor(string.ulen(text))
    else
      local ent = self.entered
      local ins = table.clone(lines)
      local fl = ins[1]
      local ll = ins[n_added]
      ins[1] = pre .. fl
      ins[n_added] = ll .. post

      for k = n_added, 1, -1 do
        local line = ins[k]

        if k == 1 then
          ent:update(line, sl)
        else
          ent:insert(line, sl + 1)
        end
      end
      local last_line_i = sl + n_added - 1
      self:move_cursor(last_line_i, string.ulen(ll) + 1)
    end
    self:text_change()
    self:_note_edit()
  end
end

--- Normalise either spelling of the content shape -- a string,
--- or a list of line strings -- to one list of lines, so the
--- caller has a single path. Sanitise for UTF-8 and the line
--- breaks (entered_text), then split on newlines;
--- string.lines takes either spelling, and over a
--- list it keeps empty elements, so a blank line survives.
--- Anything else yields nil, which leaves content standing.
--- @param text str
--- @return string[]?
local function normalized_lines(text)
  if type(text) == 'string' then
    return string.lines(entered_text(text))
  end
  if type(text) ~= 'table' then return end
  local clean = {}
  for i, l in ipairs(text) do
    clean[i] = entered_text(l)
  end
  return string.lines(clean)
end

--- @param a string[]
--- @param b string[]
--- @return boolean --- the same lines
local function same_lines(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

--- The draft canonically formatted, as one change to it: what
--- was typed before stays undoable, and the cursor keeps its
--- line and column as far as the new text allows.
--- @param text str
function UserInputModel:reformat(text)
  local lines = normalized_lines(text)
  if not lines then return end
  --- the same text is no change, and no step (IS6.6)
  if same_lines(lines, self:get_text()) then return end
  self:_record_edit('format', true)
  --- the cursor follows the text element it stood at (IS3.9)
  local cl, cc = self:get_cursor_pos()
  local nl, nc = cursor_map.cursor(self:get_text(), lines, cl, cc)
  self.entered = InputText(lines)
  self:set_cursor(Cursor(nl, nc))
  self:text_change()
  self:_clamp_cursor_pos()
  self:_follow_cursor()
  self:_note_edit()
end

--- Continue the draft on a new line (IS3.5): a line break
--- after its last character, the cursor after the break,
--- wherever it stood.
function UserInputModel:continue_line()
  self:_record_edit('newline', true)
  self:clear_selection()
  local n = self:get_n_text_lines()
  self:insert_text_line('', n + 1)
  self:move_cursor(n + 1, 1)
  self:text_change()
  self:_note_edit()
end

--- Remove the text from the cursor to the end of its line,
--- the line break excluded (IS3.12, Ctrl+K).
function UserInputModel:kill_to_line_end()
  local cl, cc = self:get_cursor_pos()
  local line = self:get_text_line(cl)
  if cc > string.ulen(line) then return end
  self:_record_edit('remove_line', true)
  self:clear_selection()
  self:_set_text_line(string.usub(line, 1, cc - 1), cl, true)
  self:text_change()
  self:_note_edit()
end

--- Both spellings normalise identically, so the cursor's
--- (line, column) address is unambiguous over whatever is
--- stored (doc/development/decisions/input.md, D-CONTENT-NORM).
--- @param text str
--- @param keep_cursor boolean
function UserInputModel:set_text(text, keep_cursor)
  --- programmatic content is a new baseline: the text
  --- level lives only inside one edit block (#45, spec 1.1)
  self.edit_history:reset()
  local lines = normalized_lines(text)
  if lines then
    self.entered = InputText(lines)
  end
  self:text_change()
  if keep_cursor then
    self:_clamp_cursor_pos()
    return
  end
  self:init_visible(self.entered)
  self:jump_end()
end

--- @private
--- @param text str
--- @param ln integer
--- @param keep_cursor boolean
function UserInputModel:_set_text_line(text, ln, keep_cursor)
  if type(text) == 'string' then
    local ent = self:get_text()
    if ent then
      local l = self:get_n_text_lines()
      if ln > l then
        ent:append(text)
      else
        ent:update(text, ln)
      end
      if not keep_cursor then
        self:_update_cursor(true)
      end
    elseif type(text) == 'table' and ln == 1 then
      self.entered = InputText(text)
    end
  end
end

--- @private
--- @param ln integer
function UserInputModel:_drop_text_line(ln)
  self:get_text():remove(ln)
  self:text_change()
end

--- @param text string
--- @param li integer?
function UserInputModel:insert_text_line(text, li)
  local l = li or self:get_cursor_y()
  self.cursor.l = l + 1
  self:get_text():insert(text, l)
  self:text_change()
end

--- The cursor's line swaps with the one above or below it,
--- the cursor going with it at its column (Alt+Up,
--- Alt+Down): one change to the draft, whose step holds the
--- field as the key found it. At the first or the last line
--- nothing moves.
--- @param dir VerticalDir
function UserInputModel:move_line(dir)
  local cl = self:get_cursor_y()
  local to = dir == 'up' and cl - 1 or cl + 1
  if to < 1 or to > self:get_n_text_lines() then return end
  self:swap_lines(to, cl)
end

--- Swap to lines of text, second param defaults to cursor line
--- @param ln_that integer
--- @param ln_this integer?
--- @return boolean success
function UserInputModel:swap_lines(ln_that, ln_this)
  if not ln_that then return false end

  if self:has_selection() then
    return false
  else
    local ln_this = ln_this or self:get_cursor_y()
    local this = self:get_text_line(ln_this)
    local that = self:get_text_line(ln_that)

    local n = self:get_n_text_lines()
    if n < 2 then return true end
    if ln_this > n or ln_that > n or
        ln_this < 1 or ln_that < 1 then
      return false
    end
    --- one change to the draft, unless the lines are the same
    if this ~= that then self:_record_edit('swap', true) end

    self:_set_text_line(that, ln_this, true)
    self:_set_text_line(this, ln_that, true)
    self:set_cursor(Cursor(ln_that, self:get_cursor_x()))
    self:text_change()
    self:_note_edit()
    return true
  end
end

function UserInputModel:line_feed()
  self:_record_edit('newline', true)
  local cl, cc = self:get_cursor_pos()
  local cur_line = self:get_text_line(cl)
  local pre, post = string.split_at(cur_line, cc)
  self:_set_text_line(pre, cl, true)
  self:insert_text_line(post, cl + 1)
  self:move_cursor(cl + 1, 1)
  self:text_change()
  self:_note_edit()
end

--- @return InputText
function UserInputModel:get_text()
  return self.entered or InputText()
end

--- @param l integer
--- @return string
function UserInputModel:get_text_line(l)
  local ent = self:get_text()
  return ent:get(l) or ''
end

--- @return integer
function UserInputModel:get_n_text_lines()
  local ent = self:get_text()
  return ent:length()
end

--- @return VisibleContent
function UserInputModel:get_wrapped_text()
  return self.visible
end

--- @param l integer
--- @return string
function UserInputModel:get_wrapped_text_line(l)
  return self:get_wrapped_text():get_line(l)
end

--- @return string
function UserInputModel:get_current_line()
  local cl = self:get_cursor_y() or 1
  return self:get_text():get(cl)
end

function UserInputModel:backspace()
  --- nothing before the cursor and nothing selected: no
  --- change, and no step (IS6.6)
  local l0, c0 = self:get_cursor_pos()
  if l0 == 1 and c0 == 1 and not self:has_selection() then
    return
  end
  self:_record_edit('remove')
  self:pop_selected_text()
  local line = self:get_current_line()
  local cl, cc = self:get_cursor_pos()
  local newcl = cl - 1
  local pre, post

  if cc == 1 then
    if cl == 1 then -- can't delete nothing
      return
    end
    -- line merge
    pre = self:get_text_line(newcl) or ''
    local pre_len = string.ulen(pre)
    post = line or ''
    local nval = pre .. post
    self:_set_text_line(nval, newcl, true)
    self:move_cursor(newcl, pre_len + 1)
    self:_drop_text_line(cl)
  else
    -- regular merge
    pre = string.usub(line, 1, cc - 2)
    post = string.usub(line, cc)
    local nval = pre .. post
    self:_set_text_line(nval, cl, true)
    self:cursor_left()
  end
  self:text_change()
  self:_note_edit()
end

--- Ctrl+Backspace, Alt+Backspace and Ctrl+W: delete exactly
--- what Ctrl+Left moves over (IS3.8), as one change: one word
--- splitting for both (the maintainer's ruling of November
--- 14, 2026). At a line's start that is the line break and the
--- previous line's last word; at the draft's start, nothing.
function UserInputModel:backspace_word()
  local l, c = self:get_cursor_pos()
  local tl, tc = self:_word_left_of(l, c)
  if tl == l and tc == c then return end
  self:_record_edit('remove_word', true)
  self:clear_selection()
  local lines = { }
  for i = 1, tl - 1 do lines[i] = self:get_text_line(i) end
  lines[tl] = string.usub(self:get_text_line(tl), 1, tc - 1)
      .. string.usub(self:get_text_line(l), c)
  for i = l + 1, self:get_n_text_lines() do
    lines[#lines + 1] = self:get_text_line(i)
  end
  self.entered = InputText(lines)
  self:text_change()
  self:move_cursor(tl, tc)
  self:_note_edit()
end

function UserInputModel:delete()
  --- nothing after the cursor and nothing selected: no
  --- change, and no step (IS6.6)
  local l0, c0 = self:get_cursor_pos()
  local last = string.ulen(self:get_current_line() or '') + 1
  if l0 == self:get_n_text_lines() and c0 == last
      and not self:has_selection() then
    return
  end
  self:_record_edit('remove')
  self:pop_selected_text()
  local line = self:get_current_line()
  local cl, cc = self:get_cursor_pos()
  local pre, post

  local n = self:get_n_text_lines()

  local llen = string.ulen(line)
  if cc == llen + 1 then
    if cl == n then
      return
    end
    -- line merge
    post = self:get_text_line(cl + 1)
    pre = line
    self:_drop_text_line(cl + 1)
  else
    -- regular merge
    pre = string.usub(line, 1, cc - 1)
    post = string.usub(line, cc + 1)
  end
  local nval = (pre or '') .. (post or '')
  self:_set_text_line(nval, cl, true)
  self:text_change()
  self:_note_edit()
end

function UserInputModel:clear_input()
  --- the text level lives only inside one edit block
  --- (#45, spec 1.1): clearing ends the block, and its
  --- undo with it
  self.edit_history:reset()
  self.entered = InputText()
  self:text_change()
  self:clear_selection()
  self:_update_cursor(true)
  self.custom_status = nil
  self.history:reset_index()
end

--- @param history boolean?
function UserInputModel:reset(history)
  if history and self:keep_history() then
    self.history = History(self.cfg.input_history)
  end
  self:clear_input()
end

function UserInputModel:text_change()
  self.visible:wrap(self.entered)
  self.visible:check_range()
  self:_follow_cursor()
  local ev = self.evaluator
  if ev then
    self:highlight()
  end
end

function UserInputModel:highlight()
  local ev = self.evaluator
  if not ev then return end
  local text = self:get_text()

  local p = ev.parser
  if p then
    local ok, p_err = p.parse(text)
    local parse_err
    if not ok then
      --- red starts at the failing character (IS3.4); a draft
      --- that fails only at its end has none (IS3.5)
      parse_err = p.failure and p.failure(text, p_err) or p_err
    end
    local hl
    if ev.highlighter then
      hl = ev.highlighter(text)
    end

    -- hl stays indexable even with no highlighter (parser but
    -- no colouring): the view indexes highlight.hl
    -- unconditionally.
    self._memo.highlight = { hl = hl or {}, parse_err = parse_err }
  else
    if ev.highlighter then
      -- same invariant as the parser branch above: a
      -- highlighter that returns nil must not leave `.hl` nil
      -- for the view to index
      self._memo.highlight = { hl = ev.highlighter(text) or {} }
    else
      self._memo.highlight = ev:validation_hl(text)
    end
  end
end

function UserInputModel:get_highlight()
  if not self._memo.highlight then
    self:highlight()
  end
  return self._memo.highlight
end

----------------
--  history   --
----------------

--- @return boolean
-- doc/development/internals/user_input.md, "Submit and cancel —
-- widget-owned callback sequences": oneshot is gone, so nothing
-- distinguishes a single-use solicitation from any other
-- model anymore. Only the (never-history-reading) project
-- widget set oneshot=true, so suppression here was already
-- inert; the flag's other job (submit-closing) is what
-- moved into the new submit chain (userInputController.lua).
function UserInputModel:keep_history()
  return true
end

--- @private
function UserInputModel:_remember()
  if self:keep_history() then
    local ent = self.entered
    if string.is_non_empty_string_array(ent) then
      self.history:remember(ent)
    end
  end
end

--- A recalled line shows with the cursor at its end (FR1.5)
function UserInputModel:history_back()
  if self:keep_history() then
    local t = self:get_text()
    local ok, hist = self.history:history_back(t)
    if ok then
      self:set_text(hist)
      self:jump_end()
    end
  end
end

--- Past the newest entry is the line typed, and Down on it
--- does nothing
function UserInputModel:history_fwd()
  if self:keep_history() then
    local t = self:get_text()
    local ok, hist = self.history:history_fwd(t)
    if ok then
      self:set_text(hist)
      self:jump_end()
    end
  end
end

----------------
--   cursor   --
----------------

--- Follow cursor movement with visible range
--- @private
function UserInputModel:_follow_cursor()
  local cl, cc = self:get_cursor_pos()
  local w = self.cfg.view.drawableChars
  --- the cursor's row among the wrapped rows (IS3.10)
  local rows = self.visible.wrap_forward[cl] or { cl }
  local nth = math.intdiv(math.max(cc - 1, 0), w) + 1
  local acl = rows[math.min(nth, #rows)]
  local vrange = self.visible:get_range()
  local diff = vrange:outside(acl)
  if diff ~= 0 then
    self.visible:move_range(diff)
  end
  self.visible:check_range()
end

--- @private
--- @param replace_line boolean
function UserInputModel:_update_cursor(replace_line)
  local cl = self:get_cursor_y()
  local t = self:get_text()
  if replace_line then
    -- DEBT: c is measured on t[cl] while l is set to #t
    -- (doc/development/technical_debt/input.md,
    -- "_update_cursor measures the column on the wrong line").
    self.cursor.c = string.ulen(t[cl]) + 1
    self.cursor.l = #t
  else

  end
end

--- @private
--- @param x integer?
--- @param y integer?
function UserInputModel:_advance_cursor(x, y)
  local cur_l, cur_c = self:get_cursor_pos()
  local move_x = x or 1
  local move_y = y or 0
  if move_y == 0 then
    local next = cur_c + move_x
    self.cursor.c = next
  else
    self.cursor.l = cur_l + move_y
  end
end

--- @param c Cursor
function UserInputModel:set_cursor(c)
  self.cursor = c
end

--- @private
--- Clamp self.cursor into the current text's valid range,
--- counted in characters like every other cursor move —
--- set_text(t, true)'s landing when the
--- new content is shorter than the preserved cursor
--- position (doc/input_api.md, "Live changes").
function UserInputModel:_clamp_cursor_pos()
  local n = self:get_n_text_lines()
  local l = math.max(1, math.min(self.cursor.l, n))
  local llen = string.ulen(self:get_text_line(l))
  local c = math.max(1, math.min(self.cursor.c, llen + 1))
  self:set_cursor(Cursor(l, c))
end

--- @param y integer?
--- @param x integer?
--- @param selection 'keep'|'move'?
function UserInputModel:move_cursor(y, x, selection)
  local prev_l, prev_c = self:get_cursor_pos()
  local c, l
  local line_limit = self:get_n_text_lines() + 1 -- allow for line just being added
  if y and y >= 1 and y <= line_limit then
    l = y
  else
    l = prev_l
  end
  local llen = string.ulen(self:get_text_line(l))
  local char_limit = llen + 1
  if x and x >= 1 and x <= char_limit then
    c = x
  else
    c = prev_c
  end
  self:set_cursor(Cursor(l, c))


  if selection == 'keep' then
  elseif selection == 'move' then
  else
    self:clear_selection()
  end
  self:_follow_cursor()
end

--- @return integer l
--- @return integer c
function UserInputModel:get_cursor_pos()
  return self.cursor.l, self.cursor.c
end

--- @return CursorInfo
function UserInputModel:get_cursor_info()
  return {
    cursor = self.cursor,
  }
end

--- @return integer
function UserInputModel:get_cursor_x()
  return self.cursor.c
end

--- @return integer
function UserInputModel:get_cursor_y()
  return self.cursor.l
end

--- Whether the cursor sits on a text boundary.
--- 'up'/'down' (and nil, meaning either) compare the line
--- only. 'left'/'right' are two-dimensional: with scope
--- 'line' the column edge alone is the limit; with scope
--- 'input' (the default, forced for single-line text) the
--- line must be an edge too, so left at the very start
--- doubles as the 'up' limit and right at the very end as
--- the 'down' limit.
--- @param dir VerticalDir?
--- @param scope 'input'|'line'?
--- @return boolean
function UserInputModel:is_at_limit(dir, scope)
  local n = self:get_n_text_lines()
  local cl, cc = self:get_cursor_pos()
  
  if dir == 'up' then return cl == 1 end
  if dir == 'down' then return cl == n end
  if not dir then return cl == 1 or cl == n end
  
  local line = self:get_text_line(cl)
  local line_end = string.ulen(line) + 1
  local req = (n == 1) and 'input' or (scope or 'input')

  if dir == 'left' then
    return cc == 1 and (req == 'line' or cl == 1)
  elseif dir == 'right' then
    return cc == line_end and (req == 'line' or cl == n)
  end
  return false
end

--- @return InputDTO
function UserInputModel:get_input()
  return {
    text          = self:get_text(),
    highlight     = self:get_highlight(),
    selection     = self:get_ordered_selection(),
    visible       = self.visible,
    wrapped_error = self:get_wrapped_error(),
  }
end

--- @private
--- A line's rows, as the field wraps it (IS3.13). A line that
--- fills its last row does not wrap further: its end shows on
--- that row, as in Luditor.
--- @param l integer
--- @return integer last --- the last row, counted from 0
--- @return integer len --- the line's length in characters
function UserInputModel:_line_rows(l)
  local w = self.visible.wrap_w
  local len = string.ulen(self:get_text_line(l))
  return math.max(math.ceil(len / w) - 1, 0), len
end

--- @private
--- @param l integer
--- @param c integer
--- @return integer row --- the row of position l:c, from 0
function UserInputModel:_row_of(l, c)
  local w = self.visible.wrap_w
  return math.min(math.floor((c - 1) / w), (self:_line_rows(l)))
end

--- @private
--- The first and the last cursor position a row shows. The
--- position after a row's last character shows on the row
--- below, the line's end on its last row.
--- @param l integer
--- @param row integer
--- @return integer first
--- @return integer last
function UserInputModel:_row_bounds(l, row)
  local w = self.visible.wrap_w
  local last_row, len = self:_line_rows(l)
  local first = row * w + 1
  if row >= last_row then return first, len + 1 end
  return first, first + w - 1
end

--- @private
--- The row above or below the cursor's, a wrapped line's rows
--- included (IS3.8, IS3.13)
--- @param dir VerticalDir
--- @return integer? line --- nil at the draft's first or last row
--- @return integer? row --- counted from 0 within the line
function UserInputModel:_neighbor_row(dir)
  local cl, cc = self:get_cursor_pos()
  local row = self:_row_of(cl, cc)
  if dir == 'up' then
    if row > 0 then return cl, row - 1 end
    if cl == 1 then return nil end
    return cl - 1, (self:_line_rows(cl - 1))
  end
  if row < self:_line_rows(cl) then return cl, row + 1 end
  if cl < self:get_n_text_lines() then return cl + 1, 0 end
  return nil
end

--- Up and Down move the cursor by row, keeping its offset
--- from the row's first position where the target row is long
--- enough, at the row's last position otherwise (IS3.8).
--- @param dir VerticalDir
--- @return boolean? limit --- no row lies that way
function UserInputModel:cursor_vertical_move(dir)
  if dir ~= 'up' and dir ~= 'down' then return end
  local nl, nrow = self:_neighbor_row(dir)
  if not nl then
    --- IS3.8: in the editor's field, Up on the first row
    --- goes to the draft's start and Down on the last row to
    --- its end
    if self.editing or self:is_selection_held() then
      if dir == 'up' then
        self:jump_home()
      else
        self:jump_end()
      end
    end
    return true
  end
  local cl, cc = self:get_cursor_pos()
  local offset = cc - self:_row_bounds(cl, self:_row_of(cl, cc))
  local first, last = self:_row_bounds(nl, nrow)
  local keep = self.selection:is_held() and 'keep' or nil
  self:move_cursor(nl, math.min(first + offset, last), keep)
  if keep then self:end_selection() end
  self:_follow_cursor()
end

function UserInputModel:cursor_left()
  local cl, cc = self:get_cursor_pos()
  local nl, nc = (function()
    if cc > 1 then
      local next = cc - 1
      return nil, next
    elseif cl > 1 then
      local cpl = cl - 1
      local pl = self:get_text_line(cpl)
      local cpc = 1 + string.ulen(pl)
      return cpl, cpc
    end
  end)()

  if self.selection:is_held() then
    self:move_cursor(nl, nc, 'keep')
    self:end_selection()
  else
    self:move_cursor(nl, nc)
  end
end

function UserInputModel:cursor_right()
  local cl, cc = self:get_cursor_pos()
  local line = self:get_text_line(cl)
  local len = string.ulen(line)
  local next = cc + 1
  local nl, nc = (function()
    if cc <= len then
      return nil, next
    elseif cl < self:get_n_text_lines() then
      return cl + 1, 1
    end
  end)()

  if self.selection:is_held() then
    self:end_selection(cl, cc + 1)
    self:move_cursor(nl, nc, 'keep')
  else
    self:move_cursor(nl, nc)
  end
end

function UserInputModel:jump_home()
  local keep = (function()
    if self.selection:is_held() then
      return 'keep'
    end
  end)()
  local nl, nc = 1, 1
  self:end_selection(nl, nc)
  self:move_cursor(nl, nc, keep)
  self:_follow_cursor()
end

function UserInputModel:jump_end()
  local ent = self:get_text()
  local last_line = #ent
  local last_char = string.ulen(ent[last_line]) + 1
  local keep = (function()
    if self.selection:is_held() then
      return 'keep'
    end
  end)()
  self:end_selection(last_line, last_char)
  self:move_cursor(last_line, last_char, keep)
  self.visible:to_end()
  self.visible:check_range()
end

--- Whether Caps Lock is on: it changes the case of typed
--- letters, so the status line shows it (H-NFR4.4).
--- @return boolean
local function caps_lock()
  local active = love.keyboard.isModifierActive
  return active ~= nil and active('capslock') == true
end

--- A host that sets status_source (the file editor) has its
--- custom status read afresh each time; one that sets
--- project_source (the console) names the open project.
--- @return Status
function UserInputModel:get_status()
  local src = self.status_source
  local project = self.project_source
  return {
    label = self:get_label(),
    cursor = self.cursor,
    n_lines = self:get_n_text_lines(),
    custom = src and src() or self.custom_status,
    input_more = self.visible:get_more(),
    caps = caps_lock() and 'CAPS' or nil,
    project = project and project() or nil,
  }
end

--- The cursor's row within its wrapped line (IS3.13): the
--- columns of the first and the last cursor position the row
--- shows.
--- @return integer first
--- @return integer last
function UserInputModel:get_row_span()
  local cl, cc = self:get_cursor_pos()
  return self:_row_bounds(cl, self:_row_of(cl, cc))
end

--- @private
--- @param l integer
--- @param c integer
function UserInputModel:_jump_to(l, c)
  local keep = (function()
    if self.selection:is_held() then
      return 'keep'
    end
  end)()
  self:end_selection(l, c)
  self:move_cursor(l, c, keep)
end

--- Home: the first cursor position shown on the cursor's row
--- (IS3.8), the line's start unless the line wraps
function UserInputModel:jump_line_start()
  local first = self:get_row_span()
  self:_jump_to(self.cursor.l, first)
end

--- End: the last cursor position shown on the cursor's row
function UserInputModel:jump_line_end()
  local _, last = self:get_row_span()
  self:_jump_to(self.cursor.l, last)
end

--- Past ASCII, the punctuation, signs and symbols that
--- separate words, as code point ranges. LÖVE's utf8 module,
--- which the IDE runs on, has no character classes.
--- A number is a word's, as a letter is (², ½, ①).
--- In order, by script: Latin-1, Greek, Cyrillic, Armenian,
--- Hebrew, Arabic, Devanagari, then the shared blocks of
--- punctuation and symbols, fullwidth forms and pictographs.
local NON_WORD = {
  { 0xA0, 0xA9 }, { 0xAB, 0xB1 }, { 0xB4, 0xB4 },
  { 0xB6, 0xB8 }, { 0xBB, 0xBB }, { 0xBF, 0xBF },
  { 0xD7, 0xD7 }, { 0xF7, 0xF7 },
  { 0x37E, 0x37E }, { 0x387, 0x387 },
  { 0x482, 0x482 },
  { 0x55A, 0x55F }, { 0x589, 0x58A },
  { 0x5BE, 0x5BE }, { 0x5C0, 0x5C0 }, { 0x5C3, 0x5C3 },
  { 0x5C6, 0x5C6 }, { 0x5F3, 0x5F4 },
  { 0x600, 0x60F }, { 0x61B, 0x61F }, { 0x66A, 0x66D },
  { 0x6D4, 0x6D4 }, { 0x6DD, 0x6DE }, { 0x6E9, 0x6E9 },
  { 0x964, 0x965 },
  --- from U+2000 to U+2BFF, the letters and numbers among
  --- the signs are a word's: superscripts and subscripts,
  --- letterlike symbols (ℝ), number forms (Ⅻ) and circled
  --- numbers (①)
  { 0x2000, 0x206F }, { 0x207A, 0x207E }, { 0x208A, 0x208E },
  { 0x20A0, 0x2101 }, { 0x2103, 0x2106 }, { 0x2108, 0x2109 },
  { 0x2114, 0x2114 }, { 0x2116, 0x2118 }, { 0x211E, 0x2123 },
  { 0x2125, 0x2125 }, { 0x2127, 0x2127 }, { 0x2129, 0x2129 },
  { 0x212E, 0x212E }, { 0x213A, 0x213B }, { 0x2140, 0x2144 },
  { 0x214A, 0x214D }, { 0x214F, 0x214F }, { 0x218A, 0x245F },
  { 0x249C, 0x24E9 }, { 0x2500, 0x2775 }, { 0x2794, 0x2BFF },
  { 0x2E00, 0x2E7F }, { 0x3000, 0x303F },
  { 0xFE10, 0xFE1F }, { 0xFE30, 0xFE6F }, { 0xFF01, 0xFF0F },
  { 0xFF1A, 0xFF20 }, { 0xFF3B, 0xFF3E }, { 0xFF40, 0xFF40 },
  { 0xFF5B, 0xFF65 },
  { 0x1F000, 0x1FAFF },
}

--- @param ch string?
--- @return boolean --- a letter, a digit or an underscore
local function is_word_char(ch)
  if not ch or ch == '' then return false end
  if string.byte(ch) < 128 then
    return string.match(ch, '^[%w_]') ~= nil
  end
  local ok, cp = pcall(utf8.codepoint, ch)
  if not ok then return false end
  for _, r in ipairs(NON_WORD) do
    if cp < r[1] then return true end
    if cp <= r[2] then return false end
  end
  return true
end

--- Where Ctrl+Left lands from (l, c): the start of the word
--- under or before it (IS3.8); everything that is no letter,
--- digit or underscore separates words, line breaks included
--- @param l integer
--- @param c integer
--- @return integer l
--- @return integer c
function UserInputModel:_word_left_of(l, c)
  while true do
    local ch
    if c > 1 then
      ch = string.usub(self:get_text_line(l), c - 1, c - 1)
    end
    if ch and is_word_char(ch) then break end
    if ch then
      c = c - 1
    elseif l > 1 then
      l = l - 1
      c = string.ulen(self:get_text_line(l)) + 1
    else
      break
    end
  end
  local line = self:get_text_line(l)
  while c > 1 and is_word_char(string.usub(line, c - 1, c - 1)) do
    c = c - 1
  end
  return l, c
end

--- Ctrl+Left: to the start of the word under or before the
--- cursor (IS3.8)
function UserInputModel:cursor_word_left()
  self:_jump_to(self:_word_left_of(self:get_cursor_pos()))
end

--- Ctrl+Right: to the end of the word under or after the
--- cursor (IS3.8)
function UserInputModel:cursor_word_right()
  local l, c = self:get_cursor_pos()
  local n = self:get_n_text_lines()
  while true do
    local line = self:get_text_line(l)
    local len = string.ulen(line)
    local ch = c <= len and string.usub(line, c, c) or nil
    if ch and is_word_char(ch) then break end
    if ch then
      c = c + 1
    elseif l < n then
      l, c = l + 1, 1
    else
      break
    end
  end
  local line = self:get_text_line(l)
  local len = string.ulen(line)
  while c <= len and is_word_char(string.usub(line, c, c)) do
    c = c + 1
  end
  self:_jump_to(l, c)
end

--- @param cs CustomStatus
function UserInputModel:set_custom_status(cs)
  if type(cs) == 'table' then
    self.custom_status = cs
  end
end

----------------
-- evaluation --
----------------

--- @return boolean
--- @return string[]
function UserInputModel:evaluate()
  return self:handle(true)
end

--- Clear the field. Only a line that `ran` goes to the
--- history: one dropped never ran.
--- @param ran boolean?
function UserInputModel:cancel(ran)
  if ran then self:_remember() end
  self:reset()
end


--- The parser reports an error column as a BYTE offset, and
--- the cursor counts characters (doc/input_api.md, "Live
--- changes"), so the two need reconciling before the caret is
--- seated. An offset landing inside a character trims back to
--- that character's start, which is where the caret belongs
--- anyway. Same trim-and-retry shape as sanitize_utf8 above,
--- because utf8.len answers nil for a cut-short prefix.
--- @param line string
--- @param byte_c integer
--- @return integer
local function char_col(line, byte_c)
  if byte_c < 1 then return byte_c end
  local pre = string.sub(line, 1, byte_c - 1)
  local n = utf8.len(pre)
  while not n do
    pre = string.sub(pre, 1, -2)
    n = utf8.len(pre)
  end
  return n + 1
end

--- @private
--- @param ent InputText
--- @return Error? --- where the text fails to parse, at the
--- failing character, when the evaluator's parser can say
function UserInputModel:_parse_failure(ent)
  local p = self.evaluator.parser
  if not p or not p.failure then return nil end
  local parses, err = p.parse(ent)
  if parses then return nil end
  return p.failure(ent, err)
end

--- @private
--- On a reject, seat the cursor on the error position.
--- @param ent InputText
--- @return boolean ok
--- @return string[]|Error[]|InputText result
function UserInputModel:_apply_eval(ent)
  local ok, result = self.evaluator:apply(ent)
  if ok then return ok, result end
  local perr = result[1]
  if not perr or not perr.c then return ok, result end
  --- a draft unfinished at its end goes on, on a new line,
  --- with no error to show (IS3.5); a failure before the end
  --- seats the cursor before the failing character (IS3.4)
  local failure = self:_parse_failure(ent)
  if failure and failure.at_end then
    self:continue_line()
    return false, nil
  end
  if failure then
    self:move_cursor(failure.l, failure.c)
    return ok, { failure }
  end
  local c = char_col(self:get_text_line(perr.l), perr.c)
  if c > 1 then c = c + 1 end
  self:move_cursor(perr.l, c)
  return ok, result
end

--- @param eval boolean
--- @return boolean
--- @return string[]|Error[]
-- on_text_entered (userInputController.lua submit chain) is
-- the "value ready" signal. See
-- doc/development/internals/user_input.md,
-- "Submit and cancel — widget-owned callback sequences".
function UserInputModel:handle(eval)
  local ent = self:get_text()
  local ok, result
  if ent:non_empty() then
    self:_remember()
    if eval then
      ok, result = self:_apply_eval(ent)
      if not ok then return false, result end
    else
      ok = true
    end
  end

  return ok, (result or ent)
end

----------------
--   error    --
----------------
function UserInputModel:clear_error()
  self.error = nil
end

--- One entry per screen row: a message's own line breaks
--- (\n, \r\n or \r) split it before wrapping (a failed
--- require lists a path per line), a tab becomes two
--- spaces, and bytes that are not UTF-8 show as U+FFFD.
--- @return string[]?
function UserInputModel:get_wrapped_error()
  if self.error then
    local e = { }
    for _, er in ipairs(self.error) do
      local s = string.scrub(tostring(er))
        :gsub('\r\n?', '\n')
        :gsub('\t', '  ')
      for _, l in ipairs(string.lines(s)) do
        table.insert(e, l)
      end
    end
    local we = string.wrap_array(
      e,
      self.visible.wrap_w)
    --- a notice (IS3.14) is its own one line
    if not self.error.notice then
      table.insert(we, 1, 'Errors:')
    end
    return we
  end
end

--- An error as the text it shows. A project's validator may
--- give a plain { msg = ... } table, which has no __tostring
--- of its own: it shows its message, with its line (and
--- column) when it has them.
--- @param e Error|string|{ msg: string }
--- @return string
local function position(e)
  if not e.l then return "" end
  return "L" .. e.l .. ":" .. (e.c and e.c .. ":" or "")
end

local function error_text(e)
  local mt = type(e) == "table" and getmetatable(e)
  local plain = type(e) == "table" and not (mt and mt.__tostring)
  if not (plain and e.msg ~= nil) then return tostring(e) end
  return position(e) .. tostring(e.msg)
end

--- @TODO support error[] and string[]
--- @param errors Error[]?
function UserInputModel:set_error(errors)
  self.error = nil
  if errors == nil then return end
  --- one error alone, not in a list, is a list of one
  local one = type(errors) ~= "table" or errors.msg ~= nil
  if one then errors = { errors } end
  self.error = {}
  for _, e in ipairs(errors) do
    table.insert(self.error, error_text(e))
  end
end

--- @return boolean
function UserInputModel:has_error()
  if self.error and #(self.error) > 0 then
    return true
  end
  return false
end

--- @param eval Evaluator
function UserInputModel:set_eval(eval)
  self.evaluator = eval
  self.label = eval.label or ''
end

----------------
-- selection  --
----------------
--- The draft's line and column of a cell on its wrapped row
--- `l`, column `c`: the row's place in its own line counts,
--- not the rows the lines before it wrap to
--- @param l integer
--- @param c integer
--- @return integer li
--- @return integer ci
function UserInputModel:translate_grid_to_cursor(l, c)
  local vis = self.visible
  local wt = vis.wrap_reverse
  if not wt[l] then l = #wt end
  local li = wt[l]
  local rank = vis.wrap_rank[l] or 0
  local len = string.ulen(self:get_wrapped_text_line(l))
  return li, rank * vis.wrap_w + math.min(len + 1, c)
end

--- @param c1 Cursor?
--- @param c2 Cursor?
--- @return Cursor?
--- @return Cursor?
function UserInputModel:diff_cursors(c1, c2)
  if c1 and c2 then
    local d = c1:compare(c2)
    if d > 0 then
      return c1, c2
    else
      return c2, c1
    end
  end
end

--- @param from Cursor?
--- @param to Cursor?
function UserInputModel:text_between_cursors(from, to)
  if from and to then
    return self:get_text():traverse(from, to)
  else
    return { '' }
  end
end

--- @param l integer?
--- @param c integer?
function UserInputModel:start_selection(l, c)
  local start = (function()
    if l and c then
      return Cursor(l, c)
    else -- default to current cursor position
      return Cursor(self:get_cursor_pos())
    end
  end)()
  self.selection.start = start
end

--- @param l integer?
--- @param c integer?
function UserInputModel:end_selection(l, c)
  local start         = self.selection.start
  local fin           = (function()
    if l and c then
      return Cursor(l, c)
    else -- default to current cursor position
      return Cursor(self:get_cursor_pos())
    end
  end)()
  local from, to      = self:diff_cursors(start, fin)
  local sel           = self:text_between_cursors(from, to)
  self.selection.fin  = fin
  self.selection.text = sel
end

--- @param is_mouse boolean
function UserInputModel:hold_selection(is_mouse)
  if not is_mouse then
    local cur_start = self:get_selection().start
    local cur_end = self:get_selection().fin
    if cur_start and cur_start.l and cur_start.c then
      self:start_selection(cur_start.l, cur_start.c)
    else
      self:start_selection()
    end
    if cur_end and cur_end.l and cur_end.c then
      self:end_selection(cur_end.l, cur_end.c)
    else
      self:end_selection()
    end
  end
  self.selection.held = true
end

function UserInputModel:release_selection()
  self.selection.held = false
end

--- @return InputSelection
function UserInputModel:get_selection()
  return self.selection
end

--- @return boolean
function UserInputModel:is_selection_held()
  return self.selection.held
end

--- @return InputSelection
function UserInputModel:get_ordered_selection()
  local sel = self.selection
  local s, e = self:diff_cursors(sel.start, sel.fin)
  local ret = InputSelection()
  ret.start = s
  ret.fin = e
  ret.text = sel.text
  ret.held = sel.held
  return ret
end

--- @return string[]?
function UserInputModel:pop_selected_text()
  local t = self.selection.text
  local start = self.selection.start
  local fin = self.selection.fin
  if start and fin then
    local from, to = self:diff_cursors(start, fin)
    if from and to then
      self:get_text():traverse(from, to, { delete = true })
      self:text_change()
      self:move_cursor(from.l, from.c)
      self:clear_selection()
      return t
    end
  end
end

function UserInputModel:clear_selection()
  self.selection = InputSelection()
  self:release_selection()
end

--- @return boolean
function UserInputModel:has_selection()
  local s = self.selection
  return s:is_defined()
end

--- @param l integer
--- @param c integer
function UserInputModel:mouse_click(l, c)
  local li, ci = self:translate_grid_to_cursor(l, c)
  self:clear_selection()
  self:start_selection(li, ci)
  self:hold_selection(true)
end

--- @param l integer
--- @param c integer
function UserInputModel:mouse_release(l, c)
  local li, ci = self:translate_grid_to_cursor(l, c)
  self:release_selection()
  self:end_selection(li, ci)
  self:move_cursor(li, ci, 'keep')
end

--- @param l integer
--- @param c integer
function UserInputModel:mouse_drag(l, c)
  local li, ci = self:translate_grid_to_cursor(l, c)
  local sel = self:get_selection()
  local held = sel.held and love.mouse.isDown(1)
  if sel.start and held then
    self:end_selection(li, ci)
    self:move_cursor(li, ci, 'move')
  end
end
