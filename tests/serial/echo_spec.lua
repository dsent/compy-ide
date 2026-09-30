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

  --- a file exec handed over ends while echo shows the board:
  --- exec gives echo the frame its end comes in
  describe("with a frame to expect", function()
    local F = "\30exec 65f00001 "
    local ENDED = "The program on the micro:bit has ended."
    local STOPPED = "The program on the micro:bit stopped on the"
      .. " mistake above."
    local UNREAD = "The program on the micro:bit could not run,"
      .. " because of the mistake above."

    before_each(function() e:expect(F) end)

    it("says the end in words, and drops the break before it",
      function()
        e:bytes("done\r\n\r\n" .. F .. "ok\r\n")
        assert.same({ "done", ENDED }, said)
      end)

    it("says a mistake the same way", function()
      e:bytes("oops\r\n\r\n" .. F .. "error\r\n")
      assert.same({ "oops", STOPPED }, said)
    end)

    --- io.write("done "): the tail went out open, and the break
    --- before the frame ends its line
    it("ends a line the tail left open", function()
      e:bytes("done ")
      e:tick(0.25)
      assert.same({ "done " }, wrote)
      e:bytes("\r\n" .. F .. "ok\r\n")
      assert.same({ "", ENDED }, said)
    end)

    --- every place the line can be cut, the status word too, with
    --- a pause the tail would otherwise be written in
    for _, case in ipairs({ { "ok", ENDED }, { "error", STOPPED },
      { "compile", UNREAD } }) do
      local line = F .. case[1] .. "\r\n"
      for cut = 1, #line - 1 do
        it("holds the end line cut after " .. cut .. " bytes ("
          .. case[1] .. ")", function()
            e:bytes(line:sub(1, cut))
            e:tick(0.25)
            assert.same({}, wrote)
            e:bytes(line:sub(cut + 1))
            assert.same({ case[2] }, said)
          end)
      end
    end

    it("holds a whole end line until its line break comes",
      function()
        e:bytes(F .. "ok")
        e:tick(1)
        assert.same({}, wrote)
        e:bytes("\r\n")
        assert.same({ ENDED }, said)
      end)

    it("shows a held start that turned out not to be the frame",
      function()
        e:bytes("\30ex")
        e:tick(0.25)
        assert.same({}, wrote)
        e:bytes("tra\r\n")
        assert.same({ "\30extra" }, said)
      end)

    it("shows another exec's frame and a frame inside a line",
      function()
        e:bytes("\30exec 1 ok\r\nx " .. F .. "ok\r\n")
        assert.same({ "\30exec 1 ok", "x " .. F .. "ok" }, said)
      end)

    it("says the end once", function()
      e:bytes(F .. "ok\r\n" .. F .. "ok\r\n")
      assert.same({ ENDED, F .. "ok" }, said)
    end)
  end)

  it("shows a frame it was not given as it is", function()
    e:bytes("\30exec 65f00001 ok\r\n")
    assert.same({ "\30exec 65f00001 ok" }, said)
  end)

  it("takes a CR LF cut between two chunks for one line end",
    function()
      e:bytes("one\r")
      e:bytes("\ntwo\r\n")
      assert.same({ "one", "two" }, said)
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
