-- Requirements FR1 to FR4 and the H requirements (editor
-- principles, ratified): the clauses the tests of
-- fr1_fr2_spec.lua, fr3_structure_spec.lua,
-- r4_orientation_spec.lua and h_requirements_spec.lua leave
-- out. Keys only, through tests/helpers/editor_keys.lua. Edit
-- is F2; cut is Ctrl+Delete; move is Alt+Up and Alt+Down.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local FILE = "x = 1\ny = 2\nz = 3\n"
local MD = "# Title\nsome *em* text\n"

local function open_file(text)
  K.reset({ ["main.lua"] = text or FILE })
  K.open()
end

--- Edit (F2) on block `b`.
local function edit(b)
  K.browse_to(b)
  K.keys("f2")
end

--- Hold `k` through `n` repeats, with Ctrl when `ctrl`.
local function hold(k, n, ctrl)
  if ctrl then
    K.hold("lctrl")
  end
  K.hold(k)
  for _ = 1, n do
    K.repeat_key(k)
  end
  K.release(k)
  if ctrl then
    K.release("lctrl")
  end
end

--- `n` one-line blocks: v1 = 1 to vn = n.
local function many(n)
  local t = { }
  for i = 1, n do
    t[i] = "v" .. i .. " = " .. i .. "\n"
  end
  return table.concat(t)
end

describe("requirements, added #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("FR1", function()
    before_each(function()
      open_file()
    end)

    spec_it("FR1.3 Keep the replacement target: after a " ..
        "switch, only undoing it moves the target back",
        function()
      edit(1)
      K.keys("lctrl", "down")
      K.keys("lctrl", "down")
      K.keys("f2")
      K.keys("lctrl", "up")
      K.keys("lctrl", "up")
      local browsed = {
        K.position(),
        K.target(),
        K.draft()
      }
      K.keys("lctrl", "z")
      assert.same({
        1,
        3,
        "z = 3"
      }, browsed)
      assert.same(1, K.target())
      assert.same("x = 1", K.draft())
      assert.same(FILE, K.file())
    end)

    spec_it("FR1.3 Keep the replacement target: browsing " ..
        "with a modified draft leaves the target", function()
      edit(2)
      K.type("0")
      K.keys("lctrl", "up")
      K.keys("lctrl", "down")
      K.keys("lctrl", "down")
      assert.same(3, K.position())
      assert.same(2, K.target())
      assert.same("y = 20", K.draft())
      assert.same(FILE, K.file())
    end)

    spec_it("FR1.5 Cursor at the end of loaded text: after " ..
        "Edit reloads the target", function()
      edit(2)
      K.type("00")
      K.keys("lctrl", "home")
      K.keys("f2")
      assert.same("y = 2", K.draft())
      assert.same({
        1,
        6
      }, { K.cursor() })
    end)

    spec_it("FR1.5 Cursor at the end of loaded text: after " ..
        "Edit switches the target", function()
      open_file("x = 1\nlonger = 22\n")
      edit(1)
      K.keys("lctrl", "down")
      K.keys("f2")
      assert.same("longer = 22", K.draft())
      assert.same({
        1,
        12
      }, { K.cursor() })
    end)

    spec_it("FR1.7 Explicit block removal: Backspace held " ..
        "past the start of a draft leaves the file alone",
        function()
      K.browse_to(2)
      K.type("abc")
      hold("backspace", 12)
      assert.same("", K.draft())
      assert.same(FILE, K.file())
      assert.same(3, K.blocks())
      assert.same(2, K.position())
    end)

    spec_it("FR1.7 Explicit block removal: Backspace held " ..
        "through a replacement draft leaves the target",
        function()
      edit(2)
      hold("backspace", 12)
      assert.same("", K.draft())
      assert.same(2, K.target())
      assert.same(FILE, K.file())
      assert.same(3, K.blocks())
    end)

    spec_it("FR1.7 Explicit block removal: Delete held at " ..
        "the end of a draft leaves the file alone", function()
      K.browse_to(2)
      K.type("abc")
      hold("delete", 12)
      assert.same("abc", K.draft())
      assert.same(FILE, K.file())
      assert.same(2, K.position())
    end)
  end)

  describe("FR2", function()
    before_each(function()
      open_file()
    end)

    spec_it("FR2.1 Quickly abort an edit: one Escape drops " ..
        "a valid insertion draft", function()
      K.browse_to(2)
      K.type("a = 1")
      K.keys("escape")
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same(2, K.position())
      assert.same("editor", K.app_state())
      assert.same(FILE, K.file())
    end)

    spec_it("FR2.1 Quickly abort an edit: one Escape drops " ..
        "an unmodified replacement", function()
      edit(2)
      K.keys("escape")
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("", K.draft())
      assert.same("editor", K.app_state())
      assert.same(FILE, K.file())
    end)

    spec_it("FR2.2 Leave an edit by submitting: Enter leaves "
        .. "a replacement for the browsing state", function()
      edit(2)
      K.type("0")
      K.keys("return")
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("x = 1\ny = 20\nz = 3\n", K.file())
      assert.same("editor", K.app_state())
    end)

    spec_it("FR2.2 Leave an edit by submitting: Enter leaves "
        .. "an unmodified replacement too", function()
      edit(2)
      K.keys("return")
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("", K.draft())
      assert.same(FILE, K.file())
    end)

    spec_it("FR2.4 Valid submissions only: a refused " ..
        "insertion stays an edit until it is aborted", function(
      
    )
      K.type("a = = 1")
      K.keys("return")
      local refused = {
        K.state(),
        K.draft(),
        K.file(),
        K.message() ~= nil
      }
      -- the parser's message shows (NFR4.3); it blocks
      -- nothing, and one Escape aborts (IS5.7)
      K.keys("escape")
      assert.same({
        "inserting",
        "a = = 1",
        FILE,
        true
      }, refused)
      assert.is_nil(K.message())
      assert.same("browsing", K.state())
      assert.same("editor", K.app_state())
      assert.same(FILE, K.file())
    end)

    spec_it("FR2.4 Valid submissions only: a refused " ..
        "replacement stays one until it is aborted", function()
      edit(2)
      K.type(" = 3")
      K.keys("return")
      K.keys("return")
      local refused = {
        K.state(),
        K.target(),
        K.draft(),
        K.file(),
        K.message() ~= nil
      }
      -- the parser's message shows (NFR4.3); it blocks
      -- nothing, and one Escape aborts (IS5.7)
      K.keys("escape")
      assert.same({
        "replacing",
        2,
        "y = 2 = 3",
        FILE,
        true
      }, refused)
      assert.is_nil(K.message())
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("editor", K.app_state())
      assert.same(FILE, K.file())
    end)

    spec_it("FR2.8 Take back an accepted change: a cut is " ..
        "taken back with one press and redone with one",
        function()
      K.browse_to(2)
      K.keys("lctrl", "delete")
      local cut = K.file()
      K.keys("lctrl", "z")
      local back = K.file()
      K.keys("lctrl", "y")
      assert.same("x = 1\nz = 3\n", cut)
      assert.same(FILE, back)
      assert.same(cut, K.file())
    end)

    spec_it("FR2.8 Take back an accepted change: a move is " ..
        "taken back with one press and redone with one",
        function()
      K.browse_to(2)
      K.keys("lalt", "down")
      local moved = K.file()
      K.keys("lctrl", "z")
      local back = K.file()
      K.keys("lctrl", "y")
      assert.same("x = 1\nz = 3\ny = 2\n", moved)
      assert.same(FILE, back)
      assert.same(moved, K.file())
    end)

    spec_it("FR2.8 Take back an accepted change: an abort " ..
        "is taken back with one press and redone with one",
        function()
      K.type("a = = 1")
      K.keys("escape")
      local aborted = K.draft()
      K.keys("lctrl", "z")
      local back = K.draft()
      K.keys("lctrl", "y")
      assert.same("", aborted)
      assert.same("a = = 1", back)
      assert.same("", K.draft())
      assert.same(FILE, K.file())
    end)
  end)

  describe("FR2.7", function()
    spec_it("FR2.7 Step back from a file with Escape: from " ..
        "a followed file, back to the caller's position",
        function()
      K.reset({
        ["main.lua"] = "x = 1\nlocal m = require(\"mod\")\n" ..
            "z = 3\n",
        ["mod.lua"] = "y = 2\n"
      })
      K.open()
      K.browse_to(2)
      K.keys("lctrl", "j")
      local followed = K.file_name()
      K.keys("escape")
      assert.same("mod.lua", followed)
      assert.same("editor", K.app_state())
      assert.same("main.lua", K.file_name())
      assert.same(2, K.position())
      assert.same("browsing", K.state())
      assert.same(K.PROJECT, K.cc.model.projects.current.name)
    end)
  end)

  describe("FR3", function()
    spec_it("FR3.1 Preserve file structure: a Markdown file "
        .. "keeps one line per block, each terminated",
        function()
      K.reset({ ["b.md"] = MD })
      K.open("b.md")
      K.type_lines({
        "- a",
        "",
        "- b"
      })
      K.keys("return")
      assert.same(MD .. "- a\n\n- b\n", K.file("b.md"))
      assert.same(5, K.blocks())
    end)

    spec_it("FR3.1 Preserve file structure: an accepted " ..
        "replacement leaves whole blocks, each terminated",
        function()
      open_file()
      edit(3)
      K.type("; w = 4")
      K.keys("return")
      assert.same("x = 1\ny = 2\nz = 3\nw = 4\n", K.file())
      assert.same(4, K.blocks())
    end)

    spec_it("FR3.1 Preserve file structure: cutting the " ..
        "last block leaves the rest terminated", function()
      open_file()
      K.browse_to(3)
      K.keys("lctrl", "delete")
      assert.same("x = 1\ny = 2\n", K.file())
      assert.same(2, K.blocks())
      assert.same("end", K.position())
    end)

    spec_it("FR3.5 Advance position for sequential entry: " ..
        "after a replacement that splits, the next follows",
        function()
      open_file()
      edit(2)
      K.type("; a = 1; b = 2")
      K.keys("return")
      local position = K.position()
      K.type("c = 3")
      K.keys("return")
      assert.same(5, position)
      assert.same(
        "x = 1\ny = 2\na = 1\nb = 2\nc = 3\nz = 3\n",
        K.file()
      )
      assert.same("browsing", K.state())
    end)

    spec_it("FR3.5 Advance position for sequential entry: " ..
        "insertions before a block stay in typing order",
        function()
      open_file()
      K.browse_to(2)
      K.type("a = 1")
      K.keys("return")
      K.type("b = 2")
      K.keys("return")
      assert.same(
        "x = 1\na = 1\nb = 2\ny = 2\nz = 3\n",
        K.file()
      )
      assert.same(4, K.position())
    end)
  end)

  describe("R4", function()
    spec_it("NFR4.4 Post-submission orientation: after a " ..
        "replacement, the white highlight is on the next",
        function()
      -- taller than the view, so that what stays in view is
      -- the editor's choice
      open_file(many(60))
      edit(30)
      K.type("0")
      K.keys("return")
      local h = K.highlights()
      assert.same(31, K.position())
      assert.same({ 31 }, h.white)
      assert.same({ }, h.yellow)
      assert.truthy(K.file():find("\nv30 = 300\nv31 = 31\n", 1, true))
      assert.is_true(K.in_view(30))
      assert.is_true(K.in_view(31))
    end)

    spec_it("NFR4.4 Post-submission orientation: after an " ..
        "insertion, the highlight stays on its block", function(
      
    )
      open_file(many(60))
      K.browse_to(30)
      K.type("a = 1")
      K.keys("return")
      local h = K.highlights()
      assert.same(31, K.position())
      assert.same({ 31 }, h.white)
      assert.is_true(K.in_view(30))
      assert.is_true(K.in_view(31))
    end)

    spec_it("FR4.6 Visible project and context on the status "
        .. "line: in a Markdown file, name, project and state",
        function()
      K.reset({ ["b.md"] = MD })
      K.open("b.md")
      K.browse_to(1)
      local browsing = K.status_text()
      K.keys("f2")
      local replacing = K.status_text()
      assert.truthy(browsing:find("b.md", 1, true))
      assert.truthy(browsing:find(K.PROJECT, 1, true))
      assert.truthy(replacing:find("b.md", 1, true))
      assert.are_not.same(browsing, replacing)
    end)

    spec_it("FR4.6 Visible project and context on the status "
        .. "line: the replacing state, its target out of view",
        function()
      open_file(many(60))
      edit(60)
      local browsed = pcall(K.browse_to, 1)
      local replacing = K.status_text()
      local in_view = K.in_view(60)
      K.keys("escape")
      assert.is_true(browsed)
      assert.is_false(in_view)
      assert.same(1, K.position())
      assert.are_not.same(replacing, K.status_text())
    end)
  end)

  describe("H requirements", function()
    spec_it("H-FR5.1 Supported document types: a binary " ..
        "file is refused with a console notice", function()
      K.reset({
        ["main.lua"] = FILE,
        ["photo.jpg"] = "\255\216\255\224JFIF\255\219"
      })
      K.open("photo.jpg")
      assert.same("ready", K.app_state())
      assert.truthy(K.console_text():find("photo.jpg", 1, true))
    end)

    spec_it("H-NFR3.2 Avoid sudden disappearance: a held cut "
        .. "takes one block, no more", function()
      open_file("x = 1\n\n\ny = 2\nz = 3\nw = 4\n")
      K.browse_to(4)
      hold("delete", 8, true)
      assert.same("x = 1\n\n\nz = 3\nw = 4\n", K.file())
      assert.same("y = 2", K.draft())
    end)

    spec_it("H-NFR1.1 Limit typing loss: a draft dropped " ..
        "with Escape comes back once later actions are undone",
        function()
      open_file()
      K.type("a = = 1")
      K.keys("escape")
      K.browse_to(2)
      K.keys("lalt", "up")
      local moved = K.file()
      K.keys("lctrl", "z")
      local unmoved = {
        K.file(),
        K.draft()
      }
      K.keys("lctrl", "z")
      assert.same("y = 2\nx = 1\nz = 3\n", moved)
      assert.same({
        FILE,
        ""
      }, unmoved)
      assert.same("a = = 1", K.draft())
      assert.same(FILE, K.file())
    end)
  end)
end)
