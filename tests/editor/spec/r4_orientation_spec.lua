-- R4 Submission and orientation across input contexts:
-- NFR4.1, FR4.2, NFR4.3-NFR4.5, FR4.6, FR4.7 and FR4.9
-- (editor principles, ratified). FR4.8 has no test: it
-- permits a continuation cue and requires none. NFR4.1's
-- "identify ... the destination of any edit" is a person's
-- judgement of the screen: a device check, with FR4.6's
-- status line tested here.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

--- The status line's words, without its numbers and flags:
--- what tells one state from another.
local function status_words()
  local words = { }
  for w in K.status_text():gmatch("%S+") do
    local flag = w == "true" or w == "false"
    local is_word = not flag and not w:match("^%d+$")
    if is_word then
      words[#words + 1] = w
    end
  end
  return table.concat(words, " ")
end

--- The status line's words in the browsing, replacing and
--- inserting states: Edit (F2) on block 1, then a fresh
--- console and typing at the end.
local function words_per_state()
  K.browse_to(1)
  local browsing = status_words()
  K.keys("f2")
  local replacing, state = status_words(), K.state()
  K.restart()
  K.open()
  K.browse_to_end()
  K.type("a = 1")
  return browsing, status_words(), replacing, state
end

describe("R4 orientation #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  before_each(function()
    K.reset({
      ["main.lua"] = "x = 1\ny = 2\n",
      ["a.txt"] = "one\n"
    })
  end)

  spec_gap("NFR4.1 Identify the pending action: the status " ..
      "line tells browsing, inserting and replacing apart",
      function(gap)
    K.open()
    local b, i, r, state = words_per_state()
    gap(function()
      assert.same("replacing", state)
      assert.are_not.same(b, i)
      assert.are_not.same(i, r)
      assert.are_not.same(b, r)
    end)
  end)

  spec_gap("FR4.2 Deliberate submission: browsing away from a "
      .. "changed draft writes nothing", function(gap)
    K.open()
    K.browse_to_end()
    K.type("z = 3")
    K.keys("lctrl", "up")
    gap(function()
      assert.same("x = 1\ny = 2\n", K.file())
    end)
  end)

  spec_it("NFR4.3 Understandable submission outcome: a refused "
      .. "submission says so and keeps the draft", function()
    K.open()
    K.browse_to_end()
    K.type("x = ")
    K.keys("return")
    assert.is_not_nil(K.message())
    assert.same("x = ", K.draft())
    assert.same("x = 1\ny = 2\n", K.file())
  end)

  spec_it("NFR4.4 Post-submission orientation: after an append "
      .. "the new block is in view at the end", function()
    K.open()
    K.browse_to_end()
    K.type("z = 3")
    K.keys("return")
    assert.same("end", K.position())
    assert.is_true(K.in_view(3))
    assert.same("browsing", K.state())
  end)

  spec_gap("NFR4.5 Consistent text interaction: Escape drops "
      .. "a draft in the console and in the editor alike",
      function(gap)
    K.type("x = 1")
    K.keys("escape")
    local console = K.console_draft()
    K.open()
    K.browse_to_end()
    K.type("x = 1")
    K.keys("escape")
    gap(function()
      assert.same("", console)
      assert.same("", K.draft())
    end)
  end)

  spec_it("FR4.6 Visible project and context on the status " ..
      "line: the open file's name", function()
    K.open()
    assert.truthy(K.status_text():find("main.lua", 1, true))
  end)

  spec_gap("FR4.6 Visible project and context on the status "
      .. "line: the open project's name", function(gap)
    K.open()
    gap(function()
      assert.truthy(K.status_text():find(K.PROJECT, 1, true))
    end)
  end)

  spec_gap("FR4.6 Visible project and context on the status "
      .. "line: the editor's state", function(gap)
    K.open()
    local b, i, r, state = words_per_state()
    gap(function()
      assert.same("replacing", state)
      assert.are_not.same(i, r)
      assert.are_not.same(b, i)
    end)
  end)

  spec_it("FR4.7 Wrap long lines: a draft line wider than the "
      .. "field wraps with every character shown", function()
    K.open("a.txt")
    K.browse_to_end()
    local line = string.rep("abcdefghij", 8)
    K.type(line)
    local rows = K.field_rows()
    assert.same(2, #rows)
    assert.same(line, rows[1] .. rows[2])
    assert.same(line, K.draft())
  end)

  spec_gap("FR4.7 Wrap long lines: the cursor's row is shown "
      .. "when wrapped rows outgrow the field", function(gap)
    K.open("a.txt")
    K.browse_to_end()
    local lines = { }
    for n = 1, 10 do
      lines[n] = string.format("%02d", n) .. string.rep("x", 90)
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

  spec_it("FR4.9 Keys on request: holding the help key changes "
      .. "no state", function()
    K.open()
    K.browse_to(1)
    K.hold("f1")
    K.release("f1")
    assert.same(1, K.position())
    assert.same("browsing", K.state())
    assert.same("x = 1\ny = 2\n", K.file())
  end)

  spec_gap("FR4.9 Keys on request: while the help key is held "
      .. "the editor shows the keys", function(gap)
    K.open()
    K.hold("f1")
    local card = K.key_card()
    K.release("f1")
    gap(function()
      assert.is_not_nil(card)
      -- the browsing state's keys first: Edit among them
      assert.truthy(
        table.concat(card, "\n"):find("F2", 1, true)
      )
      assert.is_nil(K.key_card())
    end)
  end)
end)
