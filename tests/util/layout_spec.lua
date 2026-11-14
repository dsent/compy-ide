-- The screen's layout: 18 rows of 33 pixels leave 6 of a
-- Compy's 600; conf/display.lua gives them to the status line
-- and to a strip at the bottom, and what it leaves lies at
-- the top. The status line's text has the pixels the line
-- gains split above and below it.

local display = require("conf.display")
local layout = require("view.layout")

local CFG = { h = 600, fh = 33, lines = 16 }

describe("the screen's layout", function()
  local saved

  before_each(function()
    saved = { display.status_extra, display.bottom_strip }
  end)

  after_each(function()
    display.status_extra, display.bottom_strip =
        saved[1], saved[2]
  end)

  local function with(extra, bottom)
    display.status_extra, display.bottom_strip = extra, bottom
    return layout(CFG)
  end

  it("gives four pixels to the status line and two to the "
      .. "bottom by default", function()
    assert.same({ top = 0, bottom = 2, status_h = 37,
      status_pad = 2 }, layout(CFG))
  end)

  it("splits them between the status line and the bottom",
    function()
      assert.same({ top = 0, bottom = 3, status_h = 36,
        status_pad = 1 }, with(3, 3))
      assert.same({ top = 0, bottom = 4, status_h = 35,
        status_pad = 1 }, with(2, 4))
      assert.same({ top = 0, bottom = 6, status_h = 33,
        status_pad = 0 }, with(0, 6))
      assert.same({ top = 0, bottom = 0, status_h = 39,
        status_pad = 3 }, with(6, 0))
    end)

  it("leaves at the top what the two numbers do not take, and "
      .. "never more than there is", function()
    assert.same({ top = 2, bottom = 1, status_h = 36,
      status_pad = 1 }, with(3, 1))
    assert.same({ top = 0, bottom = 0, status_h = 39,
      status_pad = 3 }, with(9, 9))
  end)
end)
