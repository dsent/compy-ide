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

local MOD_KEYS = { ctrl = "lctrl", alt = "lalt", shift = "lshift" }
local ORDER = { "ctrl", "alt", "shift" }

--- the gate's own chords, and the help key: not the tables'
local RESERVED = {
  ["ctrl+escape"] = true, ["ctrl+t"] = true, ["ctrl+q"] = true,
  ["ctrl+pause"] = true, ["ctrl+alt+r"] = true,
  ["ctrl+alt+p"] = true, ["ctrl+alt+shift+p"] = true,
  f10 = true,
}

--- Every chord of a table with one more modifier, which the
--- table does not bind: { name, keys for K.keys }
local function unbound_neighbours(t)
  local out, seen = { }, { }
  for chord in pairs(t) do
    local mods, trigger = { }, nil
    for part in chord:gmatch("[^+]+") do
      if MOD_KEYS[part] then mods[part] = true else trigger = part end
    end
    for _, m in ipairs(ORDER) do
      if not mods[m] and trigger ~= "f1" then
        local names, keys = { }, { }
        for _, o in ipairs(ORDER) do
          if mods[o] or o == m then
            names[#names + 1] = o
            keys[#keys + 1] = MOD_KEYS[o]
          end
        end
        names[#names + 1] = trigger
        keys[#keys + 1] = trigger
        local name = table.concat(names, "+")
        if not t[name] and not RESERVED[name] and not seen[name]
        then
          seen[name] = true
          out[#out + 1] = { name, keys }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

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

    it("Ctrl+Up and Ctrl+Down neither move nor recall",
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

    it("Ctrl+Delete and Ctrl+Backspace delete nothing",
      function()
        console()
        K.keys("home")
        local before = snapshot()
        K.keys("lctrl", "delete")
        K.keys("end")
        K.keys("lctrl", "backspace")
        before.cursor = { 1, 2 }
        assert.same(before, snapshot())
      end)

    it("every bound key with one more modifier that the table "
        .. "does not bind does nothing", function()
      local chords =
          unbound_neighbours(ConsoleKeys.tables.idle)
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
      it("the card lists exactly the table's keys with words, "
          .. (live and "a program live" or "no program"),
        function()
          local KeyCard = require("model.editor.keyCard")
          local state = live and "live" or "idle"
          local want = { }
          for _, row in ipairs(ConsoleKeys:card_rows(state)) do
            want[row[1]] = row[2]
          end
          local got = { }
          for _, c in ipairs(KeyCard.console_cells(live)) do
            if c.key then got[c.key] = c.what end
          end
          assert.same(want, got)
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
      { "Ctrl+Backspace", { "lctrl", "backspace" } },
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
    -- which keys repeat while held (the ruling of November
    -- 14, 2026), for the keys whose repeat no key test can tell
    -- from a press: a second F2, Ctrl+Shift+F or Ctrl+L changes
    -- nothing the first did not
    local ONCE = {
      { EditorKeys, { "return", "kpenter", "escape", "f2",
        "shift+insert", "ctrl+insert", "alt+up", "alt+down",
        "ctrl+shift+f", "ctrl+shift+s", "ctrl+j", "ctrl+q", "f1",
        "f5" } },
      { ConsoleKeys, { "return", "escape", "shift+insert",
        "ctrl+l", "ctrl+q", "f1" } },
    }
    local REPEATS = {
      { EditorKeys, { "shift+return", "alt+return", "up",
        "ctrl+down", "pagedown", "alt+pageup", "alt+left",
        "ctrl+right", "home", "backspace", "ctrl+backspace",
        "ctrl+delete", "shift+delete", "ctrl+z", "ctrl+y",
        "ctrl+w", "ctrl+k", "ctrl+d" } },
      { ConsoleKeys, { "shift+return", "up", "pageup", "alt+up",
        "shift+left", "delete", "ctrl+z", "ctrl+y" } },
    }
    it("say which keys act once and which repeat", function()
      for _, set in ipairs({ { ONCE, false }, { REPEATS, true } })
      do
        for _, group in ipairs(set[1]) do
          for st, t in pairs(group[1].tables) do
            for _, chord in ipairs(group[2]) do
              local e = t[chord]
              if e then
                assert.same(set[2], e.repeats, st .. ": " .. chord)
              end
            end
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
              assert.is_true(field:names(chord), st .. ": " .. chord)
            end
          end
        end
      end
      check(EditorKeys, K.ed.input)
      check(ConsoleKeys, K.cc.input)
    end)
  end)
end)
