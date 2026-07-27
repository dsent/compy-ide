local class = require("util.class")
local assert = require("luassert")
local fmt = string.format

--- Drives the editor in tests via mocked keystrokes
--- (block navigation mode).

--- @class EditorSession
--- @field controller EditorController
--- @field press fun(...: any)
--- @field save fun(src: string)
--- @field mock table
--- @field input UserInputController?
--- @field buffer BufferModel?

EditorSession = class.create(
  --- @param controller EditorController
  --- @param press fun(...: any)
  --- @param save fun(src: string)
  --- @param mock table
  function(controller, press, save, mock)
    return {
      controller = controller,
      press = press,
      save = save,
      mock = mock,
    }
  end
)

--- @param src string
--- @param nb integer?
--- @return UserInputController
--- @return BufferModel
function EditorSession:open(src, nb)
  self.save(src)
  self.controller:open("test.lua", src, self.save)
  local input = self.controller.input
  local buffer = self.controller:get_active_buffer()

  local srclines = string.lines(src)
  local has_trailing_nl = (srclines[#srclines] == "")
  local expected = (has_trailing_nl and src or src .. "\n")

  assert.same(
    string.lines(expected),
    buffer:get_text_content(),
    "desired content loaded"
  )
  if nb then
    if has_trailing_nl then
      assert.same(
        nb,
        buffer:get_content_length(),
        fmt("Blocks loaded: %s", nb)
      )
    else
      assert.same(
        nb + 1,
        buffer:get_content_length(),
        fmt("Blocks loaded: %s original +1 extra", nb)
      )
    end
  end
  self.input = input
  self.buffer = buffer
  return input, buffer
end

-- moves selection to block number `n`
-- this helper is a bit of a dirty hack
-- so it only works reliably in block-level navigation mode!
-- (when editor multiline input buffer is not yet activated with <ESC>)
-- see also: https://github.com/compy-toys/compy/issues/117 (p.2)
--- @param n integer
--- @param target_content string?
function EditorSession:select_block(n, target_content)
  local s = self.buffer.selection
  local dir = (s > n) and "up" or "down"
  local steps = math.abs(s - n)
  if (not self.input:is_empty()) and (steps > 0) then
    local jumpkey = dir == "up" and "home" or "end"
    self.mock.keystroke(jumpkey, self.press)
  end
  --- blocks move with Ctrl (bare arrows are line-wise)
  for i = 1, steps do
    self.mock.keystroke('C-' .. dir, self.press)
  end

  assert.same(
    n,
    self.buffer.selection,
    fmt("selection moved to block #%s", n)
  )
  if target_content then
    assert.same(
      string.lines(target_content),
      self.buffer:get_selected_text(),
      "selected block #%s has expected content",
      n
    )
  end
end

--- @param n integer
--- @param target_content string?
function EditorSession:select_and_open_block(n, target_content)
  self:select_block(n, target_content)
  --- Enter on an empty input opens the block (Esc is inert)
  self.mock.keystroke("return", self.press)

  assert.same(n, self.buffer.loaded, fmt("loaded block #%s", n))
  if target_content then
    assert.same(
      string.lines(target_content),
      self.input:get_text(),
      "input loaded expected content (block #%s)",
      n
    )
  end
end

--- @param newtext string
--- Compose text as if it had been typed: the editor is
--- editing whenever the input holds anything (2.1), so
--- putting text in without the mode is not a real state
--- @param newtext string
function EditorSession:alter_input(newtext)
  local newlines = string.lines(newtext)
  if self.controller:get_mode() == 'nav' then
    self.controller:set_mode('edit')
  end
  self.input:set_text(newlines)
  assert.same(newlines, self.input:get_text(), "input altered")
end

--- @param newtext string
--- @param ctrl boolean?
function EditorSession:submit(newtext, ctrl)
  self:alter_input(newtext)
  local keycode = ctrl and "C-return" or "return"
  self.mock.keystroke(keycode, self.press)
end

--- @param snippet string
--- @return integer
function EditorSession:input_line_of(snippet)
  local first = string.lines(snippet)[1]
  for i, line in ipairs(self.input:get_text()) do
    if line == first then return i end
  end
  error("snippet first line not found in input")
end

--- @param line integer
--- @param col integer?
function EditorSession:assert_cursor_at(line, col)
  col = col or 1
  local cl, cc = self.input:get_cursor_pos()
  assert.same(line, cl, "cursor line")
  assert.same(col, cc, "cursor column")
  local vr = self.input.model.visible:get_range()
  assert.is_true(vr:inc(line), "cursor line visible in input")
end
