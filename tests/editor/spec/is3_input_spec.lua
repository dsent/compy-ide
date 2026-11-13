-- IS3 Preparing and submitting input, with FR3.6 (editor
-- principles, ratified). Keys only, through
-- tests/helpers/editor_keys.lua. IS3.6 is the console's own
-- (not an editor item); IS3.10's bezel clause is a device
-- check.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap
local spec_deviation = marks.spec_deviation

--- An assignment `n` characters long, to one long name: no
--- formatting can shorten it.
local function long_line(n)
  return string.rep("x", n - 4) .. " = 1"
end

--- Open main.lua and start typing at its end.
local function at_end(contents)
  K.reset(contents or { ["main.lua"] = "x = 1\ny = 2\n" })
  K.open()
  K.browse_to_end()
end

describe("IS3 input #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("IS3.1", function()
    spec_it(
        "IS3.1 Prepare input: typing goes in at the cursor, "
        .. "which stays after it", function()
      at_end()
      K.type("ab")
      K.keys("left")
      K.type("X")
      assert.same("aXb", K.draft())
      assert.same({
        1,
        3
      }, { K.cursor() })
    end)

    spec_gap("IS3.1 Prepare input: typing on a block begins an "
        .. "insertion and leaves the block alone", function(gap)
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(1)
      K.type("z")
      gap(function()
        assert.same("inserting", K.state())
        assert.same("z", K.draft())
        assert.is_nil(K.target())
      end)
    end)

    spec_it("IS3.1 Prepare input: removing text leaves the " ..
        "cursor where the removed range began", function()
      at_end()
      K.type("abc")
      K.keys("backspace")
      assert.same("ab", K.draft())
      assert.same({
        1,
        3
      }, { K.cursor() })
    end)

    spec_it("IS3.1 Prepare input: a draft may hold several " ..
        "lines and statements", function()
      at_end()
      K.type_lines({
        "a = 1",
        "b = 2"
      })
      assert.same("a = 1\nb = 2", K.draft())
      assert.same("inserting", K.state())
    end)
  end)

  describe("IS3.2", function()
    spec_it(
        "IS3.2 Show Lua interpretation: the draft keeps the "
        .. "user's spelling while typing", function()
      at_end()
      K.type("z=3")
      assert.same("z=3", K.draft())
    end)

    spec_it("IS3.2 Show Lua interpretation: an accepted draft "
        .. "is stored canonically formatted", function()
      at_end()
      K.type("z=3")
      K.keys("return")
      assert.same("x = 1\ny = 2\nz = 3\n", K.file())
    end)

    spec_it("IS3.2 Show Lua interpretation: the line-length "
        .. "check counts formatted lines", function()
      at_end()
      local stmts = { }
      for i = 1, 13 do
        stmts[i] = "a" .. i .. "=1"
      end
      -- one draft line over 64 characters; formatted, thirteen
      -- short lines
      local line = table.concat(stmts, " ")
      assert.is_true(64 < #line)
      K.type(line)
      K.keys("return")
      assert.same("", K.draft())
      assert.truthy(K.file():find("\na13 = 1\n", 1, true))
    end)
  end)

  describe("IS3.3", function()
    spec_it("IS3.3 Check Lua submission: an incorrect draft "
        .. "leaves the file as it was", function()
      at_end()
      K.type("z = = 1")
      K.keys("return")
      assert.same("x = 1\ny = 2\n", K.file())
      assert.same("z = = 1", K.draft())
    end)

    spec_it("IS3.3 Check Lua submission: an incorrect console "
        .. "command is not executed", function()
      K.reset()
      K.type("edit(\"main.lua\"")
      K.keys("return")
      assert.same("ready", K.app_state())
    end)

    spec_gap("IS3.3 Check Lua submission: a line over 64 " ..
        "characters is refused, the notice naming 64", function(
      gap
    )
      at_end()
      K.type(long_line(70))
      K.keys("return")
      gap(function()
        -- the draft stays, shown formatted (IS3.2)
        assert.are_not.same("", K.draft())
        assert.same("x = 1\ny = 2\n", K.file())
        assert.truthy((K.message() or ""):find("64", 1, true))
      end)
    end)

    spec_gap(
        "IS3.3 Check Lua submission: a block over 14 lines " ..
        "is refused, the notice naming 14", function(gap)
      at_end()
      K.type_lines(K.block_lines(15))
      K.keys("return")
      gap(function()
        assert.same("x = 1\ny = 2\n", K.file())
        assert.truthy((K.message() or ""):find("14", 1, true))
      end)
    end)
  end)

  describe("IS3.3, the line limit", function()
    spec_it("IS3.3 Check Lua submission: a string line of 64 "
      .. "characters is accepted as written", function()
      at_end()
      local line = 's = "' .. string.rep("x", 58) .. '"'
      assert.same(64, #line)
      K.type(line)
      K.keys("return")
      assert.same("", K.draft())
      assert.same("x = 1\ny = 2\n" .. line .. "\n", K.file())
    end)
  end)

  describe("IS3.4 and IS3.5", function()
    spec_gap("IS3.4 Locate a syntax failure: Enter puts the "
        .. "cursor before the failing character", function(gap)
      at_end()
      -- the second "=" (column 5) is where parsing fails
      K.type("z = = 1 + 2")
      K.keys("return")
      gap(function()
        assert.same({
          1,
          5
        }, { K.cursor() })
      end)
    end)

    spec_gap("IS3.4 Locate a syntax failure: the text from the "
        .. "failing character on is red", function(gap)
      at_end()
      K.type("z = = 1 + 2")
      local _, at = K.field_highlight()
      gap(function()
        assert.same({
          1,
          5
        }, at)
      end)
    end)

    spec_gap("IS3.5 Continue input on a new line: a draft that "
        .. "fails only at its end shows no red", function(gap)
      at_end()
      local line = "for i = 1, 2 do"
      K.type(line)
      local _, at = K.field_highlight()
      gap(function()
        -- an error, if any, starts past the last character
        local red = at and at[1] == 1 and at[2] <= #line
        assert.is_falsy(red)
      end)
    end)

    spec_gap("IS3.5 Continue input on a new line: Enter on a "
        .. "draft incomplete at its end adds a line", function(
      gap
    )
      at_end()
      K.type("for i = 1, 2 do")
      K.keys("home")
      K.keys("return")
      gap(function()
        assert.same("for i = 1, 2 do\n", K.draft())
        assert.same({
          2,
          1
        }, { K.cursor() })
        assert.same("x = 1\ny = 2\n", K.file())
      end)
    end)
  end)

  describe("IS3.7", function()
    spec_it(
        "IS3.7 Preserve accepted Lua: statements on one line "
        .. "become separate blocks", function()
      at_end()
      K.type("a = 1; b = 2")
      K.keys("return")
      assert.same(4, K.blocks())
      assert.same("x = 1\ny = 2\na = 1\nb = 2\n", K.file())
    end)

    spec_gap(
        "IS3.7 Preserve accepted Lua: each empty line of a " ..
        "draft becomes an empty-line block", function(gap)
      at_end()
      K.type_lines({
        "a = 1",
        "",
        "",
        "b = 2"
      })
      K.keys("return")
      gap(function()
        assert.same(
          "x = 1\ny = 2\na = 1\n\n\nb = 2\n",
          K.file()
        )
      end)
    end)
  end)

  describe("IS3.7, a draft of empty lines", function()
    spec_gap(
        "IS3.7 Preserve accepted Lua: a draft of only empty "
        .. "lines becomes empty-line blocks", function(gap)
      at_end()
      K.keys("lshift", "return")
      local drafted = K.draft()
      K.keys("return")
      gap(function()
        assert.same("\n", drafted)
        assert.same("x = 1\ny = 2\n\n\n", K.file())
      end)
    end)
  end)

  describe("IS3.8", function()
    spec_it(
        "IS3.8 Position the text cursor: Left crosses a line "
        .. "break", function()
      at_end()
      K.type_lines({
        "ab",
        "cd"
      })
      K.keys("home")
      K.keys("left")
      assert.same({
        1,
        3
      }, { K.cursor() })
    end)

    spec_gap("IS3.8 Position the text cursor: Ctrl+Left and "
        .. "Ctrl+Right move by word", function(gap)
      at_end()
      K.type("foo bar_baz")
      K.keys("lctrl", "left")
      local left = { K.cursor() }
      K.keys("lctrl", "left")
      local start = { K.cursor() }
      K.keys("lctrl", "right")
      gap(function()
        assert.same({
          1,
          5
        }, left)
        assert.same({
          1,
          1
        }, start)
        assert.same({
          1,
          4
        }, { K.cursor() })
      end)
    end)

    spec_it("IS3.8 Position the text cursor: Ctrl+Home and " ..
        "Ctrl+End reach the draft's start and end", function()
      at_end()
      K.type_lines({
        "ab",
        "cd"
      })
      K.keys("lctrl", "home")
      assert.same({
        1,
        1
      }, { K.cursor() })
      K.keys("lctrl", "end")
      assert.same({
        2,
        3
      }, { K.cursor() })
    end)

    spec_it(
        "IS3.8 Position the text cursor: in an insertion, Up "
        .. "on the first row goes to the draft's start",
        function()
      at_end()
      K.type_lines({
        "ab",
        "cd"
      })
      K.keys("up")
      K.keys("up")
      assert.same({
        1,
        1
      }, { K.cursor() })
      assert.same("ab\ncd", K.draft())
      assert.same("end", K.position())
    end)

    spec_gap(
        "IS3.8 Position the text cursor: in a replacement, " ..
        "Up on the first row never browses", function(gap)
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(2)
      K.keys("f2")
      K.keys("up")
      gap(function()
        assert.same("replacing", K.state())
        assert.same("y = 2", K.draft())
        assert.same({
          1,
          1
        }, { K.cursor() })
        assert.same(2, K.position())
      end)
    end)

    spec_it("IS3.8 Position the text cursor: Down keeps the "
        .. "offset, or stops at a shorter row's end", function()
      at_end()
      K.type_lines({
        "abcdef",
        "xy",
        "abcdef"
      })
      K.keys("lctrl", "home")
      for _ = 1, 4 do
        K.keys("right")
      end
      K.keys("down")
      assert.same({
        2,
        3
      }, { K.cursor() })
    end)

    spec_it("IS3.8 Position the text cursor: moving it changes "
        .. "neither the draft nor the position", function()
      at_end()
      K.type("abc")
      K.keys("left")
      K.keys("home")
      K.keys("right")
      assert.same("abc", K.draft())
      assert.same("end", K.position())
      assert.is_nil(K.target())
    end)
  end)

  describe("IS3.9 and FR3.6", function()
    -- a block over 14 lines is refused for size, and the
    -- draft comes back canonically formatted (IS3.2); its
    -- second line is typed "  v1=1", the cursor after "="
    local function refuse_formatted()
      at_end()
      local lines = K.block_lines(15)
      lines[2] = "  v1=1"
      K.type_lines(lines)
      K.keys("lctrl", "home")
      K.keys("down")
      for _ = 1, 5 do
        K.keys("right")
      end
      K.keys("return")
    end

    spec_gap("IS3.9 Preserve cursor through formatting: at an "
        .. "element's boundary, on the same side", function(gap)
      refuse_formatted()
      gap(function()
        assert.truthy(K.draft():find("\n  v1 = 1\n", 1, true))
        -- "=" and "1" shared the boundary: the end of "=" is
        -- preferred (IS3.9), in "  v1 = 1" column 7
        assert.same({
          2,
          7
        }, { K.cursor() })
      end)
    end)

    spec_gap(
        "FR3.6 Preserve cursor position through formatting: "
        .. "the browsing position is unchanged too", function(
      gap
    )
      refuse_formatted()
      gap(function()
        assert.same({
          2,
          7
        }, { K.cursor() })
        assert.same("end", K.position())
      end)
    end)
  end)

  describe("IS3.10 to IS3.12", function()
    spec_gap(
        "IS3.10 Keep the cursor visible: below many wrapped "
        .. "rows, the cursor's row is shown", function(gap)
      at_end()
      local lines = { }
      for n = 1, 10 do
        lines[n] = string.format("%02d", n) .. string.rep(
          "x",
          90
        )
      end
      K.type_lines(lines)
      gap(function()
        local shown = false
        for _, r in ipairs(K.field_rows()) do
          if r:sub(1, 2) == "10" then
            shown = true
          end
        end
        assert.is_true(shown)
      end)
    end)

    spec_gap("IS3.11 Preserve state on refusal: a refused cut "
        .. "keeps the draft and the cursor", function(gap)
      at_end()
      K.type("abc")
      K.keys("left")
      K.keys("left")
      -- a cut is the browsing state's; here it is refused
      K.keys("lctrl", "delete")
      gap(function()
        assert.same("abc", K.draft())
        assert.same({
          1,
          2
        }, { K.cursor() })
        assert.same("end", K.position())
        assert.same("x = 1\ny = 2\n", K.file())
      end)
    end)

    spec_gap(
        "IS3.12 Keep deletion keys in the draft: Delete and "
        .. "Backspace on an empty field change nothing",
        function(gap)
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(1)
      for _ = 1, 3 do
        K.keys("backspace")
        K.keys("delete")
      end
      gap(function()
        assert.same("x = 1\ny = 2\n", K.file())
        assert.same(2, K.blocks())
        assert.same(1, K.position())
      end)
    end)

    spec_gap("IS3.12 Keep deletion keys in the draft: Ctrl+K "
        .. "removes to the end of the line", function(gap)
      at_end()
      K.type_lines({
        "abc def",
        "gh"
      })
      K.keys("lctrl", "home")
      for _ = 1, 3 do
        K.keys("right")
      end
      K.keys("lctrl", "k")
      gap(function()
        assert.same("abc\ngh", K.draft())
        assert.same("x = 1\ny = 2\n", K.file())
      end)
    end)
  end)

  describe("IS3.13", function()
    spec_it("IS3.13 Wrap long lines: a row break is one " ..
        "character boundary", function()
      at_end({
        ["main.lua"] = "x = 1\n",
        ["a.txt"] = "one\n"
      })
      K.restart()
      K.open("a.txt")
      K.browse_to_end()
      local line = string.rep("abcdefghij", 7)
      K.type(line)
      K.keys("lctrl", "home")
      for _ = 1, 64 do
        K.keys("right")
      end
      K.keys("backspace")
      assert.same(line:sub(1, 63) .. line:sub(65), K.draft())
    end)

    spec_gap("IS3.13 Wrap long lines: Home and End move by row"
        , function(gap)
      K.reset({ ["a.txt"] = "one\n" })
      K.open("a.txt")
      K.browse_to_end()
      K.type(string.rep("abcdefghij", 7))
      K.keys("home")
      gap(function()
        -- the second row starts after 64 characters
        assert.same({
          1,
          65
        }, { K.cursor() })
      end)
    end)

    spec_it(
        "IS3.13 Wrap long lines: past the field's height the "
        .. "draft scrolls to the cursor", function()
      K.reset({ ["a.txt"] = "one\n" })
      K.open("a.txt")
      K.browse_to_end()
      local lines = { }
      for n = 1, 20 do
        lines[n] = "line " .. n
      end
      K.type_lines(lines)
      local rows = K.field_rows()
      assert.same("line 20", rows[#rows])
      K.keys("lctrl", "home")
      assert.same("line 1", K.field_rows()[1])
    end)

    spec_gap("IS3.13 Wrap long lines: the field takes at most "
        .. "half the rows", function(gap)
      K.reset({ ["a.txt"] = "one\n" })
      K.open("a.txt")
      K.browse_to_end()
      local lines = { }
      for n = 1, 20 do
        lines[n] = "line " .. n
      end
      K.type_lines(lines)
      gap(function()
        -- 17 rows besides the status line on this screen
        assert.is_true(#K.field_rows() <= 8)
      end)
    end)
  end)

  describe("IS3.14 and IS3.15", function()
    spec_gap(
        "IS3.14 Explain a refusal: a refused action shows a "
        .. "notice the next key dismisses", function(gap)
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to_end()
      -- no block at the end position: Ctrl+Delete is refused
      K.keys("lctrl", "delete")
      local notice = K.message()
      K.keys("lctrl", "up")
      gap(function()
        assert.is_not_nil(notice)
        assert.is_nil(K.message())
        assert.same(2, K.position())
        assert.same("x = 1\ny = 2\n", K.file())
      end)
    end)

    spec_it(
        "IS3.15 Break a line: Shift+Enter breaks the line at "
        .. "the cursor and submits nothing", function()
      at_end()
      K.type("abcd")
      K.keys("left")
      K.keys("left")
      K.keys("lshift", "return")
      assert.same("ab\ncd", K.draft())
      assert.same({
        2,
        1
      }, { K.cursor() })
      assert.same("x = 1\ny = 2\n", K.file())
      assert.same("end", K.position())
    end)

    spec_gap("IS3.15 Break a line: Alt+Enter breaks it too",
        function(gap)
      at_end()
      K.type("abcd")
      K.keys("left")
      K.keys("left")
      K.keys("lalt", "return")
      gap(function()
        assert.same("ab\ncd", K.draft())
        assert.same("x = 1\ny = 2\n", K.file())
      end)
    end)
  end)

  describe("IS3.16", function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1\n" })
    end)

    spec_gap(
        "IS3.16 Show the key card: in the file editor, while "
        .. "F1 is held", function(gap)
      K.open()
      K.hold("f1")
      local card = K.key_card()
      K.release("f1")
      gap(function()
        assert.is_not_nil(card)
      end)
    end)

    spec_gap("IS3.16 Show the key card: other keys do nothing "
        .. "while F1 is held", function(gap)
      K.open()
      K.browse_to_end()
      K.hold("f1")
      K.type("z")
      K.release("f1")
      gap(function()
        assert.same("", K.draft())
      end)
    end)

    spec_deviation("IS3.16 Show the key card: in the console "
        .. "no card shows",
        "design decision D3: the key card is " ..
        "the file editor's only, for now", function()
      K.type("x")
      K.hold("f1")
      local card = K.key_card()
      K.release("f1")
      assert.is_nil(card)
      assert.same("ready", K.app_state())
      assert.same("x", K.console_draft())
    end)
  end)
end)
