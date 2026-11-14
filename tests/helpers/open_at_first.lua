--- Tests written before IS1.1 (a file opens at its end
--- position) start at the file's first block. With this
--- installed, a newly opened file is browsed to its first
--- block right away, as Ctrl+Home does.
local M = {}

--- @return function restore --- call in teardown
function M.install()
  local open = EditorController.open
  EditorController.open = function(self, name, content,
                                   save, key)
    local had = key and self:_find_buffer(key)
    open(self, name, content, save, key)
    if had or self.model.buffers:length() == 0 then return end
    self:get_active_buffer():set_selection(1)
    self.view:get_current_buffer():follow_selection()
    self:update_status()
    self:set_state()
  end
  return function()
    EditorController.open = open
  end
end

return M
