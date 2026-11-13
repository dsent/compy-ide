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

  spec_gap("IS8.1 Open a text or Markdown file: at the end " ..
      "position, a block per line", function(gap)
    K.open("a.txt")
    gap(function()
      assert.same("end", K.position())
      assert.same(2, K.blocks())
    end)
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

  spec_gap("IS8.2 Submit text: a text file holds a block per "
      .. "line, before and after a submission", function(gap)
    K.open("a.txt")
    local opened = K.blocks()
    K.browse_to_end()
    K.type_lines({
      "three",
      "four"
    })
    K.keys("return")
    gap(function()
      assert.same(2, opened)
      assert.same(4, K.blocks())
    end)
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

  spec_gap("IS8.2 Submit text: an append adds the draft's " ..
      "lines and nothing else", function(gap)
    K.open("a.txt")
    K.browse_to_end()
    K.type("three")
    K.keys("return")
    gap(function()
      assert.same("one\ntwo\nthree\n", K.file("a.txt"))
    end)
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
