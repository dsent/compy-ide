-- The marks spec tests carry (tests/helpers/spec_marks.lua)
-- and the script that counts them (util/spec_count.lua).

local marks = require("tests.helpers.spec_marks")
local count = require("util.spec_count")

--- Define a test through `mark` as a spec file would, and
--- return the name and body handed to `it`, unrun.
local function define(mark, ...)
  local got = { }
  local env = {
    it = function(name, fn)
      got.name, got.fn = name, fn
    end
  }
  -- not a tail call: the mark reads `it` from this frame
  local spec_file = function(...)
    mark(...)
  end
  setfenv(spec_file, setmetatable(env, { __index = _G }))
  spec_file(...)
  return got
end

local function failing()
  assert.same(1, 2)
end
local function passing()
  assert.same(1, 1)
end

--- A gap's body: `before` runs as an ordinary step, then
--- `check` as the spec's check.
local function gap_of(before, check)
  return function(gap)
    before()
    gap(check)
  end
end

local n = 0
--- A name no other test in this file has.
local function fresh(id)
  n = n + 1
  return id .. " Item: case " .. n
end

describe("spec marks #editor", function()
  describe("a gap", function()
    it("passes while the spec's check fails", function()
      local t = define(
        marks.spec_gap,
        fresh("IS2.1"),
        gap_of(passing, failing)
      )
      assert.has_no.errors(t.fn)
    end)

    it("fails once the editor complies", function()
      local t = define(
        marks.spec_gap,
        fresh("IS2.1"),
        gap_of(passing, passing)
      )
      local ok, e = pcall(t.fn)
      assert.is_false(ok)
      assert.matches("spec_marks_spec.lua:%d+: IS2.1 now " ..
          "complies: remove the mark", e)
    end)

    it("fails when a step before the check fails", function()
      local t = define(
        marks.spec_gap,
        fresh("IS2.1"),
        gap_of(failing, failing)
      )
      assert.has_error(t.fn)
    end)

    it("fails on an error that is not an assertion", function()
      local t = define(marks.spec_gap, fresh("IS2.1"), gap_of(
          passing, function()
        error("a typo in the test", 0)
      end))
      assert.has_error(t.fn, "a typo in the test")
    end)

    it("fails unless it checks exactly once", function()
      local none = define(marks.spec_gap, fresh("IS2.1"),
          function()
        
      end)
      assert.has_error(none.fn)
      local twice = define(marks.spec_gap, fresh("IS2.1"),
          function(gap)
        gap(failing)
        gap(failing)
      end)
      assert.has_error(twice.fn)
    end)

    it("is tagged, so it can be run apart", function()
      local name = fresh("FR4.8")
      local t = define(
        marks.spec_gap,
        name,
        gap_of(passing, failing)
      )
      assert.same(name .. " #spec_gap", t.name)
    end)
  end)

  describe("a deviation", function()
    it("asserts what is built", function()
      local t = define(
        marks.spec_deviation,
        fresh("IS3.16"),
        "design D3",
        failing
      )
      assert.has_error(t.fn)
      local name = fresh("IS3.16")
      t = define(
        marks.spec_deviation,
        name,
        "design D3",
        passing
      )
      assert.has_no.errors(t.fn)
      assert.same(name .. " #spec_deviation", t.name)
    end)

    it("names its ruling", function()
      assert.has_error(function()
        define(
          marks.spec_deviation,
          fresh("IS3.16"),
          "",
          passing
        )
      end)
    end)
  end)

  describe("every mark refuses", function()
    it("a name that does not open with an id", function()
      assert.has_error(function()
        define(marks.spec_it, "browses blocks", passing)
      end)
      local name = fresh("H-NFR4.4")
      assert.same(
        name,
        define(marks.spec_it, name, passing).name
      )
      local journey = fresh("CUJ1")
      assert.same(
        journey,
        define(marks.spec_it, journey, passing).name
      )
    end)

    it("a missing body", function()
      assert.has_error(function()
        define(marks.spec_it, fresh("IS2.1"), nil)
      end)
      assert.has_error(function()
        define(marks.spec_deviation, fresh("IS2.1"), "D3", nil)
      end)
    end)

    it("a name a test in the same file has", function()
      local name = fresh("IS2.1")
      define(marks.spec_it, name, passing)
      assert.has_error(function()
        define(marks.spec_gap, name, gap_of(passing, failing))
      end)
    end)

    it("a call from where busted's it is not", function()
      local helper = function(name)
        marks.spec_it(name, passing)
      end
      setfenv(helper, setmetatable({ }, { __index = _G }))
      local ok, e = pcall(helper, fresh("IS2.1"))
      assert.is_false(ok)
      assert.matches("call a mark from the spec file", e)
    end)
  end)

  describe("under busted's own it", function()
    marks.spec_it("IS0.1 Marks: a test that complies", passing)
    marks.spec_gap(
      "IS0.1 Marks: a gap",
      gap_of(passing, failing)
    )
    marks.spec_deviation(
      "IS0.1 Marks: a deviation",
      "a ruling",
      passing
    )
  end)

  describe("the count", function()
    local src = table.concat({
      "spec_it(\"IS2.1 Browse: a\", f)",
      "spec_gap('IS2.1 Browse: b', f)",
      "spec_deviation(\n  \"IS3.16 Card: a\", \"D3\", f)",
      "marks.spec_it([[FR4.8 Cue: a]], f)",
      "it(\"IS9.9 not a mark\", f)",
      "my_spec_it(\"IS9.9 not a mark\", f)",
      "-- spec_it(\"IS9.9 commented out\", f)",
      "--[[ spec_gap(\"IS9.9 commented out\", f) ]]",
      "local s = \"spec_it(\\\"IS9.9 in a string\\\", f)\"",
      "spec_it(name, f)",
      "spec_it(\"no id here\", f)",
      "local spec_it = marks.spec_it",
      "spec_it \"IS9.9 no body\""
    }, "\n")

    it("finds every mark and its item, nothing else", function()
      local found, unread = count.scan(src)
      assert.same({
        {
          id = "IS2.1",
          kind = "tests"
        },
        {
          id = "IS2.1",
          kind = "gaps"
        },
        {
          id = "IS3.16",
          kind = "deviations"
        },
        {
          id = "FR4.8",
          kind = "tests"
        }
      }, found)
      assert.same({
        11,
        12,
        14
      }, unread)
    end)

    it("counts per item, gaps and deviations among the marks",
        function()
      local found = count.scan(src)
      assert.same({
        "item       marks  gaps  devs",
        "IS2.1          2     1     0",
        "IS3.16         1     0     1",
        "FR4.8          1     0     0",
        "total          4     1     1",
        "items: 3"
      }, count.report(count.tally(found)))
    end)
  end)
end)
