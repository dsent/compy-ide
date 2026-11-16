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
    -- a key pressed under the card is dropped, not deferred:
    -- releasing F1 delivers nothing
    spec_it("IS3.16 Show the key card: Ctrl+Q pressed while the "
        .. "editor's card shows does nothing, then or when F1 is "
        .. "released", function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.hold("f1")
      K.keys("lctrl", "q")
      K.release("f1")
      assert.same("editor", K.app_state())
      K.keys("lctrl", "q")
      assert.same("ready", K.app_state())
    end)

    spec_it("IS3.16 Show the key card: Ctrl+Q pressed under the "
        .. "card and still held when F1 is released does nothing "
        .. "on its repeats", function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.hold("f1")
      K.hold("lctrl")
      K.hold("q")
      K.release("f1")
      K.repeat_key("q")
      K.repeat_key("q")
      K.release("q")
      K.release("lctrl")
      assert.same("editor", K.app_state())
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
      K.start()
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

    -- the review's program (round 4): it writes a file when X
    -- is released. A key the card dropped has its release and
    -- its repeats dropped too, whenever they come; a key pressed
    -- before the card gets its release, so that no program sees
    -- a press without its release.
    local RELEASES = table.concat({
      "SEEN = {}",
      "function love.keyreleased(k)",
      "  SEEN[#SEEN + 1] = 'up ' .. k",
      "  if k == 'x' then writefile('answer.txt', 'x') end",
      "end",
      "compy.input.hooks.keypressed = function(k, _, isr)",
      "  SEEN[#SEEN + 1] = (isr and 'again ' or 'down ') .. k",
      "end",
      "compy.input.hooks.textinput = function(t)",
      "  SEEN[#SEEN + 1] = 'text ' .. t",
      "end",
    }, "\n") .. "\n"

    local function behind_card()
      K.reset({ ["main.lua"] = RELEASES })
      K.start()
      assert.same("ready", K.app_state())
      assert.is_true(K.cc.run_live)
      local seen = K.cc:get_project_env().SEEN
      return seen, #seen
    end

    spec_it("IS3.16 Show the key card: a key pressed and released "
        .. "under the console's card reaches no program behind it",
        function()
      local seen, n = behind_card()
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      K.keys("x")
      K.release("f1")
      assert.is_nil(K.file("answer.txt"))
      assert.same({ "up f1" }, { unpack(seen, n + 2) })
    end)

    spec_it("IS3.16 Show the key card: a key pressed under the "
        .. "card has its repeats and its release dropped after "
        .. "the card", function()
      local seen, n = behind_card()
      K.hold("f1")
      K.hold("x")
      K.release("f1")
      -- a held key's repeat brings its glyph again; text
      -- carries no key and goes on once the card is gone (the
      -- known limit), while the key's own events stay dropped
      K.repeat_key("x")
      F.session.type("x")
      K.release("x")
      assert.is_nil(K.file("answer.txt"))
      assert.same({ "up f1", "text x" }, { unpack(seen, n + 2) })
    end)

    spec_it("IS3.16 Show the key card: a key pressed before the "
        .. "card gets its release under it", function()
      local seen, n = behind_card()
      K.hold("x")
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      K.release("x")
      K.release("f1")
      assert.same({ "down x", "down f1", "up x", "up f1" },
        { unpack(seen, n + 1) })
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
        .. "that leaves F1 to the console, Ctrl+Q under the card "
        .. "does nothing", function()
      K.reset({ ["main.lua"] = "function love.update() end\n" })
      K.type("run()")
      K.keys("return")
      assert.same("running", K.app_state())
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      K.keys("lctrl", "q")
      assert.same("running", K.app_state())
      K.release("f1")
      assert.same("running", K.app_state())
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
