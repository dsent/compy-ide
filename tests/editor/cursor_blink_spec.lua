-- The text cursor's blink (H-NFR4.4), as the `blink` setting
-- asks: shown for `duty` of each `period`, hidden for the
-- rest, and shown for one whole period after a key press, a
-- typed character or a click, the cycle restarted. Time is
-- the frames' (K.frame): the blink has no timer of its own.
-- What shows is read from the real draw (K.screen).

local K = require("tests.helpers.editor_keys")
local F = require("tests.helpers.input_fixture")

local PERIOD, DUTY = 0.6, 0.5
-- a frame, and less than any phase
local TICK = 0.01

local function cfg()
  return K.cc.view.cfg.view
end

local function same_colour(a, b)
  for i = 1, 3 do
    if 0.001 <= math.abs((a[i] or 0) - (b[i] or 0)) then
      return false
    end
  end
  return true
end

--- Whether a cursor is among what a field drew: its block,
--- or its bar past a full row.
local function has_cursor(log, from)
  local c = cfg()
  for i = from or 1, #log do
    local e = log[i]
    local own = same_colour(e.colour, c.colors.input.cursor)
    local block = e.fill and e.w == c.fw and e.h == c.fh
    if own and (block or e.text == "|") then
      return true
    end
  end
  return false
end

--- Whether the screen shows a cursor.
local function shown()
  return has_cursor(K.screen().field_log)
end

--- Let `seconds` pass, a frame at a time.
local function pass(seconds)
  local n = math.floor(seconds / TICK + 0.5)
  for _ = 1, n do
    K.frame(TICK)
  end
end

--- From a key press on: shown for a whole period, then
--- shown for the duty of each period and hidden for its rest.
--- @param see fun(): boolean?  what tells whether the cursor
---   shows, the screen's own when omitted
local function blinks(see)
  see = see or shown
  -- a key's own frame has passed (K.keys): shown at once
  assert.is_true(see())
  -- past the duty of the first period: still shown
  pass(DUTY * PERIOD + 2 * TICK)
  assert.is_true(see())
  -- and just before the whole period is over
  pass(PERIOD - DUTY * PERIOD - 4 * TICK)
  assert.is_true(see())
  -- the second period: its duty shown
  pass(4 * TICK)
  assert.is_true(see())
  pass(DUTY * PERIOD - 4 * TICK)
  assert.is_true(see())
  -- and its rest hidden
  pass(4 * TICK)
  assert.is_false(see())
  pass(PERIOD - DUTY * PERIOD - 4 * TICK)
  assert.is_false(see())
  -- the third period: shown again
  pass(4 * TICK)
  assert.is_true(see())
  pass(DUTY * PERIOD)
  assert.is_false(see())
end

describe("the text cursor's blink #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(function()
    cfg().blink = nil
    K.cleanup()
  end)

  before_each(function()
    K.reset({
      ["main.lua"] = "x = 1\n",
      ["a.txt"] = "one\n"
    })
    cfg().blink = {
      enable = true,
      period = PERIOD,
      duty = DUTY
    }
  end)

  it("in the file editor: shown a period after a key, then "
      .. "on for the duty and off for the rest", function()
    K.open()
    K.browse_to_end()
    K.type("ab")
    blinks()
  end)

  it("a cursor move restarts it, shown", function()
    K.open()
    K.browse_to_end()
    K.type("ab")
    pass(PERIOD + DUTY * PERIOD + 2 * TICK)
    assert.is_false(shown())
    K.keys("left")
    blinks()
  end)

  it("a key that changes nothing restarts it too", function()
    K.open()
    K.browse_to_end()
    K.type("ab")
    pass(PERIOD + DUTY * PERIOD + 2 * TICK)
    assert.is_false(shown())
    -- at the draft's end, Right moves nothing
    local before = { K.cursor() }
    K.keys("right")
    assert.same(before, { K.cursor() })
    assert.is_true(shown())
  end)

  it("stays shown through key presses closer than a period",
      function()
    K.open()
    K.browse_to_end()
    for i = 1, 6 do
      K.type(("abcdef"):sub(i, i))
      -- nine tenths of a period to the next key, looked at
      -- every few frames
      for _ = 1, 9 do
        pass(PERIOD / 10 - TICK / 9)
        assert.is_true(shown(), "after key " .. i)
      end
    end
    assert.same("abcdef", K.draft())
  end)

  it("the bar past a full row blinks as the block does",
      function()
    K.open("a.txt")
    K.browse_to_end()
    K.type(string.rep("x", 64))
    assert.same({
      1,
      65
    }, { K.cursor() })
    blinks()
  end)

  it("in the console", function()
    K.type("ab")
    blinks()
  end)

  it("in a project's input field", function()
    -- the fixture's widget has no view of its own: give it
    -- the field's, as a run does
    local widget = F.show_widget({ text = "hey" })
    local view = UserInputView(cfg(), widget)
    widget:init_view(view)
    local renders = 0
    local render = view.render
    view.render = function(...)
      renders = renders + 1
      return render(...)
    end
    -- A project's field keeps what it last rendered: what
    -- it shows is its last render's, which the mark tells
    -- from the console's own field drawn before it.
    local on_canvas = false
    local function draw()
      view.canvas:renderTo(function()
        love.graphics.print("@project", 0, 0)
      end)
      view:draw()
    end
    local function see()
      local log = K.screen(draw).field_log
      local mark
      for i, e in ipairs(log) do
        if e.text == "@project" then
          mark = i
        end
      end
      if mark < #log then
        on_canvas = has_cursor(log, mark + 1)
      end
      return on_canvas
    end
    K.keys("lshift")
    blinks(see)
    -- it rendered at each of the blink's three turns, and at
    -- its first draw: not at every frame drawn
    assert.is_true(3 <= renders and renders <= 4,
      tostring(renders))
  end)

  it("a click restarts it", function()
    -- in the console: the fixture's configuration has no
    -- section for the editor's mouse
    K.type("ab")
    pass(PERIOD + DUTY * PERIOD + 2 * TICK)
    assert.is_false(shown())
    F.session.mousepressed(10, 10, 1, false, 1)
    assert.is_true(shown())
    F.session.mousereleased(10, 10, 1, false, 1)
  end)

  it("with blinking off the cursor is steady", function()
    cfg().blink.enable = false
    K.open()
    K.browse_to_end()
    K.type("ab")
    for _ = 1, 30 do
      pass(PERIOD / 10)
      assert.is_true(shown())
    end
  end)

  it("with no blink setting the cursor is steady", function()
    cfg().blink = nil
    K.type("ab")
    for _ = 1, 30 do
      pass(PERIOD / 10)
      assert.is_true(shown())
    end
  end)
end)
