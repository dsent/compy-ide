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

  --- a run that ends by itself leaves nothing: its natural end
  --- is a stop (stage 4 of the canvas plan); dofile() keeps what
  --- a file defines
  it("has no global a run before it set, and a run that ended "
    .. "leaves none", function()
      reset({ ["main.lua"] = "g = 41 + 1\n" })
      run("run()")
      run("print('after ' .. tostring(g))")
      assert.is_true(said("after nil"))
      run("dofile('main.lua')")
      run("print('dofile ' .. tostring(g))")
      assert.is_true(said("dofile 42"))
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
      -- able to do nothing more, the run ends at its last line
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

  describe("string code (loadstring, load, eval, print_eval)", function()
    local function error_row(fragment)
      local t = K.cc.model.output.terminal
      local err_c = K.cc.cfg.view.colors.terminal.error
      for y, r in ipairs(t.buffer) do
        local s = table.concat(r):gsub("%s+$", "")
        if s:find(fragment, 1, true) then
          local c = t.state_buffer[y][1].color
          return s, c and c[1] == err_c[1] and c[2] == err_c[2]
              and c[3] == err_c[3]
        end
      end
    end

    it("lets a program's loadstring and load see and set its globals",
      function()
        reset({ ["main.lua"] = table.concat({
          "a = 10",
          "assert(loadstring('b = a + 5'))()",
          "assert(load('c = b * 2'))()",
          "local sent = false",
          "assert(load(function()",
          "  if sent then return nil end",
          "  sent = true",
          "  return 'd = c + 1'",
          "end))()",
          -- tixy pattern: setfenv(f, _G) keeps working
          "local tf = assert(loadstring('return a'))",
          "setfenv(tf, _G)",
          "local cf = assert(loadstring('return a'))",
          "setfenv(cf, { a = 99 })",
          "local a4 = assert(load('return a', 'c', 't', { a = 77 }))",
          "local bad, berr = loadstring('10 / ')",
          "assert(bad == nil and type(berr) == 'string')",
          "local lbad, lerr = load('10 / ')",
          "assert(lbad == nil and type(lerr) == 'string')",
          "print(string.format('vals %d %d %d %d %d %d',",
          "  b, c, d, tf(), cf(), a4()))",
        }, "\n") .. "\n" })
        run("run()")
        assert.is_true(said("vals 15 30 31 10 99 77"), K.console_text())
        assert.is_nil(_G.b)
        assert.is_nil(_G.c)
        assert.is_nil(_G.d)
      end)

    it("runs console eval, print_eval, loadstring and load in the "
      .. "program env", function()
        reset({ ["main.lua"] = "print('fresh ' .. tostring(eval('x')))\n" })
        run("x = 5")
        run("print('ev ' .. eval('x'))")
        assert.is_true(said("ev 5"), K.console_text())
        run("print_eval('x * 3')")
        assert.is_true(said("\n15\n") or said("\n15"), K.console_text())
        run("assert(loadstring('y = x + 2'))()")
        assert.same(7, env().y)
        assert.is_nil(_G.y)
        run("local s = 'z = y + 1'; assert(load(function() "
          .. "local t = s; s = nil; return t end))()")
        assert.same(8, env().z)
        assert.is_nil(_G.z)
        -- a fresh run resets the env; eval follows the new env
        run("run()")
        assert.is_true(said("fresh nil"), K.console_text())
      end)

    it("shares the paused program's env during inspect", function()
      reset({ ["main.lua"] = "p = 41\n"
        .. "local n = 0\n"
        .. "function love.update()\n"
        .. "  n = n + 1\n"
        .. "  if n == 1 then pause('here') end\n"
        .. "end\n" })
      run("run()")
      K.frame()
      K.cc:suspend()
      assert.same("inspect", K.app_state())
      run("print('paused ' .. eval('p'))")
      assert.is_true(said("paused 41"), K.console_text())
      run("assert(loadstring('p = p + 1'))()")
      run("continue()")
      assert.same(42, env().p)
      env().love.update = nil
    end)

    it("reports syntax and runtime errors from eval and print_eval",
      function()
        reset({ ["main.lua"] = "eval('10 / ')\n" })
        run("eval('10 / ')")
        local s1, red1 = error_row("unexpected symbol")
        assert.is_not_nil(s1, K.console_text())
        assert.is_true(red1)

        K.keys("lctrl", "l")
        run("eval('nil + 1')")
        local s2, red2 = error_row("attempt to perform arithmetic")
        assert.is_not_nil(s2, K.console_text())
        assert.is_true(red2)

        K.keys("lctrl", "l")
        run("print_eval('10 / ')")
        local s3, red3 = error_row("unexpected symbol")
        assert.is_not_nil(s3, K.console_text())
        assert.is_true(red3)

        K.keys("lctrl", "l")
        run("eval()")
        local s4, red4 = error_row("eval expects a string, got nil")
        assert.is_not_nil(s4, K.console_text())
        assert.is_true(red4)

        K.keys("lctrl", "l")
        run("local ok, e = pcall(eval, '10 / '); print('caught ' .. tostring(ok))")
        assert.is_true(said("caught false"), K.console_text())

        K.keys("lctrl", "l")
        run("run()")
        local s5, red5 = error_row("Error: L1:")
        assert.is_not_nil(s5, K.console_text())
        assert.is_true(red5)
      end)

    it("lets a lifecycle call inside eval unwind cleanly", function()
      reset({ ["main.lua"] = "function love.update() end\n"
        .. "eval('stop()')\n"
        .. "print('after-stop')\n" })
      run("run()")
      assert.same("ready", K.app_state())
      assert.is_false(said("after-stop"), K.console_text())
      local s = error_row("Error:")
      assert.is_nil(s, K.console_text())
    end)

    it("keeps a table given as the fourth argument, gives eval's "
      .. "first value, and names eval in an error", function()
        reset()
        local e = env()
        e.x = 5
        assert.same(7, e.loadstring('return x', nil, 't', { x = 7 })())
        assert.same(7, e.load('return x', nil, 't', { x = 7 })())
        assert.same(5, e.load('return x', nil, 't', false)())
        assert.same(1, select('#', e.eval("string.find('apple', 'p')")))
        local ok, err = pcall(e.eval, "'12:34:56' +")
        assert.is_false(ok)
        assert.matches('^eval:1:', err)
      end)

    it("leaves the IDE's own loadstring, load, codeload and eval "
      .. "unchanged", function()
        reset()
        local prev = _G.__ide_env_probe
        _G.__ide_env_probe = "ide"
        env().__ide_env_probe = "program"
        finally(function()
          _G.__ide_env_probe = prev
        end)

        -- fails if the IDE's _G.loadstring or _G.load were replaced
        assert.not_equal(_G.loadstring, env().loadstring)
        assert.not_equal(_G.load, env().load)
        assert.same("ide",
          assert(_G.loadstring("return __ide_env_probe"))())
        assert.same("program",
          assert(env().loadstring("return __ide_env_probe"))())

        local function reader_of(src)
          local done = false
          return function()
            if done then return nil end
            done = true
            return src
          end
        end
        assert.same("ide",
          assert(_G.load(reader_of("return __ide_env_probe")))())
        assert.same("program",
          assert(env().load(reader_of("return __ide_env_probe")))())

        -- src/util/lua.lua: codeload
        assert.same("ide",
          assert(codeload("return __ide_env_probe"))())
        assert.same("program",
          assert(codeload("return __ide_env_probe", env()))())

        -- src/util/eval.lua: LANG.eval stays in _G and keeps its contract
        local LANG = require("util.eval")
        assert.same("ide", LANG.eval("__ide_env_probe"))
        assert.is_nil(LANG.eval("10 / "))
        assert.same("program", env().eval("__ide_env_probe"))

        -- src/model/syntax/lua.lua: loads()
        local lua_syntax = require("model.syntax.lua")
        assert.is_true(lua_syntax.loads({ "return __ide_env_probe" }))
        assert.is_false(lua_syntax.loads({ "10 / " }))

        -- src/model/interpreter/eval/evaluator.lua: LuaEval
        local ok = LuaEval():apply({ "x = 1" })
        assert.is_true(ok)
      end)
  end)
end)
