-- Availability: introduced with the Compy input API
-- (1.0.0-rc20260712) — the widget callbacks are new with
-- it, and it is what set today's submit/cancel defaults.

-- The widget's OUTCOMES, which are not part of the dispatch
-- chain at all: D-EDIT-CALLBACKS's four callbacks, the
-- highlighter / on_limit_reached
-- boundary, and the submit/cancel call-order chains of
-- D-EDIT-LIFECYCLE (doc/development/decisions/input.md). The
-- mechanics half — order, consume, fall-through, combo tables,
-- signatures — is input_events_spec.lua.

local F    = require('tests.helpers.input_fixture')
local mock = require('tests.mock')
local TU   = require('tests.testutil')

-- Every case drives the REAL project route:
-- F.activate_project() installs the ProjectInputController
-- through the same Controller.set_user_handlers path a run
-- calls, and returns the project-facing compy.input surface.
-- Assertions are on the widget's text and the project's own
-- callbacks — never a spy on an internal method, except the one
-- widget-signature case, which patches the shared widget and
-- restores it.

describe('input surface: widget callbacks #input', function()
  setup(function() F.setup() end)
  teardown(function() F.teardown() end)
  before_each(function() F.reset() end)

  describe('the callback fields', function()
    -- doc/development/decisions/input.md,
    -- D-EDIT-CALLBACKS: the four callbacks are
    -- project-assignable fields on
    -- compy.input (same boundary, widened allowlist).
    it('the four callback fields are assignable',
      function()
        local input = F.compy_input()
        assert.has_no.errors(function()
          input.callbacks.on_text_entered  = function() end
          input.callbacks.on_limit_reached = function() end
          input.callbacks.validator        = function() end
          input.callbacks.highlighter      = function() end
        end)
      end)

    -- doc/development/decisions/input.md, D-EDIT-CALLBACKS:
    -- show(config) keys and field assignment hit the same
    -- underlying callbacks.
    it('show(config) and fields share one output field',
      function()
        local input = F.compy_input()
        local cb = function() end
        input.show({ on_limit_reached = cb })
        assert.equal(cb, input.callbacks.on_limit_reached)
        local hl = function() return { { } } end
        input.callbacks.highlighter = hl
        input.show()
        assert.equal(hl, input.callbacks.highlighter)
      end)

    -- doc/development/decisions/input.md,
    -- D-EDIT-CALLBACKS cont.: on_text_entered and validator
    -- also reach the same
    -- callback via config key and via field write
    -- (settable-only here; firing/gating is decisions/
    -- input.md, D-EDIT-LIFECYCLE).
    it('show(config) shares on_text_entered callback',
      function()
        local input = F.compy_input()
        local cb = function() end
        input.show({ on_text_entered = cb })
        assert.equal(cb, input.callbacks.on_text_entered)
      end)

    it('field write shares on_text_entered callback',
      function()
        local input = F.compy_input()
        local cb = function() end
        input.callbacks.on_text_entered = cb
        input.show()
        assert.equal(cb, input.callbacks.on_text_entered)
      end)

    it('show(config) shares validator callback',
      function()
        local input = F.compy_input()
        local vfn = function() return true end
        input.show({ validator = vfn })
        assert.equal(vfn, input.callbacks.validator)
      end)

    it('field write shares validator callback',
      function()
        local input = F.compy_input()
        local vfn = function() return true end
        input.callbacks.validator = vfn
        input.show()
        assert.equal(vfn, input.callbacks.validator)
      end)
  end)

  describe('highlighter', function()
    -- doc/development/decisions/input.md, D-EDIT-CALLBACKS: a
    -- custom highlighter transforms live text and the queried
    -- highlight reflects that transformed output.
    it('a custom highlighter transforms queried highlight',
      function()
        local input = F.activate_project()
        local marker = { { 'x' } }
        input.show({
          highlighter = function()
            return marker
          end,
        })
        F.session.type('a')
        local got = F.widget.model:get_highlight()
        assert.equal(marker, got.hl)
      end)

    -- doc/input_api.md, "Callback assignments": the highlighter
    -- is assignable directly, like every other callback, and a
    -- direct assignment is live — it does not wait for an
    -- unrelated later show()/configure() to flush it. It has
    -- ONE home (the widget's callbacks slot) and the evaluator
    -- resolves that slot rather than holding a copy
    -- (doc/development/technical_debt/input.md,
    -- "T-HL-TWO-HOMES").
    it('a direct highlighter assignment is live',
      function()
        local input = F.activate_project()
        local marker = { { 'x' } }
        input.show({ text = 'hi' })
        input.callbacks.highlighter =
          function() return marker end
        F.session.type('a')
        assert.equal(marker,
          F.widget.model:get_highlight().hl)
      end)

    it('LuaHighlighter colors Lua input widget text', function()
      local input = F.activate_project()
      input.show({ highlighter = LuaHighlighter })
      F.session.type('return 1')
      local hl = F.widget.model:get_highlight().hl
      assert.is_true(type(hl) == 'table')
    end)
  end)

  describe('navigation boundaries', function()
    -- doc/development/decisions/input.md, D-EDIT-CALLBACKS,
    -- boundary half: crossing attempts fire
    -- on_limit_reached(direction, scope) and its return value
    -- is ignored (observational only; widget still runs).
    it('up boundary fires direction up with input scope',
      function()
        local seen = { }
        local input = F.activate_project()
        input.show({
          text = { 'ab', 'cd' },
          on_limit_reached = function(dir, scope)
            seen[#seen + 1] = { dir, scope }
          end,
        })
        F.widget:set_cursor(Cursor(1, 2))
        F.session.press('up')
        assert.same({ { 'up', 'input' } }, seen)
      end)

    it('down boundary fires direction down with input scope',
      function()
        local seen = { }
        local input = F.activate_project()
        input.show({
          text = { 'ab', 'cd' },
          on_limit_reached = function(dir, scope)
            seen[#seen + 1] = { dir, scope }
          end,
        })
        F.widget:set_cursor(Cursor(2, 2))
        F.session.press('down')
        assert.same({ { 'down', 'input' } }, seen)
      end)

    it('left boundary fires output; return is ignored',
      function()
        local seen = { }
        local input = F.activate_project()
        input.show({
          text = 'ab',
          on_limit_reached = function(dir, scope)
            seen[#seen + 1] = { dir, scope }
            return true
          end,
        })
        F.widget:jump_home()
        F.session.press('left')
        assert.same({ { 'left', 'input' } }, seen)
      end)

    -- doc/development/decisions/input.md, D-EDIT-CALLBACKS:
    -- line-scope boundary in multiline text.
    it('left line boundary fires scope line', function()
      local seen = { }
      local input = F.activate_project()
      input.show({
        text = { 'ab', 'cd' },
        on_limit_reached = function(dir, scope)
          seen[#seen + 1] = { dir, scope }
        end,
      })
      F.widget:set_cursor(Cursor(2, 1))
      F.session.press('left')
      assert.same({ { 'left', 'line' } }, seen)
    end)

    it('right line boundary fires scope line', function()
      local seen = { }
      local input = F.activate_project()
      input.show({
        text = { 'ab', 'cd' },
        on_limit_reached = function(dir, scope)
          seen[#seen + 1] = { dir, scope }
        end,
      })
      F.widget:set_cursor(Cursor(1, 3))
      F.session.press('right')
      assert.same({ { 'right', 'line' } }, seen)
    end)

    -- Edge case: first-line left is a horizontal key that
    -- maps to whole-input limit scope.
    it('left at first-line start has input scope', function()
      local seen = { }
      local input = F.activate_project()
      input.show({
        text = { 'ab', 'cd' },
        on_limit_reached = function(dir, scope)
          seen[#seen + 1] = { dir, scope }
        end,
      })
      F.widget:set_cursor(Cursor(1, 1))
      F.session.press('left')
      assert.same({ { 'left', 'input' } }, seen)
    end)

    -- Edge case: last-line right is a horizontal key that
    -- maps to whole-input limit scope.
    it('right at last-line end reports input scope', function()
      local seen = { }
      local input = F.activate_project()
      input.show({
        text = { 'ab', 'cd' },
        on_limit_reached = function(dir, scope)
          seen[#seen + 1] = { dir, scope }
        end,
      })
      F.widget:set_cursor(Cursor(2, 3))
      F.session.press('right')
      assert.same({ { 'right', 'input' } }, seen)
    end)
  end)

  -- ---- submit and cancel (doc/development/decisions/input.md,
  -- D-EDIT-LIFECYCLE) -------

  describe('submit', function()
    -- A truthy before_submit VETOES the submit, the mirror of
    -- before_cancel below: nothing downstream runs and the text
    -- stays, so a project can refuse a submission
    -- it is not ready for without having to undo one.
    it('a truthy before_submit vetoes the whole submit',
      function()
        local input = F.activate_project()
        local reached = { }
        input.callbacks.before_submit = function() return true end
        input.callbacks.validator = function()
          reached[#reached + 1] = 'validator'; return true
        end
        input.callbacks.after_submit = function()
          reached[#reached + 1] = 'after'
        end
        input.show({
          text = 'abc',
          on_text_entered = function()
            reached[#reached + 1] = 'entered'
          end,
        })
        F.session.press('return')
        assert.same({ }, reached)
        assert.same({ 'abc' }, F.widget:get_text())
      end)

    -- The control for the case above: a FALSEY before_submit
    -- must not veto anything. Without it, a submit broken
    -- outright would satisfy the veto assertion just as well.
    it('a falsey before_submit lets the submit through',
      function()
        local input = F.activate_project()
        local entered
        input.callbacks.before_submit = function() return nil end
        input.show({
          text = 'abc',
          on_text_entered = function(t) entered = t end,
        })
        F.session.press('return')
        assert.equal('abc', entered)
      end)

    -- doc/development/decisions/input.md, D-EDIT-LIFECYCLE: the
    -- full submit call-order chain on a real Enter keypress.
    -- Every content-bearing callback receives the same string
    -- (D-ONE-PAYLOAD); the validator
    -- keeps the line array, being positional plumbing.
    it('Enter runs the full submit call-order chain',
      function()
        local order = { }
        local input = F.activate_project()
        input.callbacks.before_submit = function(t)
          order[#order + 1] = { 'before', t }
        end
        input.callbacks.validator = function(t)
          order[#order + 1] = { 'validator', t }
          return true
        end
        input.callbacks.after_submit = function(t)
          order[#order + 1] = { 'after', t }
        end
        input.show({
          text = { 'a', 'b' },
          on_text_entered = function(t)
            order[#order + 1] = { 'entered', t }
          end,
        })
        F.session.press('return')
        assert.same(
          {
            { 'before', 'a\nb' },
            { 'validator', { 'a', 'b' } },
            { 'entered', 'a\nb' },
            { 'after', 'a\nb' },
          }, order)
      end)

    -- The reverse of what this case pinned until 2026-09-09,
    -- and the reversal is the point: the two submit callbacks
    -- no longer differ by payload, they differ by WHEN they
    -- run. Multi-line content, because a one-line widget hands
    -- back 'a' and { 'a' } -- shapes so close that a payload
    -- left as lines would still read as a string to a lax
    -- assertion. Told apart by order, which the call-order
    -- chain above pins.
    it('both submit callbacks receive the same string',
      function()
        local seen = { }
        local input = F.activate_project()
        input.callbacks.after_submit = function(t)
          seen.after = t
        end
        input.show({
          text = { 'a', 'b' },
          on_text_entered = function(t) seen.entered = t end,
        })
        F.session.press('return')
        assert.equal('a\nb', seen.entered)
        assert.equal('a\nb', seen.after)
      end)

    -- The three guard callbacks received NO argument until
    -- 2026-09-09, so a veto could not look at what it was
    -- vetoing -- which is the reason the ruling gives for
    -- handing them the draft. Asserted as a veto DECIDING on
    -- its payload: a callback that is handed the draft and
    -- ignores it would satisfy an equality check on its own.
    it('before_submit vetoes on the draft it receives',
      function()
        local seen
        local input = F.activate_project()
        input.callbacks.before_submit = function(t)
          seen = t
          return t == 'a\nb'
        end
        input.show({ text = { 'a', 'b' } })
        F.session.press('return')
        assert.equal('a\nb', seen)
        assert.same({ 'a', 'b' }, F.widget:get_text())
      end)

    -- D-EDIT-LIFECYCLE: submit does not auto-close. The default
    -- after_submit is a no-op, so BOTH on_text_entered and
    -- after_submit see the session still active — the widget
    -- stays open unless a callback hides it (AC3).
    it('on_text_entered and after_submit both see the ' ..
      'session still active (stays open)', function()
      local seen = { }
      local input = F.activate_project()
      input.show({
        text = 'x',
        on_text_entered = function()
          seen.entered = F.is_widget_visible()
        end,
      })
      input.callbacks.after_submit = function()
        seen.after = F.is_widget_visible()
      end
      F.session.press('return')
      assert.is_true(seen.entered)
      assert.is_true(seen.after)
    end)

    -- The validator is a step OF the submit chain, which is why
    -- it is documented with it
    -- (doc/development/internals/user_input.md, "Submit and
    -- cancel — widget-owned callback sequences") — that
    -- section
    -- reference is not a mismatch. What this case pins is not
    -- the chain order (the first case of this group does that)
    -- but the argument: a custom validator receives the
    -- widget's live line array, not joined or stale text.
    it('a custom validator receives the live lines',
      function()
        local seen
        local input = F.activate_project()
        input.show({
          text = 'ab',
          validator = function(t) seen = t; return true end,
        })
        F.session.press('return')
        assert.same({ 'ab' }, seen)
      end)

    -- doc/development/internals/user_input.md, "Submit and
    -- cancel — widget-owned callback sequences": a
    -- rejecting validator locks the
    -- session — no delivery, no deactivation, no
    -- after_submit.
      it('a rejecting validator locks input without delivering',
      function()
        local entered, after = false, false
        local input = F.activate_project()
        input.callbacks.after_submit = function() after = true end
        input.show({
          text = 'bad',
          validator = function() return false, { Error('nope') } end,
          on_text_entered = function() entered = true end,
        })
        F.session.press('return')
        assert.is_false(entered)
        assert.is_false(after)
        assert.is_true(F.is_widget_visible())
        assert.is_true(F.widget:has_error())
      end)

      it('LineValidators rejects one invalid line', function()
        local entered = false
        local input = F.activate_project()
        input.show({
          text = { 'ok', 'bad' },
          validator = LineValidators(function(line)
            return line ~= 'bad', 'not allowed'
          end),
          on_text_entered = function() entered = true end,
        })
        F.session.press('return')
        assert.is_false(entered)
        assert.is_true(F.widget:has_error())
        assert.is_true(F.is_widget_visible())
      end)

      it('LuaSyntaxValidator rejects invalid Lua', function()
        local entered = false
        local input = F.activate_project()
        input.show({
          text = 'return (',
          validator = LuaSyntaxValidator,
          on_text_entered = function() entered = true end,
        })
        F.session.press('return')
        assert.is_false(entered)
        assert.is_true(F.widget:has_error())
      end)

      it('LuaSyntaxValidator accepts Lua lines unchanged', function()
        local seen
        local input = F.activate_project()
        input.show({
          text = { 'local x = 1', 'return x' },
          validator = LuaSyntaxValidator,
          on_text_entered = function(text) seen = text end,
        })
        F.session.press('return')
        assert.equal('local x = 1\nreturn x', seen)
      end)
  end)

  describe('cancel — the Escape chain', function()
    -- D-EDIT-LIFECYCLE: Escape runs the cancel call-order chain
    -- (before_cancel → the flags → after_cancel). The PROJECT
    -- widget seats NEITHER cancel cell, so the chain runs over
    -- a widget it leaves standing and untouched — the callbacks
    -- fire, the outcome is the project's to ask for
    -- (doc/development/decisions/input.md, D-LIFECYCLE-FLAGS,
    -- statement 3). after_cancel is still a no-op by default.
    it('Escape runs the cancel chain and destroys nothing',
      function()
        local order = { }
        local input = F.activate_project()
        input.callbacks.before_cancel = function()
          order[#order + 1] = 'before'
        end
        input.callbacks.after_cancel = function()
          order[#order + 1] = 'after'
        end
        input.show({ text = 'x' })
        F.session.press('escape')
        assert.same({ 'before', 'after' }, order)
        assert.is_true(F.is_widget_visible())
        assert.same({ 'x' }, F.widget:get_text())
      end)

    -- doc/input_api.md, "Submit lifecycle": a truthy
    -- before_cancel VETOES the cancel outright -- the draft
    -- survives and after_cancel never runs. This is how a
    -- project guards unsaved content against a stray Escape.
    -- Both cancel cells are seated here on purpose: the widget
    -- seats neither by default, so a veto that leaked would
    -- leave no trace on a bare show.
    it('a truthy before_cancel vetoes the whole cancel',
      function()
        local input = F.activate_project()
        local after = false
        input.callbacks.before_cancel =
          function() return true end
        input.callbacks.after_cancel =
          function() after = true end
        input.show({
          text            = 'abc',
          clear_on_cancel = true,
          hide_on_cancel  = true,
        })
        F.session.press('escape')
        assert.is_false(F.widget:is_empty())
        assert.is_true(F.is_widget_visible())
        assert.is_false(after)
      end)

    -- The cancel half of the guard-callback ruling, and the
    -- mirror of before_submit's case above. hide_on_cancel is
    -- seated for the same reason as in the case above it.
    it('before_cancel vetoes on the draft it receives',
      function()
        local seen
        local input = F.activate_project()
        input.callbacks.before_cancel = function(t)
          seen = t
          return t == 'a\nb'
        end
        input.show({
          text           = { 'a', 'b' },
          hide_on_cancel = true,
        })
        F.session.press('escape')
        assert.equal('a\nb', seen)
        assert.is_true(F.is_widget_visible())
      end)

    -- after_cancel's payload is captured ABOVE the disposal,
    -- so it is the content the cancel was about even when a
    -- flag has already emptied the widget. clear_on_cancel is
    -- seated here on purpose: the project widget does not seat
    -- it, so without that the draft would still be sitting in
    -- the widget and a payload read AFTER the clear would pass.
    it('after_cancel receives the draft its flag cleared',
      function()
        local seen
        local input = F.activate_project()
        input.callbacks.after_cancel = function(t) seen = t end
        input.show({
          text            = { 'a', 'b' },
          clear_on_cancel = true,
        })
        F.session.press('escape')
        assert.equal('a\nb', seen)
        assert.same({ '' }, F.widget:get_text())
      end)
  end)

  -- doc/development/decisions/input.md, D-LIFECYCLE-FLAGS:
  -- one flag per (verb x outcome), all four off for the class
  -- and seated per instance. These cases drive the PROJECT
  -- widget, which ships with clear_on_submit seated and
  -- NOTHING on the cancel side, so each case says which cell
  -- it is about. hide_on_submit is what auto_hide used to be,
  -- and the cases that pinned auto_hide's properties are here
  -- under its name.
  describe('the lifecycle flags', function()
    it('a hide_on_submit show closes on submit', function()
      local input = F.activate_project()
      input.show({ text = 'a', hide_on_submit = true })
      F.session.press('return')
      assert.is_false(F.is_widget_visible())
    end)

    -- The control for the case above: without the key the same
    -- sequence leaves the widget shown, so a submit broken
    -- outright cannot pass the case by never showing anything.
    it('a plain show does not close on submit', function()
      local input = F.activate_project()
      input.show({ text = 'a' })
      F.session.press('return')
      assert.is_true(F.is_widget_visible())
    end)

    -- The project widget's shipped seating on the submit side:
    -- the field is empty afterwards without the project asking
    -- for it, and the widget stays up (statement 3; the
    -- stakeholders' proposal #3).
    it('submit clears the field by default', function()
      local input = F.activate_project()
      input.show({ text = 'a' })
      F.session.press('return')
      assert.is_true(F.widget:is_empty())
      assert.is_true(F.is_widget_visible())
    end)

    -- The clear is model:cancel() — remember, THEN clear — so
    -- the submitted line reaches the input history rather than
    -- being dropped (statement 4). It is not
    -- compy.input.clear(), which touches no history.
    it('the clear remembers before it empties', function()
      local input = F.activate_project()
      input.show({ text = 'remembered' })
      F.session.press('return')
      assert.is_true(F.widget:is_empty())
      F.widget:history_back()
      assert.same({ 'remembered' }, F.widget:get_text())
    end)

    -- And the cancel side, which seats NOTHING: Escape neither
    -- empties the widget nor takes it down, so cancelling is
    -- fully opt-in (statement 3, "the least-destructive
    -- default"). Both halves asserted, because a default that
    -- destroyed one of the two would satisfy either alone.
    it('cancel does nothing by default', function()
      local input = F.activate_project()
      input.show({ text = 'draft' })
      F.session.press('escape')
      assert.is_true(F.is_widget_visible())
      assert.same({ 'draft' }, F.widget:get_text())
    end)

    -- Independently settable, cell by cell: the two the
    -- project widget does not seat can be asked for, and the
    -- two it does seat can be turned off. `false` is the
    -- unset (D-CFG-BOUNDARY, statement 3).
    it('clear_on_cancel is settable and empties on Escape',
      function()
        local input = F.activate_project()
        input.show({ text = 'draft', clear_on_cancel = true })
        F.session.press('escape')
        assert.is_true(F.widget:is_empty())
      end)

    it('clear_on_submit = false keeps the submitted text',
      function()
        local input = F.activate_project()
        input.show({ text = 'a', clear_on_submit = false })
        F.session.press('return')
        assert.same({ 'a' }, F.widget:get_text())
      end)

    -- editor spec API2.2: "Key-repeat events from holding
    -- Enter do not trigger another submission"
    it('a held Enter submits once, before_submit included',
      function()
        local input = F.activate_project()
        local before, sent = 0, 0
        input.callbacks.before_submit = function()
          before = before + 1
        end
        input.callbacks.on_text_entered = function()
          sent = sent + 1
        end
        input.show({ text = 'a', clear_on_submit = false })
        F.session.press('return')
        F.session.repeat_press('return')
        F.session.repeat_press('return')
        F.session.release('return')
        assert.same(1, before)
        assert.same(1, sent)
        F.session.press('return')
        F.session.release('return')
        assert.same(2, sent)
      end)

    -- the rule is the field's: a program that reads the key
    -- itself still gets every repeat
    it("a held Enter's repeats still reach the program's hook",
      function()
        local input = F.activate_project()
        local seen = { }
        input.hooks.keypressed = function(k, _, isr)
          if k == 'return' then seen[#seen + 1] = isr end
        end
        input.show({ text = 'a', clear_on_submit = false })
        F.session.press('return')
        F.session.repeat_press('return')
        F.session.repeat_press('return')
        F.session.release('return')
        assert.same({ false, true, true }, seen)
      end)

    -- The pair of the case above, and the one that keeps the
    -- new default honest: hiding on Escape is still available,
    -- it is just asked for now. Without this, "cancel does
    -- nothing by default" would also pass on a widget that
    -- could no longer hide at all.
    it('hide_on_cancel is settable and hides on Escape',
      function()
        local input = F.activate_project()
        input.show({ text = 'a', hide_on_cancel = true })
        F.session.press('escape')
        assert.is_false(F.is_widget_visible())
      end)

    -- D-LIFECYCLE-FLAGS, "Ordering is UNIFORM": disposal runs
    -- BEFORE the verb's callbacks, on both verbs. The
    -- callbacks lose nothing, because the content reaches them
    -- as their argument -- which is what this case checks
    -- alongside the widget being already empty and already
    -- hidden when they run.
    it('the flags act before the submit callbacks',
      function()
        local seen_visible, seen_text, payload
        local input = F.activate_project()
        input.callbacks.after_submit = function()
          seen_visible = F.is_widget_visible()
          seen_text = F.widget:get_text()
        end
        input.show({
          text            = 'a',
          hide_on_submit  = true,
          on_text_entered = function(t) payload = t end,
        })
        F.session.press('return')
        assert.is_false(seen_visible)
        assert.same({ '' }, seen_text)
        assert.equal('a', payload)
      end)

    -- The cancel half of the same ordering. The widget seats
    -- no cancel cell now, so the flag is asked for here: with
    -- nothing seated there is no disposal to run before the
    -- callback and the case would pin nothing at all.
    it('the flags act before the cancel callbacks too',
      function()
        local seen_visible, seen_text
        local input = F.activate_project()
        input.callbacks.after_cancel = function()
          seen_visible = F.is_widget_visible()
          seen_text = F.widget:get_text()
        end
        input.show({ text = 'draft', hide_on_cancel = true })
        F.session.press('escape')
        assert.is_false(seen_visible)
        assert.same({ 'draft' }, seen_text)
      end)

    -- "After a SUCCESSFUL submit" needs no rule of its own:
    -- the flags hang where the delivery does, so every early
    -- return of the submit chain suppresses them for free. A
    -- rejecting validator is the case a project actually meets.
    it('a rejecting validator leaves it open and untouched',
      function()
      local input = F.activate_project()
      input.show({
        text           = 'bad',
        hide_on_submit = true,
        validator      = function()
          return false, { Error('no') }
        end,
      })
      F.session.press('return')
      assert.is_true(F.is_widget_visible())
      assert.same({ 'bad' }, F.widget:get_text())
      assert.is_true(F.widget:has_error())
    end)

    -- Statement 2: a flag configures a TYPE of behaviour, not
    -- one show/hide cycle, so it persists until replaced
    -- exactly like validator. A later bare show() inherits it.
    it('a later bare show still closes on submit', function()
      local input = F.activate_project()
      input.show({ text = 'a', hide_on_submit = true })
      F.session.press('return')
      input.show({ text = 'b' })
      F.session.press('return')
      assert.is_false(F.is_widget_visible())
    end)

    -- ...and false is the unset (D-CFG-BOUNDARY, statement 3),
    -- so the disarm needs no vocabulary of its own. This is the
    -- pair of the case above: without it, "persists" would be
    -- indistinguishable from "cannot be turned off".
    it('a later show passing false stops the closing',
      function()
      local input = F.activate_project()
      input.show({ text = 'a', hide_on_submit = true })
      F.session.press('return')
      input.show({ text = 'b', hide_on_submit = false })
      F.session.press('return')
      assert.is_true(F.is_widget_visible())
    end)

    -- The re-ask, and it is the reason the ordering is
    -- dispose-then-notify: a callback is entitled to leave a
    -- new question behind, and it survives the flow that
    -- called it. It needs neither `force` nor a disarm now --
    -- the hide belonging to this submit has already run, so
    -- the follow-up is not standing in front of it. Both were
    -- required before, and doc/input_api.md's "Asking one
    -- question" is rewritten with this sprint.
    it('a follow-up shown from a callback survives the flow',
      function()
        local input = F.activate_project()
        input.show({
          text            = 'a',
          hide_on_submit  = true,
          on_text_entered = function()
            input.show({ prompt = 'again?' })
          end,
        })
        F.session.press('return')
        assert.is_true(F.is_widget_visible())
        assert.equal('again?', F.widget.model:get_label())
      end)

    -- The raise edge, INVERTED and ruled (owner, 2026-09-07,
    -- "let it be, documented"): the disposal has already run
    -- when the callback raises, so the widget is hidden where
    -- it used to be left standing. Asserted against the error
    -- channel, not against "no crash" -- the route boundary
    -- swallows the raise and suspends, so a silently-skipped
    -- callback would pass a has_no.errors check just as well.
    it('a raised callback leaves it hidden', function()
      local ran = 0
      local input = F.activate_project()
      input.show({
        text            = 'a',
        hide_on_submit  = true,
        on_text_entered = function()
          ran = ran + 1
          error('boom')
        end,
      })
      F.session.press('return')
      assert.equal(1, ran)
      assert.equal('snapshot', love.state.app_state)
      assert.is_false(F.is_widget_visible())
    end)

    -- A veto skips the whole flow, the after_* with it, and
    -- the flags are inside what it skips (the composition
    -- section, acceptance criterion 8). Both cancel cells are
    -- asked for, since the widget seats neither: a veto that
    -- leaked would otherwise be invisible on this verb.
    it('a before_cancel veto skips the flags and after_cancel',
      function()
        local after = false
        local input = F.activate_project()
        input.callbacks.before_cancel =
          function() return true end
        input.callbacks.after_cancel =
          function() after = true end
        input.show({
          text            = 'draft',
          clear_on_cancel = true,
          hide_on_cancel  = true,
        })
        F.session.press('escape')
        assert.is_false(after)
        assert.is_true(F.is_widget_visible())
        assert.same({ 'draft' }, F.widget:get_text())
      end)
  end)

  describe('Enter and Escape as ordinary keys', function()
    -- doc/development/internals/user_input.md, "Submit and
    -- cancel — widget-owned callback sequences":
    -- Enter/Escape are ordinary keys while
    -- hidden — no
    -- widget submit/cancel handling engages, so project
    -- handlers can run.
    it('Enter and Escape are ordinary keys while hidden',
      function()
        local seen = { }
        local input = F.activate_project()
        input.shortcuts.keypressed['return'] = function()
          seen[#seen + 1] = 'return'; return true
        end
        input.shortcuts.keypressed['escape'] = function()
          seen[#seen + 1] = 'escape'; return true
        end
        F.session.press('return')
        F.session.press('escape')
        assert.same({ 'return', 'escape' }, seen)
      end)

    -- D-EDIT-LIFECYCLE: Enter/Escape are ordinary chain
    -- participants — a project shortcut on 'return' runs first
    -- and consumes, so the widget's submit never fires (the
    -- withdrawn non-overridable guarantee; the gateway power
    -- keys remain the unshadowable safety net, not this).
    it('a shortcut on return shadows the widget submit',
      function()
        local shadowed = false
        local submitted = false
        local input = F.activate_project()
        input.shortcuts.keypressed['return'] = function()
          shadowed = true; return true
        end
        input.show({
          text = 'x',
          on_text_entered = function() submitted = true end,
        })
        F.session.press('return')
        assert.is_true(shadowed)
        assert.is_false(submitted)
        assert.is_true(F.is_widget_visible())
      end)

    -- doc/development/internals/user_input.md, "Multiline
    -- input": what the WIDGET does with Shift+Return once the
    -- event reaches it — insert a newline unconditionally, do
    -- not submit, stay open. "Unconditionally" is the widget's
    -- own internal claim (no state of its own suppresses the
    -- newline); it says nothing about whether the event can be
    -- claimed before it arrives. It can, and the case below
    -- pins that. F.session.press holds the modifier on the
    -- device as well as feeding the gateway, so the keystroke
    -- below adds nothing but the return key; it is kept as the
    -- combo driver rather than unpicked into two presses.
    it('Shift+Return unconditionally adds a line without submitting',
      function()
        F.activate_project()
        F.show_widget({ text = 'a' })
        F.session.press('lshift')
        mock.keystroke('S-return', F.session.press, false)
        assert.same({ 'a', '' }, F.widget:get_text())
        assert.is_true(F.is_widget_visible())
      end)

    -- The interceptability half of the case above. Shift+Return
    -- reaches the widget only because nothing upstream claimed
    -- it: it is an ordinary combo, so a project shortcut on
    -- 'shift+return' consumes it like any other key and no
    -- newline is inserted (doc/development/decisions/input.md,
    -- D-CHAIN-OF-3 — the route holds no unshadowable keys; the
    -- gateway power keys are the only ones a project cannot
    -- reach).
    it('a shortcut on shift+return intercepts the newline',
      function()
        local fired = false
        local input = F.activate_project()
        input.shortcuts.keypressed['shift+return'] = function()
          fired = true; return true
        end
        F.show_widget({ text = 'a' })
        F.session.press('lshift')
        mock.keystroke('S-return', F.session.press, false)
        assert.is_true(fired)
        assert.same({ 'a' }, F.widget:get_text())
      end)
  end)

  describe('hide() and force fire no cancel', function()
    -- doc/development/decisions/input.md, D-EDIT-LIFECYCLE ("hide()
    -- ... fires no cancel chain"): hide() and a force=true
    -- reconfigure fire no cancel chain (the user-facing dismiss
    -- is Escape only).
    it('hide() fires no cancel chain', function()
      local fired = false
      local input = F.activate_project()
      input.callbacks.before_cancel = function() fired = true end
      input.show({ text = 'x' })
      input.hide()
      assert.is_false(fired)
    end)

    it('a force=true reconfigure fires no cancel chain',
      function()
        local fired = false
        local input = F.activate_project()
        input.callbacks.before_cancel = function() fired = true end
        input.show({ text = 'first' })
        input.show({ force = true, text = 'second' })
        assert.is_false(fired)
      end)
  end)

  describe('the continuous session', function()
    -- doc/input_api.md, "Callback assignments": widget
    -- outputs persist across a deactivation —
    -- only project stop resets them (a later chunk), not
    -- submit.
    -- The hide is the case's own, and it has to be: the
    -- project widget clears on submit and stays shown, so a
    -- bare re-show over it is refused (D-CFG-BOUNDARY,
    -- statement 4) and the second Enter would meet an empty
    -- widget. Until the flags landed, the surviving 'a' hid
    -- that gap and the case passed without ever completing the
    -- cycle its name describes.
    it('on_text_entered persists across a hide/re-show cycle',
      function()
        local hits = 0
        local input = F.activate_project()
        input.show({
          text = 'a',
          on_text_entered = function() hits = hits + 1 end,
        })
        F.session.press('return')
        input.hide()
        input.show({ text = 'b' })
        F.session.press('return')
        assert.equal(2, hits)
      end)

    -- D-EDIT-LIFECYCLE: absent callbacks default to no-ops —
    -- submit and cancel both complete without error. What
    -- happens to the content is the INSTANCE's flags and not
    -- the callbacks: the project widget seats clear_on_submit
    -- alone, so submit empties the field and leaves it open,
    -- and Escape does nothing to either (D-LIFECYCLE-FLAGS,
    -- statement 3). A widget seating nothing at all is inert
    -- on both verbs — that case is below, against a bare
    -- widget rather than against this host.
    it('submit and cancel complete with no callbacks set ' ..
      '(the flags decide)', function()
        F.activate_project()
        F.show_widget({ text = 'x' })
        assert.has_no.errors(function()
          F.session.press('return')
        end)
        assert.is_true(F.is_widget_visible())
        assert.is_true(F.widget:is_empty())
        F.show_widget({ text = 'y', force = true })
        assert.has_no.errors(function()
          F.session.press('escape')
        end)
        assert.is_true(F.is_widget_visible())
        assert.same({ 'y' }, F.widget:get_text())
      end)

    -- Submit leaves the widget shown, so hiding it is the
    -- project's to do and after_submit is where it does it.
    -- Asserted in that direction on purpose: the case that
    -- asserted the OPPOSITE — re-show from after_submit, then
    -- check the widget is shown — could not fail, because a
    -- submit no longer hides and the assertion held whether or
    -- not the callback ran at all. Proven by mutation: deleting
    -- the callback assignment left the whole file green.
    it('after_submit is what hides the widget', function()
      local input = F.activate_project()
      local seen = { }
      input.callbacks.after_submit = function() input.hide() end
      input.show({
        prompt = 'first',
        on_text_entered = function(t) seen[#seen + 1] = t end,
      })
      F.session.type('a')
      F.session.press('return')
      assert.same({ 'a' }, seen)
      assert.is_false(F.widget:is_shown())
      assert.is_false(F.is_widget_visible())
    end)

    -- The control the pair needs: WITHOUT a closing callback
    -- the widget stays shown. Together the two cases pin the
    -- default and the override; either alone pins neither.
    it('and without it the widget stays shown', function()
      local input = F.activate_project()
      input.show({ prompt = 'first' })
      F.session.type('a')
      F.session.press('return')
      assert.is_true(F.widget:is_shown())
    end)

    -- The re-show re-arms with the STICKY callback — a
    -- second submit is observed without re-passing
    -- on_text_entered, proving the loop can repeat (the
    -- shape every migrated example's re-show depends on).
    it('the re-armed session observes a second submit',
      function()
        local input = F.activate_project()
        local seen = { }
        -- The idiom (D-EDIT-LIFECYCLE): the widget stays
        -- shown;
        -- the project clears between prompts from after_submit.
        input.callbacks.after_submit = function() input.clear() end
        input.show({
          on_text_entered = function(t)
            seen[#seen + 1] = t
          end,
        })
        F.session.type('a')
        F.session.press('return')
        assert.is_true(F.is_widget_visible())
        assert.is_true(F.widget:is_empty())
        F.session.type('b')
        F.session.press('return')
        assert.is_true(F.is_widget_visible())
        assert.is_true(F.widget:is_empty())
        assert.same({ 'a', 'b' }, seen)
      end)

    -- Balloons shape (doc/input_api.md, "Live changes",
    -- "A continuous session with a changing prompt"): a
    -- hint set via configure()
    -- INSIDE on_text_entered (session still active,
    -- doc/development/internals/user_input.md, "Submit
    -- and cancel — widget-owned callback sequences")
    -- must survive the after_submit bare re-show, not the
    -- show()-time prompt: configure_core's custom_label is
    -- only overwritten
    -- when cfg.prompt is given, so a bare show({}) never
    -- resets what configure() just set.
    it('a prompt configured inside on_text_entered ' ..
      'survives the after_submit re-show', function()
      local input = F.activate_project()
      input.callbacks.after_submit = function() input.show({}) end
      input.show({
        prompt = 'first',
        on_text_entered = function()
          input.configure({ prompt = 'live' })
        end,
      })
      F.session.type('a')
      F.session.press('return')
      assert.equal('live', F.widget.model:get_label())
      assert.is_true(F.is_widget_visible())
    end)
  end)

  -- One lifecycle — `submit_flow` / `cancel_flow` — serves the
  -- console line, the editor's input and the project's widget
  -- alike, and no instance reads the screen mode to decide what
  -- a key does (doc/development/decisions/input.md,
  -- D-EDIT-LIFECYCLE). A surface that needs to differ says so
  -- locally: the editor consumes Enter/Escape upstream.
  --
  -- The repetition below IS the claim — same two keys, same
  -- lifecycle, three surfaces — and it guards against that
  -- uniformity being quietly re-conditioned on global state.
  -- Two narrow method patches stand where the seam IS the call:
  -- the console's evaluate_input count, and model:cancel not
  -- running under the editor's Escape.
  describe('the same lifecycle on every route #lifecycle', function()
    -- A standalone widget, not the shared one — direct
    -- construction, like user_input_view_spec.lua.
    local function bare_uic()
      local m = UserInputModel(F.cfg, InputEvalText)
      local c = UserInputController(m)
      c:init_view({
        render = function() end,
        draw   = function() end,
      })
      return c
    end

    -- keypressed-only driver: mock.keystroke calls
    -- press(k, scancode, isrepeat); controllers here only
    -- care about k.
    local function driver(ctrl)
      return function(k) ctrl:keypressed(k) end
    end

    -- Open a plaintext doc in the REAL wired editor (F.editor),
    -- mirroring ConsoleController:edit's own app_state flip.
    local function open_doc(lines)
      love.state.app_state = 'editor'
      local save = TU.get_save_function(lines)
      F.editor:open('doc.txt', lines, save)
      return F.editor
    end

    -- ---- 1. the lifecycle ignores the screen mode ----------

    describe('a widget does not read the screen mode',
      function()
      -- The clearest statement of the rule: a plain widget,
      -- owned by nobody, behaves identically no matter what
      -- love.state.app_state happens to say. Screen mode picks
      -- which ROUTE receives an event; it never changes what
      -- the widget does with one.
      it('plain Enter submits, plain Escape cancels', function()
        local c = bare_uic()
        love.state.app_state = 'editor'
        local submitted = 0
        local canceled = 0
        c:show({
          text = 'hello',
          on_text_entered = function() submitted = submitted + 1 end,
        })
        c.callbacks.after_cancel = function()
          canceled = canceled + 1
        end

        mock.keystroke('return', driver(c))
        assert.equal(1, submitted)

        mock.keystroke('escape', driver(c))
        assert.equal(1, canceled)
      end)

      -- The class default, pinned against a widget owned by
      -- nobody rather than inferred from a host that seats its
      -- own cells: no flags and no callbacks means both verbs
      -- complete and NOTHING happens to the content
      -- (doc/development/decisions/input.md, D-LIFECYCLE-FLAGS,
      -- statement 3, and acceptance criterion 3).
      it('with no flags and no callbacks it is inert on both',
        function()
        local c = bare_uic()
        c:show({ text = 'hello' })

        mock.keystroke('return', driver(c))
        assert.same({ 'hello' }, c:get_text())
        assert.is_true(c:is_shown())

        mock.keystroke('escape', driver(c))
        assert.same({ 'hello' }, c:get_text())
        assert.is_true(c:is_shown())
      end)
    end)

    -- ---- 2. the editor's own meaning for Escape ------------

    -- Escape in the editor's navigation mode USED to mean
    -- "load the selected line into the input", and the editor
    -- consumed it so the widget's cancel_flow never ran. The
    -- upstream editor rework moved the load onto Enter and
    -- typing (its spec 2.2) and gave Shift+Esc the discard, so
    -- bare Escape is claimed by nothing in navigation and
    -- reaches the widget, where it is an ordinary cancel.
    -- That is the chain behaving exactly as D-CHAIN-OF-3 says
    -- it should — an unclaimed key falls through — but it is
    -- ALSO a behaviour this branch did not choose, so it is
    -- registered: technical_debt/input.md, "Bare Escape in the
    -- editor's navigation mode now runs the widget's cancel".
    --
    -- The editor spec gives bare Escape to the editor: it
    -- aborts the edit at once (IS5.7), so the key no longer
    -- falls through to the widget's cancel flow.
    describe('editor Escape is the editor\'s own (IS5.7)',
      function()
      it('is claimed by the editor and aborts the edit',
        function()
        local doc = { 'first line', 'second line', '' }
        local ed  = open_doc(doc)
        local model = ed.input.model
        local canceled = false
        local reached = false
        local orig_cancel = model.cancel
        model.cancel = function(...)
          canceled = true
          return orig_cancel(...)
        end
        ed.input.callbacks.after_cancel = function()
          reached = true
        end
        ed.input:set_text('typed')

        mock.keystroke('up', driver(ed))
        mock.keystroke('escape', driver(ed))

        --- the editor claims bare Escape: it aborts the edit
        --- (IS5.7), and the widget's cancel flow never runs
        assert.is_false(reached)
        assert.is_false(canceled)
        assert.is_true(ed.input:is_empty())
        model.cancel = orig_cancel
        ed.input.callbacks.after_cancel = nil
      end)

      -- The other half of the same seam: Shift+Escape has no
      -- meaning in the editor, and the editor consumes it, so
      -- it must not reach the widget as a cancel.
      it('but Shift+Escape is claimed and does not', function()
        local doc = { 'first line', 'second line', '' }
        local ed  = open_doc(doc)
        local model = ed.input.model
        local canceled = false
        local orig_cancel = model.cancel
        model.cancel = function(...)
          canceled = true
          return orig_cancel(...)
        end

        mock.keystroke('up', driver(ed))
        mock.keystroke('S-escape', driver(ed))

        assert.is_false(canceled)
        model.cancel = orig_cancel
      end)
    end)

    -- ---- 3. the editor's own meaning for Enter -------------

    -- Same shape as Escape above: Enter (plain or with Ctrl)
    -- applies the edit to the buffer, and the editor consumes
    -- it, so the submission is delivered once — to the editor —
    -- and never a second time through the widget's
    -- on_text_entered.
    describe('editor Enter submits to the editor alone',
      function()
        it('plain Enter applies the edit, no on_text_entered',
          function()
            local doc = { '', 'body', '' }
            local ed  = open_doc(doc)
            local fired = false
            ed.input.callbacks.on_text_entered =
              function() fired = true end

            mock.keystroke('up', driver(ed))
            ed.input:add_text('replaced')
            mock.keystroke('return', driver(ed))

            assert.is_false(fired)
            assert.is_true(ed.input:is_empty())
          end)

        it('Ctrl+Enter applies the edit, no on_text_entered',
          function()
            local doc = { '', 'body', '' }
            local ed  = open_doc(doc)
            local fired = false
            ed.input.callbacks.on_text_entered =
              function() fired = true end

            ed.input:add_text('inserted')
            mock.keystroke('C-return', driver(ed))

            assert.is_false(fired)
          end)
      end)

    -- ---- 4. Alt+Enter breaks a line in the editor ----------

    -- The editor principles' IS3.15: Alt+Enter, like
    -- Shift+Enter, breaks the line at the cursor and submits
    -- nothing: the file and the widget's submit callbacks are
    -- left alone.
    describe('editor Alt+Enter', function()
      it('breaks the line and submits nothing', function()
        local doc = { 'first line', 'second line', '' }
        local ed  = open_doc(doc)
        local entered = false
        ed.input.callbacks.on_text_entered = function()
          entered = true
        end
        ed:textinput('a')
        ed:textinput('b')
        mock.keystroke('left', driver(ed))

        mock.keystroke('M-return', driver(ed))

        assert.same({ 'a', 'b' }, ed.input:get_text():items())
        assert.is_false(entered)
        ed.input.callbacks.on_text_entered = nil
      end)
    end)

    -- ---- 5. Shift+Enter is a newline everywhere ------------

    -- Shift+Enter is carved out of submit in every surface: it
    -- inserts a line-feed and never submits, including inside
    -- the editor's input, where the surrounding Enter variants
    -- are claimed by the editor.
    describe('editor Shift+Enter on non-empty input', function()
      it('inserts a line-feed instead of submitting', function()
        local doc = { '', 'body', '' }
        local ed  = open_doc(doc)

        ed.input:add_text('abc')
        mock.keystroke('S-return', driver(ed))

        assert.same({ 'abc', '' }, ed.input:get_text():items())
      end)
    end)

    -- ---- 6. the same two keys in the other two surfaces ----

    -- The uniformity claim in its plainest form: after the
    -- editor cases above, the console and the project widget
    -- are driven through the same Enter and Escape. Their
    -- subject-matter contracts (the full submit call-order
    -- chain, the cancel chain, validators) belong to this
    -- file's 'submit' and 'cancel — the Escape chain' groups;
    -- what is asserted here is only that each surface runs the
    -- one lifecycle at all.
    describe('console: the same Enter and Escape', function()
      it('Enter evaluates the line exactly once, text intact',
        function()
          local calls, seen = 0, nil
          local orig = F.cc.evaluate_input
          F.cc.evaluate_input = function(self, ...)
            calls = calls + 1
            seen = self.input:get_text():items()
            return orig(self, ...)
          end

          F.console:add_text('1')
          mock.keystroke('return', F.session.press)

          assert.equal(1, calls)
          assert.same({ '1' }, seen)
          F.cc.evaluate_input = orig
        end)

      it('Escape clears the console line', function()
        F.console:add_text('abc')
        mock.keystroke('escape', F.session.press)
        assert.is_true(F.console:is_empty())
      end)
    end)

    describe('project widget: the same Enter and Escape',
      function()
      it('Enter submits, Escape cancels', function()
        local input = F.activate_project()
        local got
        input.show({
          text = 'hi',
          on_text_entered = function(t) got = t end,
        })
        F.session.press('return')
        assert.equal('hi', got)

        input.show({ text = 'bye', force = true })
        F.session.press('escape')
        -- The project widget's own seating: the cancel chain
        -- runs and neither cell is seated, so nothing visible
        -- happens (D-LIFECYCLE-FLAGS, statement 3).
        assert.is_true(F.is_widget_visible())
        assert.same({ 'bye' }, F.widget:get_text())
      end)
    end)

    -- ---- 8. how wide "Enter" is -----------------------------

    -- Only a bare Enter submits: every chord is its own key,
    -- and nothing binds Ctrl+Enter (the maintainer's ruling of
    -- November 14, 2026, which narrowed D-DEFACTO-KEPT's
    -- breadth on purpose; doc/development/decisions/input.md)
    describe('only a bare Enter submits', function()
        it('input widget: Ctrl+Enter does nothing', function()
          local input = F.activate_project()
          local got
          input.show({
            text = 'hi',
            on_text_entered = function(t) got = t end,
          })
          mock.keystroke('C-return', F.session.press)
          assert.is_nil(got)
          assert.equal('hi', input.get_text())
        end)

        -- the editor principles' IS3.15 took Alt+Enter out of
        -- the breadth: it breaks the line, as Shift+Enter does
        it('input widget: Alt+Enter breaks the line', function()
          local input = F.activate_project()
          local got
          input.show({
            text = 'hi',
            on_text_entered = function(t) got = t end,
          })
          mock.keystroke('M-return', F.session.press)
          assert.is_nil(got)
          assert.equal('hi\n', input.get_text())
        end)

        it('console: Ctrl+Enter does not evaluate', function()
          local calls = 0
          local orig = F.cc.evaluate_input
          F.cc.evaluate_input = function(self, ...)
            calls = calls + 1
            return orig(self, ...)
          end

          F.console:add_text('x')
          mock.keystroke('C-return', F.session.press)

          assert.equal(0, calls)
          F.cc.evaluate_input = orig
        end)
      end)
  end)
end)
