local class = require('util.class')

require("model.canvasModel")
require("model.screenModel")
require("model.editor.editorModel")
require("model.project.project")

--- @class Model table
--- @field input UserInputModel
--- @field editor EditorModel
--- @field output CanvasModel
--- @field screen ScreenModel
--- @field projects ProjectService
--- @field cfg Config
ConsoleModel = class.create(function(cfg)
  --- The console's line names no label of its own: it says
  --- "console" where a running program's says "running" (the
  --- maintainer's ruling of November 17, 2026); an empty label
  --- shows nothing. Every line of the IDE's own puts the no-card
  --- mark in front (Statusline's NO_CARD).
  --- @type PromptLabel
  local console_label = ''
  return {
    input    = UserInputModel(cfg, LuaEval(), console_label),
    editor   = EditorModel(cfg),
    output   = CanvasModel(cfg),
    screen   = ScreenModel(),
    projects = ProjectService(),
    cfg      = cfg
  }
end)
