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
--- before are put back however `f` ends. The hook raises only
--- while `f` runs: once `f` has ended, or the hook has raised,
--- nothing raises, so whenever the count runs out the putting
--- back is done.
--- @param limit integer? --- the count, 1e7 by default
--- @return boolean ok, any err
local function bounded(f, limit)
  local was_on = jit and jit.status()
  local hook, mask, count = debug.gethook()
  local running = true
  if jit then jit.off() end
  debug.sethook(function()
    if running then
      running = false
      error("still running")
    end
  end, "", limit or 1e7)
  local ok, err = pcall(function()
    local done, why = pcall(f)
    running = false
    if not done then error(why, 0) end
  end)
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

  --- a clear or a frame walks the cells of the grid only: one
  --- far away or without end finishes, and changes what it covers
  --- of the grid
  it("clears and frames however far or large, and finishes",
    function()
      local huge = math.huge
      local t = full()
      t:clear(1e20, 1, 1, 1)
      t:clear(1, 1e20, 1, 1)
      t:frame("line", 1e20, 1, 3, 3)
      t:frame("line", 1, 1e20, 3, 3)
      local ok, err = bounded(function() t:update(1000) end)
      assert.is_true(ok, err)
      for y = 1, t.height - 1 do
        assert.equal(string.rep("x", 20), row(t, y), "row " .. y)
      end
      t:clear(3, 2, huge, huge)
      t:frame("line", -huge, -huge, huge, huge)
      t:frame("line", 1, 1, huge, huge)
      ok, err = bounded(function() t:update(1000) end)
      assert.is_true(ok, err)
      assert.equal("┌" .. string.rep("─", 19), row(t, 1))
      assert.equal("│x", row(t, 2))
      assert.equal("│x", row(t, t.height))
    end)

  it("clears a fractional rectangle from its whole cells",
    function()
      local t = full()
      t:clear(2.5, 1.5, 2, 1)
      local ok, err = bounded(function() t:update(1000) end)
      assert.is_true(ok, err)
      assert.equal("x  " .. string.rep("x", 17), row(t, 1))
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
--- show_cursor() and hide_cursor() set whether the cursor shows,
--- as often as they are called
describe("terminal cursor showing", function()
  it("is shown and hidden again and again", function()
    local t = new_term()
    local seen = {}
    for _, step in ipairs({ "hide_cursor", "show_cursor",
      "hide_cursor", "show_cursor", "show_cursor" }) do
      local ok, err = pcall(function() t[step](t) end)
      assert.is_true(ok, step .. ": " .. tostring(err))
      t:update(1000)
      table.insert(seen, t.cursor_visible)
    end
    assert.same({ false, true, false, true, true }, seen)
  end)
end)


--- bounded() puts the JIT and the hook before it back, wherever
--- its count runs out: in the body, or just after it returns
--- The queue of what waits to be written. A frame writes a few
--- characters of it; what the frame costs must not depend on how
--- much still waits behind them (a program that prints 2,000 lines
--- at once made every frame copy the whole queue).
describe("terminal queue", function()
  --- A terminal with `n` characters waiting and a frame's budget
  --- of ten of them
  local function waiting_term(n)
    local t = new_term()
    t.accumulator = 0
    t:print(string.rep("x", n))
    return t
  end

  --- What waits, as one string of its characters
  local function waits(t)
    local out = { }
    for c in t:waiting() do
      out[#out + 1] = type(c) == "string" and c or "<" .. c.type .. ">"
    end
    return table.concat(out)
  end

  --- The memory one frame allocates, in kB, with the collector off
  local function frame_kb(t)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    t:update(10 / t.speed + 0.001)
    local kb = collectgarbage("count") - before
    collectgarbage("restart")
    return kb
  end

  it("writes a frame's characters in a count that the waiting "
    .. "ones do not raise", function()
    -- ten characters cost a few hundred VM instructions; copying
    -- 60,000 waiting entries cost several hundred thousand
    local t = waiting_term(60000)
    local ok, err = bounded(function()
      t:update(10 / t.speed + 0.001)
    end, 5000)
    assert.is_true(ok, err)
    assert.equal(string.rep("x", 10),
      table.concat(t.buffer[1]):sub(1, 10))
  end)

  it("allocates for a frame what a short queue's frame does",
    function()
      local short = frame_kb(waiting_term(100))
      local long = frame_kb(waiting_term(60000))
      -- the copy of 60,000 entries took 512 kB
      assert.is_true(long < short + 8, string.format(
        "a frame allocated %.1f kB with 60,000 waiting, %.1f kB"
        .. " with 100", long, short))
    end)

  it("yields what still waits, oldest first, after each frame",
    function()
      local t = new_term()
      t.accumulator = 0
      t:print("abcdefghij")
      t:update(4 / t.speed + 0.0001)
      assert.equal("efghij", waits(t))
      t:print("KL")
      assert.equal("efghijKL", waits(t))
      t:update(3 / t.speed)
      assert.equal("hijKL", waits(t))
      t:update(1000)
      assert.equal("", waits(t))
      assert.equal("abcdefghijKL",
        table.concat(t.buffer[1]):sub(1, 12))
    end)

  it("holds at most twice what waits, and nothing once all is "
    .. "written", function()
    local t = waiting_term(1000)
    for _ = 1, 99 do
      t:update(10 / t.speed)
      local left = 0
      for _ in t:waiting() do left = left + 1 end
      assert.is_true(#t.stdin <= 2 * left, string.format(
        "%d entries held for %d waiting", #t.stdin, left))
    end
    t:update(1000)
    assert.same({ }, t.stdin)
    assert.equal(0, t.stdin_head)
  end)

  it("discards what waits, not what is written, and keeps the "
    .. "waiting styles", function()
    local t = new_term()
    t.accumulator = 0
    t:print("abcdef")
    t:set_cursor_color(1, 0, 0, 1)
    t:print("gh")
    t:update(3 / t.speed + 0.0001)
    assert.equal("def<cursor_color>gh", waits(t))
    t:discard()
    assert.equal("<cursor_color>", waits(t))
    t:print("Z")
    t:update(1000)
    assert.equal("abcZ", table.concat(t.buffer[1]):sub(1, 4))
    assert.same({ 1, 0, 0, 1 }, t.state_buffer[1][4].color)
  end)

  it("takes a write straight into the queue after a frame",
    function()
      -- as the clear command's test above puts its command
      local t = new_term()
      t.accumulator = 0
      t:print("abcd")
      t:update(2 / t.speed + 0.0001)
      table.insert(t.stdin, "e")
      assert.equal("cde", waits(t))
      t:update(1000)
      assert.equal("abcde", table.concat(t.buffer[1]):sub(1, 5))
    end)
end)

--- The view (view/canvas/terminalView.lua) draws the output in
--- runs: a rectangle for each run of cells of one background, a
--- print for each run of characters of one color, all the
--- backgrounds before any character. The graphics here are a
--- stand-in that records the calls, and the font is synthetic:
--- every character advances by a cell, 10, except those WIDE
--- names.
describe("terminal view", function()
  require("util.color")
  require("view.canvas.terminalView")
  local gfx = love.graphics
  local WIDE = { ["→"] = 13, ["\t"] = 40 }
  local saved, calls, count

  before_each(function()
    saved, calls, count = { }, { }, 0
    local stand_in = {
      getBlendMode = function() return "alpha", "alphamultiply" end,
      setBlendMode = function() end,
      rectangle = function(_, x, y, w)
        calls[#calls + 1] = string.format("back %d,%d %d",
          y / 10, x / 10, w / 10)
      end,
      print = function(text, x, y)
        calls[#calls + 1] = string.format("%d,%d %s", y / 10,
          x / 10, (text:gsub(" +$", "")))
      end,
    }
    for name, f in pairs(stand_in) do
      saved[name] = gfx[name] or false
      gfx[name] = f
    end
    -- every call into love.graphics is counted
    for name, f in pairs(gfx) do
      if saved[name] == nil then saved[name] = f end
      gfx[name] = function(...)
        count = count + 1
        return f(...)
      end
    end
  end)

  after_each(function()
    for name, f in pairs(saved) do gfx[name] = f or nil end
  end)

  --- a terminal of 20 by 20 cells whose font advances by a cell
  --- but for the characters WIDE names
  local function view_term(cell_width, font)
    font = font or { getHeight = function() return 10 end }
    font.getWidth = function(_, text)
      return WIDE[text] or 10
    end
    return Terminal(200, 200, font, cell_width or 10, 10), font
  end

  --- the calls that draw `t`, those of row `row` alone when
  --- given
  local function drawn(t, row, over_a_picture)
    t:update(1000)
    for i = #calls, 1, -1 do calls[i] = nil end
    count = 0
    TerminalView.draw(t, t.canvas, over_a_picture)
    if not row then return calls end
    local of_row = { }
    for _, call in ipairs(calls) do
      local rest = call:match("^back " .. row .. ",(.*)")
          or call:match("^" .. row .. ",(.*)")
      if rest then
        of_row[#of_row + 1] = (call:match("^back") and "back " or "")
            .. rest
      end
    end
    return of_row
  end

  it("draws a rectangle for each run of cells of one background",
    function()
      local t = view_term()
      t:print("ab")
      t:set_cursor_backcolor(0, 0, 1, 1)
      t:print("cd")
      t:set_cursor_backcolor(unpack(t.clear_color))
      t:print("e")
      local row = drawn(t, 0)
      assert.same({ "back 0 2", "back 2 2", "back 4 16" },
        { row[1], row[2], row[3] })
    end)

  it("draws a print for each run of characters of one color, a "
    .. "space in the run it is in", function()
    local t = view_term()
    t:print("ab cd ")
    t:set_cursor_color(1, 0, 0, 1)
    t:print(" ef")
    t:set_cursor_color(0, 0, 0, 1)
    t:print(" g")
    local row = drawn(t, 0)
    assert.same({ "0 ab cd", "7 ef", "10 g" },
      { row[#row - 2], row[#row - 1], row[#row] })
    assert.equal(4, #row)
  end)

  it("places at its own cell a character that does not advance "
    .. "by a cell", function()
    local t = view_term()
    t:print("ab→cd\te")
    local row = drawn(t, 0)
    assert.same({ "back 0 20", "0 ab", "2 →", "3 cd", "5 \t", "6 e" },
      row)
  end)

  it("asks again which characters stand alone in cells of "
    .. "another width", function()
    -- in cells of 13 the arrow advances by a cell and a letter,
    -- which advances by 10, does not
    local wide, font = view_term(13)
    wide:print("a→b")
    local row = drawn(wide, 0)
    assert.same({ "0 a", "1 →", "2 b" }, { row[2], row[3], row[4] })
    local t = view_term(10, font)
    t:print("ab→")
    row = drawn(t, 0)
    assert.same({ "0 ab", "2 →" }, { row[2], row[3] })
  end)

  it("places a space at its own cell too where it does not "
    .. "advance by a cell", function()
    -- in cells of 13 a space advances by 10 and the arrow by a
    -- cell: in a run the space would pull the arrow 3 back
    local t = view_term(13)
    t:print(" →")
    local row = drawn(t, 0)
    assert.same({ "0 ", "1 →" }, { row[2], row[3] })
  end)

  it("draws all the backgrounds before any character", function()
    local t = view_term()
    t:print("ab\ncd\nef")
    local all = drawn(t)
    local last_back, first_text = 0, #all + 1
    for i, call in ipairs(all) do
      if call:match("^back") then
        last_back = i
      elseif i < first_text then
        first_text = i
      end
    end
    assert.is_true(last_back < first_text)
  end)

  it("draws the characters alone over a program's picture",
    function()
      local t = view_term()
      t:print("ab→c")
      assert.same({ "0 ab", "2 →", "3 c" }, drawn(t, 0, true))
    end)

  it("draws the output on its ground again once the program's "
    .. "picture is gone, and then lets it be", function()
    local t = view_term()
    t:print("ab")
    assert.same({ "0 ab" }, drawn(t, 0, true))
    assert.same({ "back 0 20", "0 ab" }, drawn(t, 0))
    assert.same({ }, drawn(t, 0))
  end)

  --- The Compy's interpreter makes every call into love.graphics
  --- cost: a repaint of a full screen stays within a few calls a
  --- row, where a call or two for each cell were some 4,000.
  it("repaints a full screen in a few calls a row", function()
    for _, text in ipairs({
      "0001 ---------",
      "The quick brown fox",
    }) do
      local t = view_term()
      for y = 1, t.height do
        t:print(text .. (y < t.height and "\n" or ""))
      end
      drawn(t)
      assert.is_true(count <= 4 * t.height + 16, string.format(
        "%d calls into love.graphics for %d rows of %q", count,
        t.height, text))
    end
  end)
end)

describe("bounded", function()
  it("puts the JIT and the hook back at the count's edge",
    function()
      local before = function() end
      debug.sethook(before, "", 1e9)
      local was_on = jit and jit.status()
      local left = {}
      for n = 900, 1010 do
        local returned = pcall(bounded,
          function() for _ = 1, n do end end, 1000)
        local hook = debug.gethook()
        local on = jit and jit.status()
        --- put back at once, should bounded() have left it out
        debug.sethook(before, "", 1e9)
        if was_on then jit.on() end
        if not returned or hook ~= before or on ~= was_on then
          table.insert(left, n)
        end
      end
      debug.sethook()
      assert.same({}, left)
    end)
end)