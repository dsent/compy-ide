-- A run of the project (Ctrl+T, Ctrl+Alt+R) and a visit to
-- another file (Ctrl+J, then Escape) are no leaving of a file
-- (IS1.4, IS1.5, IS6.6): each file comes back as it was, its
-- timeline, its draft's changes and what can be redone
-- included, whatever storage holds meanwhile. The files go
-- when the editor is left, and with their project. Keys only,
-- through tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it

local UNREAD = "Could not read"
local TYPES = { "lua", "txt", "md" }

--- the file of a test in a file of type `ext`
local function named(ext)
  if ext == "lua" then return "main.lua" end
  return "notes." .. ext
end

--- Out and back: a run with Ctrl+T, a run with Ctrl+Alt+R,
--- or a visit to the file the browsed block names
local TRIPS = {
  run = function()
    K.keys("lctrl", "t")
    K.keys("lctrl", "t")
  end,
  restart = function()
    K.keys("lctrl", "lalt", "r")
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

  describe("search", function()
    spec_it("IS1.4 Resume after running a project: a run with "
        .. "Ctrl+Alt+R from search comes back to the file, out of "
        .. "search", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(2)
      K.keys("lctrl", "f")
      assert.same("search", K.ed:get_mode())
      K.keys("lctrl", "lalt", "r")
      assert.are_not.same("editor", K.app_state())
      K.keys("lctrl", "t")
      assert.same("editor", K.app_state())
      assert.same("nav", K.ed:get_mode())
      assert.same(2, K.position())
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

      spec_it("IS1.4 Resume after running a project: in a ."
          .. ext .. " file, with the SD card out at the return, "
          .. "the file comes back and its cut undoes once the "
          .. "card is in", function()
        local name = named(ext)
        local original = "precious = 123\nx = 1\n"
        K.reset({ ["main.lua"] = "", [name] = original })
        K.open(name)
        K.browse_to(1)
        K.keys("lctrl", "delete")
        K.keys("escape")
        K.keys("lctrl", "t")
        K.remove_card()
        K.keys("lctrl", "t")
        assert.same("editor", K.app_state())
        assert.same(name, K.file_name())
        assert.same(1, K.blocks())
        K.keys("lctrl", "z")
        assert.same("", K.draft())
        assert.truthy((K.message() or ""):find(UNREAD, 1, true))
        K.insert_card()
        K.keys("lctrl", "z")
        assert.same("precious = 123", K.draft())
        K.keys("lctrl", "z")
        assert.same(original, K.file(name))
      end)
    end

    spec_it("IS1.4 Resume after running a project: a caller "
        .. "that cannot be read at the return keeps its timeline "
        .. "through the next run", function()
      local original = "precious = 123\ndofile(\"notes.txt\")\n"
      K.reset({ ["main.lua"] = original, ["notes.txt"] = "n\n" })
      K.open()
      K.browse_to(1)
      K.keys("lctrl", "delete")
      K.keys("escape")
      K.browse_to(1)
      K.keys("lctrl", "j")
      K.keys("lctrl", "t")
      K.fail_reads("main.lua")
      K.keys("lctrl", "t")
      assert.same("notes.txt", K.file_name())
      TRIPS.run()
      K.keys("escape")
      assert.same("main.lua", K.file_name())
      K.keys("lctrl", "z")
      assert.truthy((K.message() or ""):find(UNREAD, 1, true))
      K.mend_reads()
      K.keys("lctrl", "z")
      assert.same("precious = 123", K.draft())
      K.keys("lctrl", "z")
      assert.same(original, K.file())
    end)
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

  describe("line endings", function()
    for _, ext in ipairs(TYPES) do
      spec_it("FR3.1 Preserve file structure: in a ." .. ext
          .. " file, a new line redone after a run keeps the "
          .. "ending it was written with", function()
        local name = named(ext)
        local original = "a = 1\r\nb = 2\n"
        K.reset({ ["main.lua"] = "", [name] = original })
        K.open(name)
        K.type("c = 3")
        K.keys("return")
        local accepted = K.file(name)
        assert.same(original .. "c = 3\r\n", accepted)
        K.browse_to(1)
        K.keys("lctrl", "delete")
        K.keys("escape")
        TRIPS.run()
        K.keys("lctrl", "z")
        K.keys("lctrl", "z")
        K.keys("lctrl", "z")
        assert.same(original, K.file(name))
        K.keys("lctrl", "y")
        assert.same(accepted, K.file(name))
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

    spec_it("IS1.1 Open a Lua file: edit() in the console after a "
        .. "run opens the file over the files the run came from",
      function()
        K.reset({
          ["main.lua"] = "x = 1\ny = 2\n",
          ["other.lua"] = "o = 1\n",
        })
        K.open()
        K.browse_to(1)
        K.keys("lctrl", "delete")
        K.keys("escape")
        K.keys("lctrl", "t")
        assert.same("ready", K.app_state())
        K.open("other.lua")
        assert.same("other.lua", K.file_name())
        assert.same("end", K.position())
        K.keys("escape")
        assert.same("main.lua", K.file_name())
        K.keys("lctrl", "z")
        assert.same("x = 1", K.draft())
      end)

    spec_it("IS1.1 Open a Lua file: edit() in the console of the "
        .. "file a run came from shows it as it was", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(1)
      K.keys("lctrl", "delete")
      K.keys("escape")
      K.keys("lctrl", "t")
      K.open()
      assert.same("main.lua", K.file_name())
      assert.same(1, K.ed.model.buffers:length())
      assert.same(1, K.position())
      K.keys("lctrl", "z")
      assert.same("x = 1", K.draft())
    end)
  end)
end)
