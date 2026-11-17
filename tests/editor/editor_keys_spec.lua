-- The key-driven editor helper: a whole journey through it,
-- and what the helper itself promises.

local K = require("tests.helpers.editor_keys")
local FS = require("util.filesystem")

--- Record the events the helper sends, in order, as
--- "press k", "text c", "release k" and "frame".
local function record(fn)
  local seen, h = { }, love.handlers
  local orig = {
    h.keypressed,
    h.textinput,
    h.keyreleased,
    love.update
  }
  function h.keypressed(k)
    seen[#seen + 1] = "press " .. k
  end
  function h.textinput(c)
    seen[#seen + 1] = "text " .. c
  end
  function h.keyreleased(k)
    seen[#seen + 1] = "release " .. k
  end
  function love.update()
    seen[#seen + 1] = "frame"
  end
  local ok, e = pcall(fn)
  h.keypressed, h.textinput, h.keyreleased = orig[1], orig[2],
      orig[3]
  love.update = orig[4]
  if not ok then
    error(e, 0)
  end
  return seen
end

describe("the key-driven editor helper #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  -- Only what holds before and after the rework: where a new
  -- block lands and which keys browse are what it changes.
  describe("a journey", function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
    end)

    it("opens a file to browse it", function()
      assert.same(2, K.blocks())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same("editor", K.app_state())
    end)

    it("types, submits and saves a new block", function()
      -- bare Down with an empty field browses toward the end
      for _ = 1, 3 do
        K.keys("down")
      end
      assert.same("end", K.position())
      K.type("z = 3")
      assert.same("inserting", K.state())
      assert.same("z = 3", K.draft())
      K.keys("return")
      assert.same("browsing", K.state())
      assert.same(3, K.blocks())
      assert.same("x = 1\ny = 2\nz = 3\n", K.file())
      assert.same({ "main.lua" }, K.writes())
    end)
  end)

  describe("itself", function()
    before_each(function()
      K.reset()
    end)

    it("sends a key's character between press and release",
        function()
      assert.same({
        "press space",
        "text  ",
        "release space",
        "frame"
      }, record(function()
        K.keys("space")
      end))
      assert.same({
        "press lshift",
        "press a",
        "text A",
        "release a",
        "release lshift",
        "frame"
      }, record(function()
        K.keys("lshift", "a")
      end))
    end)

    it("sends no character for a chord with Ctrl", function()
      assert.same({
        "press lctrl",
        "press c",
        "release c",
        "release lctrl",
        "frame"
      }, record(function()
        K.keys("lctrl", "c")
      end))
    end)

    it("types a character of several bytes as text alone",
        function()
      assert.same({
        "press x",
        "text x",
        "release x",
        "frame",
        "text é",
        "frame"
      }, record(function()
        K.type("xé")
      end))
    end)

    it("refuses a line break as text", function()
      assert.has_error(function()
        K.type("a\nb")
      end)
    end)

    it("releases every key of a chord", function()
      K.open()
      K.keys("lctrl", "lshift", "up")
      assert.is_false(love.keyboard.isDown("lctrl"))
      assert.is_false(love.keyboard.isDown("lshift"))
    end)

    it("gives each test its own files and clipboard", function()
      love.system.setClipboardText("left over")
      K.reset({ ["a.lua"] = "a = 1\n" })
      assert.is_nil(K.file())
      assert.same("a = 1\n", K.file("a.lua"))
      assert.same({ }, K.writes())
      assert.same("", K.clipboard())
    end)

    it("fails writes on request, until the next reset",
        function()
      K.fail_writes("the card is full")
      local project = K.cc.model.projects.current
      assert.same({
        false,
        "the card is full"
      }, { project:writefile("main.lua", "x") })
      K.reset()
      project = K.cc.model.projects.current
      assert.is_true(project:writefile("main.lua", "x"))
    end)

    it("starts the next test afresh after the editor raised",
        function()
      -- a file whose line two statements share makes the
      -- edge raise on the next submission
      K.reset({ ["main.lua"] = "x = 1; y = {\n  2,\n}\n" })
      K.open()
      for _ = 1, 10 do
        K.keys("down")
      end
      K.type("w = 4")
      pcall(K.keys, "return")
      K.reset()
      K.open()
      assert.same("main.lua", K.file_name())
      assert.same("browsing", K.state())
    end)

    it("puts the filesystem back, reset twice or not", function(
      
    )
      K.cleanup()
      local exists = FS.exists
      K.reset()
      K.reset()
      assert.are_not.equal(exists, FS.exists)
      K.cleanup()
      assert.are.equal(exists, FS.exists)
    end)
  end)
end)
