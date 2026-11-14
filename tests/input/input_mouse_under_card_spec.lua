-- The mouse is ignored while the key card shows (the
-- maintainer's ruling of November 14, late): in the file
-- editor, in the console, and over a program behind the
-- console's card, no press, release, move, wheel or derived
-- click does anything. A button's release goes where its press
-- went, so that no route is left with half a click. Events
-- through the production gateway (F.session, the K helper).

local F = require("tests.helpers.input_fixture")
local K = require("tests.helpers.editor_keys")
local Layout = require("view.layout")

--- the point of column `col` on the field's last row
local function on_field(col)
  local v = F.cfg.view
  local bottom = love.graphics.getHeight() - Layout(v).bottom
  return v.fw * (col - 1 + 0.2), bottom - v.fh * 0.5
end

--- every kind of mouse event, at the field's first column
local function every_mouse_event()
  local x, y = on_field(1)
  F.session.mousepressed(x, y, 1, false, 1)
  F.session.mousemoved(x + 40, y, 40, 0, false)
  F.session.mousereleased(x + 40, y, 1, false, 1)
  F.session.mousepressed(x, y, 1, false, 1)
  F.session.mousereleased(x, y, 1, false, 1)
  love.handlers.wheelmoved(0, 1)
  -- the derived single click, after its pairing time
  K.frame(0.5)
end

local function click(col)
  local x, y = on_field(col)
  F.session.mousepressed(x, y, 1, false, 1)
  F.session.mousereleased(x, y, 1, false, 1)
  K.frame()
end

--- A program that idles behind the console with a hook for
--- every pointer event, recording them in LOG
local IDLES = table.concat({
  "LOG = {}",
  "local function note(name)",
  "  return function() LOG[#LOG + 1] = name end",
  "end",
  "for _, n in ipairs({ 'mousepressed', 'mousereleased',",
  "  'mousemoved', 'wheelmoved', 'singleclick',",
  "  'doubleclick' }) do",
  "  compy.input.hooks[n] = note(n)",
  "end",
}, "\n") .. "\n"

local function log()
  return K.cc:get_project_env().LOG
end

describe("the mouse under the key card #input", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(function()
    K.cc.cfg.editor = nil
    K.cleanup()
  end)

  it("moves no cursor in the file editor's draft", function()
    K.reset({ ["notes.txt"] = "" })
    K.cc.cfg.editor = { mouse_enabled = true }
    K.open("notes.txt")
    K.type("abcd")
    K.hold("f1")
    assert.is_not_nil(K.key_card())
    every_mouse_event()
    K.release("f1")
    assert.same({ 1, 5 }, { K.cursor() })
    assert.same("abcd", K.draft())
    assert.is_nil(K.message())
    -- the card away, a click places the cursor again
    click(2)
    assert.same({ 1, 2 }, { K.cursor() })
  end)

  it("moves no cursor in the console's draft", function()
    K.reset()
    K.type("abcd")
    K.hold("f1")
    assert.is_not_nil(K.key_card())
    every_mouse_event()
    K.release("f1")
    assert.same({ 1, 5 }, { K.cc.input:get_cursor_pos() })
    click(2)
    assert.same({ 1, 2 }, { K.cc.input:get_cursor_pos() })
  end)

  it("reaches no program idling behind the console's card",
    function()
      K.reset({ ["main.lua"] = IDLES })
      K.keys("lctrl", "r")
      assert.same("ready", K.app_state())
      assert.is_true(K.cc.run_live)
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      every_mouse_event()
      K.release("f1")
      assert.same({ }, log())
      -- the card away, the program has the mouse again
      click(3)
      K.frame(0.5)
      assert.same({ "mousepressed", "mousereleased",
        "singleclick" }, log())
    end)

  it("reaches no paused program behind the console's card",
    function()
      K.reset({ ["main.lua"] = IDLES
          .. "function love.update() end\n" })
      K.keys("lctrl", "r")
      assert.same("running", K.app_state())
      K.keys("lctrl", "pause")
      K.frame()
      -- the fixture's graphics take no screenshot, whose
      -- callback finishes the pause on the device
      if K.app_state() == "snapshot" then K.cc:suspend() end
      assert.same("inspect", K.app_state())
      K.type("ab")
      local before = { K.cc.input:get_cursor_pos() }
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      every_mouse_event()
      K.release("f1")
      assert.same({ }, log())
      assert.same(before, { K.cc.input:get_cursor_pos() })
    end)

  describe("leaves no half click", function()
    it("a press under the card holds back its release after "
        .. "the card", function()
      K.reset({ ["main.lua"] = IDLES })
      K.keys("lctrl", "r")
      local x, y = on_field(1)
      K.hold("f1")
      F.session.mousepressed(x, y, 1, false, 1)
      K.release("f1")
      F.session.mousereleased(x, y, 1, false, 1)
      K.frame(0.5)
      assert.same({ }, log())
    end)

    it("a press before the card gets its release under it",
      function()
        K.reset({ ["main.lua"] = IDLES })
        K.keys("lctrl", "r")
        local x, y = on_field(1)
        F.session.mousepressed(x, y, 1, false, 1)
        K.hold("f1")
        assert.is_not_nil(K.key_card())
        F.session.mousereleased(x, y, 1, false, 1)
        K.release("f1")
        assert.same({ "mousepressed", "mousereleased" },
          { log()[1], log()[2] })
      end)
  end)
end)
