-- Run anew is Ctrl+R (the maintainer's ruling of November 14,
-- late): the gate's reserved chord, in the console, the file
-- editor and over a running program; Ctrl+Alt+R does nothing
-- anywhere. The chord's letter, which the device also sends as
-- text before or after the press, reaches no field and no
-- program. Keys through the production gateway (F.session, the
-- K helper).

local F = require("tests.helpers.input_fixture")
local K = require("tests.helpers.editor_keys")

local ORDERS = { "text before the key press",
  "text after the key press" }

--- Press `mods` and `key`, its glyph `glyph` in `order`, and
--- let everything go.
local function chord(order, mods, key, glyph)
  for _, m in ipairs(mods) do F.session.press(m) end
  if glyph and order == ORDERS[1] then F.session.type(glyph) end
  F.session.press(key)
  if glyph and order == ORDERS[2] then F.session.type(glyph) end
  F.session.release(key)
  for i = #mods, 1, -1 do F.session.release(mods[i]) end
  K.frame()
end

local PROGRAM = "function love.update() end\n"

--- Count the gate's restarts, which still run
--- @return function count, function undo
local function counting_restarts()
  local n, orig = 0, K.cc.restart
  K.cc.restart = function(...)
    n = n + 1
    return orig(...)
  end
  return function() return n end,
      function() K.cc.restart = orig end
end

describe("run anew is Ctrl+R #input", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  it("runs the project from the console", function()
    K.reset({ ["main.lua"] = PROGRAM })
    K.keys("lctrl", "r")
    assert.same("running", K.app_state())
    assert.is_true(K.cc.run_live)
  end)

  it("runs the project from the editor, browsing", function()
    K.reset({ ["main.lua"] = PROGRAM })
    K.open()
    K.keys("lctrl", "r")
    assert.same("running", K.app_state())
  end)

  it("runs a running program anew", function()
    K.reset({ ["main.lua"] = PROGRAM })
    K.keys("lctrl", "r")
    local count, undo = counting_restarts()
    K.keys("lctrl", "r")
    undo()
    assert.same(1, count())
    assert.same("running", K.app_state())
  end)

  it("waits while the editor's card shows", function()
    K.reset({ ["main.lua"] = PROGRAM })
    K.open()
    K.hold("f1")
    K.keys("lctrl", "r")
    K.release("f1")
    assert.same("editor", K.app_state())
  end)

  describe("Ctrl+Alt+R does nothing", function()
    it("in the console", function()
      K.reset({ ["main.lua"] = PROGRAM })
      K.type("ab")
      local count, undo = counting_restarts()
      K.keys("lctrl", "lalt", "r")
      undo()
      assert.same(0, count())
      assert.same("ready", K.app_state())
      assert.same("ab", K.console_draft())
    end)

    it("in the editor", function()
      K.reset({ ["main.lua"] = PROGRAM })
      K.open()
      local count, undo = counting_restarts()
      K.keys("lctrl", "lalt", "r")
      undo()
      assert.same(0, count())
      assert.same("editor", K.app_state())
      assert.same("browsing", K.state())
      assert.is_nil(K.message())
    end)

    it("over a running program", function()
      K.reset({ ["main.lua"] = PROGRAM })
      K.keys("lctrl", "r")
      local count, undo = counting_restarts()
      K.keys("lctrl", "lalt", "r")
      undo()
      assert.same(0, count())
      assert.same("running", K.app_state())
    end)
  end)

  describe("its r reaches no one", function()
    for _, order in ipairs(ORDERS) do
      it("not the console's field, " .. order, function()
        K.reset({ ["main.lua"] = PROGRAM })
        K.type("ab")
        K.cc.restart = function() end
        chord(order, { "lctrl" }, "r", "r")
        K.cc.restart = nil
        assert.same("ab", K.console_draft())
      end)

      it("not the editor's field, " .. order, function()
        K.reset({ ["main.lua"] = PROGRAM })
        K.open()
        K.type("ab")
        chord(order, { "lctrl" }, "r", "r")
        assert.same("ab", K.draft())
      end)

      it("not a program, its shortcuts, hook or field, "
          .. order, function()
        K.reset()
        local input = F.activate_project()
        local widget = F.show_widget({ text = "ab" })
        local texts, shortcut = { }, 0
        input.hooks.textinput = function(t)
          texts[#texts + 1] = t
        end
        input.shortcuts.textinput["ctrl+r"] = function()
          shortcut = shortcut + 1
          return true
        end
        -- the restart itself is not this case's: it would
        -- replace the program
        local orig = K.cc.restart
        local restarts = 0
        K.cc.restart = function() restarts = restarts + 1 end
        chord(order, { "lctrl" }, "r", "r")
        K.cc.restart = orig
        assert.same(1, restarts)
        assert.same({ }, texts)
        assert.same(0, shortcut)
        assert.same("ab", table.concat(widget:get_text(), "\n"))
      end)
    end
  end)
end)
