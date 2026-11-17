-- Selection in the draft, without the clipboard (the
-- maintainer's ruling of November 17, 2026, which changes
-- "Selection is off until the clipboard is designed" in part):
-- in the one text field, the console's, the file editor's and
-- a program's alike, Shift with a movement key and a drag of
-- the mouse select a part of the draft; typing replaces it,
-- Delete and Backspace remove it, each as one step Ctrl+Z
-- takes back with the selection; a plain movement or a click
-- clears it. Nothing copies, cuts or pastes. Keys and the
-- mouse only, through the K helper and the production
-- gateway.

local F = require("tests.helpers.input_fixture")
local K = require("tests.helpers.editor_keys")
local Layout = require("view.layout")

local LINES = { "one two", "three four" }

--- Each owner's field, its draft LINES; returns the field (a
--- UserInputController).
local OWNERS = {
  console = function()
    K.reset()
    return K.cc.input
  end,
  editor = function()
    K.reset({ ["notes.txt"] = "" })
    K.cc.cfg.editor = { mouse_enabled = true }
    K.open("notes.txt")
    return K.ed.input
  end,
  program = function()
    K.reset()
    F.activate_project()
    return F.show_widget({ text = "" })
  end,
}
local ORDER = { "console", "editor", "program" }

--- @param owner string
--- @param lines string[]?
--- @param l integer?
--- @param c integer?
local function field_of(owner, lines, l, c)
  local f = OWNERS[owner]()
  f:set_text(lines or LINES)
  f:set_cursor_pos(l or 1, c or 1)
  return f
end

local function text(f) return table.concat(f:get_text(), "\n") end

--- the selected text, nil without a selection
local function selected(f)
  local m = f.model
  if not m:has_selection() then return nil end
  return table.concat(m:get_selection().text, "\n")
end

local function cursor(f) return { f:get_cursor_pos() } end

--- each owner in turn
local function in_every_field(name, case)
  it(name .. ", in every field", function()
    for _, owner in ipairs(ORDER) do case(owner) end
  end)
end

describe("selection in the draft #input", function()
  after_each(function()
    K.cc.cfg.editor = nil
    K.cleanup()
  end)

  describe("Shift with a movement key", function()
    in_every_field("Shift+Right selects a character per press",
      function(owner)
        local f = field_of(owner, nil, 1, 1)
        K.keys("lshift", "right")
        K.keys("lshift", "right")
        assert.same("on", selected(f), owner)
        assert.same({ 1, 3 }, cursor(f), owner)
      end)

    in_every_field("Shift+Left selects back over a line break",
      function(owner)
        local f = field_of(owner, nil, 2, 3)
        for _ = 1, 4 do K.keys("lshift", "left") end
        assert.same("o\nth", selected(f), owner)
        assert.same({ 1, 7 }, cursor(f), owner)
      end)

    in_every_field("Shift+Home and Shift+End select to the row's "
        .. "ends", function(owner)
      local f = field_of(owner, nil, 2, 4)
      K.keys("lshift", "home")
      assert.same("thr", selected(f), owner)
      K.keys("right")
      f:set_cursor_pos(2, 4)
      K.keys("lshift", "end")
      assert.same("ee four", selected(f), owner)
    end)

    in_every_field("Ctrl+Shift+Left and Right select by word",
      function(owner)
        local f = field_of(owner, nil, 2, 11)
        K.keys("lctrl", "lshift", "left")
        assert.same("four", selected(f), owner)
        K.keys("lctrl", "lshift", "left")
        assert.same("three four", selected(f), owner)
        -- back to the end of "three"
        K.keys("lctrl", "lshift", "right")
        assert.same(" four", selected(f), owner)
      end)

    in_every_field("Ctrl+Shift+Home and End select to the draft's "
        .. "ends", function(owner)
      local f = field_of(owner, nil, 1, 4)
      K.keys("lctrl", "lshift", "end")
      assert.same(" two\nthree four", selected(f), owner)
      K.keys("lctrl", "lshift", "home")
      assert.same("one", selected(f), owner)
    end)

    in_every_field("Shift+Down and Shift+Up select by the draft's "
        .. "rows, a wrapped line's included", function(owner)
      local long = string.rep("a", 70)
      local f = field_of(owner, { long, "end" }, 1, 3)
      K.keys("lshift", "down")
      -- the wrapped line's second row, the same offset
      assert.same(string.rep("a", 64), selected(f), owner)
      K.keys("lshift", "down")
      assert.same(string.rep("a", 68) .. "\nen", selected(f),
        owner)
      K.keys("lshift", "up")
      K.keys("lshift", "up")
      assert.is_nil(selected(f), owner)
    end)

    it("Shift+Up on the console's first row selects to its start "
        .. "and recalls no history", function()
      K.reset()
      K.type("print(1)")
      K.keys("return")
      local f = K.cc.input
      f:set_text({ "abc" })
      f:set_cursor_pos(1, 4)
      K.keys("lshift", "up")
      assert.same("abc", selected(f))
      assert.same("abc", text(f))
    end)

    in_every_field("a plain movement clears the selection and moves "
        .. "from the cursor", function(owner)
      local f = field_of(owner, nil, 1, 1)
      K.keys("lshift", "right")
      K.keys("lshift", "right")
      K.keys("right")
      assert.is_nil(selected(f), owner)
      assert.same({ 1, 4 }, cursor(f), owner)
    end)
  end)

  describe("what replaces and removes it", function()
    in_every_field("typing replaces the selection, and Ctrl+Z takes "
        .. "it back with the selection", function(owner)
      local f = field_of(owner, nil, 1, 5)
      K.keys("lshift", "end")
      K.type("X")
      assert.same("one X\nthree four", text(f), owner)
      assert.same({ 1, 6 }, cursor(f), owner)
      K.keys("lctrl", "z")
      assert.same("one two\nthree four", text(f), owner)
      assert.same("two", selected(f), owner)
    end)

    in_every_field("Backspace removes the selection alone", function(owner)
      local f = field_of(owner, nil, 2, 1)
      K.keys("lshift", "left")
      K.keys("lshift", "left")
      K.keys("backspace")
      assert.same("one twthree four", text(f), owner)
      assert.same({ 1, 7 }, cursor(f), owner)
      K.keys("lctrl", "z")
      assert.same("one two\nthree four", text(f), owner)
    end)

    in_every_field("Delete removes the selection alone", function(owner)
      local f = field_of(owner, nil, 1, 1)
      K.keys("lctrl", "lshift", "right")
      K.keys("delete")
      assert.same(" two\nthree four", text(f), owner)
      assert.same({ 1, 1 }, cursor(f), owner)
    end)

    in_every_field("Ctrl+Backspace, Ctrl+W and Ctrl+K remove the "
        .. "selection alone", function(owner)
      for _, keys in ipairs({ { "lctrl", "backspace" },
        { "lctrl", "w" }, { "lctrl", "k" } }) do
        local f = field_of(owner, nil, 2, 7)
        K.keys("lshift", "right")
        K.keys(unpack(keys))
        assert.same("one two\nthree our", text(f), owner)
      end
    end)

    in_every_field("Shift+Enter replaces the selection with a line "
        .. "break", function(owner)
      local f = field_of(owner, nil, 1, 4)
      K.keys("lshift", "right")
      K.keys("lshift", "return")
      assert.same("one\ntwo\nthree four", text(f), owner)
    end)
  end)

  describe("the mouse", function()
    --- the point on the screen of column `col` of the field's
    --- shown row `row_from_bottom` (0, its last)
    local function at(f, row_from_bottom, col)
      local v = f.model.cfg.view
      local bottom = love.graphics.getHeight() - Layout(v).bottom
      return v.fw * (col - 1 + 0.2),
          bottom - v.fh * (row_from_bottom + 0.5)
    end

    in_every_field("a drag selects from where it began", function(owner)
      local f = field_of(owner, nil, 1, 1)
      local x, y = at(f, 1, 2)
      local x2, y2 = at(f, 0, 3)
      F.set_mouse_down(true)
      F.session.mousepressed(x, y, 1, false, 1)
      F.session.mousemoved(x2, y2, x2 - x, y2 - y, false)
      F.session.mousereleased(x2, y2, 1, false, 1)
      F.set_mouse_down(false)
      K.frame()
      assert.same("ne two\nth", selected(f), owner)
      assert.same({ 2, 3 }, cursor(f), owner)
    end)

    in_every_field("a click clears the selection and places the "
        .. "cursor", function(owner)
      local f = field_of(owner, nil, 1, 1)
      K.keys("lshift", "end")
      local x, y = at(f, 0, 4)
      F.session.mousepressed(x, y, 1, false, 1)
      F.session.mousereleased(x, y, 1, false, 1)
      K.frame()
      assert.is_nil(selected(f), owner)
      assert.same({ 2, 4 }, cursor(f), owner)
    end)
  end)

  describe("the other keys keep their meaning", function()
    it("Enter runs the console's whole line", function()
      K.reset()
      K.type("sel_x = 41 + 1")
      K.keys("lshift", "home")
      K.keys("return")
      assert.same(42, K.cc:get_project_env().sel_x)
    end)

    it("Escape clears the console's line", function()
      K.reset()
      K.type("abc")
      K.keys("lshift", "left")
      K.keys("escape")
      assert.same("", K.console_draft())
    end)

    it("in the editor, Escape drops the edit and Enter submits "
        .. "the whole draft", function()
      K.reset({ ["notes.txt"] = "a\n" })
      K.open("notes.txt")
      K.type("bcd")
      K.keys("lshift", "left")
      K.keys("return")
      assert.same("a\nbcd\n", K.file("notes.txt"))
      K.type("xyz")
      K.keys("lshift", "home")
      K.keys("escape")
      assert.same("", K.draft())
      assert.same("browsing", K.state())
    end)

    it("in the editor, Ctrl+Ins copies the block in at the cursor, "
        .. "as it does with no selection, and replaces none",
      function()
        K.reset({ ["notes.txt"] = "a\nb\n" })
        K.open("notes.txt")
        K.browse_to(1)
        K.type("xyz")
        K.keys("lshift", "left")
        K.keys("lctrl", "insert")
        assert.same("xy\na\nz", K.draft())
        assert.is_nil(selected(K.ed.input))
      end)

    it("in the editor, Shift+Ins submits the whole draft and keeps "
        .. "it", function()
      K.reset({ ["notes.txt"] = "a\n" })
      K.open("notes.txt")
      K.type("xyz")
      K.keys("lshift", "left")
      K.keys("lshift", "insert")
      assert.same("a\nxyz\n", K.file("notes.txt"))
      assert.same("xyz", K.draft())
    end)

    it("in the editor, Ctrl+Delete is refused during the edit and "
        .. "leaves the selection", function()
      K.reset({ ["notes.txt"] = "a\n" })
      K.open("notes.txt")
      K.type("xyz")
      K.keys("lshift", "left")
      K.keys("lctrl", "delete")
      assert.same("xyz", K.draft())
      assert.is_not_nil(K.message())
      assert.same("z", selected(K.ed.input))
    end)

    in_every_field("Shift+Delete removes nothing and cuts nothing",
      function(owner)
        local f = field_of(owner, nil, 1, 1)
        K.keys("lshift", "right")
        K.keys("lshift", "delete")
        assert.same("one two\nthree four", text(f), owner)
      end)
  end)
end)
