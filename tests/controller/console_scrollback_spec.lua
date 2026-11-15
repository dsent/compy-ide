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
local function reset(contents)
  K.reset(contents)
  K.cc:get_base_env().print = print
  K.cc:get_project_env().print = print
end

describe("the console's kept rows #console", function()
  before_each(function() reset() end)
  after_each(K.cleanup)

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
    local before = kept()
    run("compy.terminal.clear()")
    assert.same(before, kept())
    for _, r in ipairs(screen()) do assert.equal("", r) end
    print_lines(31, 40)
    local k = marks(kept())
    for _, n in ipairs(k) do
      assert.is_true(n <= 30, "a cleared row was kept: L" .. n)
    end
  end)

  it("are forgotten by Ctrl+L, with the screen", function()
    print_lines(1, 40)
    assert.is_true(#kept() > 0)
    K.keys("lctrl", "l")
    K.frame(100)
    assert.same({ }, kept())
    for _, r in ipairs(screen()) do assert.equal("", r) end
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

describe("the console's scrolled view #console", function()
  before_each(function() reset() end)
  after_each(K.cleanup)

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
            and y < H and #p.text <= 4 and not mark then
          rows[y + 1] = rows[y + 1] or { }
          rows[y + 1][col + 1] = p.text
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
