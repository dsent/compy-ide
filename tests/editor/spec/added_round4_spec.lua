-- The fourth review round's findings, each as the keys that
-- showed it: a program idling behind the editor, a notice
-- that outlives its key, the cursor of a retained draft,
-- pasted line breaks, a card taken out before a file opens,
-- keys that change nothing, the draft's own steps, a `#!`
-- line put back, guards no test held, the files below the
-- front one, and the browsing position kept by line when a
-- file is split anew. Keys only, through
-- tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it

local UNREAD = "could not be read"
local EDITING = "Already editing a block"

--- a program whose Escape hook closes its project
local ESCAPE_CLOSES = [[
compy.input.hooks.keypressed = function(k)
  if k == 'escape' then close_project(); return true end
end
]]

--- a program that opens a file from its own key handler, and
--- takes every key and text it is offered afterwards, as a
--- love.keypressed of its own would (hooks, so that the
--- program's globals do not outlive the test)
local OPENS_ON_F3 = [[
compy.input.hooks.keypressed = function(k)
  if k == 'f3' then edit('notes.txt') end
  if k == 'up' then saw_up = true end
  return true
end
compy.input.hooks.textinput = function(t)
  got = (got or '') .. t
  return true
end
]]

--- a program that stops or runs its project from its handlers
local STOPS = [[
compy.input.hooks.keypressed = function(k)
  if k == 'f6' then stop(); return true end
  if k == 'f7' then run_project(); return true end
end
]]

--- a program that idles with a hook, and whose exit hook
--- opens a file, then writes one
local EDITS_ON_EXIT = [[
compy.input.hooks.keypressed = function() end
compy.before_exit = function()
  edit('notes.txt')
  writefile('done.txt', 'yes')
end
]]

--- the names of the files on the editor's stack, front first
local function stack()
  local out = {}
  for _, b in ipairs(K.cc.editor.model.buffers) do
    out[#out + 1] = b.name
  end
  return out
end

--- the program's own global, as its code left it
local function program_global(name)
  return K.cc:get_project_env()[name]
end

describe("round four #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("no program behind the editor", function()
    for _, ext in ipairs({ "lua", "txt", "md" }) do
      spec_it("FR1.2 Resolve each edit: in a ." .. ext
          .. " file, edit() in the console after a run stops "
          .. "the idle program, so its Escape hook cannot close "
          .. "the project over a cut", function()
        local name = "notes." .. ext
        K.reset({
          ["main.lua"] = ESCAPE_CLOSES,
          [name] = "precious = 123\nother = 456\n",
        })
        K.next_project("scratch", { ["main.lua"] = "" })
        K.open(name)
        K.keys("lctrl", "t")
        assert.same("ready", K.app_state())
        assert.is_true(K.cc.run_live)
        K.open(name)
        assert.same("editor", K.app_state())
        assert.is_false(K.cc.run_live)
        K.browse_to(1)
        K.keys("lctrl", "delete")
        assert.same("precious = 123", K.draft())
        K.keys("escape")
        assert.same("editor", K.app_state())
        assert.same(K.PROJECT, K.cc.model.projects.current.name)
        assert.same(name, K.file_name())
        assert.same("", K.draft())
        K.keys("lctrl", "z")
        assert.same("precious = 123", K.draft())
      end)
    end

    spec_it("IS1.1 Open a Lua file: a program's own edit() "
        .. "stops it, and the editor's keys and text reach the "
        .. "editor alone", function()
      K.reset({
        ["main.lua"] = OPENS_ON_F3,
        ["notes.txt"] = "a\nb\n",
      })
      K.open()
      K.keys("lctrl", "t")
      assert.same("ready", K.app_state())
      K.keys("f3")
      assert.same("editor", K.app_state())
      assert.same("notes.txt", K.file_name())
      assert.is_false(K.cc.run_live)
      assert.same("end", K.position())
      K.keys("up")
      assert.same(2, K.position())
      assert.is_nil(program_global("saw_up"))
      K.type("new")
      assert.same("new", K.draft())
      assert.is_nil(program_global("got"))
    end)

    spec_it("IS3.11 Preserve state on refusal: a program that "
        .. "idled behind the console cannot stop or run its "
        .. "project over an edit opened with edit()", function()
      K.reset({
        ["main.lua"] = STOPS,
        ["work.lua"] = "a = 1\nb = 2\n",
      })
      K.type("run()")
      K.keys("return")
      assert.same("ready", K.app_state())
      assert.is_true(K.cc.run_live)
      K.open("work.lua")
      assert.is_false(K.cc.run_live)
      K.browse_to(1)
      K.keys("lctrl", "delete")
      K.type(" + 1")
      K.keys("f6")
      K.keys("f7")
      assert.same("editor", K.app_state())
      assert.same("work.lua", K.file_name())
      assert.same("a = 1 + 1", K.draft())
      assert.same("b = 2\n", K.file("work.lua"))
      -- back in the console, the keys are the console's
      K.keys("escape")
      K.keys("escape")
      assert.same("ready", K.app_state())
      K.type("q")
      assert.same("q", K.console_draft())
    end)
  end)

  describe("a notice and the key that hides the editor", function()
    local RUNS = {
      ["Ctrl+T"] = { "lctrl", "t" },
      ["Ctrl+Alt+R"] = { "lctrl", "lalt", "r" },
    }
    for run, keys in pairs(RUNS) do
      spec_it("IS3.14 Explain a refusal: a notice shown before "
          .. run .. " is gone when Ctrl+T brings its file back",
        function()
          K.reset({ ["main.lua"] = "x = 1\n" })
          K.open()
          K.keys("f2")
          assert.truthy(K.message())
          K.keys(unpack(keys))
          assert.are_not.same("editor", K.app_state())
          K.keys("lctrl", "t")
          assert.same("editor", K.app_state())
          assert.same("main.lua", K.file_name())
          assert.is_nil(K.message())
        end)
    end
  end)

  describe("the cursor of a retained draft", function()
    for _, ext in ipairs({ "txt", "md" }) do
      local name = "notes." .. ext
      spec_it("IS6.4 Submit and retain the field: in a ." .. ext
          .. " file the cursor keeps its place in leading "
          .. "spaces", function()
        K.reset({ ["main.lua"] = "", [name] = "" })
        K.open(name)
        K.type("  hello")
        K.keys("home")
        K.keys("right")
        assert.same({ 1, 2 }, { K.cursor() })
        K.keys("lshift", "insert")
        assert.same("  hello\n", K.file(name))
        assert.same("  hello", K.draft())
        assert.same({ 1, 2 }, { K.cursor() })
      end)

      spec_it("IS6.4 Submit and retain the field: in a ." .. ext
          .. " file the cursor keeps its place in trailing "
          .. "spaces", function()
        K.reset({ ["main.lua"] = "", [name] = "" })
        K.open(name)
        K.type("hello  ")
        K.keys("left")
        assert.same({ 1, 7 }, { K.cursor() })
        K.keys("lshift", "insert")
        assert.same("hello  ", K.draft())
        assert.same({ 1, 7 }, { K.cursor() })
      end)
    end

    spec_it("IS6.4 Submit and retain the field: a Lua draft the "
        .. "formatter leaves as it is keeps its cursor", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type("s = \"a  b\"")
      for _ = 1, 3 do K.keys("left") end
      local l, c = K.cursor()
      K.keys("lshift", "insert")
      assert.same("s = \"a  b\"\n", K.file())
      assert.same({ l, c }, { K.cursor() })
    end)
  end)

  describe("pasted line breaks", function()
    for _, ext in ipairs({ "txt", "md" }) do
      local name = "notes." .. ext
      for label, sep in pairs({ CRLF = "\r\n", CR = "\r" }) do
        spec_it("FR3.1 Preserve file structure: in a CRLF ." .. ext
            .. " file, text pasted with " .. label .. " line "
            .. "breaks is written with the file's own", function()
          K.reset({ ["main.lua"] = "", [name] = "existing\r\n" })
          K.open(name)
          love.system.setClipboardText("first" .. sep .. "second")
          K.keys("lctrl", "v")
          assert.same("first\nsecond", K.draft())
          K.keys("return")
          assert.same("existing\r\nfirst\r\nsecond\r\n", K.file(name))
          K.keys("escape")
          K.open(name)
          assert.same(3, K.blocks())
        end)
      end
    end

    spec_it("IS3.15 Break a line in the field: the console takes "
        .. "pasted CRLF as line breaks", function()
      K.reset()
      love.system.setClipboardText("a\r\nb\rc")
      K.keys("lctrl", "v")
      assert.same("a\nb\nc", K.console_draft())
    end)
  end)

  describe("the SD card out when a file opens", function()
    spec_it("IS1.2 Admit or refuse a file: with the card out, "
        .. "edit() refuses the file it cannot read", function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.remove_card()
      K.open()
      assert.same("ready", K.app_state())
      assert.is_nil(K.buffer())
      assert.truthy(K.console_text():find(
        "main.lua " .. UNREAD, 1, true))
      K.insert_card()
      K.open()
      assert.same("editor", K.app_state())
      assert.same(1, K.blocks())
    end)

    spec_it("IS1.5 Follow a file reference: with the card out, "
        .. "Ctrl+J says the file cannot be read", function()
      K.reset({
        ["main.lua"] = "require('lib')\n",
        ["lib.lua"] = "l = 1\n",
      })
      K.open()
      K.browse_to(1)
      K.remove_card()
      K.keys("lctrl", "j")
      assert.same("main.lua", K.file_name())
      assert.truthy((K.message() or ""):find(
        "lib.lua " .. UNREAD, 1, true))
    end)

    spec_it("IS1.2 Admit or refuse a file: a file missing from a "
        .. "folder that can be read opens as a new one", function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.open("new.txt")
      assert.same("editor", K.app_state())
      assert.same("new.txt", K.file_name())
      assert.same(0, K.blocks())
    end)
  end)

  describe("a key that changes nothing", function()
    for label, keys in pairs({
      Backspace = { "backspace" },
      Delete = { "delete" },
      ["Ctrl+Backspace"] = { "lctrl", "backspace" },
      ["Ctrl+V with nothing to paste"] = { "lctrl", "v" },
    }) do
      spec_it("IS6.6 Undo and redo: " .. label .. " in an empty "
          .. "field keeps what can be redone", function()
        K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
        K.open()
        K.type("z = 3")
        K.keys("return")
        K.keys("lctrl", "z")
        assert.same("x = 1\ny = 2\n", K.file())
        K.keys(unpack(keys))
        K.keys("lctrl", "y")
        assert.same("x = 1\ny = 2\nz = 3\n", K.file())
      end)
    end

    spec_it("IS6.6 Undo and redo: keys that change nothing add "
        .. "no Ctrl+Z press", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.type("z = 3")
      K.keys("return")
      for _ = 1, 3 do K.keys("backspace") end
      for _ = 1, 2 do K.keys("delete") end
      K.keys("lctrl", "z")
      assert.same("x = 1\ny = 2\n", K.file())
    end)

    spec_it("IS6.6 Undo and redo: a refused Enter that changes "
        .. "nothing adds no Ctrl+Z press", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type(string.rep("n", 70) .. " = 1")
      -- the first refusal shows the draft formatted, one change
      K.keys("return")
      local shown = K.draft()
      for _ = 1, 3 do K.keys("return") end
      assert.same(shown, K.draft())
      assert.truthy((K.message() or ""):find("limit", 1, true))
      K.keys("lctrl", "z")
      assert.are_not.same(shown, K.draft())
    end)
  end)

  describe("the draft's own steps", function()
    spec_it("IS6.6 Undo and redo: Ctrl+D is a change to the "
        .. "draft: it drops the redo, and Ctrl+Z takes it back",
      function()
        K.reset({ ["main.lua"] = "" })
        K.open()
        K.type_lines({ "local total = 0", "total = total + 1" })
        K.keys("lctrl", "z")
        local before = K.draft()
        K.keys("lctrl", "d")
        K.keys("lctrl", "d")
        local copied = K.draft()
        assert.are_not.same(before, copied)
        K.keys("lctrl", "y")
        assert.same(copied, K.draft())
        K.keys("lctrl", "z")
        K.keys("lctrl", "z")
        assert.same(before, K.draft())
      end)

    spec_it("IS6.6 Undo and redo: a swap of the draft's lines "
        .. "undoes", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type_lines({ "a = 1", "b = 2" })
      K.keys("lshift", "lalt", "up")
      assert.same("b = 2\na = 1", K.draft())
      K.keys("lctrl", "z")
      assert.same("a = 1\nb = 2", K.draft())
    end)

    spec_it("IS5.6 Switch the replacement target: a draft "
        .. "changed by Ctrl+D is modified", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(1)
      K.keys("f2")
      K.keys("lctrl", "d")
      K.browse_to(2)
      K.keys("f2")
      assert.truthy((K.message() or ""):find(EDITING, 1, true))
      assert.same(1, K.target())
    end)

    spec_it("IS5.6 Switch the replacement target: a draft "
        .. "changed before a change from outside is still "
        .. "modified", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(1)
      K.keys("f2")
      K.type(" + 40 + 2")
      K.write_outside("main.lua", "x = 1\ny = 2\nz = 3\n")
      K.keys("lctrl", "z")
      assert.same("x = 1 + 40 + 2", K.draft())
      K.browse_to(2)
      K.keys("f2")
      assert.truthy((K.message() or ""):find(EDITING, 1, true))
      assert.same("x = 1 + 40 + 2", K.draft())
      assert.same(1, K.target())
    end)

    spec_it("IS5.6 Switch the replacement target: a draft typed "
        .. "into and back is not modified", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(1)
      K.keys("f2")
      K.type("9")
      K.keys("backspace")
      K.browse_to(2)
      K.keys("f2")
      assert.same(2, K.target())
      assert.same("y = 2", K.draft())
    end)
  end)

  describe("a #! first line", function()
    spec_it("IS6.2 Cut a block: Ctrl+Delete on a #! first line "
        .. "is refused with a notice, and the line stays",
      function()
        local original = "#!/usr/bin/lua\nx = 1\n"
        K.reset({ ["main.lua"] = original })
        K.open()
        K.browse_to(1)
        K.keys("lctrl", "delete")
        assert.same("", K.draft())
        assert.same(original, K.file())
        assert.truthy((K.message() or ""):find("#! header", 1,
          true))
      end)

    spec_it("IS6.5 Move a block: a #! first line does not move, "
        .. "and no block moves above it", function()
      local original = "#!/usr/bin/lua\nx = 1\ny = 2\n"
      K.reset({ ["main.lua"] = original })
      K.open()
      K.browse_to(1)
      K.keys("lalt", "down")
      assert.same(original, K.file())
      assert.truthy((K.message() or ""):find("#! header", 1,
        true))
      K.browse_to(2)
      K.keys("lalt", "up")
      assert.same(original, K.file())
      assert.same(2, K.position())
      assert.truthy((K.message() or ""):find("#! header", 1,
        true))
      -- below it, blocks move as ever
      K.browse_to(3)
      K.keys("lalt", "up")
      assert.same("#!/usr/bin/lua\ny = 2\nx = 1\n", K.file())
    end)

    spec_it("IS3.4 Locate a syntax failure: a #! draft below the "
        .. "first line is refused", function()
      local original = "#!/usr/bin/lua\nx = 1\n"
      K.reset({ ["main.lua"] = original })
      K.open()
      K.type("#!/x")
      K.keys("return")
      assert.same(original, K.file())
      assert.same("#!/x", K.draft())
      assert.same("error", K.message_kind())
    end)
  end)

  describe("tidy() in the console", function()
    spec_it("FR3.1 Preserve file structure: tidy() keeps a #! "
        .. "first line and the file's line ends, as Ctrl+Shift+F "
        .. "does", function()
      K.reset({
        ["main.lua"] = "#!/usr/bin/lua\r\nx   =   1\r\ny = 2\n",
      })
      K.type("tidy(\"main.lua\")")
      K.keys("return")
      assert.same("#!/usr/bin/lua\r\nx = 1\r\ny = 2\n", K.file())
      K.reset({
        ["main.lua"] = "#!/usr/bin/lua\r\nx   =   1\r\ny = 2\n",
      })
      K.open()
      K.keys("lctrl", "lshift", "f")
      assert.same("#!/usr/bin/lua\r\nx = 1\r\ny = 2\n", K.file())
    end)

    spec_it("FR3.1 Preserve file structure: tidy() writes nothing "
        .. "to a CRLF file already tidy", function()
      K.reset({ ["main.lua"] = "x = 1\r\ny = 2\r\n" })
      K.type("tidy(\"main.lua\")")
      K.keys("return")
      assert.same({ }, K.writes())
      assert.same("x = 1\r\ny = 2\r\n", K.file())
    end)
  end)

  describe("guards", function()
    --- the key, and the files on the stack after it: Ctrl+T
    --- opens the main file when the editor holds none
    for label, case in pairs({
      ["Ctrl+Q"] = { { "lctrl", "q" }, {} },
      ["Ctrl+T"] = { { "lctrl", "t" }, { "main.lua" } },
    }) do
      spec_it("IS3.11 Preserve state on refusal: edit() in an "
          .. "idle program's exit hook, as " .. label
          .. " stops it, opens nothing and gives the hook back "
          .. "its turn", function()
          K.reset({
            ["main.lua"] = EDITS_ON_EXIT,
            ["notes.txt"] = "a\n",
          })
          K.type("run()")
          K.keys("return")
          assert.is_true(K.cc.run_live)
          K.keys(unpack(case[1]))
          assert.is_false(K.cc.run_live)
          assert.same("yes", K.file("done.txt"))
          assert.same(case[2], stack())
        end)
    end

    spec_it("IS6.6 Undo and redo: after a write that landed "
        .. "between two changes from outside, Ctrl+Z writes "
        .. "nothing over the second", function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.open()
      K.write_outside("main.lua", "changed\n")
      K.keys("lctrl", "z")
      K.write_outside("main.lua", "x = 1\n")
      K.type("y = 2")
      K.keys("return")
      assert.same("x = 1\ny = 2\n", K.file())
      K.write_outside("main.lua", "other\n")
      K.keys("lctrl", "z")
      K.keys("lctrl", "z")
      assert.same("other\n", K.file())
    end)

    spec_it("IS1.2 Admit or refuse a file: a Lua line of spaces "
        .. "between statements keeps the file in blocks",
      function()
        local original = "x = 1\n   \nfunction f()\n  return 1\nend\n"
        K.reset({ ["main.lua"] = original })
        K.open()
        assert.same(3, K.blocks())
        K.browse_to(3)
        K.keys("f2")
        assert.same("replacing", K.state())
        assert.is_nil(K.message())
      end)

    spec_it("FR3.1 Preserve file structure: a move redone in a "
        .. "file of mixed endings writes each line's own",
      function()
        K.reset({ ["main.lua"] = "a = 1\r\nb = 2\nc = 3\r\n" })
        K.open()
        K.browse_to(1)
        K.keys("lalt", "down")
        local moved = K.file()
        assert.same("b = 2\na = 1\r\nc = 3\r\n", moved)
        K.keys("lctrl", "z")
        K.keys("lctrl", "y")
        assert.same(moved, K.file())
      end)

    spec_it("FR3.1 Preserve file structure: a replacement keeps "
        .. "the endings of its first and last lines when they "
        .. "stay", function()
      local original = "function f()\r\n  a = 1\nend\r\n"
          .. "x = 1\ny = 2\nz = 3\n"
      K.reset({ ["main.lua"] = original })
      K.open()
      K.browse_to(1)
      K.keys("f2")
      K.keys("up")
      K.keys("end")
      K.keys("backspace")
      K.type("2")
      K.keys("return")
      assert.same("function f()\r\n  a = 2\nend\r\n"
          .. "x = 1\ny = 2\nz = 3\n", K.file())
    end)

    spec_it("FR3.1 Preserve file structure: a change refused for "
        .. "a failed write puts each line's ending back",
      function()
        local original = "a = 1\r\nb = 2\nc = 3\nd = 4\n"
        K.reset({ ["main.lua"] = original })
        K.open()
        K.fail_writes("card full")
        K.browse_to(1)
        K.keys("lctrl", "delete")
        assert.same(original, K.file())
        K.fail_writes(nil)
        K.browse_to_end()
        K.type("e = 5")
        K.keys("return")
        assert.same(original .. "e = 5\n", K.file())
      end)
  end)

  describe("files below the front one", function()
    local WORK = "require('other')\na = 1\nb = 2\n"

    --- an edit in progress in work.lua, the position on its
    --- require line: the keys, and the draft it leaves
    local EDITS = {
      draft = function()
        K.browse_to(1)
        K.type("z = 3")
        return "z = 3"
      end,
      replacement = function()
        K.browse_to(2)
        K.keys("f2")
        K.browse_to(1)
        return "a = 1"
      end,
      ["cut block"] = function()
        K.browse_to(3)
        K.keys("lctrl", "delete")
        K.browse_to(1)
        return "b = 2"
      end,
    }

    --- each way out of the file, then edit() of another one
    --- in the console, wherever the key left the person
    local LEAVES = {
      ["Ctrl+J"] = { "lctrl", "j" },
      ["Ctrl+T"] = { "lctrl", "t" },
      ["Ctrl+Alt+R"] = { "lctrl", "lalt", "r" },
      ["Ctrl+Q"] = { "lctrl", "q" },
      ["Ctrl+Shift+S"] = { "lctrl", "lshift", "s" },
    }

    for edit, start in pairs(EDITS) do
      for leave, keys in pairs(LEAVES) do
        spec_it("FR1.2 Resolve each edit: with a " .. edit
            .. " in the field, " .. leave
            .. " and edit() put no file in front of it",
          function()
            K.reset({ ["main.lua"] = "", ["work.lua"] = WORK,
              ["other.lua"] = "o = 1\n" })
            K.open("work.lua")
            local draft = start()
            local state = K.state()
            K.keys(unpack(keys))
            if K.app_state() ~= "editor" then
              K.type('edit("other.lua")')
              K.keys("return")
            end
            assert.same("editor", K.app_state())
            assert.same({ "work.lua" }, stack())
            assert.same(draft, K.draft())
            assert.same(state, K.state())
          end)
      end
    end

    spec_it("IS1.5 Follow a file reference: the file Ctrl+J "
        .. "leaves is in the browsing state below the one it "
        .. "opens", function()
      K.reset({ ["main.lua"] = "", ["work.lua"] = WORK,
        ["other.lua"] = "o = 1\n" })
      K.open("work.lua")
      K.browse_to(1)
      K.keys("lctrl", "j")
      assert.same({ "other.lua", "work.lua" }, stack())
      local below = K.cc.editor.model.buffers[2]
      assert.is_nil(below.loaded)
      local text = below.input:get_text()
      assert.same("", table.concat(text, "\n"))
    end)
  end)

  describe("the browsing position, kept by line", function()
    --- the first line of the block at the browsing position
    local function viewed()
      local lines = K.buffer():block_lines(K.position())
      return lines and lines[1]
    end

    --- six functions of five lines, a blank line after each;
    --- the third line of function `bad` does not parse
    local function functions(bad)
      local t = {}
      for i = 1, 6 do
        t[#t + 1] = "function f" .. i .. "()"
        t[#t + 1] = "  local a = " .. i
        t[#t + 1] = i == bad and "  local b = = a"
            or "  local b = a"
        t[#t + 1] = "  return a + b"
        t[#t + 1] = "end"
        t[#t + 1] = ""
      end
      return table.concat(t, "\n") .. "\n"
    end

    --- the draft `  local b = = a` repaired: one `=` less
    local function repair()
      K.keys("left")
      K.keys("backspace")
      K.keys("backspace")
      assert.same("  local b = a", K.draft())
    end

    for bad, label in pairs({ [2] = "early", [5] = "late" }) do
      spec_it("IS6.2 Cut a block: a cut that lets a file parse "
          .. "again leaves the position on the block that "
          .. "holds the line after the cut one, in a function "
          .. label .. " in the file", function()
        local original = functions(bad)
        K.reset({ ["main.lua"] = original })
        K.open()
        assert.same(36, K.blocks())
        local line = (bad - 1) * 6 + 3
        K.browse_to(line)
        K.keys("lctrl", "delete")
        assert.same("  local b = = a", K.draft())
        assert.same(12, K.blocks())
        local block = (bad - 1) * 2 + 1
        assert.same(block, K.position())
        assert.same("function f" .. bad .. "()", viewed())
        repair()
        K.keys("return")
        local fixed = original:gsub(
          "(function f" .. bad .. "%(%)\n  local a = %d\n)"
          .. "  local b = = a\n", "local b = a\n%1")
        assert.same(fixed, K.file())
        assert.same(block + 1, K.position())
      end)
    end

    local TOP = "x = 1\nfunction f()\n  return x\nend\n"
        .. "y = = 2\nfunction g()\n  return y\nend\n"

    spec_it("IS6.3 Restore a cut block: a line that did not "
        .. "parse, cut and repaired, goes back with Enter "
        .. "where it was cut", function()
      K.reset({ ["main.lua"] = TOP })
      K.open()
      assert.same(8, K.blocks())
      K.browse_to(5)
      K.keys("lctrl", "delete")
      assert.same(3, K.blocks())
      assert.same(3, K.position())
      assert.same("function g()", viewed())
      K.keys("left")
      K.keys("left")
      K.keys("backspace")
      K.keys("backspace")
      assert.same("y = 2", K.draft())
      K.keys("return")
      assert.same(TOP:gsub("= = 2", "= 2"), K.file())
    end)

    spec_it("IS6.6 Undo and redo: undo and redo across the cut "
        .. "that lets a file parse keep the position on the "
        .. "line after the cut one", function()
      K.reset({ ["main.lua"] = TOP })
      K.open()
      K.browse_to(5)
      K.keys("lctrl", "delete")
      assert.same("function g()", viewed())
      K.keys("lctrl", "z")
      assert.same(TOP, K.file())
      assert.same(8, K.blocks())
      assert.same(6, K.position())
      assert.same("function g()", viewed())
      K.keys("lctrl", "y")
      assert.same(3, K.blocks())
      assert.same("y = = 2", K.draft())
      assert.same(3, K.position())
      assert.same("function g()", viewed())
    end)

    spec_it("IS6.5 Move a block: a move that lets a file parse "
        .. "leaves the position on the block that holds the "
        .. "moved line, after undo and redo too", function()
      local original = "x = 0\nend\nfunction f()\n  x = 1\n"
      K.reset({ ["main.lua"] = original })
      K.open()
      assert.same(4, K.blocks())
      K.browse_to(2)
      K.keys("lalt", "down")
      local moved = "x = 0\nfunction f()\nend\n  x = 1\n"
      assert.same(moved, K.file())
      assert.same(3, K.blocks())
      assert.same(2, K.position())
      assert.same({ "function f()", "end" },
        K.buffer():block_lines(2))
      K.keys("lctrl", "z")
      assert.same(original, K.file())
      assert.same(2, K.position())
      assert.same("end", viewed())
      K.keys("lctrl", "y")
      assert.same(3, K.blocks())
      assert.same(2, K.position())
      assert.same("function f()", viewed())
    end)

    spec_it("IS3.11 Preserve state on refusal: Ctrl+Z refused "
        .. "for a failed write leaves the position on the "
        .. "block it was on", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(1)
      K.keys("f2")
      K.keys("backspace")
      K.type("5")
      K.keys("return")
      assert.same("x = 5\ny = 2\n", K.file())
      K.browse_to(1)
      K.fail_writes("card full")
      K.keys("lctrl", "z")
      assert.same("x = 5\ny = 2\n", K.file())
      assert.same(1, K.position())
      K.fail_writes(nil)
      K.keys("lctrl", "z")
      assert.same("x = 1\ny = 2\n", K.file())
    end)

    spec_it("IS3.11 Preserve state on refusal: Ctrl+Shift+F "
        .. "refused for a failed write leaves the position on "
        .. "the block it was on", function()
      local original = "x   =   1\ny = 2\n"
      K.reset({ ["main.lua"] = original })
      K.open()
      K.browse_to(1)
      K.fail_writes("card full")
      K.keys("lctrl", "lshift", "f")
      assert.same(original, K.file())
      assert.same(1, K.position())
    end)
  end)
end)
