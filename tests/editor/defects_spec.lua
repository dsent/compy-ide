-- Edge defects fixed in code that stays through the rework,
-- where no spec item covers the key (spec items have their own
-- tests under tests/editor/spec). Keys only, through
-- tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")

local FILE = "x = 1\ny = 2\nz = 3\n"

describe("editor defects #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  before_each(function()
    K.reset({ ["main.lua"] = FILE })
    K.open()
  end)

  it("text that would join the block before it is refused",
      function()
    K.reset({ ["main.lua"] = "f = print\ny = 2\n" })
    K.open()
    K.browse_to(2)
    K.type("(print)(1)")
    K.keys("return")
    assert.same("f = print\ny = 2\n", K.file())
    assert.same("(print)(1)", K.draft())
    assert.same(2, K.blocks())
    assert.is_not_nil(K.message())
  end)

  it("text after a final return is refused, the draft kept",
      function()
    K.reset({ ["main.lua"] = "x = 1\nreturn x\n" })
    K.open()
    K.type("y = 2")
    K.keys("return")
    assert.same("x = 1\nreturn x\n", K.file())
    assert.same("y = 2", K.draft())
    assert.same("inserting", K.state())
    assert.is_not_nil(K.message())
    -- above the return it goes in
    K.keys("lctrl", "up")
    K.keys("return")
    assert.same("x = 1\ny = 2\nreturn x\n", K.file())
    assert.same("", K.draft())
  end)

  -- the merge check must not refuse a draft that stands as
  -- blocks of its own
  it("a comment alone goes in before and after a block",
      function()
    K.browse_to(1)
    K.type("-- note")
    K.keys("return")
    assert.same("-- note\nx = 1\ny = 2\nz = 3\n", K.file())
    assert.same("", K.draft())
    K.browse_to(3)
    K.type("-- after")
    K.keys("return")
    assert.same(
      "-- note\nx = 1\n-- after\ny = 2\nz = 3\n",
      K.file()
    )
    K.browse_to_end()
    K.type("-- last")
    K.keys("return")
    assert.same(
      "-- note\nx = 1\n-- after\ny = 2\nz = 3\n-- last\n",
      K.file()
    )
    assert.is_nil(K.message())
  end)

  it("a comment and a statement in one draft go in together",
      function()
    K.browse_to(2)
    K.type_lines({ "-- note", "w = 0" })
    K.keys("return")
    assert.same("x = 1\n-- note\nw = 0\ny = 2\nz = 3\n", K.file())
    assert.same("", K.draft())
    assert.is_nil(K.message())
    assert.same(4, K.position())
  end)

  it("a cut that would join its neighbors is refused",
      function()
    local file = "a = f\ndo end\n(g)()\n"
    K.reset({ ["main.lua"] = file })
    K.open()
    K.browse_to(2)
    K.keys("lctrl", "delete")
    assert.same(file, K.file())
    assert.same(3, K.blocks())
    assert.same("", K.draft())
    assert.same(2, K.position())
    assert.is_not_nil(K.message())
  end)

  it("a move that would join two blocks is refused", function()
    local file = "a = f\ndo end\n(g)()\n"
    K.reset({ ["main.lua"] = file })
    K.open()
    K.browse_to(2)
    K.keys("lalt", "up")
    assert.same(file, K.file())
    assert.same(2, K.position())
    assert.is_not_nil(K.message())
  end)

  -- a held key repeats to its natural stop (the ruling of
  -- November 16, 2026): the file's end
  it("a held Alt+Down moves the block on to the file's end, "
      .. "one step to undo per place", function()
    K.browse_to(1)
    K.hold("lalt")
    K.hold("down")
    K.repeat_key("down")
    K.repeat_key("down")
    K.release("down")
    K.release("lalt")
    assert.same("y = 2\nz = 3\nx = 1\n", K.file())
    K.keys("lctrl", "z")
    assert.same("y = 2\nx = 1\nz = 3\n", K.file())
    K.keys("lctrl", "z")
    assert.same(FILE, K.file())
  end)

  it("a held Shift+Ins submits once", function()
    K.browse_to_end()
    K.type("w = 4")
    K.hold("lshift")
    K.hold("insert")
    K.repeat_key("insert")
    K.repeat_key("insert")
    K.release("insert")
    K.release("lshift")
    assert.same(FILE .. "w = 4\n", K.file())
  end)

  -- IS1.4, IS6.6: a test run is no leaving of the file, so
  -- its undo timeline is there on the return.
  it("Ctrl+Z still takes an action back after a test run",
      function()
    K.browse_to(2)
    K.keys("lctrl", "delete")
    K.keys("escape")
    assert.same("x = 1\nz = 3\n", K.file())
    K.keys("lctrl", "t")
    K.keys("lctrl", "t")
    assert.same("editor", K.app_state())
    K.ed = K.cc.editor
    K.keys("lctrl", "z")
    assert.same("y = 2", K.draft())
    K.keys("lctrl", "z")
    assert.same(FILE, K.file())
  end)

  it("the timeline ends when the file is left with Escape",
      function()
    K.browse_to(2)
    K.keys("lctrl", "delete")
    K.keys("escape")
    K.keys("escape")
    assert.same("ready", K.app_state())
    K.open()
    K.keys("lctrl", "z")
    assert.same("", K.draft())
    assert.same("x = 1\nz = 3\n", K.file())
  end)

  -- IS6.6: after an undo the position is the first restored
  -- block, or where the removed blocks stood.
  it("undoing an empty-line insertion returns the position",
      function()
    local file = "x = 1\n\ny = 2\n"
    K.reset({ ["main.lua"] = file })
    K.open()
    K.browse_to(2)
    K.keys("return")
    assert.same("x = 1\n\n\ny = 2\n", K.file())
    assert.same(3, K.position())
    K.keys("lctrl", "z")
    assert.same(file, K.file())
    assert.same(2, K.position())
  end)

  it("undoing a replacement that keeps its first line lands "
      .. "on the restored block", function()
    K.browse_to(1)
    K.keys("f2")
    K.keys("lshift", "return")
    K.type("w = 0")
    K.keys("return")
    assert.same("x = 1\nw = 0\ny = 2\nz = 3\n", K.file())
    assert.same(3, K.position())
    K.keys("lctrl", "z")
    assert.same(FILE, K.file())
    assert.same(1, K.position())
  end)

  for name, keys in pairs({
    ["a cut"] = { "lctrl", "delete" },
    ["a move"] = { "lalt", "down" },
    ["a format of the file"] = { "lalt", "f" }
  }) do
    it(name .. " never writes over a change from outside",
        function()
      K.reset({ ["main.lua"] = "x  =  1\ny = 2\nz = 3\n" })
      K.open()
      K.write_outside("main.lua", "z = 0\n")
      K.browse_to(2)
      K.keys(unpack(keys))
      assert.same("z = 0\n", K.file())
      assert.same({ }, K.writes())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same(2, K.position())
      assert.same(3, K.blocks())
      assert.truthy(K.message():find("outside", 1, true))
    end)
  end

  it("a refused landing leaves nothing for Ctrl+Z to take back",
      function()
    K.reset({ ["main.lua"] = "x = 1\nreturn x\n" })
    K.open()
    K.type("y = 2")
    K.keys("return")
    -- one Escape: the notice goes and the edit with it
    K.keys("escape")
    assert.same("browsing", K.state())
    K.keys("lctrl", "z")
    -- the abort comes back, and nothing before it
    assert.same("y = 2", K.draft())
    assert.same("x = 1\nreturn x\n", K.file())
  end)

  it("a merge Lua cannot parse is named as a merge", function()
    K.reset({ ["main.lua"] = "f = print\n" })
    K.open()
    K.type("(print)(1)")
    K.keys("return")
    assert.same("f = print\n", K.file())
    assert.same("(print)(1)", K.draft())
    assert.truthy(K.message():find("merge", 1, true))
  end)

  it("a draft of spaces alone is an empty line (IS4.3)",
      function()
    K.browse_to(2)
    K.type("   ")
    K.keys("return")
    assert.same("x = 1\n\ny = 2\nz = 3\n", K.file())
    assert.same("browsing", K.state())
    assert.same("", K.draft())
    assert.same(3, K.position())
  end)

  -- FR3.1, IS3.7: a block the user did not touch is written
  -- back as it was, whatever changes elsewhere in the file.
  describe("an untouched block keeps its text", function()
    local OWN = {
      "--[[ a ]]",
      "--[==[ long ]==]",
      "s = [[ long  text ]]",
      "x   =   1",
      "t = {1,2}  -- odd"
    }
    for _, own in ipairs(OWN) do
      it("`" .. own .. "` through an insertion, a replacement, "
          .. "a cut and an undo", function()
        K.reset({ ["main.lua"] = own .. "\nq = 1\nr = 2\n" })
        K.open()
        K.type("y = 2")
        K.keys("return")
        assert.same(own .. "\nq = 1\nr = 2\ny = 2\n", K.file())
        K.browse_to(2)
        K.keys("f2")
        K.type("0")
        K.keys("return")
        assert.same(own .. "\nq = 10\nr = 2\ny = 2\n", K.file())
        K.browse_to(3)
        K.keys("lctrl", "delete")
        assert.same(own .. "\nq = 10\ny = 2\n", K.file())
        K.keys("lctrl", "z")
        assert.same(own .. "\nq = 10\nr = 2\ny = 2\n", K.file())
        assert.same(own, K.buffer():block_lines(1)[1])
      end)
    end
  end)

  -- Ctrl+Delete alone cuts (the maintainer's ruling of
  -- November 14, 2026)
  it("Shift+Delete in browsing removes nothing", function()
    K.browse_to(2)
    local before = K.file()
    K.keys("lshift", "delete")
    assert.same(before, K.file())
    assert.same("", K.draft())
  end)

  -- compy-editor-pending-confirm-survives-close, filed on
  -- September 29, 2026 against the editor before its rework: a
  -- discard question left open survived Ctrl+T, and Enter or
  -- Space in the next file answered it there. The editor asks
  -- no question now; an exit during an edit is refused, and
  -- what was left of the edit goes nowhere after the exit.
  for _, exit in ipairs({
    { "Ctrl+T", { "lctrl", "t" } },
    { "Ctrl+Q", { "lctrl", "q" } },
  }) do
    it(exit[1] .. " during an edit asks nothing, and nothing of "
        .. "the edit reaches the next file", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n",
        ["notes.txt"] = "a\nb\n" })
      K.open()
      K.browse_to(1)
      K.keys("f2")
      K.type("0")
      K.keys(unpack(exit[2]))
      assert.same("editor", K.app_state())
      assert.same("replacing", K.state())
      assert.same("x = 10", K.draft())
      assert.same("notice", K.message_kind())
      -- Escape drops the edit at once, and the exit is taken
      K.keys("escape")
      assert.same("browsing", K.state())
      assert.is_nil(K.message())
      K.keys(unpack(exit[2]))
      assert.same("ready", K.app_state())
      K.open("notes.txt")
      assert.same("notes.txt", K.file_name())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.is_nil(K.message())
      -- the keys that answered the question do their own work
      K.keys("space")
      assert.same(" ", K.draft())
      K.keys("escape")
      assert.same("a\nb\n", K.file("notes.txt"))
      -- Enter on an empty field adds an empty line where it
      -- stands, the file's end on opening
      K.keys("return")
      assert.same("a\nb\n\n", K.file("notes.txt"))
      assert.same("x = 1\ny = 2\n", K.file("main.lua"))
    end)
  end

  -- compy-ide-editor-error-drops-first-glyph, filed on
  -- September 30, 2026 against the editor before its rework:
  -- the first character typed over an error message was lost
  describe("a character typed over an error message", function()
    --- a syntax failure's message over the draft `x = = 1`,
    --- the cursor before the failing `=`
    local function failed()
      K.browse_to_end()
      K.type("x = = 1")
      K.keys("return")
      assert.same("error", K.message_kind())
    end

    it("is typed, its key first", function()
      failed()
      K.type("print")
      assert.is_nil(K.message())
      assert.same("x = print= 1", K.draft())
    end)

    it("is typed, its text first", function()
      failed()
      K.type_text_first("p")
      K.type("rint")
      assert.is_nil(K.message())
      assert.same("x = print= 1", K.draft())
    end)
  end)
end)
