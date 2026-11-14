-- The maintainer's rulings of November 14, 2026 on the
-- editor's own keys: PgDn and PgUp browse a page at a time,
-- the block that comes into view at the view's edge becoming
-- the browsing position; Alt+F says why it refuses;
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

    describe("Alt+F", function()
      for _, name in ipairs({ "notes.txt", "notes.md" }) do
        spec_it("IS3.14 Explain a refusal: Alt+F in "
            .. name .. " says the file has nothing to format, "
            .. "and the next key acts", function()
          K.reset({ [name] = "a  b\n" })
          K.open(name)
          K.keys("lalt", "f")
          assert.same("The file has nothing to format.",
            K.message())
          assert.same("a  b\n", K.file(name))
          K.type("c")
          assert.is_nil(K.message())
          assert.same("c", K.draft())
        end)
      end

      spec_it("IS3.14 Explain a refusal: Alt+F during an "
          .. "edit says to finish it, and changes nothing",
        function()
          K.reset({ ["main.lua"] = "x=1\n" })
          K.open()
          K.type("y = 2")
          K.keys("lalt", "f")
          assert.truthy((K.message() or ""):find("Finish", 1, true))
          assert.same("x=1\n", K.file())
          assert.same("y = 2", K.draft())
          K.keys("escape")
          K.browse_to(1)
          K.keys("f2")
          K.keys("lalt", "f")
          assert.truthy((K.message() or ""):find("Finish", 1, true))
          assert.same("x=1\n", K.file())
          assert.same(1, K.target())
        end)
    end)

    -- with an empty field Home and End move through the file
    -- (PR #28, D-PAGING; the maintainer's ruling of November
    -- 14, 2026), and in a draft they are the field's
    describe("Home and End", function()
      spec_it("IS2.1 Browse blocks: with an empty field Home "
          .. "browses to the first block and End to the end "
          .. "position", function()
        K.reset({ ["notes.txt"] = lines_file(60) })
        K.open("notes.txt")
        K.browse_to(30)
        K.keys("home")
        assert.same(1, K.position())
        assert.same(1, (shown()))
        K.keys("end")
        assert.same("end", K.position())
        assert.same(60, select(2, shown()))
        assert.same("", K.draft())
      end)

      spec_it("IS2.1 Browse blocks: a held Home or End acts once, "
          .. "and the field takes no text from it", function()
        K.reset({ ["notes.txt"] = lines_file(60) })
        K.open("notes.txt")
        K.browse_to(30)
        -- browsed away while the key is held, so that a repeat
        -- that acted would bring the position back
        K.hold("home")
        assert.same(1, K.position())
        K.keys("lctrl", "down")
        K.repeat_key("home")
        K.release("home")
        assert.same(2, K.position())
        K.hold("end")
        assert.same("end", K.position())
        K.keys("lctrl", "up")
        K.repeat_key("end")
        K.release("end")
        assert.same(60, K.position())
        assert.same("", K.draft())
        assert.same("browsing", K.state())
      end)

      spec_it("IS3.16 Show the key card: with text in the field "
          .. "the card gives Home and End no row, since they move "
          .. "the cursor there; with none it lists them", function()
        K.reset({ ["notes.txt"] = lines_file(60) })
        K.open("notes.txt")
        local function card_text()
          K.hold("f1")
          local card = K.key_card()
          K.release("f1")
          assert.is_not_nil(card)
          return table.concat(card, "\n")
        end
        assert.truthy(card_text():find("file start/end", 1, true))
        K.type("abcd")
        assert.is_nil(card_text():find("file start/end", 1, true))
        -- Ctrl+Home/End, to the text's ends, stays
        assert.is_nil(card_text():find("[^+]Home/End "))
        assert.truthy(card_text():find("Ctrl+Home/End", 1, true))
      end)

      spec_it("IS3.8 Position the text cursor: in a draft Home "
          .. "and End go to the ends of the cursor's row, and the "
          .. "position stays", function()
        K.reset({ ["notes.txt"] = lines_file(60) })
        K.open("notes.txt")
        K.browse_to(30)
        K.type("abc")
        K.keys("home")
        assert.same({ 1, 1 }, { K.cursor() })
        assert.same(30, K.position())
        K.keys("end")
        assert.same({ 1, 4 }, { K.cursor() })
        assert.same(30, K.position())
      end)
    end)

    describe("Ctrl+G", function()
      spec_it("IS2.3 Browse during edit: while replacing, Ctrl+G "
          .. "browses to the replacement target and shows it; the "
          .. "draft, its cursor and the target stay", function()
        K.reset({ ["notes.txt"] = lines_file(60) })
        K.open("notes.txt")
        K.browse_to(30)
        K.keys("f2")
        K.type("x")
        K.browse_to(1)
        assert.is_false(K.in_view(30))
        local draft, cursor = K.draft(), { K.cursor() }
        K.keys("lctrl", "g")
        assert.same(30, K.position())
        assert.is_true(K.in_view(30))
        assert.same("replacing", K.state())
        assert.same(30, K.target())
        assert.same(draft, K.draft())
        assert.same(cursor, { K.cursor() })
        assert.is_nil(K.message())
      end)

      spec_it("IS2.3 Browse during edit: on the target already, "
          .. "Ctrl+G changes nothing on the screen", function()
        K.reset({ ["notes.txt"] = lines_file(60) })
        K.open("notes.txt")
        K.browse_to(30)
        K.keys("f2")
        local before = K.screen()
        K.keys("lctrl", "g")
        assert.same(before, K.screen())
      end)

      for _, st in ipairs({ "browsing", "inserting" }) do
        spec_it("IS2.3 Browse during edit: while " .. st .. ", "
            .. "Ctrl+G does nothing and says nothing", function()
          K.reset({ ["notes.txt"] = lines_file(60) })
          K.open("notes.txt")
          K.browse_to(30)
          if st == "inserting" then K.type("ab") end
          K.browse_to(1)
          assert.same(st, K.state())
          local before = { K.position(), K.view_rows(), K.draft(),
            { K.cursor() }, K.app_state() }
          K.keys("lctrl", "g")
          assert.same(before, { K.position(), K.view_rows(),
            K.draft(), { K.cursor() }, K.app_state() })
          assert.is_nil(K.message())
        end)
      end
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
        -- the file is formatted with Alt+F, and Ctrl+F is kept
        -- for a search to come
        ["Ctrl+Shift+F"] = { "lctrl", "lshift", "f" },
        ["Ctrl+F"] = { "lctrl", "f" },
        ["Ctrl+D"] = { "lctrl", "d" },
        ["Shift+Delete"] = { "lshift", "delete" },
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
