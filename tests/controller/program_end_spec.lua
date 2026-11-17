-- A lifecycle call made from code ends that code at once, and
-- the IDE carries out the request when the code has returned
-- (design B, the maintainer's ruling of November 16, 2026).
-- Keys only, through the K helper.

local K = require("tests.helpers.editor_keys")

local unrouted
local function reset(contents)
  K.reset(contents)
  local base, project = K.cc:get_base_env(), K.cc:get_project_env()
  unrouted = unrouted or { base.print, project.print }
  base.print, project.print = print, print
end

local function cleanup()
  if unrouted then
    K.cc:get_base_env().print = unrouted[1]
    K.cc:get_project_env().print = unrouted[2]
    unrouted = nil
  end
  K.cleanup()
end

local function run(line)
  K.type(line)
  K.keys("return")
  K.frame(100)
end

local function env()
  return K.cc:get_project_env()
end

--- `note(word)` in a program or a typed line, its words read
--- back here; it is in the base environment, so every
--- environment a run or a reset makes has it
local function notes()
  local said = { }
  local function note(w) said[#said + 1] = w end
  local base = K.cc:get_base_env()
  base.note = note
  env().note = note
  finally(function() base.note = nil end)
  return said
end

local function count(said, w)
  local n = 0
  for _, s in ipairs(said) do
    if s == w then n = n + 1 end
  end
  return n
end

local EXIT = "compy.before_exit = function() note('exit') end\n"
local LIVE = "function love.update() end\n"

--- `body` placed where the IDE calls into the program
local PLACES = {
  { "top-level code", function(body)
    return EXIT .. LIVE .. body .. "\n"
  end, function() end },
  { "love.update", function(body)
    return EXIT .. "function love.update()\n" .. body .. "\nend\n"
  end, function() K.frame() end },
  { "love.draw", function(body)
    return EXIT .. LIVE .. "function love.draw()\n" .. body .. "\nend\n"
  end, function() K.frame(); love.draw() end },
  { "love.keypressed", function(body)
    return EXIT .. LIVE .. "function love.keypressed(k)\n"
      .. "if k == 'g' then\n" .. body .. "\nend\nend\n"
  end, function() K.keys("g") end },
  { "an input hook", function(body)
    return EXIT .. LIVE .. "compy.input.hooks.keypressed = function(k)\n"
      .. "if k == 'g' then\n" .. body .. "\nend\nend\n"
  end, function() K.keys("g") end },
}

describe("a lifecycle call ends the code that made it #console",
  function()
    after_each(cleanup)

    for _, place in ipairs(PLACES) do
      local name, program, trigger = place[1], place[2], place[3]
      for _, call in ipairs({ "stop()", "reset()" }) do
        it(call .. " from " .. name .. " runs nothing after it,"
          .. " and the stop happens once", function()
            reset({ ["main.lua"] = program(call .. "\nnote('after')") })
            local said = notes()
            run("run()")
            trigger()
            assert.equal(0, count(said, "after"))
            assert.equal(1, count(said, "exit"))
            assert.is_false(K.cc.run_live)
            assert.same("ready", K.app_state())
          end)
      end
    end

    it("project() from love.update runs nothing after it", function()
      reset({ ["main.lua"] = EXIT
        .. "function love.update()\nproject('other')\nnote('after')\nend\n" })
      K.next_project("other", { ["main.lua"] = "\n" })
      local said = notes()
      run("run()")
      K.frame()
      assert.equal(0, count(said, "after"))
      assert.equal(1, count(said, "exit"))
      assert.same("other", K.cc.model.projects.current.name)
      assert.is_false(K.cc.run_live)
    end)

    it("run() from love.update replaces the program once the"
      .. " update returns", function()
        reset({ ["main.lua"] = EXIT .. "note('start')\n"
          .. "function love.update()\n"
          .. "if once() then run(); note('after') end\n"
          .. "end\n" })
        local said = notes()
        local base, asked = K.cc:get_base_env(), false
        base.once = function()
          local first = not asked
          asked = true
          return first
        end
        finally(function() base.once = nil end)
        run("run()")
        K.frame()
        assert.equal(0, count(said, "after"))
        assert.equal(1, count(said, "exit"))
        assert.equal(2, count(said, "start"))
        assert.is_true(K.cc.run_live)
        assert.same("running", K.app_state())
        K.keys("lctrl", "q")
      end)

    it("run() in before_exit ends the hook and runs nothing",
      function()
        reset({ ["main.lua"] = "compy.before_exit = function()\n"
          .. "note('exit')\nrun()\nnote('after')\nend\n" .. LIVE })
        local said = notes()
        run("run()")
        K.keys("lctrl", "q")
        assert.same({ "exit" }, said)
        assert.is_false(K.cc.run_live)
      end)

    it("ends a function the handler called, and the handler", function()
      reset({ ["main.lua"] = EXIT
        .. "local function quit() stop(); note('in') end\n"
        .. "function love.update()\nquit()\nnote('after')\nend\n" })
      local said = notes()
      run("run()")
      K.frame()
      assert.equal(0, count(said, "in"))
      assert.equal(0, count(said, "after"))
      assert.equal(1, count(said, "exit"))
    end)

    it("is no error: nothing is said, and the globals go", function()
      reset({ ["main.lua"] = "g = 1\nstop()\n" .. LIVE })
      notes()
      run("run()")
      assert.is_nil(K.console_text():find("rror", 1, true),
        K.console_text())
      assert.is_nil(env().g)
      assert.is_false(K.cc.run_live)
    end)

    it("an error before stop() is an error, the stop never made",
      function()
        reset({ ["main.lua"] = EXIT .. "error('first')\nstop()\n" })
        local said = notes()
        run("run()")
        assert.truthy(K.console_text():find("first", 1, true),
          K.console_text())
        assert.equal(0, count(said, "exit"))
        assert.is_false(K.cc.run_live)
      end)

    describe("a typed line", function()
      --- a program that ended its code but keeps its picture is
      --- live and can do nothing more: the console takes lines
      --- behind it (November 17)
      it("stop(); print(1) prints nothing after the stop", function()
        reset({ ["main.lua"] = "x = 1\n" })
        run("run()")
        assert.is_true(K.cc.run_live)
        run("stop(); print('AFTER' .. '_STOP')")
        assert.is_nil(K.console_text():find("AFTER_STOP", 1, true))
        assert.is_false(K.cc.run_live)
      end)

      it("r = reset() assigns nothing", function()
        reset()
        run("r = 1")
        run("r = reset()")
        assert.is_nil(env().r)
        assert.truthy(K.console_text():find("Runtime reset for ", 1,
          true))
      end)

      it("project('other'); note('after') runs nothing after it",
        function()
          reset()
          K.next_project("other", { ["main.lua"] = "\n" })
          local said = notes()
          run("project('other'); note('after')")
          assert.same({ }, said)
          assert.same("other", K.cc.model.projects.current.name)
        end)

      it("run(); note('after') runs nothing after the run", function()
        reset({ ["main.lua"] = "note('ran')\n" })
        local said = notes()
        run("run(); note('after')")
        assert.same({ "ran" }, said)
      end)
    end)

    it("the program's own pcall swallows the end: its code runs on,"
      .. " and the stop is made when that code returns", function()
        reset({ ["main.lua"] = EXIT .. "function love.update()\n"
          .. "pcall(stop)\nnote('after')\nend\n" })
        local said = notes()
        run("run()")
        K.frame()
        assert.equal(1, count(said, "after"))
        assert.equal(1, count(said, "exit"))
        assert.is_false(K.cc.run_live)
      end)

    it("the first request wins", function()
      reset({ ["main.lua"] = EXIT .. "print('KEPT_ROW')\n"
        .. "function love.update()\n"
        .. "pcall(stop)\npcall(reset)\nnote('after')\nend\n" })
      local said = notes()
      run("run()")
      K.frame()
      assert.equal(1, count(said, "after"))
      assert.equal(1, count(said, "exit"))
      --- the stop, not the reset: the console is not erased
      assert.truthy(K.console_text():find("KEPT_ROW", 1, true))
      assert.is_nil(K.console_text():find("Runtime reset", 1, true))
    end)

    it("stop() in before_exit ends the hook; the stop goes on once",
      function()
        reset({ ["main.lua"] = "compy.before_exit = function()\n"
          .. "note('exit')\nstop()\nnote('after')\nend\n" .. LIVE })
        local said = notes()
        run("run()")
        K.keys("lctrl", "q")
        assert.same({ "exit" }, said)
        assert.is_false(K.cc.run_live)
        assert.same("ready", K.app_state())
      end)

    it("project() in before_exit ends the hook and opens nothing",
      function()
        reset({ ["main.lua"] = "compy.before_exit = function()\n"
          .. "note('exit')\nproject('other')\nnote('after')\nend\n"
          .. LIVE })
        K.next_project("other", { ["main.lua"] = "\n" })
        local said = notes()
        run("run()")
        K.keys("lctrl", "q")
        assert.same({ "exit" }, said)
        assert.is_false(K.cc.run_live)
        assert.same(K.PROJECT, K.cc.model.projects.current.name)
      end)

    --- a program that runs owns the input; a line is typed while
    --- it is paused (November 17)
    it("a typed run() while a program is paused is refused, and"
      .. " the line goes on", function()
        reset({ ["main.lua"] = LIVE })
        local said = notes()
        run("run()")
        K.cc:suspend_run()
        K.cc:suspend()
        assert.same("inspect", K.app_state())
        run("run(); note('after')")
        assert.same({ "after" }, said)
        assert.truthy(K.console_text():find("already running", 1, true))
        assert.is_true(K.cc.run_live)
        K.keys("lctrl", "q")
      end)

    --- round 17: the field's highlighter, which the IDE calls as
    --- it renders the field, is program code too
    it("stop() in a field's highlighter ends it, and is made when"
      .. " the IDE's call returns", function()
        reset({ ["main.lua"] = EXIT .. LIVE
          .. "compy.input.show({ highlighter = function(t)\n"
          .. "  if t[1] == 'go' then stop(); note('after') end\n"
          .. "  return { }\nend })\n" })
        local said = notes()
        run("run()")
        local field = love.state.user_input_controller
        field.model:set_text("go")
        local End = require("util.program_end")
        End.held(function() field.model:highlight() end)
        assert.equal(0, count(said, "after"))
        assert.equal(1, count(said, "exit"))
        assert.is_false(K.cc.run_live)
      end)

    it("an edit() its admission refuses ends nothing", function()
      reset({ ["main.lua"] = "x = 1\n" })
      local said = notes()
      run("run()")
      assert.is_true(K.cc.run_live)
      run("edit('../bad'); note('after')")
      assert.same({ "after" }, said, K.console_text())
      assert.is_true(K.cc.run_live)
    end)

    it("a run() whose main.lua cannot be read ends nothing",
      function()
        reset({ ["main.lua"] = "x = 1\n" })
        local said = notes()
        run("run()")
        assert.is_true(K.cc.run_live)
        K.fail_reads("main.lua")
        run("run(); note('after')")
        assert.same({ "after" }, said)
        assert.is_true(K.cc.run_live)
      end)

    it("a refused call ends nothing", function()
      reset()
      local said = notes()
      run("stop(); note('after')")
      assert.same({ "after" }, said)
      assert.truthy(K.console_text():find("Nothing is running.", 1,
        true))
    end)
  end)

-- round 22: a question asked at the console with nothing live
-- is refused, and leaves nothing for the next run to restore
describe("compy.ask with nothing live #console", function()
  after_each(cleanup)

  --- with no widget, the question asks nothing; the next run's
  --- unask() then has no question to withdraw, and hides no
  --- field of its own
  it("leaves nothing for the next run's unask() to withdraw",
    function()
      reset({ ["main.lua"] = "compy.input.show({ })\n"
        .. "compy.unask()\n"
        .. "function love.update() end\n" })
      run("compy.ask('old')")
      run("run()")
      local field = love.state.user_input_controller
      assert.is_true(field:is_shown())
      K.keys("lctrl", "q")
    end)
end)

-- round 23: what a program created is released at its stop, a
-- question it left unanswered included
describe("compy.ask at a stop #console", function()
  after_each(cleanup)

  it("keeps no stopped program's widget alive", function()
    reset({ ["main.lua"] = "compy.ask('name?')\n"
      .. "function love.update() end\n" })
    run("run()")
    local held = setmetatable({ love.state.user_input_controller },
      { __mode = "v" })
    assert.is_not_nil(held[1])
    K.keys("lctrl", "q")
    assert.is_false(K.cc.run_live)
    collectgarbage("collect")
    collectgarbage("collect")
    assert.is_nil(held[1])
  end)
end)

-- Beads compy-ide-ask-flags-keep-a-stopped-programs-callbacks:
-- a question's flags are no store of a program's callbacks
describe("compy.ask's flags at a stop #console", function()
  after_each(cleanup)

  it("keep no stopped program's callback, capture or environment",
    function()
      reset({ ["main.lua"] = "BIG = { }\n"
        .. "compy.input.callbacks.on_text_entered = function()\n"
        .. "  return BIG\nend\n"
        .. "compy.ask('name?')\n"
        .. "function love.update() end\n" })
      run("run()")
      local env = K.cc:get_project_env()
      local held = setmetatable({ env.BIG, env,
        env.compy.input.callbacks.on_text_entered }, { __mode = "v" })
      env = nil
      assert.is_not_nil(held[1])
      K.keys("lctrl", "q")
      assert.is_false(K.cc.run_live)
      collectgarbage("collect")
      collectgarbage("collect")
      assert.is_nil(held[1])
      assert.is_nil(held[2])
    end)
end)
