-- The fifth review round's findings, each as the keys that
-- showed it: the cursor of a retained draft beside blank
-- lines, the key card over a program's input, a `#!` first
-- line shown red, the cursor a swap's undo puts back, a
-- second read of a changed file, the line endings formatting
-- keeps, a notice dismissed by its own key, and an abort
-- after a change from outside. Keys only, through
-- tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it
local spec_deviation = marks.spec_deviation
local F = require("tests.helpers.input_fixture")

--- a program that shows its input field and idles behind the
--- console, noting the help key when it reaches it
local SHOWS_FIELD = [[
compy.input.hooks.keypressed = function(k)
  if k == 'f1' then saw_f1 = true end
end
compy.input.show { text = 'program' }
]]

--- a program that runs on, noting the help key. Its handlers
--- go from the project's love table when the key comes, so
--- that no later run in the file finds them there.
local RUNS_ON = [[
function love.update() end
function love.keypressed(k)
  if k == 'f1' then saw_f1 = true end
  love.update, love.keypressed = nil, nil
end
]]

--- a program that an error pauses; its handler goes as it
--- fails
local PAUSES = [[
function love.update()
  love.update = nil
  error('x')
end
]]

--- a program that opens a file from its key hook on Enter or
--- Escape, and leaves the key unconsumed
local OPENS_ON_KEY = [[
compy.input.hooks.keypressed = function(k)
  if k == 'return' or k == 'escape' then edit('notes.txt') end
end
]]

--- the program's own global, as its code left it
local function program_global(name)
  return K.cc:get_project_env()[name]
end

--- a press on the console's field and a release elsewhere,
--- which places the cursor when it reaches the field
local function drag()
  F.session.mousepressed(10, 540, 1, false, 1)
  F.session.mousereleased(40, 508, 1, false, 1)
end

describe("round five #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("the cursor of a retained draft beside blank lines",
    function()
      spec_deviation("IS6.4 Submit and retain the field: of the "
          .. "leading blank lines the formatter keeps one, the "
          .. "cursor before the text after it", "rulings.md: The formatter decides a draft's empty lines", function()
        K.reset({ ["main.lua"] = "" })
        K.open()
        K.keys("lshift", "return")
        K.keys("lshift", "return")
        K.type("x=1")
        K.keys("lctrl", "home")
        K.keys("right")
        assert.same({ 2, 1 }, { K.cursor() })
        K.keys("lshift", "insert")
        assert.same("\nx = 1", K.draft())
        assert.same({ 2, 1 }, { K.cursor() })
      end)

      spec_deviation("IS6.4 Submit and retain the field: of the "
          .. "trailing blank lines the formatter keeps one, the "
          .. "cursor on it", "rulings.md: The formatter decides a draft's empty lines", function()
        K.reset({ ["main.lua"] = "" })
        K.open()
        K.type("x=1")
        K.keys("lshift", "return")
        K.keys("lshift", "return")
        K.keys("left")
        assert.same({ 2, 1 }, { K.cursor() })
        K.keys("lshift", "insert")
        assert.same("x = 1\n", K.draft())
        assert.same({ 2, 1 }, { K.cursor() })
      end)

      spec_it("IS6.4 Submit and retain the field: the cursor on a "
          .. "blank line stays when the formatter respaces the "
          .. "line above it", function()
        K.reset({ ["main.lua"] = "" })
        K.open()
        K.type("x=1  ")
        K.keys("lshift", "return")
        K.keys("lshift", "return")
        K.type("y=2")
        K.keys("up")
        assert.same({ 2, 1 }, { K.cursor() })
        K.keys("lshift", "insert")
        assert.same("x = 1\n\ny = 2", K.draft())
        assert.same({ 2, 1 }, { K.cursor() })
      end)

      spec_it("IS6.4 Submit and retain the field: the cursor on a "
          .. "blank line the formatter removes goes before what "
          .. "follows", function()
        K.reset({ ["main.lua"] = "" })
        K.open()
        K.type_lines({ "function f()", "a=1", "", "", "b=2" })
        K.keys("lshift", "return")
        K.type("end")
        for _ = 1, 3 do K.keys("up") end
        assert.same({ 3, 1 }, { K.cursor() })
        K.keys("lshift", "insert")
        assert.same("function f()\n  a = 1\n\n  b = 2\nend",
          K.draft())
        assert.same({ 4, 3 }, { K.cursor() })
      end)
    end)

  describe("the key card and a program's input", function()
    spec_it("IS3.16 Show the key card: no console card shows "
        .. "over a program's input field, and the help key and "
        .. "the keys held with it are the program's", function()
      K.reset({ ["main.lua"] = SHOWS_FIELD })
      K.open()
      K.keys("lctrl", "t")
      assert.same("ready", K.app_state())
      assert.is_true(F.is_widget_visible())
      K.hold("f1")
      assert.is_nil(K.key_card())
      K.type("x")
      K.release("f1")
      assert.is_true(program_global("saw_f1"))
      assert.same("programx", F.compy_input().get_text())
      -- the reserved keys act: the card does not show
      K.hold("f1")
      K.keys("lctrl", "q")
      K.release("f1")
      assert.is_false(K.cc.run_live)
    end)

    spec_it("IS3.16 Show the key card: no console card shows "
        .. "over a program that runs, and the help key is the "
        .. "program's", function()
      K.reset({ ["main.lua"] = RUNS_ON })
      K.open()
      K.keys("lctrl", "t")
      assert.same("running", K.app_state())
      K.hold("f1")
      assert.is_nil(K.key_card())
      K.release("f1")
      assert.is_true(program_global("saw_f1"))
      K.keys("lctrl", "q")
      assert.same("ready", K.app_state())
    end)

    spec_it("IS3.16 Show the key card: over a program idling "
        .. "with no input field of its own, the console's card "
        .. "shows and its field takes nothing", function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.open()
      K.keys("lctrl", "t")
      assert.same("ready", K.app_state())
      assert.is_true(K.cc.run_live)
      K.type("a")
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      K.type("y")
      K.keys("backspace")
      K.release("f1")
      assert.same("a", K.console_draft())
    end)

    spec_it("IS3.16 Show the key card: while a program is "
        .. "paused, the console's card shows and its field "
        .. "takes nothing", function()
      K.reset({ ["main.lua"] = PAUSES })
      K.open()
      K.keys("lctrl", "t")
      K.frame()
      assert.same("snapshot", K.app_state())
      -- the move from the snapshot to 'inspect' is the
      -- screenshot's callback, which needs a real graphics
      -- context
      K.cc:suspend()
      assert.same("inspect", K.app_state())
      K.type("a")
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      K.type("y")
      K.keys("backspace")
      K.release("f1")
      assert.same("a", K.console_draft())
    end)

    spec_it("IS3.16 Show the key card: the pointer changes "
        .. "nothing in the console's field while its card "
        .. "shows", function()
      K.reset()
      K.type_lines({ "aa", "bb", "cc" })
      local before = { K.cc.input:get_cursor_pos() }
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      drag()
      K.release("f1")
      assert.same(before, { K.cc.input:get_cursor_pos() })
      -- the same click, the card away, places the cursor
      drag()
      assert.are_not.same(before, { K.cc.input:get_cursor_pos() })
    end)
  end)

  describe("a #! line in the field", function()
    --- where the field turns the draft red, nil where it does
    --- not
    local function red()
      local _, at = K.field_highlight()
      return at
    end

    spec_it("IS3.3 Check Lua submission: a draft refused for a "
        .. "line's length is not red", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type(string.rep("n", 70) .. " = 1")
      assert.is_nil(red())
      K.keys("return")
      assert.same("", K.file())
      assert.truthy((K.message() or ""):find("the limit is", 1,
        true))
    end)

    for _, ext in ipairs({ "txt", "md" }) do
      spec_it("IS3.4 Locate a syntax failure: a #! line in a ."
          .. ext .. " file is not red, and Enter takes it",
        function()
          local name = "notes." .. ext
          K.reset({ ["main.lua"] = "", [name] = "x\n" })
          K.open(name)
          K.type("#!/x")
          assert.is_nil(red())
          K.keys("return")
          assert.same("x\n#!/x\n", K.file(name))
        end)
    end
  end)

  describe("the cursor a draft's undo puts back", function()
    spec_it("IS6.6 Undo and redo: undoing a swap of the "
        .. "draft's lines puts the cursor where the swap found "
        .. "it, and redoing it where the swap left it",
      function()
        K.reset({ ["main.lua"] = "" })
        K.open()
        K.type_lines({ "first", "second" })
        assert.same({ 2, 7 }, { K.cursor() })
        K.keys("lshift", "lalt", "up")
        assert.same("second\nfirst", K.draft())
        -- the cursor goes with its line
        assert.same({ 1, 7 }, { K.cursor() })
        K.keys("lctrl", "z")
        assert.same("first\nsecond", K.draft())
        assert.same({ 2, 7 }, { K.cursor() })
        K.keys("lctrl", "y")
        assert.same("second\nfirst", K.draft())
        assert.same({ 1, 7 }, { K.cursor() })
      end)

    spec_it("IS6.6 Undo and redo: a swap at the draft's first "
        .. "or last line changes nothing and is no step",
      function()
        K.reset({ ["main.lua"] = "" })
        K.open()
        K.type_lines({ "aa", "bb" })
        K.keys("lshift", "lalt", "down")
        assert.same("aa\nbb", K.draft())
        assert.same({ 2, 3 }, { K.cursor() })
        K.keys("up")
        K.keys("lshift", "lalt", "up")
        assert.same("aa\nbb", K.draft())
        assert.same({ 1, 3 }, { K.cursor() })
        -- Ctrl+Z takes back the typing before them
        K.keys("lctrl", "z")
        assert.same("aa\n", K.draft())
      end)

    spec_it("IS6.6 Undo and redo: undoing Ctrl+D puts the "
        .. "cursor where Ctrl+D found it", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type_lines({ "first", "second" })
      K.keys("up")
      K.keys("left")
      assert.same({ 1, 5 }, { K.cursor() })
      K.keys("lctrl", "d")
      assert.same("first\nfirst\nsecond", K.draft())
      assert.same({ 2, 5 }, { K.cursor() })
      K.keys("lctrl", "z")
      assert.same("first\nsecond", K.draft())
      assert.same({ 1, 5 }, { K.cursor() })
      K.keys("lctrl", "y")
      assert.same({ 2, 5 }, { K.cursor() })
    end)
  end)

  describe("the key the editor comes to the front on", function()
    for _, key in ipairs({ "return", "escape" }) do
      spec_it("FR1.2 Resolve each edit: the " .. key .. " a "
          .. "program's hook opens a file on does nothing in the "
          .. "editor it opens", function()
        K.reset({
          ["main.lua"] = OPENS_ON_KEY,
          ["notes.txt"] = "a\nb\n",
        })
        K.open()
        K.keys("lctrl", "t")
        assert.same("ready", K.app_state())
        K.keys(key)
        assert.same("editor", K.app_state())
        assert.same("notes.txt", K.file_name())
        assert.same("a\nb\n", K.file("notes.txt"))
        assert.same("end", K.position())
        -- the next key is the editor's
        K.keys("up")
        assert.same(2, K.position())
      end)
    end
  end)

  describe("a file read anew after a run", function()

    spec_it("IS1.2 Admit or refuse a file: a file made "
        .. "non-UTF-8 while hidden is not taken", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\n" })
      K.open()
      K.keys("lctrl", "t")
      K.write_outside("main.lua", "bad \255 byte\n")
      K.keys("lctrl", "t")
      assert.same({ "a = 1", "b = 2" }, K.view_rows())
      K.type("c = 3")
      K.keys("return")
      assert.same("bad \255 byte\n", K.file())
      assert.same("c = 3", K.draft())
    end)

  end)
end)
