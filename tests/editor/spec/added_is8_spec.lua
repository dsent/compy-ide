-- IS8 Plain text and Markdown files (editor principles,
-- ratified): the clauses the tests of is8_text_spec.lua leave
-- out. Keys only, through tests/helpers/editor_keys.lua. Edit
-- is F2; copy is Ctrl+Ins; cut is Ctrl+Delete; move is Alt+Up
-- and Alt+Down.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local TXT = "one\ntwo\nthree\n"
local MD = "# Title\nsome *em* text\n"
local GAPPED = "one\n\ntwo\n"

--- Open `name` from a card holding the three files.
local function open(name)
  K.reset({
    ["a.txt"] = TXT,
    ["b.md"] = MD,
    ["c.txt"] = GAPPED,
    ["notes.log"] = "one\ntwo\n"
  })
  K.open(name)
end

--- Edit (F2) on block `b`.
local function edit(b)
  K.browse_to(b)
  K.keys("f2")
end

describe("IS8 text files, added #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("IS8.1", function()
    spec_it("IS8.1 Open a text or Markdown file: a Markdown "
        .. "file opens browsing, at the end position", function(
      
    )
      open("b.md")
      assert.same("markdown", K.file_type())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same("end", K.position())
      assert.same(2, K.blocks())
      assert.same(MD, K.file("b.md"))
    end)

    spec_it("IS8.1 Open a text or Markdown file: a text file "
        .. "opens browsing, the field empty", function()
      open("a.txt")
      assert.same("plain", K.file_type())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same(3, K.blocks())
    end)

    spec_it("IS8.1 Open a text or Markdown file: Up and Down "
        .. "browse line by line", function()
      open("a.txt")
      K.keys("up")
      local last = K.position()
      K.keys("up")
      local second = K.position()
      K.keys("down")
      K.keys("down")
      assert.same(3, last)
      assert.same(2, second)
      assert.same("end", K.position())
      assert.same(TXT, K.file("a.txt"))
    end)

    spec_it("IS8.1 Open a text or Markdown file: Edit loads a "
        .. "line, the cursor at its end", function()
      open("a.txt")
      edit(2)
      assert.same("replacing", K.state())
      assert.same(2, K.target())
      assert.same("two", K.draft())
      assert.same({
        1,
        4
      }, { K.cursor() })
      assert.same(TXT, K.file("a.txt"))
    end)

    spec_it("IS8.1 Open a text or Markdown file: Edit loads a "
        .. "Markdown line as it is written", function()
      open("b.md")
      edit(1)
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      assert.same("# Title", K.draft())
      assert.same(MD, K.file("b.md"))
    end)

    spec_it("IS8.1 Open a text or Markdown file: Edit is " ..
        "refused on an empty line, with a notice", function()
      open("c.txt")
      edit(2)
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("", K.draft())
      assert.is_not_nil(K.message())
      assert.same(GAPPED, K.file("c.txt"))
    end)

    spec_it("IS8.1 Open a text or Markdown file: Edit on the "
        .. "target reloads the line", function()
      open("a.txt")
      edit(2)
      K.type("!")
      K.keys("f2")
      assert.same("two", K.draft())
      assert.same(2, K.target())
    end)

    spec_it("IS8.1 Open a text or Markdown file: Ctrl+Delete "
        .. "cuts a line into the field", function()
      open("a.txt")
      K.browse_to(2)
      K.keys("lctrl", "delete")
      assert.same("one\nthree\n", K.file("a.txt"))
      assert.same("inserting", K.state())
      assert.same("two", K.draft())
      assert.same({
        1,
        4
      }, { K.cursor() })
      assert.same(2, K.position())
    end)

    spec_it("IS8.1 Open a text or Markdown file: cutting an "
        .. "empty line leaves the field empty", function()
      open("c.txt")
      K.browse_to(2)
      K.keys("lctrl", "delete")
      assert.same("one\ntwo\n", K.file("c.txt"))
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same(2, K.position())
    end)

    spec_it("IS8.1 Open a text or Markdown file: Ctrl+Z puts "
        .. "a cut line back", function()
      open("a.txt")
      K.browse_to(2)
      K.keys("lctrl", "delete")
      K.keys("lctrl", "z")
      assert.same(TXT, K.file("a.txt"))
      assert.same("browsing", K.state())
      assert.same("", K.draft())
    end)

    spec_it("IS8.1 Open a text or Markdown file: Ctrl+Ins " ..
        "copies a line into the field", function()
      open("a.txt")
      K.browse_to(1)
      K.keys("lctrl", "insert")
      assert.same("inserting", K.state())
      assert.same("one", K.draft())
      assert.is_nil(K.target())
      assert.same(TXT, K.file("a.txt"))
    end)

    spec_it("IS8.1 Open a text or Markdown file: Ctrl+Ins " ..
        "puts a copied line on a line of its own", function()
      open("a.txt")
      K.browse_to_end()
      K.type("new")
      local browsed = pcall(K.browse_to, 1)
      K.keys("lctrl", "insert")
      assert.is_true(browsed)
      assert.same("new\none", K.draft())
      assert.same({
        2,
        4
      }, { K.cursor() })
    end)

    spec_it("IS8.1 Open a text or Markdown file: Alt+Up and "
        .. "Alt+Down move a line, the position with it",
        function()
      open("a.txt")
      K.browse_to(2)
      K.keys("lalt", "up")
      local up = {
        K.file("a.txt"),
        K.position()
      }
      K.keys("lalt", "down")
      K.keys("lalt", "down")
      assert.same({
        "two\none\nthree\n",
        1
      }, up)
      assert.same("one\nthree\ntwo\n", K.file("a.txt"))
      assert.same(3, K.position())
    end)

    spec_it("IS8.1 Open a text or Markdown file: Escape drops "
        .. "a replacement, the file as it was", function()
      open("a.txt")
      edit(2)
      K.type("!")
      K.keys("escape")
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("", K.draft())
      assert.same(2, K.position())
      assert.same("editor", K.app_state())
      assert.same(TXT, K.file("a.txt"))
    end)

    spec_it("IS8.1 Open a text or Markdown file: Escape while "
        .. "browsing steps out of the file", function()
      open("b.md")
      K.keys("escape")
      assert.same("ready", K.app_state())
      assert.same(MD, K.file("b.md"))
    end)
  end)

  describe("IS8.2", function()
    spec_it("IS8.2 Submit text: an empty draft inserts an " ..
        "empty line before the position", function()
      open("a.txt")
      K.browse_to(2)
      K.keys("return")
      assert.same("one\n\ntwo\nthree\n", K.file("a.txt"))
      assert.same("browsing", K.state())
      assert.same(3, K.position())
    end)

    spec_it("IS8.2 Submit text: an empty draft at the end " ..
        "appends an empty line", function()
      open("b.md")
      K.keys("return")
      assert.same(MD .. "\n", K.file("b.md"))
      assert.same("end", K.position())
    end)

    spec_it("IS8.2 Submit text: the draft goes before the " ..
        "block at the position, which stays on it", function()
      open("a.txt")
      K.browse_to(2)
      K.type_lines({
        "new",
        "newer"
      })
      K.keys("return")
      assert.same(
        "one\nnew\nnewer\ntwo\nthree\n",
        K.file("a.txt")
      )
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same(4, K.position())
    end)

    spec_it("IS8.2 Submit text: Enter replaces the target " ..
        "with the draft, a block per line", function()
      open("a.txt")
      edit(2)
      K.keys("lshift", "return")
      K.type("2b")
      K.keys("return")
      assert.same("one\ntwo\n2b\nthree\n", K.file("a.txt"))
      assert.same(4, K.blocks())
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("", K.draft())
      assert.same(4, K.position())
    end)

    spec_it("IS8.2 Submit text: a replacement is accepted " ..
        "browsed away, and Ctrl+Z takes it back", function()
      open("a.txt")
      edit(1)
      K.type("!")
      local browsed = pcall(K.browse_to, 3)
      K.keys("return")
      local accepted = {
        K.file("a.txt"),
        K.position()
      }
      K.keys("lctrl", "z")
      assert.is_true(browsed)
      assert.same({
        "one!\ntwo\nthree\n",
        2
      }, accepted)
      assert.same(TXT, K.file("a.txt"))
    end)

    spec_it("IS8.2 Submit text: a replacement cleared to " ..
        "empty leaves an empty line", function()
      open("a.txt")
      edit(2)
      K.keys("lctrl", "home")
      K.keys("lctrl", "k")
      K.keys("return")
      assert.same("one\n\nthree\n", K.file("a.txt"))
      assert.same("browsing", K.state())
      assert.same(3, K.position())
    end)

    spec_it("IS8.2 Submit text: a Markdown file takes the " ..
        "draft with no syntax check and no formatting",
        function()
      open("b.md")
      K.type("x=  = 1")
      K.keys("return")
      assert.same(MD .. "x=  = 1\n", K.file("b.md"))
      assert.same("browsing", K.state())
      assert.same("", K.draft())
    end)

    spec_it("IS8.2 Submit text: in a Markdown file, each " ..
        "line of the draft becomes a block", function()
      open("b.md")
      K.type_lines({
        "- a",
        "- b"
      })
      K.keys("return")
      assert.same(MD .. "- a\n- b\n", K.file("b.md"))
      assert.same(4, K.blocks())
      assert.same("end", K.position())
    end)

    spec_it("IS8.2 Submit text: a replacement keeps its " ..
        "spacing, with no formatting", function()
      open("a.txt")
      edit(2)
      K.type("  =  2")
      K.keys("return")
      assert.same("one\ntwo  =  2\nthree\n", K.file("a.txt"))
    end)

    spec_it("IS8.2 Submit text: Shift+Enter breaks a line in "
        .. "the draft and submits nothing", function()
      open("a.txt")
      K.type("ab")
      K.keys("left")
      K.keys("lshift", "return")
      assert.same("a\nb", K.draft())
      assert.same({
        2,
        1
      }, { K.cursor() })
      assert.same(TXT, K.file("a.txt"))
      assert.same("end", K.position())
    end)

    spec_it("IS8.2 Submit text: Alt+Enter breaks a line in " ..
        "the draft and submits nothing", function()
      open("b.md")
      K.type("ab")
      K.keys("left")
      K.keys("lalt", "return")
      assert.same("a\nb", K.draft())
      assert.same({
        2,
        1
      }, { K.cursor() })
      assert.same(MD, K.file("b.md"))
    end)

    spec_it("IS8.2 Submit text: a long line wraps in the " ..
        "field, the draft unchanged", function()
      open("a.txt")
      local long = string.rep("w", 150)
      K.type(long)
      assert.is_true(1 < #K.field_rows())
      assert.same(long, K.draft())
      assert.same({
        1,
        151
      }, { K.cursor() })
    end)
  end)

  describe("H-FR5.1", function()
    spec_it("H-FR5.1 Supported document types: a file with " ..
        "another extension opens as plain text", function()
      open("notes.log")
      assert.same("editor", K.app_state())
      assert.same("plain", K.file_type())
      assert.same(2, K.blocks())
      assert.same("end", K.position())
    end)
  end)
end)
