require("view.input.userInputView")
require("view.editor.bufferView")
require("view.editor.keyCardView")

require("util.string.string")
local class = require('util.class')

--- @param cfg ViewConfig
--- @param ctrl EditorController
local function new(cfg, ctrl)
  local self = {
    cfg = cfg,
    controller = ctrl,
    input = UserInputView(cfg, ctrl.input),
    buffers = {},
    key_card = KeyCardView(cfg),
  }
  --- hook the view in the controller
  ctrl:init_view(self)
  return self
end

--- @class EditorView : ViewBase
--- @field controller EditorController
--- @field input UserInputView
--- @field buffers { [string]: BufferView }
EditorView = class.create(new)

function EditorView:draw()
  local ctrl = self.controller
  if ctrl:key_card() then return self:draw_key_card() end
  local bv = self:get_current_buffer()

  local rows = self:fit_buffer()
  gfx.push('all')
  if ViewUtils.conditional_draw('show_buffer') then
    --- the view's area ends where the status line's band
    --- starts
    bv:draw(false, self.input:status_y(rows))
  end
  if ViewUtils.conditional_draw('show_input') then
    gfx.push('all')
    self.input:draw()
    gfx.pop()
    self:draw_message(bv)
  end
  gfx.pop()
end

--- The rows a message may take: one, or up to three when it
--- is wider than the screen
local MESSAGE_ROWS = 3

--- The rows of the message shown, nil when none shows; one
--- longer than the band ends in an ellipsis.
--- @return string[]?
function EditorView:message_rows()
  local all = self.controller.input:get_wrapped_error()
  if not all or #all == 0 then return nil end
  local rows = { }
  for i = 1, math.min(#all, MESSAGE_ROWS) do
    rows[i] = all[i]
  end
  if #all > MESSAGE_ROWS then
    local w = self.cfg.drawableChars
    local last = string.usub(rows[MESSAGE_ROWS], 1, w - 1)
    rows[MESSAGE_ROWS] = last .. '…'
  end
  return rows
end

--- The colour of a message's text: the parser's message in
--- the error colour, a notice in the
--- status line's warning colour, as the console's status line
--- has its '[no sd card]'.
--- @private
--- @return RGB
function EditorView:_message_color()
  local colors = self.cfg.colors
  if self.controller:message_kind() == 'notice' then
    return colors.statusline.editor.warning
  end
  return colors.input.error
end

--- A message, a notice or an error's, in the band directly
--- above the status line, over the document view's last rows
--- (IS3.14). It is a hint that blocks nothing: neither the
--- status line nor the field moves for it, and the view
--- neither scrolls nor resizes; the rows under it are hidden
--- until the next key. Call after the field's draw, which
--- places the status line.
--- @param bv BufferView
function EditorView:draw_message(bv)
  local rows = self:message_rows()
  if not rows then return end
  local cf = self.cfg
  local colors = cf.colors.input
  local fh = cf.fh
  local width = gfx.getWidth()
  local bottom = self.input.start_h
  local top = bottom - #rows * fh
  --- from the top of the view's row the band reaches into,
  --- so that no row of the view shows cut
  local pitch, origin = bv:row_height(), bv:top()
  local from = origin
      + math.floor((top - origin) / pitch) * pitch

  gfx.push('all')
  gfx.setFont(cf.font)
  gfx.setColor(colors.error_bg)
  gfx.rectangle('fill', 0, from, width, bottom - from)
  gfx.setColor(self:_message_color())
  for i, row in ipairs(rows) do
    gfx.print(row, 0, top + (i - 1) * fh)
  end
  gfx.pop()
end

--- The key card over the document view and the field, the
--- status line beneath it (IS3.16)
function EditorView:draw_key_card()
  local ctrl = self.controller
  self.key_card:draw(ctrl:state_name(), ctrl:_draft_is_empty(),
    self.input.statusline, ctrl.input:get_status())
end

--- @param buffer BufferModel
--- @return BufferView
function EditorView:open(buffer)
  local bid = buffer:get_id()
  local opn = self.buffers[bid]
  if not opn then
    local v           = BufferView(self.cfg)
    self.buffers[bid] = v
    v:open(buffer)
    return v
  end
  return opn
end

--- @return BufferView
function EditorView:get_current_buffer()
  local ctrl = self.controller
  local bm = ctrl:get_active_buffer()
  local bid = bm:get_id()
  return self.buffers[bid]
end

--- @param bid string
--- @return BufferView
function EditorView:get_buffer(bid)
  return self.buffers[bid]
end

function EditorView:refresh()
  self:get_current_buffer():refresh()
  self:update_input()
end

function EditorView:update_input()
  local ctrl = self.controller
  local input = ctrl:get_input()
  local status = ctrl.input:get_status()
  self:fit_buffer(input)
  self.input:render(input, status)
end

--- Leave the document view the rows the field does not take:
--- the field grows upwards over the view's last rows, and the
--- view keeps the browsed block in those left (IS2.2)
--- @param input InputDTO?
--- @return integer? rows --- the field's, its status line apart
function EditorView:fit_buffer(input)
  local bm = self.controller:get_active_buffer()
  local bv = bm and self.buffers[bm:get_id()]
  if not bv then return end
  local inp = input or self.controller:get_input()
  local rows = self.input:get_rows(inp)
  bv:set_covered(rows - 1)
  return rows
end
