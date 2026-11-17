-- IS3.4 with letters outside ASCII: a draft that fails on
-- one is located at that letter, and its message names the
-- whole letter, not one of its bytes. Children type Cyrillic
-- and other scripts, so this is an ordinary draft. Keys only,
-- through tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local F = require("tests.helpers.input_fixture")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it

local FILE = "x = 1\n"

local function open_file()
  K.reset({ ["main.lua"] = FILE })
  K.open()
  K.browse_to_end()
end

--- `s` is text the screen can draw: valid UTF-8
local function valid(s)
  return string.scrub(s) == s
end

--- Every text the whole screen draws is valid UTF-8, and the
--- draw raises nothing.
local function screen_is_text()
  local s = K.screen()
  for _, list in ipairs({ s.texts, s.field }) do
    for _, t in ipairs(list) do
      assert.is_true(valid(t.text), t.text)
    end
  end
end

--- Enter on `draft`, which fails at column `col` on `ch`
local function fails_at(draft, col, ch)
  open_file()
  K.type(draft)
  local ok, err = pcall(K.keys, "return")
  assert.is_true(ok, err)
  assert.same(draft, K.draft())
  assert.same(FILE, K.file())
  local msg = K.message() or ""
  assert.is_true(valid(msg), msg)
  assert.truthy(msg:find("`" .. ch .. "'", 1, true), msg)
  assert.same({
    1,
    col
  }, { K.cursor() })
  local _, at = K.field_highlight()
  assert.same({
    1,
    col
  }, at)
  screen_is_text()
end

--- The columns three presses of Ctrl+Right, then three of
--- Ctrl+Left, stop at in a draft of `text`, from its start.
local function word_stops(text)
  open_file()
  K.type(text)
  K.keys("home")
  local stops = { }
  for _, k in ipairs({ "right", "right", "right", "left",
    "left", "left" }) do
    K.keys("lctrl", k)
    local _, c = K.cursor()
    stops[#stops + 1] = c
  end
  return stops
end

describe("IS3.8 words outside ASCII #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  spec_it("IS3.8 Position the text cursor: letterlike "
      .. "symbols and number forms are letters of a word",
      function()
    assert.same({ 2, 4, 6, 5, 3, 1 }, word_stops("ℝ ⅻ ½"))
  end)

  spec_it("IS3.8 Position the text cursor: a sign among "
      .. "them separates words", function()
    assert.same({ 2, 4, 9, 7, 3, 1 }, word_stops("a™b → x₂"))
  end)
end)

describe("IS3.4 letters outside ASCII #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  spec_it("IS3.4 Locate a syntax failure: a Latin letter "
      .. "outside ASCII that opens the draft", function()
    fails_at("é = 1", 1, "é")
  end)

  spec_it("IS3.4 Locate a syntax failure: a Cyrillic letter "
      .. "that opens the draft", function()
    fails_at("п = 1", 1, "п")
  end)

  spec_it("IS3.4 Locate a syntax failure: a Cyrillic letter "
      .. "where an expression goes", function()
    fails_at("x = ж", 5, "ж")
  end)

  spec_it("IS3.4 Locate a syntax failure: an emoji where an "
      .. "expression goes", function()
    fails_at("x = 😀", 5, "😀")
  end)

  spec_it("IS3.4 Locate a syntax failure: a cut block with "
      .. "a letter outside ASCII stays in the field on Enter",
      function()
    -- LuaJIT runs names with bytes over 127; the editor's
    -- parser does not, so the block is cut to be fixed
    K.reset({ ["main.lua"] = "élet = 3\ny = 2\n" })
    K.open()
    K.browse_to(1)
    K.keys("lctrl", "delete")
    assert.same("élet = 3", K.draft())
    local ok, err = pcall(K.keys, "return")
    assert.is_true(ok, err)
    assert.same("élet = 3", K.draft())
    assert.same("y = 2\n", K.file())
    assert.truthy((K.message() or ""):find("`é'", 1, true))
    screen_is_text()
  end)

  spec_it("IS3.4 Locate a syntax failure: a letter outside "
      .. "ASCII in a string is no failure", function()
    open_file()
    K.type('x = "ж"')
    K.keys("return")
    assert.same("", K.draft())
    assert.same(FILE .. 'x = "ж"\n', K.file())
  end)

  spec_it("IS3.4 Locate a syntax failure: a byte that is not "
      .. "UTF-8, arriving as text, raises nothing", function()
    open_file()
    F.session.type("\255 = 1")
    K.frame()
    assert.is_true(valid(K.draft()))
    local ok, err = pcall(K.keys, "return")
    assert.is_true(ok, err)
    assert.same(FILE, K.file())
    assert.is_true(valid(K.message() or ""))
    screen_is_text()
  end)
end)
