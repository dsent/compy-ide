-- A cut or a move that would leave a Lua file unable to load,
-- or two blocks reading as one statement, is refused with a
-- notice, as Luditor refuses it; no spec item names the case
-- for these keys (IS3.7 names it for a submission). Keys
-- only, through tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")

describe("reuse refusals #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  local function open_file(text)
    K.reset({ ["main.lua"] = text })
    K.open()
  end

  it("a return is not moved above the code after it",
      function()
    local file = "x = 1\nreturn x\n"
    open_file(file)
    K.browse_to(2)
    K.keys("lalt", "up")
    assert.same(file, K.file())
    assert.same(2, K.position())
    assert.same(2, K.blocks())
    assert.is_not_nil(K.message())
  end)

  it("a block is not moved below a return", function()
    local file = "x = 1\nreturn x\n"
    open_file(file)
    K.browse_to(1)
    K.keys("lalt", "down")
    assert.same(file, K.file())
    assert.same(1, K.position())
    assert.is_not_nil(K.message())
  end)

  it("a cut that would join its neighbors is refused",
      function()
    local file = "a = f\ndo end\n(g)()\n"
    open_file(file)
    K.browse_to(2)
    K.keys("lctrl", "delete")
    assert.same(file, K.file())
    assert.same("", K.draft())
    assert.same(3, K.blocks())
    assert.is_not_nil(K.message())
  end)

  it("a refused move leaves nothing to undo", function()
    local file = "x = 1\nreturn x\n"
    open_file(file)
    K.browse_to(2)
    K.keys("lalt", "up")
    K.keys("lctrl", "z")
    assert.same(file, K.file())
  end)
end)
