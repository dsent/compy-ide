local display = require('conf.display')

--- Lints: conventions the editor lets through. They are reported
--- and never refused; what the editor refuses is a gate
--- (model.lang.lua.check). Each rule reads formatted text and
--- its AST. The limits are doc/development/conventions/code.md's.

--- @class LintFinding
--- @field l integer --- the line
--- @field rule string --- the rule's name
--- @field msg string --- what to change, in plain words

--- @alias LintRule fun(lines: string[], ast: luaAST): LintFinding[]

--- A function fits the input the editor shows it in
local FUNCTION_LINES = display.input_lines
local PARAMETERS = 4
local NESTING = 4

--- @param node any
--- @param visit fun(node: table)
local function walk(node, visit)
  if type(node) ~= 'table' then return end
  if node.tag then visit(node) end
  for _, child in ipairs(node) do walk(child, visit) end
end

--- @param n table
--- @return integer
local function line_of(n)
  return n.lineinfo and n.lineinfo.first.line or 1
end

--- @type LintRule
local function function_length(_, ast)
  local found = {}
  walk(ast, function(n)
    if n.tag ~= 'Function' or not n.lineinfo then return end
    local len = n.lineinfo.last.line - n.lineinfo.first.line + 1
    if len > FUNCTION_LINES then
      table.insert(found, {
        l = line_of(n),
        rule = 'function-length',
        msg = string.format(
          'function of %d lines; keep it to %d', len, FUNCTION_LINES),
      })
    end
  end)
  return found
end

--- @type LintRule
local function parameters(_, ast)
  local found = {}
  walk(ast, function(n)
    if n.tag ~= 'Function' then return end
    local params = n[1]
    local count = #params
    --- `self` in a method is no parameter the caller passes
    local first = params[1]
    if first and first.tag == 'Id' and first[1] == 'self' then
      count = count - 1
    end
    if count > PARAMETERS then
      table.insert(found, {
        l = line_of(n),
        rule = 'parameters',
        msg = string.format(
          'function takes %d parameters; keep it to %d,'
          .. ' or pass a table', count, PARAMETERS),
      })
    end
  end)
  return found
end

--- The statement lists a statement opens, each one level deeper
--- @param n table
--- @return table? --- set of the child lists that are bodies
local function bodies(n)
  local t, b = n.tag, {}
  if t == 'If' then
    for i = 2, #n, 2 do b[n[i]] = true end
    if #n % 2 == 1 then b[n[#n]] = true end
  elseif t == 'Fornum' or t == 'Forin' then
    b[n[#n]] = true
  elseif t == 'While' then
    b[n[2]] = true
  elseif t == 'Repeat' then
    b[n[1]] = true
  elseif t == 'Do' then
    for _, s in ipairs(n) do b[s] = true end
  else
    return
  end
  return b
end

--- Control statements nested more than NESTING deep, counted
--- afresh in each function body, since a function is read on
--- its own. The outermost one too deep is reported.
--- @type LintRule
local function nesting(_, ast)
  local found = {}
  local function visit(n, depth, reported)
    if type(n) ~= 'table' then return end
    if n.tag == 'Function' then
      visit(n[2], 0, false)
      return
    end
    local b = n.tag and bodies(n)
    if not b then
      for _, child in ipairs(n) do visit(child, depth, reported) end
      return
    end
    local inner = depth + 1
    local over = inner > NESTING and not reported
    if over then
      table.insert(found, {
        l = line_of(n),
        rule = 'nesting',
        msg = string.format('%d levels deep; keep it to %d, or move'
          .. ' the inner part into a function', inner, NESTING),
      })
    end
    for _, child in ipairs(n) do
      if b[child] then
        visit(child, inner, reported or over)
      else
        visit(child, depth, reported)
      end
    end
  end
  visit(ast, 0, false)
  return found
end

local M = {
  --- @type LintRule[]
  rules = { function_length, parameters, nesting },
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
