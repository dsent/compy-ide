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

--- Run `f`, failing with "still running" when it would not end.
--- LuaJIT fires a count hook only in code it runs uncompiled, and
--- its hook holds for every coroutine, so the JIT and any hook
--- before are put back however `f` ends.
--- @return boolean ok, any err
local function bounded(f)
  local was_on = jit and jit.status()
  local hook, mask, count = debug.gethook()
  if jit then jit.off() end
  debug.sethook(function() error("still running") end, "", 1e7)
  local ok, err = pcall(f)
  if hook then debug.sethook(hook, mask, count)
  else debug.sethook() end
  if was_on then jit.on() end
  return ok, err
end

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

  --- Make `s` the cursor's style
  local function set_style(t, s)
    t:set_cursor_color(s.color)
    t:set_cursor_backcolor(s.back)
    t:reverse_cursor(s.rev)
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

  --- a row that came back at the bottom is cells of their own:
  --- after 20 rolls every row of the grid has come back
  for _, rolls in ipairs({ 1, 20 }) do
    it("keeps each cell's colors on a row that came back after "
      .. rolls .. " rolls", function()
        local t = print_rows(19 + rolls)
        for y = 1, t.height do
          t:move_to(1, y)
          for i, ch in ipairs({ "R", "G", "B" }) do
            set_style(t, STYLES[i])
            t:print(ch)
          end
        end
        t:update(1000)
        for y = 1, t.height do
          for i, ch in ipairs({ "R", "G", "B" }) do
            assert_cells(t, y, i, i, ch, STYLES[i])
          end
        end
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

--- reverse_cursor(true) reverses, (false) does not, and with
--- no value it changes over
describe("terminal reverse", function()
  it("is set by a value and changed over without one", function()
    local t = new_term()
    local seen = {}
    for _, v in ipairs({ true, false, false, "none", "none", true,
      true }) do
      if v == "none" then
        t:reverse_cursor()
      else
        t:reverse_cursor(v)
      end
      t:update(1000)
      table.insert(seen, t.cursor_reversed)
    end
    assert.same({ true, false, false, true, false, true, true },
      seen)
  end)
end)

--- terminal:clear() always says where; a clear command that
--- says nothing clears the whole grid
describe("terminal clear command", function()
  it("clears every row when it names no height", function()
    local t = new_term()
    t:print(string.rep("x", t.width * t.height - 1))
    t:update(1000)
    table.insert(t.stdin, { type = "clear" })
    t:update(1000)
    for y = 1, t.height do
      assert.equal(" ", t.buffer[y][1], "row " .. y)
    end
  end)
end)

--- What falls outside the grid is lost: a clear or a frame is
--- cut at the edges. (A cursor cannot be moved off the grid: see
--- "terminal cursor moves".)
describe("terminal outside the grid", function()
  --- a grid full of `x`
  local function full()
    local t = new_term()
    t:print(string.rep("x", t.width * t.height - 1))
    t:update(1000)
    return t
  end

  --- the text of grid row `y`, spaces at its end left out
  local function row(t, y)
    return (table.concat(t.buffer[y]):gsub("%s+$", ""))
  end

  it("clears only the part of a clear inside the grid", function()
    local t = full()
    t:clear(15, 15, 10, 10)
    t:clear(25, 25, 2, 2)
    t:update(1000)
    for y = 1, 14 do
      assert.equal(string.rep("x", 20), row(t, y), "row " .. y)
    end
    for y = 15, 19 do
      assert.equal(string.rep("x", 14), row(t, y), "row " .. y)
    end
  end)

  it("draws only the part of a frame inside the grid", function()
    local t = new_term()
    t:frame("line", 15, 2, 10, 3)
    t:frame("line", 2, 18, 5, 5)
    t:update(1000)
    assert.equal(string.rep(" ", 14) .. "┌─────", row(t, 2))
    assert.equal(string.rep(" ", 14) .. "│", row(t, 3))
    assert.equal(string.rep(" ", 14) .. "└─────", row(t, 4))
    assert.equal(" ┌───┐", row(t, 18))
    assert.equal(" │   │", row(t, 19))
    assert.equal(" │   │", row(t, 20))
  end)

  --- the debug self-test frames at column 90 and down to row 19
  --- on the console's 64 by 16 grid
  it("draws the self-test's frames on the console's grid",
    function()
      local font = {
        getWidth  = function() return 10 end,
        getHeight = function() return 10 end,
      }
      local t = Terminal(640, 160, font, 10, 10)
      t:frame("line", 10, 10, 10, 10)
      t:frame("line", 90, 10, 10, 10)
      t:update(1000)
      assert.equal("┌", t.buffer[10][10])
      assert.equal("│", t.buffer[16][19])
    end)

  --- more rolls than rows leave the same blank grid, so no
  --- row the cursor is on asks for more than a grid's worth
  it("scrolls a grid's worth at most, whatever the row", function()
    local t = full()
    t.cursor_y = math.huge
    t:print("\n")
    local ok, err = bounded(function() t:update(1000) end)
    assert.is_true(ok, err)
    assert.equal(t.height, t.cursor_y)
    for y = 1, t.height do
      assert.equal("", row(t, y), "row " .. y)
    end
  end)
end)


--- A cursor moved off the grid goes to the nearest edge, as a
--- classic terminal takes it, and what is printed next lands
--- there.
describe("terminal cursor moves", function()
  local function row(t, y)
    return (table.concat(t.buffer[y]):gsub("%s+$", ""))
  end

  local nan, huge = 0 / 0, math.huge
  local CASES = {
    { 1, 30, 1, 20 },
    { 0, 0, 1, 1 },
    { 30, 1, 20, 1 },
    { -5, -5, 1, 1 },
    --- move_to floored a fraction before the clamp too: this
    --- case pins that, and passes without the clamp
    { 2.7, 3.2, 2, 3 },
    --- the last cell's character wraps the grid up a row
    { huge, huge, 20, 20, 19 },
    { -huge, -huge, 1, 1 },
    { nan, nan, 1, 1 },
    { nan, 5, 1, 5 },
    { 5, nan, 5, 1 },
  }

  for _, c in ipairs(CASES) do
    it(string.format("takes %s, %s to %d, %d", tostring(c[1]),
      tostring(c[2]), c[3], c[4]), function()
        local t = new_term()
        t:move_to(c[1], c[2])
        t:update(1000)
        assert.same({ c[3], c[4] }, { t.cursor_x, t.cursor_y })
        t:print("h")
        t:update(1000)
        assert.equal("h", t.buffer[c[5] or c[4]][c[3]])
      end)
  end

  it("prints on the bottom row from below, scrolling once",
    function()
      for _, y in ipairs({ 30, math.huge }) do
        local t = new_term()
        for i = 1, t.height - 1 do t:print("r" .. i .. "\n") end
        t:move_to(1, y)
        t:print("hi\n")
        t:update(1000)
        assert.equal("r2", row(t, 1), "y " .. y)
        assert.equal("hi", row(t, t.height - 1), "y " .. y)
        assert.equal("", row(t, t.height), "y " .. y)
        assert.equal(t.height, t.cursor_y)
      end
    end)

  it("prints at the last column and wraps from the right",
    function()
      local t = new_term()
      t:move_to(30, 1)
      t:print("ab")
      t:update(1000)
      assert.equal("a", t.buffer[1][t.width])
      assert.equal("b", t.buffer[2][1])
    end)

  --- a position that is no number at all is the program's own
  --- error, raised where it asks, and the terminal goes on: as
  --- before the clamp, which this pins and does not test
  it("refuses no position or a word, in the asking call",
    function()
      local t = new_term()
      assert.has_error(function() t:move_to() end)
      assert.has_error(function() t:move_to("a", 1) end)
      t:print("ok")
      t:update(1000)
      assert.equal("ok", row(t, 1))
    end)
end)