require('util.string.string')
require('util.table')
local format = require('model.lang.lua.format')
local display = require('conf.display')
local inputs = require('tests.interpreter.ast_inputs')

local W = display.columns

--- @param path string
--- @return string[]
local function read_lines(path)
  local f = assert(io.open(path))
  local text = f:read('*a')
  f:close()
  return string.lines(text)
end

--- @return string[]
local function shipped_lua_files()
  local found = {}
  local ls = assert(io.popen("find src/examples -name '*.lua' | sort"))
  for path in ls:lines() do table.insert(found, path) end
  ls:close()
  return found
end

--- @param lines string[]
--- @return string? bytecode
--- @return function? chunk --- kept alive so template-table keys stay pinned
local function stripped_bytecode(lines)
  local fn = loadstring(table.concat(lines, '\n'))
  if not fn then return nil end
  return string.dump(fn, true), fn
end

--- Inputs in ast_inputs.lua that LuaJIT loads, which format.format
--- refuses because the printer currently changes their bytecode:
---   wrap[3]  -- long quoted string split into `..` pieces
---   wrap[13] -- long bracket string split into `..` pieces
---   wrap[29] -- 87-digit number truncated by tostring to 14 digits
local EXPECTED_AST_NOT_OK = {
  'wrap[3]',
  'wrap[13]',
  'wrap[29]',
}

local EXPECTED_SHIPPED_NOT_OK = {}

describe('lua format bytecode corpus #format', function()
  it('preserves LuaJIT stripped bytecode across ast_inputs.lua', function()
    local accepted = 0
    local not_ok = {}

    for _, group in ipairs(inputs) do
      local tag, cases = group[1], group[2]
      for i, tc in ipairs(cases) do
        local inp = tc[1]
        local lines = type(inp) == 'string' and string.lines(inp) or inp
        local before, pinned = stripped_bytecode(lines)
        if before then
          accepted = accepted + 1
          local id = string.format('%s[%d]', tag, i)
          local out, ok = format.format(lines, W)
          if ok then
            local after = stripped_bytecode(out)
            assert.is_not_nil(after, id .. ' loads after format')
            assert.equal(before, after, id .. ' bytecode changed')
          else
            assert.same(lines, out, id .. ' returned unchanged on refusal')
            table.insert(not_ok, id)
          end
          assert.is_not_nil(pinned)
        end
      end
    end

    assert.is_true(accepted > 0)
    assert.same(EXPECTED_AST_NOT_OK, not_ok)
  end)

  it('preserves LuaJIT stripped bytecode across shipped example files',
    function()
      local files = shipped_lua_files()
      assert.is_true(#files > 0)
      local accepted = 0
      local not_ok = {}

      for _, path in ipairs(files) do
        local lines = read_lines(path)
        local before, pinned = stripped_bytecode(lines)
        if before then
          accepted = accepted + 1
          local out, ok = format.format(lines, W)
          if ok then
            local after = stripped_bytecode(out)
            assert.is_not_nil(after, path .. ' loads after format')
            assert.equal(before, after, path .. ' bytecode changed')
          else
            assert.same(lines, out, path .. ' returned unchanged on refusal')
            table.insert(not_ok, path)
          end
          assert.is_not_nil(pinned)
        end
      end

      assert.equal(#files, accepted)
      assert.same(EXPECTED_SHIPPED_NOT_OK, not_ok)
    end)
end)
