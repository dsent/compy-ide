-- IS3 Preparing and submitting input, with FR3.6 (editor
-- principles, ratified). Keys only, through
-- tests/helpers/editor_keys.lua. IS3.6 is the console's own
-- (not an editor item); IS3.10's bezel clause is a device
-- check.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

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

    spec_it("IS3.1 Prepare input: typing on a block begins an "
        .. "insertion and leaves the block alone", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(1)
      K.type("z")
      assert.same("inserting", K.state())
      assert.same("z", K.draft())
      assert.is_nil(K.target())
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

    spec_it("IS3.3 Check Lua submission: a line over 64 " ..
        "characters is refused, the notice naming 64", function()
      at_end()
      K.type(long_line(70))
      K.keys("return")
      -- the draft stays, shown formatted (IS3.2)
      assert.are_not.same("", K.draft())
      assert.same("x = 1\ny = 2\n", K.file())
      assert.truthy((K.message() or ""):find("64", 1, true))
    end)

    spec_it(
        "IS3.3 Check Lua submission: a block over 14 lines " ..
        "is refused, the notice naming 14", function()
      at_end()
      K.type_lines(K.block_lines(15))
      K.keys("return")
      assert.same("x = 1\ny = 2\n", K.file())
      assert.truthy((K.message() or ""):find("14", 1, true))
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
    spec_it("IS3.4 Locate a syntax failure: Enter puts the "
        .. "cursor before the failing character", function()
      at_end()
      -- the second "=" (column 5) is where parsing fails
      K.type("z = = 1 + 2")
      K.keys("return")
      assert.same({
        1,
        5
      }, { K.cursor() })
    end)

    spec_it("IS3.4 Locate a syntax failure: the text from the "
        .. "failing character on is red", function()
      at_end()
      K.type("z = = 1 + 2")
      local _, at = K.field_highlight()
      assert.same({
        1,
        5
      }, at)
    end)

    spec_it("IS3.5 Continue input on a new line: a draft that "
        .. "fails only at its end shows no red", function()
      at_end()
      local line = "for i = 1, 2 do"
      K.type(line)
      local _, at = K.field_highlight()
      -- an error, if any, starts past the last character
      local red = at and at[1] == 1 and at[2] <= #line
      assert.is_falsy(red)
    end)

    spec_it("IS3.5 Continue input on a new line: Enter on a "
        .. "draft incomplete at its end adds a line", function()
      at_end()
      K.type("for i = 1, 2 do")
      K.keys("home")
      K.keys("return")
      assert.same("for i = 1, 2 do\n", K.draft())
      assert.same({
        2,
        1
      }, { K.cursor() })
      assert.same("x = 1\ny = 2\n", K.file())
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

    spec_it(
        "IS3.7 Preserve accepted Lua: each empty line of a " ..
        "draft becomes an empty-line block", function()
      at_end()
      K.type_lines({
        "a = 1",
        "",
        "",
        "b = 2"
      })
      K.keys("return")
      assert.same(
        "x = 1\ny = 2\na = 1\n\n\nb = 2\n",
        K.file()
      )
    end)
  end)

  describe("IS3.7, a draft of empty lines", function()
    spec_it(
        "IS3.7 Preserve accepted Lua: a draft of only empty "
        .. "lines becomes empty-line blocks", function()
      -- IS3.7 names the empty lines between blocks; for a
      -- draft with no statement the reference decides (Luditor
      -- src/lua/chunker.rs: one empty-line block per blank
      -- line), as an empty draft is one line (IS4.3)
      at_end()
      K.keys("lshift", "return")
      local drafted = K.draft()
      K.keys("return")
      assert.same("\n", drafted)
      assert.same("x = 1\ny = 2\n\n\n", K.file())
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

    spec_it("IS3.8 Position the text cursor: Ctrl+Left and "
        .. "Ctrl+Right move by word", function()
      at_end()
      K.type("foo bar_baz")
      K.keys("lctrl", "left")
      local left = { K.cursor() }
      K.keys("lctrl", "left")
      local start = { K.cursor() }
      K.keys("lctrl", "right")
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

    spec_it(
        "IS3.8 Position the text cursor: in a replacement, " ..
        "Up on the first row never browses", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(2)
      K.keys("f2")
      K.keys("up")
      assert.same("replacing", K.state())
      assert.same("y = 2", K.draft())
      assert.same({
        1,
        1
      }, { K.cursor() })
      assert.same(2, K.position())
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

    spec_it("IS3.9 Preserve cursor through formatting: at an "
        .. "element's boundary, on the same side", function()
      refuse_formatted()
      assert.truthy(K.draft():find("\n  v1 = 1\n", 1, true))
      -- "=" and "1" shared the boundary: the end of "=" is
      -- preferred (IS3.9), in "  v1 = 1" column 7
      assert.same({
        2,
        7
      }, { K.cursor() })
    end)

    spec_it(
        "FR3.6 Preserve cursor position through formatting: "
        .. "the browsing position is unchanged too", function()
      refuse_formatted()
      assert.same({
        2,
        7
      }, { K.cursor() })
      assert.same("end", K.position())
    end)
  end)

  describe("IS3.10 to IS3.12", function()
    spec_it(
        "IS3.10 Keep the cursor visible: below many wrapped "
        .. "rows, the cursor's row is shown", function()
      at_end()
      local lines = { }
      -- 92 characters, two rows; a line's number ends its
      -- second row, where the cursor comes to stand
      for n = 1, 10 do
        local nn = string.format("%02d", n)
        lines[n] = nn .. string.rep("x", 88) .. nn
      end
      K.type_lines(lines)
      local rows = K.field_rows()
      assert.same(string.rep("x", 26) .. "10", rows[#rows])
    end)

    spec_it("IS3.11 Preserve state on refusal: a refused cut "
        .. "keeps the draft and the cursor", function()
      at_end()
      K.type("abc")
      K.keys("left")
      K.keys("left")
      -- a cut is the browsing state's; here it is refused
      K.keys("lctrl", "delete")
      assert.same("abc", K.draft())
      assert.same({
        1,
        2
      }, { K.cursor() })
      assert.same("end", K.position())
      assert.same("x = 1\ny = 2\n", K.file())
    end)

    spec_it(
        "IS3.12 Keep deletion keys in the draft: Delete and "
        .. "Backspace on an empty field change nothing",
        function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(1)
      for _ = 1, 3 do
        K.keys("backspace")
        K.keys("delete")
      end
      assert.same("x = 1\ny = 2\n", K.file())
      assert.same(2, K.blocks())
      assert.same(1, K.position())
    end)

    spec_it("IS3.12 Keep deletion keys in the draft: Ctrl+K "
        .. "removes to the end of the line", function()
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
      assert.same("abc\ngh", K.draft())
      assert.same("x = 1\ny = 2\n", K.file())
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

    spec_it("IS3.13 Wrap long lines: Home and End move by row"
        , function()
      K.reset({ ["a.txt"] = "one\n" })
      K.open("a.txt")
      K.browse_to_end()
      K.type(string.rep("abcdefghij", 7))
      K.keys("home")
      -- the second row starts after 64 characters
      assert.same({
        1,
        65
      }, { K.cursor() })
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

    spec_it("IS3.13 Wrap long lines: the field takes at most "
        .. "half the rows", function()
      K.reset({ ["a.txt"] = "one\n" })
      K.open("a.txt")
      K.browse_to_end()
      local lines = { }
      for n = 1, 20 do
        lines[n] = "line " .. n
      end
      K.type_lines(lines)
      -- 17 rows besides the status line on this screen
      assert.is_true(#K.field_rows() <= 8)
    end)
  end)

  describe("IS3.14 and IS3.15", function()
    spec_it(
        "IS3.14 Explain a refusal: a refused action shows a "
        .. "notice the next key dismisses", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to_end()
      -- no block at the end position: Ctrl+Delete is refused
      K.keys("lctrl", "delete")
      local notice = K.message()
      K.keys("lctrl", "up")
      assert.is_not_nil(notice)
      -- it names what was refused and the action that works
      assert.truthy(notice:find("no block to cut", 1, true))
      assert.truthy(notice:find("Move up", 1, true))
      assert.is_nil(K.message())
      assert.same(2, K.position())
      assert.same("x = 1\ny = 2\n", K.file())
    end)

    spec_it("IS3.14 Explain a refusal: a typed letter "
        .. "dismisses the notice and is typed", function()
      at_end()
      K.keys("lctrl", "delete")
      local notice = K.message()
      K.type("z")
      assert.is_not_nil(notice)
      assert.is_nil(K.message())
      assert.same("z", K.draft())
      assert.same("x = 1\ny = 2\n", K.file())
    end)

    spec_it("IS3.14 Explain a refusal: a letter whose text "
        .. "arrives before its key press is typed once",
        function()
      at_end()
      K.keys("lctrl", "delete")
      local notice = K.message()
      K.type_text_first("z")
      assert.is_not_nil(notice)
      assert.is_nil(K.message())
      assert.same("z", K.draft())
      -- and with Shift held
      K.keys("lctrl", "delete")
      local again = K.message()
      K.type_text_first("Q")
      assert.is_not_nil(again)
      assert.is_nil(K.message())
      assert.same("zQ", K.draft())
    end)

    spec_it("IS3.14 Explain a refusal: text that arrives "
        .. "with Ctrl held types nothing and leaves the notice",
        function()
      at_end()
      K.keys("lctrl", "delete")
      local notice = K.message()
      -- a glyph with no key of its own: it is sent as text
      K.hold("lctrl")
      K.type("é")
      K.release("lctrl")
      assert.is_not_nil(notice)
      assert.same(notice, K.message())
      assert.same("", K.draft())
    end)

    spec_it("IS3.14 Explain a refusal: a syntax failure's "
        .. "message goes at the next key too, which acts",
        function()
      at_end()
      K.type("x = = 1")
      K.keys("return")
      local message = K.message()
      K.keys("delete")
      assert.is_not_nil(message)
      assert.is_nil(K.message())
      -- the cursor stood before the failing `=`
      assert.same("x =  1", K.draft())
    end)

    -- Each refusal during an edit names the two ways to end
    -- it, in the reference editor's words for the case.
    local ADDS = "Finish the text first: Enter adds it, " ..
        "Esc drops it."
    local KEEPS = "Finish the text first: Enter keeps it, " ..
        "Esc drops it."
    local EDITING = "Finish editing first: Enter keeps it, " ..
        "Esc drops it."
    local ALREADY = "Already editing a block: Enter keeps it, "
        .. "Esc drops it."

    --- an insertion: a draft with the highlight on block 1
    local function inserting()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(1)
      K.type("z")
    end

    --- a replacement of block 1, the draft modified
    local function replacing()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(1)
      K.keys("f2")
      K.type("0")
    end

    spec_it("IS3.14 Explain a refusal: Edit and a cut during "
        .. "an insertion say that Enter adds the text",
        function()
      inserting()
      K.keys("f2")
      local edit = K.message()
      K.keys("lctrl", "delete")
      assert.same(ADDS, edit)
      assert.same(ADDS, K.message())
      assert.same("inserting", K.state())
      assert.same("z", K.draft())
    end)

    spec_it("IS3.14 Explain a refusal: a cut and a move "
        .. "during a replacement say to finish editing",
        function()
      replacing()
      K.keys("lctrl", "delete")
      local cut = K.message()
      K.keys("lalt", "down")
      assert.same(EDITING, cut)
      assert.same(EDITING, K.message())
      assert.same("replacing", K.state())
      assert.same("x = 10", K.draft())
      assert.same("x = 1\ny = 2\n", K.file())
    end)

    spec_it("IS3.14 Explain a refusal: Edit on another block "
        .. "with the draft modified says a block is being "
        .. "edited", function()
      replacing()
      K.browse_to(2)
      K.keys("f2")
      assert.same(ALREADY, K.message())
      assert.same(1, K.target())
      assert.same("x = 10", K.draft())
    end)

    spec_it("IS3.14 Explain a refusal: following a reference "
        .. "and leaving during an edit say that Enter keeps "
        .. "the text", function()
      inserting()
      K.keys("lctrl", "j")
      local follow = K.message()
      K.keys("lctrl", "lshift", "s")
      local leave = K.message()
      K.keys("lctrl", "q")
      assert.same(KEEPS, follow)
      assert.same(KEEPS, leave)
      assert.same(KEEPS, K.message())
      assert.same("editor", K.app_state())
      assert.same("z", K.draft())
      replacing()
      K.keys("lctrl", "j")
      assert.same(KEEPS, K.message())
      assert.same("x = 10", K.draft())
    end)

    spec_it("IS3.14 Explain a refusal: a modifier or a lock "
        .. "on its own leaves the notice showing", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to_end()
      K.keys("lctrl", "delete")
      local notice = K.message()
      for _, k in ipairs({
        "lshift", "rshift", "lctrl", "lalt", "ralt",
        "lgui", "rgui", "capslock", "f1"
      }) do
        K.keys(k)
        assert.same(notice, K.message(), k)
      end
      K.keys("capslock")
      -- the next key that does something dismisses it
      K.keys("lctrl", "up")
      assert.is_not_nil(notice)
      assert.is_nil(K.message())
      assert.same(2, K.position())
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

    spec_it("IS3.15 Break a line: Alt+Enter breaks it too",
        function()
      at_end()
      K.type("abcd")
      K.keys("left")
      K.keys("left")
      K.keys("lalt", "return")
      assert.same("ab\ncd", K.draft())
      assert.same("x = 1\ny = 2\n", K.file())
    end)
  end)

  describe("IS3.16", function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1\n" })
    end)

    spec_it(
        "IS3.16 Show the key card: in the file editor, while "
        .. "F1 is held", function()
      K.open()
      K.hold("f1")
      local card = K.key_card()
      K.release("f1")
      assert.is_not_nil(card)
    end)

    spec_it("IS3.16 Show the key card: other keys do nothing "
        .. "while F1 is held", function()
      K.open()
      K.browse_to_end()
      K.hold("f1")
      K.type("z")
      K.release("f1")
      assert.same("", K.draft())
    end)

    spec_it("IS3.16 Show the key card: Escape and Ctrl+Q do "
        .. "nothing while F1 is held", function()
      K.open()
      K.hold("f1")
      K.keys("escape")
      K.keys("lctrl", "q")
      K.release("f1")
      assert.same("editor", K.app_state())
      assert.same("main.lua", K.file_name())
    end)

    spec_it("IS3.16 Show the key card: a notice comes back "
        .. "as it was once F1 is released", function()
      K.open()
      K.browse_to_end()
      K.keys("lctrl", "delete")
      local notice = K.message()
      K.hold("f1")
      K.type("z")
      K.release("f1")
      assert.is_not_nil(notice)
      assert.same(notice, K.message())
      assert.same("", K.draft())
    end)

    spec_it("IS3.16 Show the key card: in the console, while "
        .. "F1 is held", function()
      K.type("x")
      K.hold("f1")
      local card = K.key_card()
      -- other keys do nothing meanwhile, Ctrl+Q included
      K.type("y")
      K.keys("return")
      K.keys("lctrl", "q")
      K.release("f1")
      assert.is_not_nil(card)
      assert.truthy(
        table.concat(card, "\n"):find("Enter", 1, true)
      )
      assert.is_nil(K.key_card())
      assert.same("ready", K.app_state())
      assert.same("x", K.console_draft())
      assert.is_not_nil(K.cc.model.projects.current)
    end)
  end)
end)
