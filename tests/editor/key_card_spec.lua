local KeyCard = require("model.editor.keyCard")

--- the Compy's screen: 17 rows over the status line, 64 wide
local ROWS, WIDTH = 17, 64

--- A card's keys under its first heading and under the
--- second, each as { key = what it does }.
local function group_of(cells)
  local now, other, to = { }, { }, nil
  for _, c in ipairs(cells) do
    if c.heading then
      to = to and other or now
    else
      to[c.key] = c.what
    end
  end
  return now, other
end

local function group(state, empty)
  return group_of(KeyCard.cells(state, empty))
end

describe("the key card #editor", function()
  it("lists the browsing state's keys first", function()
    local now, other = group("browsing", true)
    for _, k in ipairs({
      "Enter", "F2", "Esc", "Ctrl+Q", "Ctrl+Up/Down",
      "Ctrl+Ins", "Ctrl+Delete", "Alt+Up/Down", "Ctrl+Z",
      "Ctrl+Y", "Ctrl+J"
    }) do
      assert.is_string(now[k], k)
    end
    -- the field's keys in a draft come after them
    assert.is_string(other["Ctrl+Left/Right"])
    assert.is_nil(now["Ctrl+Left/Right"])
    -- with an empty field Home and End move through the file
    assert.same("file start/end", now["Home/End"])
  end)

  -- the maintainer's ruling of November 17, 2026: Ctrl+PgUp and
  -- Ctrl+PgDn are the file's start and end in every state, the
  -- draft kept; Home and End only with an empty field
  it("lists Ctrl+PgUp/PgDn, the file's start and end, among the"
      .. " keys now in every state", function()
    for _, st in ipairs({ "browsing", "inserting", "replacing" })
    do
      for _, empty in ipairs({ true, false }) do
        local now = group(st, empty)
        assert.same("file start/end", now["Ctrl+PgUp/PgDn"],
          st .. " " .. tostring(empty))
      end
    end
  end)

  -- trivial keys are bound but not on the card (the
  -- maintainer's ruling of November 14, 2026)
  it("leaves the trivial keys off", function()
    for _, st in ipairs({ "browsing", "inserting", "replacing" })
    do
      local now, other = group(st, st == "browsing")
      for _, k in ipairs({ "Left/Right", "Bksp/Delete",
        "PgDn/PgUp" }) do
        assert.is_nil(now[k], st .. " " .. k)
        assert.is_nil(other[k], st .. " " .. k)
      end
    end
  end)

  -- the selection (the ruling of November 17, 2026): one row
  it("lists Shift with a movement key as select, in every card",
    function()
      local now, other = group("browsing", true)
      assert.is_nil(now["Shift+move"])
      assert.same("select", other["Shift+move"])
      for _, st in ipairs({ "inserting", "replacing" }) do
        assert.same("select", (group(st, false))["Shift+move"], st)
      end
      for _, live in ipairs({ true, false }) do
        local n = group_of(KeyCard.console_cells(live))
        assert.same("select", n["Shift+move"])
      end
    end)

  it("lists Ctrl+A as select all, in every card", function()
    local now, other = group("browsing", true)
    assert.is_nil(now["Ctrl+A"])
    assert.same("select all", other["Ctrl+A"])
    for _, st in ipairs({ "inserting", "replacing" }) do
      assert.same("select all", (group(st, false))["Ctrl+A"], st)
    end
    for _, live in ipairs({ true, false }) do
      local n = group_of(KeyCard.console_cells(live))
      assert.same("select all", n["Ctrl+A"])
    end
  end)

  -- not trivial for a child (the ruling of November 14, late)
  it("lists Ctrl+Home/End, the text's start and end, in every "
      .. "card", function()
    local now, other = group("browsing", true)
    assert.is_nil(now["Ctrl+Home/End"])
    assert.same("text start/end", other["Ctrl+Home/End"])
    for _, st in ipairs({ "inserting", "replacing" }) do
      assert.same("text start/end",
        (group(st, false))["Ctrl+Home/End"], st)
    end
    for _, live in ipairs({ true, false }) do
      local n = group_of(KeyCard.console_cells(live))
      assert.same("text start/end", n["Ctrl+Home/End"])
    end
  end)

  it("moves the keys a state does not admit after it",
      function()
    local ins = group("inserting", false)
    local _, ins_other = group("inserting", false)
    assert.is_nil(ins["F2"])
    assert.is_string(ins_other["F2"])
    assert.is_string(ins_other["Ctrl+Delete"])
    -- leaving waits for the edit to end
    assert.is_nil(ins["Ctrl+Q"])
    assert.same("to the console", ins_other["Ctrl+Q"])
    local rep, rep_other = group("replacing", false)
    assert.is_string(rep["F2"])
    assert.is_string(rep_other["Alt+Up/Down"])
    -- Ctrl+G acts while replacing alone
    assert.same("go to the edit", rep["Ctrl+G"])
    assert.is_nil(ins["Ctrl+G"])
    assert.same("go to the edit", ins_other["Ctrl+G"])
    local br, br_other = group("browsing", true)
    assert.is_nil(br["Ctrl+G"])
    assert.same("go to the edit", br_other["Ctrl+G"])
  end)

  it("says what a key does in the state", function()
    local function enter(state, empty)
      return (group(state, empty)).Enter
    end
    assert.same("add empty line", enter("browsing", true))
    -- with no draft to keep it does what Enter does
    assert.same("add empty line",
      (group("browsing", true))["Shift+Ins"])
    assert.same("insert, keep",
      (group("inserting", false))["Shift+Ins"])
    assert.same("insert text", enter("inserting", false))
    assert.same("replace block", enter("replacing", false))
    assert.same("browse blocks",
      (group("replacing", true))["Up/Down"])
    -- in a draft Up and Down move the cursor, and Home and End
    -- go to the ends of its row: trivial keys, on no row, and
    -- not under the other keys with what they do elsewhere
    for _, st in ipairs({ "inserting", "replacing" }) do
      local now, other = group(st, false)
      for _, k in ipairs({ "Up/Down", "Home/End" }) do
        assert.is_nil(now[k], st .. " " .. k)
        assert.is_nil(other[k], st .. " " .. k)
      end
    end
    -- Ctrl+G, bound in no other state, stays among them
    assert.same("go to the edit",
      select(2, group("inserting", false))["Ctrl+G"])
  end)

  it("fits one screen in every state", function()
    -- the editor's own keys, the field's, and the reserved
    -- chords that act in the editor; in a draft without Up/Down
    -- and Home/End, which move its cursor there
    local COUNT = { browsing = 28, inserting = 26, replacing = 26 }
    for _, state in ipairs({
      "browsing", "inserting", "replacing"
    }) do
      local lines = KeyCard.lines(state, false, ROWS, WIDTH)
      assert.is_true(#lines <= ROWS, state)
      local keys = 0
      for _, l in ipairs(lines) do
        assert.is_true(#l <= WIDTH, l)
      end
      for _, c in ipairs(KeyCard.cells(state, false)) do
        if c.key then
          keys = keys + 1
          local text = table.concat(lines, "\n")
          assert.truthy(text:find(c.key .. " ", 1, true), c.key)
          assert.truthy(text:find(c.what, 1, true), c.what)
        end
      end
      assert.same(COUNT[state], keys, state)
    end
  end)

  it("has a card for the console that fits one screen",
      function()
    for _, live in ipairs({ false, true }) do
      local cells = KeyCard.console_cells(live)
      local lines = KeyCard.lines_of(cells, ROWS, WIDTH)
      assert.is_true(#lines <= ROWS)
      assert.truthy(lines[1]:find("^ Keys now, console:"))
      local text = table.concat(lines, "\n")
      for _, c in ipairs(cells) do
        if c.key then
          assert.truthy(text:find(c.key .. " ", 1, true), c.key)
          assert.truthy(text:find(c.what, 1, true), c.what)
        end
      end
    end
  end)

  --- Ctrl+R alike since November 16: it restarts a live
  --- program only
  it("lists Ctrl+Q and Ctrl+R in the console: among the keys now"
      .. " while a program is not stopped, after them with none",
      function()
    local now, other = group_of(KeyCard.console_cells(true))
    assert.same("exit program", now["Ctrl+Q"])
    assert.same("run anew", now["Ctrl+R"])
    assert.same({ }, other)
    local function after_them(cells)
      local n, o = group_of(cells)
      assert.is_nil(n["Ctrl+Q"])
      assert.is_nil(n["Ctrl+R"])
      assert.same({ ["Ctrl+Q"] = "exit program",
        ["Ctrl+R"] = "run anew" }, o)
    end
    after_them(KeyCard.console_cells(false))
    after_them(KeyCard.console_cells())
    local lines = KeyCard.lines_of(KeyCard.console_cells(),
      ROWS, WIDTH)
    -- the last three of the card's second column, nothing
    -- after them
    local at
    for i, l in ipairs(lines) do
      if l:find(" Other keys:$") then at = i end
    end
    assert.truthy(at)
    assert.truthy(lines[at + 1]:find(" Ctrl%+Q +exit program$"))
    assert.truthy(lines[at + 2]:find(" Ctrl%+R +run anew$"))
    for i = at + 3, #lines do
      assert.same("", (lines[i]:sub(WIDTH / 2 + 1):gsub(" ", "")))
    end
  end)

  --- the screen modes' key (the program's canvas, stage 2): the
  --- console's alone, idle and live; the editor has none
  it("lists F12 in the console, among the keys now, and not in"
      .. " the editor", function()
    for _, live in ipairs({ false, true }) do
      local now = group_of(KeyCard.console_cells(live))
      assert.same("screen", now["F12"])
    end
    for _, state in ipairs({ "browsing", "inserting", "replacing" }) do
      local now, other = group(state, false)
      assert.is_nil(now["F12"])
      assert.is_nil(other["F12"])
    end
  end)

  it("takes one column where two do not fit", function()
    local lines = KeyCard.lines("browsing", true, 40, 40)
    assert.same(30, #lines)
    assert.same(" Keys now, browsing:", lines[1])
  end)
end)
