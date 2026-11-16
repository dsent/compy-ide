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

  --- the maintainer's ruling of November 16, 2026: Ctrl+T from
  --- the editor runs "main.lua only for now"
  it("runs main.lua with Ctrl+T from the editor after a second.lua"
    .. " run", function()
      reset(FILES)
      run("run(nil, 'second.lua')")
      K.keys("lctrl", "q")
      run("edit('main.lua')")
      assert.same("editor", K.app_state())
      K.keys("lctrl", "t")
      K.frame()
      assert.same("main", env().which)
    end)

  --- "Ctrl+R should do nothing at the console. End of story."
  it("does nothing with Ctrl+R with no live program", function()
    reset(FILES)
    run("x = 1")
    local before = K.console_text()
    K.type("draft")
    K.keys("lctrl", "r")
    K.frame()
    assert.is_falsy(K.cc.run_live)
    assert.same("ready", K.app_state())
    assert.is_nil(env().which)
    assert.same(before, K.console_text():gsub("draft$", ""))
    assert.same("draft", K.console_draft())
  end)

  it("does nothing with Ctrl+R in the editor", function()
    reset(FILES)
    K.open("main.lua")
    for _, typed in ipairs({ "", "y = 2" }) do
      K.type(typed)
      K.keys("lctrl", "r")
      K.frame()
      assert.same("editor", K.app_state())
      assert.is_falsy(K.cc.run_live)
      assert.is_nil(env().which)
      assert.same(typed, K.draft())
    end
  end)

  it("restarts a program idle behind the console with Ctrl+R",
    function()
      reset({ ["main.lua"] = "which = 'main'\n"
        .. "function love.keypressed() end\n",
        ["second.lua"] = "which = 'second'\n"
        .. "function love.keypressed() end\n" })
      run("run(nil, 'second.lua')")
      assert.same("ready", K.app_state())
      assert.is_true(K.cc.run_live)
      env().which = "changed"
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
  --- the entry point "should only be remembered as long as the
  --- program is running from a particular entry point"
  it("restarts main.lua after Ctrl+Q and run()", function()
    reset(FILES)
    run("run(nil, 'second.lua')")
    K.keys("lctrl", "q")
    K.write_outside("main.lua", "which = 'main'\n"
      .. "function love.update() end\n")
    run("run()")
    env().which = "changed"
    K.keys("lctrl", "r")
    K.frame()
    assert.same("main", env().which)
    K.keys("lctrl", "q")
  end)

  it("leaves run() to main.lua", function()
    reset(FILES)
    run("run(nil, 'second.lua')")
    K.keys("lctrl", "q")
    run("run()")
    assert.same("main", env().which)
  end)
end)
