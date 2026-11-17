-- A `#!` first line is the language layer's matter (the
-- maintainer's ruling of November 14, 2026): the editor has
-- no rule of its own for it. What happens to it falls out of
-- the parser, which skips a `#!` first line and refuses a `#`
-- line anywhere else; the formatter, which keeps a `#!` first
-- line; and the editor's rule that a change leaves the file
-- loadable ("Lua could not run the file after this").
-- Keys only, through tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it

local TEXT = "#!/usr/bin/lua\nx = 1\n"
local NO_RUN = "Lua could not run the file after this"

describe("a #! first line #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  before_each(function()
    K.reset({ ["main.lua"] = TEXT })
    K.open()
  end)

  spec_it("IS5.1 Begin a replacement: Edit loads a #! first line, "
      .. "and Enter takes it back unchanged or with another "
      .. "interpreter", function()
    K.browse_to(1)
    K.keys("f2")
    assert.same("replacing", K.state())
    assert.same("#!/usr/bin/lua", K.draft())
    K.keys("return")
    assert.same("browsing", K.state())
    assert.same(TEXT, K.file())
    K.browse_to(1)
    K.keys("f2")
    for _ = 1, #"lua" do K.keys("backspace") end
    K.type("luajit")
    K.keys("return")
    assert.same("browsing", K.state())
    assert.same("#!/usr/bin/luajit\nx = 1\n", K.file())
  end)

  spec_it("IS3.3 Check Lua submission: a #! line entered below "
      .. "the first line is refused, the draft kept", function()
    -- alone in the draft: it would stop the file loading
    K.type("#!/usr/bin/lua")
    K.keys("return")
    assert.same(TEXT, K.file())
    assert.same("#!/usr/bin/lua", K.draft())
    assert.truthy((K.message() or ""):find(NO_RUN, 1, true))
    -- below the draft's first line: the parser refuses it
    K.keys("escape")
    K.type_lines({ "y = 2", "#!/usr/bin/lua" })
    K.keys("return")
    assert.same(TEXT, K.file())
    assert.same("y = 2\n#!/usr/bin/lua", K.draft())
    assert.same("error", K.message_kind())
  end)

  spec_it("IS6.2 Cut a block: the #! first line is cut, and "
      .. "Ctrl+Z puts it back", function()
    K.browse_to(1)
    K.keys("lctrl", "delete")
    assert.same("x = 1\n", K.file())
    assert.same("#!/usr/bin/lua", K.draft())
    K.keys("lctrl", "z")
    K.keys("lctrl", "z")
    assert.same(TEXT, K.file())
  end)

  spec_it("IS6.5 Move a block: the #! first line does not move "
      .. "down, and no block moves above it", function()
    K.browse_to(1)
    K.keys("lalt", "down")
    assert.same(TEXT, K.file())
    assert.truthy((K.message() or ""):find(NO_RUN, 1, true))
    K.browse_to(2)
    K.keys("lalt", "up")
    assert.same(TEXT, K.file())
    assert.truthy((K.message() or ""):find(NO_RUN, 1, true))
  end)

  spec_it("IS4.1 Insert before a block: text entered "
      .. "above a #! first line is refused, the draft kept",
    function()
      K.browse_to(1)
      K.type("y = 2")
      K.keys("return")
      assert.same(TEXT, K.file())
      assert.same("y = 2", K.draft())
      assert.truthy((K.message() or ""):find(NO_RUN, 1, true))
    end)

  spec_it("FR3.1 Preserve file structure: Alt+F and "
      .. "tidy() keep a #! first line", function()
    K.reset({ ["main.lua"] = "#!/usr/bin/lua\nx=1\n" })
    K.open()
    K.keys("lalt", "f")
    assert.same(TEXT, K.file())
    K.reset({ ["main.lua"] = "#!/usr/bin/lua\nx=1\n" })
    K.type('tidy("main.lua")')
    K.keys("return")
    assert.same(TEXT, K.file())
  end)

  spec_it("IS1.2 Admit or refuse a file: in a file that does "
      .. "not load, a #! line lands anywhere", function()
    K.reset({ ["main.lua"] = "x = = 1\ny = 2\n" })
    K.open()
    K.browse_to(2)
    K.type("#!/usr/bin/lua")
    K.keys("return")
    assert.same("x = = 1\n#!/usr/bin/lua\ny = 2\n", K.file())
  end)
end)
