-- R1 Scope and targets of an edit, R2 Recovery and leaving
-- an edit: FR1.1-FR1.9, FR2.1-FR2.8 (editor principles,
-- ratified). Keys only, through tests/helpers/editor_keys.lua.
-- Edit is F2; copy a block into the draft is Ctrl+Ins (IS6.1).

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local FILE = "x = 1\ny = 2\nz = 3\n"

local function open_file(text)
  K.reset({ ["main.lua"] = text or FILE })
  K.open()
end

local function edit(b)
  K.browse_to(b)
  K.keys("f2")
end

--- `n` one-line blocks, v1 = 1 to vn = n.
local function many(n)
  local t = { }
  for i = 1, n do
    t[i] = "v" .. i .. " = " .. i
  end
  return table.concat(t, "\n") .. "\n"
end

describe("FR1 and FR2 #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("FR1", function()
    -- FR1.1 names no key: browsing (IS2.1) and the view's
    -- own scroll (Alt+Home, `D-ALT-LOOK`, kept for now) are
    -- both ways; either passes
    spec_it("FR1.1 View persisted text during an edit: the " ..
        "first block can be brought into view mid-edit",
        function()
      open_file(many(40))
      K.browse_to_end()
      K.type("a = 1")
      K.keys("lalt", "home")
      if not K.in_view(1) then
        pcall(K.browse_to, 1)
      end
      assert.is_true(K.in_view(1))
      assert.same("a = 1", K.draft())
      assert.same("inserting", K.state())
    end)

    spec_gap("FR1.2 Resolve each edit: no second edit begins "
        .. "while one is open", function(gap)
      open_file()
      K.browse_to_end()
      K.type("a = 1")
      local browsed = pcall(K.browse_to, 1)
      K.keys("f2")
      gap(function()
        assert.is_true(browsed)
        assert.same("inserting", K.state())
        assert.same("a = 1", K.draft())
        assert.is_nil(K.target())
      end)
    end)

    spec_gap(
        "FR1.3 Keep the replacement target: browsing leaves "
        .. "the target, changed draft or not", function(gap)
      open_file()
      edit(1)
      local browsed = pcall(K.browse_to, 3)
      local unchanged = K.target()
      K.type("0")
      pcall(K.browse_to, 2)
      gap(function()
        assert.is_true(browsed)
        assert.same(1, unchanged)
        assert.same(1, K.target())
        assert.same(FILE, K.file())
      end)
    end)

    spec_gap("FR1.4 Explicit replacement entry: typing on a "
        .. "block never makes it the target", function(gap)
      open_file()
      K.browse_to(2)
      K.type("a")
      gap(function()
        assert.is_nil(K.target())
      end)
    end)

    spec_it("FR1.4 Explicit replacement entry: browsing never "
        .. "makes a block the target", function()
      open_file()
      K.browse_to(1)
      K.keys("lctrl", "down")
      K.keys("lctrl", "down")
      assert.is_nil(K.target())
      assert.same("browsing", K.state())
    end)

    spec_gap("FR1.5 Cursor at the end of loaded text: after "
        .. "Edit", function(gap)
      open_file("if a then\n  b = 1\nend\n")
      edit(1)
      gap(function()
        assert.same("replacing", K.state())
        assert.same({
          3,
          2
        }, { K.cursor() })
      end)
    end)

    spec_gap("FR1.5 Cursor at the end of loaded text: after a "
        .. "cut", function(gap)
      open_file()
      K.browse_to(2)
      K.keys("lctrl", "delete")
      gap(function()
        assert.same("y = 2", K.draft())
        assert.same({
          1,
          6
        }, { K.cursor() })
      end)
    end)

    spec_it(
        "FR1.6 Multi-statement drafts split into blocks: two "
        .. "lines become two blocks", function()
      open_file()
      K.browse_to_end()
      K.type_lines({
        "a = 1",
        "b = 2"
      })
      K.keys("return")
      assert.same(5, K.blocks())
      assert.same(FILE .. "a = 1\nb = 2\n", K.file())
    end)

    spec_gap("FR1.7 Explicit block removal: Backspace, Delete "
        .. "and Ctrl+K never touch the file", function(gap)
      open_file()
      K.browse_to(2)
      K.keys("backspace")
      K.keys("delete")
      K.keys("lctrl", "k")
      gap(function()
        assert.same(FILE, K.file())
        assert.same(3, K.blocks())
      end)
    end)

    spec_gap(
        "FR1.8 Reuse a block in the draft: Ctrl+Ins copies " ..
        "the browsed block in at the cursor", function(gap)
      open_file()
      K.browse_to_end()
      K.type("a = 1")
      local browsed = pcall(K.browse_to, 1)
      K.keys("lctrl", "insert")
      gap(function()
        assert.is_true(browsed)
        assert.same("a = 1\nx = 1", K.draft())
        assert.same(FILE, K.file())
      end)
    end)

    spec_it("FR1.9 Break a line on request: Shift+Enter, no "
        .. "submission", function()
      open_file()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("lshift", "return")
      assert.same("a = 1\n", K.draft())
      assert.same(FILE, K.file())
    end)

    spec_gap("FR1.9 Break a line on request: right after a " ..
        "refused submission too", function(gap)
      open_file()
      K.browse_to_end()
      K.type("a = = 1")
      K.keys("return")
      K.keys("lctrl", "end")
      K.keys("lshift", "return")
      gap(function()
        assert.same("a = = 1\n", K.draft())
      end)
    end)
  end)

  describe("FR2", function()
    before_each(function()
      open_file()
    end)

    spec_gap("FR2.1 Quickly abort an edit: one Escape, no " ..
        "question, the file untouched", function(gap)
      edit(2)
      K.type("0")
      K.keys("escape")
      gap(function()
        assert.same("browsing", K.state())
        assert.same("", K.draft())
        assert.same(FILE, K.file())
      end)
    end)

    spec_it("FR2.2 Leave an edit by submitting: a valid draft "
        .. "is accepted, back to browsing", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      assert.same("browsing", K.state())
    end)

    spec_it(
        "FR2.2 Leave an edit by submitting: a draft of only "
        .. "empty lines leaves the edit too", function()
      K.browse_to_end()
      K.keys("lshift", "return")
      assert.same("\n", K.draft())
      K.keys("return")
      assert.same("browsing", K.state())
      assert.same("", K.draft())
    end)

    spec_gap(
        "FR2.3 Leave an edit by aborting: Escape leaves an " ..
        "invalid draft too", function(gap)
      K.browse_to_end()
      K.type("a = = 1")
      K.keys("escape")
      gap(function()
        assert.same("browsing", K.state())
        assert.same(FILE, K.file())
      end)
    end)

    spec_it("FR2.4 Valid submissions only: an invalid draft is "
        .. "refused, the edit stays open", function()
      K.browse_to_end()
      K.type("a = = 1")
      K.keys("return")
      assert.same("inserting", K.state())
      assert.same(FILE, K.file())
    end)

    spec_gap(
        "FR2.5 Locate syntax failures or continue on Enter: "
        .. "the cursor stops before the failure", function(gap)
      K.browse_to_end()
      K.type("a = = 1")
      K.keys("return")
      gap(function()
        assert.same({
          1,
          5
        }, { K.cursor() })
      end)
    end)

    spec_gap(
        "FR2.5 Locate syntax failures or continue on Enter: "
        .. "an incomplete draft gets a new line", function(gap)
      K.browse_to_end()
      K.type("if a then")
      K.keys("return")
      gap(function()
        assert.same("if a then\n", K.draft())
        assert.same({
          2,
          1
        }, { K.cursor() })
      end)
    end)

    spec_gap(
        "FR2.6 Preserve state on refused actions: a refused "
        .. "Edit changes nothing", function(gap)
      K.browse_to_end()
      K.type("abc")
      K.keys("left")
      local browsed = pcall(K.browse_to, 1)
      K.keys("f2")
      gap(function()
        assert.is_true(browsed)
        assert.same("abc", K.draft())
        assert.same({
          1,
          3
        }, { K.cursor() })
        assert.same(1, K.position())
        assert.is_nil(K.target())
      end)
    end)

    spec_gap("FR2.7 Step back from a file with Escape: no " ..
        "question, the project still open", function(gap)
      K.keys("escape")
      gap(function()
        assert.same("ready", K.app_state())
        assert.same(K.PROJECT, K.cc.model.projects.current.name)
      end)
    end)

    spec_it(
        "FR2.8 Take back an accepted change: one press takes "
        .. "back a submission, one redoes it", function()
      K.browse_to_end()
      K.type("a = 1; b = 2")
      K.keys("return")
      K.keys("lctrl", "z")
      assert.same(FILE, K.file())
      K.keys("lctrl", "y")
      assert.same(FILE .. "a = 1\nb = 2\n", K.file())
    end)

    spec_it("FR2.8 Take back an accepted change: a cut, in one "
        .. "press", function()
      K.browse_to(2)
      K.keys("lctrl", "delete")
      K.keys("lctrl", "z")
      assert.same(FILE, K.file())
    end)

    spec_gap(
        "FR2.8 Take back an accepted change: a move, in one "
        .. "press", function(gap)
      K.browse_to(2)
      K.keys("lalt", "up")
      local moved = K.file()
      K.keys("lctrl", "z")
      gap(function()
        assert.same("y = 2\nx = 1\nz = 3\n", moved)
        assert.same(FILE, K.file())
      end)
    end)

    spec_it("FR2.8 Take back an accepted change: a new change "
        .. "ends what could be redone", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.keys("lctrl", "z")
      K.browse_to_end()
      K.type("b = 2")
      K.keys("return")
      K.keys("lctrl", "y")
      assert.same(FILE .. "b = 2\n", K.file())
    end)

    spec_gap("FR2.8 Take back an accepted change: an abort is "
        .. "taken back as an abort", function(gap)
      K.browse_to_end()
      K.type("a = 1")
      K.keys("escape")
      K.keys("lctrl", "z")
      gap(function()
        assert.same("a = 1", K.draft())
        assert.same(FILE, K.file())
      end)
    end)

    spec_gap(
        "FR2.8 Take back an accepted change: one action per "
        .. "key press, not per key repeat", function(gap)
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.type("b = 2")
      K.keys("return")
      K.hold("lctrl")
      K.hold("z")
      K.repeat_key("z")
      K.release("z")
      K.release("lctrl")
      gap(function()
        assert.same(FILE .. "a = 1\n", K.file())
      end)
    end)
  end)
end)
