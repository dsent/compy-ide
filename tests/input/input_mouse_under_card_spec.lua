-- The mouse is ignored while the key card shows (the
-- maintainer's ruling of November 14, late): in the file
-- editor, in the console, and over a program behind the
-- console's card, no press, release, move, wheel, derived
-- click or touch does anything. A button's release goes where
-- its press went, and a touch's where its start went, by its
-- id, so that no route is left with half a click. Events
-- through the production gateway (love.handlers, F.session,
-- the K helper).

local F = require("tests.helpers.input_fixture")
local K = require("tests.helpers.editor_keys")
local Layout = require("view.layout")

--- the point of column `col` on the field's last row
local function on_field(col)
  local v = F.cfg.view
  local bottom = love.graphics.getHeight() - Layout(v).bottom
  return v.fw * (col - 1 + 0.2), bottom - v.fh * 0.5
end

--- every kind of mouse event, at the field's first column
local function every_mouse_event()
  local x, y = on_field(1)
  F.session.mousepressed(x, y, 1, false, 1)
  F.session.mousemoved(x + 40, y, 40, 0, false)
  F.session.mousereleased(x + 40, y, 1, false, 1)
  F.session.mousepressed(x, y, 1, false, 1)
  F.session.mousereleased(x, y, 1, false, 1)
  love.handlers.wheelmoved(0, 1)
  -- the derived single click, after its pairing time
  K.frame(0.5)
end

local function click(col)
  local x, y = on_field(col)
  F.session.mousepressed(x, y, 1, false, 1)
  F.session.mousereleased(x, y, 1, false, 1)
  K.frame()
end

--- A program that idles behind the console with a hook for
--- every pointer event, recording them in LOG
local IDLES = table.concat({
  "LOG = {}",
  "local function note(name)",
  "  return function() LOG[#LOG + 1] = name end",
  "end",
  "for _, n in ipairs({ 'mousepressed', 'mousereleased',",
  "  'mousemoved', 'wheelmoved', 'singleclick',",
  "  'doubleclick' }) do",
  "  compy.input.hooks[n] = note(n)",
  "end",
}, "\n") .. "\n"

local function log()
  return K.cc:get_project_env().LOG
end

--- A program that can act owns all input, F1 too (November 17):
--- the console's card comes up behind a program only while it
--- is paused. Run IDLES with an update, and pause it.
local function paused(program)
  K.reset({ ["main.lua"] = program .. "function love.update() end\n" })
  K.start()
  K.keys("lctrl", "pause")
  K.frame()
  if K.app_state() == "snapshot" then K.cc:suspend() end
  assert.same("inspect", K.app_state())
end

describe("the mouse under the key card #input", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(function()
    K.cc.cfg.editor = nil
    K.cleanup()
  end)

  it("moves no cursor in the file editor's draft", function()
    K.reset({ ["notes.txt"] = "" })
    K.cc.cfg.editor = { mouse_enabled = true }
    K.open("notes.txt")
    K.type("abcd")
    K.hold("f1")
    assert.is_not_nil(K.key_card())
    every_mouse_event()
    K.release("f1")
    assert.same({ 1, 5 }, { K.cursor() })
    assert.same("abcd", K.draft())
    assert.is_nil(K.message())
    -- the card away, a click places the cursor again
    click(2)
    assert.same({ 1, 2 }, { K.cursor() })
  end)

  it("moves no cursor in the console's draft", function()
    K.reset()
    K.type("abcd")
    K.hold("f1")
    assert.is_not_nil(K.key_card())
    every_mouse_event()
    K.release("f1")
    assert.same({ 1, 5 }, { K.cc.input:get_cursor_pos() })
    click(2)
    assert.same({ 1, 2 }, { K.cc.input:get_cursor_pos() })
  end)

  --- turned around on November 17: a program that can act owns
  --- all input, so no console card comes up over it
  it("brings no card over a program that can act: F1 and the"
    .. " mouse are its own", function()
      K.reset({ ["main.lua"] = IDLES })
      K.start()
      assert.same("ready", K.app_state())
      assert.is_true(K.cc.run_live)
      K.hold("f1")
      assert.is_nil(K.key_card())
      click(3)
      K.release("f1")
      K.frame(0.5)
      assert.same({ "mousepressed", "mousereleased",
        "singleclick" }, log())
    end)

  it("reaches no paused program behind the console's card",
    function()
      K.reset({ ["main.lua"] = IDLES
          .. "function love.update() end\n" })
      K.start()
      assert.same("running", K.app_state())
      K.keys("lctrl", "pause")
      K.frame()
      -- the fixture's graphics take no screenshot, whose
      -- callback finishes the pause on the device
      if K.app_state() == "snapshot" then K.cc:suspend() end
      assert.same("inspect", K.app_state())
      K.type("ab")
      local before = { K.cc.input:get_cursor_pos() }
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      every_mouse_event()
      K.release("f1")
      assert.same({ }, log())
      assert.same(before, { K.cc.input:get_cursor_pos() })
    end)

  describe("touch", function()
    local H = function() return love.handlers end
    --- a touch's press, move and release, by id
    local function touch(id, phase)
      local x, y = on_field(2)
      if phase ~= "release" and phase ~= "move" then
        H().touchpressed(id, x, y, 0, 0, 1)
      end
      if phase == nil or phase == "move" then
        H().touchmoved(id, x + 10, y, 10, 0, 1)
      end
      if phase ~= "press" and phase ~= "move" then
        H().touchreleased(id, x + 10, y, 0, 0, 1)
      end
    end

    local TOUCHES = table.concat({
      "TOUCHES = {}",
      "for _, n in ipairs({ 'touchpressed', 'touchmoved',",
      "  'touchreleased' }) do",
      "  compy.input.hooks[n] = function()",
      "    TOUCHES[#TOUCHES + 1] = n",
      "  end",
      "end",
    }, "\n") .. "\n"

    local function touches()
      return K.cc:get_project_env().TOUCHES
    end

    --- count the touch events a field controller is handed
    local function counting(field)
      local n = 0
      for _, m in ipairs({ "touchpressed", "touchmoved",
        "touchreleased" }) do
        field[m] = function() n = n + 1 end
      end
      return function() return n end
    end

    it("reaches no paused program behind the console's card",
      function()
        paused(IDLES .. TOUCHES)
        K.hold("f1")
        assert.is_not_nil(K.key_card())
        touch("t1")
        K.release("f1")
        assert.same({ }, touches())
      end)

    --- the card comes up behind a program only while it is
    --- paused (November 17), and a paused program gets no touch,
    --- begun under the card or before it
    it("a touch begun under the card or before it reaches no"
        .. " paused program", function()
      paused(IDLES .. TOUCHES)
      K.hold("f1")
      touch("t1", "press")
      K.release("f1")
      touch("t1", "move")
      touch("t1", "release")
      touch("t2", "press")
      K.hold("f1")
      touch("t2", "move")
      touch("t2", "release")
      K.release("f1")
      assert.same({ }, touches())
    end)

    --- p2: a release goes only to the receiver of its touch's
    --- start, the console's own field included
    it("gives the console's field the release of a touch begun"
      .. " before the card", function()
        K.reset()
        local ends = 0
        local field = K.cc.input
        local was = field.touchreleased
        field.touchreleased = function(...)
          ends = ends + 1
          return was(...)
        end
        finally(function() field.touchreleased = was end)
        touch("t1", "press")
        K.hold("f1")
        assert.is_not_nil(K.key_card())
        touch("t1", "release")
        K.release("f1")
        assert.same(1, ends)
      end)

    it("reaches not the console's field under its card", function()
      K.reset()
      local count = counting(K.cc.input)
      K.hold("f1")
      assert.is_not_nil(K.key_card())
      touch("t1")
      K.release("f1")
      assert.same(0, count())
      -- the card away, the field is handed the touch
      touch("t2")
      assert.same(3, count())
    end)

    it("reaches not the file editor's field: its touch is off, "
        .. "and under the card held back with it on too",
      function()
        K.reset({ ["notes.txt"] = "" })
        K.open("notes.txt")
        local count = counting(K.ed.input)
        -- as main.lua ships it
        K.cc.cfg.editor = { touch_enabled = false }
        touch("t1")
        assert.same(0, count())
        K.cc.cfg.editor = { touch_enabled = true }
        K.hold("f1")
        assert.is_not_nil(K.key_card())
        touch("t2")
        K.release("f1")
        assert.same(0, count())
        touch("t3")
        assert.same(3, count())
      end)
  end)

  --- the card comes up behind a program only while it is paused
  --- (November 17): the console is the receiver then, and what it
  --- is handed is recorded (p1: the paused program's empty log
  --- alone observed nothing)
  describe("leaves no half click", function()
    --- the button events the console's field is handed
    local function console_mouse()
      local seen = { }
      local field = K.cc.input
      local press, release = field.mousepressed, field.mousereleased
      field.mousepressed = function(...)
        seen[#seen + 1] = "mousepressed"
        return press(...)
      end
      field.mousereleased = function(...)
        seen[#seen + 1] = "mousereleased"
        return release(...)
      end
      finally(function()
        field.mousepressed, field.mousereleased = press, release
      end)
      return seen
    end

    it("a press under the card holds back its release after "
        .. "the card", function()
      paused(IDLES)
      local seen = console_mouse()
      local x, y = on_field(1)
      K.hold("f1")
      F.session.mousepressed(x, y, 1, false, 1)
      K.release("f1")
      F.session.mousereleased(x, y, 1, false, 1)
      K.frame(0.5)
      assert.same({ }, seen)
      assert.same({ }, log())
    end)

    --- p2: a release goes only to the receiver of its press: a
    --- button the program got the press of, released while the
    --- console has the pointer, reaches neither
    it("a press the program got gives the console no release",
      function()
        K.reset({ ["main.lua"] = IDLES .. "function love.update() end\n" })
        K.start()
        local x, y = on_field(1)
        F.session.mousepressed(x, y, 1, false, 1)
        assert.same({ "mousepressed" }, log())
        K.keys("lctrl", "pause")
        K.frame()
        if K.app_state() == "snapshot" then K.cc:suspend() end
        assert.same("inspect", K.app_state())
        local seen = console_mouse()
        K.hold("f1")
        F.session.mousereleased(x, y, 1, false, 1)
        K.release("f1")
        assert.same({ }, seen)
        assert.same({ "mousepressed" }, log())
      end)

    it("a press before the card gets its release under it, at"
        .. " the console, not the paused program", function()
        paused(IDLES)
        local seen = console_mouse()
        local x, y = on_field(1)
        F.session.mousepressed(x, y, 1, false, 1)
        K.hold("f1")
        assert.is_not_nil(K.key_card())
        F.session.mousereleased(x, y, 1, false, 1)
        K.release("f1")
        assert.same({ "mousepressed", "mousereleased" }, seen)
        assert.same({ }, log())
      end)
  end)
end)

-- p3: a pointer's release goes where its press went when the
-- route itself goes back to the console, the press first or the
-- release
describe("a pointer across the end of a program's acting #input",
  function()
    setup(K.setup)
    teardown(K.teardown)
    after_each(K.cleanup)

    --- the button and touch events the console's field is handed
    local function console_events()
      local seen = { }
      local field = K.cc.input
      local saved = { }
      for _, m in ipairs({ "mousepressed", "mousereleased",
        "touchpressed", "touchreleased" }) do
        saved[m] = field[m]
        field[m] = function(...)
          seen[#seen + 1] = m
          return saved[m](...)
        end
      end
      finally(function()
        for m, f in pairs(saved) do field[m] = f end
      end)
      return seen
    end

    --- such a program ends at its last line (stage 4 of the
    --- canvas plan)
    it("gives the console both halves of the first click and touch"
      .. " after a program that could do nothing more", function()
        K.reset({ ["main.lua"] = "X = 1\n" })
        K.start()
        assert.is_false(K.cc.run_live)
        local seen = console_events()
        local x, y = on_field(1)
        F.session.mousepressed(x, y, 1, false, 1)
        F.session.mousereleased(x, y, 1, false, 1)
        local H = love.handlers
        H.touchpressed("t1", x, y, 0, 0, 1)
        H.touchreleased("t1", x, y, 0, 0, 1)
        assert.same({ "mousepressed", "mousereleased",
          "touchpressed", "touchreleased" }, seen)
      end)

    it("gives the console no release of a press the program got as"
      .. " it stopped acting", function()
        K.reset({ ["main.lua"] = "compy.input.hooks.mousepressed ="
          .. " function() compy.input.hooks.mousepressed = nil end\n"
          .. "compy.input.hooks.touchpressed ="
          .. " function() compy.input.hooks.touchpressed = nil end\n" })
        K.start()
        local seen = console_events()
        local x, y = on_field(1)
        F.session.mousepressed(x, y, 1, false, 1)
        local H = love.handlers
        H.touchpressed("t1", x, y, 0, 0, 1)
        F.session.mousereleased(x, y, 1, false, 1)
        H.touchreleased("t1", x, y, 0, 0, 1)
        assert.same({ }, seen)
      end)
  end)

-- p4: a press during which the program stops or is replaced
-- (a request its hook makes) went to the program: its release
-- goes to no one, neither the console nor the next run
describe("a pointer across a stop or a run its press asks for #input",
  function()
    setup(K.setup)
    teardown(K.teardown)
    after_each(K.cleanup)

    for _, call in ipairs({ "stop()", "run()" }) do
      it("gives no one the release when the press hook calls "
        .. call, function()
          K.reset({ ["main.lua"] = "RELEASES = 0\n"
            .. "compy.input.hooks.mousereleased = function()"
            .. " RELEASES = RELEASES + 1 end\n"
            .. "compy.input.hooks.touchreleased = function()"
            .. " RELEASES = RELEASES + 1 end\n"
            .. "compy.input.hooks.mousepressed = function() "
            .. call .. " end\n"
            .. "compy.input.hooks.touchpressed = function() "
            .. call .. " end\n" })
          K.start()
          local field = K.cc.input
          local ends = 0
          local was_m, was_t = field.mousereleased, field.touchreleased
          field.mousereleased = function(...)
            ends = ends + 1
            return was_m(...)
          end
          field.touchreleased = function(...)
            ends = ends + 1
            return was_t(...)
          end
          finally(function()
            field.mousereleased, field.touchreleased = was_m, was_t
          end)
          local x, y = on_field(1)
          F.session.mousepressed(x, y, 1, false, 1)
          F.session.mousereleased(x, y, 1, false, 1)
          assert.same(0, ends)
          assert.same(0, K.cc:get_project_env().RELEASES or 0)
          --- the touch from a program of its own: the stop has
          --- given the console the input
          if call == "stop()" then K.start() end
          local H = love.handlers
          H.touchpressed("t1", x, y, 0, 0, 1)
          H.touchreleased("t1", x, y, 0, 0, 1)
          assert.same(0, ends)
          assert.same(0, K.cc:get_project_env().RELEASES or 0)
        end)
    end
  end)

describe("a key across a stop its press asks for #input", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  it("gives the console no release of the key", function()
    K.reset({ ["main.lua"] = "compy.input.hooks.keypressed ="
      .. " function(k) if k == 'x' then stop() end end\n"
      .. "function love.update() end\n" })
    K.start()
    local field = K.cc.input
    local ends = 0
    local was = field.keyreleased
    field.keyreleased = function(...)
      ends = ends + 1
      return was(...)
    end
    finally(function() field.keyreleased = was end)
    F.session.press("x")
    assert.is_false(K.cc.run_live)
    F.session.release("x")
    assert.same(0, ends)
  end)
end)

-- p5: an event raised during a press's own handler is no
-- hand-over of the press: a nested event the console gets, the
-- program having nothing left to act with, does not make the
-- console the press's receiver. A program cannot reach
-- love.handlers; the test hands it NEST, which raises the event
-- as LÖVE would
describe("a press's receiver, decided at its hand-over #input",
  function()
    setup(K.setup)
    teardown(K.teardown)
    after_each(K.cleanup)

    local KINDS = {
      { hook = "keypressed", press = function()
          F.session.press("x")
        end, release = function()
          F.session.release("x")
        end, ends = "keyreleased" },
      { hook = "mousepressed", press = function(x, y)
          F.session.mousepressed(x, y, 1, false, 1)
        end, release = function(x, y)
          F.session.mousereleased(x, y, 1, false, 1)
        end, ends = "mousereleased" },
      { hook = "touchpressed", press = function(x, y)
          love.handlers.touchpressed("t1", x, y, 0, 0, 1)
        end, release = function(x, y)
          love.handlers.touchreleased("t1", x, y, 0, 0, 1)
        end, ends = "touchreleased" },
    }
    for _, kind in ipairs(KINDS) do
      it("keeps the " .. kind.hook .. " the program's", function()
        K.reset({ ["main.lua"] = "compy.input.hooks." .. kind.hook
          .. " = function()\n"
          .. "  compy.input.hooks." .. kind.hook .. " = nil\n"
          .. "  NEST()\n"
          .. "  run()\n"
          .. "end\n" })
        K.start()
        K.cc:get_project_env().NEST = function()
          love.handlers.wheelmoved(0, 0)
        end
        --- the console's field: Controller._defaults is built
        --- anew by the run() the hook asks for
        local field = K.cc.input
        local ends = 0
        local was = field[kind.ends]
        field[kind.ends] = function(...)
          ends = ends + 1
          return was(...)
        end
        finally(function() field[kind.ends] = was end)
        local x, y = on_field(1)
        kind.press(x, y)
        kind.release(x, y)
        assert.same(0, ends)
      end)
    end

    -- one record of receivers for keys, buttons and touches: a
    -- release a paused program is owed comes at its continue(), the
    -- button's and the touch's as the key's
    it("gets its release at continue(), the button's and the"
      .. " touch's", function()
        K.reset({ ["main.lua"] = "LOG = { }\n"
          .. "for _, e in ipairs({ 'mousepressed', 'mousereleased',"
          .. " 'touchpressed', 'touchreleased' }) do\n"
          .. "  compy.input.hooks[e] = function()"
          .. " LOG[#LOG + 1] = e end\nend\n"
          .. "function love.update() end\n" })
        K.start()
        local x, y = on_field(1)
        local H = love.handlers
        F.session.mousepressed(x, y, 1, false, 1)
        H.touchpressed("t1", x, y, 0, 0, 1)
        K.keys("lctrl", "pause")
        K.frame()
        if K.app_state() == "snapshot" then K.cc:suspend() end
        assert.same("inspect", K.app_state())
        F.session.mousereleased(x, y, 1, false, 1)
        H.touchreleased("t1", x, y, 0, 0, 1)
        local log = K.cc:get_project_env().LOG
        assert.same({ "mousepressed", "touchpressed" }, log)
        K.cc:get_project_env().continue()
        assert.same({ "mousepressed", "touchpressed",
          "mousereleased", "touchreleased" }, log)
      end)

    -- p6: a press's receiver is recorded before its handler runs, so
    -- a release the handler raises itself finds its press; and an
    -- owed release after which the program can act no more is the
    -- last of them
    it("gives a release raised in the press hook to the program",
      function()
        K.reset({ ["main.lua"] = "UPS = 0\n"
          .. "compy.input.hooks.keypressed = function(k)"
          .. " if k == 'x' then NEST() end end\n"
          .. "compy.input.hooks.keyreleased = function(k)"
          .. " if k == 'x' then UPS = UPS + 1 end end\n"
          .. "function love.update() end\n" })
        K.start()
        local env = K.cc:get_project_env()
        env.NEST = function() love.handlers.keyreleased("x", "x") end
        F.session.press("x")
        assert.same(1, env.UPS)
        --- the press is over: its own release finds no receiver
        F.session.release("x")
        assert.same(1, env.UPS)
      end)

    it("delivers no owed release after one leaves the program"
      .. " nothing to act with", function()
        K.reset({ ["main.lua"] = "LOG = { }\n"
          .. "local H = compy.input.hooks\n"
          .. "H.mousepressed = function() end\n"
          .. "H.touchpressed = function() end\n"
          .. "H.touchreleased = function() LOG[#LOG + 1] = 't' end\n"
          .. "H.mousereleased = function()\n"
          .. "  LOG[#LOG + 1] = 'm'\n"
          .. "  for _, e in ipairs({ 'mousepressed', 'touchpressed',"
          .. " 'touchreleased', 'mousereleased' }) do H[e] = nil end\n"
          .. "end\n" })
        K.start()
        local field = K.cc.input
        local ends = 0
        local was = field.touchreleased
        field.touchreleased = function(...)
          ends = ends + 1
          return was(...)
        end
        finally(function() field.touchreleased = was end)
        local x, y = on_field(1)
        local H = love.handlers
        F.session.mousepressed(x, y, 1, false, 1)
        H.touchpressed("t1", x, y, 0, 0, 1)
        H.touchpressed("t2", x, y, 0, 0, 1)
        K.keys("lctrl", "pause")
        K.frame()
        if K.app_state() == "snapshot" then K.cc:suspend() end
        assert.same("inspect", K.app_state())
        F.session.mousereleased(x, y, 1, false, 1)
        H.touchreleased("t1", x, y, 0, 0, 1)
        H.touchreleased("t2", x, y, 0, 0, 1)
        local env = K.cc:get_project_env()
        env.continue()
        assert.same({ "m" }, env.LOG)
        assert.same(0, ends)
      end)
  end)
