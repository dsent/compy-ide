--- Lints: conventions the editor lets through. They are reported
--- and never refused; what the editor refuses is a gate
--- (model.lang.lua.check). Each rule reads formatted text.

--- @class LintFinding
--- @field l integer --- the line
--- @field rule string --- the rule's name
--- @field msg string --- what to change, in plain words

--- @alias LintRule fun(lines: string[], ast: luaAST): LintFinding[]

local M = {
  --- @type LintRule[]
  rules = {},
}

--- Every finding of every rule, in line order
--- @param lines string[] --- formatted text
--- @param ast luaAST --- its AST
--- @return LintFinding[]
function M.lint(lines, ast)
  local found = {}
  for _, rule in ipairs(M.rules) do
    for _, f in ipairs(rule(lines, ast)) do
      table.insert(found, f)
    end
  end
  table.sort(found, function(a, b) return a.l < b.l end)
  return found
end

return M
