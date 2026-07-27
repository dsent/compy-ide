local class = require('util.class')

--- The text-level undo of the open block (1.1). Born when
--- the block opens, dies when it closes; never touches the
--- file. Snapshots are taken before a mutation; consecutive
--- same-kind edits at the expected cursor coalesce into one
--- step, so undo removes a typed word, not a letter.
--- @class EditHistory
--- @field cap integer
--- @field steps table[] --- snapshots {text, cursor}
--- @field redo_steps table[]
--- @field last_kind string?
--- @field last_cursor table? --- {l, c} after the last edit
EditHistory = class.create(function(cap)
  return {
    cap = cap,
    steps = {},
    redo_steps = {},
    last_kind = nil,
    last_cursor = nil,
  }
end)

--- Forget everything (the block closed or was replaced)
function EditHistory:reset()
  self.steps = {}
  self.redo_steps = {}
  self.last_kind = nil
  self.last_cursor = nil
end

--- @param l integer
--- @param c integer
--- @return boolean --- the edit continues the previous one
function EditHistory:_continues(l, c)
  local lc = self.last_cursor
  return lc ~= nil and lc.l == l and lc.c == c
end

--- Record the state before a mutation
--- @param snapshot table --- {text: string[], cursor: {l,c}}
--- @param kind string --- 'insert'|'remove'|'paste'|...
--- @param boundary boolean --- force a new step
function EditHistory:record(snapshot, kind, boundary)
  local c = snapshot.cursor
  local coalesce = not boundary
      and kind == self.last_kind
      and self:_continues(c.l, c.c)
  if not coalesce then
    table.insert(self.steps, snapshot)
    if #self.steps > self.cap then
      table.remove(self.steps, 1)
    end
  end
  self.redo_steps = {}
  self.last_kind = kind
end

--- The cursor where the last mutation ended; the next
--- edit coalesces only if it starts here
--- @param l integer
--- @param c integer
function EditHistory:note_cursor(l, c)
  self.last_cursor = { l = l, c = c }
end

--- @param current table --- snapshot to park for redo
--- @return table? --- the snapshot to restore
function EditHistory:undo(current)
  local n = #self.steps
  if n == 0 then return end
  table.insert(self.redo_steps, current)
  local snap = self.steps[n]
  table.remove(self.steps, n)
  self.last_kind = nil
  self.last_cursor = nil
  return snap
end

--- @param current table --- snapshot to park for undo
--- @return table? --- the snapshot to restore
function EditHistory:redo(current)
  local n = #self.redo_steps
  if n == 0 then return end
  table.insert(self.steps, current)
  local snap = self.redo_steps[n]
  table.remove(self.redo_steps, n)
  self.last_kind = nil
  self.last_cursor = nil
  return snap
end
