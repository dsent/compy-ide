-- IS1 Opening and leaving files, IS2 Browsing a Lua file
-- (editor principles, ratified): the clauses the tests of
-- is1_files_spec.lua and is2_browse_spec.lua leave out. Keys
-- only, through tests/helpers/editor_keys.lua. Edit is F2;
-- follow a reference is Ctrl+J; run is Ctrl+T.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local FILE = "x = 1\ny = 2\nz = 3\n"

--- `n` one-line blocks: v1 = 1 to vn = n.
local function many(n)
  local t = { }
  for i = 1, n do
    t[i] = "v" .. i .. " = " .. i .. "\n"
  end
  return table.concat(t)
end

describe("IS1 and IS2, added #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("IS1.2", function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1" })
    end)

    spec_it("IS1.2 Admit or refuse a file: a refused " ..
        "submission does not create a missing file", function()
      K.open("new.lua")
      K.type("a = = 1")
      K.keys("return")
      assert.same("a = = 1", K.draft())
      assert.is_nil(K.file("new.lua"))
      assert.same({ }, K.writes())
    end)

    spec_it("IS1.2 Admit or refuse a file: an aborted draft "
        .. "does not create a missing file", function()
      K.open("new.lua")
      K.type("a = 1")
      K.keys("escape")
      K.keys("escape")
      assert.same("ready", K.app_state())
      assert.is_nil(K.file("new.lua"))
      assert.same({ }, K.writes())
    end)

    spec_it("IS1.2 Admit or refuse a file: a missing last " ..
        "line break is not stored before a submission",
        function()
      K.open()
      local blocks = K.blocks()
      K.type("a = = 1")
      K.keys("return")
      K.keys("escape")
      K.keys("escape")
      assert.same(1, blocks)
      assert.same("x = 1", K.file())
      assert.same({ }, K.writes())
    end)
  end)

  describe("IS1.3", function()
    before_each(function()
      K.reset({ ["main.lua"] = K.block(16) .. "y = 2\n" })
      K.open()
    end)

    spec_it("IS1.3 Handle size limits: an append to a file " ..
        "with an oversized block works as usual", function()
      K.type("z = 3")
      K.keys("return")
      assert.same(K.block(16) .. "y = 2\nz = 3\n", K.file())
      assert.same("browsing", K.state())
      assert.same("end", K.position())
    end)

    spec_it("IS1.3 Handle size limits: an insertion after " ..
        "the oversized block works as usual", function()
      K.browse_to(2)
      K.type("a = 1")
      K.keys("return")
      assert.same(K.block(16) .. "a = 1\ny = 2\n", K.file())
      assert.same("browsing", K.state())
      assert.same(3, K.position())
    end)

    spec_it("IS1.3 Handle size limits: an insertion before " ..
        "the oversized block works as usual", function()
      K.browse_to(1)
      K.type("a = 1")
      K.keys("return")
      assert.same(
        "a = 1\n" .. K.block(16) .. "y = 2\n",
        K.file()
      )
      assert.same("browsing", K.state())
      assert.same(2, K.position())
    end)
  end)

  describe("IS1.4", function()
    spec_it("IS1.4 Resume after running a project: Ctrl+T " ..
        "and back restores the document view", function()
      K.reset({ ["main.lua"] = many(60) })
      K.open()
      K.browse_to(8)
      local view = K.view_rows()
      K.keys("lctrl", "t")
      K.keys("lctrl", "t")
      assert.same("editor", K.app_state())
      assert.same(8, K.position())
      -- the view left the end of the file to show block 8
      assert.are_not.same("v60 = 60", view[#view])
      assert.same(view, K.view_rows())
    end)
  end)

  describe("IS1.5", function()
    before_each(function()
      K.reset({
        ["main.lua"] = "local m = require(\"mod\")\nx = 1\n",
        ["mod.lua"] = "y = 2\n"
      })
      K.open()
    end)

    spec_it("IS1.5 Follow a file reference: on a block with "
        .. "no reference, Ctrl+J opens nothing", function()
      K.browse_to(2)
      K.keys("lctrl", "j")
      assert.same("editor", K.app_state())
      assert.same("main.lua", K.file_name())
      assert.same(2, K.position())
      assert.same("browsing", K.state())
    end)

    spec_it("IS1.5 Follow a file reference: with a " ..
        "replacement target, Ctrl+J is refused with a notice",
        function()
      K.browse_to(1)
      K.keys("f2")
      K.keys("lctrl", "j")
      assert.same("main.lua", K.file_name())
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      assert.same("local m = require(\"mod\")", K.draft())
      assert.is_not_nil(K.message())
    end)

    spec_it("IS1.5 Follow a file reference: the referenced " ..
        "file opens in the browsing state", function()
      K.browse_to(1)
      K.keys("lctrl", "j")
      assert.same("mod.lua", K.file_name())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.is_nil(K.target())
    end)
  end)

  describe("IS2.1", function()
    before_each(function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.browse_to(2)
      K.keys("f2")
    end)

    spec_it("IS2.1 Browse blocks: in a replacement, bare Up "
        .. "and Down move the text cursor only", function()
      K.keys("up")
      local up = {
        K.position(),
        { K.cursor() }
      }
      K.keys("down")
      assert.same({
        2,
        {
          1,
          1
        }
      }, up)
      assert.same(2, K.position())
      assert.same({
        1,
        6
      }, { K.cursor() })
      assert.same(2, K.target())
      assert.same("y = 2", K.draft())
    end)

    spec_it("IS2.1 Browse blocks: in a replacement, Ctrl+Up "
        .. "and Ctrl+Down browse, the draft and cursor kept",
        function()
      K.keys("home")
      K.keys("lctrl", "up")
      local up = K.position()
      K.keys("lctrl", "down")
      K.keys("lctrl", "down")
      K.keys("lctrl", "down")
      assert.same(1, up)
      assert.same("end", K.position())
      assert.same(2, K.target())
      assert.same("y = 2", K.draft())
      assert.same({
        1,
        1
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)
  end)

  describe("IS2.2", function()
    spec_it("IS2.2 Keep the viewed block visible: at the " ..
        "end, the view's last row is the file's last", function(
      
    )
      K.reset({ ["main.lua"] = many(60) })
      K.open()
      local view = K.view_rows()
      assert.same("end", K.position())
      assert.same("v60 = 60", view[#view])
      assert.same("v59 = 59", view[#view - 1])
    end)
  end)

  describe("IS2.4", function()
    local LINE = string.rep("alpha ", 16)

    spec_it("IS2.4 Wrap long lines in the document view: " ..
        "the yellow highlight covers every row too", function()
      K.reset({ ["notes.txt"] = LINE .. "\nbeta\n" })
      K.open("notes.txt")
      K.browse_to(1)
      K.keys("f2")
      K.keys("lctrl", "down")
      local h = K.highlights()
      assert.same(1, K.target())
      assert.same({ 1 }, h.yellow)
      assert.same(2, h.rows.yellow)
      assert.same({ 2 }, h.white)
    end)

    spec_it("IS2.4 Wrap long lines in the document view: " ..
        "a wide line of a Lua file wraps as well", function()
      local wide = "s = \"" .. LINE .. "\""
      K.reset({ ["main.lua"] = wide .. "\ny = 2\n" })
      K.open()
      K.browse_to(1)
      local rows, shown = K.rows_shown(1)
      local view = K.view_rows()
      local h = K.highlights()
      assert.same(2, K.blocks())
      assert.same(2, rows)
      assert.same(2, shown)
      assert.same(wide, view[1] .. view[2])
      assert.same({ 1 }, h.white)
      assert.same(2, h.rows.white)
      assert.same(wide .. "\ny = 2\n", K.file())
    end)
  end)

  describe("IS1, the notices and the caller's view", function()
    spec_it("IS1.2 Admit or refuse a file: the notice names "
        .. "the file and the reason, the field empty", function(
      
    )
      K.reset({ ["bad8.lua"] = "s = '\255'\n" })
      K.open("bad8.lua")
      local text = K.console_text()
      assert.same("ready", K.app_state())
      assert.truthy(text:find("bad8.lua", 1, true))
      assert.truthy(text:find("UTF-8", 1, true))
      assert.same("", K.console_draft())
    end)

    spec_it("IS1.3 Handle size limits: a refused submission "
        .. "names the limit and stays an insertion", function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.open()
      K.type_lines(K.block_lines(15))
      K.keys("return")
      assert.truthy((K.message() or ""):find("14", 1, true))
      assert.same("inserting", K.state())
      assert.same("end", K.position())
      assert.same("x = 1\n", K.file())
    end)

    --- A file of 60 blocks, the 20th a reference to mod.lua,
    --- open at block 20, reached from block `from`.
    local function at_reference(from)
      local ref = "local m = require(\"mod\")\n"
      K.reset({
        ["main.lua"] = many(19) .. ref .. many(40),
        ["mod.lua"] = "y = 2\n"
      })
      K.open()
      K.browse_to(from)
      K.browse_to(20)
    end

    spec_it("IS1.6 Step back from a file with Escape: the " ..
        "caller's view, reached from above, comes back",
        function()
      at_reference(2)
      local view = K.view_rows()
      K.keys("lctrl", "j")
      local followed = K.file_name()
      K.keys("escape")
      assert.same("mod.lua", followed)
      assert.same("main.lua", K.file_name())
      assert.same(20, K.position())
      assert.same(view, K.view_rows())
    end)

    spec_it("IS1.6 Step back from a file with Escape: the " ..
        "caller's view, reached from below, comes back",
        function()
      at_reference(50)
      local view = K.view_rows()
      K.keys("lctrl", "j")
      local followed = K.file_name()
      K.keys("escape")
      assert.same("mod.lua", followed)
      assert.same("main.lua", K.file_name())
      assert.same(20, K.position())
      assert.same(view, K.view_rows())
    end)

    spec_it("IS1.7 Report a persistence failure: a failed " ..
        "replacement keeps the edit, and the next lands",
        function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.browse_to(2)
      K.keys("f2")
      K.type("0")
      K.keys("left")
      K.fail_writes("the card is full")
      K.keys("return")
      local failed = {
        K.draft(),
        { K.cursor() },
        K.position(),
        K.target(),
        K.file(),
        K.message() ~= nil
      }
      K.fail_writes(nil)
      K.keys("return")
      assert.same({
        "y = 20",
        {
          1,
          6
        },
        2,
        2,
        FILE,
        true
      }, failed)
      assert.same("x = 1\ny = 20\nz = 3\n", K.file())
      assert.same("browsing", K.state())
    end)
  end)

  describe("IS2, the cursor and the scrolled rows", function()
    spec_it("IS2.1 Browse blocks: during an insertion, " ..
        "Ctrl+Up leaves the draft's cursor where it was",
        function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.type("abc")
      K.keys("left")
      K.keys("lctrl", "up")
      K.keys("lctrl", "up")
      assert.same(2, K.position())
      assert.same("abc", K.draft())
      assert.same({
        1,
        3
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)

    spec_it("IS2.1 Browse blocks: with text in the field, " ..
        "bare Up on the first row goes to the draft's start",
        function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.type_lines({
        "ab",
        "cd"
      })
      K.keys("up")
      local first = { K.cursor() }
      K.keys("up")
      assert.same({
        1,
        3
      }, first)
      assert.same({
        1,
        1
      }, { K.cursor() })
      assert.same("end", K.position())
      assert.same("ab\ncd", K.draft())
    end)

    spec_it("IS2.3 Browse during a replacement: a modified " ..
        "draft, its cursor and the target stay", function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.browse_to(2)
      K.keys("f2")
      K.type("0")
      K.keys("home")
      K.keys("right")
      K.keys("lctrl", "up")
      K.keys("lctrl", "down")
      K.keys("lctrl", "down")
      local browsed = {
        K.position(),
        K.target(),
        K.draft(),
        { K.cursor() },
        K.file()
      }
      K.keys("return")
      assert.same({
        3,
        2,
        "y = 20",
        {
          1,
          2
        },
        FILE
      }, browsed)
      assert.same("x = 1\ny = 20\nz = 3\n", K.file())
    end)

    --- A block of 60 lines between two short ones.
    local function tall_file()
      K.reset(
        { ["main.lua"] = "a = 1\n" .. K.block(60) .. "z = 3\n" }
      )
      K.open()
    end

    spec_it("IS2.2 Keep the viewed block visible: Ctrl+Down "
        .. "scrolls a tall block by one row a press", function()
      tall_file()
      K.browse_to(1)
      K.keys("lctrl", "down")
      local before = K.view_rows()
      K.keys("lctrl", "down")
      local after = K.view_rows()
      assert.same(2, K.position())
      assert.same(before[2], after[1])
      assert.same(before[#before], after[#after - 1])
    end)

    spec_it("IS2.2 Keep the viewed block visible: Ctrl+Up " ..
        "scrolls a tall block by one row a press", function()
      tall_file()
      K.browse_to(3)
      K.keys("lctrl", "up")
      local before = K.view_rows()
      K.keys("lctrl", "up")
      local after = K.view_rows()
      assert.same(2, K.position())
      assert.same(before[1], after[2])
      assert.same(before[#before - 1], after[#after])
    end)

    spec_it("IS2.2 Keep the viewed block visible: one press "
        .. "for each hidden row, then the key moves on",
        function()
      tall_file()
      K.browse_to(1)
      K.keys("lctrl", "down")
      local rows, shown = K.rows_shown(2)
      for _ = 1, rows - shown do
        K.keys("lctrl", "down")
      end
      local scrolled = K.position()
      local _, at_bottom = K.rows_shown(2)
      K.keys("lctrl", "down")
      assert.is_true(shown < rows)
      assert.same(2, scrolled)
      assert.same(shown, at_bottom)
      assert.same(3, K.position())
    end)
  end)
end)
