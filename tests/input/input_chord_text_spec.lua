-- A modifier chord's own glyph is no typed text.
--
-- On the device a Ctrl+letter or Alt+letter chord also sends
-- the letter as text, and text arrives BEFORE its key press;
-- on a desktop, where a chord's text surfaces at all, it comes
-- after. The event gate stops that glyph (Key.chord_text,
-- controller.lua handlers.textinput), so it reaches no text
-- field: not the console's, not the file editor's, not a
-- project's input widget. A project's shortcuts and hook sit
-- above its widget and still get it.
--
-- Every case runs in both delivery orders, through the
-- production gateway (F.session, the K helper).

local F = require("tests.helpers.input_fixture")
local K = require("tests.helpers.editor_keys")

local ORDERS = {
  "text before the key press",
  "text after the key press"
}

--- Press a chord as a keyboard does: the modifiers go down,
--- the key and its glyph arrive in `order`, and everything is
--- let go.
--- @param order string  one of ORDERS
--- @param mods string[]
--- @param key string
--- @param glyph string?  the text the device sends with it
local function chord(order, mods, key, glyph)
  for _, m in ipairs(mods) do
    F.session.press(m)
  end
  if glyph and order == ORDERS[1] then
    F.session.type(glyph)
  end
  F.session.press(key)
  if glyph and order == ORDERS[2] then
    F.session.type(glyph)
  end
  F.session.release(key)
  for i = #mods, 1, -1 do
    F.session.release(mods[i])
  end
  K.frame()
end

--- Run `case` once for each delivery order.
local function in_both_orders(name, case)
  for _, order in ipairs(ORDERS) do
    it(name .. ", " .. order, function()
      case(order)
    end)
  end
end

--- Pose as the system `name` (love.system.getOS) in each case
--- of the enclosing describe, from its before_each on.
local function posing_as(name)
  local get_os
  before_each(function()
    get_os = love.system.getOS
    love.system.getOS = function()
      return name
    end
  end)
  after_each(function()
    love.system.getOS = get_os
  end)
end

describe("a chord's own glyph is no text #input", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("in the console", function()
    before_each(function()
      K.reset()
      K.type("abc")
    end)

    in_both_orders("Ctrl+L types no l", function(order)
      chord(order, { "lctrl" }, "l", "l")
      assert.same("abc", K.console_draft())
    end)

    -- the system clipboard has left the field
    in_both_orders("Ctrl+C types no c and copies nothing",
        function(order)
      love.system.setClipboardText("kept")
      K.keys("lshift", "home")
      chord(order, { "lctrl" }, "c", "c")
      assert.same("abc", K.console_draft())
      assert.same("kept", K.clipboard())
    end)

    in_both_orders("Ctrl+X types no x and cuts nothing",
        function(order)
      love.system.setClipboardText("kept")
      K.keys("lshift", "home")
      chord(order, { "lctrl" }, "x", "x")
      assert.same("abc", K.console_draft())
      assert.same("kept", K.clipboard())
    end)

    in_both_orders("Ctrl+V types no v and pastes nothing",
        function(order)
      love.system.setClipboardText("xyz")
      chord(order, { "lctrl" }, "v", "v")
      assert.same("abc", K.console_draft())
    end)

    -- Ctrl+Z undoes the typing (D-UNDO-KEYS), and adds no z
    in_both_orders("Ctrl+Z types no z", function(order)
      chord(order, { "lctrl" }, "z", "z")
      assert.same("", K.console_draft())
    end)

    in_both_orders("the right Ctrl is a Ctrl too", function(
      order
    )
      chord(order, { "rctrl" }, "l", "l")
      assert.same("abc", K.console_draft())
    end)

    in_both_orders("Ctrl+Shift+L types no L", function(order)
      chord(order, {
        "lctrl",
        "lshift"
      }, "l", "L")
      assert.same("abc", K.console_draft())
    end)

    in_both_orders("Alt+X types no x", function(order)
      chord(order, { "lalt" }, "x", "x")
      assert.same("abc", K.console_draft())
    end)

    in_both_orders("Ctrl+Alt+X types no x", function(order)
      chord(order, {
        "lctrl",
        "lalt"
      }, "x", "x")
      assert.same("abc", K.console_draft())
    end)

    in_both_orders("Shift composes text", function(order)
      chord(order, { "lshift" }, "d", "D")
      assert.same("abcD", K.console_draft())
    end)

    in_both_orders("typing goes on after the chord", function(
      order
    )
      chord(order, { "lctrl" }, "l", "l")
      K.type("d")
      assert.same("abcd", K.console_draft())
    end)
  end)

  describe("in the console, under an error message", function()
    before_each(function()
      K.reset()
      K.type("x = = 1")
      K.keys("return")
    end)

    in_both_orders("Ctrl+L types no l on the failed line",
        function(order)
      assert.is_true(F.console:has_error())
      chord(order, { "lctrl" }, "l", "l")
      assert.same("x = = 1", K.console_draft())
    end)

    in_both_orders("Ctrl+V types no v and pastes nothing",
        function(order)
      love.system.setClipboardText("9")
      F.console.model:jump_end()
      chord(order, { "lctrl" }, "v", "v")
      assert.same("x = = 1", K.console_draft())
    end)
  end)

  describe("in the file editor's field", function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.open()
      K.browse_to_end()
      K.type("abc def")
    end)

    in_both_orders("Ctrl+K removes to the line's end and types "
        .. "no k", function(order)
      K.keys("lctrl", "home")
      for _ = 1, 3 do
        K.keys("right")
      end
      chord(order, { "lctrl" }, "k", "k")
      assert.same("abc", K.draft())
    end)

    in_both_orders("Ctrl+W removes a word and types no w",
        function(order)
      chord(order, { "lctrl" }, "w", "w")
      assert.same("abc ", K.draft())
    end)

    in_both_orders("Ctrl+Left moves by word and types nothing",
        function(order)
      chord(order, { "lctrl" }, "left", nil)
      assert.same("abc def", K.draft())
      assert.same({
        1,
        5
      }, { K.cursor() })
    end)

    in_both_orders("Alt+X types no x", function(order)
      chord(order, { "lalt" }, "x", "x")
      assert.same("abc def", K.draft())
    end)

    in_both_orders("a refused Ctrl+T keeps its notice, and no "
        .. "t is typed", function(order)
      chord(order, { "lctrl" }, "t", "t")
      assert.same("editor", K.app_state())
      assert.is_not_nil(K.message())
      assert.same("abc def", K.draft())
      -- the next key dismisses the notice and does its work
      K.type("g")
      assert.is_nil(K.message())
      assert.same("abc defg", K.draft())
    end)

    in_both_orders("a chord's glyph leaves a notice showing",
        function(order)
      -- no block at the end position: Ctrl+Delete is refused
      K.keys("lctrl", "home")
      K.keys("lctrl", "k")
      K.keys("lctrl", "delete")
      local notice = K.message()
      -- the glyph alone, the modifier still held
      F.session.press("lctrl")
      F.session.type("q")
      local kept = K.message()
      F.session.release("lctrl")
      K.frame()
      assert.is_not_nil(notice)
      assert.same(notice, kept)
      assert.same("", K.draft())
      assert.is_string(order)
    end)

    in_both_orders("in a browsing editor a chord's glyph begins "
        .. "no insertion", function(order)
      K.keys("lctrl", "home")
      K.keys("lctrl", "k")
      assert.same("browsing", K.state())
      chord(order, { "lalt" }, "x", "x")
      assert.same("browsing", K.state())
      assert.same("", K.draft())
    end)
  end)

  -- On a computer the right Alt key is AltGr, which composes
  -- text in the layout its user brings. On a Compy (Android)
  -- it is an Alt like the left one: what arrives while it is
  -- held is a chord's, whatever the character.
  describe("the right Alt key, in the console", function()
    before_each(function()
      K.reset()
      K.type("abc")
    end)

    describe("on a computer (Linux), as AltGr", function()
      posing_as("Linux")

      in_both_orders("a composed character lands", function(
        order
      )
        chord(order, { "ralt" }, "q", "@")
        chord(order, { "ralt" }, "a", "ą")
        chord(order, { "ralt" }, "e", "€")
        assert.same("abc@ą€", K.console_draft())
      end)

      in_both_orders("with Shift, a composed character lands",
          function(order)
        chord(order, {
          "ralt",
          "lshift"
        }, "a", "Ą")
        assert.same("abcĄ", K.console_draft())
      end)

      -- a computer sends no text for a chord, so whatever
      -- arrives under AltGr is composed: the French us-alt
      -- layout types 6 through AltGr on its 6 key
      in_both_orders("an ASCII letter, digit or space lands too",
          function(order)
        chord(order, { "ralt" }, "6", "6")
        chord(order, { "ralt" }, "x", "x")
        chord(order, { "ralt" }, "space", " ")
        assert.same("abc6x ", K.console_draft())
      end)

      in_both_orders("left Ctrl with right Alt is a chord",
          function(order)
        chord(order, {
          "lctrl",
          "ralt"
        }, "q", "@")
        assert.same("abc", K.console_draft())
      end)

      in_both_orders("with the left Alt or the right Ctrl too, "
          .. "it is a chord", function(order)
        chord(order, {
          "lalt",
          "ralt"
        }, "q", "@")
        chord(order, {
          "rctrl",
          "ralt"
        }, "q", "@")
        assert.same("abc", K.console_draft())
      end)
    end)

    describe("on a computer (Windows), as AltGr", function()
      posing_as("Windows")

      in_both_orders("as Windows reports it, left Ctrl with "
          .. "right Alt, a composed character lands", function(
        order
      )
        chord(order, {
          "lctrl",
          "ralt"
        }, "q", "@")
        assert.same("abc@", K.console_draft())
      end)
    end)

    describe("on a Compy (Android), as an Alt", function()
      posing_as("Android")

      in_both_orders("a composed character does not land",
          function(order)
        chord(order, { "ralt" }, "q", "@")
        chord(order, { "ralt" }, "a", "ą")
        chord(order, { "ralt" }, "e", "€")
        assert.same("abc", K.console_draft())
      end)

      in_both_orders("with Shift, a composed character does "
          .. "not land", function(order)
        chord(order, {
          "ralt",
          "lshift"
        }, "a", "Ą")
        assert.same("abc", K.console_draft())
      end)

      in_both_orders("the key's own glyph does not either",
          function(order)
        chord(order, { "ralt" }, "x", "x")
        chord(order, { "ralt" }, "1", "1")
        chord(order, { "ralt" }, "space", " ")
        assert.same("abc", K.console_draft())
      end)

      in_both_orders("left Ctrl with right Alt is a chord",
          function(order)
        chord(order, {
          "lctrl",
          "ralt"
        }, "q", "@")
        assert.same("abc", K.console_draft())
      end)

      in_both_orders("typing goes on after the chord", function(
        order
      )
        chord(order, { "ralt" }, "q", "@")
        K.type("d")
        assert.same("abcd", K.console_draft())
      end)
    end)
  end)

  describe("the right Alt key, in the file editor's field",
      function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.open()
      K.browse_to_end()
      K.type("s = ")
    end)

    describe("on a computer (Linux), as AltGr", function()
      posing_as("Linux")

      in_both_orders("a composed character lands", function(
        order
      )
        chord(order, { "ralt" }, "q", "@")
        assert.same("s = @", K.draft())
      end)

      in_both_orders("an ASCII digit lands too", function(
        order
      )
        chord(order, { "ralt" }, "6", "6")
        assert.same("s = 6", K.draft())
      end)
    end)

    describe("on a Compy (Android), as an Alt", function()
      posing_as("Android")

      in_both_orders("a composed character does not land",
          function(order)
        chord(order, { "ralt" }, "q", "@")
        assert.same("s = ", K.draft())
      end)

      in_both_orders("the key's own glyph does not either",
          function(order)
        chord(order, { "ralt" }, "x", "x")
        assert.same("s = ", K.draft())
      end)
    end)
  end)

  describe("the right Alt key, in a project's input field",
      function()
    local input, widget

    before_each(function()
      K.reset()
      input = F.activate_project()
      widget = F.show_widget({ text = "hey" })
    end)

    local function field()
      return table.concat(widget:get_text(), "\n")
    end

    describe("on a computer (Linux), as AltGr", function()
      posing_as("Linux")

      in_both_orders("a composed character lands", function(
        order
      )
        chord(order, { "ralt" }, "q", "@")
        assert.same("hey@", field())
      end)

      in_both_orders("an ASCII digit lands too", function(
        order
      )
        chord(order, { "ralt" }, "6", "6")
        assert.same("hey6", field())
      end)
    end)

    describe("on a Compy (Android), as an Alt", function()
      posing_as("Android")

      in_both_orders("a composed character does not land",
          function(order)
        chord(order, { "ralt" }, "q", "@")
        assert.same("hey", field())
      end)

      in_both_orders("the key's own glyph does not either",
          function(order)
        chord(order, { "ralt" }, "x", "x")
        assert.same("hey", field())
      end)

      in_both_orders("the project's shortcut still gets the "
          .. "chord's text", function(order)
        local got = { }
        input.shortcuts.textinput["alt+@"] = function(t)
          got[#got + 1] = t
          return true
        end
        chord(order, { "ralt" }, "q", "@")
        assert.same({ "@" }, got)
        assert.same("hey", field())
      end)

      in_both_orders("the project's hook still gets it, and the "
          .. "field does not", function(order)
        local got = { }
        input.hooks.textinput = function(t)
          got[#got + 1] = t
        end
        chord(order, { "ralt" }, "q", "@")
        chord(order, { "ralt" }, "x", "x")
        chord(order, { }, "z", "z")
        assert.same({
          "@",
          "x",
          "z"
        }, got)
        assert.same("heyz", field())
      end)
    end)
  end)

  describe("in a project's input field", function()
    local input, widget

    before_each(function()
      K.reset()
      input = F.activate_project()
      widget = F.show_widget({ text = "hey" })
    end)

    local function field()
      return table.concat(widget:get_text(), "\n")
    end

    in_both_orders("Ctrl+L types no l", function(order)
      chord(order, { "lctrl" }, "l", "l")
      assert.same("hey", field())
    end)

    in_both_orders("Alt+X types no x", function(order)
      chord(order, { "lalt" }, "x", "x")
      assert.same("hey", field())
    end)

    in_both_orders("typed text and AltGr's still land",
        function(order)
      chord(order, { }, "x", "x")
      chord(order, { "lshift" }, "y", "Y")
      chord(order, { "ralt" }, "q", "@")
      assert.same("heyxY@", field())
    end)

    -- the input contract (doc/input_api.md): shortcuts and the
    -- hook are offered every text event, with its modifiers
    in_both_orders("the project's shortcut still gets the "
        .. "chord's text", function(order)
      local got = { }
      input.shortcuts.textinput["ctrl+j"] = function(t)
        got[#got + 1] = t
        return true
      end
      chord(order, { "lctrl" }, "j", "j")
      assert.same({ "j" }, got)
      assert.same("hey", field())
    end)

    in_both_orders("the project's hook still gets it, and the "
        .. "field does not", function(order)
      local got = { }
      input.hooks.textinput = function(t)
        got[#got + 1] = t
        -- falsey: the walk goes on below the hook
      end
      chord(order, { "lalt" }, "x", "x")
      chord(order, { }, "z", "z")
      assert.same({
        "x",
        "z"
      }, got)
      assert.same("heyz", field())
    end)
  end)

  describe("in a project with no field shown", function()
    before_each(function()
      K.reset()
    end)

    in_both_orders("a chord's glyph does not fall through to "
        .. "the console", function(order)
      F.activate_project({ })
      chord(order, { "lctrl" }, "l", "l")
      assert.same("", K.console_draft())
      -- typed text does, as before
      chord(order, { }, "a", "a")
      assert.same("a", K.console_draft())
    end)

    in_both_orders("a project's own text handler gets every "
        .. "text event", function(order)
      local got = { }
      F.activate_project({
        textinput = function(t)
          got[#got + 1] = t
        end
      })
      chord(order, { "lctrl" }, "l", "l")
      chord(order, { }, "a", "a")
      assert.same({
        "l",
        "a"
      }, got)
    end)
  end)
end)

describe("Key.chord_text #input", function()
  setup(K.setup)
  teardown(K.teardown)

  local mock = require("tests.mock")

  after_each(function()
    mock.release_keys()
  end)

  --- Whether `t` is a chord's glyph while `keys` are held.
  local function with(keys, t)
    mock.release_keys()
    for _, k in ipairs(keys) do
      mock.hold(k)
    end
    local verdict = Key.chord_text(t)
    mock.release_keys()
    return verdict
  end

  it("is false with no modifier, or with Shift alone", function()
    assert.is_false(with({ }, "a"))
    assert.is_false(with({ "lshift" }, "A"))
    assert.is_false(with({ "rshift" }, "?"))
  end)

  it("is true with a Ctrl or the left Alt, whatever the text",
      function()
    assert.is_true(with({ "lctrl" }, "l"))
    assert.is_true(with({ "rctrl" }, "L"))
    assert.is_true(with({ "lalt" }, "x"))
    assert.is_true(with({ "lalt" }, "@"))
    assert.is_true(with({
      "lctrl",
      "lshift"
    }, "é"))
    assert.is_true(with({
      "rctrl",
      "ralt"
    }, "@"))
  end)

  describe("on a computer (Linux)", function()
    posing_as("Linux")

    it("is false under AltGr, whatever the text", function()
      assert.is_false(with({ "ralt" }, "@"))
      assert.is_false(with({ "ralt" }, "ł"))
      assert.is_false(with({ "ralt" }, "{"))
      assert.is_false(with({
        "ralt",
        "lshift"
      }, "Ł"))
      assert.is_false(with({ "ralt" }, "l"))
      assert.is_false(with({ "ralt" }, "L"))
      assert.is_false(with({ "ralt" }, "6"))
      assert.is_false(with({ "ralt" }, " "))
    end)
  end)

  describe("on a Compy (Android)", function()
    posing_as("Android")

    it("is true with the right Alt, whatever the text",
        function()
      assert.is_true(with({ "ralt" }, "@"))
      assert.is_true(with({ "ralt" }, "ł"))
      assert.is_true(with({ "ralt" }, "{"))
      assert.is_true(with({
        "ralt",
        "lshift"
      }, "Ł"))
      assert.is_true(with({ "ralt" }, "l"))
      assert.is_true(with({ "ralt" }, " "))
    end)

    it("is false with no modifier, or with Shift alone",
        function()
      assert.is_false(with({ }, "a"))
      assert.is_false(with({ "lshift" }, "A"))
    end)
  end)
end)

-- On a computer a key pressed under AltGr belongs to typing:
-- no Ctrl, Alt or Ctrl+Alt chord fires from it, in the
-- reserved keys, the console, the file editor or a field. On
-- a Compy the right Alt is an Alt, and its chords fire.
describe("a key pressed under AltGr makes no chord #input",
    function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  local WINDOWS_ALTGR = {
    "lctrl",
    "ralt"
  }

  describe("on a computer (Windows)", function()
    posing_as("Windows")

    in_both_orders("in the console, AltGr+L types and keeps "
        .. "the output (Ctrl+L clears it)", function(order)
      K.reset()
      print("KEEP_ME")
      K.frame()
      chord(order, WINDOWS_ALTGR, "l", "ł")
      assert.same("ł", K.console_draft())
      assert.truthy(K.console_text():find("KEEP_ME", 1, true))
    end)

    in_both_orders("in the console, AltGr+R types and starts "
        .. "no program (Ctrl+R does)", function(order)
      K.reset()
      chord(order, WINDOWS_ALTGR, "r", "®")
      assert.same("®", K.console_draft())
      assert.is_falsy(K.cc.run_live)
    end)

    in_both_orders("in the file editor, AltGr+F types its "
        .. "character", function(order)
      K.reset({ ["a.txt"] = "" })
      K.open("a.txt")
      chord(order, WINDOWS_ALTGR, "f", "[")
      assert.same("[", K.draft())
    end)

    in_both_orders("in a project's field, AltGr+V types and "
        .. "pastes nothing", function(order)
      K.reset()
      F.activate_project()
      local widget = F.show_widget({ text = "hey" })
      love.system.setClipboardText("ZZ")
      chord(order, WINDOWS_ALTGR, "v", "@")
      assert.same("hey@", table.concat(widget:get_text(), "\n"))
    end)

    in_both_orders("a project's Ctrl+Alt combo does not fire "
        .. "from AltGr, and its hook gets the key", function(order)
      K.reset()
      local input = F.activate_project()
      local fired, keys = 0, { }
      input.shortcuts.keypressed["ctrl+alt+r"] = function()
        fired = fired + 1
        return true
      end
      input.hooks.keypressed = function(k)
        keys[#keys + 1] = k
      end
      chord(order, WINDOWS_ALTGR, "r", "®")
      assert.same(0, fired)
      assert.truthy(table.is_member(keys, "r"))
    end)

    it("left Ctrl and right Alt with the left Alt too are "
        .. "still Ctrl+Alt+R: a project's shortcut fires", function()
      K.reset()
      local input = F.activate_project()
      local fired = 0
      input.shortcuts.keypressed["ctrl+alt+r"] = function()
        fired = fired + 1
        return true
      end
      chord(ORDERS[2], {
        "lctrl",
        "lalt",
        "ralt"
      }, "r")
      assert.same(1, fired)
    end)
  end)

  --- the console's draft, two lines, the cursor on the second
  local function two_lines()
    K.reset()
    K.type("a")
    K.keys("lshift", "return")
    K.type("b")
  end

  describe("on a computer (Linux)", function()
    posing_as("Linux")

    it("in the console, AltGr+Shift+Up swaps no line "
        .. "(Alt+Shift+Up does)", function()
      two_lines()
      chord(ORDERS[2], { "ralt", "lshift" }, "up")
      assert.same("a\nb", K.console_draft())
      chord(ORDERS[2], { "lalt", "lshift" }, "up")
      assert.same("b\na", K.console_draft())
    end)
  end)

  describe("on a Compy (Android)", function()
    posing_as("Android")

    it("the right Alt with Shift and Up swaps lines, as "
        .. "Alt+Shift+Up does", function()
      two_lines()
      chord(ORDERS[2], { "ralt", "lshift" }, "up")
      assert.same("b\na", K.console_draft())
    end)

    it("left Ctrl with the right Alt and R is Ctrl+Alt+R: a "
        .. "project's shortcut fires", function()
      K.reset()
      local input = F.activate_project()
      local fired = 0
      input.shortcuts.keypressed["ctrl+alt+r"] = function()
        fired = fired + 1
        return true
      end
      chord(ORDERS[2], WINDOWS_ALTGR, "r", "r")
      assert.same(1, fired)
    end)
  end)
end)
