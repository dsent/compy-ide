-- The eighth review round's findings, each as the keys that
-- showed it. Keys only, through tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it

describe("round eight #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  spec_it("IS3.4 Locate a syntax failure: a string the lexer "
      .. "cannot read is red from its opening quote, and Enter "
      .. "puts the cursor there", function()
    K.reset({ ["main.lua"] = "a = 1\n" })
    K.open()
    K.type('x = "\\999" y = 1')
    local _, red = K.field_highlight()
    assert.same({ 1, 5 }, red)
    K.keys("return")
    assert.same({ 1, 5 }, { K.cursor() })
    assert.same("error", K.message_kind())
    assert.same("a = 1\n", K.file())
  end)

  spec_it("IS1.5 Follow a file reference: a require with no "
      .. "name written out takes nothing from the other "
      .. "references of the file", function()
    K.reset({
      ["main.lua"] = "require()\nlocal m = require(\"mod\")\n"
          .. "function f()\nend\n",
      ["mod.lua"] = "x = 1\n",
    })
    K.open()
    K.browse_to(2)
    K.keys("lctrl", "j")
    assert.same("mod.lua", K.file_name())
  end)

  spec_it("IS3.16 Show the key card: Enter pressed under the "
      .. "console's card does not run the line once F1 is "
      .. "released", function()
    K.reset({ ["main.lua"] = "a = 1\n" })
    K.type("saw_repeat = true")
    K.hold("f1")
    assert.is_not_nil(K.key_card())
    K.hold("return")
    K.release("f1")
    K.repeat_key("return")
    K.release("return")
    assert.same("saw_repeat = true", K.console_draft())
    assert.is_nil(K.cc:get_project_env().saw_repeat)
  end)

  -- the third reviewer's ready tests (A1, A2): the language
  -- layer skips a `#!` first line alone
  spec_it("IS3.3 Check Lua submission: a draft that opens with "
      .. "a # line loses no line", function()
    K.reset({ ["main.lua"] = "a = 1\n" })
    K.open()
    K.type_lines({ "#speed = 5", "speed = 10" })
    K.keys("return")
    assert.same("a = 1\n", K.file())
    assert.same("#speed = 5\nspeed = 10", K.draft())
    assert.is_truthy(K.message())
  end)

  spec_it("FR3.1 Preserve file structure: formatting keeps a # "
      .. "line under an empty line", function()
    K.reset({ ["main.lua"] = "\n#x = 1\ny=2\n" })
    K.open()
    K.keys("lalt", "f")
    assert.is_truthy(K.file():find("#x = 1", 1, true))
  end)

  spec_it("IS3.4 Locate a syntax failure: a lone name after a "
      .. "space is a syntax error, the cursor before it",
    function()
      K.reset({ ["main.lua"] = "a = 1\n" })
      K.open()
      K.type(" x")
      K.keys("return")
      assert.same(" x", K.draft())
      assert.same("error", K.message_kind())
      assert.same({ 1, 2 }, { K.cursor() })
    end)

  spec_it("IS3.4 Locate a syntax failure: the cursor goes before "
      .. "a name under an empty line", function()
    K.reset({ ["main.lua"] = "a = 1\n" })
    K.open()
    K.keys("lshift", "return")
    K.type("hello")
    K.keys("return")
    assert.same({ 2, 1 }, { K.cursor() })
  end)

  spec_it("IS3.4 Locate a syntax failure: a lone value after a "
      .. "space is no line the console runs", function()
    K.reset({ ["main.lua"] = "a = 1\n" })
    K.type(" 2")
    K.keys("return")
    assert.same(" 2", K.console_draft())
  end)

  spec_it("IS3.5 Continue input on a new line: a draft that opens "
      .. "a long comment and does not close it goes on, on a new "
      .. "line", function()
    K.reset({ ["main.lua"] = "a = 1\n" })
    K.open()
    K.type_lines({ "--[[ note", "more" })
    K.keys("return")
    assert.same("--[[ note\nmore\n", K.draft())
    assert.is_nil(K.message())
    assert.same("a = 1\n", K.file())
  end)
end)
