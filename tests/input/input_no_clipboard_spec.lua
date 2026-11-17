-- The system clipboard has left the IDE's text field (the
-- maintainer's ruling of November 14, 2026): no key pastes,
-- copies or cuts through it, in the console, the file editor
-- or a program's input field. Keys only, through the K
-- helper, whose clipboard is the test's own.

local F = require("tests.helpers.input_fixture")
local K = require("tests.helpers.editor_keys")

local CHORDS = {
  ["Ctrl+V"] = { "lctrl", "v" },
  ["Shift+Ins"] = { "lshift", "insert" },
  ["Ctrl+C"] = { "lctrl", "c" },
  ["Ctrl+Ins"] = { "lctrl", "insert" },
  ["Ctrl+X"] = { "lctrl", "x" },
}

describe("no system clipboard in the field #input", function()
  after_each(K.cleanup)

  for label, keys in pairs(CHORDS) do
    it("in a program's field, " .. label .. " changes neither "
        .. "the text nor the clipboard", function()
      K.reset()
      local input = F.activate_project()
      local sent = 0
      input.callbacks.on_text_entered = function()
        sent = sent + 1
      end
      local widget = F.show_widget({ text = "hey" })
      love.system.setClipboardText("ZZ")
      K.keys(unpack(keys))
      assert.same("hey", table.concat(widget:get_text(), "\n"))
      assert.same("ZZ", K.clipboard())
      assert.same(0, sent)
    end)

    it("in the console, " .. label .. " changes neither the "
        .. "line nor the clipboard", function()
      K.reset()
      K.type("abc")
      love.system.setClipboardText("ZZ")
      K.keys(unpack(keys))
      assert.same("abc", K.console_draft())
      assert.same("ZZ", K.clipboard())
    end)
  end

  it("in the file editor, Ctrl+V pastes nothing", function()
    K.reset({ ["notes.txt"] = "" })
    K.open("notes.txt")
    love.system.setClipboardText("ZZ")
    K.keys("lctrl", "v")
    assert.same("", K.draft())
    assert.same("browsing", K.state())
  end)
end)
