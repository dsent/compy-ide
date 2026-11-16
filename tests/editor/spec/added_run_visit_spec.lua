-- A run of the project (Ctrl+T, Ctrl+R) and a visit to
-- another file (Ctrl+J, then Escape) are no leaving of a file
-- (IS1.4, IS1.5, IS6.6): each file comes back as it was, its
-- timeline, its draft's changes and what can be redone
-- included, while storage holds what the editor left there.
-- A file changed from outside meanwhile comes back as storage
-- holds it, its timeline gone. The files go when the editor
-- is left, with their project, and when edit() in the console
-- starts the editor anew (IS1.1). Keys only, through
-- tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it

local TYPES = { "lua", "txt", "md" }

--- the file of a test in a file of type `ext`
local function named(ext)
  if ext == "lua" then return "main.lua" end
  return "notes." .. ext
end

--- What the program a run starts does once its code is done:
--- it ends, it idles with a hook of its own, or an error
--- pauses it
local PROGRAMS = {
  ends = "y = 0\n",
  idles = "compy.input.hooks.keypressed = function() end\n",
  -- its handler goes from the project's love table as it
  -- fails, so that no later run in the file finds it there
  pauses = "function love.update()\n"
      .. "  love.update = nil\n"
      .. "  error('x')\n"
      .. "end\n",
}
local PROGRAM_KINDS = { "ends", "idles", "pauses" }

--- Run the project from the editor with Ctrl+T; its program
--- ends as `kind` says
local function run_from_editor(kind)
  K.keys("lctrl", "t")
  if kind == "pauses" then
    -- the error in its handler pauses it; the move from the
    -- snapshot to 'inspect' is the screenshot's callback,
    -- which needs a real graphics context
    K.frame()
    assert.same("snapshot", K.app_state())
    K.cc:suspend()
    assert.same("inspect", K.app_state())
  else
    assert.same("ready", K.app_state())
  end
end

--- the names of the files on the editor's stack, front first
local function stack()
  local out = {}
  for _, b in ipairs(K.cc.editor.model.buffers) do
    out[#out + 1] = b.name
  end
  return out
end

--- the document view's rows, as one text
local function shown()
  return table.concat(K.view_rows(), "\n")
end

--- the document view's first row shown
local function view_offset()
  return K.ed.view:get_current_buffer():get_offset()
end

--- Out and back: a run with Ctrl+T, a run with Ctrl+R,
--- or a visit to the file the browsed block names
local TRIPS = {
  run = function()
    K.keys("lctrl", "t")
    K.keys("lctrl", "t")
  end,
  --- a run, Ctrl+R on it (it restarts a live program only),
  --- and back
  restart = function()
    K.keys("lctrl", "t")
    K.keys("lctrl", "r")
    K.keys("lctrl", "t")
  end,
  visit = function()
    K.keys("lctrl", "j")
    K.keys("escape")
  end,
}

describe("a run and a visit #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("the draft", function()
    for _, ext in ipairs(TYPES) do
      spec_it("IS1.4 Resume after running a project: in a ."
          .. ext .. " file, the draft's changes undo and redo "
          .. "after a run", function()
        local name = named(ext)
        K.reset({ ["main.lua"] = "x = 1\n", [name] = "a = 1\n" })
        K.open(name)
        K.type("q")
        K.keys("backspace")
        TRIPS.run()
        assert.same(name, K.file_name())
        K.keys("lctrl", "z")
        assert.same("q", K.draft())
        K.keys("lctrl", "y")
        assert.same("", K.draft())
        K.keys("lctrl", "z")
        assert.same("q", K.draft())
      end)
    end

    spec_it("IS1.4 Resume after running a project: an aborted "
        .. "replacement comes back by undo after a run", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(1)
      K.keys("f2")
      K.type("9")
      K.keys("lctrl", "t")
      assert.same("editor", K.app_state())
      assert.same("replacing", K.state())
      K.keys("escape")
      TRIPS.run()
      K.keys("lctrl", "z")
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      assert.same("x = 19", K.draft())
    end)
  end)

  describe("a cut", function()
    for _, ext in ipairs(TYPES) do
      spec_it("IS6.6 Undo and redo: in a ." .. ext .. " file, a "
          .. "cut and its abort undo after a run", function()
        local name = named(ext)
        local original = "precious = 123\nx = 1\n"
        K.reset({ ["main.lua"] = "", [name] = original })
        K.open(name)
        K.browse_to(1)
        K.keys("lctrl", "delete")
        K.keys("escape")
        TRIPS.run()
        K.keys("lctrl", "z")
        assert.same("precious = 123", K.draft())
        K.keys("lctrl", "z")
        assert.same(original, K.file(name))
      end)

    end

  end)

  describe("what a new action drops", function()
    for _, trip in ipairs({ "run", "restart", "visit" }) do
      local types = trip == "visit" and { "lua" } or TYPES
      for _, ext in ipairs(types) do
        spec_it("IS6.6 Undo and redo: in a ." .. ext .. " file, "
            .. "typing after an undone cut drops its redo, a "
            .. trip .. " later too", function()
          local name = named(ext)
          local original = "precious = 123\ndofile(\"other.lua\")\n"
          K.reset({
            ["main.lua"] = "", [name] = original, ["other.lua"] = ""
          })
          K.open(name)
          K.browse_to(1)
          K.keys("lctrl", "delete")
          K.keys("lctrl", "z")
          assert.same(original, K.file(name))
          K.type("x")
          K.keys("backspace")
          K.browse_to(2)
          TRIPS[trip]()
          assert.same(name, K.file_name())
          K.keys("lctrl", "y")
          assert.same(original, K.file(name))
          assert.same("", K.draft())
        end)
      end

      spec_it("IS6.6 Undo and redo: typing after an undone "
          .. "draft change drops its redo, a " .. trip
          .. " later too", function()
        K.reset({
          ["main.lua"] = "dofile(\"notes.txt\")\n",
          ["notes.txt"] = "n\n",
        })
        K.open()
        K.browse_to(1)
        K.type("old")
        K.keys("lctrl", "z")
        K.type("q")
        K.keys("backspace")
        TRIPS[trip]()
        K.keys("lctrl", "y")
        assert.same("", K.draft())
      end)

      spec_it("IS6.6 Undo and redo: what can be redone still "
          .. "can after a " .. trip, function()
        K.reset({
          ["main.lua"] = "dofile(\"notes.txt\")\n",
          ["notes.txt"] = "n\n",
        })
        K.open()
        K.browse_to(1)
        K.type("y = 2")
        K.keys("return")
        K.keys("lctrl", "z")
        K.browse_to(1)
        TRIPS[trip]()
        K.keys("lctrl", "y")
        assert.same("y = 2\ndofile(\"notes.txt\")\n", K.file())
      end)
    end
  end)

  describe("the files go with the editor and the project", function()
    spec_it("IS6.6 Undo and redo: a project switched after a "
        .. "run takes the editor's files with it", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(1)
      K.keys("lctrl", "delete")
      K.keys("escape")
      K.keys("lctrl", "t")
      assert.same("ready", K.app_state())
      K.next_project("other", { ["main.lua"] = "b = 1\n" })
      K.type("project(\"other\")")
      K.keys("return")
      K.keys("lctrl", "t")
      assert.same("editor", K.app_state())
      assert.same(1, K.blocks())
      assert.same(1, K.ed.model.buffers:length())
      K.keys("lctrl", "z")
      assert.same("", K.draft())
      K.type("c = 2")
      K.keys("return")
      assert.same("b = 1\nc = 2\n", K.file())
    end)

    spec_it("IS1.6 Step back from a file with Escape: the files "
        .. "left go, and Ctrl+T opens the main file anew",
      function()
        K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
        K.open()
        K.browse_to(1)
        K.keys("lctrl", "delete")
        K.keys("escape")
        K.keys("escape")
        assert.same("ready", K.app_state())
        assert.is_nil(K.buffer())
        K.keys("lctrl", "t")
        assert.same("editor", K.app_state())
        assert.same("end", K.position())
        K.keys("lctrl", "z")
        assert.same("", K.draft())
        assert.same("y = 2\n", K.file())
      end)
  end)

  describe("edit() in the console starts the editor anew", function()
    for _, kind in ipairs(PROGRAM_KINDS) do
      spec_it("IS1.1 Open a Lua file: after a run whose program "
          .. kind .. ", edit() of the file the run came from "
          .. "opens it alone, at its end, with no timeline",
        function()
          local program = PROGRAMS[kind]
          K.reset({ ["main.lua"] = program .. "x = 1\n" })
          K.open()
          K.browse_to(2)
          K.keys("lctrl", "delete")
          K.keys("escape")
          K.browse_to(1)
          run_from_editor(kind)
          K.open()
          assert.same("editor", K.app_state())
          assert.same({ "main.lua" }, stack())
          assert.same("end", K.position())
          K.keys("lctrl", "z")
          assert.same("", K.draft())
          assert.same(program, K.file())
        end)

      spec_it("IS1.1 Open a Lua file: after a run whose program "
          .. kind .. ", edit() of another file opens it alone, "
          .. "and Escape goes to the console", function()
        K.reset({
          ["main.lua"] = PROGRAMS[kind] .. "x = 1\n",
          ["other.lua"] = "o = 1\n",
        })
        K.open()
        K.browse_to(1)
        run_from_editor(kind)
        K.open("other.lua")
        assert.same("editor", K.app_state())
        assert.same({ "other.lua" }, stack())
        assert.same("end", K.position())
        K.keys("escape")
        assert.are_not.same("editor", K.app_state())
        assert.is_nil(K.buffer())
      end)

      spec_it("IS1.4 Resume after running a project: after a run "
          .. "whose program " .. kind .. ", Ctrl+T brings the "
          .. "file back with its position, view and timeline",
        function()
          local lines = {}
          for i = 1, 40 do lines[i] = "line " .. i end
          K.reset({
            ["main.lua"] = PROGRAMS[kind],
            ["notes.txt"] = table.concat(lines, "\n") .. "\n",
          })
          K.open("notes.txt")
          K.browse_to(5)
          K.keys("lctrl", "delete")
          K.keys("escape")
          local off = view_offset()
          assert.is_true(off > 0)
          run_from_editor(kind)
          K.keys("lctrl", "t")
          assert.same("editor", K.app_state())
          assert.same({ "notes.txt" }, stack())
          assert.same(5, K.position())
          assert.same(off, view_offset())
          K.keys("lctrl", "z")
          assert.same("line 5", K.draft())
        end)
    end
  end)

  describe("a file changed outside while it was away", function()
    local REWRITES = 'writefile("main.lua", '
        .. '"a = 1\\nb = 2\\nc = 3\\n")\n'
    local NEW = "a = 1\nb = 2\nc = 3\n"

    spec_it("IS1.4 Resume after running a project: a file the "
        .. "run rewrote comes back as storage holds it, with no "
        .. "timeline, and takes the next line", function()
      K.reset({ ["main.lua"] = REWRITES })
      K.open()
      K.type("y = 1")
      K.keys("return")
      assert.same(REWRITES .. "y = 1\n", K.file())
      K.keys("lctrl", "t")
      assert.same(NEW, K.file())
      K.keys("lctrl", "t")
      assert.same("editor", K.app_state())
      assert.same("main.lua", K.file_name())
      assert.same(3, K.blocks())
      assert.truthy(shown():find("c = 3", 1, true))
      assert.falsy(shown():find("writefile", 1, true))
      assert.same("end", K.position())
      K.keys("lctrl", "z")
      assert.same("", K.draft())
      assert.same(NEW, K.file())
      K.type("d = 4")
      K.keys("return")
      assert.is_nil(K.message())
      assert.same(NEW .. "d = 4\n", K.file())
    end)

    --- the browsing position before the run, the file's text
    --- before it, and the position after it
    local POSITIONS = {
      { 2, "a\nb\nc\nd\ne\n", 2 },
      { 4, "a\nb\nc\nd\ne\n", "end" },
      { "end", "a\nb\n", "end" },
    }
    for _, case in ipairs(POSITIONS) do
      local from, text, to = case[1], case[2], case[3]
      spec_it("IS1.4 Resume after running a project: a file the "
          .. "run rewrote keeps the browsing position's block "
          .. "number while it has it, else the end: "
          .. tostring(from) .. " of " .. #text / 2 .. " blocks "
          .. "comes back as " .. tostring(to), function()
        K.reset({
          ["main.lua"] = 'writefile("notes.txt", '
              .. '"n1\\nn2\\nn3\\n")\n',
          ["notes.txt"] = text,
        })
        K.open("notes.txt")
        if from ~= "end" then K.browse_to(from) end
        K.keys("lctrl", "t")
        K.keys("lctrl", "t")
        assert.same(3, K.blocks())
        assert.same(to, K.position())
        assert.truthy(shown():find("n3", 1, true))
      end)
    end

    --- what a console command changes, and what it leaves
    local COMMANDS = {
      ["tidy()"] = {
        name = "main.lua",
        text = "a = 0\nx   =   1\ny=2\n",
        command = 'tidy("main.lua")',
        after = "x = 1\ny = 2\n",
      },
      ["writefile()"] = {
        name = "notes.txt",
        text = "cut\nold\n",
        command = 'writefile("notes.txt", "new\\n")',
        after = "new\n",
      },
    }
    for what, c in pairs(COMMANDS) do
      spec_it("IS1.4 Resume after running a project: a file "
          .. what .. " in the console changed comes back as "
          .. "storage holds it, with no timeline", function()
        K.reset({ ["main.lua"] = "x = 1\n", [c.name] = c.text })
        K.open(c.name)
        K.browse_to(1)
        K.keys("lctrl", "delete")
        K.keys("escape")
        K.keys("lctrl", "t")
        K.type(c.command)
        K.keys("return")
        assert.same(c.after, K.file(c.name))
        K.keys("lctrl", "t")
        assert.same("editor", K.app_state())
        assert.same(c.name, K.file_name())
        local first = c.after:match("^[^\n]*")
        assert.truthy(shown():find(first, 1, true))
        K.keys("lctrl", "z")
        assert.same("", K.draft())
        assert.same(c.after, K.file(c.name))
        K.type("z = 3")
        K.keys("return")
        assert.is_nil(K.message())
        assert.truthy(K.file(c.name):find("z = 3", 1, true))
      end)
    end

    --- how the caller changes while the file it names is in
    --- front: from outside, or by a run from that file
    local CALLER_CHANGES = {
      outside = function(text)
        K.write_outside("main.lua", text)
      end,
      run = function()
        K.keys("lctrl", "t")
        K.keys("lctrl", "t")
        assert.same("lib.lua", K.file_name())
      end,
    }
    for how, change in pairs(CALLER_CHANGES) do
      spec_it("IS1.6 Step back from a file with Escape: a caller "
          .. "changed during a visit (" .. how .. ") comes back "
          .. "as storage holds it, with no timeline", function()
        -- the reference is never run: dofile reads no memory
        -- card
        local names = 'if false then dofile("lib.lua") end\n'
        local after = names .. "y = 2\nz = 3\n"
        local writes = 'writefile("main.lua", '
            .. string.format("%q", after) .. ')\n'
        K.reset({
          ["main.lua"] = names .. "cut = 1\n" .. writes,
          ["lib.lua"] = "l = 1\n",
        })
        K.open()
        K.browse_to(2)
        K.keys("lctrl", "delete")
        K.keys("escape")
        K.browse_to(1)
        K.keys("lctrl", "j")
        assert.same("lib.lua", K.file_name())
        change(after)
        assert.same(after, K.file())
        K.keys("escape")
        assert.same("main.lua", K.file_name())
        assert.same(3, K.blocks())
        assert.same(1, K.position())
        assert.truthy(shown():find("z = 3", 1, true))
        K.keys("lctrl", "z")
        assert.same("", K.draft())
        assert.same(after, K.file())
        K.browse_to_end()
        K.type("w = 4")
        K.keys("return")
        assert.is_nil(K.message())
        assert.same(after .. "w = 4\n", K.file())
      end)
    end
  end)
end)
