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
    .. "and bring the screen back", function()
      print_lines(1, 80)
      K.type("abc")
      K.keys("pageup")
      K.keys("home")
      assert.is_nil(view())
      assert.same({ "abc", 1, 1 }, field())
      K.keys("pageup")
      K.keys("end")
      assert.is_nil(view())
      assert.same({ "abc", 1, 4 }, field())
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
      { "home" } }) do
      K.keys(unpack(k))
      assert.is_nil(view())
    end
  end)

  it("a typed character, Enter, Escape, an arrow and Ctrl+T "
    .. "bring the screen back", function()
      print_lines(1, 40)
      local function scrolled() K.keys("lctrl", "up") end
      scrolled()
      K.type("x")
      assert.is_nil(view())
      assert.equal("x", K.console_draft())
      scrolled()
      K.keys("left")
      assert.is_nil(view())
      scrolled()
      K.keys("escape")
      assert.is_nil(view())
      scrolled()
      K.type("y = 1")
      K.keys("return")
      assert.is_nil(view())
      scrolled()
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

  it("scroll the output of a program that finished and idles "
    .. "behind the console", function()
      reset({ ["main.lua"] =
        "for i = 1, 40 do print('L' .. i) end\n" })
      run("run()")
      assert.is_true(K.cc.run_live)
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
    assert.falsy(empty:find("PgUp", 1, true))
    local typed = card(false)
    assert.truthy(typed:find("scroll a row", 1, true))
    assert.falsy(typed:find("oldest/newest", 1, true))
  end)
end)

describe("the console's kept rows under any mix #console",
  function()
    before_each(function() reset() end)
    after_each(cleanup)

    it("hold every row that scrolled off since Ctrl+L, once and "
      .. "in order, the newest 1,000, and scrolling changes "
      .. "neither them nor the screen", function()
        local t = output().terminal
        local left = { }
        local keep = t.on_row_leaving
        t.on_row_leaving = function(chars, states)
          left[#left + 1] = (table.concat(chars):gsub("%s+$", ""))
          keep(chars, states)
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
            end
          elseif op == 5 then
            tty.clear()
          elseif op == 6 then
            K.keys("lctrl", "l")
            K.frame(100)
            left = { }
          else
            K.frame(100)
            local before = contents()
            K.keys(unpack(SCROLLS[math.random(1, #SCROLLS)]))
            assert.same(before, contents(), "step " .. step)
          end
          K.frame(100)
          local want = { }
          for i = math.max(1, #left - 999), #left do
            want[#want + 1] = left[i]
          end
          assert.same(want, kept(), "step " .. step)
          local m = marks(kept())
          for i = 2, #m do
            assert.is_true(m[i - 1] < m[i], "step " .. step)
          end
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

  it("is followed by the line's error, in the output's color",
    function()
      run("print('a') error('boom')")
      local e = row_of("print('a') error('boom')")
      assert.is_not_nil(e)
      assert.equal(e + 1, row_of("a"))
      local s, t = screen(), output().terminal
      local err = s[e + 2]
      assert.truthy(err:find("boom", 1, true), err)
      assert.same(colors().fg, t.state_buffer[e + 2][1].color)
      assert.is_true(K.cc.input:has_error())
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
