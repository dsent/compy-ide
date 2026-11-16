-- What a program can call on compy.terminal (also tty): gotoxy
-- and clear. show_cursor and hide_cursor are gone (the
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
    finally(function() base.io = io_was end)
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
      finally(function() base.io = io_was end)
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
end)
