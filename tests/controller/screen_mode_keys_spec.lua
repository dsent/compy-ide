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
-- Spec justification (dev testing policy): the full picture
-- shows no field and no status line, so a key path that misses
-- the way back leaves a person on a picture with no sign of how
-- to leave it, and a key that leaks through types into a field
-- no one sees. Both show only on a device.

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
    --- continue(). The frame is set by hand: a program that can
    --- act no more while its pause waits ends at the next event
    --- (its natural end), so no program holds it open here.
    it("leaves the picture alone between a pause's request and the"
      .. " pause", function()
        picture()
        love.state.app_state = "snapshot"
        finally(function() love.state.app_state = "ready" end)
        F.session.press("z")
        F.session.release("z")
        F.session.mousepressed(10, 10, 1, false, 1)
        F.session.mousereleased(10, 10, 1, false, 1)
        love.handlers.touchpressed("t1", 10, 10, 0, 0, 1)
        love.handlers.touchreleased("t1", 10, 10, 0, 0, 1)
        assert.same("picture", mode())
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
    it("names text and combined", function()
      K.reset()
      assert.is_true(has(status_texts(), "text"))
      K.keys("f12")
      local texts = status_texts()
      assert.is_true(has(texts, "combined"))
      assert.is_false(has(texts, "text"))
    end)

    it("keeps the mode's end in one place, whatever the position"
      .. " shows", function()
        K.reset()
        local fw = F.cfg.view.fw
        local function mode_end(word)
          for _, t in ipairs(K.screen().field) do
            if t.text == word and t.y < F.cfg.view.fh then
              return t.x + #word * fw
            end
          end
        end
        local at_start = mode_end("text")
        assert.is_not_nil(at_start)
        K.type(string.rep("y", 40))
        assert.same(at_start, mode_end("text"))
        K.keys("f12")
        assert.same(at_start, mode_end("combined"))
        K.keys("f12")
        K.keys("f12")
        -- behind a running program that owns the input: the bare
        -- line, with no position
        K.reset({ ["main.lua"] = recorder() })
        K.start()
        assert.is_true(K.cc:fieldless())
        assert.same(at_start, mode_end("text"))
      end)

    it("is not drawn in the full picture", function()
      K.reset()
      K.keys("f12")
      K.keys("f12")
      assert.same({ }, status_texts())
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
end)
