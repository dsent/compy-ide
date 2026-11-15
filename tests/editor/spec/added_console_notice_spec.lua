-- The console's notice band is the field's, as the editor's
-- is (the maintainer's rulings of November 15, 2026): directly
-- above the status line, over the output's last rows, which do
-- not move, it says why a line was not taken, and in orange a
-- hint that is no error; what a line that ran did, its error
-- or a command's refusal included, is said in the output. The
-- field keeps the draft and its cursor, and the next key
-- dismisses the message and still acts. Keys only, through
-- tests/helpers/editor_keys.lua, and the screen through its
-- real draw functions (K.screen).

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it

--- a band message too long for its rows, set as the field's
--- message (no line the console refuses says as much)
local function long_message(msg)
  K.cc.input:set_error({ msg })
end

--- a program that an error pauses; its handler goes as it
--- fails
local PAUSES = [[
function love.update()
  love.update = nil
  error('x')
end
]]

local function fh()
  return K.cc.view.cfg.view.fh
end

local function colors()
  return K.cc.view.cfg.view.colors
end

local function same_colour(a, b)
  for i = 1, 3 do
    if 0.001 <= math.abs((a[i] or 0) - (b[i] or 0)) then
      return false
    end
  end
  return true
end

--- The band's rows on the screen `s`: drawn last, one text
--- per row of the message shown.
local function band(s)
  local rows = K.cc.view.input:notice_rows() or { }
  local out = { }
  for i = 1, #rows do
    out[i] = s.texts[#s.texts - #rows + i]
    assert(out[i] and out[i].text == rows[i],
      "the band's rows are drawn last")
  end
  return out
end

--- The texts of the band's rows, joined by a space
local function band_text(s)
  local out = { }
  for i, r in ipairs(band(s)) do out[i] = r.text end
  return table.concat(out, " ")
end

--- What the field draws, its status line included
local function field(s)
  return K.screen_text(s.field)
end

--- The field's text drawn in the error colour, under its
--- status line
local function red(s)
  local out = { }
  for _, t in ipairs(s.field) do
    if same_colour(t.colour or { }, colors().input.error)
        and fh() <= t.y then
      out[#out + 1] = t.text
    end
  end
  return table.concat(out)
end

local function cursor()
  return { K.cc.input.model:get_cursor_pos() }
end

--- Some output, so that the band has rows to cover
local function output()
  K.type('for i = 1, 20 do print("row " .. i) end')
  K.keys("return")
end

describe("the console's errors in the notice band #editor #spec",
  function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("what shows", function()
    spec_it("IS3.4 Locate a syntax failure: in the console the "
        .. "parser's message shows in the band above the status "
        .. "line, and the field keeps the draft, red from the "
        .. "failure, the cursor before it", function()
      K.reset()
      output()
      K.type("x = = 1")
      local before = K.screen()
      K.keys("return")
      local s = K.screen()
      local rows = band(s)
      assert.truthy(band_text(s):find("expression", 1, true))
      assert.same("error", K.cc.input:message_kind())
      assert.same(s.field_y - fh(), rows[#rows].y)
      for _, r in ipairs(rows) do
        assert.is_true(same_colour(colors().input.notice.error,
          r.colour))
      end
      -- no header, and nothing of the message in the field
      assert.is_nil(K.screen_text(s.texts):find("Errors:", 1,
        true))
      assert.is_nil(field(s):find("expression", 1, true))
      -- the field and the status line where they were, the
      -- draft in it
      assert.same(before.field_y, s.field_y)
      assert.same(before.field_rows, s.field_rows)
      assert.truthy(field(s):find("x = = 1", 1, true))
      assert.same({ 1, 5 }, cursor())
      assert.same("= 1", red(s))
    end)

    spec_it("NFR4.3 Understandable submission outcome: a "
        .. "console line that fails while it runs says so in the "
        .. "output, in red, and not in the band, the line kept in "
        .. "the field", function()
        K.reset()
        local before = K.screen()
        K.type('error("boom")')
        K.keys("return")
        K.frame(100)
        local s = K.screen()
        assert.is_nil(K.cc.view.input:notice_rows())
        assert.truthy(K.console_text():find("L1:boom", 1, true))
        assert.same('error("boom")', K.console_draft())
        assert.truthy(field(s):find('error("boom")', 1, true))
        assert.same(before.field_y, s.field_y)
      end)

    spec_it("NFR4.3 Understandable submission outcome: a "
        .. "console line Lua does not load shows why in the "
        .. "band, the line kept in the field", function()
      K.reset()
      K.type("break")
      K.keys("return")
      local s = K.screen()
      assert.truthy(band_text(s):find("no loop to break", 1,
        true))
      assert.same("error", K.cc.input:message_kind())
      assert.same("break", K.console_draft())
    end)

    spec_it("NFR4.3 Understandable submission outcome: the "
        .. "output's rows under the band neither move nor change, "
        .. "and come back with the next key", function()
      K.reset()
      output()
      K.type("x = = 1")
      local text = K.console_text()
      local before = K.screen()
      K.keys("return")
      local s = K.screen()
      local n = #band(s)
      assert.same(text, K.console_text())
      -- the band's fill is drawn last, over the output, from
      -- the top of the output's row it reaches into down to
      -- the status line; nothing else is drawn after the field
      local fill = s.fills[#s.fills]
      local top = s.field_y - n * fh()
      local origin = require("view.layout")(K.cc.view.cfg.view).top
      assert.same(s.field_y, fill.y + fill.h)
      assert.is_true(fill.y <= top and top - fill.y < fh())
      assert.same(0, (fill.y - origin) % fh())
      assert.same(before.field_y, s.field_y)
      K.keys("end")
      local gone = K.screen()
      assert.is_nil(K.cc.view.input:notice_rows())
      for _, f in ipairs(gone.fills) do
        assert.is_false(same_colour(colors().input.notice.bg,
          f.colour or { }) and f.y + f.h == gone.field_y)
      end
      assert.same(text, K.console_text())
      assert.same(before.field_y, gone.field_y)
    end)

    spec_it("IS3.14 Explain a refusal: a message longer than "
        .. "the band shows three rows, broken between words, the "
        .. "last cut", function()
      K.reset()
      long_message(string.rep("seven77 ", 40))
      local rows = band(K.screen())
      assert.same(3, #rows)
      for _, r in ipairs(rows) do
        assert.is_true(string.ulen(r.text) <= 64, r.text)
        assert.is_nil(r.text:find("seven77s", 1, true))
      end
      assert.same("…", rows[3].text:sub(-#"…"))
    end)

    spec_it("IS3.14 Explain a refusal: a message of several "
        .. "lines takes a row for each, three at most",
      function()
        K.reset()
        long_message("one\ntwo\nthree\nfour")
        local rows = band(K.screen())
        assert.same({ "one", "two", "three…" },
          { rows[1].text, rows[2].text, rows[3].text })
      end)

    spec_it("NFR4.3 Understandable submission outcome: a "
        .. "program paused by an error says it in the output, the "
        .. "band left empty", function()
      K.reset({ ["main.lua"] = PAUSES })
      K.open()
      K.keys("lctrl", "t")
      K.frame()
      -- the move from the snapshot to 'inspect' is the
      -- screenshot's callback, which needs a real graphics
      -- context
      K.cc:suspend()
      assert.same("inspect", K.app_state())
      K.frame(100)
      assert.is_nil(K.cc.view.input:notice_rows())
      assert.truthy(K.console_text():find("Execution error", 1,
        true))
      K.type("a")
      assert.same("a", K.console_draft())
    end)
  end)

  describe("a refusal said by the line that ran", function()
    --- A program paused by an error
    local function paused()
      K.reset({ ["main.lua"] = PAUSES })
      K.open()
      K.keys("lctrl", "t")
      K.frame()
      K.cc:suspend()
      assert.same("inspect", K.app_state())
      assert.is_false(K.cc.input:has_error())
    end

    for _, line in ipairs({ "run()", 'run("other")',
      "run_project()" }) do
      spec_it("IS3.14 Explain a refusal: " .. line .. " while "
          .. "a program is paused says it in the output, as a refusal, "
          .. "not in the band, the line run and stored",
        function()
          paused()
          K.type(line)
          K.keys("return")
          K.frame(100)
          assert.is_nil(K.cc.view.input:notice_rows())
          local t = K.cc.model.output.terminal
          local found
          for y, r in ipairs(t.buffer) do
            if table.concat(r):find("A project is already running: "
                .. "Ctrl+Q stops it.", 1, true) then
              found = t.state_buffer[y][1].color
            end
          end
          assert.is_not_nil(found)
          assert.is_true(same_colour(colors().terminal.refusal, found))
          -- the call returned: the line ran, so it is stored
          -- and the field is cleared
          assert.same("", K.console_draft())
          assert.same("inspect", K.app_state())
          K.keys("up")
          assert.same(line, K.console_draft())
        end)
    end

    spec_it("IS3.14 Explain a refusal: a message shown before "
        .. "Enter goes with that Enter, though the line runs "
        .. "and sets none", function()
      K.reset()
      K.type("x = = 1")
      K.keys("return")
      assert.is_true(K.cc.input:has_error())
      K.keys("home")
      K.keys("delete")
      K.type("y")
      K.keys("end")
      for _ = 1, 3 do K.keys("left") end
      K.keys("backspace")
      K.keys("backspace")
      K.cc.input:set_error({ "an older message" })
      K.keys("return")
      assert.same("", K.console_draft())
      assert.is_false(K.cc.input:has_error())
    end)
  end)

  describe("the next key", function()
    --- Leave the message of a line Lua does not load showing
    local function fails()
      K.reset()
      K.type("break")
      K.keys("return")
      assert.is_true(K.cc.input:has_error())
    end

    spec_it("IS3.14 Explain a refusal: a letter typed in the "
        .. "console dismisses the message and is typed",
      function()
        fails()
        K.type("x")
        assert.is_false(K.cc.input:has_error())
        assert.same("breakx", K.console_draft())
      end)

    spec_it("IS3.14 Explain a refusal: a letter whose text "
        .. "comes before its key in the console is typed once",
      function()
        fails()
        K.type_text_first("x")
        assert.is_false(K.cc.input:has_error())
        assert.same("breakx", K.console_draft())
      end)

    spec_it("IS3.14 Explain a refusal: Enter in the console "
        .. "dismisses the message and runs the line", function()
      K.reset()
      K.type("n = 7")
      K.cc.input:set_error({ "an older message" })
      K.keys("return")
      assert.is_false(K.cc.input:has_error())
      assert.same("", K.console_draft())
      assert.same(7, K.cc:get_project_env().n)
    end)

    spec_it("IS3.14 Explain a refusal: an arrow in the console "
        .. "dismisses the message and moves the cursor", function()
      fails()
      K.keys("left")
      assert.is_false(K.cc.input:has_error())
      assert.same({ 1, 5 }, cursor())
    end)

    spec_it("IS3.14 Explain a refusal: Escape in the console "
        .. "dismisses the message and clears the line", function()
      fails()
      K.keys("escape")
      assert.is_false(K.cc.input:has_error())
      assert.same("", K.console_draft())
    end)

    spec_it("IS3.14 Explain a refusal: a modifier or a lock on "
        .. "its own leaves the console's message", function()
      fails()
      for _, k in ipairs({ "lshift", "lctrl", "lalt", "capslock" })
      do
        K.keys(k)
        assert.is_true(K.cc.input:has_error(), k)
      end
      K.keys("capslock")
      assert.same("break", K.console_draft())
    end)

    spec_it("IS3.16 Show the key card: the card covers the "
        .. "console's message while F1 is held, and the message "
        .. "is back after", function()
      fails()
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      local s = K.screen()
      assert.is_nil(K.screen_text(s.texts):find("loop", 1, true))
      K.release("f1")
      assert.is_true(K.cc.input:has_error())
      assert.truthy(band_text(K.screen()):find("loop", 1, true))
    end)
  end)
end)
