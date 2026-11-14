-- Draws the whole screen through the real draw functions in
-- each state of the file editor, and in the console. The
-- fixture's graphics stand-in skips the field's render and
-- runs no canvas, so no other test runs this path, and an
-- error in it stops the editor on the device. K.screen draws
-- as love.draw does, with recording calls in place of
-- love.graphics' (tests/helpers/editor_keys.lua).
--
-- Each case: drawing raises no error (K.screen raises it),
-- and a fact or two a person would see.

local K = require("tests.helpers.editor_keys")

local function many(n)
  local t = { }
  for i = 1, n do
    t[i] = "v" .. i .. " = " .. i
  end
  return table.concat(t, "\n") .. "\n"
end

local function white(s)
  return K.screen_rows(s, "highlight")
end

local function yellow(s)
  return K.screen_rows(s, "highlight_loaded")
end

--- `text` is among what was drawn in the field or on its
--- status line.
local function in_field(s, text)
  return K.screen_text(s.field):find(text, 1, true) ~= nil
end

--- Where the last text matching `pattern` was drawn in the
--- field, from the field's top.
local function last_y(s, pattern)
  local y
  for _, t in ipairs(s.field) do
    if t.text:find(pattern) then
      y = t.y
    end
  end
  return y
end

describe("render smoke #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  before_each(function()
    K.reset({
      ["main.lua"] = "x = 1\n\nif a then\n  b = 1\nend\n",
      ["many.lua"] = many(40),
      ["tall.lua"] = "a = 1\n" .. K.block(22) .. "b = 2\n",
      ["empty.lua"] = "",
      ["a.txt"] = "one\n" .. string.rep("word ", 30) .. "\n",
      ["a.md"] = "# Title\n\nSome *text* here.\n"
    })
  end)

  it("browsing on a block", function()
    K.open()
    K.browse_to(3)
    local s = K.screen()
    assert.same("browsing", K.state())
    -- the three rows of the if block
    assert.same(3, white(s))
    assert.same(0, yellow(s))
    assert.same(1, s.field_rows)
    assert.is_true(in_field(s, "main.lua"))
  end)

  it("the end position", function()
    K.open()
    K.browse_to_end()
    local s = K.screen()
    assert.same(0, white(s))
    assert.same(1, s.field_rows)
  end)

  it("an empty file", function()
    K.open("empty.lua")
    local s = K.screen()
    assert.same(0, white(s))
    assert.same(1, s.field_rows)
    assert.is_true(in_field(s, "empty.lua"))
  end)

  it("inserting, a one-row draft", function()
    K.open()
    K.browse_to(1)
    K.type("y = 2")
    local s = K.screen()
    assert.same("inserting", K.state())
    assert.same(1, s.field_rows)
    assert.is_true(in_field(s, "y = 2"))
    assert.same(1, white(s))
  end)

  it("inserting, a wrapped draft of many rows", function()
    K.open("a.txt")
    K.browse_to_end()
    local lines = { }
    for n = 1, 6 do
      lines[n] = string.rep("abcdefghij", 9) .. n
    end
    K.type_lines(lines)
    local s = K.screen()
    -- twelve rows of draft, the field at its limit of 8
    assert.same(8, s.field_rows)
    assert.is_true(in_field(s, "abcdefghij6"))
    assert.is_false(in_field(s, "abcdefghij1"))
  end)

  it("inserting, the cursor at the end of a full row",
      function()
    K.open("a.txt")
    K.browse_to_end()
    K.type(string.rep("x", 64))
    local s = K.screen()
    -- the line's end is on its full row: no row is added,
    -- and the cursor is drawn on that row
    assert.same(1, s.field_rows)
    assert.is_truthy(last_y(s, "^x+$"))
    assert.same(last_y(s, "^x+$"), last_y(s, "^|$"))
  end)

  it("inserting, a full last row at the field's limit",
      function()
    K.open("a.txt")
    K.browse_to_end()
    local lines = { }
    for n = 1, 9 do
      lines[n] = "line " .. n
    end
    lines[10] = string.rep("x", 64)
    K.type_lines(lines)
    local s = K.screen()
    assert.same(8, s.field_rows)
    -- the last two lines are shown, the cursor on the last
    assert.is_true(in_field(s, "line 9"))
    assert.is_false(in_field(s, "line 2"))
    assert.is_truthy(last_y(s, "^x+$"))
    assert.same(last_y(s, "^x+$"), last_y(s, "^|$"))
  end)

  it("replacing, the target on screen", function()
    K.open()
    K.browse_to(3)
    K.keys("f2")
    local s = K.screen()
    assert.same("replacing", K.state())
    assert.same(3, yellow(s))
    assert.same(3, white(s))
    assert.same(3, s.field_rows)
    K.keys("lctrl", "up")
    s = K.screen()
    assert.same(3, yellow(s))
    assert.same(1, white(s))
  end)

  it("replacing, the target scrolled out of view", function()
    K.open("many.lua")
    K.browse_to(40)
    K.keys("f2")
    K.browse_to(1)
    local s = K.screen()
    assert.same("replacing", K.state())
    assert.same(40, K.target())
    assert.is_false(K.in_view(40))
    assert.same(0, yellow(s))
    assert.same(1, white(s))
    assert.is_true(in_field(s, "v40 = 40"))
  end)

  it("a tall block scrolled part-way", function()
    K.open("tall.lua")
    K.browse_to(1)
    for _ = 1, 4 do
      K.keys("lctrl", "down")
    end
    local s = K.screen()
    assert.same(2, K.position())
    local rows, shown = K.rows_shown(2)
    assert.is_true(shown < rows)
    -- every row of the view is the browsed block's
    assert.same(#K.view_rows(), white(s))
    assert.same(shown, white(s))
  end)

  it("a notice after a refusal", function()
    K.open()
    K.browse_to_end()
    -- a line over the limit is refused with a notice; a
    -- syntax failure shows none (IS3.14)
    local name = string.rep("x", 66)
    K.type(name .. " = 1")
    K.keys("return")
    local s = K.screen()
    local message = K.message()
    assert.is_truthy(message)
    -- the draft stays, shown formatted (IS3.2)
    assert.truthy(K.draft():find(name, 1, true))
    -- the notice's first words, and the status line with it
    assert.is_true(in_field(s, message:sub(1, 12)))
    assert.is_true(in_field(s, "main.lua"))
    -- the next key dismisses it, and the draft is drawn again
    K.keys("left")
    s = K.screen()
    assert.is_nil(K.message())
    assert.is_true(in_field(s, name:sub(1, 12)))
  end)

  it("the key card while the help key is held", function()
    K.open()
    K.browse_to(1)
    K.hold("f1")
    local card = K.key_card()
    local s = K.screen()
    K.release("f1")
    assert.is_truthy(card)
    -- the card covers the view: its heading shows, no
    -- highlight does, and the status line stays
    local heading = (card[1] .. "  "):match("^%s*(.-)%s%s")
    local drawn = K.screen_text(s.texts)
    assert.is_true(drawn:find(heading, 1, true) ~= nil)
    assert.is_true(drawn:find("main.lua", 1, true) ~= nil)
    assert.same(0, white(s))
    assert.is_nil(K.key_card())
    assert.same(1, white(K.screen()))
  end)

  it("a text file", function()
    K.open("a.txt")
    K.browse_to(2)
    local s = K.screen()
    local rows = K.rows_shown(2)
    assert.is_true(1 < rows)
    assert.same(rows, white(s))
    assert.is_true(in_field(s, "a.txt"))
  end)

  it("a Markdown file", function()
    K.open("a.md")
    K.browse_to(1)
    local s = K.screen()
    assert.same(1, white(s))
    assert.is_true(in_field(s, "a.md"))
  end)

  it("the console with a draft", function()
    K.type("1 + 1")
    local s = K.screen()
    assert.same("1 + 1", K.console_draft())
    assert.same(1, s.field_rows)
    assert.is_true(in_field(s, "1 + 1"))
    assert.is_true(in_field(s, K.PROJECT))
  end)
end)
