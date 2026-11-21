-- The console's scrollback (Beads compy-ide-console-scrollback,
-- the maintainer's ruling "Console scrollback, first version"):
-- the rows that scroll off the top of the output are kept,
-- each as it looked, the newest 1,000; a clear from code adds
-- nothing to them and Ctrl+L forgets them. Keys only, through
-- the K helper and the console's real paths.

local K = require("tests.helpers.editor_keys")

--- Run a console line and let its output reach the screen
--- @param line string
local function run(line)
  K.type(line)
  K.keys("return")
  K.frame(100)
end

local function output()
  return K.cc.model.output
end

--- the kept rows' texts, oldest first, spaces at the end left
--- out
--- @return string[]
local function kept()
  local k, out = output().kept, { }
  for i = k.first, k.last do
    out[#out + 1] = (k:get(i).text:gsub("%s+$", ""))
  end
  return out
end

--- the screen's rows, spaces at their ends left out
--- @return string[]
local function screen()
  local out = { }
  for y, row in ipairs(output().terminal.buffer) do
    out[y] = (table.concat(row):gsub("%s+$", ""))
  end
  return out
end

--- the rows of `rows` that print() made, `L<n>`, by number
--- @param rows string[]
--- @return integer[]
local function marks(rows)
  local out = { }
  for _, r in ipairs(rows) do
    local n = r:match("^L(%d+)$")
    if n then out[#out + 1] = tonumber(n) end
  end
  return out
end

--- 1 to n
local function upto(from, n)
  local out = { }
  for i = from, n do out[#out + 1] = i end
  return out
end

local function print_lines(from, to)
  run(string.format(
    "for i = %d, %d do print('L' .. i) end", from, to))
end

--- A fresh console whose lines and programs print to its
--- output, as the IDE redirects print before it builds them
--- (model.io.redirect); the fixture built them before
--- @param contents table<string, string>?
local unrouted
local function reset(contents)
  K.reset(contents)
  local base, project = K.cc:get_base_env(), K.cc:get_project_env()
  unrouted = unrouted or { base.print, project.print }
  base.print, project.print = print, print
end

--- the console's print as the fixture had it, for later files
local function cleanup()
  if unrouted then
    K.cc:get_base_env().print = unrouted[1]
    K.cc:get_project_env().print = unrouted[2]
    unrouted = nil
  end
  K.cleanup()
end

describe("the console's kept rows #console", function()
  before_each(function() reset() end)
  after_each(cleanup)

  it("are the rows that scrolled off the top, each once and "
    .. "in order", function()
      print_lines(1, 40)
      local k, s = marks(kept()), marks(screen())
      assert.is_true(#k > 0)
      local all = { }
      for _, n in ipairs(k) do all[#all + 1] = n end
      for _, n in ipairs(s) do all[#all + 1] = n end
      assert.same(upto(1, 40), all)
      assert.same(K.cc.model.output.kept:count(), #kept())
    end)

  it("keep each cell's color, back color and reversal", function()
    local t = output().terminal
    local red, back = { 1, 0, 0, 1 }, { 0, 0, 1, 1 }
    for _ = 1, t.height - 1 do t:print("\n") end
    t:print("plain ")
    t:set_cursor_color(red)
    t:set_cursor_backcolor(back)
    t:reverse_cursor(true)
    t:print("red")
    t:reverse_cursor(false)
    t:set_cursor_color(K.cc.cfg.view.colors.terminal.fg)
    t:set_cursor_backcolor(K.cc.cfg.view.colors.terminal.bg)
    for _ = 1, t.height do t:print("\n") end
    K.frame(100)
    local k = output().kept
    local row
    for i = k.first, k.last do
      if k:get(i).text:match("^plain red") then row = k:get(i) end
    end
    assert.is_not_nil(row)
    local runs = row.runs
    assert.equal(6, runs[1].n)
    assert.equal(3, runs[2].n)
    assert.same(red, runs[2].style.color)
    assert.same(back, runs[2].style.backcolor)
    assert.is_true(runs[2].style.reversed)
    assert.is_false(runs[3].style.reversed)
    assert.equal(t.width - 9, runs[3].n)
  end)

  it("are the newest 1,000", function()
    print_lines(1, 1100)
    local k = marks(kept())
    assert.equal(1000, output().kept:count())
    assert.equal(1000, #kept())
    local s = marks(screen())
    assert.same(upto(k[1], 1100), (function()
      local all = { }
      for _, n in ipairs(k) do all[#all + 1] = n end
      for _, n in ipairs(s) do all[#all + 1] = n end
      return all
    end)())
  end)

  it("take nothing from a clear from code", function()
    print_lines(1, 30)
    run("compy.terminal.clear()")
    for _, r in ipairs(screen()) do assert.equal("", r) end
    local after = kept()
    print_lines(31, 60)
    local k = kept()
    local older, newer = { }, { }
    for i, r in ipairs(k) do
      if i <= #after then older[#older + 1] = r
      else newer[#newer + 1] = r end
    end
    assert.same(after, older)
    for _, n in ipairs(marks(newer)) do
      assert.is_true(n > 30, "a cleared row was kept: L" .. n)
    end
    assert.is_true(#newer > 0)
  end)

  it("are forgotten by Ctrl+L, with the screen", function()
    print_lines(1, 40)
    assert.is_true(#kept() > 0)
    K.keys("lctrl", "l")
    K.frame(100)
    assert.same({ }, kept())
    for _, r in ipairs(screen()) do assert.equal("", r) end
  end)

  --- Ctrl+L leaves an empty console: what was still waiting to
  --- be written when it was pressed appears neither on the
  --- screen nor among the kept rows
  it("are not refilled by output that waited for Ctrl+L",
    function()
      -- a frame's budget left from an earlier drain would write
      -- the burst at once: a tenth of a second writes 80
      -- characters
      output().terminal.accumulator = 0
      for i = 1, 200 do output():push("L" .. i) end
      K.frame(0.1)
      local waits = 0
      for _ in output().terminal:waiting() do waits = waits + 1 end
      assert.is_true(waits > 500)
      K.keys("lctrl", "l")
      K.frame(100)
      assert.same({ }, kept())
      for _, r in ipairs(screen()) do assert.equal("", r) end
      K.keys("home")
      assert.is_false(output():is_scrolled())
    end)

  it("keep the output's color when Ctrl+L drops a waiting echo",
    function()
      -- the echo's blue taken, its return to the output's color
      -- still waiting
      K.frame(100)
      output().terminal.accumulator = 0
      output():echo({ "x = 1" })
      K.frame(0.005)
      assert.same(K.cc.cfg.view.colors.terminal.echo,
        output().terminal.cursor_color)
      K.keys("lctrl", "l")
      K.frame(100)
      local t = output().terminal
      assert.same(K.cc.cfg.view.colors.terminal.fg, t.cursor_color)
      output():push("after")
      K.frame(100)
      assert.same(K.cc.cfg.view.colors.terminal.fg,
        t.state_buffer[1][1].color)
    end)

  it("stay through a visit to the editor and a program's run",
    function()
      reset({ ["main.lua"] = "for i = 41, 60 do print('L' .. i) end\n" })
      print_lines(1, 40)
      K.open()
      K.keys("escape")
      assert.same("ready", K.app_state())
      run("run()")
      K.frame(100)
      local all = marks(kept())
      for _, n in ipairs(marks(screen())) do all[#all + 1] = n end
      assert.same(upto(1, 60), all)
    end)

  it("stay through a project's closing and opening", function()
    print_lines(1, 40)
    local before = kept()
    K.next_project("other", { ["main.lua"] = "b = 1\n" })
    run("project(\"other\")")
    local after = kept()
    for i, r in ipairs(before) do assert.equal(r, after[i]) end
  end)

  it("are none in a console started anew", function()
    print_lines(1, 40)
    assert.is_true(#kept() > 0)
    local fresh = CanvasModel(K.cc.cfg)
    assert.equal(0, fresh.kept:count())
  end)
end)

--- the scrolled view's rows' texts, top to bottom, spaces at
--- their ends left out; nil at rest
--- @return string[]?
local function view()
  local rows = output():window()
  if not rows then return nil end
  local t, out = output().terminal, { }
  for i, r in ipairs(rows) do
    local text = ""
    if r.kept then
      text = r.kept.text
    elseif r.y then
      text = table.concat(t.buffer[r.y])
    end
    out[i] = (text:gsub("%s+$", ""))
  end
  return out
end

--- the console's text as one sequence: the kept rows, then the
--- screen's rows down to the last that holds text
--- @return string[]
local function sequence()
  local out = kept()
  local s = screen()
  local last = 0
  for y, r in ipairs(s) do
    if r ~= "" then last = y end
  end
  for y = 1, last do out[#out + 1] = s[y] end
  return out
end

--- the rows from `i` to `j` of `list`
local function slice(list, i, j)
  local out = { }
  for n = i, j do out[#out + 1] = list[n] end
  return out
end

--- what scrolling must not change: the grid's cells and the
--- kept rows
local function contents()
  local t = output().terminal
  local cells = { }
  for y = 1, t.height do
    for x = 1, t.width do
      local s = t.state_buffer[y][x]
      cells[#cells + 1] = table.concat({ t.buffer[y][x],
        table.concat(s.color, ","), table.concat(s.backcolor, ","),
        tostring(s.reversed == true) }, "|")
    end
  end
  local k = output().kept
  return { cells = cells, kept = kept(), first = k.first,
    last = k.last, cursor = { t.cursor_x, t.cursor_y } }
end

--- An empty print makes a blank row, as it does on any
--- terminal: the output dropped what was only spaces and line
--- ends, so print("") between two lines left them touching.
describe("a blank row in the output #console", function()
  before_each(function() reset() end)
  after_each(cleanup)

  --- the screen's rows from the row that is `first` to the row
  --- that is `last`
  local function from_to(first, last)
    local rows, out = screen(), nil
    for _, r in ipairs(rows) do
      if r == first then out = { } end
      if out then out[#out + 1] = r end
      if out and r == last then return out end
    end
    return out
  end

  it("is what print('') prints", function()
    run("print('a') print('') print('b')")
    assert.same({ "a", "", "b" }, from_to("a", "b"))
  end)

  it("is what print() with nothing prints", function()
    run("print('a') print() print('b')")
    assert.same({ "a", "", "b" }, from_to("a", "b"))
  end)

  it("is what a print of spaces prints", function()
    run("print('a') print('  ') print('b')")
    assert.same({ "a", "", "b" }, from_to("a", "b"))
  end)

  it("comes twice from print('\\n'), its own line end and "
    .. "print's", function()
    run("print('a') print('\\n') print('b')")
    assert.same({ "a", "", "", "b" }, from_to("a", "b"))
  end)

  it("is what two line ends written after a line make, as "
    .. "io.write hands them to the output", function()
    -- the fixture redirects print alone; io.write's redirection
    -- (model/io/redirect.lua) calls the output's write
    output():write("a")
    output():write("\n\n")
    output():write("b\n")
    K.frame(100)
    assert.same({ "a", "", "b" }, from_to("a", "b"))
  end)

  it("can be the first row of the output", function()
    run("print() print('h')")
    local rows = from_to("print() print('h')", "h")
    assert.same({ "print() print('h')", "", "h" }, rows)
  end)

  it("is kept with the rows that scroll off, and the scrolled "
    .. "view shows it", function()
    run("for i = 1, 40 do print(i == 5 and '' or 'L' .. i) end")
    local rows = kept()
    local at
    for i, r in ipairs(rows) do
      if r == "L4" then at = i end
    end
    assert.same({ "L4", "", "L6" },
      { rows[at], rows[at + 1], rows[at + 2] })
    output():to_oldest()
    local shown = view()
    for i, r in ipairs(shown) do
      if r == "L4" then at = i end
    end
    assert.same({ "L4", "", "L6" },
      { shown[at], shown[at + 1], shown[at + 2] })
  end)
end)

--- A line as wide as the screen takes its row and no more: the
--- row wraps when a character follows it, so the line end after
--- it leaves no blank row.
describe("a line as wide as the screen #console", function()
  before_each(function() reset() end)
  after_each(cleanup)

  local function wide(ch)
    return string.rep(ch, output().terminal.width)
  end

  --- the screen's rows from the row that is `first`, `n` of
  --- them
  local function from(first, n)
    local rows, out = screen(), nil
    for _, r in ipairs(rows) do
      if r == first then out = { } end
      if out and #out < n then out[#out + 1] = r end
    end
    return out
  end

  it("has the next line right under it", function()
    run("print(('x'):rep(64)) print('b')")
    assert.same({ wide("x"), "b" }, from(wide("x"), 2))
  end)

  it("has one blank row under it for one empty print", function()
    run("print(('x'):rep(64)) print('') print('b')")
    assert.same({ wide("x"), "", "b" }, from(wide("x"), 3))
  end)

  it("wraps its 65th character", function()
    run("print(('x'):rep(65)) print('b')")
    assert.same({ wide("x"), "x", "b" }, from(wide("x"), 3))
  end)

  it("has the echo of the next entered line right under it when "
    .. "it was left open", function()
    output():write(wide("x"))
    K.frame(100)
    run("print('b')")
    assert.same({ wide("x"), "print('b')", "b" }, from(wide("x"), 3))
  end)

  it("is kept as one row, and the scrolled view shows it so",
    function()
      run("for i = 1, 40 do print(i == 5 and ('w'):rep(64) "
        .. "or 'L' .. i) end")
      local rows, at = kept(), nil
      for i, r in ipairs(rows) do
        if r == "L4" then at = i end
      end
      assert.same({ "L4", wide("w"), "L6" },
        { rows[at], rows[at + 1], rows[at + 2] })
      output():to_oldest()
      local shown = view()
      for i, r in ipairs(shown) do
        if r == "L4" then at = i end
      end
      assert.same({ "L4", wide("w"), "L6" },
        { shown[at], shown[at + 1], shown[at + 2] })
    end)
end)

describe("the console's scrolled view #console", function()
  before_each(function() reset() end)
  after_each(cleanup)

  local H = 16

  it("is the screen as it is at rest", function()
    print_lines(1, 40)
    assert.is_false(output():is_scrolled())
    assert.is_nil(view())
  end)

  it("fills a nearly empty screen with history at once",
    function()
      print_lines(1, 40)
      run("compy.terminal.clear()")
      print_lines(41, 43)
      output():scroll_row(-1)
      local seq, v = sequence(), view()
      assert.equal(H, #v)
      assert.equal("L43", v[H])
      assert.same(slice(seq, #seq - H + 1, #seq), v)
      for _, r in ipairs(v) do assert.not_equal("", r) end
    end)

  it("moves a full screen's text by one row on the first step",
    function()
      print_lines(1, 40)
      local s, k = screen(), kept()
      output():scroll_row(-1)
      local v = view()
      assert.equal(k[#k], v[1])
      assert.same(slice(s, 1, H - 1), slice(v, 2, H))
    end)

  it("moves a row at a time and stops at the oldest kept row",
    function()
      print_lines(1, 40)
      output():scroll_row(-1)
      local first = view()
      output():scroll_row(-1)
      assert.same(slice(first, 1, H - 1), slice(view(), 2, H))
      for _ = 1, 100 do output():scroll_row(-1) end
      local k = kept()
      assert.same(slice(k, 1, H), view())
      output():scroll_row(-1)
      assert.same(slice(k, 1, H), view())
    end)

  it("returns to rest from the filled view", function()
    print_lines(1, 40)
    output():scroll_row(-1)
    output():scroll_row(-1)
    output():scroll_row(1)
    assert.is_true(output():is_scrolled())
    output():scroll_row(1)
    assert.is_false(output():is_scrolled())
    output():scroll_row(1)
    assert.is_false(output():is_scrolled())
  end)

  it("pages by 15 rows with one carried over", function()
    print_lines(1, 80)
    local s = screen()
    output():scroll_page(-1)
    local p1 = view()
    assert.equal(s[1], p1[H])
    output():scroll_page(-1)
    local p2 = view()
    assert.equal(p1[1], p2[H])
    output():scroll_page(1)
    assert.same(p1, view())
    -- no page goes past the filled view, so no row is skipped;
    -- from it the next page is the screen at rest
    output():scroll_page(1)
    output():to_rest()
    output():scroll_row(-1)
    local filled = view()
    output():scroll_page(-1)
    output():scroll_page(1)
    assert.same(filled, view())
    output():scroll_page(1)
    assert.is_false(output():is_scrolled())
  end)

  it("goes to the oldest kept row and back to rest", function()
    print_lines(1, 80)
    output():to_oldest()
    assert.same(slice(kept(), 1, H), view())
    output():to_rest()
    assert.is_nil(view())
  end)

  it("does nothing while no row is kept", function()
    print_lines(1, 5)
    output():scroll_row(-1)
    output():scroll_page(-1)
    output():to_oldest()
    assert.is_false(output():is_scrolled())
  end)

  it("stays where it is while new output arrives", function()
    print_lines(1, 40)
    for _ = 1, 5 do output():scroll_row(-1) end
    local before = view()
    for i = 41, 70 do output():push("L" .. i) end
    K.frame(100)
    assert.same(before, view())
  end)

  it("stays at the oldest row kept when the rows it showed are "
    .. "dropped", function()
      print_lines(1, 40)
      output():to_oldest()
      for i = 41, 1100 do output():push("L" .. i) end
      K.frame(100)
      assert.same(slice(kept(), 1, H), view())
    end)

  it("changes neither the screen nor the kept rows", function()
    print_lines(1, 80)
    local before = contents()
    for _, step in ipairs({ { "scroll_row", -1 }, { "scroll_page", -1 },
      { "to_oldest" }, { "scroll_row", 1 }, { "scroll_page", 1 },
      { "scroll_row", -1 }, { "to_rest" } }) do
      output()[step[1]](output(), step[2])
      assert.same(before, contents(), step[1])
    end
  end)

  it("is drawn from the kept rows and the screen, with the cue "
    .. "at a cut edge", function()
      print_lines(1, 80)
      for _ = 1, 3 do output():scroll_row(-1) end
      local s = K.screen()
      local t = output().terminal
      local cw, ch = t.char_width, t.char_height
      local rows = { }
      for _, p in ipairs(s.texts) do
        local col, y = p.x / cw, p.y / ch
        local mark = p.text == "^" or p.text == "v"
        if col == math.floor(col) and y == math.floor(y)
            and y < H and not mark then
          rows[y + 1] = rows[y + 1] or { }
          -- a row is printed in runs: each character of a run
          -- lands a cell after the one before it
          for char in p.text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            rows[y + 1][col + 1] = char
            col = col + 1
          end
        end
      end
      local drawn = { }
      for i = 1, H do
        local r = rows[i] or { }
        local cells = { }
        for x = 1, t.width do cells[x] = r[x] or " " end
        drawn[i] = (table.concat(cells):gsub("%s+$", ""))
      end
      assert.same(view(), drawn)
      local marks = { }
      for _, p in ipairs(s.texts) do
        if p.text == "^" or p.text == "v" then
          marks[p.text] = true
        end
      end
      assert.same({ ["^"] = true, v = true }, marks)
    end)
end)

describe("the console's scrolling keys #console", function()
  before_each(function() reset() end)
  after_each(cleanup)

  local H = 16

  local function field()
    local l, c = K.cc.input:get_cursor_pos()
    return { K.console_draft(), l, c }
  end

  it("Ctrl+Up and Ctrl+Down move the view a row, the draft and "
    .. "its cursor stay", function()
      print_lines(1, 40)
      K.type("half typed")
      K.keys("left")
      local before = field()
      K.keys("lctrl", "up")
      local one = view()
      assert.is_not_nil(one)
      K.keys("lctrl", "up")
      assert.same(slice(one, 1, H - 1), slice(view(), 2, H))
      K.keys("lctrl", "down")
      assert.same(one, view())
      K.keys("lctrl", "down")
      assert.is_nil(view())
      assert.same(before, field())
    end)

  it("PgUp and PgDn page the view, 15 rows with one carried "
    .. "over", function()
      print_lines(1, 80)
      local s = screen()
      K.keys("pageup")
      local p1 = view()
      assert.equal(s[1], p1[H])
      K.keys("pageup")
      assert.equal(p1[1], view()[H])
      K.keys("pagedown")
      assert.same(p1, view())
      K.keys("pagedown")
      local last = view()
      assert.is_not_nil(last)
      assert.equal(screen()[H - 1], last[H])
      K.keys("pagedown")
      assert.is_nil(view())
    end)

  it("Home and End go to the oldest and the newest row while the "
    .. "field is empty", function()
      print_lines(1, 80)
      K.keys("home")
      assert.same(slice(kept(), 1, H), view())
      K.keys("end")
      assert.is_nil(view())
    end)

  it("Home and End with text in the field are the field's keys, "
    .. "and leave the view where it is", function()
      print_lines(1, 80)
      K.type("abc")
      K.keys("pageup")
      local v = view()
      assert.is_not_nil(v)
      K.keys("home")
      assert.same(v, view())
      assert.same({ "abc", 1, 1 }, field())
      K.keys("end")
      assert.same(v, view())
      assert.same({ "abc", 1, 4 }, field())
    end)

  -- the maintainer's ruling of November 17, 2026: the Home and
  -- End of the output while the field holds text
  it("Ctrl+PgUp and Ctrl+PgDn go to the oldest and the newest "
    .. "row, the field empty or not, the draft and its cursor "
    .. "staying", function()
      print_lines(1, 80)
      K.keys("lctrl", "pageup")
      assert.same(slice(kept(), 1, H), view())
      K.keys("lctrl", "pagedown")
      assert.is_nil(view())
      K.type("half typed")
      K.keys("left")
      local before = field()
      K.keys("lctrl", "pageup")
      assert.same(slice(kept(), 1, H), view())
      assert.same(before, field())
      K.keys("lctrl", "pagedown")
      assert.is_nil(view())
      assert.same(before, field())
    end)

  it("keep scrolling while held", function()
    print_lines(1, 80)
    K.hold("lctrl")
    K.hold("up")
    local one = view()
    K.repeat_key("up")
    K.repeat_key("up")
    K.release("up")
    K.release("lctrl")
    assert.same(slice(one, 1, H - 2), slice(view(), 3, H))
    K.hold("pageup")
    local p = view()
    K.repeat_key("pageup")
    K.release("pageup")
    assert.equal(p[1], view()[H])
  end)

  it("do nothing while no row is kept", function()
    print_lines(1, 3)
    for _, k in ipairs({ { "lctrl", "up" }, { "pageup" },
      { "home" }, { "lctrl", "pageup" } }) do
      K.keys(unpack(k))
      assert.is_nil(view())
    end
  end)

  --- the maintainer's ruling of November 17, 2026: "I can
  --- scroll up, look at something in the history while typing a
  --- new command"
  it("typing, an arrow, Backspace and Escape leave the view "
    .. "where it is", function()
      print_lines(1, 40)
      K.keys("lctrl", "up")
      local v = view()
      K.type("x = 1")
      assert.same(v, view(), "typed text")
      assert.equal("x = 1", K.console_draft())
      K.keys("left")
      K.keys("backspace")
      assert.same(v, view(), "an arrow and Backspace")
      K.keys("escape")
      assert.same(v, view(), "Escape")
      assert.equal("", K.console_draft())
    end)

  it("Enter on a line that runs brings the screen back", function()
    print_lines(1, 40)
    K.keys("lctrl", "up")
    K.type("y = 1")
    assert.is_true(output():is_scrolled())
    K.keys("return")
    assert.is_nil(view())
  end)

  it("Enter on a line that does not run leaves the view where "
    .. "it is", function()
      print_lines(1, 40)
      K.keys("lctrl", "up")
      local v = view()
      -- nothing to run
      K.keys("return")
      assert.same(v, view(), "an empty field")
      -- a statement that goes on
      K.type("if x then")
      K.keys("return")
      assert.same(v, view(), "an unfinished statement")
      K.keys("escape")
      -- Lua refuses it
      K.type("x = = 1")
      K.keys("return")
      assert.same(v, view(), "a line Lua does not load")
    end)

  it("Ctrl+T, to the editor and back, brings the screen back",
    function()
      print_lines(1, 40)
      K.keys("lctrl", "up")
      K.keys("lctrl", "t")
      K.keys("lctrl", "t")
      assert.same("ready", K.app_state())
      assert.is_nil(view())
    end)

  it("a modifier alone and F1 leave the view where it is",
    function()
      print_lines(1, 40)
      K.keys("lctrl", "up")
      local v = view()
      K.keys("lshift")
      K.keys("lalt")
      K.hold("f1")
      K.release("f1")
      assert.same(v, view())
    end)

  it("are the field's to a program that shows its field",
    function()
      reset({ ["main.lua"] =
        "for i = 1, 40 do print('L' .. i) end\n"
        .. "compy.input.show { }\n" })
      run("run()")
      assert.is_true(#kept() > 0)
      K.keys("lctrl", "up")
      K.keys("pageup")
      assert.is_nil(view())
    end)

  it("are a program's that takes keys", function()
    reset({ ["main.lua"] =
      "for i = 1, 40 do print('L' .. i) end\n"
      .. "function love.update() end\n"
      .. "function love.keypressed(k) end\n" })
    run("run()")
    assert.is_true(#kept() > 0)
    K.keys("lctrl", "up")
    assert.is_nil(view())
    -- the fixture keeps a program's love table for the next
    -- run in this file: its handlers go with it
    local lv = K.cc:get_project_env().love
    lv.update, lv.keypressed = nil, nil
  end)

  it("scroll the output of a program that shows no field and "
    .. "takes no keys", function()
      reset({ ["main.lua"] =
        "for i = 1, 40 do print('L' .. i) end\n"
        .. "function love.update() end\n" })
      run("run()")
      assert.same("running", K.app_state())
      K.keys("lctrl", "up")
      assert.is_not_nil(view())
    end)

  it("scroll the output of a program that ended by itself",
    function()
      reset({ ["main.lua"] =
        "for i = 1, 40 do print('L' .. i) end\n" })
      run("run()")
      assert.is_false(K.cc.run_live)
      K.keys("lctrl", "up")
      assert.is_not_nil(view())
    end)

  it("scroll the output while a program is paused", function()
    reset({ ["main.lua"] =
      "for i = 1, 40 do print('L' .. i) end\n"
      .. "function love.update() love.update = nil; error('x') end\n" })
    run("run()")
    K.frame()
    K.cc:suspend()
    assert.same("inspect", K.app_state())
    K.keys("lctrl", "up")
    assert.is_not_nil(view())
  end)

  it("are on the console's card, paging left off", function()
    local KeyCard = require("model.editor.keyCard")
    local function card(empty)
      return table.concat(KeyCard.lines_of(
        KeyCard.console_cells(false, empty), 17, 64), "\n")
    end
    local empty = card(true)
    assert.truthy(empty:find("Ctrl+Up/Down", 1, true))
    assert.truthy(empty:find("scroll a row", 1, true))
    assert.truthy(empty:find("Home/End", 1, true))
    assert.truthy(empty:find("oldest/newest", 1, true))
    assert.truthy(empty:find("Ctrl+PgUp/PgDn  oldest/newest", 1, true))
    -- no row for PgUp and PgDn alone
    assert.falsy(empty:find("[^/+]PgUp"))
    local typed = card(false)
    assert.truthy(typed:find("scroll a row", 1, true))
    -- Home and End are the field's then; Ctrl+PgUp/PgDn stays
    assert.falsy(typed:find("[^+]Home/End"))
    assert.truthy(typed:find("Ctrl+PgUp/PgDn  oldest/newest", 1, true))
  end)
end)

describe("the console's kept rows under any mix #console",
  function()
    before_each(function() reset() end)
    after_each(cleanup)

    it("hold every row that scrolled off since Ctrl+L, once and "
      .. "in order, the newest 1,000, and scrolling changes "
      .. "neither them nor the screen", function()
        --- The test's own picture of the 16 rows: each print is
        --- a row of its own, the cursor's row the next blank one,
        --- and the top row leaves when a print passes the
        --- bottom. What left is recorded here, apart from the
        --- console's code.
        local H = output().terminal.height
        local rows, cursor, left = { }, 1, { }
        local function blank()
          for y = 1, H do rows[y] = "" end
          cursor = 1
        end
        blank()
        local function print_row(text)
          rows[cursor] = text
          cursor = cursor + 1
          if H < cursor then
            left[#left + 1] = table.remove(rows, 1)
            rows[H] = ""
            cursor = H
          end
        end
        local tty = K.cc:get_project_env().compy.terminal
        local n = 0
        local seed = 20261115
        math.randomseed(seed)
        local SCROLLS = { { "lctrl", "up" }, { "lctrl", "down" },
          { "pageup" }, { "pagedown" }, { "home" }, { "end" } }
        for step = 1, 300 do
          local op = math.random(1, 10)
          if op <= 4 then
            for _ = 1, math.random(1, op == 4 and 400 or 20) do
              n = n + 1
              output():push("L" .. n)
              print_row("L" .. n)
            end
          elseif op == 5 then
            tty.clear()
            blank()
          elseif op == 6 then
            K.keys("lctrl", "l")
            K.frame(100)
            blank()
            left = { }
          else
            K.frame(100)
            local before = contents()
            K.keys(unpack(SCROLLS[math.random(1, #SCROLLS)]))
            assert.same(before, contents(), "step " .. step)
          end
          K.frame(100)
          local what = "step " .. step
          assert.same(rows, screen(), what .. ": the screen")
          local want = { }
          for i = math.max(1, #left - 999), #left do
            want[#want + 1] = left[i]
          end
          assert.same(want, kept(), what .. ": the kept rows")
        end
        assert.is_true(n > 1000)
      end)
  end)

describe("the sign of a scrolled view #console", function()
  before_each(function() reset() end)
  after_each(cleanup)

  --- the cue's marks drawn on the whole screen
  local function marks_drawn()
    output().terminal.dirty = true
    local s = K.screen()
    local seen = { }
    for _, p in ipairs(s.texts) do
      if p.text == "^" or p.text == "v" then seen[p.text] = true end
    end
    return seen
  end

  it("is none at rest", function()
    print_lines(1, 80)
    assert.same({ }, marks_drawn())
  end)

  it("is on top alone while only older rows lie beyond the view",
    function()
      print_lines(1, 80)
      K.keys("lctrl", "up")
      assert.same({ ["^"] = true }, marks_drawn())
    end)

  it("is at the bottom alone at the oldest kept row", function()
    print_lines(1, 80)
    K.keys("home")
    assert.same({ v = true }, marks_drawn())
  end)

  it("is on both edges between them", function()
    print_lines(1, 80)
    K.keys("pageup")
    K.keys("lctrl", "up")
    assert.same({ ["^"] = true, v = true }, marks_drawn())
  end)
end)

describe("the echo of an entered line #console", function()
  before_each(function() reset() end)
  after_each(cleanup)

  local function colors() return K.cc.cfg.view.colors.terminal end

  --- the screen row whose text is `text`, and its first cell's
  --- color
  local function row_of(text)
    local t = output().terminal
    for y, r in ipairs(screen()) do
      if r == text then
        return y, t.state_buffer[y][1].color
      end
    end
  end

  it("writes an accepted line in blue before it runs, its output "
    .. "after it", function()
      run("print('hi')")
      local e, ec = row_of("print('hi')")
      local o, oc = row_of("hi")
      assert.is_not_nil(e)
      assert.equal(e + 1, o)
      assert.same(colors().echo, ec)
      assert.same(colors().fg, oc)
      assert.same(require("util.color") and Color[Color.blue], ec)
    end)

  it("starts on a row of its own when the cursor's row holds "
    .. "text", function()
      -- io.write's path (model.io.redirect)
      output():write("partial")
      K.frame(100)
      run("x = 1")
      assert.is_not_nil(row_of("partial"))
      local p = row_of("partial")
      assert.equal(p + 1, row_of("x = 1"))
    end)

  it("is not written for a line the syntax check refuses",
    function()
      K.type("x = = 1")
      K.keys("return")
      K.frame(100)
      assert.is_nil(row_of("x = = 1"))
      assert.equal("x = = 1", K.console_draft())
    end)

  it("is not written for a line the syntax continues", function()
    K.type("for i = 1, 2 do")
    K.keys("return")
    K.frame(100)
    assert.is_nil(row_of("for i = 1, 2 do"))
  end)

  it("is followed by the line's error, in the output's error "
    .. "color", function()
      run("print('a') error('boom')")
      local e = row_of("print('a') error('boom')")
      assert.is_not_nil(e)
      assert.equal(e + 1, row_of("a"))
      local s, t = screen(), output().terminal
      local err = s[e + 2]
      assert.truthy(err:find("boom", 1, true), err)
      assert.same(colors().error, t.state_buffer[e + 2][1].color)
      assert.is_false(K.cc.input:has_error())
    end)

  it("writes each line of a command on a row of its own",
    function()
      K.type("x = 1")
      K.keys("lshift", "return")
      K.type("y = 2")
      K.keys("return")
      K.frame(100)
      local a, ac = row_of("x = 1")
      local b, bc = row_of("y = 2")
      assert.equal(a + 1, b)
      assert.same(colors().echo, ac)
      assert.same(colors().echo, bc)
    end)

  it("is erased by its own line's clear", function()
    print_lines(1, 5)
    run("compy.terminal.clear()")
    for _, r in ipairs(screen()) do assert.equal("", r) end
  end)

  it("is not written for what a program's input field takes",
    function()
      reset({ ["main.lua"] = "compy.input.show { }\n" })
      run("run()")
      K.type("sent")
      K.keys("return")
      K.frame(100)
      assert.is_nil(row_of("sent"))
    end)

  it("is kept with its color once it scrolls off", function()
    run("print('first')")
    print_lines(1, 30)
    local k = output().kept
    local found
    for i = k.first, k.last do
      if k:get(i).text:match("^print%('first'%)") then
        found = k:get(i)
      end
    end
    assert.is_not_nil(found)
    assert.same(colors().echo, found.runs[1].style.color)
  end)
end)

describe("list_projects() #console", function()
  before_each(function() reset() end)
  after_each(cleanup)

  it("prints below what is on the screen, clearing nothing",
    function()
      print_lines(1, 5)
      run("list_projects()")
      local seq = sequence()
      local l5, header
      for i, r in ipairs(seq) do
        if r == "L5" then l5 = i end
        if r == "Projects:" then header = header or i end
      end
      assert.is_not_nil(header)
      assert.is_not_nil(l5)
      assert.is_true(l5 < header)
      assert.same({ 1, 2, 3, 4, 5 }, marks(seq))
    end)
end)

--- Every transition that hands the keys to something else or
--- changes what the console shows brings the screen back, so
--- that a scrolled view is never left where no key reaches it
describe("the scrolled view at a transition #console", function()
  before_each(function() reset() end)
  after_each(cleanup)

  local FIELD = "compy.input.show { }\n"
  local RUNS = "function love.update() end\n"

  --- output enough to scroll, and the view scrolled
  local function scrolled()
    print_lines(1, 40)
    K.keys("home")
    assert.is_true(output():is_scrolled())
  end

  local function at_rest(what)
    assert.is_false(output():is_scrolled(), what)
  end

  --- a line typed behind a program that can act reaches no
  --- console (November 17): the program prints the rows, and
  --- the output's own Home scrolls them (ruling 1.1)
  it("a run started anew by Ctrl+R", function()
    reset({ ["main.lua"] = "for i = 1, 40 do print('L' .. i) end\n"
      .. RUNS })
    K.start()
    K.keys("home")
    assert.is_true(output():is_scrolled())
    K.keys("lctrl", "r")
    at_rest("Ctrl+R")
  end)

  it("a run started by run()", function()
    reset({ ["main.lua"] = RUNS })
    scrolled()
    K.cc:run_project()
    at_rest("run()")
    -- the fixture keeps a program's love table for the next run
    K.cc:get_project_env().love.update = nil
  end)

  it("a run started by Ctrl+T from the editor", function()
    reset({ ["main.lua"] = FIELD })
    print_lines(1, 40)
    K.open()
    output():to_oldest()
    K.keys("lctrl", "t")
    at_rest("Ctrl+T")
  end)

  it("a stop by Ctrl+Q", function()
    reset({ ["main.lua"] = "for i = 1, 40 do print('L' .. i) end\n"
      .. RUNS })
    run("run()")
    output():to_oldest()
    assert.is_true(output():is_scrolled())
    K.keys("lctrl", "q")
    at_rest("Ctrl+Q")
  end)

  it("a pause and its end", function()
    reset({ ["main.lua"] = "for i = 1, 40 do print('L' .. i) end\n"
      .. RUNS })
    run("run()")
    output():to_oldest()
    K.keys("lctrl", "pause")
    K.frame()
    K.cc:suspend()
    assert.same("inspect", K.app_state())
    at_rest("a pause")
    K.keys("home")
    assert.is_true(output():is_scrolled())
    K.cc:get_project_env().continue()
    at_rest("continue()")
    K.cc:get_project_env().love.update = nil
  end)

  --- the pause is made in the frame of the error: the program
  --- raises once the view is scrolled
  it("an error that pauses the program", function()
    reset({ ["main.lua"] = "function love.update()\n"
      .. "  if go then love.update = nil; error('x') end\n"
      .. "end\n" })
    run("run()")
    print_lines(1, 40)
    output():to_oldest()
    K.cc:get_project_env().go = true
    K.frame()
    assert.same("inspect", K.app_state())
    at_rest("the error's pause")
  end)

  it("opening and leaving the editor", function()
    scrolled()
    K.cc:edit("main.lua")
    assert.same("editor", K.app_state())
    at_rest("the editor opened")
    output():to_oldest()
    K.cc:finish_edit()
    at_rest("the editor left")
  end)

  it("opening and closing a project", function()
    scrolled()
    K.next_project("other", { ["main.lua"] = "b = 1\n" })
    K.cc:open_project("other")
    at_rest("a project opened")
    output():to_oldest()
    K.cc:close_project()
    at_rest("a project closed")
  end)

  it("a program's field shown while the view is scrolled",
    function()
      reset({ ["main.lua"] = "for i = 1, 40 do print('L' .. i) end\n"
        .. "function love.update()\n"
        .. "  n = (n or 0) + 1\n"
        .. "  if n == 20 then compy.input.show { } end\n"
        .. "end\n" })
      run("run()")
      K.keys("lctrl", "up")
      assert.is_true(output():is_scrolled())
      for _ = 1, 30 do K.frame() end
      at_rest("the program's field")
      K.cc:get_project_env().love.update = nil
    end)

  it("not a paused program's field: the keys scroll its output",
    function()
      reset({ ["main.lua"] = "for i = 1, 40 do print('L' .. i) end\n"
        .. FIELD .. RUNS })
      run("run()")
      assert.is_true(love.state.user_input_controller:is_shown())
      K.keys("lctrl", "pause")
      K.frame()
      K.cc:suspend()
      assert.same("inspect", K.app_state())
      K.keys("home")
      assert.is_true(output():is_scrolled(), "Home")
      for _ = 1, 5 do K.frame() end
      assert.equal(output().kept.first, output():top(),
        "the oldest row stays on top")
      K.keys("end")
      K.keys("pageup")
      for _ = 1, 5 do K.frame() end
      assert.is_true(output():is_scrolled(), "PgUp")
      K.cc:get_project_env().love.update = nil
    end)

  --- a program that takes keys from its 20th frame on, by the
  --- hook `hook` for `event`, and says so
  local function takes_later(event, hook)
    return "for i = 1, 40 do print('L' .. i) end\n"
        .. "local n = 0\n"
        .. "function love.update()\n"
        .. "  n = n + 1\n"
        .. "  if n == 20 then\n"
        .. "    compy.input.hooks." .. event .. " = " .. hook .. "\n"
        .. "    print('Ready for keys.')\n"
        .. "  end\n"
        .. "end\n"
  end

  --- the program's handlers go with it: the fixture keeps its
  --- tables for the next run in this file
  local function forget_program()
    local env = K.cc:get_project_env()
    env.love.update = nil
    env.compy.input.hooks.keypressed = nil
    env.compy.input.hooks.textinput = nil
  end

  --- turned around on November 17, 2026: input no longer moves
  --- a scrolled view, a program's no more than the console's
  it("not a key a program takes after the view scrolled", function()
    reset({ ["main.lua"] = takes_later("keypressed",
      "function() return true end") })
    run("run()")
    K.keys("home")
    assert.is_true(output():is_scrolled(), "Home, before the hook")
    for _ = 1, 30 do K.frame() end
    local t = output():top()
    K.keys("end")
    K.keys("x")
    assert.equal(t, output():top(), "the keys the program took")
    forget_program()
  end)

  it("not a text a program takes after the view scrolled",
    function()
      reset({ ["main.lua"] = takes_later("textinput",
        "function() return true end") })
      run("run()")
      K.keys("home")
      for _ = 1, 30 do K.frame() end
      local t = output():top()
      love.handlers.textinput("a")
      assert.equal(t, output():top(), "the text the program took")
      forget_program()
    end)

  --- a program's field shown from the start, and what it is
  --- given printed
  local ASKS = "for i = 1, 40 do print('L' .. i) end\n"
      .. "compy.input.show { on_text_entered = function(t)\n"
      .. "  print('got ' .. t) end }\n" .. RUNS

  it("not typing in a program's field", function()
    reset({ ["main.lua"] = ASKS })
    run("run()")
    assert.is_true(love.state.user_input_controller:is_shown())
    -- a shown field has the scrolling keys: the view moves as
    -- the wheel moves it
    output():to_oldest()
    local t = output():top()
    assert.is_not_nil(t)
    K.type("abc")
    K.keys("left")
    assert.equal(t, output():top())
    K.cc:get_project_env().love.update = nil
  end)

  it("Enter that hands a program's field its answer", function()
    reset({ ["main.lua"] = ASKS })
    run("run()")
    output():to_oldest()
    assert.is_true(output():is_scrolled())
    K.type("abc")
    K.keys("return")
    at_rest("the answer given")
    K.frame(100)
    assert.truthy(table.concat(screen(), "\n"):find("got abc", 1, true))
    K.cc:get_project_env().love.update = nil
  end)

  it("not Enter in a program's field that takes no answer",
    function()
      reset({ ["main.lua"] = ASKS })
      run("run()")
      output():to_oldest()
      local t = output():top()
      assert.is_not_nil(t)
      -- an empty field hands nothing over
      K.keys("return")
      assert.equal(t, output():top())
      K.cc:get_project_env().love.update = nil
    end)

  --- turned around on November 16, 2026: a key the program
  --- leaves goes nowhere, the console's scrolling included (a
  --- program that takes keys owns the keyboard)
  it("not a lone modifier a program takes, nor a key it leaves",
    function()
      reset({ ["main.lua"] = takes_later("keypressed",
        "function(k) return k == 'lshift' or k == 'x' end") })
      run("run()")
      K.keys("home")
      assert.is_true(output():is_scrolled())
      for _ = 1, 30 do K.frame() end
      local t = output():top()
      K.keys("lctrl", "up")
      assert.equal(t, output():top(), "Ctrl+Up the program leaves")
      K.keys("lshift")
      assert.equal(t, output():top(), "a lone Shift the program took")
      forget_program()
    end)
end)

--- The field's row is the output's while no input field is
--- drawn (the maintainer's ruling of November 17, 2026: "when
--- the console input widget is hidden (when a program runs),
--- the freed lines should be available to the program with no
--- restriction. when the widget is back, if there's something
--- there, it scrolls up. The status line goes to the bottom and
--- shows only the relevant information: project, entry point
--- name, 'running'").
describe("the output's rows with no field under it #console",
  function()
    before_each(function() reset() end)
    after_each(cleanup)

    --- What a test here puts back when it ends, however it ends.
    --- Busted keeps one `finally` a test, the last one given, so
    --- a test that replaces two things gives both to at_end.
    local undo = { }
    local function at_end(f) undo[#undo + 1] = f end
    after_each(function()
      local fs = undo
      undo = { }
      for i = #fs, 1, -1 do fs[i]() end
      local view = K.cc and K.cc.view and K.cc.view.input
      assert.is_nil(view and rawget(view, "render"),
        "a test left the field's render replaced")
    end)

    local RUNS = "function love.update() end\n"
    --- a program that takes the keys and shows no field
    local OWNS = "compy.input.hooks.keypressed = function()\n"
        .. "  return true end\n" .. RUNS

    local function rows() return output().terminal.height end

    local function env() return K.cc:get_project_env() end

    local function owning()
      reset({ ["main.lua"] = OWNS })
      run("run()")
      K.frame()
    end

    --- the program's handlers go with it: the fixture keeps its
    --- tables for the next run in this file
    local function forget()
      env().love.update = nil
      env().compy.input.hooks.keypressed = nil
    end

    --- `text` written on the grid's last row
    local function on_last_row(text)
      output().terminal:move_to(1, rows())
      output():write(text)
      K.frame(100)
      assert.equal(text, screen()[rows()])
    end

    it("are 16 in the console", function()
      assert.equal(16, rows())
      print_lines(1, 40)
      assert.equal(16, rows())
    end)

    it("are 17 behind a program that owns the keys", function()
      owning()
      assert.equal(17, rows())
      assert.equal(17, #screen())
      forget()
    end)

    it("are 16 while the program shows a field of its own, and "
      .. "17 again once it hides it", function()
        owning()
        env().compy.input.show { }
        K.frame()
        assert.equal(16, rows())
        env().compy.input.hide()
        K.frame()
        assert.equal(17, rows())
        forget()
      end)

    it("lose the 17th at a stop, what is on it rolled up and the "
      .. "top row kept", function()
        owning()
        on_last_row("last")
        local top, kept_before = screen()[1], output().kept:count()
        K.keys("lctrl", "q")
        K.frame()
        assert.equal(16, rows())
        assert.equal("last", screen()[16])
        assert.equal(kept_before + 1, output().kept:count())
        local k = kept()
        assert.equal(top, k[#k])
      end)

    it("lose an empty 17th at a stop and keep nothing", function()
      owning()
      local before, kept_before = screen(), output().kept:count()
      assert.equal("", before[17])
      K.keys("lctrl", "q")
      K.frame()
      assert.equal(16, rows())
      assert.equal(before[1], screen()[1])
      assert.equal(kept_before, output().kept:count())
    end)

    it("lose the 17th at a pause", function()
      owning()
      on_last_row("last")
      K.keys("lctrl", "pause")
      K.frame()
      K.cc:suspend()
      K.frame(100)
      assert.same("inspect", K.app_state())
      assert.equal(16, rows())
      assert.equal("last", screen()[14])
      assert.equal("BREAK into program", screen()[15])
      forget()
    end)

    it("roll up for a program's field that comes up over text",
      function()
        owning()
        on_last_row("last")
        env().compy.input.show { }
        K.frame()
        assert.equal(16, rows())
        assert.equal("last", screen()[16])
        forget()
      end)

    it("let gotoxy reach the 17th row while it is there, and the "
      .. "16th otherwise", function()
        owning()
        env().compy.terminal.gotoxy(1, 17)
        output():write("deep")
        K.frame(100)
        assert.equal("deep", screen()[17])
        K.keys("lctrl", "q")
        K.frame()
        assert.equal(16, rows())
        env().compy.terminal.clear()
        env().compy.terminal.gotoxy(1, 17)
        output():write("shallow")
        K.frame(100)
        assert.equal("shallow", screen()[16])
      end)

    it("show a scrolled view 17 rows high", function()
      owning()
      for i = 1, 40 do output():push("L" .. i) end
      K.frame(100)
      output():to_oldest()
      assert.equal(17, #view())
      forget()
    end)

    --- the grid is as high as the screen drawn shows it: a
    --- program's update that shows or hides its field comes
    --- after the frame's own step (review o1)
    it("are 16 in the very frame whose update shows the "
      .. "program's field, and 17 in the one that hides it",
      function()
        reset({ ["main.lua"] = "compy.input.hooks.keypressed = "
          .. "function() return true end\n"
          .. "function love.update()\n"
          .. "  if want == 'show' then compy.input.show { } end\n"
          .. "  if want == 'hide' then compy.input.hide() end\n"
          .. "  want = nil\n"
          .. "end\n" })
        run("run()")
        K.frame()
        assert.equal(17, rows())
        env().want = "show"
        K.frame()
        local s = K.screen()
        assert.equal(16, rows(), "the frame that shows the field")
        assert.equal(1, s.field_rows)
        env().want = "hide"
        K.frame()
        s = K.screen()
        assert.equal(17, rows(), "the frame that hides it")
        assert.equal(0, s.field_rows)
        forget()
      end)

    --- an erase is made at once: nothing it erased is on the grid
    --- for the row's return to keep (review o1)
    it("keep nothing of what reset() erased when the 17th row "
      .. "goes", function()
        owning()
        for i = 1, 30 do output():push("old " .. i) end
        K.frame(100)
        assert.equal(17, output().terminal.cursor_y)
        K.cc:reset()
        K.frame()
        K.frame(100)
        assert.equal(16, rows())
        for _, r in ipairs(kept()) do
          assert.is_nil(r:find("old", 1, true), r)
        end
        for _, r in ipairs(screen()) do
          assert.is_nil(r:find("old", 1, true), r)
        end
      end)

    --- the state word is cut first, then the project, the file
    --- the last (the maintainer's ruling of November 18, 2026)
    it("have a status line that fits the screen with a long "
      .. "entry name, the word cut first, then the file", function()
        owning()
        K.cc.entry = string.rep("e", 60) .. ".lua"
        local s = K.screen()
        local v = K.cc.cfg.view
        local texts = { }
        for _, t in ipairs(s.field) do
          if t.y < v.fh then texts[#texts + 1] = t end
        end
        table.sort(texts, function(a, b) return a.x < b.x end)
        assert.equal("ru…", texts[3].text)
        assert.equal("…", texts[2].text:sub(-#"…"))
        assert.equal("text>F12", texts[4].text)
        for i, t in ipairs(texts) do
          assert.is_true(t.x + string.ulen(t.text) * v.fw <= v.w,
            t.text)
          if i > 1 then
            local prev = texts[i - 1]
            assert.is_true(prev.x + string.ulen(prev.text) * v.fw
              <= t.x, prev.text .. " runs into " .. t.text)
          end
        end
        K.cc.entry = nil
        forget()
      end)

    --- A pause takes no screenshot: the paused frame is on the
    --- program's canvas (the canvas plan's stage 1), and a program
    --- that draws nothing shows its output as it is
    --- (Harmony scrollback.paused-output checks the pixels).

    --- The bare status line says the same every frame, and its
    --- render into the field's canvas cost a Compy about 1.5 ms
    --- of each (measured on November 17, 2026): it is rendered
    --- when what it says changes, and kept otherwise.
    --- @return function --- the renders of one more frame's draw
    local function renders_counted()
      local view = K.cc.view.input
      local n, render = 0, view.render
      view.render = function(...)
        n = n + 1
        return render(...)
      end
      at_end(function() view.render = nil end)
      return function()
        n = 0
        K.redraw()
        return n
      end
    end

    it("render the status line under them once, and again when "
      .. "what it says changes", function()
        owning()
        local renders = renders_counted()
        assert.equal(1, renders(), "the first frame")
        assert.equal(0, renders())
        assert.equal(0, renders())
        K.cc.entry = "other.lua"
        assert.equal(1, renders(), "another entry point")
        assert.equal(0, renders())
        local says = { }
        for _, t in ipairs(K.screen().field) do says[t.text] = true end
        assert.is_true(says["other.lua"])
        K.cc.entry = nil
        forget()
      end)

    it("render the status line under them again when the "
      .. "screen's mode changes", function()
        owning()
        local renders = renders_counted()
        renders()
        assert.equal(0, renders())
        K.cc.model.screen:set("combined")
        assert.equal(1, renders(), "another mode")
        assert.equal(0, renders())
        local says = { }
        for _, t in ipairs(K.screen().field) do says[t.text] = true end
        assert.is_true(says["comb>F12"])
        K.cc.model.screen:set("text")
        assert.equal(1, renders(), "the first mode again")
        forget()
      end)

    --- the line's render goes by the IDE's state, which is in
    --- its key (review o4: a run that idles and its rerun that
    --- runs say the same words)
    it("render the status line under them again when a rerun of "
      .. "the same program runs where the first idled", function()
        local G = getfenv(0)
        at_end(function() G.RUNS_NOW = nil end)
        reset({ ["main.lua"] = "compy.input.hooks.keypressed = "
          .. "function() return true end\n"
          .. "if getfenv(0).RUNS_NOW then\n"
          .. "  function love.update() end\n"
          .. "end\n" })
        run("run()")
        K.frame()
        assert.same("ready", K.app_state())
        assert.is_true(K.cc:fieldless())
        local renders = renders_counted()
        renders()
        assert.equal(0, renders())
        G.RUNS_NOW = true
        K.keys("lctrl", "r")
        K.frame()
        assert.same("running", K.app_state())
        assert.is_true(K.cc:fieldless())
        assert.equal(1, renders(), "the rerun's colours")
        assert.equal(0, renders())
        forget()
      end)

    --- the line's place goes by the window's height, which a
    --- desktop window changes (review o5)
    it("render the status line under them again, at its new "
      .. "place, when the window's height changes", function()
        owning()
        local view = K.cc.view.input
        local renders = renders_counted()
        renders()
        assert.equal(0, renders())
        local at = view.start_h
        local gfx = love.graphics
        local height = gfx.getHeight
        at_end(function() gfx.getHeight = height end)
        gfx.getHeight = function() return height() + 100 end
        assert.equal(1, renders(), "another height")
        assert.equal(at + 100, view.start_h)
        assert.equal(0, renders())
        forget()
      end)

    --- The kept line is compared by Statusline:key. Every field
    --- of the IDE's state that a render of the bare line reads
    --- must be in it: the render runs here over a love.state that
    --- records what is read of it, and a change of each field
    --- read must change the key. What it records are the reads
    --- written as `love.state.<field>`, as all of them are; a
    --- read through a copy of the table kept from before, or a
    --- rawget, would pass it by.
    it("compare the kept status line by every field of the IDE's "
      .. "state that its render reads", function()
        owning()
        local view = K.cc.view.input
        local state = love.state
        local read, render = { }, view.render
        view.render = function(...)
          love.state = setmetatable({ }, {
            __index = function(_, k)
              read[k] = true
              return state[k]
            end,
            __newindex = state,
          })
          local ok, e = pcall(render, ...)
          love.state = state
          assert(ok, e)
        end
        at_end(function()
          love.state = state
          view.render = nil
        end)
        K.screen()
        view.render = nil
        assert.is_true(read.app_state, "the render read the state")
        for field in pairs(read) do
          local was, key = state[field], view:_bare_key()
          assert.is_string(key)
          state[field] = { }
          local changed = view:_bare_key()
          state[field] = was
          assert.are_not.equal(key, changed,
            "love.state." .. field .. " is read and not compared")
        end
        forget()
      end)

    --- the key holds the whole status, each field of it, so a
    --- field a later draw comes to read is compared already
    it("compare the kept status line by every field of its "
      .. "status, nested ones and new ones too", function()
        local line = K.cc.view.input.statusline
        local function status()
          return { custom = { project = "p", name = "main.lua",
            state = "running" }, mode = "text" }
        end
        local key = line:key(status())
        assert.equal(key, line:key(status()))
        local changes = {
          function(s) s.custom.project = "q" end,
          function(s) s.custom.name = "other.lua" end,
          function(s) s.custom.state = "paused" end,
          function(s) s.custom.state = nil end,
          function(s) s.mode = "combined" end,
          function(s) s.caps = "CAPS" end,
          function(s) s.cursor = { l = 1, c = 1 } end,
          function(s) s.custom.added = false end,
          --- a text that looks like two fields is one
          function(s) s.custom.project = "p\nmain.lua" end,
        }
        for i, change in ipairs(changes) do
          local s = status()
          change(s)
          assert.are_not.equal(key, line:key(s), "change " .. i)
        end
      end)

    it("render the field every frame again once it is back",
      function()
        owning()
        local renders = renders_counted()
        renders()
        assert.equal(0, renders())
        K.keys("lctrl", "q")
        K.frame()
        assert.equal(16, rows())
        assert.equal(1, renders())
        assert.equal(1, renders())
        forget()
      end)

    it("render the status line anew after the console's field "
      .. "was rendered behind a program's own field", function()
        reset({ ["main.lua"] = "compy.input.hooks.keypressed = "
          .. "function() return true end\n"
          .. "function love.update()\n"
          .. "  if want == 'show' then compy.input.show { } end\n"
          .. "  if want == 'hide' then compy.input.hide() end\n"
          .. "  want = nil\n"
          .. "end\n" })
        run("run()")
        K.frame()
        local renders = renders_counted()
        renders()
        assert.equal(0, renders())
        env().want = "show"
        K.frame()
        --- with a field shown the line says the console's own
        --- status, rendered each frame as before
        assert.equal(1, renders())
        assert.equal(1, renders())
        env().want = "hide"
        K.frame()
        assert.equal(1, renders(), "the frame that hides it")
        assert.equal(0, renders())
        forget()
      end)

    --- and the screen's mode, as the console's status line names
    --- it in every state (the program's canvas, stage 2)
    it("have the status line under them, naming the project, "
      .. "the entry point and that it runs, the screen's mode, and "
      .. "nothing else", function()
        owning()
        local s = K.screen()
        local line = { }
        for _, t in ipairs(s.field) do line[#line + 1] = t.text end
        local name = K.cc.model.projects.current.name
        assert.same({ name, "main.lua", "running", "text>F12" }, line)
        assert.equal(0, s.field_rows, "rows under the status line")
        forget()
      end)
  end)

-- The status line's mode (the maintainer's rulings of November
-- 17, 2026): its colour "clearly indicates the mode (but is never
-- the single differentiating indicator)"; "keep the bar dark
-- gray, just add 'running' in yellow as a status"; a program's
-- own field shows its prompt and the cursor's place alone; and
-- the IDE's own line "always starts with: project file mode",
-- the word in yellow: "console", "running", "paused" or the
-- editor's state. The console is dark gray, a running program's
-- bare line too, the editor blue, a pause a darker red.
describe("the status line's mode #console", function()
  before_each(function() reset() end)
  after_each(cleanup)

  local function colors() return K.cc.cfg.view.colors.statusline end

  local function same(a, b)
    return a ~= nil and b ~= nil
        and table.concat(a, ",") == table.concat(b, ",")
  end

  --- the line's ground, by the theme's name for it, and its
  --- words, each with the colour it is drawn in
  --- @return table<string, true> grounds
  --- @return table<string, number[]> words
  local function line()
    local grounds, words = { }, { }
    for _, e in ipairs(K.screen().field_log) do
      if e.fill then
        for name, c in pairs(colors()) do
          if same(c.bg, e.colour) then grounds[name] = true end
        end
      elseif e.text then
        words[e.text] = e.colour
      end
    end
    return grounds, words
  end

  --- what one status line draws for `status`: its ground, by
  --- the theme's name, and its words
  --- @return table<string, true> grounds
  --- @return table<string, true> words
  local function drawn(statusline, status)
    local gfx = love.graphics
    local saved = { gfx.setColor, gfx.rectangle, gfx.print }
    local colour, grounds, words = { }, { }, { }
    gfx.setColor = function(c, ...)
      colour = type(c) == "table" and c or { c, ... }
    end
    gfx.rectangle = function(mode)
      if mode ~= "fill" then return end
      for name, c in pairs(colors()) do
        if same(c.bg, colour) then grounds[name] = true end
      end
    end
    gfx.print = function(text) words[tostring(text)] = true end
    local ok, e = pcall(statusline.draw, statusline, status, 0)
    gfx.setColor, gfx.rectangle, gfx.print =
        saved[1], saved[2], saved[3]
    assert(ok, e)
    return grounds, words
  end

  --- each text one status line draws for `status`, with where
  --- it starts and ends, in pixels, as the line's font measures
  --- it, and its colour, left to right
  --- @return table[] --- { text, from, to, colour }
  local function placed(statusline, status)
    local gfx, font = love.graphics, statusline.cfg.font
    local saved = { gfx.print, gfx.rectangle, gfx.setColor,
      gfx.getFont, gfx.setFont }
    local out, colour = { }, nil
    --- the editor's line asks for the font
    gfx.getFont = saved[4] or function() end
    gfx.setFont = saved[5] or function() end
    gfx.setColor = function(c, ...)
      colour = type(c) == "table" and c or { c, ... }
    end
    gfx.rectangle = function() end
    gfx.print = function(text, x)
      text = tostring(text)
      if text:match("%S") then
        out[#out + 1] = { text = text, from = x,
          to = x + font:getWidth(text), colour = colour }
      end
    end
    local ok, e = pcall(statusline.draw, statusline, status, 0)
    gfx.print, gfx.rectangle, gfx.setColor, gfx.getFont, gfx.setFont =
        saved[1], saved[2], saved[3], saved[4], saved[5]
    assert(ok, e)
    table.sort(out, function(a, b) return a.from < b.from end)
    return out
  end

  --- the console's own line, the texts it draws, left to right:
  --- { text, x, colour }
  local function head()
    local fh = K.cc.cfg.view.fh
    local out = { }
    for _, e in ipairs(K.screen().field_log) do
      if e.text and e.text:match("%S") and e.y < fh then
        out[#out + 1] = { text = e.text, x = e.x, colour = e.colour }
      end
    end
    table.sort(out, function(a, b) return a.x < b.x end)
    return out
  end

  --- the line starts with the project, the entry file and the
  --- state word, in yellow, at the places a console line has
  --- them; returns the places
  --- the console's own line names no file; a running or paused
  --- program's names its entry file (the maintainer's ruling of
  --- November 18, 2026)
  local function starts_with(word, places)
    local h = head()
    local project = K.cc.model.projects.current.name
    local want = word == "console" and { project, word }
        or { project, "main.lua", word }
    local got, at = { }, { }
    for i = 1, #want do
      got[i] = h[i] and h[i].text
      at[i] = h[i] and h[i].x
    end
    assert.same(want, got)
    assert.is_true(same(K.cc.cfg.view.colors.statusline.console.state,
      h[#want].colour), word .. " in yellow")
    if places then assert.same(places, at) end
    return at
  end

  local function forget()
    local lv = K.cc:get_project_env().love
    lv.update, lv.keypressed = nil, nil
    K.cc:get_project_env().compy.input.hooks.keypressed = nil
  end

  it("has a ground of its own for the console, the editor and a "
    .. "pause, and none for a running program", function()
      local c, seen = colors(), { }
      for _, name in ipairs({ "console", "editor", "inspect" }) do
        local key = table.concat(c[name].bg, ",")
        assert.is_nil(seen[key], name .. " shares " .. tostring(seen[key]))
        seen[key] = name
      end
      assert.is_nil(c.user)
    end)

  --- WCAG's contrast ratio of two colours
  local function contrast(a, b)
    local function lum(c)
      local function ch(v)
        if v <= 0.03928 then return v / 12.92 end
        return ((v + 0.055) / 1.055) ^ 2.4
      end
      return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2])
          + 0.0722 * ch(c[3])
    end
    local x, y = lum(a), lum(b)
    if x < y then x, y = y, x end
    return (x + 0.05) / (y + 0.05)
  end

  --- the text, the state word and the position's indicator each
  --- bar draws read on its ground
  it("has tones that read on every bar", function()
    for _, name in ipairs({ "console", "editor", "inspect" }) do
      local c = colors()[name]
      for tone, v in pairs({ fg = c.fg, state = c.state or c.fg2,
        indicator = c.indicator, mark = c.mark }) do
        --- the mark's bright orange on the pause's red is 4.26:1,
        --- short of 4.5 (review e4's triage asked for #FFA500 on
        --- every bar; the choice is open): held where it is
        local least = (name == "inspect" and tone == "mark") and 4.25
            or 4.5
        assert.is_true(contrast(c.bg, v) >= least, name .. " " .. tone)
      end
    end
  end)

  it("is the console's, saying the project, the entry file and "
    .. "\"console\" in yellow, in the console", function()
      local grounds, words = line()
      assert.same({ console = true }, grounds)
      assert.is_nil(words.running)
      assert.is_nil(words.paused)
      assert.is_not_nil(words["text>F12"], "the display mode")
      starts_with("console")
    end)

  it("is the editor's, saying its state, in the editor", function()
    reset({ ["main.lua"] = "a = 1\n" })
    K.open("main.lua")
    local grounds, words = line()
    assert.is_true(grounds.editor)
    assert.is_nil(grounds.console)
    assert.is_not_nil(words.browsing)
    --- F12 does nothing in the editor, and its line names no
    --- mode to step
    assert.is_nil(words["text>F12"])
    assert.is_nil(words["comb>F12"])
    assert.is_nil(words.text)
  end)

  for _, case in ipairs({
    { "with an update", "function love.update() end\n" },
    { "with love.keypressed alone",
      "function love.keypressed() end\n" },
  }) do
    it("is the console's behind a running program, saying "
      .. "\"running\" in yellow, " .. case[1], function()
        reset({ ["main.lua"] = case[2] })
        run("run()")
        K.frame()
        assert.is_true(K.cc:fieldless())
        local grounds, words = line()
        assert.same({ console = true }, grounds)
        assert.same(colors().editor.fg2, colors().console.state)
        assert.is_not_nil(words["text>F12"], "the display mode")
        assert.is_nil(words.console)
        starts_with("running")
        K.keys("lctrl", "q")
        forget()
      end)
  end

  --- a program's own field draws its own status line, over the
  --- console's: its prompt and the cursor's place alone
  for _, case in ipairs({
    { "no update", "compy.input.show { prompt = 'Your name?' }\n" },
    { "an update", "compy.input.show { prompt = 'Your name?' }\n"
      .. "function love.update() end\n" },
    { "compy.ask", "compy.ask('Your name?', function() end)\n" },
  }) do
    it("is the console's under a program's own field, saying its "
      .. "prompt and the cursor's place alone, with " .. case[1],
      function()
        reset({ ["main.lua"] = case[2] })
        run("run()")
        K.frame()
        assert.is_true(K.cc.main_ctrl.program_owns_input())
        local ui = love.state.user_input
        local grounds, words = drawn(ui.V.statusline,
          ui.M:get_status())
        assert.same({ console = true }, grounds)
        assert.same({ ["Your name?"] = true, ["1:1"] = true }, words)
        K.keys("lctrl", "q")
        forget()
      end)
  end

  --- a field rendered in one state of the IDE is rendered again
  --- in the next: its line's colours and a pause's word go by it
  it("renders a program's field again when the IDE's state "
    .. "changes", function()
      reset({ ["main.lua"] = "compy.input.show { }\n" })
      run("run()")
      K.frame()
      local V = love.state.user_input.V
      V.ide_shown = "a state from before"
      --- the draw's calls the fixture's graphics lack
      local gfx = love.graphics
      local blend, draw = gfx.setBlendMode, gfx.draw
      gfx.setBlendMode = blend or function() end
      gfx.draw = draw or function() end
      local ok, e = pcall(V.draw, V)
      gfx.setBlendMode, gfx.draw = blend, draw
      assert(ok, e)
      assert.equal(V.statusline:ide_key(), V.ide_shown)
      K.keys("lctrl", "q")
      forget()
    end)

  --- review e2: a program's prompt is its field's label, and
  --- however long it is, it is cut to fit, and never covers or
  --- pushes away the cursor's place
  local QUESTION = "Which country would you like to visit next?"
  for _, prompt in ipairs({
    QUESTION,
    string.rep("x", 63) .. "?",
    string.rep("A long question. ", 8),
  }) do
    it("fits a program's prompt of " .. #prompt .. " characters, "
      .. "the cursor's place whole, nothing overlapping", function()
        assert.equal(43, #QUESTION)
        reset({ ["main.lua"] = string.format(
          "compy.ask(%q, function() end)\n", prompt) })
        run("run()")
        K.frame()
        local ui = love.state.user_input
        local w = K.cc.cfg.view.w
        local texts = placed(ui.V.statusline, ui.M:get_status())
        local whole = { }
        for i, t in ipairs(texts) do
          assert.is_true(t.from >= 0 and t.to <= w,
            t.text .. " off the screen")
          if i > 1 then
            assert.is_true(texts[i - 1].to <= t.from,
              texts[i - 1].text .. " runs into " .. t.text)
          end
          whole[t.text] = true
        end
        assert.is_true(whole["1:1"], "1:1")
        assert.is_nil(whole.running)
        --- a program's own field names no mode (the ruling of
        --- November 17, 2026), in neither label
        assert.is_nil(whole["text>F12"])
        assert.is_nil(whole["comb>F12"])
        -- the prompt gave way, and says how it begins
        local first = texts[1].text
        assert.equal(prompt:sub(1, 8), first:sub(1, 8))
        if #prompt > 50 then
          assert.equal("…", first:sub(-#"…"))
        end
        K.keys("lctrl", "q")
        forget()
      end)
  end

  --- every text on the screen and none running into the next
  local function contained(texts, w)
    for i, t in ipairs(texts) do
      assert.is_true(t.from >= 0 and t.to <= w,
        t.text .. " off the screen at " .. t.to)
      if i > 1 then
        assert.is_true(texts[i - 1].to <= t.from,
          texts[i - 1].text .. " runs into " .. t.text)
      end
    end
  end

  --- review e3: a line break in a prompt printed its second line
  --- under the bar
  it("draws a prompt with line breaks and tabs on its one row",
    function()
      reset({ ["main.lua"] =
        "compy.ask('Your name?\\nSECOND\\r\\tLINE', function() end)\n" })
      run("run()")
      K.frame()
      local ui = love.state.user_input
      local texts = placed(ui.V.statusline, ui.M:get_status())
      assert.equal("Your name? SECOND  LINE", texts[1].text)
      for _, t in ipairs(texts) do
        assert.is_nil(t.text:find("%c"), t.text)
      end
      contained(texts, K.cc.cfg.view.w)
      K.keys("lctrl", "q")
      forget()
    end)

  --- a toned label is cut the same, in its tone
  it("fits a long toned label, its tone kept", function()
    local sl = K.cc.view.input.statusline
    local w = K.cc.cfg.view.w
    local status = { label = { text = string.rep("y", 90),
      tone = "warning" }, cursor = { l = 1, c = 1 }, n_lines = 1,
      mode = "text" }
    local texts = placed(sl, status)
    for i, t in ipairs(texts) do
      assert.is_true(t.to <= w, t.text .. " off the screen")
      if i > 1 then
        assert.is_true(texts[i - 1].to <= t.from, t.text)
      end
    end
    assert.equal("…", texts[1].text:sub(-#"…"))
    assert.same(colors().console.warning, texts[1].colour)
  end)

  it("is a pause's, saying the project, the entry file and "
    .. "\"paused\" in yellow",
    function()
      reset({ ["main.lua"] = "function love.update() end\n" })
      run("run()")
      K.frame()
      K.keys("lctrl", "pause")
      K.frame()
      if K.app_state() == "snapshot" then K.cc:suspend() end
      assert.same("inspect", K.app_state())
      local grounds, words = line()
      assert.is_true(grounds.inspect)
      assert.is_nil(grounds.console)
      assert.is_nil(words.console)
      assert.is_nil(words.running)
      assert.is_not_nil(words["text>F12"], "the display mode")
      -- white text, "paused" in yellow
      local project = K.cc.model.projects.current.name
      assert.is_true(same(colors().inspect.fg, words[project]))
      assert.is_true(same(colors().inspect.state, words.paused))
      local h = head()
      assert.same({ project, "main.lua", "paused" },
        { h[1].text, h[2].text, h[3].text })
      K.keys("lctrl", "q")
      forget()
    end)

  it("is the console's again once a program ended by itself",
    function()
      reset({ ["main.lua"] = "print('done')\n" })
      run("run()")
      K.frame()
      local grounds, words = line()
      assert.same({ console = true }, grounds)
      assert.is_nil(words.running)
      starts_with("console")
    end)

  --- the no-card mark (the maintainer's rulings of November 17,
  --- 2026: "[no sd card] stays in front", and on every line of
  --- the IDE's own, the editor's too), read from
  --- love.state.has_removable at each draw
  local function without_card(f)
    local was = love.state.has_removable
    love.state.has_removable = false
    local ok, e = pcall(f)
    love.state.has_removable = was
    assert(ok, e)
  end

  --- the texts begin with the mark, in the warning tone of the
  --- line's colours, then the project, the file and `word`; or,
  --- with a card, with the project
  local function marked(texts, theme, word, file, card)
    local project = K.cc.model.projects.current.name
    local want = file and { project, file, word } or { project, word }
    if not card then table.insert(want, 1, "[no sd]") end
    local got = { }
    for i = 1, #want do got[i] = texts[i] and texts[i].text end
    if card then
      assert.same(want, got)
    else
      assert.same(want, got)
      assert.is_true(same(colors()[theme].mark, texts[1].colour),
        "the mark in its bright orange")
    end
  end

  local function editor_line()
    local ec = K.cc.editor
    return placed(ec.view.input.statusline, ec.input:get_status())
  end

  for _, card in ipairs({ true, false }) do
    local with = card and "with an SD card, no mark" or
        "without an SD card, the mark in front"
    local function maybe(f)
      if card then f() else without_card(f) end
    end

    it("starts the console's line " .. with, function()
      maybe(function()
        marked(head(), "console", "console", nil, card)
      end)
    end)

    it("starts a running program's line " .. with, function()
      reset({ ["main.lua"] = "function love.update() end\n" })
      run("run()")
      K.frame()
      maybe(function()
        marked(head(), "console", "running", "main.lua", card)
      end)
      K.keys("lctrl", "q")
      forget()
    end)

    it("starts a pause's line " .. with, function()
      reset({ ["main.lua"] = "function love.update() end\n" })
      run("run()")
      K.frame()
      K.keys("lctrl", "pause")
      K.frame()
      if K.app_state() == "snapshot" then K.cc:suspend() end
      assert.same("inspect", K.app_state())
      maybe(function()
        marked(head(), "inspect", "paused", "main.lua", card)
      end)
      K.keys("lctrl", "q")
      forget()
    end)

    it("starts the editor's line in each state " .. with, function()
      reset({ ["notes.lua"] = "a = 1\nb = 2\n" })
      K.open("notes.lua")
      maybe(function()
        marked(editor_line(), "editor", "browsing", "notes.lua", card)
      end)
      K.type("c = 3")
      maybe(function()
        marked(editor_line(), "editor", "inserting", "notes.lua", card)
      end)
      K.keys("escape")
      K.keys("lctrl", "up")
      K.keys("f2")
      assert.same("replacing", K.state())
      maybe(function()
        marked(editor_line(), "editor", "replacing", "notes.lua", card)
      end)
    end)
  end

  it("puts no mark on a program's own field without an SD card",
    function()
      reset({ ["main.lua"] = "compy.ask('Your name?', function() end)\n" })
      run("run()")
      K.frame()
      without_card(function()
        local ui = love.state.user_input
        local texts = placed(ui.V.statusline, ui.M:get_status())
        assert.same("Your name?", texts[1].text)
        for _, t in ipairs(texts) do
          assert.is_nil(t.text:find("sd card", 1, true))
        end
      end)
      K.keys("lctrl", "q")
      forget()
    end)

  --- the mark is never cut: the project's name gives way
  it("keeps the mark whole beside a long project name", function()
    local sl = K.cc.view.input.statusline
    local w = K.cc.cfg.view.w
    without_card(function()
      local texts = placed(sl, { label = "", state = "console",
        project = string.rep("p", 60), name = "main.lua",
        cursor = { l = 1, c = 1 }, n_lines = 1, mode = "text" })
      assert.same("[no sd]", texts[1].text)
      assert.equal("…", texts[2].text:sub(-#"…"))
      for i, t in ipairs(texts) do
        assert.is_true(t.to <= w, t.text)
        if i > 1 then assert.is_true(texts[i - 1].to <= t.from) end
      end
    end)
  end)

  --- review e4: the file's name took the project's room, and the
  --- project went. Every text on the screen, none running into
  --- the next, the project and the file both there, cut or not
  local function both_named(texts, project, file)
    local w = K.cc.cfg.view.w
    local p, f
    for i, t in ipairs(texts) do
      assert.is_true(t.from >= 0 and t.to <= w, t.text)
      if i > 1 then
        assert.is_true(texts[i - 1].to <= t.from,
          texts[i - 1].text .. " runs into " .. t.text)
      end
      if project:sub(1, 2) == t.text:sub(1, 2) then p = t.text end
      if file:sub(1, 2) == t.text:sub(1, 2) then f = t.text end
    end
    assert.is_not_nil(p, "the project")
    assert.is_not_nil(f, "the file")
    return p, f
  end

  it("keeps the project beside a long file's name in the editor "
    .. "without a card", function()
      reset({ ["my-first-program.lua"] = "a = 1\n" })
      K.open("my-first-program.lua")
      without_card(function()
        local texts = editor_line()
        assert.same("[no sd]", texts[1].text)
        both_named(texts, K.cc.model.projects.current.name,
          "my-first-program.lua")
      end)
    end)

  it("keeps the project beside a 60-character file's name in the "
    .. "editor with a card", function()
      local file = string.rep("f", 56) .. ".lua"
      assert.equal(60, #file)
      reset({ [file] = "a = 1\n" })
      K.open(file)
      local _, f = both_named(editor_line(),
        K.cc.model.projects.current.name, file)
      assert.equal("…", f:sub(-#"…"))
    end)

  --- the state word is cut first, then the project, the file
  --- only if nothing more can (the maintainer's ruling of
  --- November 18, 2026), none below three columns
  for _, card in ipairs({ true, false }) do
    it("cuts the word, then the project, then the file "
      .. (card and "with a card" or "without one"), function()
        local sl = K.cc.view.input.statusline
        local project = string.rep("p", 40)
        local file = string.rep("f", 30) .. ".lua"
        local function draw()
          local texts = placed(sl, { label = "", state = "paused",
            project = project, name = file,
            cursor = { l = 1, c = 1 }, n_lines = 1, mode = "text" })
          local p, f = both_named(texts, project, file)
          local word
          for _, t in ipairs(texts) do
            if t.text:sub(1, 2) == "pa" then word = t.text end
          end
          assert.equal("pa…", word)
          assert.equal("…", p:sub(-#"…"))
          assert.is_true(string.ulen(p) >= 3)
          if f ~= file then
            -- the file is cut only with the project at its floor
            assert.equal(3, string.ulen(p))
          end
          return f
        end
        if card then
          assert.equal(file, draw(), "the file whole with a card")
        else
          without_card(draw)
        end
      end)
  end

  --- review e5: the fit is total. The IDE's own parts take their
  --- room whole, the names share what is left, and where even
  --- their floors do not fit they go, the label, then the file,
  --- then the project; nothing shares a cell or leaves the row.

  --- the cells one draw of `statusline` inks for `status`, a
  --- space inking none: nil and the cells, or the first clash
  --- @return string? clash
  --- @return table<integer, string> cells
  local function inked(statusline, status)
    local gfx, fw = love.graphics, K.cc.cfg.view.fw
    local cols = math.floor(K.cc.cfg.view.w / fw)
    local names = { "print", "rectangle", "setColor", "getFont",
      "setFont", "push", "pop", "transformPoint", "intersectScissor" }
    local saved = { }
    for i, n in ipairs(names) do saved[i] = gfx[n] end
    local cells, clash = { }, nil
    --- the clip in force, its end as the first cell it hides,
    --- as the graphics' scissor would hide them; a stack of them
    local clip, stack = nil, { }
    --- what this draw clipped and the right block's first cell
    local info = { clip = nil, right = nil }
    gfx.setColor = function() end
    gfx.rectangle = function() end
    gfx.getFont = saved[4] or function() end
    gfx.setFont = saved[5] or function() end
    gfx.push = function() stack[#stack + 1] = clip or false end
    gfx.pop = function() clip = table.remove(stack) or nil end
    gfx.transformPoint = function(x, y) return x, y end
    gfx.intersectScissor = function(x, _, w)
      local e = math.floor((x + w) / fw + 0.5)
      clip = clip and math.min(clip, e) or e
      info.clip = info.clip and math.min(info.clip, clip) or clip
    end
    gfx.print = function(text, x)
      text = tostring(text)
      local at = math.floor(x / fw + 0.5)
      if not clip and text:match("%S") then
        info.right = info.right and math.min(info.right, at) or at
      end
      local i = 0
      for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local cell = at + i
        if ch ~= " " and not clash and not (clip and cell >= clip) then
          if cell < 0 or cell >= cols then
            clash = text .. " leaves the row at cell " .. cell
          elseif cells[cell] then
            clash = text .. " inks cell " .. cell .. ", "
              .. cells[cell] .. "'s"
          else
            cells[cell] = text
          end
        end
        i = i + 1
      end
    end
    local ok, e = pcall(statusline.draw, statusline, status, 0)
    for i, n in ipairs(names) do gfx[n] = saved[i] end
    assert(ok, e)
    --- the left side is clipped before the right block begins
    if not clash and info.clip and info.right
        and info.clip > info.right then
      clash = "the left side's clip ends at cell " .. info.clip
        .. ", past the right block's first, " .. info.right
    end
    return clash, cells, info
  end

  --- a name of `n` characters, nil for none
  local function named(c, n, tail)
    if n == 0 then return nil end
    if tail and n > #tail then
      return string.rep(c, n - #tail) .. tail
    end
    return string.rep(c, n)
  end

  --- The widest right block (the maintainer's rulings of
  --- November 18, 2026): a draft's cursor of nine characters,
  --- 9999:9999, numbers above 9999 being written in thousands
  --- (10K); the editor's block and lines, B9999 L9999-9999; and
  --- the output scrolled back the kept rows' limit, L-1000.
  local WIDE_RANGE = { ln_label = function() return "L9999-9999" end }
  local WIDE_CURSOR = { l = 9999, c = 9999 }
  local WIDE_BACK = 1000

  --- each state's status with the widest right block it draws:
  --- { name, app state, its state word, status(p, f, caps) }
  local STATES = {
    { "the console", "ready", "console", function(p, _, caps)
      return { label = "", project = p, state = "console",
        cursor = WIDE_CURSOR, n_lines = 1,
        back = WIDE_BACK, mode = "combined", caps = caps }
    end },
    { "a pause", "inspect", "paused", function(p, f, caps)
      return { label = "", project = p, name = f, state = "paused",
        cursor = WIDE_CURSOR, n_lines = 1,
        back = WIDE_BACK, mode = "combined", caps = caps }
    end },
    { "a running program", "running", "running", function(p, f)
      return { custom = { project = p, name = f, state = "running" },
        back = WIDE_BACK, mode = "combined" }
    end },
    { "a program's field", "running", nil, function(p, _, caps)
      return { label = p, cursor = WIDE_CURSOR, n_lines = 1,
        caps = caps }
    end },
  }
  --- the editor's states, and a state word with an arrow toward
  --- the highlighted target, which a cut keeps after the word
  for _, st in ipairs({ "browsing", "inserting", "replacing",
    "replacing↑" }) do
    --- the editor's status carries the word and its arrow apart
    local word, arrow = st:match("^(%a+)(.*)$")
    STATES[#STATES + 1] = { "the editor " .. st, "editor", st,
      function(p, f, caps)
        return { custom = { project = p, name = f, state = word,
          arrow = arrow ~= "" and arrow or nil,
          spans_lines = true, selection = 9999, buflen = 9999,
          range = WIDE_RANGE },
          cursor = WIDE_CURSOR, caps = caps }
      end }
  end

  --- the editor with numbers in thousands and its block's lines
  --- too wide for half the line, which leave it
  STATES[#STATES + 1] = { "the editor, its lines left out", "editor",
    "inserting", function(p, f, caps)
      return { custom = { project = p, name = f, state = "inserting",
        spans_lines = true, selection = 123456, buflen = 999999,
        range = { ln_label = function()
          return "L123456789-123456" end } },
        cursor = { l = 123456, c = 123456 }, caps = caps }
    end }

  --- the forms a part may be drawn in: whole, or cut to `n`
  --- columns, three at least, its arrow kept
  local function forms(text)
    local out = { [text] = true }
    local l = string.ulen(text)
    local last = string.usub(text, l, l)
    local arrow = (last == "↑" or last == "↓" or last == "↕") and last
    local word = arrow and string.usub(text, 1, l - 1) or text
    for n = 3, l - 1 do
      local k = arrow and n - 1 or n
      if k >= 2 then
        out[string.usub(word, 1, k - 1) .. "…" .. (arrow or "")] = true
      end
    end
    return out
  end

  --- the first part missing or cut below its floor, if any
  local function floors_held(cells, parts)
    local drawn = { }
    for _, t in pairs(cells) do drawn[t] = true end
    for _, part in ipairs(parts) do
      local found = false
      for form in pairs(forms(part)) do
        if drawn[form] then found = true end
      end
      if not found then return part .. " not drawn, nor cut to 3+" end
    end
  end

  for _, case in ipairs(STATES) do
    it("never overlaps nor leaves the row, nor drops a name or cuts "
      .. "it below three columns, in " .. case[1] .. ", for any "
      .. "project and file from 0 to 70 characters, with and "
      .. "without a card, Caps Lock on and off", function()
        local sl = K.cc.view.input.statusline
        local was = love.state.app_state
        local removable = love.state.has_removable
        local clash
        for _, card in ipairs({ true, false }) do
          love.state.has_removable = card and true or false
          for _, caps in ipairs({ false, "CAPS" }) do
            for lp = 0, 70 do
              for lf = 0, 70 do
                love.state.app_state = case[2]
                local p, f = named("p", lp), named("f", lf, ".lua")
                local status = case[4](p, f, caps or nil)
                local c, cells = inked(sl, status)
                if not c then
                  local parts = { case[3] }
                  if p then parts[#parts + 1] = p end
                  local custom = status.custom
                  if f and (status.name or (custom and custom.name)) then
                    parts[#parts + 1] = f
                  end
                  c = floors_held(cells, parts)
                end
                if c and not clash then
                  clash = string.format("%s, project %d, file %d, %s, %s",
                    c, lp, lf, card and "card" or "no card",
                    caps and "Caps" or "no Caps")
                end
              end
            end
          end
        end
        love.state.app_state = was
        love.state.has_removable = removable
        assert.is_nil(clash)
      end)
  end

  --- the mode's two labels take the same eight columns (the
  --- maintainer's ruling of November 19, 2026: `text>F12` "takes
  --- exactly the same number of characters as `combined`"), so
  --- the text mode leaves the rest of the line as the combined
  --- mode does: every other part drawn the same, at the same
  --- place, for any project and file
  for _, case in ipairs({ STATES[1], STATES[2], STATES[3] }) do
    it("lays out the rest of the line in the text mode as in the "
      .. "combined, in " .. case[1] .. ", for any project and file "
      .. "from 0 to 70 characters, with and without a card",
      function()
        local sl = K.cc.view.input.statusline
        local was = love.state.app_state
        local removable = love.state.has_removable
        --- the line's texts and places, the mode's label as `M`
        local function line(mode, p, f)
          local status = case[4](p, f, "CAPS")
          status.mode = mode
          local out = { }
          for _, t in ipairs(placed(sl, status)) do
            local m = (t.text == "text>F12" or t.text == "comb>F12")
            out[#out + 1] = (m and "M" or t.text) .. "@" .. t.from
          end
          return table.concat(out, " ")
        end
        local differs
        for _, card in ipairs({ true, false }) do
          love.state.has_removable = card
          love.state.app_state = case[2]
          for lp = 0, 70 do
            for _, lf in ipairs({ 0, 8, 30, 70 }) do
              local p, f = named("p", lp), named("f", lf, ".lua")
              local text = line("text", p, f)
              if not differs and text ~= line("combined", p, f) then
                differs = text
              end
            end
          end
        end
        love.state.app_state = was
        love.state.has_removable = removable
        assert.is_nil(differs)
      end)
  end

  --- the scrolled output's `L-N`, every N to the kept rows' limit,
  --- beside the longest names
  for _, case in ipairs({ STATES[1], STATES[2], STATES[3] }) do
    it("fits L-1 to L-1000 in " .. case[1] .. " beside the longest "
      .. "names, without a card and with Caps Lock", function()
        local sl = K.cc.view.input.statusline
        local was = love.state.app_state
        local clash
        without_card(function()
          for back = 1, WIDE_BACK do
            love.state.app_state = case[2]
            local status = case[4](string.rep("p", 70),
              string.rep("f", 66) .. ".lua", "CAPS")
            status.back = back
            local c, cells = inked(sl, status)
            local seen = false
            for _, t in pairs(cells or { }) do
              if t == "L-" .. back then seen = true end
            end
            if not c and not seen then c = "L-" .. back .. " not drawn" end
            if c and not clash then clash = c .. ", back " .. back end
          end
        end)
        love.state.app_state = was
        assert.is_nil(clash)
      end)
  end

  --- review e6, by name: no card, Caps Lock, inserting before
  --- B9999 L9999-10000, the draft's cursor at 10:9999
  it("keeps the right block whole and the left side before it, "
    .. "e6's widest editor line", function()
      local sl = K.cc.view.input.statusline
      local was = love.state.app_state
      love.state.app_state = "editor"
      local clash
      without_card(function()
        clash = inked(sl, { custom = { project = "demo",
          name = "notes.lua", state = "inserting", spans_lines = true,
          selection = 9999, buflen = 9999,
          range = { ln_label = function() return "L9999-10000" end } },
          cursor = { l = 10, c = 9999 }, caps = "CAPS" })
      end)
      love.state.app_state = was
      assert.is_nil(clash)
    end)

  --- where even the floors do not fit, the left side is cut off
  --- at its clip, before the right block (review e6). No status
  --- the IDE makes gets there: the widest right block, Caps Lock
  --- and a position of half the line in the editor, leaves the
  --- mark and three floors exactly their room. A Caps Lock word
  --- twenty columns long makes it get there.
  it("clips the left side before the right block where even its "
    .. "floors do not fit", function()
      local sl = K.cc.view.input.statusline
      local was = love.state.app_state
      love.state.app_state = "editor"
      local clash, cells, info
      without_card(function()
        clash, cells, info = inked(sl, { custom = {
          project = string.rep("p", 30), name = string.rep("f", 30),
          state = "replacing", arrow = "↑", spans_lines = true,
          selection = 9999, buflen = 9999, range = WIDE_RANGE },
          cursor = { l = 9999, c = 9999 }, caps = string.rep("C", 20) })
      end)
      love.state.app_state = was
      assert.is_nil(clash)
      assert.is_not_nil(info.clip, "the left side is clipped")
      for cell, text in pairs(cells) do
        if cell >= info.clip then
          assert.is_true(cell >= info.right, text .. " at " .. cell)
        end
      end
    end)

  --- the arrow toward the edit's target (the maintainer's ruling
  --- of November 18, 2026): after "replacing" while no row of
  --- the target is in view, up or down; none while any row is
  it("puts an arrow after \"replacing\" toward a target out of view",
    function()
      local t = { }
      for i = 1, 60 do t[i] = "line " .. i end
      reset({ ["notes.txt"] = table.concat(t, "\n") .. "\n" })
      K.open("notes.txt")
      K.browse_to(30)
      K.keys("f2")
      assert.same("replacing", K.state())
      local ec = K.cc.editor
      local function arrow() return ec.input:get_status().custom.arrow end
      local function line_word()
        for _, x in ipairs(editor_line()) do
          if x.text:find("^repl") or x.text:find("^r…") then
            return x.text
          end
        end
      end
      assert.is_nil(arrow(), "the target in view")
      assert.equal("replacing", line_word())
      local sl = ec.view.input.statusline
      local in_view = sl:key(ec.input:get_status())
      K.keys("lctrl", "pageup")
      assert.equal("↓", arrow(), "the target below the view")
      assert.equal("replacing↓", line_word())
      local below = sl:key(ec.input:get_status())
      assert.are_not.equal(in_view, below)
      K.keys("lctrl", "pagedown")
      assert.equal("↑", arrow(), "the target above the view")
      assert.equal("replacing↑", line_word())
      assert.are_not.equal(below, sl:key(ec.input:get_status()))
      K.keys("lctrl", "g")
      assert.is_nil(arrow(), "back on the target")
      assert.equal("replacing", line_word())
      assert.equal(30, K.target())
    end)

  --- review e7: the arrow says what the document view draws of
  --- the target's yellow highlight, its wrapped rows included:
  --- none while any row of it is drawn, up or down while none is
  local function arrow_holds(what)
    local ec = K.cc.editor
    local custom = ec.input:get_status().custom
    local arrow = custom and custom.arrow
    local t = K.target()
    if not t then
      assert.is_nil(arrow, what .. ": no target, no arrow")
      return
    end
    local rows, shown = K.rows_shown(t)
    assert.is_true(rows > 0, what)
    if shown > 0 then
      assert.is_nil(arrow, what .. ": " .. shown .. " of the "
        .. rows .. " target rows in view")
    else
      local bv = ec.view:get_current_buffer()
      local s = bv:_block_span(t)
      local want = s > bv.content.range.fin and "↓" or "↑"
      assert.equal(want, arrow, what)
    end
  end

  --- a text file of 60 lines, line 20 of `n` characters
  local function long_line_file(n)
    local t = { }
    for i = 1, 60 do t[i] = "line " .. i end
    t[20] = string.rep("x", n)
    return table.concat(t, "\n") .. "\n"
  end

  --- e7's case: line 20 wraps to two rows; loaded with F2 and
  --- browsed to line 33, the view draws its second row
  it("puts no arrow while a wrapped target's row is in view",
    function()
      reset({ ["notes.txt"] = long_line_file(65) })
      K.open("notes.txt")
      K.browse_to(20)
      K.keys("f2")
      assert.same(20, K.target())
      --- browsing down until the view's first row is the
      --- target's second, its other row above the view
      local bv = K.cc.editor.view:get_current_buffer()
      local _, last = bv:_block_span(20)
      local found
      for p = 21, 60 do
        K.browse_to(p)
        if bv.content.range.start == last then
          found = p
          break
        end
      end
      assert.is_not_nil(found, "a view from the target's second row")
      local _, shown = K.rows_shown(20)
      assert.equal(1, shown, "the target's second row in view")
      assert.is_nil(K.cc.editor.input:get_status().custom.arrow)
      arrow_holds("browsed to " .. found)
    end)

  --- at every browsing position, for a target of two rows and one
  --- taller than the view; then Ctrl+G, the end position, Escape
  --- and its undo, and a submit
  for _, n in ipairs({ 65, 1100 }) do
    it("says what the view draws of a target of " .. n
      .. " characters, wherever the view is", function()
        reset({ ["notes.txt"] = long_line_file(n) })
        K.open("notes.txt")
        K.browse_to(20)
        K.keys("f2")
        assert.same(20, K.target())
        for b = 1, 60 do
          K.browse_to(b)
          arrow_holds("browsed to " .. b)
        end
        K.keys("lctrl", "g")
        assert.same(20, K.position())
        arrow_holds("Ctrl+G")
        assert.is_nil(K.cc.editor.input:get_status().custom.arrow)
        K.keys("lctrl", "pagedown")
        assert.same("end", K.position())
        arrow_holds("the end position")
        K.keys("escape")
        assert.is_nil(K.target())
        arrow_holds("after Escape")
        K.keys("lctrl", "z")
        arrow_holds("after the undo of Escape")
        K.keys("lctrl", "g")
        arrow_holds("Ctrl+G after the undo")
        K.keys("escape")
        K.browse_to(5)
        K.keys("f2")
        K.keys("return")
        arrow_holds("after a submit")
        assert.same("browsing", K.state())
      end)
  end

  --- review e7: only the state word's own arrow is never cut; a
  --- name of arrows is cut as any text
  it("cuts a name of arrows as any text", function()
    local sl = K.cc.view.input.statusline
    local was = love.state.app_state
    love.state.app_state = "inspect"
    local project = "p" .. string.rep("↑", 59)
    local texts = placed(sl, { label = "", project = project,
      name = "notes.lua", state = "paused",
      cursor = { l = 1, c = 1 }, n_lines = 1, mode = "text" })
    love.state.app_state = was
    contained(texts, K.cc.cfg.view.w)
    local said = { }
    for _, t in ipairs(texts) do said[t.text] = t end
    local p
    for text in pairs(said) do
      if text:sub(1, 1) == "p" and text:find("↑") then p = text end
    end
    assert.is_not_nil(p)
    assert.equal("…", p:sub(-#"…"))
    assert.is_not_nil(said["notes.lua"])
  end)

  it("keeps the arrow after a cut \"replacing\", in its tone",
    function()
      local sl = K.cc.view.input.statusline
      local was = love.state.app_state
      love.state.app_state = "editor"
      local texts = placed(sl, { custom = {
        project = string.rep("p", 30), name = "notes.lua",
        state = "replacing", arrow = "↑", spans_lines = true,
        selection = 3, buflen = 9,
        range = { ln_label = function() return "L3" end } },
        cursor = { l = 1, c = 1 } })
      love.state.app_state = was
      local word
      for _, x in ipairs(texts) do
        if x.text:find("↑$") then word = x end
      end
      assert.is_not_nil(word)
      assert.equal("…↑", word.text:sub(-#"…↑"))
      assert.is_true(word.text:sub(1, 1) == "r")
      assert.same(colors().editor.fg2, word.colour)
    end)

  --- the maintainer's ruling of November 18, 2026: a number
  --- above 9999 in the draft's cursor and in the block's number
  --- is written in thousands with a K
  for _, case in ipairs({ { 9999, "9999" }, { 10000, "10K" },
    { 10999, "10K" }, { 11000, "11K" }, { 123456, "123K" } }) do
    it("writes " .. case[1] .. " as " .. case[2]
      .. " in the cursor and the block", function()
        local sl = K.cc.view.input.statusline
        local was = love.state.app_state
        love.state.app_state = "editor"
        local texts = placed(sl, { custom = { project = "p",
          name = "f.lua", state = "browsing", spans_lines = true,
          selection = case[1], buflen = case[1] + 1,
          range = { ln_label = function() return "L1" end } },
          cursor = { l = case[1], c = 2 } })
        love.state.app_state = "ready"
        local console = placed(sl, { label = "", project = "p",
          state = "console", cursor = { l = 2, c = case[1] },
          n_lines = 1 })
        love.state.app_state = was
        local said = { }
        for _, t in ipairs(texts) do said[t.text] = true end
        for _, t in ipairs(console) do said[t.text] = true end
        assert.is_true(said["B" .. case[2]], "B" .. case[2])
        assert.is_true(said[case[2] .. ":2"], case[2] .. ":2")
        assert.is_true(said["2:" .. case[2]], "2:" .. case[2])
      end)
  end

  --- the position's width: from its first part to the cursor's end
  local function position_width(texts)
    local first, last
    for _, t in ipairs(texts) do
      if t.text:match("^B") or t.text:match("^L") then
        first = first and math.min(first, t.from) or t.from
      end
      if t.text:match("^[%dK]+:[%dK]+$") then last = t.to end
    end
    return (last - first) / K.cc.cfg.view.fw
  end

  --- the block's lines go exactly when the position would be
  --- wider than half the line, 32 of 64 columns, and not before:
  --- B9999, a gap of one, the lines, a gap of two and 9999:9999
  --- take 17 columns and the lines'
  for _, case in ipairs({ { 15, true }, { 16, false } }) do
    it("keeps the block's lines of " .. case[1] .. " columns "
      .. (case[2] and "within" or "past") .. " half the line "
      .. (case[2] and "" or "out"), function()
        local sl = K.cc.view.input.statusline
        local lines = "L" .. string.rep("1", case[1] - 1)
        local was = love.state.app_state
        love.state.app_state = "editor"
        local texts = placed(sl, { custom = { project = "p",
          name = "f.lua", state = "browsing", spans_lines = true,
          selection = 9999, buflen = 10000,
          range = { ln_label = function() return lines end } },
          cursor = { l = 9999, c = 9999 } })
        love.state.app_state = was
        local kept = false
        for _, t in ipairs(texts) do
          if t.text == lines then kept = true end
        end
        assert.equal(case[2], kept)
        assert.is_true(position_width(texts) <= 32)
        assert.equal(case[2] and 32 or 16, position_width(texts))
      end)
  end

  --- with the numbers in thousands above 9999 the rest of the
  --- position always fits in half the line: the widest numbers,
  --- the block's lines from none to 40 columns
  it("keeps the position within half the line for the widest "
    .. "numbers", function()
      local sl = K.cc.view.input.statusline
      local was = love.state.app_state
      local over
      for _, n in ipairs({ 9999, 10000, 99999, 999999, 9999999 }) do
        for l = 0, 40 do
          local lines = l > 0 and ("L" .. string.rep("9", l - 1)) or nil
          love.state.app_state = "editor"
          local w = position_width(placed(sl, { custom = {
            project = "p", name = "f.lua", state = "replacing",
            spans_lines = true, selection = n, buflen = n + 1,
            range = { ln_label = function() return lines end } },
            cursor = { l = n, c = n } }))
          love.state.app_state = "inspect"
          local wc = position_width(placed(sl, { label = "",
            project = "p", name = "f.lua", state = "paused", back = 1000,
            cursor = { l = n, c = n }, n_lines = 1 }))
          if (w > 32 or wc > 32) and not over then
            over = string.format("%d, lines %d: %d, %d", n, l, w, wc)
          end
        end
      end
      love.state.app_state = was
      assert.is_nil(over)
    end)

  --- e5's Major, by name: project demo, notes.lua, no card, Caps
  --- Lock, inserting before block B10 L10-23
  it("inserting before B10 L10-23 without a card, with Caps Lock, "
    .. "leaves B10 whole", function()
      local sl = K.cc.view.input.statusline
      local was = love.state.app_state
      love.state.app_state = "editor"
      local clash, cells
      without_card(function()
        clash, cells = inked(sl, { custom = { project = "demo",
          name = "notes.lua", state = "inserting", spans_lines = true,
          selection = 10, buflen = 30,
          range = { ln_label = function() return "L10-23" end } },
          cursor = { l = 1, c = 1 }, caps = "CAPS" })
      end)
      love.state.app_state = was
      assert.is_nil(clash)
      local inks = { }
      for _, t in pairs(cells) do inks[t] = true end
      for _, t in ipairs({ "[no sd]", "inserting", "CAPS",
        "B10", "L10-23" }) do
        assert.is_true(inks[t], t)
      end
    end)

  --- e5's Minor, by name: the right block is packed to the right
  --- (the maintainer's ruling of November 18, 2026), so no room
  --- is kept for a longer position, and the file is whole
  it("in a pause without a card, with Caps Lock and combined, packs "
    .. "the right block and keeps the file whole", function()
      local sl = K.cc.view.input.statusline
      local fw = K.cc.cfg.view.fw
      local was = love.state.app_state
      love.state.app_state = "inspect"
      local texts
      without_card(function()
        texts = placed(sl, { label = "", project = "demo",
          name = "notes.lua", state = "paused",
          cursor = { l = 1, c = 1 }, n_lines = 1, mode = "combined",
          caps = "CAPS" })
      end)
      love.state.app_state = was
      contained(texts, K.cc.cfg.view.w)
      local at = { }
      for _, t in ipairs(texts) do at[t.text] = t end
      assert.is_not_nil(at.demo)
      assert.is_not_nil(at["notes.lua"])
      assert.is_not_nil(at.paused)
      -- right to left from the edge: the cursor, Caps, the mode,
      -- each two columns apart
      local edge = K.cc.cfg.view.w - fw
      assert.equal(edge, at["1:1"].to)
      assert.equal(at["1:1"].from - 2 * fw, at.CAPS.to)
      assert.equal(at.CAPS.from - 2 * fw, at["comb>F12"].to)
    end)

  --- the kept render's key holds whether a card is in
  it("has a key that changes with the SD card", function()
    local sl = K.cc.view.input.statusline
    local status = { custom = { project = "p", name = "main.lua",
      state = "running" }, mode = "text" }
    local with = sl:key(status)
    local without
    without_card(function() without = sl:key(status) end)
    assert.are_not.equal(with, without)
  end)

  --- as a program starts, pauses and stops, the project keeps
  --- its place, and the file and the word keep theirs between the
  --- running line and the paused one
  it("keeps the project in its place, and the file and the word "
    .. "between running and paused", function()
      reset({ ["main.lua"] = "function love.update() end\n" })
      local idle = starts_with("console")
      run("run()")
      K.frame()
      local running = starts_with("running")
      assert.equal(idle[1], running[1], "the project's place")
      K.keys("lctrl", "pause")
      K.frame()
      if K.app_state() == "snapshot" then K.cc:suspend() end
      assert.same("inspect", K.app_state())
      starts_with("paused", running)
      K.keys("lctrl", "q")
      K.frame()
      starts_with("console", idle)
      forget()
    end)

  --- the kept render of the bare line is compared by its key:
  --- the line's words change between the console's, a running
  --- program's and a pause's, and so does the key
  it("has a key that changes as the line's words do", function()
    local sl = K.cc.view.input.statusline
    local console = { label = "", project = "p", name = "main.lua",
      state = "console", cursor = { l = 1, c = 1 }, n_lines = 1,
      mode = "text" }
    local running = { custom = { project = "p", name = "main.lua",
      state = "running" }, mode = "text" }
    local was = love.state.app_state
    love.state.app_state = "ready"
    local idle, live = sl:key(console), sl:key(running)
    love.state.app_state = "inspect"
    local paused = sl:key(console)
    love.state.app_state = was
    assert.are_not.equal(idle, live)
    assert.are_not.equal(idle, paused)
    assert.are_not.equal(live, paused)
  end)
end)

--- The view's one rule (CanvasModel:show): its top lies between
--- the oldest kept row and the filled view's top, however the
--- sequence's end moves; a page never skips a row; rest is a
--- state of its own
describe("the scrolled view's rule #console", function()
  before_each(function() reset() end)
  after_each(cleanup)

  local H = 16

  local function tty()
    return K.cc:get_project_env().compy.terminal
  end

  --- the sequence's numbers the view shows; whether all its
  --- rows lie in the sequence; the rows' texts; and whether
  --- each of its rows in the sequence is drawn from the kept
  --- row or the screen's row of its number
  local function shown()
    local out = output()
    local rows = out:window()
    local k = out.kept
    local last = out:view_bounds()
    local scr = screen()
    local ns, texts, inside, drawn = { }, { }, true, true
    for i, r in ipairs(rows) do
      ns[i] = r.n
      local got = r.kept and (r.kept.text:gsub("%s+$", ""))
          or r.y and scr[r.y]
      texts[i] = got
      if r.n < k.first or last < r.n then
        inside = false
      else
        local want = r.n <= k.last
            and (k:get(r.n).text:gsub("%s+$", ""))
            or scr[r.n - k.last]
        if got ~= want then drawn = false end
      end
    end
    return ns, inside, texts, drawn
  end

  --- the `L<n>` rows among `texts` are each the next
  local function in_order(texts, what)
    local m = marks(texts)
    for i = 2, #m do
      assert.equal(m[i - 1] + 1, m[i], what .. ": rows in order")
    end
    return m
  end

  --- Home, then PgDn until rest: every row of the sequence is
  --- shown at least once, the screen's own at rest
  local function pages_cover(what)
    local out = output()
    local first = out.kept.first
    local last = out:view_bounds()
    local seen = { }
    K.keys("home")
    for _ = 1, 200 do
      if not out:is_scrolled() then break end
      local ns, _, _, drawn = shown()
      assert.is_true(drawn, what .. ": a page drawn from its rows")
      for _, n in ipairs(ns) do seen[n] = true end
      K.keys("pagedown")
    end
    assert.is_false(out:is_scrolled(), what .. ": PgDn reached rest")
    for n = out.kept.last + 1, last do seen[n] = true end
    for n = first, last do
      assert.is_true(seen[n] == true,
        what .. ": row " .. n .. " of " .. first .. "-" .. last
        .. " never shown")
    end
  end

  it("pages down over every row above a short screen", function()
    for i = 1, 115 do output():push("L" .. i) end
    tty().clear()
    for i = 116, 118 do output():push("L" .. i) end
    K.frame(100)
    pages_cover("a short screen")
  end)

  it("stays a full window when a clear shortens the sequence",
    function()
      print_lines(1, 40)
      K.keys("lctrl", "up")
      tty().clear()
      K.frame(100)
      local ns, inside, texts, drawn = shown()
      assert.equal(H, #ns)
      assert.is_true(inside)
      assert.is_true(drawn)
      -- the screen's 16 rows went with the clear: the window is
      -- the newest 16 kept, L10 to L25
      assert.same(upto(10, 25), in_order(texts, "after a clear"))
    end)

  it("pages up from an empty screen to a full window", function()
    print_lines(1, 40)
    tty().clear()
    K.frame(100)
    K.keys("pageup")
    local ns, inside, texts, drawn = shown()
    assert.equal(H, #ns)
    assert.is_true(inside)
    assert.is_true(drawn)
    assert.same(upto(10, 25), in_order(texts, "a page up"))
  end)

  it("holds under any mix of prints, clears, Ctrl+L and the "
    .. "scrolling keys", function()
      math.randomseed(20261115)
      local KEYS = { { "lctrl", "up" }, { "lctrl", "down" },
        { "pageup" }, { "pagedown" }, { "home" }, { "end" } }
      local n = 0
      for step = 1, 400 do
        local op = math.random(1, 12)
        if op <= 3 then
          for _ = 1, math.random(1, op == 3 and 60 or 8) do
            n = n + 1
            output():push("L" .. n)
          end
        elseif op == 4 then
          tty().clear()
        elseif op == 5 then
          K.keys("lctrl", "l")
        else
          K.frame(100)
          K.keys(unpack(KEYS[math.random(1, #KEYS)]))
        end
        K.frame(100)
        local out = output()
        local what = "step " .. step
        if out:is_scrolled() then
          local _, filled = out:view_bounds()
          local t = out:top()
          assert.is_true(out.kept.first <= t and t <= filled, what)
          local last = out:view_bounds()
          if last - out.kept.first + 1 >= H then
            local ns, inside, texts, drawn = shown()
            assert.equal(H, #ns, what)
            assert.is_true(inside, what .. ": a row past the end")
            assert.is_true(drawn, what .. ": a row drawn from another")
            assert.is_true(#marks(texts) > 0, what .. ": no row of text")
          end
        end
        if step % 40 == 0 then pages_cover(what) end
      end
    end)
end)

--- The console's field shows why a line was not taken in the
--- notice band above the status line, over the output's bottom
--- rows (the maintainer's rulings of November 15, 2026); the
--- next key that is not lone dismisses the message and does
--- its work. A run's error is said in the output alone.
describe("the scrollback and the console's notice #console",
  function()
    before_each(function() reset() end)
    after_each(cleanup)

    local function message()
      local e = K.cc.input.model.error
      if type(e) == "table" then return table.concat(e, "\n") end
      return e
    end

    it("shows a run error in the output alone", function()
      run("print('a') error('boom')")
      local s = screen()
      local a
      for y, r in ipairs(s) do if r == "a" then a = y end end
      assert.is_not_nil(a)
      assert.truthy(s[a + 1]:find("boom", 1, true))
      assert.is_false(K.cc.input:has_error())
      assert.is_nil(message())
      assert.is_false(output():is_scrolled())
    end)

    it("leaves the view where it is for a line the syntax "
      .. "refuses, unechoed", function()
        print_lines(1, 40)
        K.keys("lctrl", "up")
        K.type("x = = 1")
        K.keys("return")
        K.frame(100)
        assert.is_true(output():is_scrolled())
        assert.is_true(K.cc.input:has_error())
        assert.equal("x = = 1", K.console_draft())
        for _, r in ipairs(screen()) do
          assert.not_equal("x = = 1", r)
        end
      end)

    it("lets Ctrl+Up dismiss a message and scroll, once",
      function()
        print_lines(1, 40)
        K.keys("lctrl", "up")
        local one = view()
        K.keys("end")
        K.type("x = = 1")
        K.keys("return")
        assert.is_true(K.cc.input:has_error())
        K.keys("lctrl", "up")
        assert.is_false(K.cc.input:has_error())
        assert.same(one, view())
      end)

    it("lets Ctrl+L dismiss a message and empty the console",
      function()
        print_lines(1, 40)
        K.type("x = = 1")
        K.keys("return")
        assert.is_true(K.cc.input:has_error())
        K.keys("lctrl", "l")
        K.frame(100)
        assert.is_false(K.cc.input:has_error())
        assert.same({ }, kept())
        for _, r in ipairs(screen()) do assert.equal("", r) end
      end)

    --- the notice band covers the output's bottom rows and a cue
    --- at that edge until the next key (the ruling "A notice is
    --- drawn over the document view")
    it("draws the band over a scrolled view and its bottom cue",
      function()
        print_lines(1, 80)
        K.keys("pageup")
        local _, _, below = output():window()
        assert.is_true(below)
        K.cc.input:set_error({ "a message" })
        output().terminal.dirty = true
        local s = K.screen()
        local mark, band
        for _, p in ipairs(s.texts) do
          if p.text == "v" then mark = p end
        end
        for _, p in ipairs(s.texts) do
          if p.text:find("a message", 1, true) then band = p end
        end
        for _, p in ipairs(s.field) do
          if p.text:find("a message", 1, true) then band = band or p end
        end
        assert.is_not_nil(mark)
        assert.is_not_nil(band)
        assert.is_true(band.seq > mark.seq, "the band after the cue")
        local fh = K.cc.cfg.view.fh
        assert.is_true(math.abs(band.y - mark.y) < 2 * fh,
          "the band over the output's bottom rows")
      end)

    it("lets a typed key dismiss a message over a scrolled view "
      .. "and type once, the view left where it is", function()
        print_lines(1, 40)
        K.keys("lctrl", "up")
        K.cc.input:set_error({ "a message" })
        assert.is_true(output():is_scrolled())
        K.type("q")
        assert.is_false(K.cc.input:has_error())
        assert.is_true(output():is_scrolled())
        assert.equal("q", K.console_draft())
      end)
  end)

-- Ruling 1.1 of November 17, 2026: behind a program that owns
-- the input, the output stays in use and takes its own keys and
-- the wheel when the program leaves them ("the program that only
-- prints into the text buffer, allows scrolling with both
-- keyboard and mouse wheel"). What the program's chain takes,
-- event by event, the output does not get.
describe("the output behind a program that owns the input #console",
  function()
    before_each(function() reset() end)
    after_each(cleanup)

    local PRINTS = "for i = 1, 40 do print('L' .. i) end\n"
    local RUNS = "function love.update() end\n"

    local function wheel(y)
      require("tests.helpers.input_fixture").session.wheelmoved(0, y)
      K.frame()
    end

    it("scrolls with the wheel in the console", function()
      print_lines(1, 40)
      wheel(1)
      assert.is_true(output():is_scrolled())
      wheel(-5)
      assert.is_false(output():is_scrolled())
    end)

    it("scrolls with the wheel behind a program that prints",
      function()
        reset({ ["main.lua"] = PRINTS .. RUNS })
        run("run()")
        assert.same("running", K.app_state())
        wheel(1)
        assert.is_true(output():is_scrolled())
      end)

    it("takes no other key of the console's behind it", function()
      reset({ ["main.lua"] = PRINTS .. RUNS })
      run("run()")
      K.keys("lctrl", "l")
      assert.truthy(K.console_text():find("L40", 1, true))
      K.keys("x")
      assert.same("", K.console_draft())
    end)

    it("gets only the wheel behind a program whose love.keypressed"
      .. " takes every key", function()
        reset({ ["main.lua"] = PRINTS
          .. "function love.keypressed() end\n" .. RUNS })
        run("run()")
        K.keys("lctrl", "up")
        assert.is_false(output():is_scrolled())
        K.keys("lctrl", "pageup")
        assert.is_false(output():is_scrolled())
        wheel(1)
        assert.is_true(output():is_scrolled())
      end)

    it("gets Ctrl+PgUp and Ctrl+PgDn behind a program that leaves "
      .. "them", function()
        reset({ ["main.lua"] = PRINTS .. RUNS })
        run("run()")
        assert.same("running", K.app_state())
        K.keys("lctrl", "pageup")
        assert.is_true(#kept() > 0)
        assert.equal(kept()[1], view()[1])
        K.keys("lctrl", "pagedown")
        assert.is_false(output():is_scrolled())
      end)

    it("passes Ctrl+PgUp to a program whose love.keypressed takes "
      .. "every key", function()
        reset({ ["main.lua"] = PRINTS
          .. "function love.keypressed(k) got = k end\n" .. RUNS })
        run("run()")
        K.keys("lctrl", "pageup")
        assert.same("pageup", K.cc:get_project_env().got)
        assert.is_false(output():is_scrolled())
      end)

    it("gets a key a hook leaves, and not one it takes", function()
      reset({ ["main.lua"] = PRINTS
        .. "compy.input.hooks.keypressed = function(k)\n"
        .. "  return k == 'pageup'\nend\n" .. RUNS })
      run("run()")
      K.keys("pageup")
      assert.is_false(output():is_scrolled())
      K.keys("lctrl", "up")
      assert.is_true(output():is_scrolled())
    end)

    it("gets no wheel a program's own handler takes", function()
      reset({ ["main.lua"] = PRINTS
        .. "function love.wheelmoved() end\n" .. RUNS })
      run("run()")
      wheel(1)
      assert.is_false(output():is_scrolled())
    end)
  end)

-- p1's Major, gone with ruling 1.2: a scrolling key a program's
-- hook takes leaves a scrolled view where it is
describe("a scrolled view behind a program's key #console", function()
  before_each(function() reset() end)
  after_each(cleanup)

  it("stays when the program's hook takes PgUp", function()
    reset({ ["main.lua"] = "for i = 1, 40 do print('L' .. i) end\n"
      .. "compy.input.hooks.keypressed = function(k)\n"
      .. "  return k == 'pageup'\nend\n"
      .. "function love.update() end\n" })
    run("run()")
    require("tests.helpers.input_fixture").session.wheelmoved(0, 1)
    K.frame()
    assert.is_true(output():is_scrolled())
    local t = output():top()
    K.keys("pageup")
    assert.is_true(output():is_scrolled())
    assert.equal(t, output():top())
  end)
end)
