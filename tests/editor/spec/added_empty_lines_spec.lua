-- The formatter decides a draft's empty lines (the
-- maintainer's ruling of November 14, 2026): the editor puts
-- none back, so a Lua draft lands as the gate leaves it, and
-- IS3.7's "each empty line becomes an empty-line block" holds
-- for a text or Markdown file alone, which has no formatter.
-- Keys only, through tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it
local spec_deviation = marks.spec_deviation

local RULING = "rulings.md: The formatter decides a draft's empty "
    .. "lines"

describe("empty lines in a draft #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  spec_deviation("IS3.7 Preserve accepted Lua: a run of three "
      .. "empty lines between two statements lands as one",
    RULING, function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type_lines({ "a = 1", "", "", "", "b = 2" })
      K.keys("return")
      assert.same("a = 1\n\nb = 2\n", K.file())
      assert.same(3, K.blocks())
    end)

  spec_deviation("IS3.7 Preserve accepted Lua: empty lines at a "
      .. "draft's start and end land as one each", RULING,
    function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.open()
      K.type_lines({ "", "", "a = 1", "", "" })
      K.keys("return")
      assert.same("x = 1\n\na = 1\n\n", K.file())
    end)

  spec_deviation("IS6.4 Submit and retain the field: Shift+Ins "
      .. "keeps the draft as the formatter left it", RULING,
    function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type_lines({ "a=1", "", "", "b=2" })
      K.keys("lshift", "insert")
      assert.same("a = 1\n\nb = 2\n", K.file())
      assert.same("a = 1\n\nb = 2", K.draft())
    end)

  spec_it("IS4.3 Submit an empty draft: Enter on an empty field "
      .. "adds one empty line at a time, and Alt+F leaves "
      .. "one of a run", function()
    K.reset({ ["main.lua"] = "a = 1\nb = 2\n" })
    K.open()
    K.browse_to(2)
    K.keys("return")
    K.keys("return")
    K.keys("return")
    assert.same("a = 1\n\n\n\nb = 2\n", K.file())
    K.keys("lalt", "f")
    assert.same("a = 1\n\nb = 2\n", K.file())
  end)

  for _, ext in ipairs({ "txt", "md" }) do
    spec_it("IS8.2 Submit text: in a ." .. ext .. " file every "
        .. "empty line of a draft lands as typed", function()
      local name = "notes." .. ext
      K.reset({ ["main.lua"] = "", [name] = "" })
      K.open(name)
      K.type_lines({ "", "a", "", "", "", "b", "", "" })
      K.keys("return")
      assert.same("\na\n\n\n\nb\n\n\n", K.file(name))
    end)
  end
end)
