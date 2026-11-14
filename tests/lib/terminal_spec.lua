-- LÖVE brings utf8 and a graphics context; a spec runs without
-- them, so shim the calls lib.terminal makes at construction and
-- while queueing output. utf8 is the real lua-utf8 rock, which
-- (like LÖVE's utf8) raises on a malformed sequence.
package.preload["utf8"] = function() return require("lua-utf8") end

local canvas = {}
_G.love = _G.love or {}
love.graphics = {
  newCanvas = function() return canvas end,
  getCanvas = function() return nil end,
  setCanvas = function() end,
  clear     = function() end,
  push      = function() end,
  origin    = function() end,
  pop       = function() end,
  getColor  = function() return 1, 1, 1, 1 end,
  setColor  = function() end,
  setFont   = function() end,
  print     = function() end,
  draw      = function() end,
  rectangle = function() end,
}
love.timer = { getTime = function() return 0 end }

local Terminal = require("lib.terminal")

local function new_term()
  local font = {
    getWidth  = function() return 10 end,
    getHeight = function() return 10 end,
  }
  return Terminal(200, 200, font, 10, 10)
end

describe("terminal output", function()
  it("queues each utf-8 codepoint of a normal write", function()
    local t = new_term()
    t:print("hi")
    assert.same({ "h", "i" }, t.stdin)
  end)

  -- Regression: io.write of a byte that is not valid UTF-8 used to
  -- raise (utf8.codes, terminal.lua) and take the whole console
  -- output down. The bad byte is dropped; the valid text survives.
  it("does not crash on a non-utf-8 byte, and keeps the good bytes", function()
    local t = new_term()
    assert.has_no.errors(function()
      t:print("A" .. string.char(0xFF) .. "B")
    end)
    assert.same({ "A", "B" }, t.stdin)
  end)
end)

--- A row's colors are its own: when the output scrolls, every
--- cell keeps its color, back color and reversal, and the row
--- coming in at the bottom is blank in the cursor's colors.
describe("terminal scrolling", function()
  local STYLES = {
    { color = { 1, 0, 0, 1 }, back = { 0, 0, 0, 1 }, rev = false },
    { color = { 0, 1, 0, 1 }, back = { 0, 0, 1, 1 }, rev = true },
    { color = { 0, 0, 1, 1 }, back = { 1, 1, 0, 1 }, rev = false },
  }
  local OTHER =
    { color = { 1, 1, 1, 1 }, back = { 1, 0, 1, 1 }, rev = true }

  --- Make `s` the cursor's style. reverse_cursor(false) is not
  --- used: given false, it toggles.
  local function set_style(t, s)
    t:set_cursor_color(s.color)
    t:set_cursor_backcolor(s.back)
    if s.rev ~= (t.test_reversed or false) then
      t:reverse_cursor()
      t.test_reversed = s.rev
    end
  end

  --- Print `n` rows, each as wide as the grid, so that each
  --- wraps to the next by itself, in styles taking turns
  --- @return table terminal, string[] texts, table[] styles
  local function print_rows(n)
    local t = new_term()
    local texts, styles = {}, {}
    for i = 1, n do
      local s = STYLES[(i - 1) % #STYLES + 1]
      set_style(t, s)
      local ch = string.char(string.byte('a') + (i - 1) % 26)
      texts[i] = string.rep(ch, t.width)
      styles[i] = s
      t:print(texts[i])
    end
    t:update(1000)
    return t, texts, styles
  end

  --- Cells `from` to `to` of grid row `y` hold `ch` in style `s`
  local function assert_cells(t, y, from, to, ch, s)
    for x = from, to do
      local st = t.state_buffer[y][x]
      local where = string.format("row %d, column %d", y, x)
      assert.equal(ch, t.buffer[y][x], where)
      assert.same(s.color, st.color, where)
      assert.same(s.back, st.backcolor, where)
      assert.equal(s.rev, st.reversed == true, where)
    end
  end

  for _, rolls in ipairs({ 1, 8 }) do
    it("keeps each row's colors after " .. rolls .. " rolls",
      function()
        local t, texts, styles = print_rows(19 + rolls)
        assert.equal(t.height, t.cursor_y)
        for y = 1, t.height - 1 do
          local line = y + rolls
          assert_cells(t, y, 1, t.width,
            string.sub(texts[line], 1, 1), styles[line])
        end
      end)

    --- the row printed last is in one style, the cursor in
    --- another when the newline brings the blank row in
    it("brings a blank row in the cursor's colors after "
      .. rolls .. " rolls", function()
        local t = print_rows(19 + rolls)
        set_style(t, STYLES[1])
        t:print("aaa")
        set_style(t, OTHER)
        t:print("\n")
        t:update(1000)
        assert_cells(t, t.height - 1, 1, 3, "a", STYLES[1])
        assert_cells(t, t.height, 1, t.width, " ", OTHER)
      end)
  end
end)

--- The console draws the grid again only when it is marked
--- (view/canvas/terminalView.lua), and output reaches the grid a
--- few characters a frame: a newline that scrolls the grid on a
--- frame of its own is still to be drawn.
describe("terminal scrolling on a frame of its own", function()
  it("marks the grid and every cell to be drawn again", function()
    local t = new_term()
    t:print(string.rep("x\n", t.height - 1) .. "abc")
    t:update(1000)
    assert.equal(t.height, t.cursor_y)
    -- drawn: the view clears the marks
    t.dirty = false
    for _, row in ipairs(t.state_buffer) do
      for _, st in ipairs(row) do st.dirty = false end
    end
    t:print("\n")
    t:update(1000)
    assert.equal("a", t.buffer[t.height - 1][1])
    assert.is_true(t.dirty)
    for y, row in ipairs(t.state_buffer) do
      for x, st in ipairs(row) do
        assert.is_true(st.dirty,
          string.format("row %d, column %d", y, x))
      end
    end
  end)
end)
