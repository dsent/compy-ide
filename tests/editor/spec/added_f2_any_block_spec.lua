-- Edit opens any block, whatever it holds: the maintainer's
-- ruling of November 14, 2026 overrides IS1.3's refusal of
-- Edit. The language's check at submission is the only one:
-- a Lua draft over a limit, or one that does not parse, is
-- refused at Enter, and a text file has no limit.
-- Keys only, through tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it

--- a name no formatter can wrap
local LONG = string.rep("a", 70) .. " = 1"

--- `n` lines of text, each its number
local function numbered(n, from)
  local t = { }
  for i = 1, n do
    t[i] = "line " .. (from or 0) + i
  end
  return t
end

--- open `text` as main.lua, browsed to its first block, and
--- press Edit on it
local function edit_first(text)
  K.reset({ ["main.lua"] = text })
  K.open()
  K.browse_to(1)
  K.keys("f2")
end

describe("Edit opens any block #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("a Lua block over the size limit", function()
    local TEXT = K.block(15) .. "y = 2\n"

    spec_it("IS1.3 Handle size limits: Edit opens a block of 15 "
        .. "lines into the field, the replacing state", function()
      edit_first(TEXT)
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      assert.same(table.concat(K.block_lines(15), "\n"), K.draft())
      assert.is_nil(K.message())
    end)

    spec_it("IS3.3 Check Lua submission: a block of 15 lines "
        .. "submitted unchanged is refused with the limit's "
        .. "notice, the draft and the file as they were",
      function()
        edit_first(TEXT)
        K.keys("return")
        assert.same("replacing", K.state())
        assert.same(1, K.target())
        assert.same(table.concat(K.block_lines(15), "\n"),
          K.draft())
        assert.truthy((K.message() or ""):find(
          "Block of 15 lines, the limit is 14", 1, true))
        assert.same(TEXT, K.file())
        assert.same({ }, K.writes())
      end)

    spec_it("IS5.3 Accept a replacement: a block of 15 lines "
        .. "shortened to 14 is accepted", function()
      edit_first(TEXT)
      -- the cursor is at the end of `end`: up to the line
      -- above, emptied and joined to the one before it
      K.keys("up")
      K.keys("home")
      K.keys("lctrl", "k")
      K.keys("backspace")
      K.keys("return")
      assert.same("browsing", K.state())
      assert.same(K.block(14) .. "y = 2\n", K.file())
    end)

    spec_it("IS5.3 Accept a replacement: a block of 15 lines "
        .. "split into two is accepted as two blocks", function()
      edit_first(TEXT)
      -- up from `end` to `  v6 = 6`, the seventh line
      for _ = 1, 8 do K.keys("up") end
      K.keys("end")
      K.keys("lshift", "return")
      K.type("end")
      K.keys("lshift", "return")
      K.type("function g()")
      K.keys("return")
      assert.same("browsing", K.state())
      local f = { "function f()" }
      for i = 1, 6 do f[#f + 1] = "  v" .. i .. " = " .. i end
      f[#f + 1] = "end"
      f[#f + 1] = "function g()"
      for i = 7, 13 do f[#f + 1] = "  v" .. i .. " = " .. i end
      f[#f + 1] = "end"
      assert.same(table.concat(f, "\n") .. "\ny = 2\n", K.file())
      assert.same(3, K.blocks())
    end)

    spec_it("IS5.7 Cancel an edit with Escape: Escape drops the "
        .. "edit of a block over the limit, the file as it was",
      function()
        edit_first(TEXT)
        K.keys("return")
        K.keys("escape")
        assert.same("browsing", K.state())
        assert.is_nil(K.target())
        assert.same("", K.draft())
        assert.same(TEXT, K.file())
      end)
  end)

  describe("a Lua line the formatter cannot wrap", function()
    local TEXT = LONG .. "\ny = 2\n"

    -- a guard: Edit opened a one-line block before too
    spec_it("IS3.3 Check Lua submission: Edit opens a block "
        .. "with a name of 70 characters, and Enter refuses it "
        .. "with the line's notice", function()
      edit_first(TEXT)
      assert.same("replacing", K.state())
      -- formatted as far as the formatter can: the name stays
      -- whole on its line
      local loaded = K.draft()
      assert.same(string.rep("a", 70), loaded:sub(1, 70))
      K.keys("return")
      assert.same("replacing", K.state())
      assert.same(loaded, K.draft())
      assert.truthy((K.message() or ""):find(
        "characters, the limit is 64", 1, true))
      assert.same(TEXT, K.file())
      -- shortened, it is accepted
      K.keys("lctrl", "home")
      for _ = 1, 10 do K.keys("delete") end
      K.keys("return")
      assert.same("browsing", K.state())
      assert.same(string.rep("a", 60) .. " = 1\ny = 2\n", K.file())
    end)
  end)

  describe("a line of a file that does not parse", function()
    local BROKEN = "x = 1\n?\n  function f(\ny = 2\n"

    spec_it("IS1.2 Admit or refuse a file: a line opened with "
        .. "Edit that still does not parse is refused at Enter "
        .. "with the parser's message", function()
      K.reset({ ["main.lua"] = BROKEN })
      K.open()
      K.browse_to(2)
      K.keys("f2")
      assert.same("?", K.draft())
      K.keys("return")
      assert.same("replacing", K.state())
      assert.same("error", K.message_kind())
      assert.same(BROKEN, K.file())
    end)

    spec_it("IS1.2 Admit or refuse a file: a line opened with "
        .. "Edit and repaired replaces that line alone, every "
        .. "other byte as it was", function()
      K.reset({ ["main.lua"] = BROKEN })
      K.open()
      K.browse_to(2)
      K.keys("f2")
      K.keys("backspace")
      K.type("z = 3")
      K.keys("return")
      assert.same("browsing", K.state())
      assert.same("x = 1\nz = 3\n  function f(\ny = 2\n",
        K.file())
      -- the file does not parse yet: still a line per block
      assert.same(4, K.blocks())
    end)

    spec_it("IS3.5 Continue input on a new line: a line opened "
        .. "with Edit that is an unfinished statement goes on, "
        .. "on a new line, and once whole it replaces the line",
      function()
        K.reset({ ["main.lua"] = BROKEN })
        K.open()
        K.browse_to(3)
        K.keys("f2")
        assert.same("replacing", K.state())
        assert.same("  function f(", K.draft())
        K.keys("return")
        assert.same("  function f(\n", K.draft())
        assert.same(BROKEN, K.file())
        K.keys("backspace")
        K.type(") return 1 end")
        K.keys("return")
        assert.same("browsing", K.state())
        assert.same("x = 1\n?\nfunction f()\n  return 1\nend\n"
          .. "y = 2\n", K.file())
      end)
  end)

  describe("a tall draft in the field", function()
    spec_it("IS3.10 Keep the cursor visible: in a block of 40 "
        .. "lines opened with Edit the cursor reaches the first "
        .. "and the last line, and the field shows it there",
      function()
        edit_first(K.block(40))
        local function shown(l)
          local rows = K.field_rows()
          local want = K.block_lines(40)[l]
          for _, r in ipairs(rows) do
            if r == want then return #rows end
          end
          return nil
        end
        assert.same(40, (K.cursor()))
        assert.truthy(shown(40))
        for _ = 1, 39 do K.keys("up") end
        assert.same(1, (K.cursor()))
        local rows = shown(1)
        assert.truthy(rows)
        assert.is_true(rows <= 8)
        local s = K.screen()
        assert.is_true(s.field_rows <= 8)
        for _ = 1, 39 do K.keys("down") end
        assert.same(40, (K.cursor()))
        assert.truthy(shown(40))
        K.screen()
        -- one step past either end stays
        K.keys("down")
        assert.same(40, (K.cursor()))
      end)
  end)

  describe("a text file has no limit", function()
    -- guards: text had no limit before either
    spec_it("IS8.2 Submit text: a line replaced by a draft of "
        .. "200 lines is accepted, every other line as it was",
      function()
        local text = "head\nold\nfoot\n"
        K.reset({ ["notes.txt"] = text })
        K.open("notes.txt")
        K.browse_to(2)
        K.keys("f2")
        assert.same("replacing", K.state())
        local lines = numbered(200)
        for _ = 1, 3 do K.keys("backspace") end
        assert.same("", K.draft())
        K.type_lines(lines)
        assert.same(200, #K.ed.input:get_text())
        K.keys("return")
        assert.same("browsing", K.state())
        local file = K.file("notes.txt")
        assert.same("head\n" .. table.concat(lines, "\n")
          .. "\nfoot\n", file)
      end)

    spec_it("IS8.2 Submit text: a draft of 200 lines inserted "
        .. "into a text file is accepted, and a line in the "
        .. "middle of them is edited and saved alone", function()
      K.reset({ ["notes.txt"] = "" })
      K.open("notes.txt")
      local lines = numbered(200)
      K.type_lines(lines)
      K.keys("return")
      local text = table.concat(lines, "\n") .. "\n"
      assert.same(text, K.file("notes.txt"))
      assert.same(200, K.blocks())
      K.browse_to(100)
      K.keys("f2")
      assert.same("line 100", K.draft())
      K.type("!")
      K.keys("return")
      assert.same((text:gsub("line 100\n", "line 100!\n")),
        K.file("notes.txt"))
    end)
  end)
end)
