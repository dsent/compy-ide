-- To run on the joined tree (program-owns-input with the selection),
-- the review's round s3: a drag released under the console's key card,
-- then a second press outside the field still under the card, does not
-- revive after the card. Through the production gateway.
local F = require('tests.helpers.input_fixture')
local K = require('tests.helpers.editor_keys')
local Layout = require('view.layout')

local function at(f, row, col)
  local v = f.model.cfg.view
  local bottom = love.graphics.getHeight() - Layout(v).bottom
  return v.fw * (col - 1 + .2), bottom - v.fh * (row + .5)
end

describe('a drag across the key card #input', function()
  after_each(function()
    F.set_mouse_down(false)
    K.cleanup()
  end)

  it('does not revive after a second press under the card', function()
    K.reset()
    local f = K.cc.input
    f:set_text({ 'abcdef' })
    local x, y = at(f, 0, 2)
    F.set_mouse_down(true)
    F.session.mousepressed(x, y, 1, false, 1)
    K.hold('f1')
    assert.is_not_nil(K.key_card())
    F.set_mouse_down(false)
    F.session.mousereleased(x, y, 1, false, 1)
    F.set_mouse_down(true)
    F.session.mousepressed(x, 10, 1, false, 1)
    K.release('f1')
    local x2 = at(f, 0, 5)
    F.session.mousemoved(x2, y, x2 - x, 0, false)
    F.session.mousereleased(x2, y, 1, false, 1)
    assert.is_false(f.model:has_selection())
  end)
end)
