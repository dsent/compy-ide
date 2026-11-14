-- The maintainer's rulings of November 14, 2026 on the
-- editor's own keys: PgDn and PgUp browse a page at a time,
-- the block that comes into view at the view's edge becoming
-- the browsing position; Ctrl+Shift+F says why it refuses;
-- Ctrl+Shift+S and the Alt look-around keys are gone. Keys
-- only, through tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it

--- a text file of `n` lines, "line 1" to "line n": one block
--- a line
local function lines_file(n)
  local t = { }
  for i = 1, n do t[i] = "line " .. i end
  return table.concat(t, "\n") .. "\n"
end

--- the number of the line a view row shows
local function line_no(row)
  return tonumber(row:match("^line (%d+)"))
end

--- the first and last lines the view shows
local function shown()
  local rows = K.view_rows()
  return line_no(rows[1]), line_no(rows[#rows])
end

--- a Lua file of `n` three-line functions
local function functions_file(n)
  local t = { }
  for i = 1, n do
    t[#t + 1] = "function f" .. i .. "()\n  x = " .. i .. "\nend"
  end
  return table.concat(t, "\n") .. "\n"
end

--- a Lua function of `n` lines in all
local function tall(name, n)
  local t = { "function " .. name .. "()" }
  for i = 1, n - 2 do t[#t + 1] = "  v" .. i .. " = " .. i end
  t[#t + 1] = "end"
  return table.concat(t, "\n")
end

describe("paging, formatting, removed keys #editor #spec",
  function()
    after_each(K.cleanup)

    describe("PgDn and PgUp", function()
      spec_it("IS2.1 Browse blocks: PgDn browses to the first "
          .. "block not wholly visible below and shows it at the "
          .. "view's top", function()
        K.reset({ ["notes.txt"] = lines_file(60) })
        K.open("notes.txt")
        K.browse_to(1)
        local _, last = shown()
        K.keys("pagedown")
        assert.same(last + 1, K.position())
        assert.same(last + 1, (shown()))
        assert.is_true(K.in_view(last + 1))
      end)

      spec_it("IS2.1 Browse blocks: PgUp browses to the last "
          .. "block not wholly visible above and shows it at the "
          .. "view's bottom", function()
        K.reset({ ["notes.txt"] = lines_file(60) })
        K.open("notes.txt")
        K.browse_to(40)
        local first = shown()
        assert.is_true(1 < first)
        K.keys("pageup")
        assert.same(first - 1, K.position())
        assert.same(first - 1, select(2, shown()))
      end)

      spec_it("IS2.1 Browse blocks: after PgUp, PgDn brings the "
          .. "block just below the view to its top", function()
        K.reset({ ["notes.txt"] = lines_file(60) })
        K.open("notes.txt")
        K.keys("pageup")
        local p = K.position()
        assert.same(p, select(2, shown()))
        K.keys("pagedown")
        assert.same(p + 1, K.position())
        assert.same(p + 1, (shown()))
      end)

      spec_it("IS2.1 Browse blocks: a block cut off at the "
          .. "view's bottom is the one PgDn brings to the top",
        function()
          K.reset({ ["main.lua"] = functions_file(12) })
          K.open()
          K.browse_to(1)
          local cut
          for b = 1, 12 do
            local rows, n = K.rows_shown(b)
            if n < rows then cut = b; break end
          end
          assert.is_not_nil(cut)
          K.keys("pagedown")
          assert.same(cut, K.position())
          assert.same("function f" .. cut .. "()", K.view_rows()[1])
        end)

      spec_it("IS2.1 Browse blocks: at the file's end PgDn goes "
          .. "to the end position, at its start PgUp to the first "
          .. "block", function()
        K.reset({ ["notes.txt"] = lines_file(5) })
        K.open("notes.txt")
        K.browse_to(2)
        K.keys("pagedown")
        assert.same("end", K.position())
        K.keys("pageup")
        assert.same(1, K.position())
        K.keys("pageup")
        assert.same(1, K.position())
      end)

      spec_it("IS2.2 Keep the viewed block visible: a block taller "
          .. "than the view is paged through, the browsing position "
          .. "on it, before PgDn leaves it", function()
        K.reset({ ["main.lua"] = "a = 1\n" .. tall("big", 40)
          .. "\nb = 2\n" })
        K.open()
        -- from above: the block shows from its first row
        K.browse_to(1)
        K.keys("lctrl", "down")
        assert.same("function big()", K.view_rows()[1])
        local rows, n = K.rows_shown(2)
        assert.is_true(n < rows)
        local pages = 0
        while K.view_rows()[#K.view_rows()] ~= "end" do
          K.keys("pagedown")
          pages = pages + 1
          assert.same(2, K.position())
          assert.is_true(pages < 10)
        end
        assert.is_true(1 < pages)
        assert.same("end", K.view_rows()[#K.view_rows()])
        K.keys("pagedown")
        assert.same(3, K.position())
        -- back up: the tall block shown to its last row, then
        -- paged through upward
        K.keys("pageup")
        assert.same(2, K.position())
        assert.same("end", K.view_rows()[#K.view_rows()])
        local up = 0
        while K.view_rows()[1] ~= "function big()" do
          K.keys("pageup")
          up = up + 1
          assert.same(2, K.position())
          assert.is_true(up < 10)
        end
        K.keys("pageup")
        assert.same(1, K.position())
      end)

      spec_it("IS2.3 Browse during a replacement: PgDn and PgUp "
          .. "leave the draft and the target", function()
        K.reset({ ["notes.txt"] = lines_file(60) })
        K.open("notes.txt")
        K.browse_to(1)
        K.keys("f2")
        K.type("!")
        K.keys("pagedown")
        assert.same(1, K.target())
        assert.same("line 1!", K.draft())
        assert.are_not.same(1, K.position())
        K.keys("pageup")
        assert.same(1, K.target())
        assert.same("line 1!", K.draft())
      end)

      spec_it("IS2.1 Browse blocks: a held PgDn pages per repeat",
        function()
          K.reset({ ["notes.txt"] = lines_file(80) })
          K.open("notes.txt")
          K.browse_to(1)
          local _, last = shown()
          K.hold("pagedown")
          local once = K.position()
          K.repeat_key("pagedown")
          K.release("pagedown")
          assert.same(last + 1, once)
          assert.is_true(once < K.position())
        end)
    end)

    describe("Ctrl+Shift+F", function()
      for _, name in ipairs({ "notes.txt", "notes.md" }) do
        spec_it("IS3.14 Explain a refusal: Ctrl+Shift+F in "
            .. name .. " says the file has nothing to format, "
            .. "and the next key acts", function()
          K.reset({ [name] = "a  b\n" })
          K.open(name)
          K.keys("lctrl", "lshift", "f")
          assert.same("The file has nothing to format.",
            K.message())
          assert.same("a  b\n", K.file(name))
          K.type("c")
          assert.is_nil(K.message())
          assert.same("c", K.draft())
        end)
      end

      spec_it("IS3.14 Explain a refusal: Ctrl+Shift+F during an "
          .. "edit says to finish it, and changes nothing",
        function()
          K.reset({ ["main.lua"] = "x=1\n" })
          K.open()
          K.type("y = 2")
          K.keys("lctrl", "lshift", "f")
          assert.truthy((K.message() or ""):find("Finish", 1, true))
          assert.same("x=1\n", K.file())
          assert.same("y = 2", K.draft())
          K.keys("escape")
          K.browse_to(1)
          K.keys("f2")
          K.keys("lctrl", "lshift", "f")
          assert.truthy((K.message() or ""):find("Finish", 1, true))
          assert.same("x=1\n", K.file())
          assert.same(1, K.target())
        end)
    end)

    describe("removed keys", function()
      for label, keys in pairs({
        ["Alt+PgUp"] = { "lalt", "pageup" },
        ["Alt+PgDn"] = { "lalt", "pagedown" },
        ["Alt+Left"] = { "lalt", "left" },
        ["Alt+Right"] = { "lalt", "right" },
        ["Alt+Home"] = { "lalt", "home" },
        ["Alt+End"] = { "lalt", "end" },
        ["Ctrl+Shift+S"] = { "lctrl", "lshift", "s" },
      }) do
        spec_it("IS2.1 Browse blocks: " .. label .. " does "
            .. "nothing", function()
          K.reset({ ["notes.txt"] = lines_file(60) })
          K.open("notes.txt")
          K.browse_to(30)
          local before = { K.position(), K.view_rows(),
            K.app_state() }
          K.keys(unpack(keys))
          assert.same(before, { K.position(), K.view_rows(),
            K.app_state() })
        end)
      end
    end)
  end)
