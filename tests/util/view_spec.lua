local mock = require("tests.mock")
mock.mock_love({})
require("util.view")

describe('view utils #view', function()
  local prev_gfx
  local color

  setup(function()
    prev_gfx = _G.gfx
    color = { 1, 1, 1, 1 }
    _G.gfx = {
      getColor = function()
        return color[1], color[2], color[3], color[4]
      end,
      setColor = function(r, g, b, a)
        if type(r) == 'table' then
          color = { r[1], r[2], r[3], r[4] }
        else
          color = { r, g, b, a }
        end
      end,
      print = function() end,
    }
  end)

  teardown(function()
    _G.gfx = prev_gfx
  end)

  describe('write_token', function()
    it('leaves the active color untouched', function()
      gfx.setColor(0.1, 0.2, 0.3, 1)
      ViewUtils.write_token(0, 0, 'x',
        { 1, 0, 0, 1 }, { 0, 0, 0, 1 }, false)
      local r, g, b = gfx.getColor()
      assert.same({ 0.1, 0.2, 0.3 }, { r, g, b })

      ViewUtils.write_token(0, 0, 'x',
        { 1, 0, 0, 1 }, { 0, 0, 0, 1 }, true)
      r, g, b = gfx.getColor()
      assert.same({ 0.1, 0.2, 0.3 }, { r, g, b })
    end)
  end)
end)
