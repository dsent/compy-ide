-- LÖVE brings utf8; a spec runs without it, so here is the
-- one call the echo makes.
package.preload["utf8"] = function()
  local function seq_len(b)
    if b < 128 then return 1 end
    if b >= 194 and b <= 223 then return 2 end
    if b >= 224 and b <= 239 then return 3 end
    if b >= 240 and b <= 244 then return 4 end
  end
  return {
    len = function(s)
      local i, n = 1, 0
      while i <= #s do
        local len = seq_len(s:byte(i))
        if not len then return nil, i end
        for k = i + 1, i + len - 1 do
          local c = s:byte(k)
          if not c or c < 128 or c > 191 then return nil, i end
        end
        i, n = i + len, n + 1
      end
      return n
    end,
  }
end

require("model.serial.echo")

describe("echo", function()
  local said, wrote, e

  before_each(function()
    said, wrote = {}, {}
    e = Echo.new(
      function(s) wrote[#wrote + 1] = s end,
      function(s) said[#said + 1] = s end)
    e:on()
  end)

  it("starts off", function()
    assert.is_false(Echo.new(print, print):isOn())
  end)

  it("says whole lines and holds the rest", function()
    e:bytes("> print(1)\r\r\n2\r\n> ")
    assert.same({ "> print(1)", "2" }, said)
    assert.same({}, wrote)
  end)

  --- a file exec handed over ends while echo shows the board
  it("says how a file ended in place of exec's status line",
    function()
      e:bytes("done\r\n\30exec ok\r\n")
      e:bytes("oops\r\n\30exec error\r\n")
      assert.same({ "done", "The program on the micro:bit has"
        .. " ended.", "oops", "The program on the micro:bit"
        .. " stopped on the mistake above." }, said)
      for _, line in ipairs(said) do
        assert.is_nil(line:find("\30", 1, true))
      end
    end)

  it("shows a line that only looks like a status", function()
    e:bytes("x \30exec ok\r\n")
    assert.same({ "x \30exec ok" }, said)
  end)

  it("assembles a line from single characters", function()
    for c in ("hi\r"):gmatch(".") do e:bytes(c) end
    assert.same({ "hi" }, said)
  end)

  it("writes the tail once the board falls quiet", function()
    e:bytes("2\r\n> ")
    e:tick(0.1)
    assert.same({}, wrote)
    e:tick(0.2)
    assert.same({ "> " }, wrote)
    e:tick(1)
    assert.same({ "> " }, wrote)
  end)

  it("keeps the tail while more keeps coming", function()
    e:bytes("> ")
    e:tick(0.15)
    e:bytes("a")
    e:tick(0.15)
    assert.same({}, wrote)
  end)

  it("drops what is not UTF-8, keeps what is", function()
    e:bytes("\255\237hi\r")
    assert.same({ "hi" }, said)
    e:bytes("\208\191\209\128\208\184\r")
    assert.same({ "hi", "при" }, said)
  end)

  it("forgets the tail when switched off", function()
    e:bytes("> ")
    e:off()
    e:tick(1)
    assert.same({}, wrote)
    assert.is_false(e:isOn())
  end)

  it("forgets the tail when switched on again", function()
    e:bytes("> ")
    e:on()
    e:tick(1)
    assert.same({}, wrote)
  end)
end)
