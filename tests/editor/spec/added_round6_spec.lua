-- The sixth review round's findings, each as the keys that
-- showed it: the key card follows who the help key goes to, a
-- `#!` first line keeps its text through a change, formatting
-- and their undo and redo, and a key held as the editor comes
-- to the front adds nothing. Keys only, through
-- tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it

--- a program that takes every key through its hook and shows
--- no field: it idles behind the console with the keys
local HOOK_ONLY = [[
received = {}
compy.input.hooks.keypressed = function(k)
  received[#received + 1] = k
  return true
end
]]

--- a program that takes the help key alone, as a shortcut
local F1_SHORTCUT = [[
compy.input.shortcuts.keypressed['f1'] = function()
  saw_f1 = true
  return true
end
]]

--- a program that holds the screen and takes no key. The
--- project's love table outlives a run, so each program here
--- clears what an earlier one left in it.
local DRAWS = [[
love.update = nil
function love.draw() end
]]

--- a program that runs on and takes no key: the keys fall
--- through to the console
local UPDATES = [[
love.draw = nil
function love.update() end
]]

--- the program's own global, as its code left it
local function program_global(name)
  return K.cc:get_project_env()[name]
end

describe("round six #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("the key card and who the help key goes to",
    function()
      spec_it("IS3.16 Show the key card: no console card shows "
          .. "over a program that takes keys through its hook "
          .. "alone, and Ctrl+Q acts while F1 is held", function()
        K.reset({ ["main.lua"] = HOOK_ONLY })
        K.open()
        K.keys("lctrl", "t")
        assert.same("ready", K.app_state())
        assert.is_true(K.cc.run_live)
        local received = program_global("received")
        local before = #received
        K.hold("f1")
        assert.is_nil(K.key_card())
        K.keys("left")
        assert.same({ "f1", "left" },
          { received[before + 1], received[before + 2] })
        K.keys("lctrl", "q")
        K.release("f1")
        assert.is_false(K.cc.run_live)
      end)

      spec_it("IS3.16 Show the key card: no console card shows "
          .. "over a program with a shortcut for the help key",
        function()
          K.reset({ ["main.lua"] = F1_SHORTCUT })
          K.open()
          K.keys("lctrl", "t")
          assert.same("ready", K.app_state())
          K.hold("f1")
          assert.is_nil(K.key_card())
          K.release("f1")
          assert.is_true(program_global("saw_f1"))
        end)

      -- a guard: the card never showed while a program runs
      spec_it("IS3.16 Show the key card: no console card shows "
          .. "over a program that holds the screen, and Ctrl+Q "
          .. "acts while F1 is held", function()
        K.reset({ ["main.lua"] = DRAWS })
        K.open()
        K.keys("lctrl", "t")
        assert.same("running", K.app_state())
        K.hold("f1")
        assert.is_nil(K.key_card())
        K.keys("lctrl", "q")
        K.release("f1")
        assert.same("ready", K.app_state())
        assert.is_false(K.cc.run_live)
      end)

      -- turned around on November 17: a program that runs on owns
      -- all input, whether it takes a key or not: the keys and
      -- F1 are its own, and no console card comes up
      spec_it("IS3.16 Show the key card: over a program that "
          .. "runs on and takes no key, the keys are the "
          .. "program's, and no card comes up", function()
        K.reset({ ["main.lua"] = UPDATES })
        K.open()
        K.keys("lctrl", "t")
        assert.same("running", K.app_state())
        K.type("a")
        assert.same("", K.console_draft())
        K.hold("f1")
        assert.is_nil(K.key_card())
        K.type("y")
        K.release("f1")
        assert.same("", K.console_draft())
        K.keys("lctrl", "q")
        assert.is_false(K.cc.run_live)
      end)
    end)

  describe("a #! first line", function()
    -- a guard: undo and redo restored the bytes before
    spec_it("FR3.1 Preserve file structure: a #! first line "
        .. "keeps its text through a change, its undo and its "
        .. "redo, and through formatting and its undo",
      function()
        local text = "#!/usr/bin/lua\nx=1\n"
        K.reset({ ["main.lua"] = text })
        K.open()
        K.type("y = 2")
        K.keys("return")
        assert.same("#!/usr/bin/lua\nx=1\ny = 2\n", K.file())
        K.keys("lctrl", "z")
        assert.same(text, K.file())
        K.keys("lctrl", "y")
        assert.same("#!/usr/bin/lua\nx=1\ny = 2\n", K.file())
        K.keys("lalt", "f")
        assert.same("#!/usr/bin/lua\nx = 1\ny = 2\n", K.file())
        K.keys("lctrl", "z")
        assert.same("#!/usr/bin/lua\nx=1\ny = 2\n", K.file())
      end)

  end)

  describe("a key held as the editor comes to the front",
    function()
      spec_it("IS1.1 Open a file: a held Enter that submitted "
          .. "edit() in the console adds nothing to the file",
        function()
          K.reset({ ["main.lua"] = "a = 1\n" })
          K.type('edit("main.lua")')
          K.hold("return")
          K.ed = K.cc.editor
          K.repeat_key("return")
          K.repeat_key("return")
          K.release("return")
          assert.same("a = 1\n", K.file())
          assert.same({ }, K.writes())
          -- a key pressed in the editor repeats there
          K.type("b = 234")
          K.hold("backspace")
          K.repeat_key("backspace")
          K.release("backspace")
          assert.same("b = 2", K.draft())
          K.keys("return")
          assert.same("a = 1\nb = 2\n", K.file())
        end)
    end)

end)
