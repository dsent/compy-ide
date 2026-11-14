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

  -- trivial keys are bound but not on the card (the
  -- maintainer's ruling of November 14, 2026)
  it("leaves the trivial keys off", function()
    for _, st in ipairs({ "browsing", "inserting", "replacing" })
    do
      local now, other = group(st, st == "browsing")
      for _, k in ipairs({ "Left/Right", "Ctrl+Home/End",
        "Bksp/Delete", "PgDn/PgUp" }) do
        assert.is_nil(now[k], st .. " " .. k)
        assert.is_nil(other[k], st .. " " .. k)
      end
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
    -- in a draft Up and Down move the cursor, a trivial key:
    -- the card says what they do with an empty field
    local now, other = group("replacing", false)
    assert.is_nil(now["Up/Down"])
    assert.same("browse blocks", other["Up/Down"])
  end)

  it("fits one screen in every state", function()
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
      -- the editor's own keys, the field's, and the reserved
      -- chords that act in the editor
      assert.same(25, keys)
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

  it("lists Ctrl+Q in the console as exit program: among the "
      .. "keys now while a program is not stopped, after them "
      .. "with none", function()
    local now, other = group_of(KeyCard.console_cells(true))
    assert.same("exit program", now["Ctrl+Q"])
    assert.same({ }, other)
    local function after_them(cells)
      local n, o = group_of(cells)
      assert.is_nil(n["Ctrl+Q"])
      assert.same({ ["Ctrl+Q"] = "exit program" }, o)
    end
    after_them(KeyCard.console_cells(false))
    after_them(KeyCard.console_cells())
    local lines = KeyCard.lines_of(KeyCard.console_cells(),
      ROWS, WIDTH)
    assert.truthy(lines[#lines - 1]:find(" Other keys:$"))
    assert.truthy(lines[#lines]:find(" Ctrl%+Q +exit program$"))
  end)

  it("takes one column where two do not fit", function()
    local lines = KeyCard.lines("browsing", true, 40, 40)
    assert.same(27, #lines)
    assert.same(" Keys now, browsing:", lines[1])
  end)
end)
