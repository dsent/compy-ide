-- What the status line, a notice and the key card draw,
-- through the real draw functions (K.screen): the fixture's
-- graphics stand-in skips this path everywhere else.

local K = require("tests.helpers.editor_keys")

local function field(s)
  return K.screen_text(s.field)
end

--- a row's height in the field and in the band
local function fh()
  return K.ed.view.cfg.fh
end

--- Texts as what was drawn where: each text and its y.
local function placed(list)
  local out = { }
  for i, t in ipairs(list) do
    out[i] = {
      t.text,
      t.y
    }
  end
  return out
end

--- The band's rows on the screen `s`: the editor draws them
--- last, one text per row of the message shown.
local function band(s)
  local rows = K.ed.view:message_rows() or { }
  local out = { }
  for i = 1, #rows do
    out[i] = s.texts[#s.texts - #rows + i]
    assert(out[i] and out[i].text == rows[i],
      "the band's rows are drawn last")
  end
  return out
end

--- What the screen `s` shows under the band: the texts and
--- the fills drawn before the band's own, and the band's
--- fill.
local function under_band(s)
  local n = #band(s)
  local texts, fills = { }, { }
  for i = 1, #s.texts - n do
    texts[i] = s.texts[i]
  end
  for i = 1, #s.fills - 1 do
    fills[i] = s.fills[i]
  end
  return texts, fills, s.fills[#s.fills]
end

--- The field's text drawn in the error colour, under its
--- status line, in the order drawn.
local function red(s)
  local cfg = K.ed.view.cfg
  local err = cfg.colors.input.error
  local out = { }
  for _, t in ipairs(s.field) do
    local c = t.colour or { }
    local same = true
    for i = 1, 3 do
      same = same and math.abs((c[i] or 0) - err[i]) < 0.001
    end
    if same and cfg.fh <= t.y then
      out[#out + 1] = t.text
    end
  end
  return table.concat(out)
end

local function same_colour(a, b)
  for i = 1, 3 do
    if 0.001 <= math.abs((a[i] or 0) - (b[i] or 0)) then
      return false
    end
  end
  return true
end

--- The band on the screen `s` as a person sees it: the colour
--- its rows are written in and its background's. It has no
--- frame: nothing on the screen is outlined.
local function band_colours(s)
  local rows = band(s)
  assert(0 < #rows, "a message shows")
  for _, r in ipairs(rows) do
    assert(same_colour(r.colour, rows[1].colour),
      "the band's rows are of one colour")
  end
  assert(#s.frames == 0, "the band has no frame")
  return {
    text = rows[1].colour,
    bg = s.fills[#s.fills].colour
  }
end

--- The theme's colours a message is drawn in.
local function theme()
  local colors = K.ed.view.cfg.colors
  return {
    -- as the console's status line has '[no sd card]'
    warning = colors.statusline.console.warning,
    error = colors.input.error,
    bg = colors.input.error_bg
  }
end

--- a valid Lua line of 70 characters: it wraps in the field
local WIDE = "x = " .. string.rep("1", 66)

describe("status line, notice and key card drawn #editor",
    function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  before_each(function()
    K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
    K.open()
  end)

  it("the status line names project, file and state", function()
    K.browse_to(1)
    local f = field(K.screen())
    assert.truthy(f:find(K.PROJECT, 1, true))
    assert.truthy(f:find("main.lua", 1, true))
    assert.truthy(f:find("browsing", 1, true))
    K.keys("f2")
    assert.truthy(field(K.screen()):find("replacing", 1, true))
  end)

  -- the maintainer's rulings of November 14, late, and 15:
  -- four pixels for the status line, all under its text (the
  -- text keeps a row's 33 from the line's top), and two at the
  -- very bottom
  it("the status line is 37 pixels high, its text at its top, "
      .. "and the field's rows end 2 above the screen's bottom",
      function()
    K.browse_to(1)
    local s = K.screen()
    local band
    for _, e in ipairs(s.field_log) do
      if e.fill and e.y == 0 and e.h == 37 then band = e end
    end
    assert.truthy(band, "a fill of the status line's 37 pixels")
    local named = false
    for _, t in ipairs(s.field) do
      if t.text:find("main.lua", 1, true) then
        assert.same(0, t.y)
        named = true
      end
    end
    assert.is_true(named)
    assert.same(600 - 2 - 33 - 37, s.field_y)
  end)

  it("the status line shows Caps Lock while it is on",
      function()
    assert.is_nil(field(K.screen()):find("CAPS", 1, true))
    K.keys("capslock")
    assert.truthy(field(K.screen()):find("CAPS", 1, true))
    K.keys("capslock")
    assert.is_nil(field(K.screen()):find("CAPS", 1, true))
  end)

  describe("a message, in the band above the status line",
      function()
    it("leaves the status line, the field and the view where "
        .. "they were", function()
      K.browse_to(1)
      K.type("r")
      local before = K.screen()
      -- Edit during an insertion is refused
      K.keys("f2")
      local after = K.screen()
      assert.is_truthy(K.message())
      assert.same("r", K.draft())
      assert.same(1, #band(after))
      -- the status line and the field: the same rows, and
      -- the same drawn in them
      assert.same(before.field_y, after.field_y)
      assert.same(before.field_rows, after.field_rows)
      assert.same(placed(before.field), placed(after.field))
      -- the view: every text and every fill where it was,
      -- the band's own drawn over them
      local texts, fills = under_band(after)
      assert.same(placed(before.texts), placed(texts))
      assert.same(before.fills, fills)
      -- the next key dismisses it, and nothing else moves
      K.keys("right")
      local gone = K.screen()
      assert.is_nil(K.message())
      assert.same(placed(before.texts), placed(gone.texts))
      assert.same(before.fills, gone.fills)
      assert.same(before.field_y, gone.field_y)
    end)

    it("has its rows directly above the status line", function()
      K.browse_to_end()
      -- no block at the end position: Edit is refused
      K.keys("f2")
      local s = K.screen()
      local rows = band(s)
      assert.same(1, #rows)
      assert.same(K.message(), rows[1].text)
      assert.same(s.field_y - fh(), rows[1].y)
      local drawn = K.screen_text(s.texts)
      assert.is_nil(drawn:find("Errors:", 1, true))
      assert.is_nil(field(s):find(rows[1].text, 1, true))
      assert.same(1, s.field_rows)
    end)

    it("wraps between words onto a second row above the "
        .. "first", function()
      local words = string.rep("seven77 ", 12) .. "end."
      local plain = K.screen()
      K.ed:notice(words)
      local s = K.screen()
      local rows = band(s)
      assert.same(2, #rows)
      assert.same(words, rows[1].text .. " " .. rows[2].text)
      for _, r in ipairs(rows) do
        assert.is_true(#r.text <= 64, r.text)
      end
      assert.same(s.field_y - 2 * fh(), rows[1].y)
      assert.same(s.field_y - fh(), rows[2].y)
      assert.same(plain.field_y, s.field_y)
      assert.same(plain.field_rows, s.field_rows)
    end)

    it("is filled from the top of the view's row it reaches "
        .. "into, down to the status line", function()
      K.ed:notice("A notice.")
      local s = K.screen()
      local _, _, fill = under_band(s)
      local top = s.field_y - fh()
      assert.same(s.field_y, fill.y + fill.h)
      assert.is_true(fill.y <= top)
      local pitch = K.ed.view:get_current_buffer():row_height()
      assert.is_true(top - fill.y < pitch)
      assert.same(0, fill.y % pitch)
    end)

    it("shows three rows of a longer one, the last cut",
        function()
      K.ed:notice(string.rep("seven77 ", 40))
      local rows = band(K.screen())
      assert.same(3, #rows)
      assert.same("…", rows[3].text:sub(-#"…"))
      assert.same(1, K.screen().field_rows)
    end)

    it("shows the parser's message after a syntax failure, "
        .. "the draft red from the failure on", function()
      K.browse_to_end()
      K.type("x = = 1")
      local before = K.screen()
      K.keys("return")
      local s = K.screen()
      local rows = band(s)
      assert.is_true(0 < #rows)
      assert.same(K.message(), K.screen_text(rows, " "))
      assert.truthy(K.message():find("expression", 1, true))
      assert.same(s.field_y - #rows * fh(), rows[1].y)
      assert.same("= 1", red(s))
      assert.same(before.field_y, s.field_y)
      assert.same(before.field_rows, s.field_rows)
      local texts, fills = under_band(s)
      assert.same(placed(before.texts), placed(texts))
      assert.same(before.fills, fills)
    end)
  end)

  describe("a message's colour says what it is", function()
    --- A refusal's notice: the warning colour, no frame,
    --- the background as it is.
    local function is_notice()
      assert.is_truthy(K.message())
      assert.same("notice", K.message_kind())
      local c, t = band_colours(K.screen()), theme()
      assert.is_true(same_colour(t.warning, c.text))
      assert.is_true(same_colour(t.bg, c.bg))
      assert.is_false(same_colour(t.error, c.text))
    end

    it("a refusal at the end position is a notice", function()
      K.browse_to_end()
      K.keys("f2")
      is_notice()
    end)

    it("a refusal that asks to finish first is a notice",
        function()
      K.browse_to(1)
      K.type("r")
      K.keys("f2")
      assert.truthy(K.message():find("first", 1, true))
      is_notice()
    end)

    it("a line over the limit is refused with a notice",
        function()
      K.browse_to_end()
      K.type(string.rep("x", 66) .. " = 1")
      K.keys("return")
      assert.truthy(K.message():find("limit", 1, true))
      is_notice()
    end)

    it("a block over the limit is refused with a notice",
        function()
      K.browse_to_end()
      local lines = K.block_lines(15)
      K.type_lines(lines)
      K.keys("return")
      assert.same(table.concat(lines, "\n"), K.draft())
      assert.truthy(K.message():find("limit is 14", 1, true))
      is_notice()
    end)

    it("a write that failed is told in a notice", function()
      K.browse_to_end()
      K.type("z = 3")
      K.fail_writes("the card is full")
      K.keys("return")
      assert.truthy(K.message():find("card is full", 1, true))
      is_notice()
    end)

    it("the parser's message is an error, in red", function()
      K.browse_to_end()
      K.type("x = = 1")
      K.keys("return")
      assert.truthy(K.message():find("expression", 1, true))
      assert.same("error", K.message_kind())
      local c, t = band_colours(K.screen()), theme()
      assert.is_true(same_colour(t.error, c.text))
      assert.is_true(same_colour(t.bg, c.bg))
      assert.is_false(same_colour(t.warning, c.text))
    end)

    it("no message has no kind", function()
      K.browse_to_end()
      K.keys("f2")
      K.keys("left")
      assert.is_nil(K.message())
      assert.is_nil(K.message_kind())
    end)

    it("the console's error stays in the error colour",
        function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.type("x = = 1")
      K.keys("return")
      local s = K.screen()
      local colors = K.cc.view.cfg.view.colors
      local found = false
      for _, t in ipairs(s.field) do
        if t.text:find("expression", 1, true) then
          found = true
          assert.is_true(same_colour(colors.input.error,
            t.colour))
        end
      end
      assert.is_true(found)
    end)
  end)

  it("the project's name is whole where it fits", function()
    local block = "function f()\n" .. string.rep("  g()\n", 5)
        .. "end\n"
    K.reset({
      ["main.lua"] = "a = 1\nb = 2\nc = 3\nd = 4\n" .. block
    })
    K.cc.model.projects.current.name = "scratchpad"
    K.open()
    K.type("r")
    K.browse_to(5)
    assert.same("inserting", K.state())
    local f = field(K.screen())
    -- 64 columns hold all of it beside `B5 L5-11`, the range
    -- with no count after it
    assert.truthy(f:find("L5-11", 1, true))
    assert.is_nil(f:find("L5-11(", 1, true))
    assert.truthy(f:find("scratchpad", 1, true))
    assert.truthy(f:find("main.lua", 1, true))
    assert.truthy(f:find("inserting", 1, true))
    -- a name too long for the line gives way, alone
    K.cc.model.projects.current.name = string.rep("p", 40)
    f = field(K.screen())
    -- up to two columns before the position: 16 and the mark
    assert.truthy(f:find(string.rep("p", 16) .. "…", 1, true))
    assert.is_nil(f:find(string.rep("p", 17), 1, true))
    assert.truthy(f:find("main.lua", 1, true))
    assert.truthy(f:find("inserting", 1, true))
  end)

  it("the key card keeps the status line under it", function()
    K.browse_to(1)
    local status = K.status_text()
    K.hold("f1")
    local s = K.screen()
    local held = K.status_text()
    K.release("f1")
    local drawn = K.screen_text(s.texts)
    assert.truthy(drawn:find("Keys now, browsing:", 1, true))
    assert.truthy(drawn:find("edit the block", 1, true))
    assert.truthy(drawn:find("main.lua", 1, true))
    assert.truthy(drawn:find("browsing", 1, true))
    assert.same(status, held)
  end)

  it("a long project name ends before the console's position",
      function()
    K.reset({ ["main.lua"] = "x = 1\n" })
    local name = string.rep("p", 80)
    K.cc.model.projects.current.name = name
    local f = field(K.screen())
    assert.is_nil(f:find(name, 1, true))
    assert.truthy(f:find("ppp…", 1, true))
  end)

  it("red starts at the failing character of a wrapped line",
      function()
    K.browse_to_end()
    K.type(WIDE .. " = 2")
    local s = K.screen()
    assert.same(2, s.field_rows)
    -- the second `=`, in the line's second row, and what
    -- follows it
    assert.same("= 2", red(s))
  end)

  it("no red in a line under a wrapped one that is unfinished",
      function()
    K.browse_to_end()
    K.type_lines({ WIDE, "f(" })
    local s = K.screen()
    assert.same(3, s.field_rows)
    assert.same("", red(s))
  end)

  it("the console's key card keeps the status line under it",
      function()
    K.reset({ ["main.lua"] = "x = 1\n" })
    K.hold("f1")
    local s = K.screen()
    K.release("f1")
    local drawn = K.screen_text(s.texts)
    assert.truthy(drawn:find("Keys now, console:", 1, true))
    assert.truthy(drawn:find("run the line", 1, true))
    assert.truthy(drawn:find(K.PROJECT, 1, true))
    assert.truthy(field(K.screen()):find(K.PROJECT, 1, true))
  end)

  it("the console's status line names the project", function()
    K.reset({ ["main.lua"] = "x = 1\n" })
    assert.truthy(field(K.screen()):find(K.PROJECT, 1, true))
  end)
end)
