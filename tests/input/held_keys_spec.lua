-- The table of keys that repeat while held (HeldKeys), for
-- the keys whose repeat no key test can tell from a press:
-- a second F2, Ctrl+Shift+F or Ctrl+L changes nothing the
-- first did not. tests/editor/spec/added_held_keys_spec.lua
-- drives the rest through keys.

local mock = require('tests.mock')
mock.mock_love({ system = { getOS = function() return 'Linux' end } })
require('util.key')
local HeldKeys = require('model.input.heldKeys')

--- Whether `k` repeats on `surface` with `mods` held.
local function repeats(surface, mods, k)
  for _, m in ipairs(mods) do mock.hold(m) end
  local r = HeldKeys[surface](k)
  for _, m in ipairs(mods) do mock.unhold(m) end
  return r
end

describe('which keys repeat while held #input', function()
  local ONCE = {
    { 'editor', { }, 'return' },
    { 'editor', { 'lctrl' }, 'return' },
    { 'editor', { }, 'escape' },
    { 'editor', { }, 'f2' },
    { 'editor', { 'lshift' }, 'insert' },
    { 'editor', { 'lctrl' }, 'insert' },
    { 'editor', { 'lalt' }, 'up' },
    { 'editor', { 'lalt' }, 'down' },
    { 'editor', { 'lctrl', 'lshift' }, 'f' },
    { 'editor', { 'lctrl', 'lshift' }, 's' },
    { 'editor', { 'lctrl' }, 'j' },
    { 'editor', { }, 'f1' },
    { 'editor', { }, 'f5' },
    { 'console', { }, 'return' },
    { 'console', { 'lctrl' }, 'return' },
    { 'console', { }, 'escape' },
    { 'console', { 'lshift' }, 'insert' },
    { 'console', { 'lctrl' }, 'insert' },
    { 'console', { 'lctrl' }, 'l' },
    { 'console', { }, 'f1' },
  }
  for _, c in ipairs(ONCE) do
    local surface, mods, k = c[1], c[2], c[3]
    it(surface .. ': ' .. table.concat(mods, '+') .. ' ' .. k
        .. ' acts once', function()
      assert.is_false(repeats(surface, mods, k))
    end)
  end

  local REPEATS = {
    { 'editor', { 'lshift' }, 'return' },
    { 'editor', { 'lalt' }, 'return' },
    { 'editor', { }, 'up' },
    { 'editor', { 'lctrl' }, 'down' },
    { 'editor', { }, 'pagedown' },
    { 'editor', { 'lalt' }, 'pageup' },
    { 'editor', { 'lalt' }, 'left' },
    { 'editor', { 'lctrl' }, 'right' },
    { 'editor', { }, 'home' },
    { 'editor', { }, 'backspace' },
    { 'editor', { 'lctrl' }, 'backspace' },
    { 'editor', { 'lctrl' }, 'delete' },
    { 'editor', { 'lctrl' }, 'z' },
    { 'editor', { 'lctrl' }, 'y' },
    { 'editor', { 'lctrl' }, 'w' },
    { 'editor', { 'lctrl' }, 'k' },
    { 'editor', { 'lctrl' }, 'd' },
    { 'console', { 'lshift' }, 'return' },
    { 'console', { }, 'up' },
    { 'console', { }, 'pageup' },
    { 'console', { 'lalt' }, 'up' },
    { 'console', { 'lshift' }, 'left' },
    { 'console', { }, 'delete' },
    { 'console', { 'lctrl' }, 'y' },
  }
  for _, c in ipairs(REPEATS) do
    local surface, mods, k = c[1], c[2], c[3]
    it(surface .. ': ' .. table.concat(mods, '+') .. ' ' .. k
        .. ' repeats', function()
      assert.is_true(repeats(surface, mods, k))
    end)
  end
end)
