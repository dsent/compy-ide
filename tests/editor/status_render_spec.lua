-- What the status line, a notice and the key card draw,
-- through the real draw functions (K.screen): the fixture's
-- graphics stand-in skips this path everywhere else.

local K = require("tests.helpers.editor_keys")

local function field(s)
  return K.screen_text(s.field)
end

--- The y of the first text drawn in the field that is `text`.
local function y_of(s, text)
  for _, t in ipairs(s.field) do
    if t.text == text then
      return t.y
    end
  end
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

  it("the status line shows Caps Lock while it is on",
      function()
    assert.is_nil(field(K.screen()):find("CAPS", 1, true))
    K.keys("capslock")
    assert.truthy(field(K.screen()):find("CAPS", 1, true))
    K.keys("capslock")
    assert.is_nil(field(K.screen()):find("CAPS", 1, true))
  end)

  it("a notice shows under the draft, which stays", function()
    K.browse_to(1)
    K.type("r")
    -- Edit during an insertion is refused
    K.keys("f2")
    local rows = K.ed.input:get_wrapped_error()
    local s = K.screen()
    assert.is_truthy(K.message())
    assert.same("r", K.draft())
    assert.same(1 + #rows, s.field_rows)
    assert.truthy(field(s):find("inserting", 1, true))
    assert.is_nil(field(s):find("Errors:", 1, true))
    local draft_y, notice_y = y_of(s, "r"), y_of(s, rows[1])
    assert.is_number(draft_y)
    assert.is_number(notice_y)
    assert.is_true(draft_y < notice_y)
    -- the next key dismisses it, and the field is one row
    K.keys("right")
    assert.is_nil(K.message())
    assert.same(1, K.screen().field_rows)
  end)

  it("a notice wider than the field wraps between words",
      function()
    local words = string.rep("seven77 ", 12) .. "end."
    K.ed:notice(words)
    local rows = K.ed.input:get_wrapped_error()
    assert.same(2, #rows)
    assert.same(words, table.concat(rows, " "))
    for _, r in ipairs(rows) do
      assert.is_true(#r <= 64, r)
    end
    assert.same(3, K.screen().field_rows)
  end)

  it("a refused Edit at the end position shows one plain row",
      function()
    K.browse_to_end()
    K.keys("f2")
    local rows = K.ed.input:get_wrapped_error()
    assert.same(1, #rows)
    assert.same(K.message(), rows[1])
    assert.same(2, K.screen().field_rows)
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
    -- 64 columns hold all of it beside `B5 L5-11(7)`
    assert.truthy(f:find("L5-11(7)", 1, true))
    assert.truthy(f:find("scratchpad", 1, true))
    assert.truthy(f:find("main.lua", 1, true))
    assert.truthy(f:find("inserting", 1, true))
    -- a name too long for the line gives way, alone
    K.cc.model.projects.current.name = string.rep("p", 40)
    f = field(K.screen())
    -- up to two columns before the position: 13 and the mark
    assert.truthy(f:find(string.rep("p", 13) .. "…", 1, true))
    assert.is_nil(f:find(string.rep("p", 14), 1, true))
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
