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
      .. "references and definitions of the file", function()
    K.reset({
      ["main.lua"] = "require()\nlocal m = require(\"mod\")\n"
          .. "function f()\nend\n",
      ["mod.lua"] = "x = 1\n",
    })
    K.open()
    -- the definition is found by search
    K.keys("lctrl", "f")
    K.type("f")
    K.keys("return")
    assert.same(3, K.position())
    -- and the reference is followed
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
end)
