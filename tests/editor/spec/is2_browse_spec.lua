-- IS2 Browsing a Lua file (editor principles, ratified).
-- Keys only, through tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

--- `n` one-line blocks, v1 = 1 to vn = n.
local function many(n)
  local t = { }
  for i = 1, n do
    t[i] = "v" .. i .. " = " .. i
  end
  return table.concat(t, "\n") .. "\n"
end

local tall = K.block

describe("IS2 browsing #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("IS2.1", function()
    before_each(function()
      K.reset({
        ["main.lua"] =
            "x = 1\n\nif a then\n  b = 1\nend\ny = 2\n",
        ["empty.lua"] = ""
      })
      K.open()
    end)

    spec_it("IS2.1 Browse blocks: Ctrl+Down and Ctrl+Up move a "
        .. "block at a time", function()
      K.browse_to(1)
      K.keys("lctrl", "down")
      assert.same(2, K.position())
      K.keys("lctrl", "down")
      assert.same(3, K.position())
      -- block 3 has three lines: one press leaves it
      K.keys("lctrl", "down")
      assert.same(4, K.position())
      K.keys("lctrl", "up")
      assert.same(3, K.position())
    end)

    spec_it(
        "IS2.1 Browse blocks: an empty-line block is browsed "
        .. "and highlighted white", function()
      K.browse_to(2)
      assert.same(2, K.position())
      assert.same({
        "white",
        2
      }, { K.highlight() })
    end)

    spec_it("IS2.1 Browse blocks: upward stops at the first "
        .. "block", function()
      K.browse_to(1)
      K.keys("lctrl", "up")
      assert.same(1, K.position())
    end)

    spec_it(
        "IS2.1 Browse blocks: downward stops after the last "
        .. "block, with no white highlight", function()
      K.browse_to(1)
      for _ = 1, 4 do
        K.keys("lctrl", "down")
      end
      assert.same("end", K.position())
      assert.is_nil(K.highlight())
      -- and it stays there: no wrapping round
      K.keys("lctrl", "down")
      assert.same("end", K.position())
    end)

    spec_it("IS2.1 Browse blocks: with the field empty, bare "
        .. "Down moves a block, not a line", function()
      K.browse_to(3)
      K.keys("down")
      assert.same(4, K.position())
    end)

    spec_it(
        "IS2.1 Browse blocks: with text in the field, bare " ..
        "Up moves the text cursor only", function()
      K.browse_to_end()
      K.type_lines({
        "a = 1",
        "b = 2"
      })
      K.keys("up")
      local line = K.cursor()
      K.keys("up")
      assert.same(1, line)
      assert.same("end", K.position())
      assert.same("a = 1\nb = 2", K.draft())
    end)

    spec_it(
        "IS2.1 Browse blocks: during an insertion, Ctrl+Up " ..
        "browses and submits nothing", function()
      K.browse_to_end()
      K.type("z = 3")
      local before = K.file()
      K.keys("lctrl", "up")
      assert.same(4, K.position())
      assert.same("z = 3", K.draft())
      assert.same("inserting", K.state())
      assert.same(before, K.file())
    end)

    spec_it("IS2.1 Browse blocks: in an empty file either " ..
        "direction keeps the end position", function()
      K.restart()
      K.open("empty.lua")
      K.keys("lctrl", "up")
      local up = K.position()
      K.keys("lctrl", "down")
      assert.same({
        "end",
        "end"
      }, {
        up,
        K.position()
      })
    end)
  end)

  describe("IS2.2", function()
    before_each(function()
      K.reset({
        ["main.lua"] = many(40),
        ["tall.lua"] = "a = 1\n" .. tall(22) .. "b = 2\n",
        ["empty.lua"] = ""
      })
    end)

    spec_it("IS2.2 Keep the viewed block visible: the browsed "
        .. "block is in view", function()
      K.open()
      K.browse_to(30)
      assert.same(30, K.position())
      assert.is_true(K.in_view(30))
    end)

    spec_it("IS2.2 Keep the viewed block visible: with " ..
        "surrounding context", function()
      K.open()
      K.browse_to(30)
      assert.is_true(K.in_view(29))
      assert.is_true(K.in_view(31))
    end)

    spec_it("IS2.2 Keep the viewed block visible: in the rows "
        .. "a tall field leaves the view", function()
      K.open()
      K.browse_to_end()
      local lines = { }
      for n = 1, 8 do
        lines[n] = "t" .. n .. " = " .. n
      end
      K.type_lines(lines)
      K.keys("lctrl", "up")
      K.keys("lctrl", "up")
      -- the field takes 8 of the 17 rows, the view the rest
      assert.is_true(#K.view_rows() <= 9)
      assert.same(39, K.position())
      assert.is_true(K.in_view(39))
      assert.is_true(K.in_view(38))
      assert.is_true(K.in_view(40))
    end)

    spec_it("IS2.2 Keep the viewed block visible: at the end, "
        .. "the last block is shown", function()
      K.open()
      K.browse_to_end()
      assert.is_true(K.in_view(40))
    end)

    spec_it(
        "IS2.2 Keep the viewed block visible: an empty file "
        .. "shows no line", function()
      K.open("empty.lua")
      assert.same({ }, K.view_rows())
    end)

    spec_it(
        "IS2.2 Keep the viewed block visible: a tall block " ..
        "reached from above starts at the top", function()
      K.open("tall.lua")
      K.browse_to(1)
      K.keys("lctrl", "down")
      assert.same(2, K.position())
      assert.same("function f()", K.view_rows()[1])
    end)

    spec_it(
        "IS2.2 Keep the viewed block visible: a tall block " ..
        "reached from below ends at the bottom", function()
      K.open("tall.lua")
      K.browse_to(3)
      K.keys("lctrl", "up")
      local rows = K.view_rows()
      assert.same(2, K.position())
      assert.same("end", rows[#rows])
    end)

    spec_it("IS2.2 Keep the viewed block visible: toward a "
        .. "hidden row, the browse key scrolls one row first",
        function()
      K.open("tall.lua")
      K.browse_to(1)
      K.keys("lctrl", "down")
      local before = K.view_rows()
      local status = K.status_text()
      K.keys("lctrl", "down")
      local after = K.view_rows()
      assert.same(2, K.position())
      -- by one row: each row moved up one place
      assert.same(#before, #after)
      for i = 1, #before - 1 do
        assert.same(before[i + 1], after[i])
      end
      assert.are_not.same(before[#before], after[#after])
      assert.same(status, K.status_text())
    end)

    spec_it("IS2.2 Keep the viewed block visible: scrolling "
        .. "to the file's first row leaves the status line "
        .. "as it was", function()
      K.reset({ ["first.lua"] = tall(22) .. "b = 2\n" })
      K.open("first.lua")
      -- reached from below: the block's first rows are hidden
      K.browse_to(1)
      local status = K.status_text()
      local scrolled = 0
      for _ = 1, 22 do
        if K.view_rows()[1] == "function f()" then
          break
        end
        K.keys("lctrl", "up")
        scrolled = scrolled + 1
        assert.same(1, K.position())
        assert.same(status, K.status_text())
      end
      assert.is_true(0 < scrolled)
      assert.same("function f()", K.view_rows()[1])
    end)

    spec_it("IS2.2 Keep the viewed block visible: toward a "
        .. "hidden row above, Ctrl+Up scrolls one row first",
        function()
      K.open("tall.lua")
      K.browse_to(3)
      K.keys("lctrl", "up")
      local before = K.view_rows()
      local status = K.status_text()
      K.keys("lctrl", "up")
      local after = K.view_rows()
      assert.same(2, K.position())
      -- by one row: each row moved down one place
      assert.same(#before, #after)
      for i = 1, #before - 1 do
        assert.same(before[i], after[i + 1])
      end
      assert.are_not.same(before[1], after[1])
      assert.same(status, K.status_text())
    end)
  end)

  describe("IS2.2, a tall block's last row", function()
    before_each(function()
      K.reset(
        { ["main.lua"] = "a = 1\n" .. tall(22) .. "b = 2\n" }
      )
      K.open()
    end)

    spec_it("IS2.2 Keep the viewed block visible: once no row "
        .. "is hidden below, Ctrl+Down moves on", function()
      K.browse_to(1)
      K.keys("lctrl", "down")
      assert.same(2, K.position())
      local rows, shown = K.rows_shown(2)
      local hidden = rows - shown
      assert.is_true(0 < hidden)
      -- the rows below the view scroll in one per press
      for _ = 1, hidden do
        K.keys("lctrl", "down")
        assert.same(2, K.position())
        local _, now = K.rows_shown(2)
        assert.same(shown, now)
      end
      -- the block's last row is now the view's last row
      local view = K.view_rows()
      assert.same("end", view[#view])
      -- no row is hidden below now: the next press moves on
      K.keys("lctrl", "down")
      assert.same(3, K.position())
    end)
  end)

  describe("IS2.3", function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\nz = 3\n" })
      K.open()
    end)

    spec_it(
        "IS2.3 Browse during a replacement: browsing moves " ..
        "the white highlight, the target stays", function()
      K.browse_to(1)
      K.keys("f2")
      K.keys("lctrl", "down")
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      assert.same(2, K.position())
      assert.same("x = 1", K.draft())
    end)

    spec_it(
        "IS2.3 Browse during a replacement: browsing never " ..
        "submits a changed draft", function()
      K.browse_to(1)
      K.keys("f2")
      K.keys("end")
      K.type("0")
      K.keys("lctrl", "down")
      assert.same("x = 10", K.draft())
      assert.same("x = 1\ny = 2\nz = 3\n", K.file())
      assert.same(1, K.target())
    end)
  end)

  describe("IS2.3, a target out of view", function()
    before_each(function()
      K.reset({ ["main.lua"] = many(40) })
      K.open()
    end)

    spec_it(
        "IS2.3 Browse during a replacement: the status line "
        .. "still names the replacing state", function()
      K.browse_to(1)
      K.keys("f2")
      local loaded = K.status_text()
      K.browse_to(40)
      assert.same("replacing", K.state())
      assert.is_false(K.in_view(1))
      -- the line follows the browsing position, as Luditor's
      -- does; the state it names stays
      assert.truthy(loaded:find("replacing", 1, true))
      assert.truthy(K.status_text():find("replacing", 1, true))
    end)
  end)

  describe("IS2.4", function()
    before_each(function()
      K.reset(
        { ["notes.txt"] = string.rep("alpha ", 16) .. "\n" }
      )
      K.open("notes.txt")
    end)

    spec_it(
        "IS2.4 Wrap long lines in the document view: a wide "
        .. "line continues on the next row", function()
      local rows, shown = K.rows_shown(1)
      assert.same(2, rows)
      assert.same(2, shown)
      local view = K.view_rows()
      local line = string.rep("alpha ", 16)
      assert.same(line, view[1] .. view[2])
    end)

    spec_it("IS2.4 Wrap long lines in the document view: the "
        .. "highlight covers every row of its block", function()
      K.browse_to(1)
      local h = K.highlights()
      assert.same({ 1 }, h.white)
      assert.same(2, h.rows.white)
    end)
  end)
end)
