-- The key card's gate (IS3.16, the review's rounds 4 to 6): a
-- key's press is passed on only while no card shows, and the
-- key's repeats and release follow its press. A release is
-- passed on exactly for a press that was; a repeat for a press
-- that was, and only while no card shows; text only while no
-- card shows. So a program behind the console's card sees a
-- release exactly for each press it saw, and no repeat or
-- release of a key whose press it did not see. Text carries no
-- key: a key pressed under the card and held after it types
-- its repeats, the known limit. Events through the production
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
    log[#log + 1] = { "text", t, K.cc:card_shows() }
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

--- the key events alone, without text
local function keys_of(list)
  local out = { }
  for _, e in ipairs(list) do
    if not e:find("^text ") then out[#out + 1] = e end
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

    it("has no key event after the card: Space, its text "
        .. "before the repeat", function()
      local log = program()
      press("f1")
      text(" ")
      press("space")
      release("f1")
      rep("space")
      rep("space")
      release("space")
      assert.same({ }, keys_of(seen(log)))
    end)

    it("has no key event after the card: keypad 1", function()
      local log = program()
      press("f1")
      press("kp1")
      release("f1")
      rep("kp1")
      release("kp1")
      assert.same({ }, keys_of(seen(log)))
    end)
  end)

  -- the review's round 6: text is held back only while the
  -- card shows, so typing after it arrives, a key from under
  -- the card held or not
  describe("text after the card", function()
    it("arrives with Shift held from under the card", function()
      local log = program()
      press("f1")
      press("lshift")
      release("f1")
      text("A")
      press("a")
      release("a")
      release("lshift")
      assert.same({ "text A", "press a", "release a" },
        seen(log))
    end)

    it("arrives while Space pressed under the card is held",
      function()
        local log = program()
        press("f1")
        press("space")
        release("f1")
        text("a")
        press("a")
        release("a")
        release("space")
        assert.same({ "text a", "press a", "release a" },
          seen(log))
      end)

    it("is held back while the card shows", function()
      local log = program()
      press("f1")
      text("a")
      press("a")
      release("a")
      release("f1")
      assert.same({ }, seen(log))
    end)
  end)

  -- the reset that always works: once Escape goes down with
  -- Ctrl held, the exit is owed and comes on Escape's release,
  -- whatever is held by then, the card up or not
  describe("Ctrl+Escape", function()
    local ORDERS = {
      ["Escape released first"] = { "lctrl", "escape", "-escape",
        "-lctrl" },
      ["Ctrl released first"] = { "lctrl", "escape", "-lctrl",
        "-escape" },
    }
    for name, steps in pairs(ORDERS) do
      for _, card in ipairs({ false, true }) do
        it("quits, " .. name .. (card and ", under the card" or ""),
          function()
            program()
            if card then
              press("f1")
              assert.is_true(K.cc:card_shows())
            end
            F.quits()
            for _, st in ipairs(steps) do
              if st:sub(1, 1) == "-" then
                release(st:sub(2))
              else
                press(st)
              end
            end
            assert.same(1, #F.quits())
            if card then release("f1") end
          end)
      end
    end

    it("does not quit for Escape pressed before Ctrl", function()
      program()
      F.quits()
      press("escape")
      press("lctrl")
      release("escape")
      release("lctrl")
      assert.same(0, #F.quits())
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
        -- closes it; a repeat needs it open
        local open = { }
        local trace = table.concat(steps, ", ")
        for _, e in ipairs(log) do
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
              -- text carries no key: it goes on only while no
              -- card shows
              assert.is_false(e[3], trace)
            end
          end
        end
        assert.same({ }, open, trace)
        assert.is_number(run)
      end
    end)
end)
