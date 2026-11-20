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
  --- a program's field that shows one row, and three: the
  --- lines past them hidden, the field scrolled to the cursor
  ["program, 1 row"] = function()
    K.reset()
    F.activate_project()
    return F.show_widget({ text = "", max_rows = 1 })
  end,
  ["program, 3 rows"] = function()
    K.reset()
    F.activate_project()
    return F.show_widget({ text = "", max_rows = 3 })
  end,
}
local ORDER = { "console", "editor", "program",
  "program, 1 row", "program, 3 rows" }

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

--- the fields that show this spec's short drafts whole: a
--- click in them finds a row of every line
local WHOLE = { "console", "editor", "program", "program, 3 rows" }

--- each of `owners` in turn
local function in_every_field_of(owners, name, case)
  it(name .. ", in every field", function()
    for _, owner in ipairs(owners) do case(owner) end
  end)
end

local function in_every_field(name, case)
  in_every_field_of(ORDER, name, case)
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

  describe("Ctrl+A", function()
    in_every_field("selects the whole draft from the middle, cursor at the "
        .. "end", function(owner)
      local f = field_of(owner, nil, 1, 4)
      K.keys("lctrl", "a")
      assert.same("one two\nthree four", selected(f), owner)
      assert.same({ 2, 11 }, cursor(f), owner)
    end)

    in_every_field("replaces an existing selection with the whole draft",
      function(owner)
        local f = field_of(owner, nil, 1, 5)
        K.keys("lshift", "right")
        K.keys("lshift", "right")
        assert.same("tw", selected(f), owner)
        K.keys("lctrl", "a")
        assert.same("one two\nthree four", selected(f), owner)
        assert.same({ 2, 11 }, cursor(f), owner)
      end)

    in_every_field("does nothing on an empty field", function(owner)
      local f = field_of(owner, { "" }, 1, 1)
      K.keys("lctrl", "a")
      assert.is_nil(selected(f), owner)
      assert.same("", text(f), owner)
      assert.same({ 1, 1 }, cursor(f), owner)
    end)

    in_every_field("acts once when held", function(owner)
      local f = field_of(owner, nil, 1, 4)
      K.hold("lctrl")
      K.hold("a")
      assert.same("one two\nthree four", selected(f), owner)
      assert.same({ 2, 11 }, cursor(f), owner)
      -- keep 'a' held so the surface's pressed record stays set;
      -- clear and move with plain Left, then repeat Ctrl+A
      K.release("lctrl")
      K.keys("left")
      assert.is_nil(selected(f), owner)
      assert.same({ 2, 10 }, cursor(f), owner)
      K.hold("lctrl")
      K.repeat_key("a")
      K.repeat_key("a")
      K.release("a")
      K.release("lctrl")
      assert.is_nil(selected(f), owner)
      assert.same({ 2, 10 }, cursor(f), owner)
    end)

    in_every_field("lets typing replace the whole draft", function(owner)
      local f = field_of(owner, nil, 1, 4)
      K.keys("lctrl", "a")
      K.type("X")
      assert.same("X", text(f), owner)
      assert.is_nil(selected(f), owner)
      assert.same({ 1, 2 }, cursor(f), owner)
    end)

    in_every_field("types no letter", function(owner)
      local f = field_of(owner, nil, 1, 4)
      K.keys("lctrl", "a")
      assert.same("one two\nthree four", text(f), owner)
      -- as on a Compy, where the chord's letter also arrives as text
      K.hold("lctrl")
      F.session.press("a")
      F.session.type("a")
      F.session.release("a")
      K.release("lctrl")
      assert.same("one two\nthree four", text(f), owner)
      assert.same("one two\nthree four", selected(f), owner)
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
      assert.same("one \nthree four", text(f), owner)
      K.keys("lctrl", "z")
      assert.same("one two\nthree four", text(f), owner)
      assert.same("two", selected(f), owner)
    end)

    --- the device run's point D (the ruling of November 17,
    --- 2026): typing over a selection is two steps, the removal
    --- and then the typing
    in_every_field("typing over a selection is two steps: the "
        .. "typing, then the removal", function(owner)
      local f = field_of(owner, { "hello world" }, 1, 12)
      K.keys("lctrl", "lshift", "left")
      assert.same("world", selected(f), owner)
      K.type("there")
      assert.same("hello there", text(f), owner)
      K.keys("lctrl", "z")
      assert.same("hello ", text(f), owner)
      assert.is_nil(selected(f), owner)
      K.keys("lctrl", "z")
      assert.same("hello world", text(f), owner)
      assert.same("world", selected(f), owner)
      K.keys("lctrl", "y")
      assert.same("hello ", text(f), owner)
      K.keys("lctrl", "y")
      assert.same("hello there", text(f), owner)
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
      --- two steps, as typing over a selection
      K.keys("lctrl", "z")
      assert.same("onetwo\nthree four", text(f), owner)
      K.keys("lctrl", "z")
      assert.same("one two\nthree four", text(f), owner)
      assert.same(" ", selected(f), owner)
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
    --- the cases click rows of every line; the one-row field
    --- is input_field_rows_spec's
    local function in_every_field(name, case)
      in_every_field_of(WHOLE, name, case)
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

    --- the device run's point E: press, one move and release in
    --- one frame, where the button's state read during the move
    --- already says it is up (LÖVE reads it as of the last event
    --- taken from the system, the release)
    in_every_field("a drag of one motion in one frame selects from "
        .. "the press to the release", function(owner)
      local f = field_of(owner, { "hello world and more" }, 1, 21)
      local x, y = at(f, 0, 3)
      local x2 = at(f, 0, 8)
      F.set_mouse_down(false)
      F.session.mousepressed(x, y, 1, false, 1)
      F.session.mousemoved(x2, y, x2 - x, 0, false)
      F.session.mousereleased(x2, y, 1, false, 1)
      K.frame()
      assert.same("llo w", selected(f), owner)
      assert.same({ 1, 8 }, cursor(f), owner)
    end)

    --- the quick drag measured on a Compy on November 18, 2026:
    --- the release reaches the system after a frame's events are
    --- taken and before its move is handled, so the move reads the
    --- button up, and the release itself is handled a frame later
    in_every_field("a quick drag whose release comes a frame after "
        .. "its move selects from the press to the release",
      function(owner)
        local f = field_of(owner, { "hello world and more" }, 1, 21)
        local x, y = at(f, 0, 3)
        local x2 = at(f, 0, 8)
        F.set_mouse_down(true)
        F.session.mousepressed(x, y, 1, false, 1)
        F.set_mouse_down(false)
        F.session.mousemoved(x2, y, x2 - x, 0, false)
        K.frame()
        F.session.mousereleased(x2, y, 1, false, 1)
        K.frame()
        assert.same("llo w", selected(f), owner)
        assert.same({ 1, 8 }, cursor(f), owner)
      end)

    --- review s4's first finding
    in_every_field("a drag brought back to its press selects "
        .. "nothing", function(owner)
      local f = field_of(owner, { "abcdef" }, 1, 7)
      local x, y = at(f, 0, 2)
      local x2 = at(f, 0, 5)
      F.set_mouse_down(true)
      F.session.mousepressed(x, y, 1, false, 1)
      F.session.mousemoved(x2, y, x2 - x, 0, false)
      assert.same("bcd", selected(f), owner)
      F.session.mousemoved(x, y, x - x2, 0, false)
      F.set_mouse_down(false)
      F.session.mousereleased(x, y, 1, false, 1)
      K.frame()
      assert.is_nil(selected(f), owner)
      assert.same({ 1, 2 }, cursor(f), owner)
    end)

    --- review s4's second finding: a release the field never saw,
    --- the button seen up, then a press elsewhere and a drag in
    in_every_field("a drag whose release went unseen does not come "
        .. "back with a later press elsewhere", function(owner)
      local f = field_of(owner, { "abcdef" }, 1, 7)
      local x, y = at(f, 0, 2)
      local x2 = at(f, 0, 5)
      F.set_mouse_down(true)
      f:mousepressed(x, y, 1)
      F.set_mouse_down(false)
      f:mousemoved(x, y, 0, 0, false)
      K.frame()
      F.set_mouse_down(true)
      f:mousemoved(x2, y, x2 - x, 0, false)
      F.set_mouse_down(false)
      f:mousereleased(x2, y, 1)
      assert.is_nil(selected(f), owner)
    end)

    --- review s4's third finding: the key card comes up during a
    --- drag in the editor; the moves under it are held back, and
    --- the release that balances the press selects nothing
    --- review q1: the editor's field takes another file's model
    --- while the release is withheld; the new draft's revision
    --- may equal the one the drag began on
    it("a release after the editor's field took another file's "
        .. "draft selects nothing", function()
      K.reset({ ["main.lua"] = 'require("b")\n',
        ["b.lua"] = "local b = 2\n" })
      K.cc.cfg.editor = { mouse_enabled = true }
      K.open("main.lua")
      K.browse_to(1)
      K.keys("f2")
      local f = K.ed.input
      local before = f.model
      local x, y = at(f, 0, 2)
      local x2 = at(f, 0, 5)
      F.set_mouse_down(true)
      F.session.mousepressed(x, y, 1, false, 1)
      F.set_mouse_down(false)
      F.session.mousemoved(x2, y, x2 - x, 0, false)
      K.frame()
      K.keys("escape")
      K.keys("lctrl", "j")
      K.browse_to(1)
      K.keys("f2")
      assert.are_not.equal(before, f.model)
      F.session.mousereleased(x2, y, 1, false, 1)
      assert.is_nil(selected(f))
    end)

    it("a release under the key card selects nothing", function()
      local f = field_of("editor", { "abcdef" }, 1, 7)
      local x, y = at(f, 0, 2)
      local x2 = at(f, 0, 5)
      F.set_mouse_down(true)
      F.session.mousepressed(x, y, 1, false, 1)
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      F.session.mousemoved(x2, y, x2 - x, 0, false)
      F.set_mouse_down(false)
      F.session.mousereleased(x2, y, 1, false, 1)
      K.release("f1")
      assert.is_nil(selected(f))
      assert.same({ 1, 2 }, cursor(f))
    end)

    --- the probe of the review's round s4 limit: in a program's
    --- field the program's own hooks take the field's release and
    --- a later press; a release in a later frame at the cell the
    --- pointer passed with the button up selects nothing
    it("a program's field selects nothing from a release in a later"
      .. " frame than its move with the button up", function()
        K.reset()
        local input = F.activate_project()
        local w = F.show_widget({ text = "" })
        w:set_text({ "abcdef" })
        local x, y = at(w, 0, 2)
        local x2 = at(w, 0, 5)
        local takes = 0
        input.hooks.mousereleased = function()
          takes = takes + 1
          return takes == 1
        end
        input.hooks.mousepressed = function(_, py) return py < 50 end
        F.set_mouse_down(true)
        F.session.mousepressed(x, y, 1, false, 1)
        F.set_mouse_down(false)
        F.session.mousereleased(x, y, 1, false, 1)
        F.session.mousemoved(x2, y, x2 - x, 0, false)
        K.frame()
        F.set_mouse_down(true)
        F.session.mousepressed(x2, 10, 1, false, 1)
        F.set_mouse_down(false)
        F.session.mousereleased(x2, y, 1, false, 1)
        assert.is_nil(selected(w))
      end)

    --- review s5: the field saw the button up in an earlier frame
    --- (its release went to the program's hook); a later quick
    --- drag of one motion, its press taken by the program too,
    --- does not finish the old drag
    it("a program's field drops a drag whose button it saw up in an"
      .. " earlier frame", function()
        K.reset()
        local input = F.activate_project()
        local w = F.show_widget({ text = "" })
        w:set_text({ "abcdef" })
        local x, y = at(w, 0, 2)
        local x2 = at(w, 0, 5)
        local field_top = y - w.model.cfg.view.fh / 2
        local canvas_y = y - w.model.cfg.view.fh
        input.hooks.mousepressed = function(_, py) return py < field_top end
        input.hooks.mousereleased = function(_, py)
          return py < field_top
        end
        F.set_mouse_down(true)
        F.session.mousepressed(x, y, 1, false, 1)
        F.session.mousemoved(x, canvas_y, 0, canvas_y - y, false)
        K.frame()
        F.set_mouse_down(false)
        F.session.mousereleased(x, canvas_y, 1, false, 1)
        F.session.mousemoved(x, y, 0, y - canvas_y, false)
        assert.is_nil(selected(w))
        K.frame()
        F.session.mousepressed(x2, canvas_y, 1, false, 1)
        F.session.mousemoved(x2, y, 0, y - canvas_y, false)
        F.session.mousereleased(x2, y, 1, false, 1)
        assert.is_nil(selected(w))
      end)

    in_every_field("a click in one frame places the cursor and "
        .. "selects nothing", function(owner)
      local f = field_of(owner, { "hello world" }, 1, 12)
      local x, y = at(f, 0, 4)
      F.set_mouse_down(false)
      F.session.mousepressed(x, y, 1, false, 1)
      F.session.mousereleased(x, y, 1, false, 1)
      K.frame()
      assert.is_nil(selected(f), owner)
      assert.same({ 1, 4 }, cursor(f), owner)
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

    --- a press and its release at (x, y), the press LÖVE's
    --- `presses`-th quick one
    local function click(x, y, presses)
      F.session.mousepressed(x, y, 1, false, presses)
      F.session.mousereleased(x, y, 1, false, presses)
    end

    --- a click with Shift held
    local function shift_click(x, y)
      K.hold("lshift")
      click(x, y, 1)
      K.release("lshift")
    end

    local function double_click(x, y)
      click(x, y, 1)
      click(x, y, 2)
      K.frame()
    end

    describe("Shift+click", function()
      in_every_field("selects from the cursor to the click",
        function(owner)
          local f = field_of(owner, nil, 1, 2)
          shift_click(at(f, 0, 3))
          assert.same("ne two\nth", selected(f), owner)
          assert.same({ 2, 3 }, cursor(f), owner)
        end)

      in_every_field("goes on from where the selection began",
        function(owner)
          local f = field_of(owner, nil, 1, 7)
          K.keys("lshift", "left")
          K.keys("lshift", "left")
          assert.same("tw", selected(f), owner)
          shift_click(at(f, 0, 3))
          assert.same("o\nth", selected(f), owner)
          assert.same({ 2, 3 }, cursor(f), owner)
          shift_click(at(f, 1, 2))
          assert.same("ne tw", selected(f), owner)
          assert.same({ 1, 2 }, cursor(f), owner)
        end)

      in_every_field("on where the selection began leaves none",
        function(owner)
          local f = field_of(owner, nil, 1, 2)
          K.keys("lshift", "right")
          shift_click(at(f, 1, 2))
          assert.is_nil(selected(f), owner)
          assert.same({ 1, 2 }, cursor(f), owner)
        end)

      in_every_field("and a drag go on from where the selection "
          .. "began", function(owner)
        local f = field_of(owner, nil, 1, 2)
        local x, y = at(f, 1, 4)
        local x2, y2 = at(f, 0, 3)
        K.hold("lshift")
        F.set_mouse_down(true)
        F.session.mousepressed(x, y, 1, false, 1)
        assert.same("ne", selected(f), owner)
        F.session.mousemoved(x2, y2, x2 - x, y2 - y, false)
        F.set_mouse_down(false)
        F.session.mousereleased(x2, y2, 1, false, 1)
        K.release("lshift")
        assert.same("ne two\nth", selected(f), owner)
        assert.same({ 2, 3 }, cursor(f), owner)
      end)

      in_every_field("selects across the rows of a wrapped line",
        function(owner)
          local long = string.rep("a", 70)
          local f = field_of(owner, { long, "end" }, 1, 3)
          --- the wrapped line's second row, its second column
          shift_click(at(f, 1, 2))
          assert.same(string.rep("a", 63), selected(f), owner)
          assert.same({ 1, 66 }, cursor(f), owner)
        end)

      it("with Ctrl held only places the cursor", function()
        local f = field_of("console", nil, 1, 2)
        K.hold("lctrl")
        K.hold("lshift")
        local x, y = at(f, 0, 3)
        click(x, y, 1)
        K.release("lshift")
        K.release("lctrl")
        assert.is_nil(selected(f))
        assert.same({ 2, 3 }, cursor(f))
      end)
    end)

    describe("a double click", function()
      in_every_field("selects the word under it, the cursor at its "
          .. "end", function(owner)
        local f = field_of(owner, { "x = hello_world2 + 1" }, 1, 1)
        double_click(at(f, 0, 9))
        assert.same("hello_world2", selected(f), owner)
        assert.same({ 1, 17 }, cursor(f), owner)
      end)

      --- review r1's major: the character under the pointer, not
      --- the cursor place a click on its right half rounds to
      in_every_field("takes the character under the pointer, on "
          .. "either half of its cell", function(owner)
        local f = field_of(owner, { "one two" }, 1, 8)
        local v = f.model.cfg.view
        local _, y = at(f, 0, 1)
        --- column, and the word selected (nil: none)
        for _, case in ipairs({ { 1, "one" }, { 3, "one" },
          { 4, nil }, { 5, "two" }, { 7, "two" } }) do
          for _, half in ipairs({ 0.2, 0.8 }) do
            local col, want = case[1], case[2]
            local what = owner .. " col " .. col .. " at " .. half
            f:set_cursor_pos(1, 8)
            K.frame()
            double_click(v.fw * (col - 1 + half), y)
            assert.same(want, selected(f), what)
            if not want then
              assert.same({ 1, col + (half > .5 and 1 or 0) },
                cursor(f), what)
            end
          end
        end
      end)

      in_every_field("is two presses LÖVE counts as one pair: two "
          .. "presses counted 1 each select nothing", function(owner)
        local f = field_of(owner, { "one two" }, 1, 1)
        local x, y = at(f, 0, 6)
        click(x, y, 1)
        click(x, y, 1)
        K.frame()
        assert.is_nil(selected(f), owner)
        assert.same({ 1, 6 }, cursor(f), owner)
      end)

      in_every_field("keeps the word through the pointer's jitter "
          .. "before the release", function(owner)
        local f = field_of(owner, { "one two three" }, 1, 1)
        local x, y = at(f, 0, 6)
        click(x, y, 1)
        F.set_mouse_down(true)
        F.session.mousepressed(x, y, 1, false, 2)
        F.session.mousemoved(x + 2, y + 1, 2, 1, false)
        F.set_mouse_down(false)
        F.session.mousemoved(x + 3, y, 1, -1, false)
        F.session.mousereleased(x + 3, y, 1, false, 2)
        K.frame()
        assert.same("two", selected(f), owner)
        assert.same({ 1, 8 }, cursor(f), owner)
      end)

      in_every_field("on a character of no word places the cursor",
        function(owner)
          local f = field_of(owner, { "a + b" }, 1, 1)
          double_click(at(f, 0, 3))
          assert.is_nil(selected(f), owner)
          assert.same({ 1, 3 }, cursor(f), owner)
        end)

      in_every_field("selects a word the line wraps, and a word of "
          .. "another line", function(owner)
        local long = string.rep("a", 60) .. " wrapping"
        local f = field_of(owner, { long, "next words" }, 1, 1)
        --- the wrapped line's second row, its second column: a
        --- letter of the word past the wrap
        double_click(at(f, 1, 2))
        assert.same("wrapping", selected(f), owner)
        assert.same({ 1, 70 }, cursor(f), owner)
        double_click(at(f, 0, 3))
        assert.same("next", selected(f), owner)
        assert.same({ 2, 5 }, cursor(f), owner)
      end)

      in_every_field("is typed over as a selection is", function(owner)
        local f = field_of(owner, { "one two three" }, 1, 1)
        double_click(at(f, 0, 6))
        K.type("2")
        assert.same("one 2 three", text(f), owner)
        K.keys("lctrl", "z")
        K.keys("lctrl", "z")
        assert.same("one two three", text(f), owner)
        assert.same("two", selected(f), owner)
      end)

      it("in a program's field selects the word, and the program's "
          .. "doubleclick hook gets the double click too", function()
        K.reset()
        local input = F.activate_project()
        local w = F.show_widget({ text = "" })
        w:set_text({ "one two" })
        local got = 0
        input.hooks.doubleclick = function() got = got + 1 end
        double_click(at(w, 0, 6))
        assert.same("two", selected(w))
        assert.same(1, got)
      end)

      it("in a program's field selects nothing when the program's "
          .. "mousepressed hook takes the press", function()
        K.reset()
        local input = F.activate_project()
        local w = F.show_widget({ text = "" })
        w:set_text({ "one two" })
        w:set_cursor_pos(1, 1)
        input.hooks.mousepressed = function() return true end
        double_click(at(w, 0, 6))
        assert.is_nil(selected(w))
        assert.same({ 1, 1 }, cursor(w))
      end)
    end)
  end)

  -- the review's round s1: whatever replaces or rewrites the
  -- field's text clears the selection; a removal is a step of
  -- its own; a plain Up or Down clears it at the draft's edge
  describe("what clears it", function()
    it("a program's set_text, keeping the cursor", function()
      K.reset()
      F.activate_project()
      local w = F.show_widget({ text = "" })
      w:set_text({ "abc", "def" })
      w:set_cursor_pos(1, 1)
      K.keys("lctrl", "lshift", "end")
      assert.is_not_nil(selected(w))
      F.compy_input().set_text("ok", true)
      assert.is_nil(selected(w))
      K.type("X")
      assert.same("okX", table.concat(w:get_text(), "\n"))
    end)

    it("the editor's formatting of a draft", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      local im = K.ed.input.model
      im:set_text({ "  v1=1" })
      im:move_cursor(1, 7)
      K.keys("lshift", "left")
      assert.same("1", selected(K.ed.input))
      im:reformat({ "v1 = 1" })
      assert.is_nil(selected(K.ed.input))
    end)

    in_every_field("a plain Up or Down at the draft's edge",
      function(owner)
        local f = field_of(owner, { "abcdef" }, 1, 7)
        K.keys("lshift", "left")
        assert.same("f", selected(f), owner)
        K.keys("down")
        assert.is_nil(selected(f), owner)
        K.keys("lshift", "left")
        K.keys("up")
        assert.is_nil(selected(f), owner)
      end)

    in_every_field("a removal is a step of its own, apart from the "
        .. "deletion after it", function(owner)
      local f = field_of(owner, { "abcde" }, 1, 3)
      K.keys("lshift", "right")
      K.keys("lshift", "right")
      K.keys("delete")
      assert.same("abe", text(f), owner)
      K.keys("delete")
      assert.same("ab", text(f), owner)
      K.keys("lctrl", "z")
      assert.same("abe", text(f), owner)
      K.keys("lctrl", "z")
      assert.same("abcde", text(f), owner)
    end)

    it("the editor's redo of a block move brings back the "
        .. "selection of the draft it left alone", function()
      K.reset({ ["notes.txt"] = "a\nb\n" })
      K.open("notes.txt")
      K.browse_to(1)
      K.type("xyz")
      K.keys("lshift", "insert")
      K.keys("lshift", "left")
      assert.same("z", selected(K.ed.input))
      K.browse_to(1)
      K.keys("lalt", "down")
      K.keys("lctrl", "z")
      K.keys("lctrl", "y")
      assert.same("xyz", K.draft())
      assert.same("z", selected(K.ed.input))
    end)

    it("the editor's redo brings back the result, and undo the "
        .. "selection, through the file's timeline too", function()
      K.reset({ ["notes.txt"] = "" })
      K.open("notes.txt")
      K.type("abc")
      K.keys("lshift", "left")
      K.type("X")
      assert.same("abX", K.draft())
      --- the typing, then the removal (point D)
      K.keys("lctrl", "z")
      assert.same("ab", K.draft())
      K.keys("lctrl", "z")
      assert.same("abc", K.draft())
      assert.same("c", selected(K.ed.input))
      K.keys("lctrl", "z")
      K.keys("lctrl", "y")
      assert.same("abc", K.draft())
      assert.same("c", selected(K.ed.input))
      K.keys("lctrl", "y")
      assert.same("ab", K.draft())
      K.keys("lctrl", "y")
      assert.same("abX", K.draft())
    end)

    it("a drag ends when the button is up, its release unseen",
      function()
        local f = field_of("console", nil, 1, 1)
        local v = f.model.cfg.view
        local bottom = love.graphics.getHeight() - Layout(v).bottom
        local x, y = v.fw * 1.2, bottom - v.fh * 1.5
        F.set_mouse_down(true)
        F.session.mousepressed(x, y, 1, false, 1)
        -- the release goes elsewhere: the button is up
        F.set_mouse_down(false)
        F.session.mousemoved(v.fw * 4.2, y, 3, 0, false)
        K.frame()
        assert.is_nil(selected(f))
      end)
  end)

  -- the review's round s2
  describe("a drag and a rewrite", function()
    --- the point of column `col` on the field's row
    --- `row_from_bottom` (0, its last)
    local function at(f, row_from_bottom, col)
      local v = f.model.cfg.view
      local bottom = love.graphics.getHeight() - Layout(v).bottom
      return v.fw * (col - 1 + 0.2),
          bottom - v.fh * (row_from_bottom + 0.5)
    end

    it("a rewrite of the text during a drag ends the drag", function()
      K.reset()
      F.activate_project()
      local w = F.show_widget({ text = "" })
      w:set_text({ "abc", "def" })
      local x, y = at(w, 0, 3)
      F.set_mouse_down(true)
      F.session.mousepressed(x, y, 1, false, 1)
      F.compy_input().set_text("ok", true)
      local x2, y2 = at(w, 0, 1)
      F.session.mousemoved(x2, y2, x2 - x, 0, false)
      F.session.mousereleased(x2, y2, 1, false, 1)
      F.set_mouse_down(false)
      K.frame()
      assert.is_nil(selected(w))
      K.type("X")
      assert.is_true(table.concat(w:get_text(), "\n"):find("ok", 1, true)
        ~= nil)
    end)

    it("a new press outside the field ends a drag whose release "
        .. "went unseen", function()
      local f = field_of("console", { "abcdef" }, 1, 1)
      local x, y = at(f, 0, 2)
      F.set_mouse_down(true)
      F.session.mousepressed(x, y, 1, false, 1)
      -- the release went elsewhere; a press outside the field,
      -- then a move into it with the button down
      F.session.mousepressed(x, 10, 1, false, 1)
      local x2 = at(f, 0, 5)
      F.session.mousemoved(x2, y, x2 - x, 0, false)
      F.set_mouse_down(false)
      K.frame()
      assert.is_nil(selected(f))
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
