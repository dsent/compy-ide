local display = require('conf.display')

--- Lints: conventions the editor lets through. They are reported
--- and never refused; what the editor refuses is a gate
--- (model.lang.lua.check). Each rule reads formatted text and
--- its AST.
---
--- The limits are doc/development/conventions/code.md's; the
--- other rules keep a program the way Compy games are written.
--- The strict rules are those much existing code breaks; they
--- run only when asked for.

--- @class LintFinding
--- @field l integer --- the line
--- @field rule string --- the rule's name
--- @field msg string --- what to change, in plain words

--- @alias LintRule fun(lines: string[], ast: luaAST): LintFinding[]

--- A function fits the input the editor shows it in
local FUNCTION_LINES = display.input_lines
local PARAMETERS = 4
local NESTING = 4
--- uses of compy.audio a file makes before it wants an alias
local AUDIO_USES = 3
--- one-letter names that say what they hold; `_` is the name
--- of a value left unused
local SHORT_NAMES = {
  x = true, y = true, t = true, r = true,
  i = true, j = true, k = true, _ = true,
}
--- what a Compy sets before a program's first line runs
local INJECTED = {
  gfx = true, Color = true, compy = true, utf8 = true,
}

--- @param node any
--- @param visit fun(node: table): boolean? --- true: skip it
local function walk(node, visit)
  if type(node) ~= 'table' then return end
  if node.tag and visit(node) then return end
  for _, child in ipairs(node) do walk(child, visit) end
end

--- @param n table
--- @return integer
local function line_of(n)
  return n.lineinfo and n.lineinfo.first.line or 1
end

--- @param n table --- where
--- @param rule string
--- @param msg string
--- @return LintFinding
local function finding(n, rule, msg)
  return { l = line_of(n), rule = rule, msg = msg }
end

--- @param n table
--- @return table
local function unparen(n)
  while n.tag == 'Paren' do n = n[1] end
  return n
end

--- The expression is the dotted name, as in 'love.draw'
--- @param n table?
--- @param path string
--- @return boolean
local function is_path(n, path)
  if not n then return false end
  local head, key = string.match(path, '^(.+)%.([^.]+)$')
  if not head then return n.tag == 'Id' and n[1] == path end
  return n.tag == 'Index' and n[2].tag == 'String'
      and n[2][1] == key and is_path(n[1], head)
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

--- A name the code declares: a local, a parameter, a loop
--- variable, or a global the first time it is set
--- @class Declaration
--- @field id table --- its Id node
--- @field kind string --- local, parameter, loop or global
--- @field value table? --- what it is first set to

--- @class DeclarationWalk
--- @field found Declaration[]
--- @field globals table<string, true>
--- @field scopes table<string, Declaration>[] --- inner last

local declare_in

--- The local a name means where the walk is
--- @param w DeclarationWalk
--- @param name string
--- @return Declaration?
local function local_of(w, name)
  for i = #w.scopes, 1, -1 do
    local d = w.scopes[i][name]
    if d then return d end
  end
end

--- @param w DeclarationWalk
--- @param d Declaration --- a global: any name set
local function declare(w, d)
  if d.id.tag ~= 'Id' then return end
  local name = d.id[1]
  d.value = d.value and unparen(d.value)
  if d.kind ~= 'global' then
    w.scopes[#w.scopes][name] = d
  else
    local l = local_of(w, name)
    --- a local declared bare takes the first value set to it
    if l and l.kind == 'local' then
      l.value = l.value or d.value
    end
    if l or w.globals[name] then return end
    w.globals[name] = true
  end
  table.insert(w.found, d)
end

--- Walk a list of nodes in a scope of its own, declaring ids
--- in it first
--- @param w DeclarationWalk
--- @param list table
--- @param ids table? --- Id nodes
--- @param kind string?
local function scoped(w, list, ids, kind)
  table.insert(w.scopes, {})
  for _, id in ipairs(ids or {}) do
    declare(w, { id = id, kind = kind or 'local' })
  end
  for _, n in ipairs(list) do declare_in(w, n) end
  table.remove(w.scopes)
end

--- How each statement that declares or scopes names is walked
local declaring = {}

function declaring.Local(w, n)
  for _, e in ipairs(n[2]) do declare_in(w, e) end
  for i, id in ipairs(n[1]) do
    declare(w, { id = id, kind = 'local', value = n[2][i] })
  end
end

function declaring.Localrec(w, n)
  for i, id in ipairs(n[1]) do
    declare(w, { id = id, kind = 'local', value = n[2][i] })
  end
  for _, e in ipairs(n[2]) do declare_in(w, e) end
end

function declaring.Set(w, n)
  for i, t in ipairs(n[1]) do
    if t.tag == 'Id' then
      declare(w, { id = t, kind = 'global', value = n[2][i] })
    else
      declare_in(w, t)
    end
  end
  for _, e in ipairs(n[2]) do declare_in(w, e) end
end

function declaring.Function(w, n)
  scoped(w, n[2], n[1], 'parameter')
end

function declaring.Fornum(w, n)
  for i = 2, #n - 1 do declare_in(w, n[i]) end
  scoped(w, n[#n], { n[1] }, 'loop')
end

function declaring.Forin(w, n)
  for _, e in ipairs(n[2]) do declare_in(w, e) end
  scoped(w, n[3], n[1], 'loop')
end

function declaring.While(w, n)
  declare_in(w, n[1])
  scoped(w, n[2])
end

--- `until` sees the locals of the loop's body
function declaring.Repeat(w, n)
  scoped(w, { n[1], n[2] })
end

function declaring.Do(w, n)
  scoped(w, n)
end

function declaring.If(w, n)
  for i, c in ipairs(n) do
    if i % 2 == 1 and i < #n then
      declare_in(w, c)
    else
      scoped(w, c)
    end
  end
end

--- @param w DeclarationWalk
--- @param n any
function declare_in(w, n)
  if type(n) ~= 'table' then return end
  local d = n.tag and declaring[n.tag]
  if d then return d(w, n) end
  for _, c in ipairs(n) do declare_in(w, c) end
end

--- @param ast luaAST
--- @return Declaration[]
local function declarations(ast)
  local w = { found = {}, globals = {}, scopes = {} }
  scoped(w, ast)
  return w.found
end

--- @param found LintFinding[]
--- @param stmts table
local function file_locals(found, stmts)
  for _, s in ipairs(stmts) do
    if s.tag == 'Do' then file_locals(found, s) end
    if s.tag == 'Local' or s.tag == 'Localrec' then
      local names = {}
      for _, id in ipairs(s[1]) do
        table.insert(names, id[1])
      end
      local msg = string.format('local %s at file level; drop'
        .. ' local so the console can see %s',
        table.concat(names, ', '),
        #names > 1 and 'them' or 'it')
      table.insert(found, finding(s, 'module-local', msg))
    end
  end
end

--- @type LintRule
local function module_local(_, ast)
  local found = {}
  file_locals(found, ast)
  return found
end

--- @type LintRule
local function love_load(_, ast)
  local found = {}
  walk(ast, function(n)
    if n.tag ~= 'Set' then return end
    for _, target in ipairs(n[1]) do
      if is_path(target, 'love.load') then
        table.insert(found, finding(n, 'love-load',
          'set things up at the top of the file instead of in'
          .. ' love.load'))
      end
    end
  end)
  return found
end

--- @type LintRule
local function metatable(_, ast)
  local found = {}
  walk(ast, function(n)
    if n.tag == 'Call' and (is_path(n[1], 'setmetatable')
          or is_path(n[1], 'getmetatable')) then
      table.insert(found, finding(n, 'metatable',
        'uses a metatable; use a plain table instead'))
    end
  end)
  return found
end

--- An argument, from the first on, is a number or a table
--- holding one
--- @param call table
--- @return boolean
local function has_number(call)
  for i = 2, #call do
    local a = unparen(call[i])
    if a.tag == 'Number' then return true end
    for _, item in ipairs(a.tag == 'Table' and a or {}) do
      local v = unparen(item.tag == 'Pair' and item[2] or item)
      if v.tag == 'Number' then return true end
    end
  end
  return false
end

--- @type LintRule
local function raw_color(_, ast)
  local found = {}
  walk(ast, function(n)
    if n.tag ~= 'Call' then return end
    local f = n[1]
    local named = is_path(f, 'setColor') or f.tag == 'Index'
        and f[2].tag == 'String' and f[2][1] == 'setColor'
    if named and has_number(n) then
      table.insert(found, finding(n, 'raw-color',
        'color given as numbers; use a Color entry, as in'
        .. ' Color[Color.red]'))
    end
  end)
  return found
end

--- Every assignment to a name the Compy sets
--- @param found LintFinding[]
--- @param ast luaAST
local function injected_assignments(found, ast)
  walk(ast, function(n)
    local t = n.tag
    if t ~= 'Set' and t ~= 'Local' and t ~= 'Localrec' then
      return
    end
    for _, id in ipairs(n[1]) do
      if id.tag == 'Id' and INJECTED[id[1]] then
        table.insert(found, finding(id, 'injected-global',
          string.format('%s is set by the Compy already; remove'
            .. ' this assignment', id[1])))
      end
    end
  end)
end

--- The file sets sfx to compy.audio
--- @param n table --- a Set or Local
--- @return boolean
local function is_sfx_alias(n)
  for i, id in ipairs(n[1]) do
    local value = n[2][i]
    if is_path(id, 'sfx') and is_path(value, 'compy.audio') then
      return true
    end
  end
  return false
end

--- compy.audio used often with no sfx alias
--- @param found LintFinding[]
--- @param ast luaAST
local function audio_alias(found, ast)
  local uses, aliased = {}, false
  walk(ast, function(n)
    if n.tag == 'Set' or n.tag == 'Local' then
      aliased = aliased or is_sfx_alias(n)
    end
    if is_path(n, 'compy.audio') then table.insert(uses, n) end
  end)
  if aliased or #uses <= AUDIO_USES then return end
  table.insert(found, finding(uses[1], 'injected-global',
    string.format('compy.audio is used %d times; set'
      .. ' sfx = compy.audio once and use sfx', #uses)))
end

--- @type LintRule
local function injected_global(_, ast)
  local found = {}
  injected_assignments(found, ast)
  audio_alias(found, ast)
  return found
end

--- The tests an if, elseif, while or until makes
--- @param n table
--- @return table[]
local function tests_of(n)
  local t = {}
  if n.tag == 'If' then
    for i = 1, #n - 1, 2 do table.insert(t, n[i]) end
  elseif n.tag == 'While' then
    table.insert(t, n[1])
  elseif n.tag == 'Repeat' then
    table.insert(t, n[2])
  end
  return t
end

--- @type LintRule
local function compound_condition(_, ast)
  local found = {}
  walk(ast, function(n)
    for _, test in ipairs(tests_of(n)) do
      local op = unparen(test)
      local joins = op.tag == 'Op'
          and (op[1] == 'and' or op[1] == 'or')
      if joins then
        table.insert(found, finding(test, 'compound-condition',
          'the test joins conditions with and/or; name it'
          .. ' first, as in local hit = left or right'))
      end
    end
  end)
  return found
end

--- @type LintRule
local function one_char_name(_, ast)
  local found = {}
  for _, d in ipairs(declarations(ast)) do
    local name = d.id[1]
    --- a global state table may have a short name
    local state = d.kind == 'global' and d.value
        and d.value.tag == 'Table'
    if #name == 1 and not SHORT_NAMES[name] and not state then
      table.insert(found, finding(d.id, 'one-char-name',
        string.format('one-letter name %s; name it for what it'
          .. ' holds', name)))
    end
  end
  return found
end

--- Code that runs on every frame
--- @param n table --- a Set
--- @param i integer --- one of its targets
--- @return string? hook --- love.update or love.draw
--- @return table? body
local function frame_hook(n, i)
  local f = n[2][i] and unparen(n[2][i])
  if not f or f.tag ~= 'Function' then return end
  for _, hook in ipairs({ 'love.update', 'love.draw' }) do
    if is_path(n[1][i], hook) then return hook, f[2] end
  end
end

--- @type LintRule
local function hot_path_allocation(_, ast)
  local found = {}
  walk(ast, function(n)
    if n.tag ~= 'Set' then return end
    for i in ipairs(n[1]) do
      local hook, body = frame_hook(n, i)
      walk(hook and body, function(inner)
        local t = inner.tag
        if t ~= 'Table' and t ~= 'Function' then return end
        local msg = string.format('makes a new %s on every'
          .. ' frame; make it once, outside %s',
          string.lower(t), hook)
        table.insert(found,
          finding(inner, 'hot-path-allocation', msg))
        return true
      end)
    end
  end)
  return found
end

--- Collect a field's key when a function is stored under it
--- @param names table[]
--- @param key table|false --- a String node
--- @param value table?
local function keyed_function(names, key, value)
  if key and key.tag == 'String' and value
      and unparen(value).tag == 'Function' then
    table.insert(names, key)
  end
end

--- Every name a function is given where it is made: `name`
--- nodes, an Id or the String of a field
--- @param ast luaAST
--- @return table[]
local function function_names(ast)
  local names = {}
  for _, d in ipairs(declarations(ast)) do
    if d.value and d.value.tag == 'Function' then
      table.insert(names, d.id)
    end
  end
  walk(ast, function(n)
    for i, t in ipairs(n.tag == 'Set' and n[1] or {}) do
      keyed_function(names, t.tag == 'Index' and t[2], n[2][i])
    end
    for _, item in ipairs(n.tag == 'Table' and n or {}) do
      if item.tag == 'Pair' then
        keyed_function(names, item[1], item[2])
      end
    end
  end)
  return names
end

--- @param name string --- as in draw_ball
--- @return string --- as in drawBall; empty for `_`
local function camel(name)
  local s = string.gsub(name, '^_+', '')
  s = string.gsub(s, '_+$', '')
  s = string.gsub(s, '_+(%w)', string.upper)
  return s
end

--- @type LintRule
local function function_name(_, ast)
  local found = {}
  for _, n in ipairs(function_names(ast)) do
    local name = n[1]
    if string.find(name, '_') then
      local as = camel(name)
      local msg = name .. ' has an underscore; write function'
        .. ' names in camelCase'
        .. (as ~= '' and ', as in ' .. as or '')
      table.insert(found, finding(n, 'function-name', msg))
    end
  end
  return found
end

--- @param name string --- as in cellSize
--- @return string --- as in cell_size
local function snake(name)
  local s = string.gsub(name, '(%l)(%u)', '%1_%2')
  s = string.gsub(s, '(%u)(%u%l)', '%1_%2')
  return string.lower(s)
end

--- A capital inside a name that is not all capitals
--- @param name string
--- @return boolean
local function mixed_case(name)
  return string.find(name, '.%u') ~= nil
      and string.find(name, '%l') ~= nil
end

--- @type LintRule
local function variable_name(_, ast)
  local found = {}
  for _, d in ipairs(declarations(ast)) do
    local name = d.id[1]
    local is_function = d.value and d.value.tag == 'Function'
    if not is_function and mixed_case(name) then
      local msg = string.format('%s has a capital inside; write'
        .. ' variable names in snake_case, as in %s', name,
        snake(name))
      table.insert(found, finding(d.id, 'variable-name', msg))
    end
  end
  return found
end

local M = {
  --- @type LintRule[]
  rules = {
    function_length, parameters, nesting,
    love_load, metatable, raw_color, injected_global,
    compound_condition, hot_path_allocation, variable_name,
  },
  --- run as well when asked for strictly
  --- @type LintRule[]
  strict = { module_local, one_char_name, function_name },
}

--- Every finding of every rule, in line order; on one line, in
--- the order of the rules
--- @param lines string[] --- formatted text
--- @param ast luaAST --- its AST
--- @param strict boolean? --- run the strict rules too
--- @return LintFinding[]
function M.lint(lines, ast, strict)
  local found, order = {}, {}
  local sets = strict and { M.rules, M.strict } or { M.rules }
  for _, set in ipairs(sets) do
    for _, rule in ipairs(set) do
      for _, f in ipairs(rule(lines, ast)) do
        table.insert(found, f)
        order[f] = #found
      end
    end
  end
  table.sort(found, function(a, b)
    if a.l ~= b.l then return a.l < b.l end
    return order[a] < order[b]
  end)
  return found
end

return M
