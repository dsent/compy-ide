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

--- Code run behind a live program, which owns the input, so no
--- line can be typed there (November 17): run as the IDE's own
--- call in the program's environment
local function behind(code)
  local f = assert(loadstring(code))
  setfenv(f, K.cc:get_project_env())
  local r = f()
  K.frame(100)
  return r
end

local RUNS = "g = 1\nfunction love.update() end\n"

--- A source as LÖVE 11 keeps one, in memory: it plays, loops,
--- pauses and stops; `finish()` is its end coming, which a
--- looping one meets by starting again
local function source(sources, looping)
  local s = { looping = looping, playing = false, plays = 0 }
  function s:setLooping(on) self.looping = on end
  function s:isLooping() return self.looping end
  function s:isPlaying() return self.playing end
  function s:play()
    self.playing, self.plays = true, self.plays + 1
    return true
  end
  function s:pause() self.playing = false end
  function s:stop() self.playing = false end
  function s:finish() self.playing = self.looping end
  sources[#sources + 1] = s
  return s
end

--- `love.audio` with its sources in memory (`newSource` makes
--- one, `pause` and `stop` act on all, as on LÖVE 11.5), and the
--- keyboard's two settings recorded, for the test's length
local function devices()
  local seen = { stops = 0, sources = { }, volume = 1 }
  local fake = {
    newSource = function() return source(seen.sources, false) end,
    setVolume = function(v) seen.volume = v end,
    getVolume = function() return seen.volume end,
    pause = function()
      local paused = { }
      for _, s in ipairs(seen.sources) do
        if s.playing then
          s:pause()
          paused[#paused + 1] = s
        end
      end
      return paused
    end,
    stop = function()
      seen.stops = seen.stops + 1
      for _, s in ipairs(seen.sources) do s:stop() end
    end,
  }
  -- the IDE's audio, and the copy a run's environment is made
  -- from, each given the fake's functions
  local swapped = { }
  for _, audio in ipairs({ love.audio,
    K.cc:get_base_env().love.audio }) do
    for name, f in pairs(fake) do
      swapped[#swapped + 1] = { audio, name, audio[name] }
      audio[name] = f
    end
  end
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
    for i = #swapped, 1, -1 do
      local s = swapped[i]
      s[1][s[2]] = s[3]
    end
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
    { "stop()", function() behind("stop()") end },
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

  --- the maintainer's ruling of November 16, 2026: "clear the
  --- repeat, but what is there, still there"
  local SOUNDS = "loop = love.audio.newSource('a.ogg', 'static')\n"
    .. "loop:setLooping(true)\n"
    .. "loop:play()\n"
    .. "shot = love.audio.newSource('b.ogg', 'static')\n"
    .. "held = love.audio.newSource('c.ogg', 'static')\n"
    .. "held:play()\n"
    .. "held:pause()\n"
    .. "function love.update() end\n"

  it("lets a loop play to its end once at Ctrl+Q, and not again",
    function()
      reset({ ["main.lua"] = SOUNDS })
      local seen = devices()
      run("run()")
      local loop = seen.sources[1]
      assert.is_true(loop:isPlaying())
      K.keys("lctrl", "q")
      assert.equal(0, seen.stops)
      assert.is_true(loop:isPlaying())
      assert.is_false(loop:isLooping())
      loop:finish()
      assert.is_false(loop:isPlaying())
    end)

  it("leaves a one-shot playing at stop(), a paused one paused",
    function()
      reset({ ["main.lua"] = SOUNDS })
      local seen = devices()
      run("run()")
      local held = seen.sources[3]
      local held_plays = held.plays
      behind("shot:play()")
      behind("stop()")
      local shot = seen.sources[2]
      assert.is_true(shot:isPlaying())
      assert.is_false(held:isPlaying())
      assert.equal(held_plays, held.plays)
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
        behind("reset()")
        assert.is_false(K.cc.run_live)
        assert.is_nil(env().g)
        assert.is_true(seen.stops >= 1)
      end)

    it("silences a loop and a one-shot", function()
      reset({ ["main.lua"] = SOUNDS })
      local seen = devices()
      run("run()")
      behind("shot:play()")
      behind("reset()")
      for _, s in ipairs(seen.sources) do
        assert.is_false(s:isPlaying())
      end
    end)

    it("empties the console", function()
        reset({ ["main.lua"] = "print('from the run')\n" .. RUNS })
        run("run()")
        behind("reset()")
        local text = K.console_text()
        assert.is_nil(text:find("from the run", 1, true), text)
        assert.same({ }, (function()
          local k, out = K.cc.model.output.kept, { }
          for i = k.first, k.last do out[#out + 1] = i end
          return out
        end)())
        --- the reset specification's IS4.1 words, the one line on
        --- the erased console
        local said = "Runtime reset for " .. K.PROJECT
          .. ". All files kept."
        assert.truthy(text:find(said, 1, true), text)
        local rows = { }
        for row in text:gmatch("[^\n]+") do
          if row:find("%S") then rows[#rows + 1] = row end
        end
        assert.same(1, #rows, text)
      end)

    --- design B: the call ends the line, so API4.1's table
    --- reaches no caller in code; the IDE's own call has it
    it("does not return to code; the IDE's own call has API4.1's"
      .. " table", function()
        reset()
        local kept = false
        env().keep = function() kept = true end
        run("keep(reset())")
        assert.is_false(kept)
        local r = K.cc:get_project_env().reset()
        assert.same({ scope = "runtime", project = K.PROJECT }, r)
        assert.is_nil(r.snapshot)
        local text = K.console_text()
        assert.is_nil(text:find("table:", 1, true), text)
      end)

    it("clears what typed lines left with nothing live", function()
      reset()
      run("t = 5")
      run("compy.before_exit = function() print('TYPED_EXIT') end")
      run("reset()")
      assert.is_nil(env().t)
      local text = K.console_text()
      assert.is_nil(text:find("TYPED_EXIT", 1, true), text)
      assert.truthy(text:find("Runtime reset for ", 1, true), text)
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

  --- the flush ends a run's state once, whichever paths reach
  --- it: the flushes that found state to end, counted
  local function count_flushes()
    local n, flush = { 0 }, K.cc.flush_program_state
    K.cc.flush_program_state = function(...)
      local flushed = flush(...)
      if flushed then n[1] = n[1] + 1 end
      return flushed
    end
    finally(function() K.cc.flush_program_state = nil end)
    return n
  end

  it("flushes once when play mode quits", function()
    reset({ ["main.lua"] = RUNS })
    run("run()")
    local n = count_flushes()
    -- the default project the close opens is the card's: not
    -- opened here
    K.cc.open_project = function() return true end
    finally(function() K.cc.open_project = nil end)
    K.cc:quit_project()
    assert.equal(1, n[1])
  end)

  for _, call in ipairs({ "stop()", "reset()" }) do
    it("flushes once when first lines call " .. call
      .. " and then raise", function()
        reset({ ["main.lua"] = "function love.update() end\n"
          .. call .. "\nerror('after')\n" })
        local n = count_flushes()
        run("run()")
        assert.equal(1, n[1])
      end)
  end

  it("clears what a typed line left after a stop, at a switch",
    function()
      reset({ ["main.lua"] = RUNS })
      run("run()")
      K.keys("lctrl", "q")
      run("t = 5")
      K.next_project("other", { ["main.lua"] = "\n" })
      run("project('other')")
      assert.is_nil(env().t)
    end)

  it("puts the master volume back at a stop and at reset()",
    function()
      reset({ ["main.lua"] = "love.audio.setVolume(0)\n" .. RUNS })
      local seen = devices()
      run("run()")
      assert.equal(0, seen.volume)
      K.keys("lctrl", "q")
      assert.equal(1, seen.volume)
      run("love.audio.setVolume(0.25)")
      run("reset()")
      assert.equal(1, seen.volume)
    end)

  --- where the key gate meets the stop: a program sees a release
  --- exactly for the presses it saw, so a run that a stop ended
  --- or Ctrl+R replaced gets nothing more, and the next run gets
  --- no release of a key it never saw pressed
  local KEYS = "presses, releases = { }, { }\n"
    .. "function love.keypressed(k) presses[#presses + 1] = k end\n"
    .. "function love.keyreleased(k) releases[#releases + 1] = k end\n"
    .. "function love.update() end\n"

  it("gives a run Ctrl+R started no release of a key held across it",
    function()
      reset({ ["main.lua"] = KEYS })
      run("run()")
      local first = env()
      K.hold("a")
      assert.same({ "a" }, first.presses)
      K.keys("lctrl", "r")
      K.frame()
      local second = env()
      assert.is_not.equal(first, second)
      K.release("a")
      assert.same({ }, second.releases)
      assert.same({ }, second.presses)
      assert.same({ }, first.releases)
      K.keys("lctrl", "q")
    end)

  it("gives no release after reset() of a key the paused run saw",
    function()
      reset({ ["main.lua"] = KEYS })
      run("run()")
      local first = env()
      K.hold("x")
      assert.same({ "x" }, first.presses)
      K.cc:suspend_run()
      K.cc:suspend()
      assert.same("inspect", K.app_state())
      run("reset()")
      K.release("x")
      assert.is_false(K.cc.run_live)
      assert.same({ }, first.releases)
      run("run()")
      assert.same({ }, env().releases)
      K.keys("lctrl", "q")
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
