-- The document view draws whole rows only, on the field's
-- grid: its last row ends where the status line's band
-- starts, a row hidden beyond either edge leaves no part of
-- itself on the screen, and a text file's rows sit on the
-- same rows as a Lua file's.

local K = require("tests.helpers.editor_keys")

local function pitch()
  return K.cc.view.cfg.view.fh
end

--- What the view's draw leaves wrong of its texts in screen
--- `s`: each text off the field's grid, beyond the band or
--- above the screen, or more than one row.
local function off_rows(s)
  local fh, band = pitch(), s.field_y
  local wrong = { }
  for _, t in ipairs(s.texts) do
    local on_grid = math.abs((band - t.y) % fh) < 1e-6
    local inside = 0 <= t.y and t.y + fh <= band
    if not (on_grid and inside) or t.text:find("\n") then
      wrong[#wrong + 1] = string.format("%q at %.3f", t.text, t.y)
    end
  end
  return wrong
end

local function lines(n, w)
  local out = { "one" }
  local word = { }
  for i = 1, n * w / 8 do
    word[#word + 1] = string.format("word%03d", i)
  end
  out[#out + 1] = table.concat(word, " ")
  out[#out + 1] = "last"
  return table.concat(out, "\n") .. "\n"
end

describe("the document view's rows #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  before_each(function()
    K.reset({
      ["main.lua"] = "x = 1\n",
      ["tall.lua"] = "a = 1\n" .. K.block(20) .. "b = 2\n",
      ["notes.txt"] = lines(20, 64),
      ["notes.md"] = lines(20, 64),
    })
  end)

  it("a target taller than the view above a taller field "
      .. "leaves no part of a row under the field", function()
    K.open("tall.lua")
    K.browse_to(2)
    K.keys("f2")
    assert.same("replacing", K.state())
    local s = K.screen()
    assert.is_true(1 < s.field_rows)
    local range = K.ed.view:get_current_buffer().content.range
    assert.is_true(range.fin < 1 + #K.block_lines(20))
    assert.same({ }, off_rows(s))
  end)

  it("a browsed block cut at both edges draws no row beyond "
      .. "either", function()
    K.open("tall.lua")
    K.browse_to(1)
    for _ = 1, 4 do
      K.keys("lctrl", "down")
    end
    assert.same(2, K.position())
    local range = K.ed.view:get_current_buffer().content.range
    assert.is_true(2 < range.start)
    local s = K.screen()
    assert.same(1, s.field_rows)
    assert.same({ }, off_rows(s))
  end)

  it("a click browses to the block on the row drawn under it, "
      .. "the space above the first row being that row's",
      function()
    K.open("tall.lua")
    K.browse_to(3)
    local bv = K.ed.view:get_current_buffer()
    local fh = bv:row_height()
    local y
    for _, t in ipairs(K.screen().texts) do
      if t.text == "b" then y = t.y end
    end
    -- the last pixel row of b = 2, the third block, and the
    -- last of the row above it, the block before
    K.ed:mousepressed(0, y + fh - 1, 1, false, 1)
    assert.same(3, K.position())
    K.ed:mousepressed(0, y - 1, 1, false, 1)
    assert.same(2, K.position())
    -- above the first row: the first row's block
    local first = bv.content.range.start
    local ln = bv.content.wrap_reverse[first]
    K.ed:mousepressed(0, 0, 1, false, 1)
    assert.same(bv.buffer:block_at_line(ln), K.position())
  end)

  for _, name in ipairs({ "notes.txt", "notes.md" }) do
    it("in " .. name .. " a long line cut at the edge draws "
        .. "each row on its own row of the grid", function()
      K.open(name)
      K.browse_to(2)
      local range = K.ed.view:get_current_buffer().content.range
      assert.is_true(1 < range.start)
      assert.same({ }, off_rows(K.screen()))
    end)
  end
end)
