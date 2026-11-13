-- R3 Document structure and position preservation: FR3.1-
-- FR3.5 and FR3.7 (editor principles, ratified). FR3.6 is
-- tested with IS3.9, which says when formatting runs.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local tall = K.block

local function parses(text)
  return loadstring(text) ~= nil
end

describe("FR3 structure and position #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("FR3.1", function()
    before_each(function()
      K.reset({
        ["main.lua"] = "x = 1\ny = 2\n",
        ["shared.lua"] = "x = 1; y = {\n  2,\n}\nz = 3\n",
        ["a.txt"] = "one\n"
      })
    end)

    spec_it(
        "FR3.1 Preserve file structure: an accepted Lua edit "
        .. "leaves a file that parses", function()
      K.open()
      K.browse_to_end()
      K.type("z = 3")
      K.keys("return")
      assert.is_true(parses(K.file()))
      assert.same(3, K.blocks())
    end)

    spec_gap("FR3.1 Preserve file structure: a line two " ..
        "statements share survives an edit elsewhere", function(
      gap
    )
      K.open("shared.lua")
      K.browse_to_end()
      K.type("w = 4")
      local ok = pcall(K.keys, "return")
      gap(function()
        assert.is_true(ok)
        assert.is_true(parses(K.file("shared.lua")))
      end)
    end)

    spec_it("FR3.1 Preserve file structure: a text file keeps "
        .. "one line per block, each terminated", function()
      K.open("a.txt")
      K.browse_to_end()
      K.type("two")
      K.keys("return")
      local f = K.file("a.txt")
      assert.same("\n", f:sub(-1))
      assert.truthy(f:find("^one\n"))
      assert.truthy(f:find("\ntwo\n$"))
    end)
  end)

  describe("FR3.1, long comments", function()
    before_each(function()
      K.reset({ ["empty.lua"] = "" })
      K.open("empty.lua")
    end)

    spec_it(
        "FR3.1 Preserve file structure: a long comment that "
        .. "holds ]] is saved as written", function()
      K.type_lines({
        "--[=[ a",
        "b ]] c ]=]"
      })
      local ok = pcall(K.keys, "return")
      local f = K.file("empty.lua")
      assert.is_true(ok)
      assert.same("--[=[ a\nb ]] c ]=]\n", f)
      assert.is_true(parses(f))
    end)

    spec_it(
        "FR3.1 Preserve file structure: a long comment ending "
        .. "in ] is saved as written", function()
      -- its text, " a\nb]", ends in "]": at level 0 the
      -- closing "]]" would come one character early
      K.type_lines({
        "--[=[ a",
        "b]]=]"
      })
      local ok = pcall(K.keys, "return")
      local f = K.file("empty.lua")
      assert.is_true(ok)
      assert.is_true(parses(f))
      assert.truthy(f:find("b]", 1, true))
    end)

    spec_it(
        "FR3.1 Preserve file structure: a long comment that "
        .. "holds ]] after a statement is saved", function()
      K.type("x = 1 --[=[ a ]] b ]=]")
      local ok = pcall(K.keys, "return")
      local f = K.file("empty.lua")
      assert.is_true(ok)
      assert.is_true(parses(f))
      assert.truthy(f:find("]]", 1, true))
    end)

    spec_it(
        "FR3.1 Preserve file structure: a long comment over "
        .. "two lines after a statement is saved", function()
      K.type_lines({
        "x = 1 --[=[ a",
        "b ]] c ]=]"
      })
      local ok = pcall(K.keys, "return")
      local f = K.file("empty.lua")
      assert.is_true(ok)
      assert.is_true(parses(f))
      assert.truthy(f:find("]]", 1, true))
    end)

    spec_it(
        "FR3.1 Preserve file structure: a long comment that "
        .. "holds ]] between statements is saved", function()
      K.type_lines({
        "x = 1",
        "--[=[ a",
        "b ]] c ]=]",
        "y = 2"
      })
      local ok = pcall(K.keys, "return")
      local f = K.file("empty.lua")
      assert.is_true(ok)
      assert.is_true(parses(f))
      assert.truthy(f:find("]]", 1, true))
    end)
  end)

  describe("FR3.2", function()
    before_each(function()
      local t = { }
      for i = 1, 40 do
        t[i] = "v" .. i .. " = " .. i
      end
      K.reset({ ["main.lua"] = table.concat(t, "\n") .. "\n" })
      K.open()
    end)

    spec_gap(
        "FR3.2 Preserve browsing position across test runs: "
        .. "the position and the view come back", function(gap)
      K.browse_to(30)
      local rows = K.view_rows()
      K.keys("lctrl", "t")
      K.keys("lctrl", "t")
      gap(function()
        assert.same(30, K.position())
        assert.same(rows, K.view_rows())
      end)
    end)
  end)

  describe("FR3.3", function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
    end)

    spec_gap("FR3.3 Open a file ready to append: typing right "
        .. "after opening appends a block", function(gap)
      K.type("z = 3")
      K.keys("return")
      gap(function()
        assert.same("x = 1\ny = 2\nz = 3\n", K.file())
      end)
    end)
  end)

  describe("FR3.4", function()
    before_each(function()
      K.reset(
        { ["main.lua"] = "a = 1\n" .. tall(22) .. "b = 2\n" }
      )
      K.open()
    end)

    spec_it(
        "FR3.4 Keep the browsed block in view: every row of "
        .. "a tall block can be seen without leaving it",
        function()
      K.browse_to(2)
      local seen = { }
      for _ = 1, 40 do
        if K.position() ~= 2 then
          break
        end
        for _, r in ipairs(K.view_rows()) do
          seen[r] = true
        end
        K.keys("down")
      end
      for line in tall(22):gmatch("[^\n]+") do
        assert.is_true(seen[line] == true, line)
      end
      assert.same("", K.draft())
    end)
  end)

  describe("FR3.4, during an insertion", function()
    before_each(function()
      K.reset(
        { ["main.lua"] = "a = 1\n" .. tall(22) .. "b = 2\n" }
      )
      K.open()
    end)

    spec_gap("FR3.4 Keep the browsed block in view: browsing "
        .. "leaves the draft and its cursor as they were",
        function(gap)
      K.browse_to_end()
      K.type("z = 3")
      local line, col = K.cursor()
      K.keys("lctrl", "up")
      K.keys("lctrl", "up")
      gap(function()
        assert.same("z = 3", K.draft())
        assert.same({
          line,
          col
        }, { K.cursor() })
        assert.same("inserting", K.state())
      end)
    end)
  end)

  describe("FR3.5", function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
    end)

    spec_it(
        "FR3.5 Advance position for sequential entry: at the "
        .. "end, two submissions stay in typing order",
        function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.type("b = 2")
      K.keys("return")
      assert.same("x = 1\ny = 2\na = 1\nb = 2\n", K.file())
      assert.same("end", K.position())
    end)

    spec_gap("FR3.5 Advance position for sequential entry: " ..
        "before a block, two submissions stay in typing order",
        function(gap)
      K.browse_to(2)
      K.type("a = 1")
      K.keys("return")
      K.type("b = 2")
      K.keys("return")
      gap(function()
        assert.same("x = 1\na = 1\nb = 2\ny = 2\n", K.file())
        assert.same(4, K.position())
      end)
    end)

    spec_gap(
        "FR3.5 Advance position for sequential entry: after "
        .. "a replacement, the next block", function(gap)
      K.browse_to(1)
      K.keys("f2")
      K.keys("end")
      K.type("0")
      K.keys("return")
      gap(function()
        assert.same("x = 10\ny = 2\n", K.file())
        assert.same(2, K.position())
      end)
    end)
  end)

  describe("FR3.7", function()
    before_each(function()
      K.reset({
        ["main.lua"] = "x = 1\n\ny = 2\n",
        ["a.txt"] = "one\ntwo\n"
      })
    end)

    spec_it("FR3.7 No highlight means the end position: every "
        .. "block is white when browsed, the end is not",
        function()
      K.open()
      K.browse_to(1)
      for b = 1, 3 do
        assert.same({
          "white",
          b
        }, { K.highlight() })
        K.keys("lctrl", "down")
      end
      assert.same("end", K.position())
      assert.is_nil(K.highlight())
    end)

    spec_gap(
        "FR3.7 No highlight means the end position: nothing "
        .. "after a text file's last line reads as a line",
        function(gap)
      K.open("a.txt")
      gap(function()
        assert.same(2, K.blocks())
        assert.same({
          "one",
          "two"
        }, K.view_rows())
      end)
    end)

    spec_gap("FR3.7 No highlight means the end position: the "
        .. "browsed block is white while it is the target",
        function(gap)
      K.open()
      K.browse_to(1)
      K.keys("f2")
      gap(function()
        assert.same("replacing", K.state())
        assert.same({
          "white",
          1
        }, { K.highlight() })
      end)
    end)
  end)
end)
