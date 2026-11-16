-- Behind a live program that takes keys and draws nothing, the
-- console's field and its cursor are hidden, and the status
-- line and the output stay (the maintainer, on the field shown
-- and dead there: "that is also weird. Should we maybe hide the
-- console in that case?"; the lead's option B). The field comes
-- back by itself at a pause, a stop, or when the program takes
-- keys no more. Drawn through the real draw functions, recorded
-- by the K helper.

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

  local function back(how)
    K.reset({ ["main.lua"] = TAKES .. "function love.update() end\n" })
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

  it("is back when the program drops its last hook", function()
    back(function()
      K.cc:get_project_env().compy.input.hooks.keypressed = nil
    end)
  end)

  it("stays as today behind a program that takes no keys",
    function()
      K.reset({ ["main.lua"] = "compy.input.hooks.mousepressed = "
        .. "function() end\n" })
      run("run()")
      assert.is_true(K.cc.run_live)
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
      assert.is_false(K.cc.main_ctrl.program_owns_keys())
      K.keys("lctrl", "q")
    end)
end)
