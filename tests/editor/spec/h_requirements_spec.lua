-- The high-level requirements, H-R1 to H-R5 (editor
-- principles, ratified), where a key-driven test can check
-- them beyond the design-level items that carry them.
--
-- No test of their own, each with its reason:
--   carried by the design-level items that implement them,
--   which are tested: H-FR2.1 (IS3.3, IS3.4), H-NFR1.2 (IS4.1,
--   IS4.2, IS5.3), H-NFR2.2 (IS3.2, IS3.7), H-NFR4.1 (IS2.1,
--   IS2.2), H-FR1.4 (IS2.2, FR3.4), H-FR3.3 (FR1.2), H-FR3.4
--   (FR1.1), H-NFR4.2 (NFR4.1, FR4.6), H-FR4.3 (IS1.4,
--   FR3.2), H-NFR4.5 (FR2.1, FR2.3), H-FR5.1 (IS1.2, IS8);
--   H-NFR4.4's cursor at the bezel, and the rest of H-NFR1.3
--   (knowing what is saved): a person's reading of the
--   screen, a device check;
--   H-NFR5.3, H-NFR5.5 (approachable source, one model behind
--   public APIs): properties of the source, for the design and
--   the review of the central change.
-- H-FR5.4 (a structured-text editor built in a project) is
-- not the editor's own: it asks of the input API.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local FILE = "x = 1\ny = 2\nz = 3\n"

describe("high-level requirements #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  before_each(function()
    K.reset({ ["main.lua"] = FILE })
    K.open()
  end)

  spec_it("H-NFR1.1 Limit typing loss: a refused submission "
      .. "keeps what was typed", function()
    K.browse_to_end()
    K.type("a = = 1")
    K.keys("return")
    assert.same("a = = 1", K.draft())
  end)

  spec_gap("H-NFR1.1 Limit typing loss: browsing keeps what "
      .. "was typed", function(gap)
    K.browse_to_end()
    K.type("a = = 1")
    local browsed = pcall(K.browse_to, 1)
    gap(function()
      assert.is_true(browsed)
      assert.same("a = = 1", K.draft())
    end)
  end)

  spec_it("H-NFR1.3 Identify safe work: a draft never shows "
      .. "among the saved lines", function()
    K.browse_to_end()
    K.type("w = 9")
    for _, r in ipairs(K.view_rows()) do
      assert.are_not.same("w = 9", r)
    end
  end)

  spec_it("H-FR2.3 Live syntax highlighting: the field colours "
      .. "Lua as it is typed", function()
    K.browse_to_end()
    K.type("w = 9")
    assert.is_true(1 < K.field_highlight())
    assert.same("w = 9", K.draft())
  end)

  spec_it("H-FR2.4 Canonical formatting: an accepted draft is "
      .. "shown formatted at once", function()
    K.browse_to_end()
    K.type("w=4")
    K.keys("return")
    local shown = false
    for _, r in ipairs(K.view_rows()) do
      if r == "w = 4" then
        shown = true
      end
    end
    assert.is_true(shown)
  end)

  spec_gap("H-NFR3.1 Accidental deletion protection: held " ..
      "Backspace and Delete leave the file alone", function(gap)
    K.browse_to(2)
    for _, key in ipairs({
      "backspace",
      "delete"
    }) do
      K.hold(key)
      for _ = 1, 5 do
        K.repeat_key(key)
      end
      K.release(key)
    end
    gap(function()
      assert.same(FILE, K.file())
      assert.same(2, K.position())
      assert.same("browsing", K.state())
    end)
  end)

  spec_gap("H-NFR3.2 Avoid sudden disappearance: a held cut "
      .. "removes one block and stops", function(gap)
    K.browse_to(1)
    K.hold("lctrl")
    K.hold("delete")
    for _ = 1, 5 do
      K.repeat_key("delete")
    end
    K.release("delete")
    K.release("lctrl")
    gap(function()
      assert.same("y = 2\nz = 3\n", K.file())
      assert.same("x = 1", K.draft())
    end)
  end)

  spec_gap("H-NFR4.4 Visible cursor and keyboard state: Caps "
      .. "Lock shows", function(gap)
    K.browse_to_end()
    local off = {
      K.status_text(),
      K.field_rows()
    }
    K.keys("capslock")
    local on = {
      K.status_text(),
      K.field_rows()
    }
    K.keys("capslock")
    gap(function()
      -- shown on the status line or in the field
      assert.are_not.same(off, on)
      assert.same(off, {
        K.status_text(),
        K.field_rows()
      })
    end)
  end)

  spec_gap("H-NFR4.6 No blocking confirmation dialogs: leaving "
      .. "after a failed write asks nothing", function(gap)
    K.fail_writes("the card is full")
    K.browse_to_end()
    K.type("a = 1")
    K.keys("return")
    K.keys("escape")
    K.keys("escape")
    gap(function()
      assert.same("ready", K.app_state())
    end)
  end)

  spec_gap("H-FR5.2 Typewriter entry: lines typed as written, "
      .. "Enter after each, are entered as written", function(
    gap
  )
    K.browse_to_end()
    for _, line in ipairs({
      "function f()",
      "  return 1",
      "end"
    }) do
      K.type(line)
      K.keys("return")
    end
    gap(function()
      assert.same(
        FILE .. "function f()\n  return 1\nend\n",
        K.file()
      )
    end)
  end)
end)
