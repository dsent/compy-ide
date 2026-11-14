require("view.input.userInputView")
require("view.editor.bufferView")
require("view.editor.search.searchView")
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
    search = SearchView(cfg, ctrl.search),
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
--- @field search SearchView
EditorView = class.create(new)

function EditorView:draw()
  local ctrl = self.controller
  if ctrl:key_card() then return self:draw_key_card() end
  local mode = ctrl:get_mode()
  if mode == 'search' then
    self.search:draw()
  else
    local bv = self:get_current_buffer()

    self:fit_buffer()
    gfx.push('all')
    if ViewUtils.conditional_draw('show_buffer') then
      bv:draw()
    end
    if ViewUtils.conditional_draw('show_input') then
      gfx.push('all')
      self.input:draw()
      gfx.pop()
    end
    gfx.pop()
  end
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

--- @param moved integer?
function EditorView:refresh(moved)
  self:get_current_buffer():refresh(moved)
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
function EditorView:fit_buffer(input)
  local bm = self.controller:get_active_buffer()
  local bv = bm and self.buffers[bm:get_id()]
  if not bv then return end
  local inp = input or self.controller:get_input()
  bv:set_covered(self.input:get_rows(inp) - 1)
end
