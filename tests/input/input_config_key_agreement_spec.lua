-- Availability: introduced with the Compy input API
-- (1.0.0-rc20260712) — covers the compy.input surface.

-- The config-key contract, as one executable statement.
-- consoleController decides which keys show()/configure()
-- ACCEPT; userInputController decides which ones they APPLY,
-- and nothing reconciles the two. A key on the accept side
-- alone is taken by the surface and dropped by the widget with
-- no raise and no warning. The contract itself is
-- doc/development/decisions/input.md, D-CFG-BOUNDARY; the
-- reason this spec exists is the retired entry "The set of
-- accepted config keys has no single home" in
-- doc/development/technical_debt/input.md.
--
-- This spec is that reconciliation. It reads the REAL accepted
-- set out of the surface rather than restating it, so a key
-- added to one side and not the other fails here, by name.
-- Deliberately not a refactor: unifying the lists would make
-- one module import the other's across the surface/widget
-- boundary the architecture keeps apart (same entry).

local F = require('tests.helpers.input_fixture')

-- The accepted set is a file-local of consoleController, two
-- upvalues below the surface function that uses it. Read by
-- NAME, so a rename breaks this loudly instead of quietly
-- shrinking what the spec checks.
--- @param fn function
--- @param want string
local function upvalue(fn, want)
  local i = 1
  while true do
    local name, value = debug.getupvalue(fn, i)
    if not name then return nil end
    if name == want then return value end
    i = i + 1
  end
end

--- @param entry function the surface's show/configure
--- @param inner string the api_* it delegates to
--- @param set_name string the key set that one checks against
local function accepted_by(entry, inner, set_name)
  local api = upvalue(entry, inner)
  assert.is_function(api,
    'upvalue ' .. inner .. ' is gone; fix this reader')
  local set = upvalue(api, set_name)
  assert.is_table(set,
    'upvalue ' .. set_name .. ' is gone; fix this reader')
  return set
end

-- One proof per accepted key: the least that would fail if the
-- widget ignored the key. Not a second copy of each key's
-- behavioural test — those live in input_widget_control_spec
-- — but evidence the key reaches the widget. `apply` runs
-- the config through whichever entry point is under test.
local PROOFS = { }

PROOFS.prompt = function(apply)
  apply({ prompt = 'p?' })
  assert.equal('p?', F.widget.model:get_label())
end

--- One per lifecycle cell: the flag reaches the widget and
--- lands in its own slot, which is what "independently
--- settable" means (doc/development/decisions/input.md,
--- D-LIFECYCLE-FLAGS, acceptance criterion 7).
--- @param name string
local function flag_proof(name)
  return function(apply)
    apply({ [name] = true })
    assert.is_true(F.widget[name])
  end
end

PROOFS.clear_on_submit = flag_proof('clear_on_submit')
PROOFS.hide_on_submit = flag_proof('hide_on_submit')
PROOFS.clear_on_cancel = flag_proof('clear_on_cancel')
PROOFS.hide_on_cancel = flag_proof('hide_on_cancel')

-- the field's window takes the limit
PROOFS.max_rows = function(apply)
  apply({ max_rows = 3 })
  assert.same(3, F.widget.model.visible.size_max)
end

PROOFS.text = function(apply)
  apply({ text = 'seeded' })
  assert.same({ 'seeded' }, F.widget:get_text())
end

PROOFS.cursor = function(apply)
  apply({ text = 'abcd', cursor = { 1, 3 } })
  local line, col = F.widget:get_cursor_pos()
  assert.same({ 1, 3 }, { line, col })
end

-- force is applied by the widget's own show(), not by the
-- config path: without it a second show is refused, with it
-- the re-setup runs and the content baseline it carries is
-- seated. The seated text is the evidence -- a refused show
-- would leave 'first' standing.
PROOFS.force = function(apply)
  apply({ text = 'first' })
  apply({ force = true, text = 'second' })
  assert.same({ 'second' }, F.widget:get_text())
end

--- @param name string
local function callback_proof(name)
  return function(apply)
    local fn = function() end
    apply({ [name] = fn })
    assert.equal(fn, F.widget.callbacks[name])
  end
end

PROOFS.validator = callback_proof('validator')
PROOFS.highlighter = callback_proof('highlighter')
PROOFS.on_text_entered =
  callback_proof('on_text_entered')
PROOFS.on_limit_reached =
  callback_proof('on_limit_reached')

describe('input surface: the config-key contract #input',
  function()
    setup(function() F.setup() end)
    teardown(function() F.teardown() end)
    before_each(function() F.reset() end)

    -- A key with no proof is exactly the defect this spec is
    -- for, so the miss is reported by name rather than as a
    -- nil call.
    --- @param key string
    --- @param make_apply function
    local function prove(key, make_apply)
      local proof = PROOFS[key]
      assert.is_function(proof,
        'the surface accepts ' .. key ..
        ' and nothing here proves the widget applies it')
      F.reset()
      proof(make_apply())
    end

    local function show_apply()
      local input = F.compy_input()
      return function(cfg) input.show(cfg) end
    end

    local function configure_apply()
      local input = F.compy_input()
      return function(cfg) input.configure(cfg) end
    end

    -- The non-empty guard is not ceremony: an upvalue read
    -- that returned an empty table would make the loop below
    -- pass while checking nothing.
    it('every key show() accepts reaches the widget',
      function()
        local set = accepted_by(F.compy_input().show,
          'api_show', 'SHOW_KEYS')
        assert.is_not_nil(next(set))
        for key in pairs(set) do
          prove(key, show_apply)
        end
      end)

    it('every key configure() accepts reaches the widget',
      function()
        local set = accepted_by(F.compy_input().configure,
          'api_configure', 'CONFIGURE_KEYS')
        assert.is_not_nil(next(set))
        for key in pairs(set) do
          prove(key, configure_apply)
        end
      end)
  end)
