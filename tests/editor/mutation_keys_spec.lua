-- Cases a mutation run over the editor's code found
-- unguarded, where no spec item covers the key (spec items
-- have their own tests under tests/editor/spec). Keys only,
-- through tests/helpers/editor_keys.lua. Edit is F2; move is
-- Alt+Up and Alt+Down.

local K = require("tests.helpers.editor_keys")

local FILE = "x = 1\ny = 2\nz = 3\n"
-- a file another program wrote, not canonically formatted
local LOOSE = "x=1\ny = 2\n"

--- What a key that does nothing must leave alone.
local function held_state()
  return {
    draft = K.draft(),
    cursor = { K.cursor() },
    position = K.position(),
    target = K.target() or "none",
    file = K.file(),
    message = K.message() or "none"
  }
end

describe("mutation survivors, keys #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("Ctrl+Shift+F, which formats the file", function()
    before_each(function()
      K.reset({ ["main.lua"] = LOOSE })
      K.open()
    end)

    it("formats the file in the browsing state", function()
      K.keys("lctrl", "lshift", "f")
      assert.same("x = 1\ny = 2\n", K.file())
    end)

    it("changes nothing during a replacement", function()
      K.browse_to(2)
      K.keys("f2")
      K.type("0")
      local before = held_state()
      K.keys("lctrl", "lshift", "f")
      assert.same(2, before.target)
      assert.same("y = 20", before.draft)
      assert.same(LOOSE, before.file)
      -- it says why, in a notice, and changes nothing else
      local msg = K.message()
      assert.truthy(msg and msg:find("Finish editing first", 1,
        true))
      before.message = msg
      assert.same(before, held_state())
    end)

    it("changes nothing during an insertion", function()
      K.type("z = 3")
      local before = held_state()
      K.keys("lctrl", "lshift", "f")
      assert.same("z = 3", before.draft)
      assert.same(LOOSE, before.file)
      local msg = K.message()
      assert.truthy(msg and msg:find("Finish the text first", 1,
        true))
      before.message = msg
      assert.same(before, held_state())
    end)
  end)

  describe("Ctrl+Backspace", function()
    before_each(function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.type_lines({
        "ab",
        "cd"
      })
    end)

    it("at a line's start joins it to the line before",
        function()
      K.keys("home")
      K.keys("lctrl", "backspace")
      assert.same("abcd", K.draft())
      assert.same({
        1,
        3
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)

    it("at the draft's start changes nothing", function()
      K.keys("lctrl", "home")
      K.keys("lctrl", "backspace")
      assert.same("ab\ncd", K.draft())
      assert.same({
        1,
        1
      }, { K.cursor() })
      assert.same(FILE, K.file())
      assert.same("end", K.position())
    end)
  end)

  -- Shift+Delete is bound in no field (the ruling of
  -- November 14, 2026: one text field, the same everywhere)
  describe("Shift+Delete with text in the field", function()
    before_each(function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.browse_to(2)
    end)

    it("changes nothing in an insertion, no block cut",
        function()
      K.type("abc")
      K.keys("home")
      local before = held_state()
      K.keys("lshift", "delete")
      assert.same(before, held_state())
    end)

    it("changes nothing in a replacement, no block cut",
        function()
      K.keys("f2")
      K.keys("home")
      local before = held_state()
      K.keys("lshift", "delete")
      assert.same(before, held_state())
    end)
  end)

  describe("an undone move", function()
    before_each(function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
    end)

    it("leaves the position on the block moved up, back " ..
        "in its place", function()
      K.browse_to(2)
      K.keys("lalt", "up")
      local moved = K.position()
      K.keys("lctrl", "z")
      assert.same(1, moved)
      assert.same(FILE, K.file())
      assert.same(2, K.position())
    end)

    it("leaves the position on the block moved down, back " ..
        "in its place", function()
      K.browse_to(2)
      K.keys("lalt", "down")
      local moved = K.position()
      K.keys("lctrl", "z")
      assert.same(3, moved)
      assert.same(FILE, K.file())
      assert.same(2, K.position())
    end)
  end)
end)
