-- The sixth review round's findings, each as the keys that
-- showed it: the key card follows who the help key goes to,
-- a `#!` first line stays as it is through every action, and
-- formatting keeps the line endings the documents promise.
-- Keys only, through tests/helpers/editor_keys.lua.

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

      spec_it("IS3.16 Show the key card: over a program that "
          .. "runs on and takes no key, the keys are the "
          .. "console's, and so is the card", function()
        K.reset({ ["main.lua"] = UPDATES })
        K.open()
        K.keys("lctrl", "t")
        assert.same("running", K.app_state())
        K.type("a")
        assert.same("a", K.console_draft())
        K.hold("f1")
        assert.is_not_nil(K.key_card())
        K.type("y")
        K.release("f1")
        assert.same("a", K.console_draft())
        K.keys("lctrl", "q")
        assert.is_false(K.cc.run_live)
      end)
    end)

  describe("a #! first line", function()
    -- a guard: undo and redo restored the bytes before
    spec_it("FR3.1 Preserve file structure: a #! first line "
        .. "keeps its bytes through a change, its undo and its "
        .. "redo, and through formatting and its undo",
      function()
        local text = "#!/usr/bin/lua\r\nx=1\r\n"
        K.reset({ ["main.lua"] = text })
        K.open()
        K.type("y = 2")
        K.keys("return")
        assert.same("#!/usr/bin/lua\r\nx=1\r\ny = 2\r\n", K.file())
        K.keys("lctrl", "z")
        assert.same(text, K.file())
        K.keys("lctrl", "y")
        assert.same("#!/usr/bin/lua\r\nx=1\r\ny = 2\r\n", K.file())
        K.keys("lctrl", "lshift", "f")
        assert.same("#!/usr/bin/lua\r\nx = 1\r\ny = 2\r\n",
          K.file())
        K.keys("lctrl", "z")
        assert.same("#!/usr/bin/lua\r\nx=1\r\ny = 2\r\n", K.file())
      end)

    spec_it("IS5.6 Switch the replacement target: a replacement "
        .. "does not switch to a #! first line", function()
      K.reset({ ["main.lua"] = "#!/usr/bin/lua\nx = 1\n" })
      K.open()
      K.browse_to(2)
      K.keys("f2")
      assert.same(2, K.target())
      K.browse_to(1)
      K.keys("f2")
      assert.same(2, K.target())
      assert.truthy((K.message() or ""):find("#! header", 1,
        true))
    end)
  end)

  describe("line endings formatting keeps", function()
    -- a guard: it pins the limit the documents now state
    spec_it("FR3.1 Preserve file structure: formatting keeps "
        .. "the endings of the lines outside the change; a line "
        .. "inside it that pairs within eight lines keeps its "
        .. "own, and one beyond takes the file's main ending",
      function()
        local stmts = { }
        for i = 1, 12 do
          stmts[#stmts + 1] = string.format("a%d=%d", i, i)
        end
        local text = "function f() " .. table.concat(stmts, ";")
            .. " end\r\nmarker = 42\ntail=9\r\nlast = 1\n"
        K.reset({ ["main.lua"] = text })
        K.open()
        K.keys("lctrl", "lshift", "f")
        local file = K.file()
        -- outside the change: the last line keeps its LF
        assert.truthy(file:find("tail = 9\r\nlast = 1\n$"))
        -- inside it, the unchanged line is more than eight
        -- lines from its place: it takes the main ending
        assert.truthy(file:find("\r\nmarker = 42\r\n", 1, true))
        K.keys("lctrl", "z")
        assert.same(text, K.file())
      end)

    -- guards: the pairing's skipping, which no test reached
    spec_it("FR3.1 Preserve file structure: tidy() keeps the "
        .. "ending of an unchanged line below a line it splits",
      function()
        K.reset({
          ["main.lua"] = "if a then b = 1 end\r\nc = 3\nd=4\r\n",
        })
        K.type('tidy("main.lua")')
        K.keys("return")
        assert.same("if a then\r\n  b = 1\r\nend\r\nc = 3\nd = 4\r\n",
          K.file())
      end)

    spec_it("FR3.1 Preserve file structure: tidy() keeps the "
        .. "ending of an unchanged line below blank lines it "
        .. "removes", function()
      K.reset({ ["main.lua"] = "a=1\n\n\n\nb = 2\r\nc=3\n" })
      K.type('tidy("main.lua")')
      K.keys("return")
      assert.same("a = 1\n\nb = 2\r\nc = 3\n", K.file())
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
          K.type("b = 2")
          K.keys("return")
          K.hold("return")
          K.repeat_key("return")
          K.release("return")
          assert.same("a = 1\nb = 2\n\n\n", K.file())
        end)
    end)

  describe("a write refused for a change from outside", function()
    -- a guard: _refuse_stale's ending of the timeline
    spec_it("IS6.6 Undo and redo: text typed after a write "
        .. "refused for a change from outside is undone",
      function()
        K.reset({ ["main.lua"] = "a = 1\n" })
        K.open()
        K.type("b = 2")
        K.write_outside("main.lua", "z = 9\n")
        K.keys("return")
        K.type("3")
        assert.same("b = 23", K.draft())
        K.keys("lctrl", "z")
        assert.same("b = 2", K.draft())
        assert.same("z = 9\n", K.file())
      end)
  end)
end)
