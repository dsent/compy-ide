-- The keys of the screen modes (stage 2 of the program's canvas,
-- built as if the proposal "The Program's Canvas and the
-- Viewing Modes" were accepted, the maintainer's ruling of
-- November 17, 2026): F12 cycles text, combined and the full
-- picture in the console, idle, running or paused, and is the
-- IDE's for its whole press; it does nothing under the key card
-- and in the editor. From the full picture, while no program
-- that can act runs, any key or mouse button goes back to the
-- console's text and goes nowhere else; a program that can act
-- keeps its input, and F12 is its way back. The status line
-- names text and combined, and a pause with a picture says how
-- to see it. Events through the production gateway
-- (love.handlers, F.session), drawn through the real draw
-- functions (K.screen).
--
-- Spec justification (dev testing policy): a key path from the
-- full picture that misses the way back leaves a person there,
-- and a key that leaks through types into a field no one sees;
-- the timed status line's opacity and expiry show on a screen.

local F = require("tests.helpers.input_fixture")
local K = require("tests.helpers.editor_keys")
local Layout = require("view.layout")

--- @return string
local function mode()
  return K.cc.model.screen:get()
end

local function env()
  return K.cc:get_project_env()
end

--- Run a line typed at the console, as the user does
--- @param line string
local function run(line)
  K.type(line)
  K.keys("return")
  K.frame(100)
end

--- A program that keeps running (an update) and records every
--- key event it gets; `draws` makes it draw at its first line.
--- @param draws boolean?
--- @return string main.lua
local function recorder(draws)
  return (draws and "love.graphics.rectangle('fill', 0, 0, 9, 9)\n"
      or "")
      .. "seen = { }\n"
      .. "function love.update() end\n"
      .. "function love.keypressed(k, _, r)\n"
      .. "  seen[#seen + 1] = (r and 'repeat ' or 'press ') .. k\n"
      .. "end\n"
      .. "function love.keyreleased(k)\n"
      .. "  seen[#seen + 1] = 'release ' .. k\n"
      .. "end\n"
      .. "function love.textinput(t)\n"
      .. "  seen[#seen + 1] = 'text ' .. t\n"
      .. "end\n"
end

--- what the running program got, joined
local function seen()
  return table.concat(env().seen or { }, ", ")
end

--- a draw-once program: it draws at its first line and can do
--- nothing after it
local DRAWS_ONCE = "love.graphics.rectangle('fill', 0, 0, 9, 9)\n"

--- The console's notice, its parts joined
--- @return string?
local function notice()
  local e = K.cc.input.model.error
  if type(e) ~= "table" then return e and tostring(e) end
  local out = { }
  for i, v in ipairs(e) do
    out[i] = type(v) == "table" and tostring(v.msg or v[1])
        or tostring(v)
  end
  return table.concat(out, " ")
end

--- The pixel of the console field's row `row` (0 its last) and
--- column `col`
local function at(row, col)
  local v = K.cc.input.model.cfg.view
  local bottom = love.graphics.getHeight() - Layout(v).bottom
  return v.fw * (col - 1 + .2), bottom - v.fh * (row + .5)
end

--- the texts the status line draws, on the field's first row
local function status_texts()
  local fh = F.cfg.view.fh
  local out = { }
  for _, t in ipairs(K.screen().field) do
    if t.y < fh then out[#out + 1] = t.text end
  end
  return out
end

local function has(list, text)
  for _, t in ipairs(list) do
    if t == text then return true end
  end
  return false
end

describe("the screen modes' keys #canvas", function()
  --- the fixture's graphics stand-in draws no rectangle; a
  --- program's drawing call needs one to reach
  local saved_rectangle
  setup(function()
    K.setup()
    saved_rectangle = rawget(love.graphics, "rectangle")
    rawset(love.graphics, "rectangle", function() end)
  end)
  teardown(function()
    rawset(love.graphics, "rectangle", saved_rectangle)
    K.teardown()
  end)
  after_each(function()
    F.set_mouse_down(false)
    K.cleanup()
  end)

  describe("F12", function()
    it("cycles text, combined, the picture and text again",
      function()
        K.reset()
        assert.same("text", mode())
        K.keys("f12")
        assert.same("combined", mode())
        K.keys("f12")
        assert.same("picture", mode())
        K.keys("f12")
        assert.same("text", mode())
      end)

    it("acts once a press: its repeats do not cycle", function()
      K.reset()
      K.hold("f12")
      K.repeat_key("f12")
      K.repeat_key("f12")
      K.release("f12")
      assert.same("combined", mode())
    end)

    it("does nothing under the key card", function()
      K.reset()
      K.hold("f1")
      K.keys("f12")
      K.release("f1")
      assert.same("text", mode())
    end)

    --- the line under the card names no mode, which would offer
    --- F12 while the card holds it back; released, the label is
    --- back (review r1's blocker)
    --- @param word string --- the line's state word
    local function no_label_under_card(word)
      K.hold("f1")
      assert.is_true(K.cc:card_shows())
      local texts = { }
      for _, t in ipairs(K.screen().texts) do
        texts[#texts + 1] = t.text
      end
      assert.is_true(has(texts, word), "the line under the card")
      assert.is_false(has(texts, "text>F12"))
      assert.is_false(has(texts, "comb>F12"))
      K.keys("f12")
      K.release("f1")
      assert.is_false(K.cc:card_shows())
      assert.same("text", mode())
      assert.is_true(has(status_texts(), "text>F12"),
        "the label back once F1 is released")
    end

    it("leaves the line under the key card without the mode in the"
      .. " idle console", function()
        K.reset()
        no_label_under_card("console")
      end)

    it("leaves the line under the key card without the mode in a"
      .. " pause", function()
        K.reset({ ["main.lua"] = recorder(true) })
        K.start()
        K.keys("lctrl", "pause")
        K.frame()
        assert.same("inspect", K.app_state())
        assert.same("text", mode())
        no_label_under_card("paused")
      end)

    it("does nothing in the editor", function()
      K.reset()
      K.open()
      K.keys("f12")
      assert.same("editor", K.app_state())
      assert.same("text", mode())
      K.keys("lctrl", "q")
      assert.same("text", mode())
    end)

    it("cycles while a program runs, and the program sees none of"
      .. " its press, repeats or release", function()
        K.reset({ ["main.lua"] = recorder() })
        K.start()
        assert.same("running", K.app_state())
        K.hold("f12")
        K.repeat_key("f12")
        K.release("f12")
        assert.same("combined", mode())
        assert.same("", seen())
      end)

    it("leaves Shift+F12 to a program", function()
      K.reset({ ["main.lua"] = recorder() })
      K.start()
      K.keys("lshift", "f12")
      assert.same("text", mode())
      assert.truthy(seen():find("press f12", 1, true))
    end)

    it("cycles while a program is paused, and continue() brings"
      .. " back the mode before the pause", function()
        K.reset({ ["main.lua"] = recorder(true) })
        K.start()
        assert.same("picture", mode())
        K.keys("lctrl", "pause")
        K.frame()
        assert.same("inspect", K.app_state())
        assert.same("text", mode())
        K.keys("f12")
        assert.same("combined", mode())
        run("continue()")
        assert.same("running", K.app_state())
        assert.same("picture", mode())
        assert.is_nil(seen():find("f12", 1, true))
      end)
  end)

  describe("any key back from the full picture", function()
    --- the full picture with nothing run, by F12 from text,
    --- through combined
    local function picture()
      K.reset()
      K.keys("f12")
      K.keys("f12")
      assert.same("picture", mode())
    end

    --- f1: a key held from before the picture repeats into
    --- nothing while the picture hides the console's draft
    it("lets no held key repeat into the hidden draft", function()
      K.reset()
      local f = K.cc.input
      f:set_text({ "abcdef" })
      f:set_cursor_pos(1, 7)
      K.hold("backspace")
      assert.same("abcde", K.console_draft())
      K.keys("f12")
      K.keys("f12")
      assert.same("picture", mode())
      K.repeat_key("backspace")
      assert.same("abcde", K.console_draft())
      K.release("backspace")
    end)

    it("lets no held Shift+Right select the hidden draft",
      function()
        K.reset()
        local f = K.cc.input
        f:set_text({ "abcdef" })
        f:set_cursor_pos(1, 2)
        K.hold("right")
        K.keys("f12")
        K.keys("f12")
        assert.same("picture", mode())
        K.hold("lshift")
        K.repeat_key("right")
        assert.is_false(f.model:has_selection())
        K.release("lshift")
        K.release("right")
      end)

    it("goes back with a key, which types nothing", function()
      picture()
      K.type("a")
      assert.same("text", mode())
      assert.same("", K.console_draft())
    end)

    it("takes the key's repeats, its text and its release too",
      function()
        picture()
        K.hold("a")
        assert.same("text", mode())
        F.session.type("a")
        K.repeat_key("a")
        F.session.type("a")
        K.release("a")
        assert.same("", K.console_draft())
        K.type("b")
        assert.same("b", K.console_draft())
      end)

    it("goes back to text from a program's first drawing and from"
      .. " F12's picture, past combined", function()
        K.reset({ ["main.lua"] = DRAWS_ONCE })
        K.start()
        assert.same("picture", mode())
        K.type("a")
        assert.same("text", mode())
        assert.same("", K.console_draft())
        K.keys("f12")
        K.keys("f12")
        K.type("a")
        assert.same("text", mode())
      end)

    --- c5's finding on the canvas branch: a reserved chord goes
    --- back as any key does, through the one path
    it("goes to text on Ctrl+Q from a picture a program left at its"
      .. " natural end", function()
        K.reset({ ["main.lua"] = DRAWS_ONCE })
        K.start()
        assert.is_false(K.cc.run_live == true)
        assert.same("picture", mode())
        K.keys("lctrl", "q")
        assert.same("text", mode())
        assert.same("", K.console_draft())
      end)

    --- k3's first finding: a program that can act no more is
    --- found ended by the key or the click that goes back, as by
    --- any event: its natural end is made, whoever takes the event
    local GOES = DRAWS_ONCE .. "ended = 0\n"
      .. "compy.before_exit = function() ended = ended + 1 end\n"
      .. "function love.mousereleased()"
      .. " compy.input.hooks.mousereleased = nil end\n"
    for name, back in pairs({
      key = function() K.type("a") end,
      button = function()
        F.session.mousepressed(10, 10, 1, false, 1)
        F.session.mousereleased(10, 10, 1, false, 1)
      end,
      touch = function()
        love.handlers.touchpressed("t1", 10, 10, 0, 0, 1)
        love.handlers.touchreleased("t1", 10, 10, 0, 0, 1)
      end,
    }) do
      it("ends a program that can act no more when a " .. name
        .. " goes back from its picture", function()
          K.reset({ ["main.lua"] = GOES })
          K.start()
          assert.is_true(K.cc.run_live)
          assert.same("picture", mode())
          F.session.mousepressed(10, 10, 1, false, 1)
          F.session.mousereleased(10, 10, 1, false, 1)
          assert.is_true(K.cc.run_live)
          local seen_end = env().ended
          assert.same("picture", mode())
          back()
          K.frame()
          assert.same("text", mode())
          assert.is_false(K.cc.run_live == true)
          assert.same(0, seen_end)
          assert.same("", K.console_draft())
        end)
    end

    --- k4's finding, as a class: every event finds a run that
    --- can act no more ended before anything takes it, a reserved
    --- chord included; and no chord changes what it does to a
    --- run that can still act
    describe("each reserved chord on a run that can act no more",
      function()
        --- a drawing program whose last handler goes at a release;
        --- `live` keeps it running with an update
        local function program(live)
          return DRAWS_ONCE
            .. "compy.before_exit = function() end\n"
            .. "function love.mousereleased()"
            .. " compy.input.hooks.mousereleased = nil end\n"
            .. (live and "function love.update() end\n" or "")
        end
        --- the program's before_exit, counted from here
        local calls = 0
        local function byes() return calls end
        local function start(live)
          K.reset({ ["main.lua"] = program(live) })
          K.start()
          calls = 0
          env().compy.before_exit = function() calls = calls + 1 end
          F.session.mousepressed(10, 10, 1, false, 1)
          F.session.mousereleased(10, 10, 1, false, 1)
          assert.is_true(K.cc.run_live)
          assert.same("picture", mode())
          assert.same(0, byes())
        end
        local CHORDS = {
          ["Ctrl+Q"] = { keys = { "lctrl", "q" },
            done = function() assert.is_false(K.cc.run_live == true) end,
            live = function()
              assert.is_false(K.cc.run_live == true)
              assert.same(1, byes())
            end },
          ["Ctrl+R"] = { keys = { "lctrl", "r" },
            done = function() assert.is_false(K.cc.run_live == true) end,
            live = function()
              assert.is_true(K.cc.run_live)
              assert.same(1, byes())
            end },
          ["Ctrl+T"] = { keys = { "lctrl", "t" },
            done = function() assert.same("editor", K.app_state()) end,
            live = function()
              assert.same("editor", K.app_state())
              assert.same(1, byes())
            end },
          ["Ctrl+Pause"] = { keys = { "lctrl", "pause" },
            done = function()
              assert.are_not.same("inspect", K.app_state())
            end,
            live = function()
              assert.same("inspect", K.app_state())
              assert.same(0, byes())
            end },
          ["F12"] = { keys = { "f12" },
            done = function() assert.same("text", mode()) end,
            live = function()
              assert.same("text", mode())
              assert.is_true(K.cc.run_live)
              assert.same(0, byes())
            end },
          --- on the full picture F1 is any key: it goes back, and
          --- the card comes with the next press
          ["F1"] = { hold = "f1",
            done = function()
              assert.same("text", mode())
              assert.is_false(K.cc:card_shows())
            end,
            live = function()
              assert.is_false(K.cc:card_shows())
              assert.same(0, byes())
            end },
          ["Ctrl+Escape"] = { keys = { "lctrl", "escape" },
            done = function() assert.same(1, #F.quits()) end,
            live = function()
              assert.same(1, #F.quits())
              assert.same(0, byes())
            end },
        }
        for name, c in pairs(CHORDS) do
          local function chord()
            F.quits()
            if c.hold then K.hold(c.hold) else K.keys(unpack(c.keys)) end
          end
          it(name .. " ends it first, then acts", function()
            start(false)
            chord()
            assert.same(1, byes())
            c.done()
            if c.hold then K.release(c.hold) end
          end)
          it(name .. " acts as ever on a run that can act", function()
            start(true)
            chord()
            c.live()
            if c.hold then K.release(c.hold) end
          end)
        end
      end)

    --- k5's finding: the click timer's derived click comes inside
    --- the frame's update, where the end is made once the update
    --- returns; the picture stays on show after that end too
    it("keeps the picture through an end the click timer finds",
      function()
        K.reset({ ["main.lua"] = DRAWS_ONCE
          .. "compy.before_exit = function() end\n"
          .. "function love.mousereleased()"
          .. " compy.input.hooks.mousereleased = nil end\n" })
        K.start()
        local calls = 0
        env().compy.before_exit = function() calls = calls + 1 end
        F.session.mousepressed(10, 10, 1, false, 1)
        F.session.mousereleased(10, 10, 1, false, 1)
        assert.is_true(K.cc.run_live)
        for _ = 1, 10 do K.frame(0.1) end
        assert.is_false(K.cc.run_live == true)
        assert.same(1, calls)
        assert.same("picture", mode())
      end)

    --- k6: every event kind on a finished run's picture, at once
    --- and inside a held End (where the end waits for the hold's
    --- close): the run ends once, and the screen is what the event
    --- made of it (text after a key or a press that goes back, the
    --- picture otherwise)
    describe("every event kind, at once and held", function()
      local End = require("util.program_end")
      local calls
      local function finished()
        K.reset({ ["main.lua"] = DRAWS_ONCE
          .. "function love.mousereleased()"
          .. " compy.input.hooks.mousereleased = nil end\n" })
        K.start()
        calls = 0
        env().compy.before_exit = function() calls = calls + 1 end
        F.session.press("m")
        F.session.mousepressed(10, 10, 2, false, 1)
        love.handlers.touchpressed("one", 10, 10, 0, 0, 1)
        F.session.mousepressed(10, 10, 1, false, 1)
        F.session.mousereleased(10, 10, 1, false, 1)
        assert.is_true(K.cc.run_live)
        assert.same("picture", mode())
      end
      after_each(function() End.reset() end)
      local hh = function() return love.handlers end
      local EVENTS = {
        key = { "text", function() F.session.press("a") end },
        repeat_key = { "picture",
          function() F.session.repeat_press("m") end },
        key_release = { "picture", function() F.session.release("m") end },
        modifier = { "picture", function() F.session.press("lshift") end },
        text = { "picture", function() F.session.type("x") end },
        f12 = { "text", function() F.session.press("f12") end },
        mouse_press = { "text", function()
          F.session.mousepressed(10, 10, 1, false, 1)
        end },
        mouse_release = { "picture", function()
          F.session.mousereleased(10, 10, 2, false, 1)
        end },
        mouse_move = { "picture", function()
          F.session.mousemoved(20, 10, 10, 0, false)
        end },
        wheel = { "picture", function() F.session.wheelmoved(0, 1) end },
        touch_press = { "text", function()
          hh().touchpressed("one", 10, 10, 0, 0, 1)
        end },
        touch_move = { "picture", function()
          hh().touchmoved("one", 20, 10, 10, 0, 1)
        end },
        touch_release = { "picture", function()
          hh().touchreleased("one", 10, 10, 0, 0, 1)
        end },
        singleclick = { "picture",
          function() hh().singleclick(10, 10) end },
      }
      for name, e in pairs(EVENTS) do
        for _, held in ipairs({ false, true }) do
          it(name .. (held and ", held" or ", at once"), function()
            finished()
            if held then End.held(e[2]) else e[2]() end
            assert.same(1, calls)
            assert.is_false(K.cc.run_live == true)
            assert.same(e[1], mode())
          end)
        end
      end
    end)

    --- a button that went back and whose release is lost (a
    --- change of focus on the Compy) does not hold back the moves
    --- after it
    describe("a lost release of a button that went back", function()
      local got, saved
      before_each(function()
        picture()
        F.set_mouse_down(true)
        F.session.mousepressed(10, 10, 1, false, 1)
        assert.same("text", mode())
        got, saved = 0, love.mousemoved
        love.mousemoved = function() got = got + 1 end
      end)
      after_each(function() love.mousemoved = saved end)

      it("lets the moves through once the button is up", function()
        F.session.mousemoved(20, 10, 10, 0, false)
        assert.same(0, got)
        F.set_mouse_down(false)
        F.session.mousemoved(30, 10, 10, 0, false)
        assert.same(1, got)
      end)

      it("lets the moves through after the window loses focus",
        function()
          love.handlers.focus(false)
          F.session.mousemoved(20, 10, 10, 0, false)
          assert.same(1, got)
        end)

      --- f1: a tap, with no move between its lost release and the
      --- next press, finds the button down again
      it("lets the moves of a new press of that button through",
        function()
          F.session.mousepressed(10, 10, 1, false, 1)
          F.session.mousemoved(20, 10, 10, 0, false)
          assert.same(1, got)
        end)
    end)

    --- k3's second finding: a keypad key's own character
    it("drops a keypad key's own text after it goes back",
      function()
        local h = love.handlers
        for _, k in ipairs({ "kp1", "kp+", "kp." }) do
          picture()
          F.session.press(k)
          h.textinput(k:sub(3))
          F.session.release(k)
          assert.same("", K.console_draft(), k)
        end
      end)

    it("leaves the picture up on a modifier alone", function()
      picture()
      K.hold("lshift")
      assert.same("picture", mode())
      K.release("lshift")
      assert.same("picture", mode())
    end)

    it("goes back on a reserved chord, which acts as well",
      function()
        picture()
        K.keys("lctrl", "t")
        assert.same("editor", K.app_state())
        -- Ctrl+T's stop of what ran shows text
        assert.same("text", mode())
      end)

    it("leaves Ctrl+Escape its quit", function()
      picture()
      F.quits()
      K.keys("lctrl", "escape")
      assert.same(1, #F.quits())
    end)

    it("takes no text without a key: the field is not seen",
      function()
        picture()
        F.session.type("x")
        K.frame()
        assert.same("picture", mode())
        assert.same("", K.console_draft())
      end)

    it("goes back with a mouse button, whose release goes nowhere"
      .. " either", function()
        picture()
        K.cc.input:set_text({ "abcdef" })
        local before = { K.cc.input:get_cursor_pos() }
        local x, y = at(0, 2)
        F.set_mouse_down(true)
        F.session.mousepressed(x, y, 1, false, 1)
        assert.same("text", mode())
        local x2 = at(0, 5)
        F.session.mousemoved(x2, y, x2 - x, 0, false)
        F.set_mouse_down(false)
        F.session.mousereleased(x2, y, 1, false, 1)
        assert.same(before, { K.cc.input:get_cursor_pos() })
        assert.is_false(K.cc.input.model:has_selection())
      end)

    it("goes back with a touch, whose moves and release go"
      .. " nowhere", function()
        picture()
        local got = { }
        local saved = { }
        for _, name in ipairs({ "touchpressed", "touchmoved",
          "touchreleased" }) do
          saved[name] = love[name]
          love[name] = function() got[#got + 1] = name end
        end
        finally(function()
          for name, f in pairs(saved) do love[name] = f end
        end)
        local h = love.handlers
        h.touchpressed("t1", 10, 10, 0, 0, 1)
        assert.same("text", mode())
        h.touchmoved("t1", 20, 10, 10, 0, 1)
        h.touchreleased("t1", 20, 10, 0, 0, 1)
        assert.same({ }, got)
      end)

    it("stays on the wheel and on movement, and the output does"
      .. " not scroll", function()
        picture()
        for i = 1, 40 do K.cc.model.output:push("line " .. i) end
        K.cc.model.output:to_rest()
        F.session.wheelmoved(0, 1)
        F.session.mousemoved(10, 10, 1, 1, false)
        assert.same("picture", mode())
        assert.is_false(K.cc.model.output:is_scrolled())
      end)

    it("leaves a program that can act its keys: F12 is its way"
      .. " back", function()
        K.reset({ ["main.lua"] = recorder(true) })
        K.start()
        assert.same("picture", mode())
        K.type("a")
        assert.same("picture", mode())
        assert.same("press a, text a, release a", seen())
        K.keys("f12")
        assert.same("text", mode())
      end)

    it("goes back at a pause, and the paused program is owed"
      .. " nothing of the key", function()
        K.reset({ ["main.lua"] = recorder(true) })
        K.start()
        K.keys("lctrl", "pause")
        K.frame()
        K.keys("f12")
        K.keys("f12")
        assert.same("picture", mode())
        K.hold("a")
        assert.same("text", mode())
        run("continue()")
        --- k1's sixth finding: the case resumes
        assert.same("running", K.app_state())
        K.release("a")
        assert.is_nil(seen():find(" a", 1, true))
      end)

    --- k1's fourth finding
    it("lets another key type while the back key is held",
      function()
        picture()
        K.hold("a")
        K.type("b")
        K.release("a")
        assert.same("b", K.console_draft())
      end)

    --- k2's first finding: both orders a key and its text come in
    local h = function() return love.handlers end
    it("drops the back key's text and types another key's, its text"
      .. " first, as a Compy sends it", function()
        picture()
        h().textinput("a")
        F.session.press("a")
        assert.same("text", mode())
        h().textinput("b")
        F.session.press("b")
        F.session.release("b")
        F.session.release("a")
        assert.same("b", K.console_draft())
      end)

    it("drops the back key's text and types another key's, its"
      .. " press first, as a desktop sends it", function()
        picture()
        F.session.press("a")
        h().textinput("a")
        F.session.press("b")
        h().textinput("b")
        F.session.release("b")
        F.session.release("a")
        assert.same("b", K.console_draft())
      end)

    it("drops the back key's text in either case, and its repeats'",
      function()
        picture()
        F.session.press("lshift")
        F.session.press("a")
        h().textinput("A")
        F.session.repeat_press("a")
        h().textinput("A")
        F.session.release("a")
        F.session.release("lshift")
        assert.same("", K.console_draft())
      end)

    it("types the back key's character once that key is up",
      function()
        picture()
        F.session.press("a")
        F.session.release("a")
        h().textinput("a")
        assert.same("a", K.console_draft())
      end)

    --- k2's third finding: the frame between a pause's request
    --- and the pause keeps the mode, which the pause saves for
    --- continue(). The program's one handler pauses it and goes,
    --- so it can act no more while the pause waits for its frame.
    it("leaves the picture alone between a pause's request and the"
      .. " pause", function()
        K.reset({ ["main.lua"] = DRAWS_ONCE .. "function"
          .. " love.keypressed() pause()"
          .. " compy.input.hooks.keypressed = nil end\n" })
        K.start()
        assert.same("picture", mode())
        F.session.press("x")
        assert.same("snapshot", K.app_state())
        F.session.press("z")
        F.session.mousepressed(10, 10, 1, false, 1)
        F.session.mousereleased(10, 10, 1, false, 1)
        F.session.release("z")
        F.session.release("x")
        K.frame()
        assert.same("inspect", K.app_state())
        --- the mode the pause saved for continue()
        assert.same("picture", K.cc.model.screen.paused)
      end)

    --- text with no key of its own (a paste, a method of
    --- input) after the key that went back is up goes on
    it("lets text with no key through once the back key is up",
      function()
        picture()
        K.keys("lctrl", "q")
        assert.same("text", mode())
        F.session.type("r")
        assert.same("r", K.console_draft())
      end)

    --- k1's third finding
    it("keeps a button's moves from a program resumed while the"
      .. " button that went back is held", function()
        K.reset({ ["main.lua"] = recorder(true)
          .. "moves = 0\nfunction love.mousemoved() moves = moves + 1"
          .. " end\n" })
        K.start()
        K.keys("lctrl", "pause")
        K.frame()
        K.keys("f12")
        K.keys("f12")
        F.set_mouse_down(true)
        F.session.mousepressed(10, 10, 1, false, 1)
        assert.same("text", mode())
        run("continue()")
        assert.same("running", K.app_state())
        F.session.mousemoved(20, 10, 10, 0, false)
        F.set_mouse_down(false)
        F.session.mousereleased(20, 10, 1, false, 1)
        assert.same(0, env().moves)
      end)

    --- k1's second finding: a packaged program's picture is all
    --- there is, and no key shows a console
    it("does nothing in playback", function()
      K.reset({ ["main.lua"] = DRAWS_ONCE })
      local Session = require("tests.helpers.input_session")
      K.cc.cfg.mode = "play"
      F.session = Session.new(K.cc)
      finally(function()
        K.cc.cfg.mode = "dev"
        F.session = Session.new(K.cc)
      end)
      K.cc:run_project(K.PROJECT)
      assert.same("picture", mode())
      K.type("a")
      assert.same("picture", mode())
      F.session.mousepressed(10, 10, 1, false, 1)
      F.session.mousereleased(10, 10, 1, false, 1)
      assert.same("picture", mode())
      K.keys("f12")
      assert.same("picture", mode())
    end)

    --- k1's seventh finding: F12 in the frame between a pause's
    --- request and the pause leaves continue() its mode
    it("leaves continue() the mode before the pause when F12 comes"
      .. " before the pause is made", function()
        K.reset({ ["main.lua"] = recorder(true) })
        K.start()
        assert.same("picture", mode())
        F.session.press("lctrl")
        F.session.press("pause")
        F.session.release("pause")
        F.session.release("lctrl")
        assert.same("snapshot", K.app_state())
        F.session.press("f12")
        F.session.release("f12")
        K.frame()
        assert.same("inspect", K.app_state())
        run("continue()")
        assert.same("running", K.app_state())
        assert.same("picture", mode())
      end)
  end)

  describe("the status line", function()
    --- the maintainer's ruling of November 19, 2026: "show
    --- text/combined as `text>F12`/`comb>F12`"
    it("names text and combined with the key to the next mode",
      function()
        K.reset()
        assert.is_true(has(status_texts(), "text>F12"))
        K.keys("f12")
        local texts = status_texts()
        assert.is_true(has(texts, "comb>F12"))
        assert.is_false(has(texts, "text>F12"))
      end)

    --- the right block is packed to the right (the maintainer's
    --- ruling of November 18, 2026): the mode's word stands two
    --- columns before the cursor's place, and moves left as that
    --- grows; with no position, at the line's right edge
    it("stands two columns before the cursor's place, or at the"
      .. " edge", function()
        K.reset()
        local fw = F.cfg.view.fw
        local edge = F.cfg.view.w - fw
        --- where `word`, or the text matching `pattern`, starts
        --- and ends on the status line's row
        local function at(pattern)
          for _, t in ipairs(K.screen().field) do
            if t.text:match(pattern) and t.y < F.cfg.view.fh then
              return t.x, t.x + string.ulen(t.text) * fw
            end
          end
        end
        local function packed(word)
          local _, mode_end = at("^" .. word .. "$")
          local pos_start, pos_end = at("^%d+:%d+$")
          assert.equal(edge, pos_end)
          assert.equal(pos_start - 2 * fw, mode_end)
          return mode_end
        end
        local short = packed("text>F12")
        K.type(string.rep("y", 40))
        local long = packed("text>F12")
        assert.equal(short - fw, long, "one column left for 1:41")
        K.keys("f12")
        packed("comb>F12")
        K.keys("f12")
        K.keys("f12")
        -- behind a running program that owns the input: the bare
        -- line, with no position
        K.reset({ ["main.lua"] = recorder() })
        K.start()
        assert.is_true(K.cc:fieldless())
        local _, mode_end = at("^text>F12$")
        assert.equal(edge, mode_end)
      end)

    local function picture_banner()
      local v = F.cfg.view
      local sy = K.cc.view.input:status_y(0)
      local s = K.screen()
      assert.same({ }, s.field)
      local words = { }
      for _, t in ipairs(s.texts) do
        if t.y >= sy then
          words[#words + 1] = t.text
          assert.equal(1, t.colour[4] or 1)
          assert.is_nil(t.text:match("^%d+:%d+$"))
        end
      end
      local band_alpha
      local band_h = love.graphics.getHeight() - sy
      for _, f in ipairs(s.fills) do
        if f.y == sy and f.h == band_h and f.w == v.w then
          band_alpha = f.colour[4]
        end
      end
      return words, band_alpha
    end

    it("shows on F12 into the full picture for two seconds", function()
      K.reset()
      K.keys("f12")
      K.keys("f12")
      local words, alpha = picture_banner()
      assert.is_true(has(words, K.PROJECT))
      assert.is_true(has(words, "picture"))
      assert.is_true(has(words, "view>F12"))
      assert.equal(F.cfg.view.colors.screen.combined.ground, alpha)

      K.frame(1.9)
      assert.is_true(has((picture_banner()), "view>F12"))
      K.frame(0.11)
      local gone, gone_alpha = picture_banner()
      assert.same({ }, gone)
      assert.is_nil(gone_alpha)

      -- leaving on a key or mouse button clears it at once
      K.keys("f12")
      K.keys("f12")
      K.keys("f12")
      assert.is_true(has((picture_banner()), "view>F12"))
      F.session.mousepressed(100, 100, 1)
      assert.equal("text", mode())
      assert.is_false(has(status_texts(), "view>F12"))

      -- a draw-once program's picture shows no line
      K.reset({ ["main.lua"] = DRAWS_ONCE })
      K.start()
      assert.same({ }, (picture_banner()))
    end)

    it("shows no banner on F12 while a program runs", function()
      K.reset({ ["main.lua"] = recorder(true) })
      K.start()
      assert.same({ }, (picture_banner()))
      K.keys("f12")
      K.keys("f12")
      K.keys("f12")
      assert.equal("picture", mode())
      assert.is_false(K.cc.model.screen:banner_shown())
      local words, alpha = picture_banner()
      assert.same({ }, words)
      assert.is_nil(alpha)
      K.keys("a")
      assert.equal("picture", mode())
      assert.matches("press a", seen())

      -- idling behind the console with a handler still counts as running
      K.reset({ ["main.lua"] = DRAWS_ONCE
        .. "function love.keypressed() end\n" })
      K.start()
      assert.equal("ready", K.app_state())
      K.keys("f12")
      K.keys("f12")
      K.keys("f12")
      assert.equal("picture", mode())
      assert.is_false(K.cc.model.screen:banner_shown())
      assert.same({ }, (picture_banner()))

      -- a paused program is a console state: F12 shows the banner
      K.keys("lctrl", "pause")
      K.frame()
      assert.equal("inspect", K.app_state())
      K.keys("f12")
      K.keys("f12")
      assert.equal("picture", mode())
      assert.is_true(has((picture_banner()), "view>F12"))
    end)
  end)

  describe("the pause's hint", function()
    local HINT = "F12 shows the picture"

    --- the band's rows
    local function rows()
      return K.cc.input:get_wrapped_error() or { }
    end

    it("shows when the paused program has a picture, on the"
      .. " pause's row where both fit", function()
        K.reset({ ["main.lua"] = recorder(true) })
        K.start()
        K.keys("lctrl", "pause")
        K.frame()
        assert.same({ "BREAK into program (" .. HINT .. ")" }, rows())
      end)

    it("takes a row of its own where the pause's text leaves no"
      .. " room", function()
        local long = string.rep("x", 50)
        K.reset({ ["main.lua"] = DRAWS_ONCE
          .. "function love.update() pause('" .. long .. "') end\n" })
        K.start()
        K.frame()
        assert.same("inspect", K.app_state())
        assert.same({ long, HINT }, rows())
      end)

    it("does not show without one", function()
      K.reset({ ["main.lua"] = recorder() })
      K.start()
      K.keys("lctrl", "pause")
      K.frame()
      local n = notice()
      assert.truthy(n and n:find("BREAK into program", 1, true))
      assert.is_nil(n:find(HINT, 1, true))
    end)

    --- k1's first finding
    it("measures a pause text that is not UTF-8 as it shows",
      function()
        K.reset({ ["main.lua"] = DRAWS_ONCE
          .. "function love.update() pause(string.char(255)) end\n" })
        K.start()
        K.frame()
        assert.same("inspect", K.app_state())
        local r = rows()
        assert.same(1, #r)
        assert.truthy(r[1]:find("(" .. HINT .. ")", 1, true))
      end)

    --- k1's fifth finding: the band shows three rows at most
    for name, text in pairs({
      ["three lines"] = "one\\ntwo\\nthree",
      ["a text three rows wide"] = string.rep("word ", 40),
      --- k2's second finding
      ["a word wider than the band"] = string.rep("wordx", 40),
    }) do
      it("keeps the hint in sight after " .. name, function()
        K.reset({ ["main.lua"] = DRAWS_ONCE
          .. "function love.update() pause('" .. text .. "') end\n" })
        K.start()
        K.frame()
        assert.same("inspect", K.app_state())
        local shown = K.cc.view.input:notice_rows()
        assert.same(HINT, shown[#shown])
        assert.truthy(shown[1]:find("^one") or shown[1]:find("^word"))
      end)
    end

    it("shows alone after pause() with no message", function()
      K.reset({ ["main.lua"] = DRAWS_ONCE
        .. "function love.update() pause() end\n" })
      K.start()
      K.frame()
      assert.same("inspect", K.app_state())
      assert.same(HINT, notice())
    end)
  end)

  describe("compy.screen.showNotice", function()
    local function fh()
      return F.cfg.view.fh
    end

    local function notice_colors()
      return F.cfg.view.colors.input.notice
    end

    local function same_rgb(a, b)
      return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
    end

    --- texts drawn in the notice warning colour
    local function drawn_notice(s)
      local warn = notice_colors().warning
      local out = { }
      for _, t in ipairs(s.texts) do
        if same_rgb(t.colour, warn) then
          out[#out + 1] = t
        end
      end
      return out
    end

    it("starts empty, shows a notice of kind 'notice', and returns"
      .. " no values", function()
        K.reset()
        assert.is_false(K.cc.input:has_error())
        assert.is_nil(K.cc.input:message_kind())
        run('compy.screen.showNotice("Press Space to jump")')
        assert.same("Press Space to jump", notice())
        assert.same("notice", K.cc.input:message_kind())
        local rows = drawn_notice(K.screen())
        assert.equal(1, #rows)
        assert.same("Press Space to jump", rows[1].text)
        assert.equal(0,
          select("#", env().compy.screen.showNotice("again")))
        assert.equal(0,
          select("#", env().compy.screen.showNotice("")))
      end)

    it("replaces the previous message and clears with empty string",
      function()
        K.reset()
        env().compy.screen.showNotice("First notice")
        assert.same("First notice", notice())
        env().compy.screen.showNotice("Try the arrow keys")
        assert.same("Try the arrow keys", notice())
        assert.same("notice", K.cc.input:message_kind())
        env().compy.screen.showNotice("")
        assert.is_false(K.cc.input:has_error())
        assert.is_nil(K.cc.input:message_kind())
        assert.is_nil(K.cc.view.input:notice_rows())
      end)

    it("wraps between words and cuts longer text to three rows",
      function()
        K.reset()
        local words = string.rep("seven77 ", 12) .. "end."
        env().compy.screen.showNotice(words)
        local rows = K.cc.view.input:notice_rows()
        assert.equal(2, #rows)
        assert.same(words, rows[1] .. " " .. rows[2])
        for _, r in ipairs(rows) do
          assert.is_true(#r <= 64, r)
        end

        env().compy.screen.showNotice(string.rep("seven77 ", 40))
        local cut = K.cc.view.input:notice_rows()
        assert.equal(3, #cut)
        assert.same("…", cut[3]:sub(-#"…"))
        local drawn = drawn_notice(K.screen())
        assert.equal(3, #drawn)
        assert.same(cut[3], drawn[3].text)
      end)

    it("is dismissed by the next key at the console while the key"
      .. " still acts", function()
        K.reset()
        run('compy.screen.showNotice("Watch this")')
        assert.same("Watch this", notice())
        K.screen()
        K.type("x")
        assert.is_false(K.cc.input:has_error())
        assert.same("x", K.console_draft())
      end)

    it("is dismissed by the next key during a run while the key"
      .. " still reaches love.keypressed", function()
        K.reset({ ["main.lua"] = recorder()
          .. 'compy.screen.showNotice("Press Space to jump")\n' })
        K.start()
        assert.same("Press Space to jump", notice())
        K.screen()
        K.keys("space")
        assert.is_false(K.cc.input:has_error())
        assert.truthy(seen():find("press space", 1, true), seen())
      end)

    it("keeps a newer notice set by love.keypressed on that key",
      function()
        K.reset({ ["main.lua"] = [[
compy.screen.showNotice("First")
function love.update() end
function love.keypressed()
  compy.screen.showNotice("Second")
end
]] })
        K.start()
        assert.same("First", notice())
        K.screen()
        K.keys("space")
        assert.same("Second", notice())
      end)

    it("keeps a notice set by love.textinput when text arrives"
      .. " before keypressed, then dismisses after a draw", function()
        K.reset({ ["main.lua"] = [[
function love.update() end
function love.keypressed() end
function love.textinput(t)
  if t == 'x' then
    compy.screen.showNotice("Use 8 letters or fewer")
  end
end
]] })
        K.start()
        -- Compy order: text arrives before its key press
        K.type_text_first("x")
        assert.same("Use 8 letters or fewer", notice())
        K.screen()
        K.keys("space")
        assert.is_false(K.cc.input:has_error())
        K.keys("lctrl", "q")
      end)

    it("stays visible on a lone modifier or lock key, idle and"
      .. " running", function()
        K.reset()
        run('compy.screen.showNotice("Stay idle")')
        K.screen()
        for _, k in ipairs({ "lshift", "rshift", "lctrl", "lalt",
          "capslock" }) do
          K.keys(k)
          assert.same("Stay idle", notice(), k)
        end
        K.keys("capslock")

        K.reset({ ["main.lua"] = recorder()
          .. 'compy.screen.showNotice("Stay running")\n' })
        K.start()
        K.screen()
        for _, k in ipairs({ "lshift", "lctrl", "lalt",
          "capslock" }) do
          K.keys(k)
          assert.same("Stay running", notice(), k)
        end
        K.keys("capslock")
        -- key repeat does not dismiss either
        K.hold("a")
        assert.is_false(K.cc.input:has_error())
        env().compy.screen.showNotice("During hold")
        K.screen()
        K.repeat_key("a")
        assert.same("During hold", notice())
        K.release("a")
        K.keys("lctrl", "q")
      end)

    it("draws above the bare status line during a run in text and"
      .. " combined, hides in picture, and shows on return", function()
        K.reset({ ["main.lua"] = recorder()
          .. 'compy.screen.showNotice("Run hint")\n' })
        K.start()
        assert.is_true(K.cc:fieldless())
        local sy = K.cc.view.input:status_y(0)

        -- text mode during a run (field hidden)
        assert.same("text", mode())
        local s = K.screen()
        local rows = drawn_notice(s)
        assert.equal(1, #rows)
        assert.same("Run hint", rows[1].text)
        assert.equal(sy - fh(), rows[1].y)
        -- black band fill sits directly above the bare status line
        local bg = notice_colors().bg
        local found_bg = false
        for _, f in ipairs(s.fills) do
          if same_rgb(f.colour, bg) and f.y + f.h == sy then
            found_bg = true
          end
        end
        assert.is_true(found_bg)

        -- combined mode during a run (program switches mode)
        env().compy.screen.show("combined")
        assert.same("combined", mode())
        rows = drawn_notice(K.screen())
        assert.equal(1, #rows)
        assert.same("Run hint", rows[1].text)

        -- full picture draws no band
        env().compy.screen.show("picture")
        assert.same("picture", mode())
        rows = drawn_notice(K.screen())
        assert.equal(0, #rows)

        -- return to text from code shows the still-current notice
        env().compy.screen.show("text")
        assert.same("text", mode())
        rows = drawn_notice(K.screen())
        assert.equal(1, #rows)
        assert.same("Run hint", rows[1].text)
        K.keys("lctrl", "q")
      end)

    it("draws above a shown two-row program input field without"
      .. " being covered by it", function()
        K.reset({ ["main.lua"] = [[
compy.input.show({ prompt = 'Answer?', text = { 'First', 'Second' } })
compy.screen.showNotice('Read this first')
]] })
        K.start()
        local ui = love.state.user_input
        assert.is_not_nil(ui)
        local expected_y = ui.V:status_y(2)
        local s = K.screen(function()
          ui.C:update_view()
          ui.V:draw()
        end)
        assert.equal(expected_y, ui.V.start_h)
        local rows = drawn_notice(s)
        assert.equal(1, #rows)
        assert.same("Read this first", rows[1].text)
        assert.equal(expected_y - fh(), rows[1].y)
        assert.is_true(rows[1].y + fh() <= ui.V.start_h)
        local bg = notice_colors().bg
        local found_bg = false
        for _, f in ipairs(s.fills) do
          if same_rgb(f.colour, bg) and f.y + f.h == expected_y then
            found_bg = true
          end
        end
        assert.is_true(found_bg)
        K.keys("lctrl", "q")
      end)

    it("is dismissed by F12 while F12 still cycles the mode",
      function()
        K.reset()
        run('compy.screen.showNotice("Dismiss on F12")')
        assert.same("Dismiss on F12", notice())
        K.screen()
        K.keys("f12")
        assert.is_false(K.cc.input:has_error())
        assert.same("combined", mode())

        K.reset({ ["main.lua"] = recorder()
          .. 'compy.screen.showNotice("Run F12")\n' })
        K.start()
        assert.same("Run F12", notice())
        K.screen()
        K.keys("f12")
        assert.is_false(K.cc.input:has_error())
        assert.same("combined", mode())
        K.keys("lctrl", "q")
      end)

    it("is dismissed by F1 behind a running program while F1 still"
      .. " reaches love.keypressed", function()
        K.reset({ ["main.lua"] = recorder()
          .. 'compy.screen.showNotice("Run F1")\n' })
        K.start()
        assert.same("Run F1", notice())
        K.screen()
        K.keys("f1")
        assert.is_false(K.cc.input:has_error())
        assert.truthy(seen():find("press f1", 1, true), seen())
        K.keys("lctrl", "q")
      end)

    it("out of the full picture keeps an unseen notice and"
      .. " dismisses one already drawn", function()
        -- set while in picture mode (never drawn): survives return
        K.reset()
        env().compy.screen.show("picture")
        env().compy.screen.showNotice("Set in picture")
        K.screen()
        assert.same("Set in picture", notice())
        K.keys("f1")
        assert.same("text", mode())
        assert.same("Set in picture", notice())
        local rows = drawn_notice(K.screen())
        assert.equal(1, #rows)
        assert.same("Set in picture", rows[1].text)

        -- already drawn in text, then switched to picture:
        -- returning with a key dismisses it
        env().compy.screen.show("picture")
        assert.same("picture", mode())
        K.keys("a")
        assert.same("text", mode())
        assert.is_false(K.cc.input:has_error())
      end)

    it("stays when F1 is held for the key card and released",
      function()
        K.reset()
        run('compy.screen.showNotice("Under card")')
        assert.same("Under card", notice())
        K.screen()
        K.hold("f1")
        assert.is_not_nil(K.key_card())
        K.keys("a")
        K.release("f1")
        assert.is_nil(K.key_card())
        assert.same("Under card", notice())
        assert.same("notice", K.cc.input:message_kind())
      end)

    it("keeps the notice on pause() without a message, replaces on"
      .. " pause('text'), and keeps across continue()", function()
        K.reset({ ["main.lua"] = [[
compy.screen.showNotice("Keep at pause")
function love.update() end
pause()
]] })
        K.start()
        K.frame()
        assert.same("inspect", K.app_state())
        assert.same("Keep at pause", notice())
        assert.same("notice", K.cc.input:message_kind())

        run('compy.screen.showNotice("Carry on"); continue()')
        assert.same("running", K.app_state())
        assert.same("Carry on", notice())
        K.keys("lctrl", "q")

        K.reset({ ["main.lua"] = [[
compy.screen.showNotice("Old notice")
function love.update() end
pause("Newer pause")
]] })
        K.start()
        K.frame()
        assert.same("inspect", K.app_state())
        assert.same("Newer pause", notice())
        K.keys("lctrl", "q")
      end)

    it("clears on stop (Ctrl+Q and stop()), natural end, reset(),"
      .. " restart, and a new accepted run", function()
        -- Ctrl+Q
        K.reset({ ["main.lua"] = recorder()
          .. 'compy.screen.showNotice("Gone on Q")\n' })
        K.start()
        assert.same("Gone on Q", notice())
        K.keys("lctrl", "q")
        assert.is_false(K.cc.input:has_error())

        -- stop()
        K.reset({ ["main.lua"] = recorder()
          .. 'compy.screen.showNotice("Gone on stop")\n' })
        K.start()
        assert.same("Gone on stop", notice())
        env().stop()
        assert.is_false(K.cc.input:has_error())

        -- natural end
        K.reset({ ["main.lua"] =
          'compy.screen.showNotice("Gone on end")\n' })
        K.start()
        assert.is_false(K.cc.run_live)
        assert.is_false(K.cc.input:has_error())

        -- reset()
        K.reset()
        env().compy.screen.showNotice("Gone on reset")
        assert.same("Gone on reset", notice())
        K.cc:reset()
        assert.is_false(K.cc.input:has_error())

        -- restart (called directly so only restart's own restore
        -- can clear it)
        K.reset({ ["main.lua"] = recorder() })
        K.start()
        env().compy.screen.showNotice("Gone on restart")
        assert.same("Gone on restart", notice())
        K.cc:restart()
        assert.is_false(K.cc.input:has_error())
        K.keys("lctrl", "q")

        -- new accepted run from idle clears before main.lua runs;
        -- a refused run keeps the notice
        K.reset({ ["main.lua"] = "function love.update() end\n" })
        env().compy.screen.showNotice("Idle notice")
        K.cc:run_project("no_such_project")
        assert.same("Idle notice", notice())
        K.cc:run_project()
        assert.is_false(K.cc.input:has_error())
        K.keys("lctrl", "q")
      end)

    for _, args in ipairs({
      "",
      "'a', 'b'",
      "'a', nil",
      "nil",
      "42",
      "{ }",
      "true",
    }) do
      it("refuses showNotice(" .. args .. ") on the calling line"
        .. " and changes nothing", function()
          K.reset({ ["main.lua"] = "local a = 1\nlocal b = 2\n"
            .. "compy.screen.showNotice(" .. args .. ")\n" })
          K.start()
          assert.same("ready", K.app_state())
          local text = K.console_text()
          assert.truthy(text:find(
            "L3:compy.screen.showNotice: expects one string", 1, true),
            text)
          -- empty band stays empty on a bad call
          assert.is_false(K.cc.input:has_error())
          local f = assert(loadstring(
            "compy.screen.showNotice(" .. args .. ")"))
          setfenv(f, env())
          local ok, err = pcall(f)
          assert.is_false(ok)
          assert.truthy(err:find(
            "compy.screen.showNotice: expects one string", 1, true),
            err)
          assert.is_false(K.cc.input:has_error())
          -- existing notice stays intact on a bad call
          env().compy.screen.showNotice("Intact")
          ok, err = pcall(f)
          assert.is_false(ok)
          assert.truthy(err:find(
            "compy.screen.showNotice: expects one string", 1, true),
            err)
          assert.same("Intact", notice())
          assert.same("notice", K.cc.input:message_kind())
        end)
    end
  end)
end)
