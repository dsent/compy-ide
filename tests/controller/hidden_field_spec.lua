-- Behind a live program that takes keys and draws nothing, the
-- console's field and its cursor are hidden, and the status
-- line and the output stay (the maintainer, on the field shown
-- and dead there: "that is also weird. Should we maybe hide the
-- console in that case?"; option B, the ruling of November 17,
-- 2026). The field comes back by itself at a pause, a stop, or
-- when the program takes keys no more. Drawn through the real
-- draw functions, recorded by the K helper.

local K = require("tests.helpers.editor_keys")

local function run(line)
  K.type(line)
  K.keys("return")
  K.frame(100)
end

local function fh()
  return require("tests.helpers.input_fixture").cfg.view.fh
end

--- whether the console's field shows its status line (the
--- project's name on its top row) and any text on the rows
--- below it, the draft's; the recorder takes a text a glyph
--- at a time
local function field_texts(s)
  local status, draft = false, false
  for _, t in ipairs(s.field) do
    if t.y < fh() and t.text == K.PROJECT then status = true end
    if t.y >= fh() then draft = true end
  end
  return status, draft
end

--- the field's cursor: a fill in the field below its status
--- line's row
local function cursor_drawn(s)
  for _, e in ipairs(s.field_log) do
    if e.fill and e.y >= fh() and e.w < 3 * fh() then return true end
  end
  return false
end

local TAKES = "compy.input.hooks.keypressed = function() end\n"

describe("the console's field behind a program that owns the keys"
  .. " #console", function()
  after_each(K.cleanup)

  it("is hidden, its cursor too, and the status line stays",
    function()
      K.reset({ ["main.lua"] = TAKES })
      K.type("draftx")
      local s = K.screen()
      local status, draft = field_texts(s)
      assert.is_true(status)
      assert.is_true(draft)
      assert.is_true(cursor_drawn(s))
      -- the draft stays in the field, as typed before the run
      K.cc.input:clear()
      run("run()")
      assert.is_true(K.cc.run_live)
      K.cc.input:add_text("draftx")
      s = K.screen()
      status, draft = field_texts(s)
      assert.is_true(status)
      assert.is_false(draft)
      assert.is_false(cursor_drawn(s))
    end)

  local function back(how, program)
    K.reset({ ["main.lua"] = program
      or TAKES .. "function love.update() end\n" })
    run("run()")
    K.cc.input:add_text("draftx")
    local _, draft = field_texts(K.screen())
    assert.is_false(draft)
    how()
    _, draft = field_texts(K.screen())
    assert.is_true(draft)
  end

  it("is back after Ctrl+Q", function()
    back(function() K.keys("lctrl", "q") end)
  end)

  it("is back at a pause", function()
    back(function()
      K.cc:suspend_run()
      K.cc:suspend()
    end)
  end)

  --- a program whose last way to act was that hook can do
  --- nothing more (November 17)
  it("is back when the program drops its last hook", function()
    back(function()
      K.cc:get_project_env().compy.input.hooks.keypressed = nil
    end, TAKES)
  end)

  --- turned around on November 17: a program that can act owns
  --- all input, a pointer hook as much as a key hook
  it("is hidden behind a program with only a pointer hook",
    function()
      K.reset({ ["main.lua"] = "compy.input.hooks.mousepressed = "
        .. "function() end\n" })
      run("run()")
      assert.is_true(K.cc.run_live)
      K.cc.input:add_text("draftx")
      local status, draft = field_texts(K.screen())
      assert.is_true(status)
      assert.is_false(draft)
    end)

  --- a program that can do nothing more has ended at its last
  --- line (stage 4 of the canvas plan)
  it("is back after a program that could do nothing more ended",
    function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      run("run()")
      assert.is_false(K.cc.run_live)
      K.type("draftx")
      local status, draft = field_texts(K.screen())
      assert.is_true(status)
      assert.is_true(draft)
    end)

  it("leaves a program's own shown field as it is", function()
    K.reset({ ["main.lua"] = TAKES .. "compy.input.show({ })\n"
      .. "compy.input.set_text('mine')\n" })
    run("run()")
    local field = love.state.user_input_controller
    assert.is_true(field:is_shown())
    --- the console's field is hidden; the program's own, a
    --- view of its own over it, is not
    K.screen()
    assert.is_true(K.cc.view.input.field_hidden)
    assert.is_falsy(love.state.user_input.V.field_hidden)
  end)
end)

-- round 20: continue() gives back the program's handlers as
-- they were at the pause; it seeds no hook anew
describe("continue() and the hook table #console", function()
  after_each(K.cleanup)

  it("does not bring back an own handler whose hook was cleared",
    function()
      K.reset({ ["main.lua"] = "function love.keypressed() got = true end\n"
        .. "function love.update() end\n" })
      run("run()")
      local env = K.cc:get_project_env()
      env.compy.input.hooks.keypressed = nil
      K.cc:suspend_run()
      K.cc:suspend()
      assert.same("inspect", K.app_state())
      run("continue()")
      assert.same("running", K.app_state())
      assert.is_nil(env.compy.input.hooks.keypressed)
      K.keys("x")
      assert.is_nil(env.got)
      --- its update still acts: the input stays the program's
      assert.is_true(K.cc.main_ctrl.program_owns_input())
      K.keys("lctrl", "q")
    end)
end)

-- Ctrl+Pause pauses any live program that can act, one with only
-- key handlers and no update or draw included (the device run of
-- November 17 found it did nothing there); the pause gives the
-- console and its field back, and continue() hides them again
describe("Ctrl+Pause on a program that can act #console", function()
  after_each(K.cleanup)

  local KEYS_ONLY = "function love.keypressed(k) last = k end\n"

  it("pauses a program with only key handlers", function()
    K.reset({ ["main.lua"] = KEYS_ONLY })
    run("run()")
    assert.same("ready", K.app_state())
    assert.is_true(K.cc.main_ctrl.program_owns_input())
    K.keys("lctrl", "pause")
    K.frame()
    if K.app_state() == "snapshot" then K.cc:suspend() end
    assert.same("inspect", K.app_state())
    assert.is_false(K.cc.main_ctrl.program_owns_input())
    K.type("draftx")
    local status, draft = field_texts(K.screen())
    assert.is_true(status)
    assert.is_true(draft)
    K.cc.input:clear()
    run("continue()")
    assert.same("ready", K.app_state())
    assert.is_true(K.cc.main_ctrl.program_owns_input())
    K.keys("y")
    assert.same("y", K.cc:get_project_env().last)
    K.keys("lctrl", "q")
  end)
end)

-- p1's findings
describe("a pause of a program that can act, p1 #console", function()
  after_each(K.cleanup)

  it("pauses the program's serial handlers too", function()
    K.reset({ ["main.lua"] = "n = 0\n"
      .. "compy.serial.onTick = function() n = n + 1 end\n" })
    run("run()")
    local env = K.cc:get_project_env()
    local function tick()
      SerialPort.dispatcher:push('tick')
      SerialPort.dispatcher:pump()
    end
    local was = env.n
    tick()
    assert.equal(was + 1, env.n)
    K.keys("lctrl", "pause")
    K.frame()
    if K.app_state() == "snapshot" then K.cc:suspend() end
    assert.same("inspect", K.app_state())
    was = env.n
    tick()
    K.frame()
    assert.equal(was, env.n)
    run("continue()")
    was = env.n
    tick()
    assert.is_true(env.n > was)
    K.keys("lctrl", "q")
  end)

  it("pauses a program whose first lines call pause() and then"
    .. " idle, and continue() resumes it idle", function()
      K.reset({ ["main.lua"] = "function love.keypressed() end\n"
        .. "pause()\n" })
      run("run()")
      K.frame()
      if K.app_state() == "snapshot" then K.cc:suspend() end
      assert.same("inspect", K.app_state())
      run("continue()")
      assert.same("ready", K.app_state())
      assert.is_nil(love.state.paused_from)
      K.keys("lctrl", "q")
    end)

  it("gives a held console key's repeats no hidden draft", function()
    K.reset({ ["main.lua"] = "function love.update() end\n" })
    K.type("abc")
    K.hold("backspace")
    assert.same("ab", K.console_draft())
    K.cc:run_project()
    assert.is_true(K.cc.main_ctrl.program_owns_input())
    K.repeat_key("backspace")
    K.release("backspace")
    assert.same("ab", K.console_draft())
    K.keys("lctrl", "q")
  end)
end)
