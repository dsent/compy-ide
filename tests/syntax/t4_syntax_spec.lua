-- A fourth syntax, made for this test, drives the editor
-- through keys: the editor knows no file type, so a syntax it
-- has never seen opens, edits, refuses, formats, cuts and
-- moves through the syntax API alone (rulings.md, "The syntax
-- processor").

local K = require("tests.helpers.editor_keys")
local Syntax = require("model.syntax")
require("model.editor.content")
require("util.dequeue")
require("util.range")

local REFUSAL = "A line may not start with !. Change it, then press Enter"

--- A draft whose last line ends in & goes on: a new line
--- indented by two, the cursor after the indent; Lua's would
--- be an empty line, the cursor at its start
--- @param lines string[]
--- @return SyntaxVerdict?
local function goes_on(lines)
  local last = lines[#lines] or ""
  if string.sub(last, -1) ~= "&" then return nil end
  local out = { }
  for i, l in ipairs(lines) do out[i] = l end
  out[#out + 1] = "  "
  return { lines = out, formatted = true,
    cursor = { l = #out, c = 3 } }
end

--- Every two lines are a block, a last odd line one alone
local function pairs_of(lines)
  local out = Dequeue.typed("block")
  for ln = 1, #lines, 2 do
    local last = math.min(ln + 1, #lines)
    local ls = { }
    for l = ln, last do ls[#ls + 1] = lines[l] end
    out:push_back(Chunk(ls, Range(ln, last)))
  end
  return out
end

local t4 = {
  name = "t4",
  spans_lines = true,
  blocks = pairs_of,
  submit = function(lines)
    local more = goes_on(lines)
    if more then return more end
    for _, l in ipairs(lines) do
      if string.sub(l, 1, 1) == "!" then
        return { lines = lines, formatted = false,
          refusal = REFUSAL }
      end
    end
    return { lines = lines, formatted = false,
      blocks = pairs_of(lines) }
  end,
  format = function(lines)
    local out, changed = { }, false
    for i, l in ipairs(lines) do
      out[i] = string.upper(l)
      changed = changed or out[i] ~= l
    end
    return out, changed, "is upper case already"
  end,
  loads = function() return true end,
  --- a line that starts with # is green, any other blue
  highlight = function(lines)
    local hl = { }
    for l, s in ipairs(lines) do
      hl[l] = { }
      local c = string.sub(s, 1, 1) == "#" and Color.green
          or Color.blue
      for i = 1, #s do hl[l][i] = c end
    end
    return hl
  end,
  references = function() return { } end,
  evaluator = function()
    require("model.interpreter.eval.evaluator")
    return TextEval
  end,
}

local FILE = "one\ntwo\nthree\nfour\n"

--- The parser t4 hands a field, whose evaluator asks it what
--- a draft that does not parse comes to
local function t4_evaluator()
  require("model.interpreter.eval.evaluator")
  require("model.lang.lua.error")
  local parser = {
    parse = function(lines)
      if goes_on(lines) then
        return false, Error("goes on", 1, 1)
      end
      return true, { }
    end,
    unparsed = function(lines) return goes_on(lines) end,
  }
  return Evaluator("t4", { parser = parser })
end

describe("a fourth syntax, through keys #syntax #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  before_each(function()
    Syntax.register("t4", t4)
    K.reset({ ["a.t4"] = FILE })
    K.open("a.t4")
  end)
  after_each(function()
    Syntax.register("t4", nil)
    K.cleanup()
  end)

  it("opens as the syntax's blocks", function()
    assert.same("a.t4", K.file_name())
    assert.same(2, K.blocks())
    assert.same("end", K.position())
  end)

  it("loads a block with F2 as the syntax formats it, and "
      .. "lands the draft as the syntax's blocks", function()
    K.browse_to(1)
    K.keys("f2")
    assert.same("replacing", K.state())
    assert.same("ONE\nTWO", K.draft())
    K.type("x")
    K.keys("return")
    assert.same("browsing", K.state())
    assert.same("ONE\nTWOx\nthree\nfour\n", K.file("a.t4"))
    assert.same(2, K.blocks())
  end)

  it("refuses a draft with the syntax's notice, and the "
      .. "next key acts", function()
    K.browse_to(1)
    K.keys("f2")
    K.keys("lshift", "return")
    K.type("!no")
    K.keys("return")
    assert.same(REFUSAL, K.message())
    assert.same(FILE, K.file("a.t4"))
    assert.same("ONE\nTWO\n!no", K.draft())
    K.keys("backspace")
    assert.is_nil(K.message())
    assert.same("ONE\nTWO\n!n", K.draft())
  end)

  it("formats with Alt+F, and says why when it does "
      .. "not", function()
    K.browse_to(1)
    K.keys("lalt", "f")
    assert.same("ONE\nTWO\nTHREE\nFOUR\n", K.file("a.t4"))
    K.keys("lalt", "f")
    assert.same("The file is upper case already.", K.message())
  end)

  it("shows a draft that goes on as the syntax returns it, "
      .. "the cursor where it says, nothing written", function()
    K.browse_to(1)
    K.keys("f2")
    K.type("&")
    K.keys("return")
    assert.same("replacing", K.state())
    assert.same("ONE\nTWO&\n  ", K.draft())
    assert.same({ 3, 3 }, { K.cursor() })
    assert.is_nil(K.message())
    assert.same(FILE, K.file("a.t4"))
    -- one change to undo, as a typed line break would be
    K.keys("lctrl", "z")
    assert.same("ONE\nTWO&", K.draft())
  end)

  it("a field shows a draft that goes on as the syntax "
      .. "returns it", function()
    K.keys("escape")
    K.keys("escape")
    local console = K.cc.input
    local was = console:get_eval()
    finally(function() console:set_eval(was) end)
    console:set_eval(t4_evaluator())
    K.type("x &")
    K.keys("return")
    assert.same("x &\n  ", K.console_draft())
    assert.same({ 2, 3 }, { console.model:get_cursor_pos() })
    -- no error: the hint that the statement goes on
    assert.same("notice", console:message_kind())
    assert.is_nil(console.model:get_highlight().parse_err)
  end)

  it("cuts a block into the draft with Ctrl+Delete", function()
    K.browse_to(1)
    K.keys("lctrl", "delete")
    assert.same("three\nfour\n", K.file("a.t4"))
    assert.same("one\ntwo", K.draft())
  end)

  it("moves a block with Alt+Down", function()
    K.browse_to(1)
    K.keys("lalt", "down")
    assert.same("three\nfour\none\ntwo\n", K.file("a.t4"))
    assert.same(2, K.position())
  end)

  it("draws the syntax's colors", function()
    K.reset({ ["b.t4"] = "# a\nbc\n" })
    K.open("b.t4")
    --- the key K.text_colours files a colour's text under
    local function key(ci)
      local c = Color[ci]
      return string.format("%.2f,%.2f,%.2f", c[1], c[2], c[3])
    end
    assert.same({
      [key(Color.green)] = "#a",
      [key(Color.blue)] = "bc",
    }, K.text_colours())
  end)
end)
