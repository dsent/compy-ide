-- The console's scrollback and echo against the application
-- items of the spec (IS7.x), under the maintainer's ruling
-- "Console scrollback, first version". Keys only, through
-- tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it
local spec_deviation = marks.spec_deviation

local RULING = "rulings.md: Console scrollback, first version"

local unrouted

--- A fresh console whose lines print to its output, as the
--- IDE redirects print before it builds them
local function reset()
  K.reset()
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

local function row_of(text)
  for y, r in ipairs(screen()) do
    if r == text then return y end
  end
end

describe("IS7 the console's output #editor #spec", function()
  before_each(reset)
  after_each(cleanup)

  spec_it("IS7.6 Present the result: the accepted line is shown "
      .. "in the output before what it printed", function()
    run("print('hi')")
    local e = row_of("print('hi')")
    assert.is_not_nil(e)
    assert.equal(e + 1, row_of("hi"))
  end)

  spec_it("IS7.6 Present the result: a failing line's error "
      .. "follows it and its output", function()
    run("print('a') error('boom')")
    local e = row_of("print('a') error('boom')")
    assert.equal(e + 1, row_of("a"))
    assert.truthy(screen()[e + 2]:find("boom", 1, true))
  end)

  spec_it("IS7.3 Check application input: a refused line is not "
      .. "written to the output and stays in the field", function()
    K.type("x = = 1")
    K.keys("return")
    K.frame(100)
    assert.is_nil(row_of("x = = 1"))
    assert.equal("x = = 1", K.console_draft())
  end)

  spec_deviation("IS7.4 Accept an application instruction: the "
      .. "accepted line moves from the field to the output, which "
      .. "shows it in blue", RULING, function()
    run("y = 2")
    assert.equal("", K.console_draft())
    assert.is_not_nil(row_of("y = 2"))
  end)

  spec_deviation("IS7.11 Coordinate activity controls: with the "
      .. "field empty, Home and End move the output's view to its "
      .. "oldest and newest row", RULING, function()
    run("for i = 1, 40 do print(i) end")
    local out = K.cc.model.output
    K.keys("home")
    assert.equal(out.kept.first, out.view_top)
    K.keys("end")
    assert.is_false(out:is_scrolled())
  end)
end)
