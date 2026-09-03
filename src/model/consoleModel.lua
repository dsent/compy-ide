local class = require('util.class')

require("model.canvasModel")
require("model.editor.editorModel")
require("model.project.project")

--- @class Model table
--- @field input UserInputModel
--- @field editor EditorModel
--- @field output CanvasModel
--- @field projects ProjectService
--- @field cfg Config
ConsoleModel = class.create(function(cfg)
  --- @type PromptLabel
  local console_label = 'console'
  if love.state.has_removable == false then
    console_label = {
      text = '[no sd card] console',
      tone = 'warning',
    }
  end
  return {
    input    = UserInputModel(cfg, LuaEval(), false, console_label),
    editor   = EditorModel(cfg),
    output   = CanvasModel(cfg),
    projects = ProjectService(),
    cfg      = cfg
  }
end)
