-- The near name (Beads compy-ide-console-suggests-the-near-name):
-- the line a run's error gains when it called a global name that
-- does not exist and one callable name differs from it in case
-- and underscores alone.

local NameHint = require("util.name_hint")

local function f() end

--- Lua 5.1's message for a call of the global `name`, nil
local function nil_call(name)
  return "[string \"x\"]:1: attempt to call global '" .. name
      .. "' (a nil value)"
end

describe("the near-name hint #console", function()
  it("names the one near name of a global called nil", function()
    assert.equal("There is no listProjects. Did you mean list_projects?",
      NameHint.of(nil_call("listProjects"), { list_projects = f }))
  end)

  it("works the other way round, and as the output shows the error",
    function()
      assert.equal("There is no list_projects. Did you mean listProjects?",
        NameHint.of("L1:attempt to call global 'list_projects' "
          .. "(a nil value)", { listProjects = f }))
    end)

  it("ignores case and underscores alone", function()
    local env = { List_Projects = f, listproject = f }
    assert.equal("There is no LISTPROJECTS. Did you mean List_Projects?",
      NameHint.of(nil_call("LISTPROJECTS"), env))
    assert.is_nil(NameHint.of(nil_call("listProj"), env))
  end)

  it("gives none where two names are near", function()
    assert.is_nil(NameHint.of(nil_call("listProjects"),
      { list_projects = f, listprojects = f }))
  end)

  it("gives none where no name is near", function()
    assert.is_nil(NameHint.of(nil_call("draw"), { list_projects = f }))
  end)

  it("counts only a name that can be called", function()
    local callable = setmetatable({ }, { __call = f })
    assert.is_nil(NameHint.of(nil_call("listProjects"),
      { list_projects = 5 }))
    assert.equal("There is no listProjects. Did you mean list_projects?",
      NameHint.of(nil_call("listProjects"),
        { list_projects = callable, LIST_PROJECTS = "text" }))
  end)

  it("looks through the environment's fallback, the nearer name "
    .. "first", function()
      local env = setmetatable({ }, { __index = { list_projects = f } })
      assert.equal("There is no listProjects. Did you mean list_projects?",
        NameHint.of(nil_call("listProjects"), env))
      -- a value the environment holds hides the fallback's
      local hidden = setmetatable({ list_projects = 1 },
        { __index = { list_projects = f } })
      assert.is_nil(NameHint.of(nil_call("listProjects"), hidden))
    end)

  --- review h1: callable only when it is a function, or its raw
  --- metatable's raw __call is one
  it("counts a __call only when it is a function, read raw",
    function()
      local function env(v) return { draw_tree = v } end
      assert.is_nil(NameHint.of(nil_call("drawTree"),
        env(setmetatable({ }, { __call = false }))))
      -- a __metatable field advertises nothing
      assert.is_nil(NameHint.of(nil_call("drawTree"),
        env(setmetatable({ }, { __metatable = { __call = f } }))))
      assert.equal("There is no drawTree. Did you mean draw_tree?",
        NameHint.of(nil_call("drawTree"),
          env(setmetatable({ }, { __call = f, __metatable = false }))))
    end)

  it("runs none of the user's code and never raises", function()
    local function boom() error("user code ran") end
    -- a metatable whose own reads raise
    local raising = setmetatable({ }, { __index = boom })
    local env = { draw_tree = setmetatable({ }, raising) }
    assert.is_nil(NameHint.of(nil_call("drawTree"), env))
    -- an environment whose metatable's reads raise
    local fallback = setmetatable({ }, setmetatable({ },
      { __index = boom }))
    assert.is_nil(NameHint.of(nil_call("drawTree"), fallback))
    -- an error that is not text is not turned into text
    local err = setmetatable({ }, { __tostring = boom })
    assert.is_nil(NameHint.of(err, { draw_tree = f }))
  end)

  --- review h1: where the names cannot all be known, "exactly
  --- one" cannot be either
  it("gives none where the environment falls back to a function",
    function()
      local env = setmetatable({ draw_tree = f },
        { __index = function() return f end })
      assert.is_nil(NameHint.of(nil_call("drawTree"), env))
    end)

  it("gives none where the fallbacks go on past four tables",
    function()
      local t = { }
      for _ = 1, 4 do t = setmetatable({ }, { __index = t }) end
      t.draw_tree = f
      assert.is_nil(NameHint.of(nil_call("drawTree"), t))
      -- four tables in all are known
      local known = setmetatable({ draw_tree = f }, { __index =
        setmetatable({ }, { __index = setmetatable({ }, { __index =
          { } }) }) })
      assert.equal("There is no drawTree. Did you mean draw_tree?",
        NameHint.of(nil_call("drawTree"), known))
    end)

  it("gives none for any other error", function()
    local env = { list_projects = f, set_text = f }
    for _, msg in ipairs({
      "[string \"x\"]:1: attempt to call global 'listProjects' "
        .. "(a number value)",
      "[string \"x\"]:1: attempt to call field 'setText' (a nil value)",
      "[string \"x\"]:1: attempt to call method 'setText' (a nil value)",
      "[string \"x\"]:1: attempt to index global 'listProjects' "
        .. "(a nil value)",
      "L1:boom",
    }) do
      assert.is_nil(NameHint.of(msg, env), msg)
    end
    assert.is_nil(NameHint.of(nil, env))
    assert.is_nil(NameHint.of(nil_call("listProjects"), nil))
  end)
end)
