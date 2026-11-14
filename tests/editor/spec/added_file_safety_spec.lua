-- The paths that write, overwrite or discard a person's text:
-- opening keeps every line of a file, an accepted change
-- writes only what it changed, storage is written only over
-- what the editor last read or wrote there, and every action
-- stays undoable while the file is open. Keys only, through
-- tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it

--- Pieces of Lua a file is made of: statements, comments
--- trailing code, line comments, long comments with levels,
--- long strings, blank lines
local PIECES = {
  "x = 1",
  "x = 1 -- speed",
  "-- the player",
  "--- doc\n--- more",
  "--[[ a\nb ]]",
  "--[==[ a\n]] b ]==]",
  "--[[ one line ]]",
  "y = 2 --[[ note\nmore note ]]",
  "s = [[\na\n\nb\n]]",
  "function f()\n  -- inside\n  return 1\nend -- done",
  "t = {\n  1, -- one\n  -- two\n  2,\n}",
  "",
  "  ",
}

--- Every file of two pieces, on lines of their own and
--- sharing a line, each also after a `#!` line
--- @return string[]
local function generated()
  local out = { }
  for _, a in ipairs(PIECES) do
    for _, b in ipairs(PIECES) do
      for _, sep in ipairs({ "\n", " " }) do
        local text = a .. sep .. b .. "\n"
        out[#out + 1] = text
        out[#out + 1] = "#!/usr/bin/lua\n" .. text
      end
    end
  end
  return out
end

local function show(s)
  return (string.format("%q", s):gsub("\\\n", "\\n"))
end

describe("text safety #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("opening a Lua file keeps every line", function()
    spec_it("FR3.1 Preserve file structure: a file opened and "
        .. "added to keeps every line it had, unchanged and once",
      function()
        local bad = { }
        for _, text in ipairs(generated()) do
          K.reset({ ["main.lua"] = text })
          K.open()
          K.type("z = 3")
          K.keys("return")
          local want = text .. "z = 3\n"
          if K.file() ~= want then
            bad[#bad + 1] = show(text) .. " -> " .. show(K.file())
          end
          K.keys("escape")
        end
        assert.same({ }, bad)
      end)

    spec_it("FR3.1 Preserve file structure: a line comment "
        .. "after a commented statement opens as a block of its own",
      function()
        K.reset({
          ["main.lua"] = "x = 1 -- speed\n-- the player\ny = 2\n"
        })
        K.open()
        assert.same(3, K.blocks())
        assert.same("browsing", K.state())
        K.browse_to(2)
        K.keys("f2")
        assert.same("replacing", K.state())
        assert.same("-- the player", K.draft())
      end)

    spec_it("IS3.7 Preserve accepted Lua: a file with a long "
        .. "comment after code still refuses text that would stop "
        .. "it loading", function()
        local text = "x = 1 --[[ note\nmore note ]]\ny = 2\n"
        K.reset({ ["main.lua"] = text })
        K.open()
        K.browse_to(2)
        K.type("return 5")
        K.keys("return")
        assert.same(text, K.file())
        assert.same("return 5", K.draft())
        assert.truthy(K.message():find("return", 1, true))
      end)
  end)

  -- A line over the width limit in a multi-line comment: the
  -- block is the comment's own lines, not lines wrapped to the
  -- width, so every block after it stays where it is
  describe("a comment with a line over the limit", function()
    local LONG = "--[[ " .. string.rep("word ", 20)
    local TEXT = LONG .. "\nend ]]\na = 1\nb = 2\nc = 3\n"

    before_each(function()
      K.reset({ ["main.lua"] = TEXT })
      K.open()
    end)

    spec_it("IS5.3 Accept a replacement: the replaced block is "
        .. "the one edited, and the comment is written as it was",
      function()
        K.browse_to(4)
        K.keys("f2")
        assert.same("c = 3", K.draft())
        K.keys("backspace")
        K.type("9")
        K.keys("return")
        assert.same(LONG .. "\nend ]]\na = 1\nb = 2\nc = 9\n",
          K.file())
      end)

    spec_it("IS4.1 Insert before a block: the draft goes in "
        .. "before the browsed block", function()
        K.browse_to(4)
        K.type("z = 0")
        K.keys("return")
        assert.same(LONG .. "\nend ]]\na = 1\nb = 2\nz = 0\nc = 3\n",
          K.file())
      end)

    spec_it("IS4.2 Append after the last block: after a comment "
        .. "with a long line, the draft goes in last", function()
        K.reset({ ["main.lua"] = "--[[\n" .. string.rep("a", 100)
            .. "\n]]\nx = 1\n" })
        K.open()
        K.type("y = 2")
        K.keys("return")
        assert.same("--[[\n" .. string.rep("a", 100)
          .. "\n]]\nx = 1\ny = 2\n", K.file())
      end)

    -- Ruling (round 1 review, finding C-7): Edit on a block
    -- with a line over the limit loads it formatted as far as
    -- the formatter can; Enter refuses with the notice a
    -- submission still over the limit
    spec_it("IS1.3 Handle size limits: Edit loads a comment with "
        .. "a line over the limit formatted, and Enter puts it "
        .. "back so in its own place", function()
        K.browse_to(1)
        K.keys("f2")
        assert.same("replacing", K.state())
        local draft = K.draft()
        assert.are_not.same(LONG .. "\nend ]]", draft)
        for l in draft:gmatch("[^\n]*") do
          assert.is_true(#l <= 64, l)
        end
        K.keys("return")
        assert.same("browsing", K.state())
        assert.same(draft .. "\na = 1\nb = 2\nc = 3\n", K.file())
      end)
  end)

  -- Shift+Ins on a replacement left as it was changes no
  -- file; the draft it retains is still a step of its own
  spec_it("IS6.6 Undo and redo: a draft retained from an "
      .. "unchanged replacement is undone before the action "
      .. "before it", function()
    K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
    K.open()
    K.type("a = 1")
    K.keys("return")
    K.browse_to(2)
    K.keys("f2")
    K.keys("lshift", "insert")
    assert.same("y = 2", K.draft())
    assert.same("inserting", K.state())
    K.keys("lctrl", "z")
    assert.same("", K.draft())
    assert.same("browsing", K.state())
    assert.same("x = 1\ny = 2\na = 1\n", K.file())
    K.keys("lctrl", "z")
    assert.same("x = 1\ny = 2\n", K.file())
    K.keys("lctrl", "y")
    assert.same("x = 1\ny = 2\na = 1\n", K.file())
    K.keys("lctrl", "y")
    assert.same("y = 2", K.draft())
    assert.same("inserting", K.state())
  end)

  -- A test run is no leaving of a file (IS1.4): from a file
  -- reached with Ctrl+J, the run comes back to the same stack
  spec_it("IS1.4 Resume after running a project: a run from a "
      .. "followed file comes back to it, its caller and both "
      .. "timelines", function()
    K.reset({
      ["main.lua"] = "require('lib')\nx = 1\n",
      ["lib.lua"] = "u = 1\n"
    })
    K.open()
    K.type("m = 0")
    K.keys("return")
    K.browse_to(1)
    K.keys("lctrl", "j")
    K.type("v = 2")
    K.keys("return")
    K.keys("lctrl", "t")
    K.keys("lctrl", "t")
    assert.same("editor", K.app_state())
    assert.same("lib.lua", K.file_name())
    K.keys("lctrl", "z")
    assert.same("u = 1\n", K.file("lib.lua"))
    K.keys("escape")
    assert.same("editor", K.app_state())
    assert.same("main.lua", K.file_name())
    assert.same(1, K.position())
    K.keys("lctrl", "z")
    assert.same("require('lib')\nx = 1\n", K.file())
  end)

  describe("the timeline", function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
    end)

    spec_it("IS5.7 Cancel an edit with Escape: a held Escape "
        .. "acts once, so a cut block is not lost by leaving the "
        .. "file", function()
      K.browse_to(1)
      K.keys("lctrl", "delete")
      assert.same("x = 1", K.draft())
      K.hold("escape")
      K.repeat_key("escape")
      K.repeat_key("escape")
      K.release("escape")
      assert.same("editor", K.app_state())
      assert.same("browsing", K.state())
      K.keys("lctrl", "z")
      assert.same("x = 1", K.draft())
      K.keys("lctrl", "z")
      assert.same("x = 1\ny = 2\n", K.file())
    end)

    spec_it("IS6.6 Undo and redo: every accepted change stays "
        .. "undoable while the file is open", function()
      for i = 1, 40 do
        K.type("v" .. i .. " = " .. i)
        K.keys("return")
      end
      for _ = 1, 40 do
        K.keys("lctrl", "z")
      end
      assert.same("x = 1\ny = 2\n", K.file())
    end)

    spec_it("IS6.6 Undo and redo: steps that change no file push "
        .. "no earlier action off the timeline", function()
      K.browse_to(1)
      K.keys("lctrl", "delete")
      K.keys("escape")
      assert.same("y = 2\n", K.file())
      for _ = 1, 20 do
        K.keys("f2")
        K.keys("escape")
      end
      -- each look is an opening and an abort, each a step
      for _ = 1, 40 do
        K.keys("lctrl", "z")
      end
      assert.same("browsing", K.state())
      -- the abort of the cut block's draft, then the cut
      K.keys("lctrl", "z")
      assert.same("x = 1", K.draft())
      K.keys("lctrl", "z")
      assert.same("x = 1\ny = 2\n", K.file())
    end)
  end)

  -- A project's files are written in its own folder alone
  -- (Project.writable_name): a file the editor could never
  -- save is not opened
  describe("a file in a folder", function()
    local CALLER = "require('lib.util')\n"

    before_each(function()
      K.reset({
        ["main.lua"] = CALLER,
        ["lib/util.lua"] = "v = 1\n"
      })
    end)

    spec_it("IS1.5 Follow a file reference: a file in a folder "
        .. "is not opened, with a notice that it cannot be saved",
      function()
        K.open()
        K.browse_to(1)
        K.keys("lctrl", "j")
        assert.same("main.lua", K.file_name())
        assert.same("browsing", K.state())
        assert.truthy(K.message():find("lib/util.lua cannot be saved",
          1, true))
      end)

    spec_it("IS1.2 Admit or refuse a file: edit of a file in a "
        .. "folder is refused in the console", function()
      K.open("lib/util.lua")
      assert.same("ready", K.app_state())
      assert.truthy(K.console_text():find(
        "lib/util.lua cannot be saved", 1, true))
      assert.same("v = 1\n", K.file("lib/util.lua"))
    end)
  end)

  describe("bytes the user did not change", function()
    for _, name in ipairs({ "notes.txt", "notes.md" }) do
      spec_it("IS8.2 Submit text: a line of spaces in " .. name
          .. " is saved as written", function()
        K.reset({ [name] = "" })
        K.open(name)
        K.type("   ")
        K.keys("return")
        assert.same("   \n", K.file(name))
      end)
    end

    spec_it("FR3.1 Preserve file structure: a blank line of "
        .. "spaces in a Lua file is written back as it was",
      function()
        K.reset({ ["main.lua"] = "x = 1\n  \ny = 2\n" })
        K.open()
        K.type("z = 3")
        K.keys("return")
        assert.same("x = 1\n  \ny = 2\nz = 3\n", K.file())
      end)

    spec_it("FR3.1 Preserve file structure: a replaced line in "
        .. "a CRLF file is written with the others, all with LF",
      function()
        K.reset({ ["main.lua"] = "x = 1\r\ny = 2\ny = 3\r\n" })
        K.open()
        K.browse_to(2)
        K.keys("f2", "backspace")
        K.type("9")
        K.keys("return")
        assert.same("x = 1\ny = 9\ny = 3\n", K.file())
      end)
  end)

  -- Back from a text file, the Lua file's draft is read as
  -- Lua again: highlighted, and checked when submitted
  describe("back from a referenced file", function()
    for _, name in ipairs({ "notes.txt", "notes.md" }) do
      spec_it("H-FR2.3 Live syntax highlighting: back from "
          .. name .. ", the field colours Lua again", function()
        K.reset({
          ["main.lua"] = "dofile('" .. name .. "')\n",
          [name] = "hello\n"
        })
        K.open()
        K.browse_to(1)
        K.keys("lctrl", "j")
        assert.same(name, K.file_name())
        K.keys("escape")
        assert.same("main.lua", K.file_name())
        K.type("local answer = 42")
        assert.is_true(1 < K.field_highlight())
        K.keys("escape", "lctrl", "q")
        K.open()
        K.type("local answer = 42")
        assert.is_true(1 < K.field_highlight())
      end)
    end
  end)

  -- No key reaches this: a program's own edit() call, made
  -- through its environment as a running program makes it
  spec_it("FR1.2 Resolve each edit: a program's edit() during "
      .. "an edit is refused, and the cut block stays in the field",
    function()
      K.reset({
        ["main.lua"] = "x = 1\ny = 2\n",
        ["lib.lua"] = "u = 1\n"
      })
      K.open()
      K.browse_to(1)
      K.keys("lctrl", "delete")
      K.cc:get_project_env().edit("lib.lua")
      assert.same("main.lua", K.file_name())
      assert.same("x = 1", K.draft())
      assert.truthy(K.message():find("Finish the text first", 1, true))
    end)

  describe("a line the formatter cannot bring within the limit",
    function()
    local NAME = "v" .. string.rep("a", 70)
    local TEXT = "x = 1\n" .. NAME .. " = 1\ny = 2\n"

    before_each(function()
      K.reset({ ["main.lua"] = TEXT })
      K.open()
      K.browse_to(2)
      K.keys("f2")
    end)

    spec_it("IS1.3 Handle size limits: Edit loads the block "
        .. "formatted as far as it goes, Enter refuses it with the "
        .. "notice, and Escape leaves the file as it was", function()
        assert.same("replacing", K.state())
        assert.same(NAME .. "\n    = 1", K.draft())
        K.keys("return")
        assert.same("replacing", K.state())
        assert.truthy(K.message():find("the limit is 64", 1, true))
        assert.same(TEXT, K.file())
        K.keys("escape")
        assert.same("browsing", K.state())
        assert.same(TEXT, K.file())
      end)

    spec_it("IS1.3 Handle size limits: the block, repaired, is "
        .. "accepted in its own place", function()
        for _ = 1, #K.draft() do
          K.keys("backspace")
        end
        assert.same("", K.draft())
        K.type("v = 1")
        K.keys("return")
        assert.same("browsing", K.state())
        assert.same("x = 1\nv = 1\ny = 2\n", K.file())
      end)
  end)
end)
