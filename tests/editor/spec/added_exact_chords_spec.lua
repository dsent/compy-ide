-- Every chord is its own key (the maintainer's ruling of
-- November 14, 2026): in each of the file editor's states a
-- key with a modifier its tables do not bind does nothing,
-- and the key card lists every key the editor takes. The card
-- suspends the reserved chords in the editor alone, and a
-- click on a block no longer browses (PR #28, D-MOUSE-BROWSE).
-- Keys only, through tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local F = require("tests.helpers.input_fixture")
local EditorKeys = require("model.editor.editorKeys")
local Keys = require("tests.helpers.surface_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it

local FILE = "a = 1\nb = 2\n"

--- Reach `state` on block 1 of FILE.
local REACH = {
  browsing = function() K.browse_to(1) end,
  inserting = function()
    K.browse_to(1)
    K.type("x = 3")
  end,
  replacing = function()
    K.browse_to(1)
    K.keys("f2")
  end,
}

local function reach(state)
  K.reset({ ["main.lua"] = FILE })
  K.open()
  REACH[state]()
  assert.same(state, K.state())
end

--- Everything a key could change, as one value.
local function snapshot()
  return {
    app = K.app_state(),
    file = K.file(),
    draft = K.draft(),
    state = K.state(),
    position = K.position(),
    cursor = { K.cursor() },
    message = K.message(),
    writes = #K.writes(),
  }
end

--- Every chord the editor's tables take in `state` with one
--- more modifier that none of them binds
local function unbound_neighbours(state)
  return Keys.unbound_neighbours(Keys.bound(EditorKeys, state))
end

describe("every chord is its own key #editor #spec", function()
  after_each(K.cleanup)

  describe("a bound key with another modifier", function()
    for _, c in ipairs({
      { "browsing", "Ctrl+Enter", { "lctrl", "return" } },
      { "inserting", "Ctrl+Enter", { "lctrl", "return" } },
      { "replacing", "Ctrl+Enter", { "lctrl", "return" } },
      { "browsing", "Alt+F2", { "lalt", "f2" } },
      { "replacing", "Shift+Escape", { "lshift", "escape" } },
      { "inserting", "Ctrl+Shift+Up", { "lctrl", "lshift", "up" } },
    }) do
      spec_it("IS3.11 Preserve state on refusal: " .. c[2]
          .. " does nothing while " .. c[1], function()
        reach(c[1])
        local before = snapshot()
        K.keys(unpack(c[3]))
        assert.same(before, snapshot())
      end)
    end

    for _, state in ipairs({ "browsing", "inserting",
      "replacing" }) do
      spec_it("IS3.11 Preserve state on refusal: while " .. state
          .. ", every bound key with one more modifier that the "
          .. "table does not bind does nothing", function()
        local chords = unbound_neighbours(state)
        assert.is_true(#chords > 20)
        for _, c in ipairs(chords) do
          reach(state)
          local before = snapshot()
          K.keys(unpack(c[2]))
          assert.same(before, snapshot(), c[1])
        end
      end)
    end
  end)

  describe("the key card", function()
    for _, state in ipairs({ "browsing", "inserting",
      "replacing" }) do
      spec_it("IS3.16 Show the key card: while " .. state
          .. ", the card lists every key the editor takes",
        function()
          -- the labels the tables' chords need, not the card's
          -- own rows: a key added without words is missing here
          local want, missing = Keys.inventory(EditorKeys, state,
            state == "browsing")
          assert.same({ }, missing)
          reach(state)
          K.hold("f1")
          local lines = K.key_card()
          K.release("f1")
          assert.same(want, Keys.shown(lines, want))
        end)
    end
  end)

  describe("the reserved chords under the card", function()
    spec_it("IS3.16 Show the key card: Ctrl+Q waits while the "
        .. "editor's card shows", function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.hold("f1")
      K.keys("lctrl", "q")
      K.release("f1")
      assert.same("editor", K.app_state())
      K.keys("lctrl", "q")
      assert.same("ready", K.app_state())
    end)

    -- in the console as in the editor (the maintainer's ruling
    -- of November 16): every other key does nothing under the
    -- card, Ctrl+Escape apart
    spec_it("IS3.16 Show the key card: in the console the "
        .. "reserved chords wait while its card shows", function()
      K.reset({ ["main.lua"] = "function love.update() end\n" })
      K.type("ab")
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      for _, c in ipairs({ "t", "r", "q" }) do
        K.keys("lctrl", c)
        assert.same("ready", K.app_state(), c)
        assert.is_falsy(K.cc.run_live, c)
      end
      K.release("f1")
      assert.same("ab", K.console_draft())
    end)

    spec_it("IS3.16 Show the key card: a program idling behind "
        .. "the console's card gets no key under it", function()
      K.reset({ ["main.lua"] = table.concat({
        "KEYS = {}",
        "compy.input.hooks.keypressed = function(k)",
        "  KEYS[#KEYS + 1] = k",
        "end",
        "compy.input.hooks.textinput = function(t)",
        "  KEYS[#KEYS + 1] = t",
        "end",
        "compy.input.hooks.mousepressed = function() end",
      }, "\n") .. "\n" })
      K.keys("lctrl", "r")
      assert.same("ready", K.app_state())
      assert.is_true(K.cc.run_live)
      local keys = K.cc:get_project_env().KEYS
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      local before = #keys
      K.type("x")
      K.keys("left")
      K.keys("lctrl", "q")
      K.release("f1")
      assert.same(before, #keys)
      assert.is_true(K.cc.run_live)
    end)

    spec_it("IS3.16 Show the key card: Ctrl+Escape asks to quit "
        .. "while the console's card shows", function()
      K.reset()
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      F.quits()
      K.keys("lctrl", "escape")
      assert.same(1, #F.quits())
      K.release("f1")
    end)

    -- a program that runs with no key handler of its own lets
    -- F1 fall through to the console, whose card then shows
    spec_it("IS3.16 Show the key card: over a running program "
        .. "that leaves F1 to the console, Ctrl+Q waits for F1's "
        .. "release", function()
      K.reset({ ["main.lua"] = "function love.update() end\n" })
      K.type("run()")
      K.keys("return")
      assert.same("running", K.app_state())
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      K.keys("lctrl", "q")
      assert.same("running", K.app_state())
      K.release("f1")
      K.keys("lctrl", "q")
      assert.same("ready", K.app_state())
      assert.is_false(K.cc.run_live)
    end)
  end)

  -- with the editor's mouse switched on, as it ships
  -- (cfg.editor.mouse_enabled in main.lua)
  describe("the mouse", function()
    local cfg
    before_each(function()
      K.reset({ ["main.lua"] = FILE })
      cfg = K.cc.cfg.editor
      K.cc.cfg.editor = { mouse_enabled = true }
    end)
    after_each(function() K.cc.cfg.editor = cfg end)

    local function click(x, y, presses)
      F.session.mousepressed(x, y, 1, false, presses or 1)
      F.session.mousereleased(x, y, 1, false, presses or 1)
      K.frame()
    end
    local function view()
      return K.ed.input.model.cfg.view
    end

    spec_it("IS2.1 Browse blocks: a click or a double click "
        .. "on a block changes nothing", function()
      K.open()
      K.browse_to(2)
      local before = snapshot()
      local v = view()
      -- the first row is block 1's
      click(v.fw * 2, v.fh * 0.5)
      assert.same(before, snapshot())
      click(v.fw * 2, v.fh * 0.5, 2)
      assert.same(before, snapshot())
    end)

    -- as in every field (the ruling of November 14, 2026)
    spec_it("IS3.8 Position the text cursor: a click in the "
        .. "draft places the cursor there", function()
      K.open()
      K.type("abcdef")
      local before = snapshot()
      local v = view()
      click(v.fw * 2.2, v.h - v.fh * 0.5)
      before.cursor = { 1, 3 }
      assert.same(before, snapshot())
    end)
  end)
end)
