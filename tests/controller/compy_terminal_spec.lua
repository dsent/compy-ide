-- What a program can call on compy.terminal (also tty): gotoxy,
-- clear and setEcho. show_cursor and hide_cursor are gone (the
-- maintainer's ruling "Programs lose show_cursor and
-- hide_cursor"): a call is the program's own error, and the
-- IDE goes on. Keys only, through the K helper.

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

--- the screen's rows, spaces at their ends left out
local function screen()
  local out = { }
  for y, row in ipairs(K.cc.model.output.terminal.buffer) do
    out[y] = (table.concat(row):gsub("%s+$", ""))
  end
  return out
end

describe("compy.terminal #console", function()
  after_each(cleanup)

  for _, name in ipairs({ "show_cursor", "hide_cursor" }) do
    it("has no " .. name .. ": a program that calls it fails "
      .. "in its own call, and the IDE goes on", function()
        reset({ ["main.lua"] = "compy.terminal." .. name .. "()\n" })
        assert.is_nil(K.cc:get_project_env().compy.terminal[name])
        run("run()")
        assert.same("ready", K.app_state())
        assert.truthy(K.console_text():find(name, 1, true))
        run("print('still here')")
        local s = table.concat(screen(), "\n")
        assert.truthy(s:find("still here", 1, true))
      end)

    it("has no " .. name .. " on tty either", function()
      reset()
      assert.is_nil(K.cc:get_project_env().tty[name])
    end)
  end

  it("still moves the cursor with gotoxy", function()
    reset({ ["main.lua"] =
      "compy.terminal.gotoxy(3, 5) io.write('x')\n" })
    -- io.write's path (model.io.redirect), as the IDE has it
    local base = K.cc:get_base_env()
    local io_was = base.io
    finally(function()
      base.io = io_was
      K.cc:get_project_env().io = io_was
    end)
    -- in the environment each run starts from
    base.io = { write = function(s)
      K.cc.model.output:write(s)
    end }
    run("run()")
    assert.equal("x", K.cc.model.output.terminal.buffer[5][3])
  end)

  --- gotoxy with what is not a number fails in the program's
  --- own call, on its own line, in the words of the other
  --- argument errors (Compy check C5)
  for _, args in ipairs({ "'x', 'y'", "", "1", "{ }, 2", "1, nil" }) do
    it("refuses gotoxy(" .. args .. ") on the program's line",
      function()
        reset({ ["main.lua"] = "local a = 1\nlocal b = 2\n"
          .. "compy.terminal.gotoxy(" .. args .. ")\n" })
        run("run()")
        assert.same("ready", K.app_state())
        local text = K.console_text()
        assert.truthy(text:find(
          "L3:compy.terminal.gotoxy: x and y must be numbers", 1, true),
          text)
        assert.falsy(text:find("floor", 1, true))
      end)
  end

  it("takes gotoxy's numbers written as text, as it did",
    function()
      reset({ ["main.lua"] =
        "compy.terminal.gotoxy('3', '5') io.write('x')\n" })
      local base = K.cc:get_base_env()
      local io_was = base.io
      finally(function()
        base.io = io_was
        K.cc:get_project_env().io = io_was
      end)
      -- in the environment each run starts from
      base.io = { write = function(s)
        K.cc.model.output:write(s)
      end }
      run("run()")
      assert.equal("x", K.cc.model.output.terminal.buffer[5][3])
    end)

  it("still clears the screen", function()
    reset({ ["main.lua"] =
      "print('gone') compy.terminal.clear()\n" })
    run("run()")
    for _, r in ipairs(screen()) do assert.equal("", r) end
  end)

  describe("setEcho", function()
    local function has(text)
      return K.console_text():find(text, 1, true) ~= nil
    end

    local function row_color(text)
      local t = K.cc.model.output.terminal
      for y, r in ipairs(t.buffer) do
        local s = table.concat(r):gsub("%s+$", "")
        if s == text then return t.state_buffer[y][1].color end
      end
    end

    it("echoes the calling line in blue and suppresses the next",
      function()
        reset()
        run("x = 42")
        run("tty.setEcho(false)")
        run("print(x)")
        run("print('second')")
        local echo_c = K.cc.cfg.view.colors.terminal.echo
        assert.same(echo_c, row_color("tty.setEcho(false)"))
        assert.is_false(has("print(x)"), K.console_text())
        assert.is_true(has("42"), K.console_text())
        assert.is_false(has("print('second')"), K.console_text())
        assert.is_true(has("second"), K.console_text())
      end)

    it("keeps every accepted line in history", function()
      reset()
      run("x = 7")
      run("tty.setEcho(false)")
      run("print(x)")
      run("tty.setEcho(true)")
      K.keys("up")
      assert.same("tty.setEcho(true)", K.console_draft())
      K.keys("up")
      assert.same("print(x)", K.console_draft())
      K.keys("up")
      assert.same("tty.setEcho(false)", K.console_draft())
    end)

    it("turns echo back on silently and echoes the line after",
      function()
        reset()
        run("tty.setEcho(false)")
        run("tty.setEcho(true)")
        run("print('back')")
        assert.is_false(has("tty.setEcho(true)"), K.console_text())
        assert.is_true(has("print('back')"), K.console_text())
        assert.is_true(has("back"), K.console_text())
      end)

    it("still shows printed output, refusals and errors when off",
      function()
        reset()
        run("tty.setEcho(false)")
        run("print('visible')")
        run("stop()")
        run("error('boom')")
        assert.is_false(has("print('visible')"), K.console_text())
        assert.is_true(has("visible"), K.console_text())
        assert.is_false(has("stop()"), K.console_text())
        assert.is_true(has("Nothing is running."), K.console_text())
        assert.is_false(has("error('boom')"), K.console_text())
        assert.is_true(has("L1:boom"), K.console_text())
      end)

    it("returns no values and is shared by tty and compy.terminal",
      function()
        reset()
        local env = K.cc:get_project_env()
        assert.equal(env.compy.terminal.setEcho, env.tty.setEcho)
        assert.equal(0, select("#", env.compy.terminal.setEcho(false)))
        assert.equal(0, select("#", env.tty.setEcho(true)))
      end)

    it("keeps a program's setting at pause() and across continue()",
      function()
        reset({ ["main.lua"] = [[
compy.terminal.setEcho(false)
local n = 0
function love.update()
  n = n + 1
  if n == 1 or n == 3 then pause('at ' .. n) end
end
]] })
        run("run()")
        K.cc:suspend()
        assert.same("inspect", K.app_state())
        run("print('quiet')")
        assert.is_false(has("print('quiet')"), K.console_text())
        assert.is_true(has("quiet"), K.console_text())
        -- turn echo back on at pause; change lasts through continue
        run("tty.setEcho(true)")
        assert.is_false(has("tty.setEcho(true)"), K.console_text())
        run("continue()")
        assert.is_true(has("continue()"), K.console_text())
        K.frame()
        K.frame()
        K.cc:suspend()
        assert.same("inspect", K.app_state())
        run("print('loud')")
        assert.is_true(has("print('loud')"), K.console_text())
        assert.is_true(has("loud"), K.console_text())
        K.keys("lctrl", "q")
      end)

    it("keeps a pause change to off across continue()", function()
      reset({ ["main.lua"] = [[
local n = 0
function love.update()
  n = n + 1
  if n == 1 or n == 3 then pause('at ' .. n) end
end
]] })
      run("run()")
      K.cc:suspend()
      assert.same("inspect", K.app_state())
      run("tty.setEcho(false)")
      assert.is_true(has("tty.setEcho(false)"), K.console_text())
      run("continue()")
      assert.is_false(has("continue()"), K.console_text())
      K.frame()
      K.frame()
      K.cc:suspend()
      assert.same("inspect", K.app_state())
      run("print('still-quiet')")
      assert.is_false(has("print('still-quiet')"), K.console_text())
      assert.is_true(has("still-quiet"), K.console_text())
      K.keys("lctrl", "q")
    end)

    it("restores echo on at stop (Ctrl+Q)", function()
      reset({ ["main.lua"] = [[
compy.terminal.setEcho(false)
function love.update() end
]] })
      run("run()")
      K.keys("lctrl", "q")
      K.frame(100)
      assert.same("ready", K.app_state())
      run("print('after-stop')")
      assert.is_true(has("print('after-stop')"), K.console_text())
    end)

    it("restores echo on at a program's natural end", function()
      reset({ ["main.lua"] = "compy.terminal.setEcho(false)\n" })
      run("run()")
      assert.is_false(K.cc.run_live)
      assert.same("ready", K.app_state())
      run("print('after-end')")
      assert.is_true(has("print('after-end')"), K.console_text())
    end)

    it("restores echo on at reset()", function()
      reset()
      run("tty.setEcho(false)")
      run("reset()")
      assert.is_false(has("reset()"), K.console_text())
      run("print('after-reset')")
      assert.is_true(has("print('after-reset')"), K.console_text())
    end)

    it("restores echo on at restart (Ctrl+R)", function()
      reset({ ["main.lua"] = [[
local n = 0
function love.update()
  n = n + 1
  if n == 1 then pause() end
end
]] })
      run("run()")
      K.cc:suspend()
      assert.same("inspect", K.app_state())
      run("tty.setEcho(false)")
      K.keys("lctrl", "r")
      K.frame()
      K.cc:suspend()
      assert.same("inspect", K.app_state())
      run("print('after-restart')")
      assert.is_true(has("print('after-restart')"), K.console_text())
      K.keys("lctrl", "q")
    end)

    it("restores echo on when a new run starts from idle", function()
      reset({ ["main.lua"] = "pause()\n" })
      run("tty.setEcho(false)")
      -- a refused run leaves echo off
      run("run('no_such_project')")
      assert.is_false(has("run('no_such_project')"), K.console_text())
      run("print('still-off')")
      assert.is_false(has("print('still-off')"), K.console_text())
      -- an accepted run restores echo on
      run("run()")
      K.cc:suspend()
      assert.same("inspect", K.app_state())
      run("print('fresh-run')")
      assert.is_true(has("print('fresh-run')"), K.console_text())
      K.keys("lctrl", "q")
    end)

    for _, args in ipairs({
      "",
      "nil",
      "1",
      "'false'",
      "{ }",
      "true, false",
      "true, nil",
    }) do
      it("refuses setEcho(" .. args .. ") on the calling line and "
        .. "changes nothing", function()
        reset({ ["main.lua"] = "local a = 1\nlocal b = 2\n"
          .. "compy.terminal.setEcho(" .. args .. ")\n" })
        run("run()")
        assert.same("ready", K.app_state())
        local text = K.console_text()
        assert.truthy(text:find(
          "L3:compy.terminal.setEcho: expects one boolean", 1, true),
          text)
        -- echo is still on after a bad call caught in the console
        -- (no flush ran)
        run("ok_bad = pcall(function() tty.setEcho("
          .. args .. ") end)")
        assert.is_false(K.cc:get_project_env().ok_bad)
        run("print('still-on')")
        assert.is_true(has("print('still-on')"), K.console_text())
        -- echo stays off after a bad call while off
        run("tty.setEcho(false)")
        K.cc.model.output:erase()
        run("compy.terminal.setEcho(" .. args .. ")")
        assert.is_true(has("compy.terminal.setEcho: expects one boolean"),
          K.console_text())
        run("print('still-off')")
        assert.is_false(has("print('still-off')"), K.console_text())
        assert.is_true(has("still-off"), K.console_text())
      end)
    end
  end)
end)
