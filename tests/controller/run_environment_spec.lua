-- Every run starts from a clean project environment (the
-- maintainer's ruling of November 16, 2026, Beads
-- compy-ide-run-keeps-earlier-runs-love-handlers): no global and
-- no love handler of an earlier run, or of a line typed before
-- it, reaches the run. What a run leaves stays for inspection
-- until the next run; continue() after a pause and dofile() run
-- in the environment as it stands. Keys only, through the K
-- helper and the console's real paths.

local K = require("tests.helpers.editor_keys")

local unrouted

--- A console whose lines and programs print to its output, as
--- the IDE redirects print before it builds them
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

local function said(text)
  return K.console_text():find(text, 1, true) ~= nil
end

describe("a run's environment #console", function()
  after_each(cleanup)

  it("has no love handler a run before it set and main.lua no "
    .. "longer does", function()
      reset({ ["main.lua"] =
        "function love.keypressed(k) hits = (hits or 0) + 1 end\n"
        .. "function love.update() end\n" })
      run("run()")
      K.keys("lctrl", "q")
      K.frame()
      K.write_outside("main.lua",
        "function love.keyreleased() end\nfunction love.update() end\n")
      run("run()")
      assert.same("running", K.app_state())
      assert.is_nil(env().love.keypressed)
      K.keys("x")
      assert.is_nil(env().hits)
      env().love.update = nil
    end)

  it("has no global a run before it set, which stays readable "
    .. "after that run", function()
      reset({ ["main.lua"] = "g = 41 + 1\n" })
      run("run()")
      run("print('after ' .. tostring(g))")
      assert.is_true(said("after 42"))
      K.write_outside("main.lua", "print('in the run ' .. tostring(g))\n")
      run("run()")
      assert.is_true(said("in the run nil"))
    end)

  it("has no global typed in the console before it", function()
    reset({ ["main.lua"] = "print('typed ' .. tostring(t))\n" })
    run("t = 5")
    run("run()")
    assert.is_true(said("typed nil"))
  end)

  it("is kept by continue() after a pause, globals and handlers",
    function()
      reset({ ["main.lua"] = "kept = 1\n"
        .. "local n = 0\n"
        .. "function love.update()\n"
        .. "  n = n + 1\n"
        .. "  if n == 1 then pause('here') end\n"
        .. "end\n" })
      run("run()")
      K.frame()
      K.cc:suspend()
      assert.same("inspect", K.app_state())
      local before = env()
      run("typed = 2")
      run("continue()")
      assert.same("running", K.app_state())
      assert.equal(before, env())
      assert.same(1, env().kept)
      assert.same(2, env().typed)
      assert.is_not_nil(env().love.update)
      env().love.update = nil
    end)

  --- a project's own module is loaded afresh by each run, a
  --- run left idle behind the console included (the
  --- multi-entry-point proposal's ME-FR3)
  it("loads the project's own modules afresh", function()
    reset({ ["main.lua"] = "local m = require('mod')\n"
      .. "m.count = m.count + 1\n"
      .. "print('count ' .. m.count)\n"
      -- the finished run stays live behind the console with
      -- its picture, and, able to do nothing more, leaves the
      -- input to it
      .. "",
      ["mod.lua"] = "return { count = 0 }\n" })
    -- the memory project's loader, as opening a project puts
    -- its own in front of package.loaders
    local loader = Project.get_loader(K.cc.model.projects.current,
      function() return K.cc:get_effective_env() end)
    table.insert(package.loaders, 1, loader)
    finally(function()
      table.delete_by_value(package.loaders, loader)
      package.loaded.mod = nil
    end)
    run("run()")
    assert.is_true(said("count 1"))
    assert.is_true(K.cc.run_live)
    run("run()")
    assert.is_false(said("count 2"), K.console_text())
    assert.is_true(select(2, K.console_text():gsub("count 1", "")) == 2,
      K.console_text())
  end)

  it("is the one dofile() runs in", function()
    reset({ ["main.lua"] = "x = 1\n",
      ["lib.lua"] = "print('lib sees ' .. tostring(d)) e = 5\n" })
    run("d = 4")
    local before = env()
    run("dofile('lib.lua')")
    assert.is_true(said("lib sees 4"))
    assert.equal(before, env())
    assert.same(5, env().e)
    assert.same(4, env().d)
  end)
end)
