local class = require("util.class")
local assert = require("luassert")
local fmt = string.format
local textfile = require("util.textfile")

--- Drives the editor in tests via mocked keystrokes: Ctrl+Up
--- and Ctrl+Down browse (IS2.1), F2 begins a replacement
--- (IS5.1), Enter submits the draft.

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

  --- the file's lines: its final newline ends the last one;
  --- the empty file is one empty block (spec 2.1)
  local expected = textfile.lines(src)
  if #expected == 0 then expected = { '' } end
  assert.same(expected, buffer:get_text_content(),
    "desired content loaded")
  if nb then
    assert.same(
      nb,
      buffer:get_content_length(),
      fmt("Blocks loaded: %s", nb)
    )
  end
  self.input = input
  self.buffer = buffer
  return input, buffer
end

-- moves the browsing position to block number `n`, in any
-- state: Ctrl+Up and Ctrl+Down browse with a draft too
--- @param n integer
--- @param target_content string?
function EditorSession:select_block(n, target_content)
  local s = self.buffer.selection
  local dir = (s > n) and "up" or "down"
  local steps = math.abs(s - n)
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
  --- Edit makes the browsed block the replacement target
  self.mock.keystroke("f2", self.press)

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

--- Put text in the field as the draft, as if it had been
--- typed
--- @param newtext string
function EditorSession:alter_input(newtext)
  local newlines = string.lines(newtext)
  self.input:set_text(newlines)
  assert.same(newlines, self.input:get_text(), "input altered")
end

--- @param newtext string
function EditorSession:submit(newtext)
  self:alter_input(newtext)
  self.mock.keystroke("return", self.press)
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

--- The cursor is where a submission left it, at the end of
--- the draft: a size refusal keeps it (editor principles,
--- IS3.2, IS3.9).
function EditorSession:assert_cursor_kept()
  local t = self.input:get_text()
  self:assert_cursor_at(#t, string.ulen(t[#t]) + 1)
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
