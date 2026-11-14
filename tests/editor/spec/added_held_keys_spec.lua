-- Which keys repeat while held (the maintainer's ruling of
-- November 14, 2026): in the file editor and the console a
-- key repeats only if it writes nothing to a file and changes
-- no state. Enter, Escape, F2, Shift+Ins, Ctrl+Ins, moving a
-- block and the commands act once per press. Keys only,
-- through tests/helpers/editor_keys.lua.

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

  describe("in the file editor, a key that acts once", function()
    spec_it("IS4.2 Append after the last block: a held Enter "
        .. "submits the draft once and adds no empty line",
      function()
        K.reset({ ["main.lua"] = "a = 1\n" })
        K.open()
        K.type("b = 2")
        held({ }, "return")
        assert.same("a = 1\nb = 2\n", K.file())
      end)

    spec_it("IS4.3 Submit an empty draft: a held Enter in an "
        .. "empty field adds one empty line", function()
      K.reset({ ["notes.txt"] = "a\n" })
      K.open("notes.txt")
      held({ }, "return")
      assert.same("a\n\n", K.file("notes.txt"))
    end)

    spec_it("IS5.7 Cancel an edit with Escape: a held Escape "
        .. "aborts the edit and stays in the file", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\n" })
      K.open()
      K.browse_to(1)
      K.keys("f2")
      assert.same("replacing", K.state())
      held({ }, "escape")
      assert.same("editor", K.app_state())
      assert.same("browsing", K.state())
      assert.same(1, K.position())
    end)

    spec_it("IS6.4 Submit and retain the field: a held Shift+Ins "
        .. "submits once", function()
      K.reset({ ["main.lua"] = "a = 1\n" })
      K.open()
      K.type("b = 2")
      held({ "lshift" }, "insert")
      assert.same("a = 1\nb = 2\n", K.file())
      assert.same("b = 2", K.draft())
    end)

    spec_it("IS6.1 Copy a block: a held Ctrl+Ins copies the "
        .. "block once", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\n" })
      K.open()
      K.browse_to(1)
      held({ "lctrl" }, "insert")
      assert.same("a = 1", K.draft())
    end)

    spec_it("IS6.5 Move a block: a held Alt+Up moves the block "
        .. "one place", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\nc = 3\n" })
      K.open()
      K.browse_to(3)
      held({ "lalt" }, "up")
      assert.same("a = 1\nc = 3\nb = 2\n", K.file())
      assert.same(2, K.position())
    end)

    spec_it("IS6.5 Move a block: a held Alt+Down moves the block "
        .. "one place", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\nc = 3\n" })
      K.open()
      K.browse_to(1)
      held({ "lalt" }, "down")
      assert.same("b = 2\na = 1\nc = 3\n", K.file())
      assert.same(2, K.position())
    end)

    spec_it("IS1.5 Follow a file reference: a held Ctrl+J "
        .. "follows once, and refuses nothing in the file it "
        .. "opened", function()
      K.reset({
        ["main.lua"] = 'require("lib")\n',
        ["lib.lua"] = "x = 1\n",
      })
      K.open()
      K.browse_to(1)
      held({ "lctrl" }, "j")
      assert.same("lib.lua", K.file_name())
      assert.is_nil(K.message())
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
