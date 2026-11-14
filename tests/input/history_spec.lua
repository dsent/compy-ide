--- @diagnostic disable: invisible
require("model.input.history")
local F = require('tests.helpers.input_fixture')

if not orig_print then
  --- @diagnostic disable: duplicate-set-field
  _G.orig_print = function() end
end

describe('history #history', function()
  require("util.debug")

  local history
  local t = {
    { 'close_project()' },
    { 'project("clock")' },
    { 'run("turtle")' },
  }
  local t1 = t[1]
  local ok = false
  local cur = { '' }
  setup(function()
    history = History()
  end)

  it('caps the number of entries', function()
    local h = History(10)
    for i = 1, 15 do
      h:remember({ 'entry ' .. i })
    end
    assert.are_equal(10, h:length())
    assert.same({ 'entry 6' }, h:get(1))
    assert.same({ 'entry 15' }, h:get(10))
  end)

  it('treats 0 as unlimited', function()
    local h = History(0)
    for i = 1, 15 do
      h:remember({ 'entry ' .. i })
    end
    assert.are_equal(15, h:length())
  end)

  it('defaults the limit', function()
    assert.are_equal(1000, History().limit)
  end)

  it('ends the walk when a line is stored, past the cap too',
    function()
    local h = History(100)
    for i = 1, 100 do
      h:remember({ 'e' .. i })
    end
    h:history_back({ 'draft' })
    h:history_back({ 'e100 edited' })
    h:remember({ 'typed' })
    assert.is_nil(h.index)
    assert.are_equal(100, h:length())
    assert.same({ 'e2' }, h:get(1))
    assert.same({ 'e100' }, h:get(99))
    local _, cur = h:history_back({ '' })
    assert.same({ 'typed' }, cur)
    _, cur = h:history_back({ '' })
    assert.same({ 'e100' }, cur)
  end)

  it('walks without writing, keeping the draft and edits',
    function()
    local h = History()
    h:remember({ 'a' })
    h:remember({ 'b' })
    assert.is_false(h:history_fwd({ 'draft' }))
    local ok, cur = h:history_back({ 'draft' })
    assert.is_true(ok)
    assert.same({ 'b' }, cur)
    _, cur = h:history_back({ 'b edited' })
    assert.same({ 'a' }, cur)
    _, cur = h:history_fwd({ 'a' })
    assert.same({ 'b edited' }, cur)
    _, cur = h:history_fwd({ 'b edited' })
    assert.same({ 'draft' }, cur)
    assert.is_nil(h.index)
    assert.same({ { 'a' }, { 'b' } }, h:_get_entries())
    h:reset_index()
    _, cur = h:history_back({ '' })
    assert.same({ 'b' }, cur)
  end)

  it('stores a copy, which later edits leave alone', function()
    local h = History()
    local line = { 'x = = 1' }
    h:remember(line)
    line[1] = 'x = 1'
    assert.same({ { 'x = = 1' } }, h:_get_entries())
  end)

  it('skips a line equal to the newest entry, compared '
    .. 'exactly, and ends the walk all the same', function()
    local h = History()
    assert.is_true(h:remember({ 'a', 'b' }))
    h:history_back({ 'draft' })
    assert.is_false(h:remember({ 'a', 'b' }))
    assert.is_nil(h.index)
    assert.is_nil(h.line_typed)
    assert.is_true(h:remember({ 'a', 'b ' }))
    assert.is_true(h:remember({ 'a' }))
    assert.is_true(h:remember({ 'a', 'b ' }))
    assert.same({ { 'a', 'b' }, { 'a', 'b ' }, { 'a' }, { 'a', 'b ' } },
      h:_get_entries())
  end)

  it('recalls nothing when empty', function()
    assert.is_false(History():history_back({ 'draft' }))
  end)

  it('remembers', function()
    history:remember(t1)
    local h1 = { t1 }
    assert.same(h1, history:_get_entries())
    history:remember(t[2])
    history:remember(t[3])
    assert.same(t, history:_get_entries())
  end)
  it('recalls', function()
    --- go back
    assert.same(t, history:_get_entries())
    assert.same(nil, history.index)
    ok, cur = history:history_back()
    assert.same(3, history.index)
    assert.is_true(ok)
    assert.same(t[3], cur)
    ok, cur = history:history_back()
    assert.same(2, history.index)
    assert.is_true(ok)
    assert.same(t[2], cur)
    ok, cur = history:history_back()
    assert.same(1, history.index)
    assert.is_true(ok)
    assert.same(t[1], cur)
    --- bottoms out
    ok, cur = history:history_back()
    assert.same(1, history.index)
    assert.is_false(ok)

    --- now go fwd
    ok, cur = history:history_fwd()
    assert.same(2, history.index)
    assert.is_true(ok)
    assert.same(t[2], cur)
    ok, cur = history:history_fwd()
    assert.same(3, history.index)
    assert.is_true(ok)
    assert.same(t[3], cur)
    --- past the newest, the line typed
    ok, cur = history:history_fwd()
    assert.same(nil, history.index)
    assert.is_true(ok)
    assert.same({ '' }, cur)
    ok, cur = history:history_fwd()
    assert.is_false(ok)
    assert.same(nil, cur)
  end)
end)

-- End-to-end, the way a user reaches it: the console input is
-- single-line, so Up hits the vertical limit at once and the
-- widget reports that through on_limit_reached, which the
-- console maps to history_back
-- (doc/development/decisions/input.md, D-EDIT-CALLBACKS).
describe('console history navigation #input #history',
  function()
  setup(function() F.setup() end)
  teardown(function() F.teardown() end)
  before_each(function() F.reset() end)

  it('Up at the vertical limit recalls the last entry',
    function()
    F.console.model.history:remember({ 'foo' })
    F.session.press('up')
    assert.same({ 'foo' }, F.console:get_text())
  end)
end)
