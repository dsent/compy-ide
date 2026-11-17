-- Messages, the status line and names with letters outside
-- ASCII, or with bytes that are not UTF-8, in the console and
-- in a project's field: what they show is text the screen can
-- draw (LÖVE raises on bytes that are not UTF-8), and a letter
-- a parser message quotes is whole.

local K = require("tests.helpers.editor_keys")
local F = require("tests.helpers.input_fixture")

local R = string.REPLACEMENT

local function valid(s)
  return string.scrub(s) == s
end

--- Every text the screen `s` draws is valid UTF-8.
local function all_text(s)
  for _, list in ipairs({ s.texts, s.field }) do
    for _, t in ipairs(list) do
      assert.is_true(valid(t.text), t.text)
    end
  end
end

local function console_message()
  return table.concat(F.console:get_wrapped_error() or { }, "")
end

describe("text outside ASCII in messages #input", function()
  setup(K.setup)
  teardown(K.teardown)
  before_each(function()
    K.reset()
  end)
  after_each(K.cleanup)

  describe("a console draft that fails", function()
    for _, case in ipairs({
      { "é = 1", 1, "é" },
      { "п = 1", 1, "п" },
      { "x = ж", 5, "ж" },
      { "x = 😀", 5, "😀" },
    }) do
      local draft, col, ch = case[1], case[2], case[3]
      it("on " .. ch .. " names it whole, at its column",
        function()
          K.type(draft)
          local ok, err = pcall(K.keys, "return")
          assert.is_true(ok, err)
          assert.same(draft, K.console_draft())
          local msg = console_message()
          assert.is_true(valid(msg), msg)
          assert.truthy(msg:find("`" .. ch .. "'", 1, true), msg)
          assert.same({ 1, col },
            { F.console.model:get_cursor_pos() })
          local h = F.console.model:get_highlight() or { }
          local e = h.parse_err or { }
          assert.same({ 1, col }, { e.l, e.c })
          all_text(K.screen())
        end)
    end
  end)

  --- a run's error is said in the output (the maintainer's
  --- ruling of November 15, 2026)
  it("a console error holding a byte that is not UTF-8 " ..
    "shows a replacement", function()
    K.type('error("\\195")')
    K.keys("return")
    K.frame(100)
    local msg = K.console_text():match("[^\n]*L1:[^\n]*") or ""
    assert.truthy(msg:find(R, 1, true), msg)
    assert.is_true(valid(msg), msg)
    all_text(K.screen())
  end)

  it("a file name that is not UTF-8 is refused with a reason",
    function()
      K.reset({ ["main.lua"] = "x = 1\n", ["\195.txt"] = "a\n" })
      K.type('edit("\\195.txt")')
      local ok, err = pcall(K.keys, "return")
      assert.is_true(ok, err)
      assert.same("ready", K.app_state())
      local out = K.console_text()
      assert.truthy(out:find("Not UTF-8 text", 1, true), out)
      all_text(K.screen())
    end)

  it("a project folder named in bytes that are not UTF-8 " ..
    "shows in the editor's status line with a replacement",
    function()
      -- a folder put on the card by another computer: the
      -- console opens a project by any folder's name
      K.cc.model.projects.current.name = "p\195"
      K.open()
      local s = K.screen()
      all_text(s)
      assert.truthy(K.screen_text(s.field):find("p" .. R, 1, true))
    end)

  it("a project's prompt that is not UTF-8 is drawn with a " ..
    "replacement", function()
    local widget = F.show_widget({
      text = "hey",
      prompt = "ask\195"
    })
    local view = UserInputView(K.cc.view.cfg.view, widget)
    widget:init_view(view)
    local s = K.screen(function()
      view:draw()
    end)
    all_text(s)
    local found = false
    for _, t in ipairs(s.field) do
      if t.text == "ask" .. R then found = true end
    end
    assert.is_true(found)
  end)
end)
