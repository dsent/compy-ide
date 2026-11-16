-- The console's two channels (the maintainer's ruling of
-- November 15, 2026): the notice band is the field's, and says
-- only why a line was not taken (it does not parse) or, in
-- orange, a hint that is no error (an unfinished statement).
-- What a command does, a refusal or a run's error included, is
-- said in the output: a run's error in the theme's red
-- (colors.terminal.error), a refusal, which is no error, in a
-- burnt orange (colors.terminal.refusal), an answer in the
-- output's own color.
-- Keys only, through the K helper and the console's real paths.

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

local function colors()
  return K.cc.cfg.view.colors.terminal
end

--- the screen's row that reads `text`, and the color of its
--- first character
--- @return string? row
--- @return number[]? color
local function row(text)
  local t = K.cc.model.output.terminal
  for y, r in ipairs(t.buffer) do
    local s = table.concat(r):gsub("%s+$", "")
    if s == text then return s, t.state_buffer[y][1].color end
  end
end

local function same_color(a, b)
  return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

--- `text` is a row of the output, in `color`
local function said(text, color, what)
  local s, c = row(text)
  assert.is_not_nil(s, (what or text) .. ": not on the screen:\n"
    .. K.console_text())
  assert.is_true(same_color(c, color), (what or text)
    .. ": not in the color it should be")
end

local function band()
  return K.cc.input.model:get_wrapped_error()
end

local function no_band(what)
  assert.is_nil(band(), what)
end

describe("the console's channels #console", function()
  after_each(cleanup)

  describe("a run's error", function()
    --- Enter acts once per press (the ruling of November 16,
    --- 2026, on held keys): a line that fails keeps its text,
    --- and no band message holds a repeat back any more
    it("of a line Enter is held on runs it once", function()
      reset()
      K.type("error('boom')")
      K.hold("return")
      for _ = 1, 5 do K.repeat_key("return") end
      K.release("return")
      K.frame(100)
      local n = select(2, K.console_text():gsub("L1:boom", ""))
      assert.equal(1, n)
      assert.same("error('boom')", K.console_draft())
    end)

    it("of a typed line is said once, in the output, in red, and "
      .. "the line stays in the field", function()
        reset()
        run("error('boom')")
        said("L1:boom", colors().error)
        no_band("no copy in the band")
        assert.same("error('boom')", K.console_draft())
        local n = select(2, K.console_text():gsub("boom'?%)?", ""))
        assert.equal(2, n, "the echo and the error, once each")
      end)

    it("of a program's first lines is said in the output, in red",
      function()
        reset({ ["main.lua"] = "local a = 1\nerror('top')\n" })
        run("run()")
        said("Error: L2:top", colors().error)
        no_band()
      end)

    it("of a program's load is said in the output, in red",
      function()
        reset({ ["main.lua"] = "x = = 1\n" })
        run("run()")
        local t = K.console_text()
        local first = t:match("\n([^\n]*unexpected[^\n]*)")
          or t:match("\n(L1:[^\n]*)")
        assert.is_not_nil(first, t)
        said(first:gsub("%s+$", ""), colors().error)
        no_band()
      end)

    it("of a running program is said once, in the output, in red, "
      .. "and the band stays empty", function()
        reset({ ["main.lua"] =
          "local done\n"
          .. "function love.update()\n"
          .. "  if done then return end\n"
          .. "  done = true\n"
          .. "  error('late')\n"
          .. "end\n" })
        K.type("run()")
        K.keys("return")
        -- one frame: on a Compy the pause comes at its end
        K.frame()
        K.cc:suspend()
        K.frame(100)
        assert.same("inspect", K.app_state())
        said("Execution error at L5:late", colors().error)
        no_band()
        local n = select(2, K.console_text():gsub("Execution error", ""))
        assert.equal(1, n)
      end)
  end)

  --- a pause is the debugger's: its text shows in the band as
  --- an orange notice, and the program's screen is not touched
  --- (the maintainer's ruling of November 16, 2026)
  describe("a pause's text", function()
    local function paused_by(how)
      reset({ ["main.lua"] = "print('mine')\n"
        .. "local n = 0\n"
        .. "function love.update()\n"
        .. "  n = n + 1\n"
        .. "  if n == 1 and PAUSE then pause('Look here') end\n"
        .. "end\n" })
      K.cc:get_project_env().PAUSE = how == "pause"
      run("run()")
      local before = K.console_text()
      if how == "ctrl" then K.keys("lctrl", "pause") end
      K.frame()
      K.cc:suspend()
      K.frame(100)
      assert.same("inspect", K.app_state())
      return before
    end

    for _, case in ipairs({ { "pause", "Look here" },
      { "ctrl", "BREAK into program" } }) do
      it((case[1] == "pause" and "pause('Look here')" or "Ctrl+Pause")
        .. " shows in the band, orange, the output untouched",
        function()
          local before = paused_by(case[1])
          assert.same({ case[2] }, band())
          assert.same("notice", K.cc.input:message_kind())
          assert.same(before, K.console_text())
          K.cc:get_project_env().continue()
          K.frame(100)
          assert.same(before, K.console_text())
          K.cc:get_project_env().love.update = nil
        end)
    end
  end)

  it("a line that does not parse is said in the band alone",
    function()
      reset()
      run("x = = 1")
      assert.is_not_nil(band())
      assert.same("error", K.cc.input:message_kind())
      assert.is_nil((K.console_text():find("x = = 1", 1, true)))
    end)

  describe("a command's refusal is said in the output, in its own color",
    function()
      it("run() while a program runs", function()
        reset({ ["main.lua"] = "function love.update() end\n" })
        run("run()")
        K.cc:get_project_env().run()
        K.frame(100)
        said("A project is already running: Ctrl+Q stops it.",
          colors().refusal)
        no_band()
        K.cc:get_project_env().love.update = nil
      end)

      for _, cmd in ipairs({ "stop()", "pause()" }) do
        it(cmd .. " with nothing running", function()
          reset()
          run(cmd)
          said("Nothing is running.", colors().refusal)
          no_band()
        end)
      end

      it("continue() with nothing paused", function()
        reset()
        run("continue()")
        said("Nothing is paused.", colors().refusal)
      end)

      it("project() with no name", function()
        reset()
        run("project()")
        said('A project needs a name: project("name").',
          colors().refusal)
      end)

      it("a file the project does not hold, in one sentence",
        function()
          reset()
          for _, cmd in ipairs({ "tidy('nosuch.lua')",
            "dofile('nosuch.lua')", "readfile('nosuch.lua')",
            "readlines('nosuch.lua')" }) do
            K.keys("lctrl", "l")
            run(cmd)
            said("There is no nosuch.lua in this project.",
              colors().refusal, cmd)
          end
        end)

      it("a project that cannot be opened, the open one left open",
        function()
          reset()
          local open = K.cc.model.projects.current
          run("project('a/b')")
          said("Filename invalid: Forbidden characters",
            colors().refusal)
          assert.equal(open, K.cc.model.projects.current)
          run("current_project()")
          said("Currently open project: " .. open.name, colors().fg)
          K.keys("lctrl", "l")
          run("print(readfile('main.lua') ~= nil)")
          said("true", colors().fg)
        end)
    end)

  --- a refused command changes nothing: a name that cannot be
  --- a project's is refused before the open project closes
  for _, name in ipairs({ "'a/b'", "''" }) do
    it("project(" .. name .. ") leaves a paused program paused and "
      .. "its files open", function()
        reset({ ["main.lua"] =
          "function love.update() love.update = nil; error('x') end\n" })
        K.open()
        K.keys("lctrl", "t")
        K.frame()
        K.cc:suspend()
        assert.same("inspect", K.app_state())
        local open = K.cc.model.projects.current
        local buffer = K.cc.editor:get_active_buffer()
        assert.is_not_nil(buffer)
        run("project(" .. name .. ")")
        assert.same("inspect", K.app_state())
        assert.is_true(K.cc.run_live)
        assert.equal(open, K.cc.model.projects.current)
        assert.equal(buffer, K.cc.editor:get_active_buffer())
        local t = K.console_text()
        assert.truthy(t:find("Filename invalid", 1, true), t)
      end)
  end

  --- With no project open, which only an SD card that cannot
  --- hold scratchpad leaves (closing a project, or the IDE's
  --- start, cannot open or make it), every command that needs a
  --- project says so in one sentence, and nothing else
  describe("with no project open", function()
    local NONE = "No project is open: the SD card cannot be used."

    --- the state a card that cannot hold scratchpad leaves
    local function no_project()
      reset()
      K.cc:_close_project()
      assert.is_nil(K.cc.model.projects.current)
    end

    for _, cmd in ipairs({ "edit()", "edit('main.lua')",
      "readfile('main.lua')", "readlines('main.lua')",
      "writefile('a.txt', 'x')", "tidy()", "dofile('main.lua')",
      "loadfile('main.lua')", "current_project()",
      "list_contents()", "run()", "run_project()" }) do
      it(cmd .. " says so", function()
        no_project()
        run(cmd)
        said(NONE, colors().refusal, cmd)
        local t = K.console_text()
        assert.is_nil(t:find("nil", 1, true), t)
        assert.is_nil(t:find("attempt to", 1, true), t)
        assert.is_nil(t:find("Filename invalid", 1, true), t)
        assert.same("ready", K.app_state())
      end)
    end

    it("Ctrl+T says so", function()
      no_project()
      K.keys("lctrl", "t")
      K.frame(100)
      said(NONE, colors().refusal)
      assert.same("ready", K.app_state())
    end)
  end)

  --- run() of a name no project has refuses and changes
  --- nothing; project() creates (the maintainer's ruling of
  --- November 16, 2026)
  describe("run() of a name", function()
    it("no project has refuses, and changes nothing", function()
      reset()
      local open = K.cc.model.projects.current
      run("run('mzae')")
      said('There is no project mzae: project("mzae") creates it.',
        colors().refusal)
      assert.equal(open, K.cc.model.projects.current)
      assert.same("ready", K.app_state())
      assert.is_falsy(K.cc.run_live)
      assert.is_nil(ProjectService.is_project(ProjectService.path,
        "mzae"), "no project made")
    end)

    it("that cannot be a project's is refused for its name",
      function()
        reset()
        local open = K.cc.model.projects.current
        run("run('a/b')")
        said("Filename invalid: Forbidden characters", colors().refusal)
        assert.equal(open, K.cc.model.projects.current)
      end)

    it("a project has opens and runs it", function()
      reset()
      K.next_project("other", { ["main.lua"] = "print('other ran')\n" })
      run("run('other')")
      said("Project other opened", colors().fg)
      said("other ran", colors().fg)
    end)
  end)

  it("an answer stays in the output's own color", function()
    reset()
    K.next_project("other", { ["main.lua"] = "b = 1\n" })
    run("project('other')")
    said("Project other opened", colors().fg)
    run("current_project()")
    said("Currently open project: other", colors().fg)
  end)

  describe("an unfinished statement", function()
    it("takes Enter as a new line, and says so in orange",
      function()
        reset()
        run("for i = 1, 3 do")
        assert.same("for i = 1, 3 do\n", K.console_draft())
        assert.same("notice", K.cc.input:message_kind())
        assert.same({ "Unfinished code: type the rest, then press Enter." },
          band())
        assert.is_nil((K.console_text():find("for i", 1, true)))
      end)

    it("runs once finished, the hint gone", function()
      reset()
      run("for i = 1, 2 do")
      K.type("print('n' .. i) end")
      K.keys("return")
      K.frame(100)
      no_band()
      said("n2", colors().fg)
    end)
  end)
end)
