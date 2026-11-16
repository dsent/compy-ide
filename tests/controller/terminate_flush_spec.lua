-- Terminating a program returns the IDE to its own baseline
-- through one flush (Beads compy-ide-terminate-flush; the
-- maintainer's invariant of 2026-06-12, confirmed 2026-11-16:
-- "a stop clears the globals too"): stop(), Ctrl+Q, a project's
-- close, an error in a program's first lines and the run seam's
-- stop all call it. A program's natural end and a pause flush
-- nothing. Keys only, through the K helper.

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

local RUNS = "g = 1\nfunction love.update() end\n"

--- `love.audio.stop` and the keyboard's two settings, counted
--- and recorded, for the test's length
local function devices()
  local seen = { stops = 0 }
  local audio = love.audio
  love.audio = setmetatable({
    stop = function() seen.stops = seen.stops + 1 end,
  }, { __index = audio })
  -- the IDE's keyboard, and the copy a run's environment is
  -- made from
  local saved = { }
  for _, kb in ipairs({ love.keyboard,
    K.cc:get_base_env().love.keyboard }) do
    saved[#saved + 1] = { kb, kb.setKeyRepeat, kb.setTextInput }
    kb.setKeyRepeat = function(on) seen.key_repeat = on end
    kb.setTextInput = function(on) seen.text_input = on end
  end
  finally(function()
    love.audio = audio
    for i = #saved, 1, -1 do
      local s = saved[i]
      s[1].setKeyRepeat, s[1].setTextInput = s[2], s[3]
    end
  end)
  return seen
end

describe("the terminate flush #console", function()
  after_each(cleanup)

  for _, case in ipairs({
    { "Ctrl+Q", function() K.keys("lctrl", "q") end },
    { "stop()", function() run("stop()") end },
  }) do
    it("clears the program's globals at " .. case[1], function()
      reset({ ["main.lua"] = RUNS })
      run("run()")
      assert.equal(1, env().g)
      case[2]()
      assert.is_false(K.cc.run_live)
      assert.is_nil(env().g)
      assert.is_nil(env().love.update)
    end)
  end

  it("clears the globals of first lines that raise", function()
    reset({ ["main.lua"] = "g = 1\nerror('top')\n" })
    run("run()")
    assert.is_nil(env().g)
  end)

  it("keeps the globals at a program's natural end", function()
    reset({ ["main.lua"] = "g = 1\n" })
    run("run()")
    run("print('read ' .. tostring(g))")
    assert.truthy(K.console_text():find("read 1", 1, true))
    assert.equal(1, env().g)
  end)

  it("keeps everything through a pause and continue()", function()
    reset({ ["main.lua"] = "g = 1\n"
      .. "local n = 0\n"
      .. "function love.update()\n"
      .. "  n = n + 1\n"
      .. "  if n == 1 then pause() end\n"
      .. "end\n" })
    local seen = devices()
    run("run()")
    K.frame()
    K.cc:suspend()
    assert.same("inspect", K.app_state())
    local before = env()
    run("continue()")
    assert.same("running", K.app_state())
    assert.equal(before, env())
    assert.equal(1, env().g)
    assert.is_not_nil(env().love.update)
    assert.equal(0, seen.stops)
    K.keys("lctrl", "q")
  end)

  it("stops the sound a program started at Ctrl+Q", function()
    reset({ ["main.lua"] = RUNS })
    local seen = devices()
    run("run()")
    K.keys("lctrl", "q")
    assert.is_true(seen.stops >= 1)
  end)

  it("puts key repeat and text input back at Ctrl+Q", function()
    reset({ ["main.lua"] = "love.keyboard.setKeyRepeat(false)\n"
      .. "love.keyboard.setTextInput(false)\n"
      .. "function love.update() end\n" })
    local seen = devices()
    run("run()")
    assert.is_false(seen.key_repeat)
    assert.is_false(seen.text_input)
    K.keys("lctrl", "q")
    assert.is_true(seen.key_repeat)
    assert.is_true(seen.text_input)
  end)

  it("collects garbage twice when a run ends, not otherwise",
    function()
      reset({ ["main.lua"] = RUNS })
      local n = 0
      local was = K.cc.collect_garbage
      K.cc.collect_garbage = function(what)
        if what == 'collect' then n = n + 1 end
      end
      finally(function() K.cc.collect_garbage = was end)
      run("stop()")
      assert.equal(0, n)
      run("run()")
      K.keys("lctrl", "q")
      assert.equal(2, n)
    end)

  --- reset(): the flush, live or not, then the console
  --- emptied as Ctrl+L empties it (Beads
  --- compy-ide-reset-runtime-reset: only reset() exists yet)
  describe("reset()", function()
    it("stops a live program, clears its globals and the console",
      function()
        reset({ ["main.lua"] = "print('from the run')\n" .. RUNS })
        local seen = devices()
        run("run()")
        run("reset()")
        assert.is_false(K.cc.run_live)
        assert.is_nil(env().g)
        assert.is_true(seen.stops >= 1)
        local text = K.console_text()
        assert.is_nil(text:find("from the run", 1, true), text)
        assert.same({ }, (function()
          local k, out = K.cc.model.output.kept, { }
          for i = k.first, k.last do out[#out + 1] = i end
          return out
        end)())
        assert.truthy(text:find("Reset.", 1, true), text)
      end)

    it("clears what typed lines left with nothing live", function()
      reset()
      run("t = 5")
      run("compy.before_exit = function() print('TYPED_EXIT') end")
      run("reset()")
      assert.is_nil(env().t)
      local text = K.console_text()
      assert.is_nil(text:find("TYPED_EXIT", 1, true), text)
      assert.truthy(text:find("Reset.", 1, true), text)
      K.keys("up")
      assert.same("reset()", K.console_draft())
    end)

    it("refuses an argument in one sentence", function()
      reset()
      run("t = 5")
      run("reset('globals')")
      assert.equal(5, env().t)
      assert.truthy(K.console_text():find(
        "Only reset() exists yet, with nothing between the brackets.",
        1, true), K.console_text())
    end)
  end)

  it("keeps the console's output and history", function()
    reset({ ["main.lua"] = "print('from the run')\n"
      .. "function love.update() end\n" })
    run("run()")
    K.keys("lctrl", "q")
    assert.truthy(K.console_text():find("from the run", 1, true))
    K.keys("up")
    assert.same("run()", K.console_draft())
  end)
end)
