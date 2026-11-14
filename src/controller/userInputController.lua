local class = require('util.class')
local FieldKeys = require('model.input.fieldKeys')
require("util.key")
require("util.view")
require("util.string.string")
require("util.lua")

-- Stay-open defaults for the submit/cancel lifecycle
-- after_submit/after_cancel default to no-ops, so a widget
-- stays open unless a callback hides it. on_limit_ reached
-- defaults to a no-op so the navigation-boundary emit is an
-- unconditional call. Re-seeded (not wiped) on teardown (AC10).
-- before_submit/before_cancel are deliberately absent: their
-- return is READ as a veto, and an unset one must be
-- distinguishable from one that declines to veto
-- (doc/development/decisions/input.md, D-NO-LOG-NOISE).
-- run_callback already answers nil for an absent name, which is
-- no veto.
local function default_callbacks()
  return {
    on_limit_reached = noop,
    after_submit = noop,
    after_cancel = noop,
  }
end

--- @param model UserInputModel
local new = function(model)
  return {
    model = model,
    -- is_shown() reads this, never love.state (owner ruling
    -- 2026-07-20).
    shown = false,
    -- For the project widget, compy.input.callbacks RESOLVES to
    -- this table for as long as this widget is the current one
    -- (owner ruling 2026-07-20, re-made 2026-08-27); console
    -- and editor set their own directly.
    callbacks = default_callbacks(),
  }
end

--- @class UserInputController
--- @field model UserInputModel
--- @field view UserInputView?
UserInputController = class.create(new)

--- @param v UserInputView
function UserInputController:init_view(v)
  self.view = v
end

function UserInputController:update_view()
  local input = self.model:get_input()
  local status = self:get_status()
  self.view:render(input, status)
end

--- Give the highlighter ONE home: this widget's `callbacks`
--- slot, which is also what compy.input.callbacks resolves to.
--- The evaluator stops holding a copy and RESOLVES the slot
--- instead, so a direct `compy.input.callbacks.highlighter`
--- assignment and a show()/configure() key are the same write
--- by construction — rather than by a copy step every writing
--- path has to remember, which is the step that was missed
--- (doc/development/technical_debt/input.md,
--- "T-HL-TWO-HOMES").
---
--- Resolution, not a forwarding function, because the model
--- branches on the TRUTH of `ev.highlighter`: with no
--- highlighter set it must stay nil so the validation-colouring
--- fallback still runs (userInputModel.lua, `highlight`).
---
--- Call it only on a widget whose evaluator is its OWN. The
--- console's and editor's evaluators are shared and carry a
--- LANGUAGE highlighter of their own, which is not a project
--- callback and must not be resolved away.
function UserInputController:bind_highlighter()
  local ev = self.model.evaluator
  if not ev then return end
  local base = getmetatable(ev)
  local callbacks = self.callbacks
  setmetatable(ev, {
    __index = function(_, k)
      if k == 'highlighter' then
        return callbacks.highlighter
      end
      return base[k]
    end,
  })
end

---------------
--  entered  --
---------------

--- @param t str
function UserInputController:add_text(t)
  self.model:add_text(string.unlines(t))
end

--- @return InputText
function UserInputController:get_text()
  return self.model:get_text()
end

--- @param t str
--- @param keep_cursor boolean?
function UserInputController:set_text(t, keep_cursor)
  self.model:set_text(t, keep_cursor)
  self:update_view()
end

--- @return boolean
function UserInputController:is_empty()
  local ent = self:get_text()
  local is_empty = not string.is_non_empty_string_array(ent)
  return is_empty
end

--- @param dir VerticalDir?
--- @param scope 'input'|'line'?
--- @return boolean
function UserInputController:is_at_limit(dir, scope)
  return self.model:is_at_limit(dir, scope)
end

----------------
-- evaluation --
----------------

--- @param eval Evaluator
function UserInputController:set_eval(eval)
  self.model:set_eval(eval)
end

--- @return Evaluator
function UserInputController:get_eval()
  return self.model.evaluator
end

function UserInputController:clear()
  self.model:clear_input()
  self:clear_error()
end

--- @param cs CustomStatus
function UserInputController:set_custom_status(cs)
  self.model:set_custom_status(cs)
end

--- @return InputDTO
function UserInputController:get_input()
  return self.model:get_input()
end

--- @return Status
function UserInputController:get_status()
  return self.model:get_status()
end

--- @return CursorInfo
function UserInputController:get_cursor_info()
  return self.model:get_cursor_info()
end

--- @return integer l
--- @return integer c
function UserInputController:get_cursor_pos()
  return self.model:get_cursor_pos()
end

--- @param cursor Cursor
function UserInputController:set_cursor(cursor)
  return self.model:set_cursor(cursor)
end

--- Clamped 2D move (compy.input.set_cursor;
--- doc/development/internals/user_input.md, "Cursor
--- manipulation and \"reset\""). Named apart from
--- set_cursor(Cursor) above — that simple function
--- already has a different signature/caller (editorController
--- load_selection); this computes a valid landing itself
--- rather than relying on move_cursor's fallback-to-previous,
--- which does not clamp an out-of-range value to the line/text
--- end. The landing is counted in CHARACTERS, like every other
--- cursor move in the model (doc/input_api.md, "Live changes":
--- col is a caret position between characters).
--- @param line integer
--- @param col integer
function UserInputController:set_cursor_pos(line, col)
  local n = self.model:get_n_text_lines()
  local l = math.max(1, math.min(line, n))
  local llen = string.ulen(self.model:get_text_line(l))
  local c = math.max(1, math.min(col, llen + 1))
  self.model:move_cursor(l, c)
end

-----------
-- error --
-----------
--- @return boolean
function UserInputController:has_error()
  return self.model:has_error()
end

function UserInputController:clear_error()
  self.model:clear_error()
end

--- @param error string[]|Error[]?
function UserInputController:set_error(error)
  self.model:set_error(error)
end

--- @return string[]?
function UserInputController:get_wrapped_error()
  return self.model:get_wrapped_error()
end

--- @return boolean
--- @return Error[]
function UserInputController:evaluate()
  local ok, res = self.model:handle(true)
  self:update_view()
  return ok, res
end

--- Throw away the current draft, firing nothing. Deliberately
--- NOT `cancel_flow` (below): that is a project's Escape and
--- runs `before_cancel`/`after_cancel`, which a console debug
--- path must not trigger on a project's behalf. Its only
--- caller is `consoleController.lua`'s `terminal_test`.
function UserInputController:discard_draft()
  self.model:cancel()
end

function UserInputController:jump_home()
  self.model:jump_home()
end

----------------------
---     history    ---
----------------------
--- @param history boolean?
function UserInputController:reset(history)
  self.model:reset(history)
end

function UserInputController:history_back()
  self.model:history_back()
end

function UserInputController:history_fwd()
  self.model:history_fwd()
end

----------------------
---   widget API    ---
----------------------

-- Internal widget API, reached only through the compy.input.*
-- wrappers (consoleController). Free functions, not methods:
-- they are private helpers to show()/hide() below.

-- The callbacks a config table may carry. The lifecycle ones
-- (before_/after_submit, before_/after_cancel) are deliberately
-- absent: they are set through compy.input.callbacks, never
-- through show() or configure().
local CONFIG_CALLBACKS = {
  'validator', 'on_text_entered', 'on_limit_reached',
  'highlighter',
}

-- One cell per (verb x outcome), all four OFF for the class:
-- a widget nobody configured does nothing at all on Enter or
-- Escape (doc/development/decisions/input.md,
-- D-LIFECYCLE-FLAGS, statement 3). Each owner seats its own
-- through seat_lifecycle below.
local LIFECYCLE_FLAGS = {
  'clear_on_submit', 'hide_on_submit',
  'clear_on_cancel', 'hide_on_cancel',
}

--- Set the flags a table carries and leave the rest alone.
--- `false` is the unset and is written, which is why the test
--- is against nil (D-CFG-BOUNDARY, statement 3).
--- @param self UserInputController
--- @param cfg table
local apply_lifecycle = function(self, cfg)
  for _, name in ipairs(LIFECYCLE_FLAGS) do
    if cfg[name] ~= nil then
      self[name] = cfg[name]
    end
  end
end

--- Everything the PROJECT owns: set-if-given, left alone when
--- absent, and identical in both entry points — which is what
--- stops show() and configure() drifting apart
--- (doc/development/decisions/input.md, D-CFG-BOUNDARY).
--- The user's content is deliberately not here; see
--- reset_content.
--- @param self UserInputController
--- @param cfg table
local configure_core = function(self, cfg)
  if cfg.prompt ~= nil then
    self.model.custom_label = cfg.prompt
  end
  -- Persistent until replaced, like every other key here: they
  -- configure a TYPE of behaviour, not one show/hide cycle
  -- (D-LIFECYCLE-FLAGS, statement 2).
  apply_lifecycle(self, cfg)
  for _, name in ipairs(CONFIG_CALLBACKS) do
    if cfg[name] ~= nil then
      self.callbacks[name] = cfg[name]
    end
  end
end

--- The content baseline, which only ACTIVATION sets: text
--- given is the content, text ABSENT leaves the content alone
--- (D-CFG-BOUNDARY, statement 1, amended 2026-09-07). So a
--- re-show finds what the last lifecycle verb left, and
--- destruction has exactly one home — the (verb x outcome)
--- flags of D-LIFECYCLE-FLAGS. `false` is the uniform unset
--- and so reads as absent (checked_text normalises it to nil
--- at the boundary); the explicit fresh start is text = ''.
--- @param self UserInputController
--- @param cfg table
local reset_content = function(self, cfg)
  if cfg.text ~= nil then
    self.model:set_text(cfg.text)
  end
end

--- The activation path: content baseline, then the
--- project-owned fields, then the cursor, then publish the
--- handle and render once. `text` and `cursor` are here and not
--- in configure_core because they are the USER's — activation
--- is the only call that may seat them
--- (doc/development/decisions/input.md, D-CFG-BOUNDARY).
--- See doc/development/internals/user_input.md,
--- "Cursor manipulation and reset".
--- @param self UserInputController
--- @param cfg table
local open_widget = function(self, cfg)
  reset_content(self, cfg)
  configure_core(self, cfg)
  if cfg.cursor ~= nil then
    self:set_cursor_pos(cfg.cursor[1], cfg.cursor[2])
  end
  -- love.state.user_input is the widget CONTRACT: its presence
  -- is the flag the draw loop (controller.lua) checks to paint
  -- V:draw() each frame, and it carries the { M, C, V } handle
  -- the legacy poll idiom reads. Drivers change but the flag
  -- persists (doc/development/internals/user_input.md, "Widget
  -- lifecycle").
  love.state.user_input = {
    M = self.model,
    C = self,
    V = self.view,
  }
  self.shown = true
  self:update_view()
end

--- Activate the widget. Over a widget already shown this
--- is refused unless force=true, and a forced show is the SAME
--- path a first one takes — a full re-setup, not a narrower
--- second policy (doc/development/decisions/input.md,
--- D-CFG-BOUNDARY, statement 4).
--- @param config table?
function UserInputController:show(config)
  local cfg = config or {}
  -- doc/development/decisions/input.md, D-WIDGET-AT-BOOT
  -- (warn-don't-swallow): a plain show() over an active widget
  -- is suppressed; say so.
  if self.shown and not cfg.force then
    Log.warn('UserInputController:show ignored — widget already'
      .. ' active (pass force=true to override)')
    return
  end
  open_widget(self, cfg)
end

--- Deactivate without firing the cancel chain. Clearing
--- love.state.user_input is what "hides" the widget: the draw
--- loop (controller.lua) paints V:draw() only while the flag is
--- set, so nil-ing it stops the paint on the next frame.
--- A permanent surface (always_shown) declines.
function UserInputController:hide()
  if self.always then return end
  self.shown = false
  love.state.user_input = nil
end

--- Live-reconfigure an active session (compy.input.configure;
--- doc/development/internals/user_input.md,
--- "configure(config)"). It runs configure_core and nothing
--- else, so the project-owned fields are applied by the same
--- code show() uses. No filter table stands in front of it:
--- configure_core cannot see the user's content, which is the
--- boundary itself rather than something this call enforces
--- (doc/development/decisions/input.md, D-CFG-BOUNDARY).
--- @param cfg table
function UserInputController:configure(cfg)
  configure_core(self, cfg)
  self:update_view()
end

----------------------
--- submit / cancel ---
----------------------

-- Submit/cancel are the widget's OWN default behaviour
-- (doc/development/decisions/input.md, D-EDIT-LIFECYCLE): the
-- widget runs them on Enter/Escape as an ordinary consumer
-- (never a routing concern) and signals out through its
-- callbacks. before_/after_submit and before_/after_cancel are
-- read off self.callbacks — the same table a project populates
-- via compy.input.callbacks.

--- Run the project's validator, if it set one, and record its
--- errors on the model — which is what locks the session until
--- keypressed()'s has_error()/clear_error() releases it. No
--- validator accepts unconditionally.
--- @param model UserInputModel
--- @param validator function?
--- @param lines string[]
--- @return boolean accepted
local function validate(model, validator, lines)
  if not validator then return true end
  local ok, errors = validator(lines)
  if not ok then model:set_error(errors) end
  return ok
end

--- @param label string
local function debug_noop(label)
  if love.DEBUG then
    Log.debug('input: ' .. label .. ' noop')
  end
end

--- Invoke a widget callback by name (self.callbacks[name]);
--- absent → no-op + debug-log. The return value is honoured by
--- the caller only where noted (before_cancel veto).
--- @param self UserInputController
--- @param name string
--- @return any
local function run_callback(self, name, ...)
  local cb = self.callbacks[name]
  if cb then return cb(...) end
  debug_noop(name)
end

--- Dispose of the content a verb finished with, then take the
--- widget down — both only if this instance seats the cell
--- (doc/development/decisions/input.md, D-LIFECYCLE-FLAGS).
--- The clear is model:cancel(): a submitted line reaches the
--- input history before it is emptied, and a cancelled one,
--- which never ran, does not (the classic shell's history).
--- It is not compy.input.clear(), which touches no history.
--- @param self UserInputController
--- @param clear boolean?
--- @param hide boolean?
--- @param ran boolean? the verb is a submission
local function dispose(self, clear, hide, ran)
  if clear then self.model:cancel(ran) end
  if hide then self:hide() end
end

--- Submit flow (doc/development/decisions/input.md,
--- D-EDIT-LIFECYCLE): the widget's own Enter behaviour. A truthy
--- before_submit VETOES; otherwise empty guard → validate →
--- dispose → deliver (fires on_text_entered) → after_submit.
--- after_submit defaults to a no-op, so the widget stays shown
--- unless a flag or a callback takes it down.  All three
--- content-bearing callbacks receive the SAME concatenated
--- string (D-ONE-PAYLOAD), before_submit included, so a veto
--- can look at what it is vetoing; on_text_entered and
--- after_submit are told apart by when they run, not by shape.
--- The validator keeps the lines — it runs per line, and
--- LineValidators reports which one failed.
---
--- Disposal runs BEFORE the callbacks (D-LIFECYCLE-FLAGS,
--- "Ordering is UNIFORM"): a callback is entitled to ask a new
--- question, and a trailing hide would take it down. The
--- callbacks lose nothing — the content reaches them as their
--- argument, captured above the clear. Two consequences are
--- ruled rather than incidental: after_submit no longer sees
--- the content IN the widget, and a callback that RAISES now
--- leaves the widget hidden rather than standing, because the
--- raise unwinds to the route boundary (controller.lua,
--- with_canvas_and_errors) past callbacks the disposal already
--- ran ahead of.
function UserInputController:submit_flow()
  local draft = string.unlines(self.model:get_text())
  if run_callback(self, 'before_submit', draft) then return end
  if self.model:get_text():is_empty() then return end
  local lines = self.model:get_text()
  local validator = self.callbacks.validator
  if not validate(self.model, validator, lines) then
    return
  end
  local text = string.unlines(lines)
  dispose(self, self.clear_on_submit, self.hide_on_submit, true)
  run_callback(self, 'on_text_entered', text)
  run_callback(self, 'after_submit', text)
end

--- Cancel flow (D-EDIT-LIFECYCLE): the widget's own Escape
--- behaviour. A truthy before_cancel VETOES the whole flow,
--- after_cancel included; otherwise dispose → after_cancel.
--- Both callbacks receive the draft, read ONCE above the veto:
--- after_cancel's payload is the content the cancel was about,
--- which a flag may already have cleared out of the widget.
--- Both outcomes are this instance's flags, so a widget that
--- seats neither and sets no callbacks does NOTHING here — the
--- class default, and what makes the editor's bare Escape inert
--- (D-LIFECYCLE-FLAGS, statement 3).
function UserInputController:cancel_flow()
  local draft = string.unlines(self.model:get_text())
  if run_callback(self, 'before_cancel', draft) then
    return
  end
  dispose(self, self.clear_on_cancel, self.hide_on_cancel)
  run_callback(self, 'after_cancel', draft)
end

----------------------
--- event handlers ---
----------------------

--- Whether this widget is currently shown — a strictly INTERNAL
--- flag (owner ruling 2026-07-20; no love.state reach). Toggled
--- by show()/hide(); always-active widgets (console/editor) set
--- it true at construction. The project route consumes an event
--- at the widget only while shown; the view skips its per-frame
--- redraw only while shown.
--- @return boolean
function UserInputController:is_shown()
  return self.shown
end

--- Mark this widget as its host's permanent input surface —
--- the console line and the editor's input strip —
--- and return self, for inline construction. A project's widget
--- leaves shown=false and toggles it with show()/hide().
---
--- The name is enforced, not aspirational: hide() refuses on
--- such a widget. Shownness became a flag with this API
--- (pre-feature there was none: a widget was live iff
--- love.state.user_input was set), and a flag anything may
--- clear is a convention, not the guarantee the name claims.
--- Ratified at doc/development/decisions/input.md,
--- D-WIDGET-AT-BOOT: pre-feature nothing could hide these
--- surfaces, and the guard is what re-states that.
--- @return UserInputController self
function UserInputController:always_shown()
  self.shown = true
  self.always = true
  return self
end

--- Seat this owner's lifecycle flags at construction, and
--- return self for inline construction. The class default is
--- all four off; an owner that wants an outcome asks for it
--- here, in the same shape a project asks through show() /
--- configure() (doc/development/decisions/input.md,
--- D-LIFECYCLE-FLAGS, statement 3).
---
--- A method rather than constructor arguments: the two
--- existing capabilities are positional, and four more would
--- put the constructor at seven against agents/rules.md's
--- limit of four.
--- @param flags table
--- @return UserInputController self
function UserInputController:seat_lifecycle(flags)
  apply_lifecycle(self, flags)
  return self
end

----------------
--  keyboard  --
----------------

--- The field's keys are one table for every owner, the
--- console, the file editor and a program's input
--- (model/input/fieldKeys.lua), each chord by its full name
--- (Key.combo): a chord the table does not name does nothing in
--- the field. These are its actions, each taking the
--- controller, its model, the key and whether it repeats.

--- Navigation-boundary output (doc/development/decisions/
--- input.md, D-EDIT-CALLBACKS): a hit limit is signalled only
--- through on_limit_reached
--- @param self UserInputController
local function emit_limit(self, dir, scope)
  local cb = self.callbacks.on_limit_reached
  if cb then cb(dir, scope) end
end

--- @param input UserInputModel
local function horizontal_limit_scope(input, dir)
  if input:get_n_text_lines() == 1 then return 'input' end
  if input:is_at_limit(dir, 'input') then return 'input' end
  return 'line'
end

--- Left or Right, a character or (`word`) a word
local function horizontal(word)
  return function(self, input, k)
    if input:is_at_limit(k, 'line') then
      emit_limit(self, k, horizontal_limit_scope(input, k))
    end
    if k == 'left' then
      if word then input:cursor_word_left()
      else input:cursor_left() end
    else
      if word then input:cursor_word_right()
      else input:cursor_right() end
    end
  end
end

--- Home and End are line-scoped; with Ctrl (`whole`) they
--- jump over the whole text (spec 2.7)
local function edge(whole)
  return function(_, input, k)
    if k == 'home' then
      if whole then input:jump_home()
      else input:jump_line_start() end
    else
      if whole then input:jump_end()
      else input:jump_line_end() end
    end
  end
end

local function vertical(self, input, k)
  if input:cursor_vertical_move(k) then
    emit_limit(self, k, 'input')
  end
end

local ACT = {
  char = horizontal(false),
  word = horizontal(true),
  edge = edge(false),
  whole = edge(true),
  vertical = vertical,
  --- the cursor's line moves past its neighbor
  move_line = function(_, input, k) input:move_line(k) end,
  backspace = function(_, input) input:backspace() end,
  delete = function(_, input) input:delete() end,
  --- word-wise deletion, Ctrl+W as in readline (spec 2.7)
  backspace_word = function(_, im) im:backspace_word() end,
  --- IS3.12: to the end of the line, the break kept
  kill = function(_, input) input:kill_to_line_end() end,
  --- IS3.15: Shift+Enter and Alt+Enter each break the line
  line_feed = function(_, input) input:line_feed() end,
  --- the widget's own submit and cancel (D-EDIT-LIFECYCLE),
  --- out through callbacks. A held Enter submits once: its
  --- repeats reach no callback (API2.2).
  submit = function(self, _, _, isr)
    if not isr then self:submit_flow() end
  end,
  cancel = function(self) self:cancel_flow() end,
  --- the draft's own undo and redo (D-UNDO-KEYS)
  undo = function(_, input) input:undo_edit() end,
  redo = function(_, input) input:redo_edit() end,
}

--- Whether the field acts on a chord (Key.combo's name), and
--- its entry (fieldKeys.lua)
--- @param chord string
--- @return table? entry
function UserInputController:names(chord)
  return FieldKeys:lookup('field', chord)
end

--- The keys an error unlocks the field with
--- (doc/development/internals/user_input.md, "Error state")
local UNLOCKS = {
  ['return'] = true, kpenter = true, up = true, down = true,
  left = true, right = true, space = true,
}

--- LÖVE's own argument list, like every other consumer on the
--- chain (doc/development/decisions/input.md, D-LOVE-ARGS).
--- The scancode is unread; a repeat edits as its press does,
--- and submits nothing (API2.2).
--- @param k string
--- @param sc string?    scancode
--- @param isr boolean?  key repeat
-- No return value: the old limit-flag return channel is
-- retired (D-EDIT-CALLBACKS) — on_limit_reached is the sole
-- notification path now.
function UserInputController:keypressed(k, sc, isr)
  if not self.shown then
    if love.DEBUG then Log.debug('input: hidden no-op') end
    return
  end
  -- Defensive render-on-entry: guarantees the view catches up
  -- to the model even if a prior branch returned without
  -- re-rendering.
  self:update_view()
  -- _G.web: web/love.js build flag. On web, space may not emit
  -- textinput, so synthesise it here.
  -- This text does not pass the event gate, so a chord's
  -- space is held back here (Key.chord_text).
  if _G.web and k == 'space' and not Key.chord_text(' ') then
    self:textinput(' ')
  end
  local input = self.model
  local chord = Key.combo(k)

  -- doc/development/internals/user_input.md, "Error state":
  -- locked-on-reject unlocks on Enter/Space/arrows.
  -- The editor's field shows a notice without blocking input:
  -- the next key dismisses it and does its work (IS3.14).
  -- A modifier or a lock on its own leaves it showing.
  local lone = Key.is_mod(k) or k == 'capslock'
      or k == 'numlock' or k == 'scrolllock'
      or k == 'lgui' or k == 'rgui'
  if input:has_error() and input.editing then
    if not lone then input:clear_error() end
  elseif input:has_error() then
    if UNLOCKS[chord] then input:clear_error() end
    return
  end

  local entry = self:names(chord)
  if entry then
    ACT[entry.act](self, input, k, isr)
  end
  self:update_view()
end

--- @param t string
-- Visibility is decided by the internal hidden-check (shown ->
-- edit; hidden -> no-op). A shown widget always edits its live
-- model state.
function UserInputController:textinput(t)
  if not self.shown then
    if love.DEBUG then Log.debug('input: hidden no-op') end
    return
  end
  self:update_view()
  if self.model:has_error() then
    if not self.model.editing then return end
    --- the editor's notice blocks no input (IS3.14)
    self.model:clear_error()
  end
  self.model:add_text(t)
  self:update_view()
end

--- @param k string
--- @param sc string?    scancode; LÖVE's second argument,
---                    unread
function UserInputController:keyreleased(k, sc)
  if not self.shown then
    if love.DEBUG then Log.debug('input: hidden no-op') end
    return
  end
  local input = self.model
  self:update_view()

  if input:has_error() and k == 'space' then
    input:clear_error()
  end
  self:update_view()
end

---------------
--   mouse   --
---------------

--- A click in the draft places the text cursor on the cell
--- it points at, in every field; it selects nothing (the
--- ruling of November 14, 2026). A click outside the rows the
--- field shows leaves the cursor where it is.
--- @param x integer
--- @param y integer
--- @param btn integer
function UserInputController:mousepressed(x, y, btn)
  local v = self.view
  if btn ~= 1 or not (v and v.cell_at) then return end
  local im = self.model
  local row, col = v:cell_at(x, y, im:get_input())
  if not row then return end
  im:move_cursor(im:translate_grid_to_cursor(row, col))
  self:update_view()
end

--- @param x integer
--- @param y integer
--- @param btn integer
--- @param touch boolean
--- @param presses number
function UserInputController:mousereleased(
    x, y, btn, touch, presses)
end

--- @param x number
--- @param y number
--- @param dx number
--- @param dy number
--- @param touch boolean
--- A drag selects nothing
function UserInputController:mousemoved(x, y, dx, dy, touch)
end

--- @param x integer
--- @param y integer
function UserInputController:wheelmoved(x, y)
  --- TODO
end

-- The derived clicks are the framework's synthesis, for
-- projects to bind; text editing has no use for them. Present
-- because the chain calls every channel on its terminal tier.
function UserInputController:singleclick()
end

function UserInputController:doubleclick()
end

--- @param id userdata
--- @param x number
--- @param y number
--- @param dx number?
--- @param dy number?
--- @param pressure number?
function UserInputController:touchpressed(id, x, y,
                                          dx, dy, pressure)
  --- TODO
end

--- @param id userdata
--- @param x number
--- @param y number
--- @param dx number?
--- @param dy number?
--- @param pressure number?
function UserInputController:touchreleased(id, x, y,
                                           dx, dy, pressure)
  --- TODO
end

--- @param id userdata
--- @param x number
--- @param y number
--- @param dx number?
--- @param dy number?
--- @param pressure number?
function UserInputController:touchmoved(id, x, y,
                                        dx, dy, pressure)
  --- TODO
end
