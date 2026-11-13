-- Edge defects fixed in code that stays through the rework,
-- where no spec item covers the key (spec items have their own
-- tests under tests/editor/spec). Keys only, through
-- tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")

local FILE = "x = 1\ny = 2\nz = 3\n"

describe("editor defects #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  before_each(function()
    K.reset({ ["main.lua"] = FILE })
    K.open()
  end)

  it("Alt+End scrolls the view to the end of the file",
      function()
    local t = { }
    for i = 1, 40 do
      t[i] = "v" .. i .. " = " .. i
    end
    K.reset({ ["main.lua"] = table.concat(t, "\n") .. "\n" })
    K.open()
    K.browse_to(1)
    K.keys("lalt", "end")
    local rows = K.view_rows()
    assert.same("v40 = 40", rows[#rows])
    assert.is_true(K.in_view(40))
    assert.same(1, K.position())
  end)

  it("Shift+Delete in browsing removes one block, not two",
      function()
    K.browse_to(2)
    K.keys("lshift", "delete")
    assert.same("x = 1\nz = 3\n", K.file())
    assert.same(2, K.blocks())
  end)
end)
