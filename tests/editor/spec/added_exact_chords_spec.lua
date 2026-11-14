-- Every chord is its own key (the maintainer's ruling of
-- November 14, 2026): in each of the file editor's states a
-- key with a modifier its table does not bind does nothing,
-- and the key card lists exactly the table's keys. The card
-- suspends the reserved chords in the editor alone, and a
-- click on a block no longer browses (PR #28, D-MOUSE-BROWSE).
-- Keys only, through tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local F = require("tests.helpers.input_fixture")
local EditorKeys = require("model.editor.editorKeys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it

local FILE = "a = 1\nb = 2\n"

--- Reach `state` on block 1 of FILE.
local REACH = {
  browsing = function() K.browse_to(1) end,
  inserting = function()
    K.browse_to(1)
    K.type("x = 3")
  end,
  replacing = function()
    K.browse_to(1)
    K.keys("f2")
  end,
}

local function reach(state)
  K.reset({ ["main.lua"] = FILE })
  K.open()
  REACH[state]()
  assert.same(state, K.state())
end

--- Everything a key could change, as one value.
local function snapshot()
  return {
    app = K.app_state(),
    file = K.file(),
    draft = K.draft(),
    state = K.state(),
    position = K.position(),
    cursor = { K.cursor() },
    message = K.message(),
    writes = #K.writes(),
  }
end

local MOD_KEYS = { ctrl = "lctrl", alt = "lalt", shift = "lshift" }
local ORDER = { "ctrl", "alt", "shift" }

--- A chord's held keys, for K.keys.
local function keys_of(mods, trigger)
  local ks = { }
  for _, m in ipairs(ORDER) do
    if mods[m] then ks[#ks + 1] = MOD_KEYS[m] end
  end
  ks[#ks + 1] = trigger
  return ks
end

--- @return table mods, string trigger
local function split(chord)
  local mods, trigger = { }, nil
  for part in chord:gmatch("[^+]+") do
    if MOD_KEYS[part] then mods[part] = true else trigger = part end
  end
  return mods, trigger
end

--- the gate's own chords, and the help key: not the tables'
local RESERVED = {
  ["ctrl+escape"] = true, ["ctrl+t"] = true, ["ctrl+q"] = true,
  ["ctrl+pause"] = true, ["ctrl+alt+r"] = true,
  ["ctrl+alt+p"] = true, ["ctrl+alt+shift+p"] = true,
  f10 = true,
}

--- Every chord of `state`'s table with one more modifier,
--- which the table does not bind: { name, keys }.
local function unbound_neighbours(state)
  local out, seen = { }, { }
  local t = EditorKeys.tables[state]
  for chord in pairs(t) do
    local mods, trigger = split(chord)
    for _, m in ipairs(ORDER) do
      if not mods[m] and trigger ~= "f1" then
        local more = { }
        for k in pairs(mods) do more[k] = true end
        more[m] = true
        local name = table.concat(keys_of(more, trigger), "+")
          :gsub("l(%a+)%+", "%1+")
        if not t[name] and not RESERVED[name] and not seen[name]
        then
          seen[name] = true
          out[#out + 1] = { name, keys_of(more, trigger) }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

describe("every chord is its own key #editor #spec", function()
  after_each(K.cleanup)

  describe("a bound key with another modifier", function()
    for _, c in ipairs({
      { "browsing", "Ctrl+Enter", { "lctrl", "return" } },
      { "inserting", "Ctrl+Enter", { "lctrl", "return" } },
      { "replacing", "Ctrl+Enter", { "lctrl", "return" } },
      { "browsing", "Alt+F2", { "lalt", "f2" } },
      { "replacing", "Shift+Escape", { "lshift", "escape" } },
      { "inserting", "Ctrl+Shift+Up", { "lctrl", "lshift", "up" } },
    }) do
      spec_it("IS3.11 Preserve state on refusal: " .. c[2]
          .. " does nothing while " .. c[1], function()
        reach(c[1])
        local before = snapshot()
        K.keys(unpack(c[3]))
        assert.same(before, snapshot())
      end)
    end

    for _, state in ipairs({ "browsing", "inserting",
      "replacing" }) do
      spec_it("IS3.11 Preserve state on refusal: while " .. state
          .. ", every bound key with one more modifier that the "
          .. "table does not bind does nothing", function()
        local chords = unbound_neighbours(state)
        assert.is_true(#chords > 20)
        for _, c in ipairs(chords) do
          reach(state)
          local before = snapshot()
          K.keys(unpack(c[2]))
          assert.same(before, snapshot(), c[1])
        end
      end)
    end
  end)

  describe("the key card", function()
    for _, state in ipairs({ "browsing", "inserting",
      "replacing" }) do
      spec_it("IS3.16 Show the key card: while " .. state
          .. ", the card lists exactly the table's keys with "
          .. "words, the state's own first", function()
        reach(state)
        K.hold("f1")
        local lines = K.key_card()
        K.release("f1")
        local now, other, section = { }, { }, nil
        for col = 0, 1 do
          for _, l in ipairs(lines) do
            local cell = l:sub(col * 32 + 1, col * 32 + 32)
            if cell:find("Keys now", 1, true) then
              section = now
            elseif cell:find("Other keys", 1, true) then
              section = other
            else
              local key = cell:match("^ (%S+)")
              if key then section[key] = true end
            end
          end
        end
        -- F1's label has a space in it
        now["F1"] = nil
        local want_now, want_other = { }, { }
        for _, row in ipairs(EditorKeys:card_rows(state,
          state == "browsing")) do
          local key = row[1]:match("^(%S+)")
          if key ~= "F1" then
            if row[3] then want_now[key] = true
            else want_other[key] = true end
          end
        end
        assert.same(want_now, now)
        assert.same(want_other, other)
      end)
    end
  end)

  describe("the reserved chords under the card", function()
    spec_it("IS3.16 Show the key card: Ctrl+Q waits while the "
        .. "editor's card shows", function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.hold("f1")
      K.keys("lctrl", "q")
      K.release("f1")
      assert.same("editor", K.app_state())
      K.keys("lctrl", "q")
      assert.same("ready", K.app_state())
    end)

    spec_it("IS3.16 Show the key card: Ctrl+Q stops a program "
        .. "while F1 is held over it", function()
      K.reset({ ["main.lua"] = "function love.update() end\n" })
      K.type("run()")
      K.keys("return")
      assert.same("running", K.app_state())
      K.hold("f1")
      K.keys("lctrl", "q")
      K.release("f1")
      assert.same("ready", K.app_state())
      assert.is_false(K.cc.run_live)
    end)
  end)

  -- with the editor's mouse switched on, as it ships
  -- (cfg.editor.mouse_enabled in main.lua)
  describe("the mouse", function()
    local cfg
    before_each(function()
      K.reset({ ["main.lua"] = FILE })
      cfg = K.cc.cfg.editor
      K.cc.cfg.editor = { mouse_enabled = true }
    end)
    after_each(function() K.cc.cfg.editor = cfg end)

    local function click(x, y, presses)
      F.session.mousepressed(x, y, 1, false, presses or 1)
      F.session.mousereleased(x, y, 1, false, presses or 1)
      K.frame()
    end
    local function view()
      return K.ed.input.model.cfg.view
    end

    spec_it("IS2.1 Browse blocks: a click or a double click "
        .. "on a block changes nothing", function()
      K.open()
      K.browse_to(2)
      local before = snapshot()
      local v = view()
      -- the first row is block 1's
      click(v.fw * 2, v.fh * 0.5)
      assert.same(before, snapshot())
      click(v.fw * 2, v.fh * 0.5, 2)
      assert.same(before, snapshot())
    end)

    -- as in every field (the ruling of November 14, 2026)
    spec_it("IS3.8 Position the text cursor: a click in the "
        .. "draft places the cursor there", function()
      K.open()
      K.type("abcdef")
      local before = snapshot()
      local v = view()
      click(v.fw * 2.2, v.h - v.fh * 0.5)
      before.cursor = { 1, 3 }
      assert.same(before, snapshot())
    end)
  end)
end)
