-- A second entry point for run (Option 2 of the
-- multi-entry-point proposal, its two-argument form only):
-- run(nil, "second.lua") runs that file of the open project as
-- the program, a clean start like any run; run("name",
-- "second.lua") opens that project first. Ctrl+R restarts the
-- entry point that last ran in this project. Keys only, through
-- the K helper.

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

local FILES = {
  ["main.lua"] = "which = 'main'\n",
  ["second.lua"] = "which = 'second'\n"
    .. "function love.update() ticks = (ticks or 0) + 1 end\n",
}

describe("run's second entry point #console", function()
  after_each(cleanup)

  it("runs a file of the open project as the program", function()
    reset(FILES)
    run("run(nil, 'second.lua')")
    assert.same("running", K.app_state())
    assert.same("second", env().which)
    K.frame()
    K.frame()
    assert.is_true((env().ticks or 0) >= 1)
    K.keys("lctrl", "q")
    assert.is_false(K.cc.run_live)
    assert.is_nil(env().which)
  end)

  it("refuses a file the project does not hold", function()
    reset(FILES)
    run("run(nil, 'nope.lua')")
    assert.truthy(K.console_text():find(
      "There is no nope.lua in this project.", 1, true))
    assert.is_falsy(K.cc.run_live)
  end)

  it("refuses a name a file cannot have", function()
    reset(FILES)
    run("run(nil, 'a/b.lua')")
    assert.truthy(K.console_text():find("Filename invalid", 1, true))
    assert.is_falsy(K.cc.run_live)
  end)

  it("restarts that entry point with Ctrl+R", function()
    reset(FILES)
    run("run(nil, 'second.lua')")
    env().which = 'changed'
    K.keys("lctrl", "r")
    K.frame()
    assert.same("running", K.app_state())
    assert.same("second", env().which)
    K.keys("lctrl", "q")
  end)

  it("runs that entry point again with Ctrl+R from the editor",
    function()
      reset(FILES)
      run("run(nil, 'second.lua')")
      K.keys("lctrl", "q")
      run("edit('main.lua')")
      assert.same("editor", K.app_state())
      K.keys("lctrl", "r")
      K.frame()
      assert.same("second", env().which)
      K.keys("lctrl", "q")
    end)

  it("opens the project named first, then runs its file", function()
    reset(FILES)
    K.next_project("other", {
      ["main.lua"] = "which = 'other main'\n",
      ["second.lua"] = "which = 'other second'\n"
        .. "function love.update() end\n",
    })
    run("run('other', 'second.lua')")
    assert.same("other", K.cc.model.projects.current.name)
    assert.same("other second", env().which)
    K.keys("lctrl", "q")
  end)

  it("refuses a file the named project lacks, and stays", function()
    reset(FILES)
    K.next_project("other", { ["main.lua"] = "which = 1\n" })
    run("run('other', 'second.lua')")
    assert.same(K.PROJECT, K.cc.model.projects.current.name)
    assert.truthy(K.console_text():find(
      "There is no second.lua in this project.", 1, true))
    assert.is_falsy(K.cc.run_live)
  end)

  it("refuses a folder before the run that ended is touched",
    function()
      local files = { ["assets/a.png"] = "png",
        ["idle.lua"] = "which = 'idle'\n" }
      for k, v in pairs(FILES) do files[k] = v end
      reset(files)
      run("run(nil, 'idle.lua')")
      run("run(nil, 'assets')")
      assert.same("idle", env().which)
      assert.truthy(K.console_text():find(
        "There is no assets in this project.", 1, true),
        K.console_text())
    end)

  --- the entry point is remembered while its project stays
  --- open; opening a project starts from main.lua again
  it("forgets the entry point when the project is opened again",
    function()
      reset(FILES)
      run("run(nil, 'second.lua')")
      K.keys("lctrl", "q")
      K.next_project("other", { ["main.lua"] = "which = 'other'\n" })
      run("project('other')")
      K.next_project(K.PROJECT, FILES)
      run("project('" .. K.PROJECT .. "')")
      run("edit('main.lua')")
      K.keys("lctrl", "r")
      K.frame()
      assert.same("main", env().which)
    end)

  it("leaves run() to main.lua", function()
    reset(FILES)
    run("run(nil, 'second.lua')")
    K.keys("lctrl", "q")
    run("run()")
    assert.same("main", env().which)
  end)
end)
