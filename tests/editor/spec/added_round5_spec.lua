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

--- a press on the console's field and a drag over it, which
--- selects text there when it reaches the field
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
      spec_it("IS6.4 Submit and retain the field: the cursor in "
          .. "leading blank lines stays when the formatter "
          .. "changes the text after them", function()
        K.reset({ ["main.lua"] = "" })
        K.open()
        K.keys("lshift", "return")
        K.keys("lshift", "return")
        K.type("x=1")
        K.keys("lctrl", "home")
        K.keys("right")
        assert.same({ 2, 1 }, { K.cursor() })
        K.keys("lshift", "insert")
        assert.same("\n\nx = 1", K.draft())
        assert.same({ 2, 1 }, { K.cursor() })
      end)

      spec_it("IS6.4 Submit and retain the field: the cursor in "
          .. "trailing blank lines stays when the formatter "
          .. "changes the text before them", function()
        K.reset({ ["main.lua"] = "" })
        K.open()
        K.type("x=1")
        K.keys("lshift", "return")
        K.keys("lshift", "return")
        K.keys("left")
        assert.same({ 2, 1 }, { K.cursor() })
        K.keys("lshift", "insert")
        assert.same("x = 1\n\n", K.draft())
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
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      drag()
      K.release("f1")
      assert.is_false(K.cc.input.model:has_selection())
      -- the same drag, the card away, selects
      drag()
      assert.is_true(K.cc.input.model:has_selection())
    end)
  end)

  describe("a #! line in the field", function()
    --- where the field turns the draft red, nil where it does
    --- not
    local function red()
      local _, at = K.field_highlight()
      return at
    end

    spec_it("IS3.4 Locate a syntax failure: the file's own #! "
        .. "first line loaded with F2 is not red, and Enter "
        .. "keeps it", function()
      local original = "#!/usr/bin/lua\nx = 1\n"
      K.reset({ ["main.lua"] = original })
      K.open()
      K.browse_to(1)
      K.keys("f2")
      assert.same("#!/usr/bin/lua", K.draft())
      assert.is_nil(red())
      K.keys("return")
      assert.same(original, K.file())
      assert.same("browsing", K.state())
    end)

    spec_it("IS3.4 Locate a syntax failure: a #! line typed "
        .. "into an empty file is not red, and Enter takes it",
      function()
        K.reset({ ["main.lua"] = "" })
        K.open()
        K.type("#!/usr/bin/lua")
        assert.is_nil(red())
        K.keys("return")
        assert.same("#!/usr/bin/lua\n", K.file())
      end)

    spec_it("IS3.4 Locate a syntax failure: a #! draft is red "
        .. "below the first line and not above it, as Enter "
        .. "refuses and takes it", function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.open()
      K.type("#!/usr/bin/lua")
      assert.is_not_nil(red())
      K.browse_to(1)
      assert.is_nil(red())
      K.keys("lctrl", "down")
      assert.same("end", K.position())
      assert.is_not_nil(red())
      K.keys("return")
      assert.same("x = 1\n", K.file())
      assert.same("error", K.message_kind())
      K.browse_to(1)
      assert.is_nil(red())
      K.keys("return")
      assert.same("#!/usr/bin/lua\nx = 1\n", K.file())
    end)

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

  describe("a file changed while hidden, read once", function()
    for _, ext in ipairs({ "lua", "txt", "md" }) do
      spec_it("IS1.4 Resume after running a project: in a ."
          .. ext .. " file changed while the editor was "
          .. "hidden, the text "
          .. "Ctrl+T finds changed is the text it shows, and a "
          .. "read failing after it changes nothing", function()
        local name = ext == "lua" and "main.lua" or "notes." .. ext
        K.reset({ ["main.lua"] = "x = 1\n", [name] = "x = 1\n" })
        K.open(name)
        K.type("q")
        K.keys("backspace")
        K.keys("lctrl", "t")
        assert.are_not.same("editor", K.app_state())
        K.write_outside(name, "x = 2\n")
        K.fail_reads_after(1, name)
        K.keys("lctrl", "t")
        assert.same("editor", K.app_state())
        assert.same(name, K.file_name())
        assert.same(1, K.blocks())
        assert.same("x = 2", K.view_rows()[1])
        assert.same("x = 2\n", K.file(name))
      end)
    end
  end)

  describe("the line endings formatting keeps", function()
    local MIXED = "a=1\r\nb = 2\nc=3\r\n"
    local TIDY = "a = 1\r\nb = 2\nc = 3\r\n"

    spec_it("FR3.1 Preserve file structure: tidy() keeps the "
        .. "ending of a line it leaves as it is between lines "
        .. "it changes", function()
      K.reset({ ["main.lua"] = MIXED })
      K.type('tidy("main.lua")')
      K.keys("return")
      assert.same(TIDY, K.file())
    end)

    spec_it("FR3.1 Preserve file structure: Ctrl+Shift+F keeps "
        .. "the ending of a line it leaves as it is between "
        .. "lines it changes, and undoes and redoes", function()
      K.reset({ ["main.lua"] = MIXED })
      K.open()
      K.keys("lctrl", "lshift", "f")
      assert.same(TIDY, K.file())
      K.keys("lctrl", "z")
      assert.same(MIXED, K.file())
      K.keys("lctrl", "y")
      assert.same(TIDY, K.file())
    end)
  end)

  describe("a change from outside and the keys after it",
    function()
      spec_it("IS3.14 Explain a refusal: the notice that a file "
          .. "changed while hidden to text the editor cannot take "
          .. "stays after the Ctrl+T that brings it back, until "
          .. "the next key", function()
        K.reset({ ["main.lua"] = "x = 1\n" })
        K.open()
        K.keys("lctrl", "t")
        assert.are_not.same("editor", K.app_state())
        K.write_outside("main.lua", "x = '\255'\n")
        K.keys("lctrl", "t")
        assert.same("editor", K.app_state())
        assert.truthy((K.message() or ""):find(
          "changed outside the editor", 1, true))
        assert.same("x = 1", K.view_rows()[1])
        K.keys("up")
        assert.is_nil(K.message())
      end)

      local ABORTS = {
        ["after a refused Enter"] = true,
        ["with no key between"] = false,
      }
      for label, enter in pairs(ABORTS) do
        spec_it("IS6.6 Undo and redo: an abort after a change "
            .. "from outside undoes, " .. label, function()
          K.reset({ ["main.lua"] = "a = 1\nb = 2\n" })
          K.open()
          K.browse_to(1)
          K.keys("lctrl", "delete")
          assert.same("a = 1", K.draft())
          K.write_outside("main.lua", "c = 3\n")
          if enter then
            K.keys("return")
            assert.truthy((K.message() or ""):find(
              "changed outside the editor", 1, true))
          end
          K.keys("escape")
          assert.same("", K.draft())
          K.keys("lctrl", "z")
          assert.same("a = 1", K.draft())
          assert.same("c = 3\n", K.file())
        end)
      end
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
    spec_it("IS1.4 Resume after running a project: a file read "
        .. "anew after a run keeps the line endings the SD card "
        .. "holds", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\n" })
      K.open()
      K.keys("lctrl", "t")
      K.write_outside("main.lua", "a = 1\r\nb = 2\r\nc = 3\r\n")
      K.keys("lctrl", "t")
      K.type("d = 4")
      K.keys("return")
      assert.same("a = 1\r\nb = 2\r\nc = 3\r\nd = 4\r\n",
        K.file())
    end)

    spec_it("IS1.4 Resume after running a project: a file read "
        .. "anew after a run that broke it is a line per block",
      function()
        K.reset({ ["main.lua"] = "a = 1\nb = 2\n" })
        K.open()
        K.keys("lctrl", "t")
        K.write_outside("main.lua",
          "a = = 1\nfunction f()\n  b = 2\nend\n")
        K.keys("lctrl", "t")
        assert.same(4, K.blocks())
        K.browse_to(2)
        K.keys("f2")
        assert.is_nil(K.target())
        assert.truthy((K.message() or ""):find("cannot split", 1,
          true))
      end)

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

    spec_it("IS1.5 Follow a file reference: a file read anew "
        .. "after a run follows the reference it now holds",
      function()
        K.reset({ ["main.lua"] = "a = 1\n", ["lib.lua"] = "l = 1\n" })
        K.open()
        K.keys("lctrl", "t")
        K.write_outside("main.lua", "require('lib')\n")
        K.keys("lctrl", "t")
        K.browse_to(1)
        K.keys("lctrl", "j")
        assert.same("lib.lua", K.file_name())
      end)

    spec_it("IS5.3 Submit a replacement: a #! first line is "
        .. "replaced in place while the position is elsewhere",
      function()
        K.reset({ ["main.lua"] = "#!/usr/bin/lua\nx = 1\ny = 2\n" })
        K.open()
        K.browse_to(1)
        K.keys("f2")
        K.browse_to(3)
        K.type("jit")
        K.keys("return")
        assert.same("#!/usr/bin/luajit\nx = 1\ny = 2\n", K.file())
      end)
  end)
end)
