-- The key card's gate (IS3.16, the review's rounds 4 and 5): a
-- key's press is passed on only while no card shows, and the
-- key's repeats and release follow its press. A release is
-- passed on exactly for a press that was; a repeat for a press
-- that was, and only while no card shows; text is passed on
-- only while no card shows and no key is down whose press was
-- not. So a program behind the console's card sees a release
-- exactly for each press it saw, and no repeat or text of a key
-- whose press it did not see. Events through the production
-- gateway (love.handlers, F.session).

local F = require("tests.helpers.input_fixture")
local K = require("tests.helpers.editor_keys")

--- A program behind the console: its hooks record every key
--- and text event and fall through, so that F1 reaches the
--- console and brings its card up.
--- @return table log --- { kind, key-or-text }
local function program()
  K.reset()
  local input = F.activate_project()
  local log = { }
  input.hooks.keypressed = function(k, _, isr)
    log[#log + 1] = { isr and "repeat" or "press", k }
  end
  input.hooks.keyreleased = function(k)
    log[#log + 1] = { "release", k }
  end
  input.hooks.textinput = function(t)
    log[#log + 1] = { "text", t }
  end
  return log
end

local H = function() return love.handlers end
local function press(k) F.session.press(k) end
local function rep(k) F.session.repeat_press(k) end
local function release(k) F.session.release(k) end
local function text(t) H().textinput(t) end

--- the log without F1's own events
local function seen(log)
  local out = { }
  for _, e in ipairs(log) do
    if e[2] ~= "f1" then out[#out + 1] = e[1] .. " " .. e[2] end
  end
  return out
end

describe("the key card's gate #input", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  it("brings the console's card up over the program", function()
    program()
    press("f1")
    assert.is_true(K.cc:card_shows())
    release("f1")
  end)

  describe("a key pressed before the card", function()
    it("gets its release under the card, its repeat there "
        .. "dropped", function()
      local log = program()
      press("x")
      press("f1")
      rep("x")
      release("x")
      release("f1")
      assert.same({ "press x", "release x" }, seen(log))
    end)

    it("repeats again once F1 is released, and gets its "
        .. "release", function()
      local log = program()
      press("x")
      press("f1")
      rep("x")
      release("f1")
      rep("x")
      release("x")
      assert.same({ "press x", "repeat x", "release x" },
        seen(log))
    end)
  end)

  describe("a key pressed under the card", function()
    it("has no release, then or after the card (round 4)",
      function()
        local log = program()
        press("f1")
        press("x")
        release("x")
        release("f1")
        press("f1")
        press("x")
        release("f1")
        release("x")
        assert.same({ }, seen(log))
      end)

    it("sends no text after the card: Space, its text before "
        .. "the repeat", function()
      local log = program()
      press("f1")
      text(" ")
      press("space")
      release("f1")
      text(" ")
      rep("space")
      text(" ")
      rep("space")
      release("space")
      assert.same({ }, seen(log))
      -- pressed afresh, it types
      text(" ")
      press("space")
      release("space")
      assert.same({ "text  ", "press space", "release space" },
        seen(log))
    end)

    it("sends no text after the card: keypad 1", function()
      local log = program()
      press("f1")
      text("1")
      press("kp1")
      release("f1")
      rep("kp1")
      text("1")
      release("kp1")
      assert.same({ }, seen(log))
    end)

    -- the card needs a bare F1, so Shift comes after it
    it("sends no text after the card: Shift+1", function()
      local log = program()
      press("f1")
      press("lshift")
      text("!")
      press("1")
      release("f1")
      text("!")
      rep("1")
      release("1")
      release("lshift")
      assert.same({ }, seen(log))
    end)
  end)

  -- random interleavings: the invariant, whatever the order
  it("keeps a program's keys whole over random interleavings",
    function()
      local KEYS = { a = "a", space = " " }
      local NAMES = { "a", "space" }
      math.randomseed(20261116)
      for run = 1, 300 do
        local log = program()
        local down = { }
        local f1 = false
        local steps = { }
        local function act(what, k)
          steps[#steps + 1] = what .. " " .. (k or "")
          if what == "f1" then
            if f1 then release("f1") else press("f1") end
            f1 = not f1
          elseif what == "down" then
            if math.random() < 0.5 then text(KEYS[k]) end
            press(k)
            if math.random() < 0.5 then text(KEYS[k]) end
            down[k] = true
          elseif what == "repeat" then
            if math.random() < 0.5 then text(KEYS[k]) end
            rep(k)
            if math.random() < 0.5 then text(KEYS[k]) end
          else
            release(k)
            down[k] = nil
          end
        end
        for _ = 1, 12 do
          local r = math.random(4)
          if r == 1 then
            act("f1")
          else
            local k = NAMES[math.random(2)]
            if not down[k] then
              act("down", k)
            elseif r == 2 then
              act("repeat", k)
            else
              act("up", k)
            end
          end
        end
        for _, k in ipairs(NAMES) do
          if down[k] then act("up", k) end
        end
        if f1 then act("f1") end
        -- the program's view: a press opens a key, a release
        -- closes it; a repeat and a key's text need it open
        local open, glyph_of = { }, { }
        for k, t in pairs(KEYS) do glyph_of[t] = k end
        local trace = table.concat(steps, ", ")
        for i, e in ipairs(log) do
          local kind, x = e[1], e[2]
          if x ~= "f1" then
            if kind == "press" then
              assert.is_nil(open[x], trace)
              open[x] = true
            elseif kind == "repeat" then
              assert.is_true(open[x] == true, trace)
            elseif kind == "release" then
              assert.is_true(open[x] == true, trace)
              open[x] = nil
            else
              -- a key's text comes beside its own key event:
              -- its press is open now, or opens next
              local k = glyph_of[x]
              local nxt = log[i + 1]
              local opens = nxt and nxt[1] == "press"
                  and nxt[2] == k
              assert.is_true(open[k] == true or opens == true,
                trace)
            end
          end
        end
        assert.same({ }, open, trace)
        assert.is_number(run)
      end
    end)
end)
