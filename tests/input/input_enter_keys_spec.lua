-- The four Enter keys in each text-entry context: the console,
-- the file editor and a program's input field. Shift+Enter
-- and Alt+Enter break the line and submit nothing (the editor
-- principles' IS3.15); a bare Enter submits. Ctrl+Enter is
-- pinned as it is built: it submits in the console and in a
-- program's field, and does nothing in the file editor.

local K = require("tests.helpers.editor_keys")
local F = require("tests.helpers.input_fixture")

describe("the Enter keys in each context #input", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("in the console", function()
    -- each case types its own number: the project's globals
    -- outlive a case
    local n, line = 0, nil

    before_each(function()
      K.reset()
      n = n + 1
      line = "ran = " .. n
      K.type(line)
    end)

    --- the line ran when its assignment reached the project
    local function ran()
      return K.cc:get_project_env().ran == n
    end

    it("Enter runs the line", function()
      K.keys("return")
      assert.is_true(ran())
      assert.same("", K.console_draft())
    end)

    it("Shift+Enter breaks the line and runs nothing",
        function()
      K.keys("lshift", "return")
      assert.is_false(ran())
      assert.same(line .. "\n", K.console_draft())
    end)

    it("Alt+Enter breaks the line and runs nothing", function()
      K.keys("lalt", "return")
      assert.is_false(ran())
      assert.same(line .. "\n", K.console_draft())
    end)

    it("Ctrl+Enter runs the line", function()
      K.keys("lctrl", "return")
      assert.is_true(ran())
      assert.same("", K.console_draft())
    end)
  end)

  describe("in the file editor", function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.open()
      K.browse_to_end()
      K.type("y = 2")
    end)

    it("Enter submits the draft", function()
      K.keys("return")
      assert.same("x = 1\ny = 2\n", K.file())
      assert.same("", K.draft())
    end)

    it("Shift+Enter breaks the line and submits nothing",
        function()
      K.keys("lshift", "return")
      assert.same("x = 1\n", K.file())
      assert.same("y = 2\n", K.draft())
    end)

    it("Alt+Enter breaks the line and submits nothing",
        function()
      K.keys("lalt", "return")
      assert.same("x = 1\n", K.file())
      assert.same("y = 2\n", K.draft())
    end)

    it("Ctrl+Enter does nothing", function()
      K.keys("lctrl", "return")
      assert.same("x = 1\n", K.file())
      assert.same("y = 2", K.draft())
    end)
  end)

  describe("in a program's input field", function()
    local widget, got

    before_each(function()
      K.reset()
      F.activate_project()
      got = nil
      widget = F.show_widget({
        text = "hi",
        on_text_entered = function(t)
          got = t
        end
      })
    end)

    local function field()
      return table.concat(widget:get_text(), "\n")
    end

    it("Enter submits the text", function()
      K.keys("return")
      assert.same("hi", got)
    end)

    it("Shift+Enter breaks the line and submits nothing",
        function()
      K.keys("lshift", "return")
      assert.is_nil(got)
      assert.same("hi\n", field())
    end)

    it("Alt+Enter breaks the line and submits nothing",
        function()
      K.keys("lalt", "return")
      assert.is_nil(got)
      assert.same("hi\n", field())
    end)

    it("Ctrl+Enter submits the text", function()
      K.keys("lctrl", "return")
      assert.same("hi", got)
    end)
  end)
end)
