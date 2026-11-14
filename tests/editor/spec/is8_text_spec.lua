-- IS8 Plain text and Markdown files (editor principles,
-- ratified). Keys only, through tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local function count(set)
  local n = 0
  for _ in pairs(set) do
    n = n + 1
  end
  return n
end

describe("IS8 text files #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  before_each(function()
    K.reset({
      ["a.txt"] = "one\ntwo\n",
      ["b.md"] = "# Title\nsome *em* text\n"
    })
  end)

  spec_it("IS8.1 Open a text or Markdown file: at the end " ..
      "position, a block per line", function()
    K.open("a.txt")
    assert.same("end", K.position())
    assert.same(2, K.blocks())
  end)

  spec_it("IS8.1 Open a text or Markdown file: a Markdown " ..
      "file opens at the end position, a block per line",
      function()
    K.open("b.md")
    assert.same("browsing", K.state())
    assert.same("end", K.position())
    assert.same(2, K.blocks())
  end)

  spec_it("IS8.1 Open a text or Markdown file: an empty text "
      .. "file opens at its end, with no block", function()
    K.open("new.txt")
    assert.same(0, K.blocks())
    assert.same("end", K.position())
    K.type("first")
    K.keys("return")
    assert.same("first\n", K.file("new.txt"))
  end)

  spec_it("IS8.1 Open a text or Markdown file: Edit loads a " ..
      "line and Enter replaces it", function()
    K.open("a.txt")
    K.browse_to(1)
    K.keys("f2")
    assert.same("replacing", K.state())
    assert.same("one", K.draft())
    K.type("!")
    K.keys("return")
    assert.same("one!\ntwo\n", K.file("a.txt"))
    assert.same("browsing", K.state())
    assert.same(2, K.position())
  end)

  spec_it("IS8.1 Open a text or Markdown file: Escape aborts " ..
      "a replacement and the line stays", function()
    K.open("a.txt")
    K.browse_to(2)
    K.keys("f2")
    K.type("!")
    K.keys("escape")
    assert.same("browsing", K.state())
    assert.same("", K.draft())
    assert.same(2, K.position())
    assert.same("one\ntwo\n", K.file("a.txt"))
  end)

  spec_it("IS8.1 Open a text or Markdown file: cutting a line "
      .. "takes it from the file into the field", function()
    K.open("a.txt")
    K.browse_to(1)
    K.keys("lctrl", "delete")
    assert.same("two\n", K.file("a.txt"))
    assert.same("one", K.draft())
    assert.same(1, K.blocks())
  end)

  spec_it("IS8.2 Submit text: a draft is inserted before the "
      .. "viewed line", function()
    K.open("a.txt")
    K.browse_to(2)
    K.type("middle")
    K.keys("return")
    assert.same("one\nmiddle\ntwo\n", K.file("a.txt"))
    assert.same(3, K.blocks())
    assert.same(3, K.position())
  end)

  spec_it("IS8.2 Submit text: an empty draft inserts an " ..
      "empty line", function()
    K.open("a.txt")
    K.browse_to(2)
    K.keys("return")
    assert.same("one\n\ntwo\n", K.file("a.txt"))
    K.browse_to_end()
    K.keys("return")
    assert.same("one\n\ntwo\n\n", K.file("a.txt"))
    assert.same(4, K.blocks())
  end)

  spec_it("IS8.2 Submit text: a replacement of several lines "
      .. "puts a block for each in the line's place", function()
    K.open("a.txt")
    K.browse_to(1)
    K.keys("f2")
    K.keys("lshift", "return")
    K.type("more")
    K.keys("return")
    assert.same("one\nmore\ntwo\n", K.file("a.txt"))
    assert.same(3, K.blocks())
  end)

  spec_it("IS8.2 Submit text: a Markdown draft is accepted as "
      .. "written, each line a block", function()
    K.open("b.md")
    K.type_lines({
      "## Sub   title",
      "x=  = 1"
    })
    K.keys("return")
    assert.same("", K.draft())
    assert.same(
      "# Title\nsome *em* text\n## Sub   title\nx=  = 1\n",
      K.file("b.md")
    )
    assert.same(4, K.blocks())
  end)

  spec_it("IS8.2 Submit text: Enter accepts with no syntax " ..
      "check and no formatting", function()
    K.open("a.txt")
    K.browse_to_end()
    K.type("x=  = 1")
    K.keys("return")
    assert.same("", K.draft())
    assert.truthy(K.file("a.txt"):find("\nx=  = 1\n$"))
  end)

  spec_it("IS8.2 Submit text: each line of the draft becomes "
      .. "a block", function()
    K.open("a.txt")
    K.browse_to_end()
    K.type_lines({
      "three",
      "four"
    })
    K.keys("return")
    -- each a line of its own; what else an append adds is
    -- the next test's
    assert.truthy(K.file("a.txt"):find("\nthree\nfour\n$"))
  end)

  spec_it("IS8.2 Submit text: a text file holds a block per "
      .. "line, before and after a submission", function()
    K.open("a.txt")
    local opened = K.blocks()
    K.browse_to_end()
    K.type_lines({
      "three",
      "four"
    })
    K.keys("return")
    assert.same(2, opened)
    assert.same(4, K.blocks())
  end)

  spec_it("IS8.3 Highlight Markdown: the editor field colours "
      .. "a Markdown draft, not a plain one", function()
    K.open("b.md")
    K.browse_to_end()
    K.type("# T *e*")
    local md = K.field_highlight()
    K.restart()
    K.open("a.txt")
    K.browse_to_end()
    K.type("# T *e*")
    local txt = K.field_highlight()
    assert.is_true(1 < md)
    assert.is_true(txt <= 1)
  end)

  spec_it("IS8.2 Submit text: an append adds the draft's " ..
      "lines and nothing else", function()
    K.open("a.txt")
    K.browse_to_end()
    K.type("three")
    K.keys("return")
    assert.same("one\ntwo\nthree\n", K.file("a.txt"))
  end)

  spec_it("IS8.2 Submit text: a line has no length limit",
      function()
    K.open("a.txt")
    K.browse_to_end()
    local line = string.rep("abcdefghij", 10)
    K.type(line)
    K.keys("return")
    assert.same("", K.draft())
    assert.truthy(K.file("a.txt"):find(line, 1, true))
  end)

  spec_it("IS8.3 Highlight Markdown: the document view colours "
      .. "Markdown, not plain text", function()
    K.open("b.md")
    local md = count(K.text_colours())
    K.restart()
    K.open("a.txt")
    assert.is_true(1 < md)
    assert.same(1, count(K.text_colours()))
  end)
end)
