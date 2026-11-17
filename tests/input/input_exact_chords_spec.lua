-- Every chord is its own key (the maintainer's ruling of
-- November 14, 2026) in the console and in the shared text
-- field a program's input uses: a key with a modifier no
-- table binds does nothing. Ctrl+Z and Ctrl+Y are the draft's
-- undo and redo in every field, and Ctrl+Y no longer deletes
-- a line (PR #28, D-UNDO-KEYS). Keys only, through the K
-- helper and the production gateway.

local F = require("tests.helpers.input_fixture")
local K = require("tests.helpers.editor_keys")
local ConsoleKeys = require("model.input.consoleKeys")
local EditorKeys = require("model.editor.editorKeys")
local FieldKeys = require("model.input.fieldKeys")
local Keys = require("tests.helpers.surface_keys")

describe("every chord is its own key #input", function()
  after_each(K.cleanup)

  describe("in the console", function()
    --- a line in the history, and "y" typed after it
    local function console()
      K.reset()
      K.type("held = 1")
      K.keys("return")
      K.type("y")
    end
    local function snapshot()
      local l, c = K.cc.input:get_cursor_pos()
      return {
        draft = K.console_draft(),
        cursor = { l, c },
        error = K.cc.input:has_error(),
        app = K.app_state(),
        text = K.console_text(),
      }
    end

    it("Ctrl+Up and Ctrl+Down neither move the cursor nor recall",
      function()
        console()
        local before = snapshot()
        K.keys("lctrl", "up")
        assert.same(before, snapshot())
        K.keys("lctrl", "down")
        assert.same(before, snapshot())
        K.keys("up")
        assert.same("held = 1", K.console_draft())
      end)

    it("Ctrl+Delete deletes nothing", function()
      console()
      K.keys("home")
      local before = snapshot()
      K.keys("lctrl", "delete")
      assert.same(before, snapshot())
    end)

    it("every bound key with one more modifier that the table "
        .. "does not bind does nothing", function()
      local chords = Keys.unbound_neighbours(
        Keys.bound(ConsoleKeys, "idle"))
      assert.is_true(#chords > 20)
      for _, c in ipairs(chords) do
        console()
        local before = snapshot()
        K.keys(unpack(c[2]))
        assert.same(before, snapshot(), c[1])
      end
    end)

    it("Ctrl+Z undoes the line's typing and Ctrl+Y redoes it",
      function()
        K.reset()
        K.type("one two")
        K.keys("lctrl", "z")
        assert.same("one", K.console_draft())
        K.keys("lctrl", "z")
        assert.same("", K.console_draft())
        K.keys("lctrl", "y")
        assert.same("one", K.console_draft())
      end)

    it("Ctrl+Y deletes no line", function()
      K.reset()
      K.type("keep me")
      K.keys("lctrl", "y")
      assert.same("keep me", K.console_draft())
    end)

    it("a recalled line is no step to undo", function()
      K.reset()
      K.type("held = 2")
      K.keys("return")
      K.keys("up")
      assert.same("held = 2", K.console_draft())
      K.keys("lctrl", "z")
      assert.same("held = 2", K.console_draft())
    end)

    for _, live in ipairs({ false, true }) do
      it("the card lists every key the console takes, "
          .. (live and "a program live" or "no program"),
        function()
          local KeyCard = require("model.editor.keyCard")
          local state = live and "live" or "idle"
          -- the labels the tables' chords need, not the card's
          -- own rows: a key added without words is missing here
          local want, missing = Keys.inventory(ConsoleKeys, state)
          assert.same({ }, missing)
          local lines = KeyCard.lines_of(
            KeyCard.console_cells(live), 17, 64)
          assert.same(want, Keys.shown(lines, want))
        end)
    end
  end)

  describe("in a program's input field", function()
    local widget, sent, cancelled
    before_each(function()
      K.reset()
      local input = F.activate_project()
      sent, cancelled = 0, 0
      input.callbacks.on_text_entered = function()
        sent = sent + 1
      end
      input.callbacks.after_cancel = function()
        cancelled = cancelled + 1
      end
      widget = F.show_widget({ text = "" })
    end)
    local function text()
      return table.concat(widget:get_text(), "\n")
    end

    it("Ctrl+Z and Ctrl+Y undo and redo the typing", function()
      K.type("one two")
      K.keys("lctrl", "z")
      assert.same("one", text())
      K.keys("lctrl", "y")
      assert.same("one two", text())
    end)

    it("Ctrl+Y deletes no line", function()
      K.type("keep")
      K.keys("lctrl", "y")
      assert.same("keep", text())
    end)

    for _, c in ipairs({
      { "Ctrl+Enter", { "lctrl", "return" } },
      { "Ctrl+Up", { "lctrl", "up" } },
      { "Ctrl+Delete", { "lctrl", "delete" } },
      { "Shift+Delete", { "lshift", "delete" } },
      { "Alt+Up", { "lalt", "up" } },
      { "Shift+Escape", { "lshift", "escape" } },
      { "Alt+Escape", { "lalt", "escape" } },
    }) do
      it(c[1] .. " does nothing", function()
        K.type("xy")
        K.keys("lshift", "return")
        K.type("ab")
        K.keys("left")
        local l, col = widget:get_cursor_pos()
        K.keys(unpack(c[2]))
        assert.same("xy\nab", text())
        assert.same({ l, col }, { widget:get_cursor_pos() })
        assert.same(0, sent)
        assert.same(0, cancelled)
      end)
    end

    it("Enter and Escape act", function()
      K.type("ab")
      K.keys("escape")
      assert.same(1, cancelled)
      K.keys("return")
      assert.same(1, sent)
    end)
  end)

  describe("the tables", function()
    -- which keys repeat while held (the maintainer's ruling of
    -- November 16, 2026: a held key repeats, each reaching a
    -- natural stop), for the keys whose repeat no key test can
    -- tell from a press: a second F2, Alt+F or Ctrl+L changes
    -- nothing the first did not. Once per press: what the
    -- specification says (a program field's Enter, API2.2) and
    -- what has no natural stop (the console's Enter, Shift+Ins,
    -- Ctrl+Ins), and the help key
    local ONCE = {
      { EditorKeys, { "shift+insert", "ctrl+insert", "escape",
        "ctrl+j", "f1", "f5" } },
      { ConsoleKeys, { "return", "kpenter", "f1" } },
      { FieldKeys, { "return", "kpenter" } },
    }
    local REPEATS = {
      { EditorKeys, { "up", "ctrl+down", "pagedown", "pageup",
        "ctrl+z", "ctrl+y", "return", "kpenter", "f2",
        "ctrl+delete", "alt+up", "alt+down", "alt+f", "home",
        "end", "ctrl+g" } },
      { ConsoleKeys, { "up", "down", "escape", "ctrl+l" } },
      { FieldKeys, { "shift+return", "alt+return", "left",
        "ctrl+right", "home", "ctrl+end", "up", "backspace",
        "shift+backspace", "delete", "ctrl+backspace", "ctrl+w",
        "ctrl+k", "alt+shift+up", "ctrl+z",
        "ctrl+y", "escape" } },
    }
    it("say which keys act once and which repeat", function()
      for _, set in ipairs({ { ONCE, false }, { REPEATS, true } })
      do
        for _, group in ipairs(set[1]) do
          for _, chord in ipairs(group[2]) do
            local found = false
            for st, t in pairs(group[1].tables) do
              local e = t[chord]
              if e then
                found = true
                assert.same(set[2], e.repeats, st .. ": " .. chord)
              end
            end
            assert.is_true(found, chord)
          end
        end
      end
    end)

    -- a 'field' entry hands its key to the shared field, which
    -- must name it, as the surface sets the field up
    it("give the field only chords it names", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      local function check(keys, field)
        for st, t in pairs(keys.tables) do
          for chord, e in pairs(t) do
            if e.act == "field" then
              assert.is_truthy(field:names(chord),
                st .. ": " .. chord)
            end
          end
        end
      end
      check(EditorKeys, K.ed.input)
      check(ConsoleKeys, K.cc.input)
    end)
  end)
end)
