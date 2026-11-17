require("model.editor.bufferModel")
require("model.input.userInputModel")

local class = require('util.class')

--- @class EditorModel
--- @field input UserInputModel
--- @field buffers Dequeue<BufferModel>
--- @field cfg Config
EditorModel = class.create(function(cfg)
  return {
    -- editing = true: the editor's rich input (#45). The
    -- oneshot slot this call used upstream is gone, so the
    -- label stays nil and `editing` moves up one position.
    input = UserInputModel(cfg, LuaEval(), nil, true),
    buffers = Dequeue.new({}, 'BufferModel'),
    cfg = cfg,
  }
end)
