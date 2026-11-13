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

    spec_gap("IS2.1 Browse blocks: with the field empty, bare "
        .. "Down moves a block, not a line", function(gap)
      K.browse_to(3)
      K.keys("down")
      gap(function()
        assert.same(4, K.position())
      end)
    end)

    spec_gap(
        "IS2.1 Browse blocks: with text in the field, bare " ..
        "Up moves the text cursor only", function(gap)
      K.browse_to_end()
      K.type_lines({
        "a = 1",
        "b = 2"
      })
      K.keys("up")
      local line = K.cursor()
      K.keys("up")
      gap(function()
        assert.same(1, line)
        assert.same("end", K.position())
        assert.same("a = 1\nb = 2", K.draft())
      end)
    end)

    spec_gap(
        "IS2.1 Browse blocks: during an insertion, Ctrl+Up " ..
        "browses and submits nothing", function(gap)
      K.browse_to_end()
      K.type("z = 3")
      local before = K.file()
      K.keys("lctrl", "up")
      gap(function()
        assert.same(4, K.position())
        assert.same("z = 3", K.draft())
        assert.same("inserting", K.state())
        assert.same(before, K.file())
      end)
    end)

    spec_gap("IS2.1 Browse blocks: in an empty file either " ..
        "direction keeps the end position", function(gap)
      K.restart()
      K.open("empty.lua")
      K.keys("lctrl", "up")
      local up = K.position()
      K.keys("lctrl", "down")
      gap(function()
        assert.same({
          "end",
          "end"
        }, {
          up,
          K.position()
        })
      end)
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

    spec_gap("IS2.2 Keep the viewed block visible: with " ..
        "surrounding context", function(gap)
      K.open()
      K.browse_to(30)
      gap(function()
        assert.is_true(K.in_view(29))
        assert.is_true(K.in_view(31))
      end)
    end)

    spec_it("IS2.2 Keep the viewed block visible: at the end, "
        .. "the last block is shown", function()
      K.open()
      K.browse_to_end()
      assert.is_true(K.in_view(40))
    end)

    spec_gap(
        "IS2.2 Keep the viewed block visible: an empty file "
        .. "shows no line", function(gap)
      K.open("empty.lua")
      gap(function()
        assert.same({ }, K.view_rows())
      end)
    end)

    spec_gap(
        "IS2.2 Keep the viewed block visible: a tall block " ..
        "reached from above starts at the top", function(gap)
      K.open("tall.lua")
      K.browse_to(1)
      K.keys("lctrl", "down")
      gap(function()
        assert.same(2, K.position())
        assert.same("function f()", K.view_rows()[1])
      end)
    end)

    spec_gap(
        "IS2.2 Keep the viewed block visible: a tall block " ..
        "reached from below ends at the bottom", function(gap)
      K.open("tall.lua")
      K.browse_to(3)
      K.keys("lctrl", "up")
      gap(function()
        local rows = K.view_rows()
        assert.same(2, K.position())
        assert.same("end", rows[#rows])
      end)
    end)

    spec_gap("IS2.2 Keep the viewed block visible: toward a "
        .. "hidden row, the browse key scrolls one row first",
        function(gap)
      K.open("tall.lua")
      K.browse_to(1)
      K.keys("lctrl", "down")
      local top = K.view_rows()[1]
      local status = K.status_text()
      K.keys("lctrl", "down")
      gap(function()
        assert.same(2, K.position())
        assert.are_not.same(top, K.view_rows()[1])
        assert.same(status, K.status_text())
      end)
    end)
  end)

  describe("IS2.2, a tall block's last row", function()
    before_each(function()
      K.reset(
        { ["main.lua"] = "a = 1\n" .. tall(22) .. "b = 2\n" }
      )
      K.open()
    end)

    spec_gap("IS2.2 Keep the viewed block visible: once no row "
        .. "is hidden below, Ctrl+Down moves on", function(gap)
      K.browse_to(1)
      local moved_at = nil
      for press = 1, 40 do
        K.keys("lctrl", "down")
        if K.position() ~= 2 then
          moved_at = press
          break
        end
      end
      gap(function()
        -- the first press arrives; the rows below the view
        -- scroll in one per press before the block is left
        assert.is_true(moved_at ~= nil and 2 < moved_at)
        assert.same(3, K.position())
      end)
    end)
  end)

  describe("IS2.3", function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\nz = 3\n" })
      K.open()
    end)

    spec_gap(
        "IS2.3 Browse during a replacement: browsing moves " ..
        "the white highlight, the target stays", function(gap)
      K.browse_to(1)
      K.keys("f2")
      K.keys("lctrl", "down")
      gap(function()
        assert.same("replacing", K.state())
        assert.same(1, K.target())
        assert.same(2, K.position())
        assert.same("x = 1", K.draft())
      end)
    end)

    spec_gap(
        "IS2.3 Browse during a replacement: browsing never " ..
        "submits a changed draft", function(gap)
      K.browse_to(1)
      K.keys("f2")
      K.keys("end")
      K.type("0")
      K.keys("lctrl", "down")
      gap(function()
        assert.same("x = 10", K.draft())
        assert.same("x = 1\ny = 2\nz = 3\n", K.file())
        assert.same(1, K.target())
      end)
    end)
  end)

  describe("IS2.3, a target out of view", function()
    before_each(function()
      K.reset({ ["main.lua"] = many(40) })
      K.open()
    end)

    spec_gap(
        "IS2.3 Browse during a replacement: the status line "
        .. "still names the replacing state", function(gap)
      K.browse_to(1)
      K.keys("f2")
      local loaded = K.status_text()
      K.browse_to(40)
      gap(function()
        assert.same("replacing", K.state())
        assert.is_false(K.in_view(1))
        assert.same(loaded, K.status_text())
      end)
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
