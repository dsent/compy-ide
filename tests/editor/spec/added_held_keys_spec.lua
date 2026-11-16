-- Which keys repeat while held (the maintainer's ruling of
-- November 16, 2026, which adopts the specification's and
-- Luditor's): a held key repeats, and each key is safe to hold
-- because it reaches a natural stop. A key acts once per press
-- where the specification says so (a program field's Enter,
-- API2.2; Ctrl+Z and Ctrl+Y beyond the draft, IS6.6) or where a
-- repeat would do harm: the console's Enter, the editor's
-- Escape, Shift+Ins, Ctrl+Ins, Ctrl+J, Ctrl+R and Ctrl+T. Keys
-- only, through tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it
local spec_deviation = marks.spec_deviation

--- Press `k` with `mods` held, send `n` repeats of it, and
--- let everything go.
--- @param mods string[]
--- @param k string
--- @param n integer?  2 when omitted
local function held(mods, k, n)
  for _, m in ipairs(mods) do K.hold(m) end
  K.hold(k)
  for _ = 1, n or 2 do K.repeat_key(k) end
  K.release(k)
  for i = #mods, 1, -1 do K.release(mods[i]) end
end

describe("held keys #editor #spec", function()
  after_each(K.cleanup)

  describe("in the file editor, a key that repeats to its "
      .. "natural stop", function()
    spec_it("IS4.2 Append after the last block: a held Enter "
        .. "submits the draft, and each repeat adds an empty "
        .. "line, as Luditor's", function()
        K.reset({ ["notes.txt"] = "a\n" })
        K.open("notes.txt")
        K.type("b")
        held({ }, "return", 2)
        assert.same("a\nb\n\n\n", K.file("notes.txt"))
      end)

    spec_it("IS4.3 Submit an empty draft: a held Enter in an "
        .. "empty field adds an empty line per repeat", function()
      K.reset({ ["notes.txt"] = "a\n" })
      K.open("notes.txt")
      held({ }, "return", 2)
      assert.same("a\n\n\n\n", K.file("notes.txt"))
    end)

    spec_it("IS6.2 Cut a block: a held Ctrl+Delete removes the "
        .. "empty lines down to the first block with text, cuts "
        .. "it, and stops", function()
      K.reset({ ["notes.txt"] = "a\n\n\nb\nc\n" })
      K.open("notes.txt")
      K.browse_to(2)
      held({ "lctrl" }, "delete", 4)
      assert.same("a\nc\n", K.file("notes.txt"))
      assert.same("b", K.draft())
      assert.same("inserting", K.state())
    end)

    spec_it("IS6.5 Move a block: a held Alt+Up moves the block "
        .. "up to the file's start, and stops", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\nc = 3\n" })
      K.open()
      K.browse_to(3)
      held({ "lalt" }, "up", 3)
      assert.same("c = 3\na = 1\nb = 2\n", K.file())
      assert.same(1, K.position())
    end)

    spec_it("IS6.5 Move a block: a held Alt+Down moves the block "
        .. "down to the file's end, and stops", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\nc = 3\n" })
      K.open()
      K.browse_to(1)
      held({ "lalt" }, "down", 3)
      assert.same("b = 2\nc = 3\na = 1\n", K.file())
      assert.same(3, K.position())
    end)

  end)

  describe("in the file editor, a key that acts once", function()
    -- the user's ruling of November 16: rushing through files
    -- at repeat speed would confuse
    spec_it("IS1.5 Follow a file reference: a held Ctrl+J "
        .. "follows one reference, though the file it opens names "
        .. "another", function()
      K.reset({
        ["main.lua"] = 'require("lib")\n',
        ["lib.lua"] = 'require("other")\n',
        ["other.lua"] = "x = 1\n",
      })
      K.open()
      K.browse_to(1)
      held({ "lctrl" }, "j", 3)
      assert.same("lib.lua", K.file_name())
      -- a press of its own follows the next
      K.browse_to(1)
      K.keys("lctrl", "j")
      assert.same("other.lua", K.file_name())
    end)

    spec_it("IS5.7 Cancel an edit with Escape: a held Escape "
        .. "aborts the edit and stays in the file: a repeat would "
        .. "leave it, and with it the timeline that holds a cut "
        .. "block", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\n" })
      K.open()
      K.browse_to(1)
      K.keys("f2")
      assert.same("replacing", K.state())
      held({ }, "escape", 3)
      assert.same("editor", K.app_state())
      assert.same("browsing", K.state())
      assert.same(1, K.position())
    end)

    spec_it("IS6.4 Submit and retain the field: a held Shift+Ins "
        .. "submits once: a repeat would add a copy each time",
      function()
        K.reset({ ["main.lua"] = "a = 1\n" })
        K.open()
        K.type("b = 2")
        held({ "lshift" }, "insert")
        assert.same("a = 1\nb = 2\n", K.file())
        assert.same("b = 2", K.draft())
      end)

    spec_it("IS6.1 Copy a block: a held Ctrl+Ins copies the "
        .. "block once: a repeat would add a copy each time",
      function()
        K.reset({ ["main.lua"] = "a = 1\nb = 2\n" })
        K.open()
        K.browse_to(1)
        held({ "lctrl" }, "insert")
        assert.same("a = 1", K.draft())
      end)
  end)

  describe("in the file editor, a key that repeats", function()
    spec_it("IS2.1 Browse blocks: a held Down browses a block "
        .. "per repeat", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\nc = 3\nd = 4\n" })
      K.open()
      K.browse_to(1)
      held({ }, "down")
      assert.same(4, K.position())
    end)

    spec_it("IS2.1 Browse blocks: a held Ctrl+Up browses a block "
        .. "per repeat", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\nc = 3\nd = 4\n" })
      K.open()
      held({ "lctrl" }, "up", 3)
      assert.same(1, K.position())
    end)

    spec_it("IS3.8 Position the text cursor: a held Left moves "
        .. "the cursor a character per repeat", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type("abcd")
      held({ }, "left")
      assert.same({ 1, 2 }, { K.cursor() })
    end)

    spec_it("IS3.15 Break a line: a held Shift+Enter breaks the "
        .. "line per repeat", function()
      K.reset({ ["notes.txt"] = "" })
      K.open("notes.txt")
      K.type("a")
      held({ "lshift" }, "return")
      assert.same("a\n\n\n", K.draft())
    end)

    spec_it("IS3.12 Keep deletion keys in the draft: a held "
        .. "Backspace deletes a character per repeat", function()
      K.reset({ ["notes.txt"] = "" })
      K.open("notes.txt")
      K.type("abcd")
      held({ }, "backspace")
      assert.same("a", K.draft())
    end)

    spec_it("IS6.6 Undo and redo: a held Ctrl+Z takes back the "
        .. "draft's changes per repeat", function()
      K.reset({ ["notes.txt"] = "" })
      K.open("notes.txt")
      K.type("a b c")
      held({ "lctrl" }, "z", 1)
      assert.same("a", K.draft())
    end)
  end)

  describe("a key held as the surface changes", function()
    -- the press went to the program, whose hook opened the
    -- file: its repeats are not the editor's
    spec_it("IS1.1 Open a Lua file: a held Up that made a "
        .. "program open a file browses nothing there", function()
      K.reset({
        ["main.lua"] = "compy.input.hooks.keypressed = function(k)\n"
            .. "  if k == 'up' then edit('notes.txt') end\nend\n",
        ["notes.txt"] = "a\nb\nc\n",
      })
      K.open()
      K.keys("lctrl", "t")
      K.hold("up")
      K.ed = K.cc.editor
      assert.same("notes.txt", K.file_name())
      K.repeat_key("up")
      K.repeat_key("up")
      K.release("up")
      assert.same("end", K.position())
    end)

    -- the press went to the program, whose hook stopped it
    spec_it("IS7.8 Recall an instruction: a held PgUp that "
        .. "stopped a program recalls nothing in the console",
      function()
        K.reset({
          ["main.lua"] = "function love.update() end\n"
              .. "compy.input.hooks.keypressed = function(k)\n"
              .. "  if k == 'pageup' then stop(); return true end\n"
              .. "end\n",
        })
        K.type("run()")
        K.keys("return")
        assert.same("running", K.app_state())
        K.hold("pageup")
        assert.same("ready", K.app_state())
        K.repeat_key("pageup")
        K.repeat_key("pageup")
        K.release("pageup")
        assert.same("", K.console_draft())
      end)
  end)

  describe("in the console", function()
    spec_it("IS3.6 Execute console input: a held Enter runs the "
        .. "line once, and a failed line stays under its error",
      function()
        K.reset()
        K.type("x = = 1")
        held({ }, "return", 3)
        assert.is_true(K.cc.input:has_error())
        assert.same("x = = 1", K.console_draft())
      end)

    spec_it("IS3.6 Execute console input: a held Enter runs a "
        .. "line that fails as it runs once, and the field "
        .. "empties", function()
        K.reset()
        K.type("n = (n or 0) + 1; error('x')")
        held({ }, "return", 3)
        assert.same(1, K.cc:get_project_env().n)
        assert.same("", K.console_draft())
      end)

    -- the reserved chords that would switch or run anew at
    -- repeat speed act once per press; Ctrl+Q stops by itself
    spec_it("IS1.4 Resume after running a project: a held Ctrl+R "
        .. "runs the project once", function()
        K.reset({ ["main.lua"] =
          "RUNS = (RUNS or 0) + 1\nfunction love.update() end\n" })
        local runs, orig = 0, K.cc.restart
        K.cc.restart = function(...)
          runs = runs + 1
          return orig(...)
        end
        held({ "lctrl" }, "r", 3)
        K.cc.restart = orig
        assert.same(1, runs)
        assert.same("running", K.app_state())
      end)

    spec_it("IS1.4 Resume after running a project: a held Ctrl+T "
        .. "switches once", function()
        K.reset({ ["main.lua"] = "x = 1\n" })
        K.open()
        held({ "lctrl" }, "t", 3)
        assert.are_not.same("editor", K.app_state())
      end)

    spec_it("IS1.4 Resume after running a project: a held Ctrl+Q "
        .. "stops the program and then does nothing more",
      function()
        K.reset({ ["main.lua"] = "function love.update() end\n" })
        K.keys("lctrl", "r")
        assert.same("running", K.app_state())
        K.type("ab")
        held({ "lctrl" }, "q", 3)
        assert.same("ready", K.app_state())
        assert.is_false(K.cc.run_live)
      end)

    -- the spec's *submission* names Shift+Ins in the console
    spec_deviation("IS6.4 Submit and retain the field: Shift+Ins "
        .. "in the console, pressed or held, does nothing",
      "the maintainer's ruling of November 14, 2026: Shift+Ins "
        .. "does nothing in the console", function()
        K.reset()
        K.type("kept = (kept or 0) + 1")
        K.keys("left")
        held({ "lshift" }, "insert")
        assert.is_nil(K.cc:get_project_env().kept)
        assert.same("kept = (kept or 0) + 1", K.console_draft())
        local l, c = K.cc.input:get_cursor_pos()
        assert.same({ 1, 22 }, { l, c })
        assert.is_false(K.cc.input:has_error())
      end)

    spec_it("IS3.6 Execute console input: Ctrl+Ins does nothing "
        .. "in the console", function()
      K.reset()
      K.type("copied = 1")
      K.keys("lctrl", "insert")
      assert.same("copied = 1", K.console_draft())
      assert.is_nil(K.cc:get_project_env().copied)
    end)

    spec_it("IS3.8 Position the text cursor: a held Left in the "
        .. "console moves a character per repeat", function()
      K.reset()
      K.type("abcd")
      held({ }, "left")
      local l, c = K.cc.input:get_cursor_pos()
      assert.same({ 1, 2 }, { l, c })
    end)
  end)
end)
