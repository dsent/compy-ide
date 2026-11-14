-- The seventh review round's finding, as the keys that showed
-- it: the key card belongs to whoever the help key's press
-- went to, until its release, whatever modifiers come and go
-- and whatever runs or stops meanwhile.
-- Keys only, through tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local F = require("tests.helpers.input_fixture")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it
local spec_deviation = marks.spec_deviation

--- a program that takes the bare help key, as a shortcut
local F1_SHORTCUT = [[
compy.input.shortcuts.keypressed['f1'] = function()
  saw_f1 = true
  return true
end
]]

--- a program that takes every Ctrl chord, and no bare key
local CTRL_CLASS = [[
compy.input.shortcuts.keypressed['ctrl+*'] = function()
  return true
end
]]

--- a program that runs on, takes no key, and stops itself
--- after a few frames. The project's love table outlives a
--- run, so it takes its update back with it.
local STOPS_SOON = [[
love.draw = nil
frames = 0
function love.update()
  frames = frames + 1
  if frames == 4 then
    love.update = nil
    stop()
  end
end
]]

--- the program's own global, as its code left it
local function program_global(name)
  return K.cc:get_project_env()[name]
end

describe("round seven #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("the key card follows the help key's press",
    function()
      spec_it("IS3.16 Show the key card: over a program that "
          .. "took F1, Ctrl pressed while F1 is held brings no "
          .. "card, and Ctrl+Q stops the program", function()
        K.reset({ ["main.lua"] = F1_SHORTCUT })
        K.open()
        K.keys("lctrl", "t")
        assert.same("ready", K.app_state())
        K.hold("f1")
        assert.is_true(program_global("saw_f1"))
        K.hold("lctrl")
        assert.is_nil(K.key_card())
        K.keys("q")
        K.release("lctrl")
        K.release("f1")
        assert.is_false(K.cc.run_live)
      end)

      -- the console's card suspends no reserved chord
      spec_deviation("IS3.16 Show the key card: the console's "
          .. "card for a bare F1 stays when Ctrl is pressed over "
          .. "a program with a Ctrl shortcut, and Ctrl+Q stops "
          .. "the program under it",
          "rulings.md: The key card suspends reserved chords in "
          .. "the editor only", function()
        K.reset({ ["main.lua"] = CTRL_CLASS })
        K.open()
        K.keys("lctrl", "t")
        assert.same("ready", K.app_state())
        K.hold("f1")
        assert.is_not_nil(K.key_card())
        K.hold("lctrl")
        assert.is_not_nil(K.key_card())
        K.keys("q")
        K.release("lctrl")
        assert.is_false(K.cc.run_live)
        K.release("f1")
        assert.is_nil(K.key_card())
      end)

      spec_it("IS3.16 Show the key card: F1 that a program took "
          .. "brings no card when the program stops under it; "
          .. "its next press does", function()
        K.reset({ ["main.lua"] = F1_SHORTCUT })
        K.open()
        K.keys("lctrl", "t")
        K.hold("f1")
        K.keys("lctrl", "q")
        assert.is_false(K.cc.run_live)
        assert.is_nil(K.key_card())
        K.type("a")
        assert.same("a", K.console_draft())
        K.release("f1")
        K.hold("f1")
        assert.is_not_nil(K.key_card())
        K.release("f1")
      end)

      spec_it("IS3.16 Show the key card: F1 that a program took "
          .. "brings no card in the editor that Ctrl+T opens "
          .. "under it, and the editor's keys act", function()
        K.reset({ ["main.lua"] = F1_SHORTCUT })
        K.open()
        K.keys("lctrl", "t")
        K.hold("f1")
        K.keys("lctrl", "t")
        assert.same("editor", K.app_state())
        assert.is_nil(K.key_card())
        K.type("b")
        assert.same("b", K.draft())
        K.release("f1")
        K.hold("f1")
        assert.is_not_nil(K.key_card())
        K.release("f1")
      end)

      -- a guard: the record outlives the run that stops
      spec_it("IS3.16 Show the key card: the console's card "
          .. "stays while a run stops under it, and the keys "
          .. "wait for F1's release", function()
        K.reset({ ["main.lua"] = STOPS_SOON })
        K.open()
        K.keys("lctrl", "t")
        assert.same("running", K.app_state())
        K.hold("f1")
        assert.is_not_nil(K.key_card())
        for _ = 1, 4 do K.frame() end
        assert.is_false(K.cc.run_live)
        assert.same("ready", K.app_state())
        assert.is_not_nil(K.key_card())
        K.type("y")
        assert.same("", K.console_draft())
        K.release("f1")
        assert.is_nil(K.key_card())
        K.type("y")
        assert.same("y", K.console_draft())
      end)

      -- a guard: the card suspends the reserved presses alone
      spec_it("IS3.16 Show the key card: Ctrl+Escape asks to "
          .. "quit while the editor's card shows", function()
        K.reset({ ["main.lua"] = "a = 1\n" })
        K.open()
        K.hold("f1")
        assert.is_not_nil(K.key_card())
        F.quits()
        K.keys("lctrl", "escape")
        assert.same(1, #F.quits())
        K.release("f1")
      end)
    end)

  -- the review's findings on the paths that write
  describe("a key repeats only where its press acted", function()
    spec_it("IS3.16 Show the key card: Enter pressed under the "
        .. "card does not repeat once F1 is released, though "
        .. "Enter acted in the file before", function()
      K.reset({ ["main.lua"] = "a = 1\n" })
      K.open()
      K.type("b = 2")
      K.keys("return")
      assert.same("a = 1\nb = 2\n", K.file())
      K.hold("f1")
      K.hold("return")
      K.release("f1")
      K.repeat_key("return")
      K.repeat_key("return")
      K.release("return")
      assert.same("a = 1\nb = 2\n", K.file())
    end)

    -- a guard: the press is recorded only past _held_back
    spec_it("IS1.1 Open a file: a held Enter that made a program "
        .. "open a file adds nothing to it", function()
      K.reset({
        ["main.lua"] = "compy.input.hooks.keypressed = function(k)\n"
            .. "  if k == 'return' then edit('notes.txt') end\nend\n",
        ["notes.txt"] = "a\nb\n",
      })
      K.open()
      K.keys("lctrl", "t")
      K.hold("return")
      K.ed = K.cc.editor
      assert.same("notes.txt", K.file_name())
      K.repeat_key("return")
      K.repeat_key("return")
      K.release("return")
      assert.same("a\nb\n", K.file("notes.txt"))
      assert.same({ }, K.writes())
    end)

    spec_it("IS5.7 Cancel an edit with Escape: a held Escape "
        .. "that leaves the file does not clear the console's "
        .. "line", function()
      K.reset({ ["main.lua"] = "a = 1\n" })
      K.open()
      K.keys("escape")
      assert.same("ready", K.app_state())
      K.type("foo")
      K.keys("lctrl", "t")
      assert.same("editor", K.app_state())
      K.hold("escape")
      assert.same("ready", K.app_state())
      K.repeat_key("escape")
      K.repeat_key("escape")
      K.release("escape")
      assert.same("foo", K.console_draft())
    end)

    spec_it("IS1.4 Resume after running a project: a held Ctrl+T "
        .. "runs the project once", function()
      K.reset({ ["main.lua"] = "runs = (runs or 0) + 1\n" })
      K.open()
      K.hold("lctrl")
      K.hold("t")
      assert.are_not.same("editor", K.app_state())
      K.repeat_key("t")
      K.repeat_key("t")
      K.repeat_key("t")
      K.release("t")
      K.release("lctrl")
      assert.are_not.same("editor", K.app_state())
      assert.same(1, K.cc:get_project_env().runs)
    end)
  end)

  -- the language layer as the base reads it (the ruling that
  -- the editor rework changes nothing there)
  describe("a file's first line that Lua skips", function()
    spec_it("IS1.2 Admit or refuse a file: a file of a #! line "
        .. "alone, with a line end or without, is its header "
        .. "and nothing else; formatting changes nothing, and "
        .. "text goes after the header", function()
      for _, text in ipairs({ "#!/usr/bin/lua\n", "#!/usr/bin/lua" }) do
        K.reset({ ["main.lua"] = text })
        K.open()
        assert.falsy(K.buffer().invalid)
        assert.same(1, K.blocks())
        K.keys("lctrl", "lshift", "f")
        assert.is_nil(K.message())
        assert.same(text, K.file())
        K.type("x = 1")
        K.keys("return")
        assert.same("#!/usr/bin/lua\nx = 1\n", K.file())
        K.cleanup()
      end
    end)

    spec_it("IS1.1 Open a file: an empty Lua file has no block, "
        .. "and formatting it changes nothing and says nothing",
      function()
        K.reset({ ["main.lua"] = "" })
        K.open()
        assert.same(0, K.blocks())
        assert.falsy(K.buffer().invalid)
        K.keys("lctrl", "lshift", "f")
        assert.is_nil(K.message())
        assert.same("", K.file())
      end)
  end)

  describe("a #! first line", function()

    -- a guard: the header is a Lua file's alone
    spec_it("IS8.2 Submit text: a #! first line of a text file "
        .. "is a line like any other", function()
      K.reset({ ["notes.txt"] = "#!x\nb\n" })
      K.open("notes.txt")
      K.browse_to(1)
      K.keys("f2")
      assert.same(1, K.target())
      K.type("y")
      K.keys("return")
      assert.same("#!xy\nb\n", K.file("notes.txt"))
      K.browse_to(1)
      K.keys("lctrl", "delete")
      assert.same("b\n", K.file("notes.txt"))
    end)

    spec_it("FR3.1 Preserve file structure: formatting a file "
        .. "that holds a #! line alone leaves it as it is",
      function()
        K.reset({ ["main.lua"] = "#!x\n" })
        K.type('tidy("main.lua")')
        K.keys("return")
        assert.same("#!x\n", K.file())
        K.open()
        K.keys("lctrl", "lshift", "f")
        assert.same("#!x\n", K.file())
        assert.same({ }, K.writes())
      end)
  end)
end)
