-- The console's history is the classic shell's (the
-- maintainer's ruling of November 14, 2026, which replaces
-- IS7.8's condition and its notice): the history holds only
-- lines that ran, and walking through it never writes to it;
-- the line being typed waits below the newest entry and comes
-- back on Down; an edit to a recalled line is kept for its
-- entry until Enter. Keys only, through
-- tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it
local spec_deviation = marks.spec_deviation
local F = require("tests.helpers.input_fixture")

local RULING = "rulings.md: The console's history is the "
    .. "classic shell's"
local REPEAT = "rulings.md: The history skips a repeated line"

--- Run each line in the console
--- @param ... string
local function run(...)
  for _, line in ipairs({ ... }) do
    K.type(line)
    K.keys("return")
  end
end

--- The console's field after each of `n` presses of `k`
--- @param k string
--- @param n integer
--- @return string[]
local function walk(k, n)
  local seen = { }
  for i = 1, n do
    K.keys(k)
    seen[i] = K.console_draft()
  end
  return seen
end

--- @return integer line, integer column
local function cursor()
  return K.cc.input.model:get_cursor_pos()
end

describe("the console's history #editor #spec #history", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("the line being typed", function()
    spec_deviation("IS7.8 Recall an instruction: Up from an "
        .. "edited draft shows the newest line run, and Down "
        .. "brings the draft back as it was", RULING, function()
      K.reset()
      run("a = 1", "b = 2")
      K.type("half")
      K.keys("up")
      assert.same("b = 2", K.console_draft())
      K.keys("down")
      assert.same("half", K.console_draft())
      K.type(" more")
      assert.same("half more", K.console_draft())
      -- the draft never ran: it is no entry
      K.keys("escape")
      assert.same({ "b = 2", "a = 1", "a = 1" }, walk("up", 3))
    end)

    spec_deviation("IS7.8 Recall an instruction: Down on the "
        .. "line being typed leaves it as it is", RULING,
      function()
        K.reset()
        run("a = 1")
        K.type("typed")
        K.keys("down")
        assert.same("typed", K.console_draft())
        K.keys("up")
        assert.same({ "typed", "typed" }, walk("down", 2))
      end)
  end)

  describe("an edit to a recalled line", function()
    spec_deviation("IS7.8 Recall an instruction: an edit to a "
        .. "recalled line is kept while the walk moves away and "
        .. "back", RULING, function()
      K.reset()
      run("a = 1", "b = 2")
      K.type("draft")
      K.keys("up")
      K.keys("backspace")
      K.type("9")
      assert.same({ "a = 1" }, walk("up", 1))
      assert.same({ "b = 9", "draft" }, walk("down", 2))
      assert.same({ "b = 9", "a = 1" }, walk("up", 2))
      -- the edit was the walk's, never the entry's
      K.keys("escape")
      assert.same({ "b = 2", "a = 1" }, walk("up", 2))
    end)

    spec_deviation("IS7.8 Recall an instruction: moving through "
        .. "the history writes nothing to it, and Enter runs the "
        .. "edited line as a new entry", RULING, function()
      K.reset()
      run("a = 1", "b = 2")
      K.type("draft")
      K.keys("up")
      K.keys("backspace")
      K.type("9")
      K.keys("down")
      assert.same("draft", K.console_draft())
      K.keys("up")
      assert.same("b = 9", K.console_draft())
      K.keys("return")
      assert.same("", K.console_draft())
      -- the edited line that ran, then the original, then the
      -- first: no draft and no edit reached the history
      assert.same({ "b = 9", "b = 2", "a = 1", "a = 1" },
        walk("up", 4))
    end)

    spec_deviation("IS7.8 Recall an instruction: Enter forgets "
        .. "every edit made on the walk, and each entry is again "
        .. "the line that ran", RULING, function()
      K.reset()
      run("a = 1", "b = 2", "c = 3")
      K.keys("up")
      K.keys("up")
      K.keys("backspace")
      K.type("5")
      K.keys("up")
      assert.same("a = 1", K.console_draft())
      K.keys("return")
      assert.same({ "a = 1", "c = 3", "b = 2", "a = 1" },
        walk("up", 4))
    end)

    spec_deviation("IS7.8 Recall an instruction: Escape clears "
        .. "the field, stores nothing, and forgets the walk's "
        .. "draft and edits", RULING, function()
      K.reset()
      run("a = 1")
      K.type("draft")
      K.keys("up")
      K.keys("backspace")
      K.type("7")
      K.keys("escape")
      assert.same("", K.console_draft())
      assert.same({ "a = 1", "a = 1" }, walk("up", 2))
      assert.same({ "" }, walk("down", 1))
      K.keys("escape")
      K.type("dropped")
      K.keys("escape")
      assert.same({ "a = 1" }, walk("up", 1))
    end)
  end)

  describe("what the history holds", function()
    spec_deviation("IS7.8 Recall an instruction: a line the "
        .. "syntax refuses is no entry, and the line corrected "
        .. "and run is", RULING, function()
      K.reset()
      run("z = 0")
      K.type("x = = 1")
      K.keys("return")
      assert.is_true(K.cc.input:has_error())
      -- the refused line stays; the next key dismisses the
      -- message and acts
      K.keys("home")
      K.keys("delete")
      K.type("y")
      K.keys("end")
      K.keys("left")
      K.keys("left")
      K.keys("left")
      K.keys("backspace")
      K.keys("backspace")
      assert.same("y = 1", K.console_draft())
      K.keys("return")
      assert.same({ "y = 1", "z = 0", "z = 0" }, walk("up", 3))
    end)

    spec_deviation("IS7.8 Recall an instruction: Up from a "
        .. "refused line walks from the line typed, and Down "
        .. "brings the refused line back", RULING, function()
      K.reset()
      run("a = 1")
      K.type("x = = 1")
      K.keys("return")
      assert.is_true(K.cc.input:has_error())
      assert.same({ "a = 1", "a = 1" }, walk("up", 2))
      assert.same({ "x = = 1", "x = = 1" }, walk("down", 2))
      K.keys("escape")
      assert.same({ "a = 1", "a = 1" }, walk("up", 2))
    end)

    spec_deviation("IS7.8 Recall an instruction: a line that "
        .. "fails while it runs ran, and is an entry", RULING,
      function()
        K.reset()
        run("a = 1")
        K.type('error("boom")')
        K.keys("return")
        -- its error is said in the output, the band left empty,
        -- and the field empties as after any line that ran
        assert.is_false(K.cc.input:has_error())
        assert.same("", K.console_draft())
        assert.same({ 'error("boom")', "a = 1" }, walk("up", 2))
      end)

    spec_deviation("IS7.8 Recall an instruction: a draft the "
        .. "syntax continues is no entry", RULING, function()
      K.reset()
      run("a = 1")
      K.type("if true then")
      K.keys("return")
      assert.same("if true then\n", K.console_draft())
      K.keys("escape")
      assert.same({ "a = 1", "a = 1" }, walk("up", 2))
    end)

    spec_deviation("IS7.8 Recall an instruction: a command "
        .. "finished over three Enters is one entry, the whole "
        .. "command", RULING, function()
      K.reset()
      run("a = 1")
      K.type("function f()")
      K.keys("return")
      K.type("return 1")
      K.keys("return")
      K.type("end")
      K.keys("return")
      assert.same("", K.console_draft())
      local whole = "function f()\nreturn 1\nend"
      -- Up recalls it with the cursor on its last row, rises
      -- through its rows, then recalls the line before
      assert.same({ whole, whole, whole, "a = 1" }, walk("up", 4))
    end)

    spec_deviation("IS7.8 Recall an instruction: a recalled line "
        .. "the syntax continues keeps the walk, and Down brings "
        .. "the line typed back", RULING, function()
      K.reset()
      run("a = 1")
      K.type("precious = 42")
      K.keys("up")
      assert.same("a = 1", K.console_draft())
      K.type("+")
      K.keys("return")
      assert.same("a = 1+\n", K.console_draft())
      K.keys("down")
      assert.same("precious = 42", K.console_draft())
      K.keys("up")
      assert.same("a = 1+\n", K.console_draft())
    end)

    spec_deviation("IS7.8 Recall an instruction: a line run "
        .. "again is no second entry", REPEAT, function()
      K.reset()
      run("z = 0", "a = 1", "a = 1", "a = 1")
      assert.same({ "a = 1", "z = 0" }, walk("up", 2))
    end)

    spec_deviation("IS7.8 Recall an instruction: the newest line "
        .. "recalled and run unchanged adds no entry, and edited "
        .. "and run adds one", REPEAT, function()
      K.reset()
      run("z = 0", "a = 1")
      K.keys("up")
      K.keys("return")
      assert.same({ "a = 1", "z = 0" }, walk("up", 2))
      K.keys("escape")
      K.keys("up")
      K.keys("backspace")
      K.type("2")
      K.keys("return")
      assert.same({ "a = 2", "a = 1", "z = 0" }, walk("up", 3))
    end)

    spec_deviation("IS7.8 Recall an instruction: only the newest "
        .. "entry is compared: A, B, A is three entries", REPEAT,
      function()
        K.reset()
        run("a = 1", "b = 2", "a = 1")
        assert.same({ "a = 1", "b = 2", "a = 1", "a = 1" },
          walk("up", 4))
      end)

    spec_deviation("IS7.8 Recall an instruction: a multi-line "
        .. "command run again is no second entry, and one that "
        .. "differs in a line is", REPEAT, function()
      K.reset()
      local function command(body)
        K.type("function f()")
        K.keys("return")
        K.type(body)
        K.keys("return")
        K.type("end")
        K.keys("return")
      end
      run("z = 0")
      command("return 1")
      command("return 1")
      local whole = "function f()\nreturn 1\nend"
      -- Up rises through the command's rows before it recalls
      assert.same({ whole, whole, whole, "z = 0" }, walk("up", 4))
      K.keys("escape")
      command("return 2")
      local other = "function f()\nreturn 2\nend"
      assert.same({ other, other, other, whole }, walk("up", 4))
    end)

    spec_it("IS7.8 Recall an instruction: an empty or blank "
        .. "line is no entry", function()
      K.reset()
      run("a = 1")
      K.keys("return")
      K.type("   ")
      K.keys("return")
      K.keys("escape")
      assert.same({ "a = 1", "a = 1" }, walk("up", 2))
    end)

    spec_it("IS7.8 Recall an instruction: a recalled line "
        .. "shows with the cursor at its end", function()
      K.reset()
      run("a = 1", "long = 22")
      K.keys("up")
      assert.same({ 1, 10 }, { cursor() })
      K.keys("up")
      assert.same({ 1, 6 }, { cursor() })
      K.keys("down")
      assert.same({ 1, 10 }, { cursor() })
    end)

    spec_it("IS7.8 Recall an instruction: with no earlier line, "
        .. "Up leaves the draft and its cursor as they are",
      function()
        K.reset()
        K.type("abc")
        K.keys("left")
        K.keys("up")
        assert.same("abc", K.console_draft())
        assert.same({ 1, 3 }, { cursor() })
      end)
  end)
end)

-- Not the console: the file editor's draft and a program's
-- field walk no history.
describe("no history outside the console #editor #history",
  function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  it("the file editor's Up on its draft's first row recalls "
      .. "nothing", function()
    K.reset({ ["main.lua"] = "a = 1\n" })
    run("ran = 1")
    K.open()
    K.type("b = 2")
    K.keys("up")
    assert.same("b = 2", K.draft())
    K.keys("down")
    assert.same("b = 2", K.draft())
  end)

  it("a program's field recalls nothing, and the program's "
      .. "hook sees Up first", function()
    K.reset({ ["main.lua"] = [[
compy.input.hooks.keypressed = function(k)
  if k == 'up' then ups = (ups or 0) + 1 end
end
compy.input.show { }
]] })
    K.open()
    K.keys("lctrl", "t")
    assert.is_true(F.is_widget_visible())
    K.type("sent")
    K.keys("return")
    K.keys("up")
    assert.same(1, K.cc:get_project_env().ups)
    assert.same("", F.compy_input().get_text())
  end)
end)
