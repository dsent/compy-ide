-- IS3 Preparing and submitting input (editor principles,
-- ratified): the clauses the tests of is3_input_spec.lua
-- leave out. Keys only, through
-- tests/helpers/editor_keys.lua. Edit is F2; submit and
-- retain is Shift+Ins, which shows the retained draft
-- formatted (IS3.2) and so drives IS3.9.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local FILE = "x = 1\ny = 2\n"

--- Open main.lua and start typing at its end.
local function at_end()
  K.reset({ ["main.lua"] = FILE })
  K.open()
  K.browse_to_end()
end

--- Open main.lua and press Edit (F2) on block `b`.
local function edit(b)
  K.reset({ ["main.lua"] = FILE })
  K.open()
  K.browse_to(b)
  K.keys("f2")
end

--- Type `lines` at the end, put the cursor `rights` characters
--- after the start of line `line`, and submit with Shift+Ins,
--- which keeps the draft.
local function retain(lines, line, rights)
  at_end()
  K.type_lines(lines)
  K.keys("lctrl", "home")
  for _ = 2, line do
    K.keys("down")
  end
  K.keys("home")
  for _ = 1, rights do
    K.keys("right")
  end
  K.keys("lshift", "insert")
end

--- Type a 15-line block at the end, its second line `text`
--- (and its last `last`), put the cursor `rights` characters
--- after the start of line `line`, and press Enter: the block
--- is over the size limit, so the draft stays, shown
--- canonically formatted (IS3.2).
local function refuse(text, line, rights, last)
  at_end()
  local lines = K.block_lines(15)
  lines[2] = text
  lines[15] = last or lines[15]
  K.type_lines(lines)
  K.keys("lctrl", "home")
  for _ = 2, line do
    K.keys("down")
  end
  K.keys("home")
  for _ = 1, rights do
    K.keys("right")
  end
  K.keys("return")
end

--- Line `n` of the draft.
local function line_of(n)
  local i = 0
  for l in (K.draft() .. "\n"):gmatch("(.-)\n") do
    i = i + 1
    if i == n then
      return l
    end
  end
end

--- What the editor holds that a key card or a refusal must
--- leave alone.
local function held_state()
  return {
    draft = K.draft(),
    cursor = { K.cursor() },
    position = K.position(),
    target = K.target() or "none",
    file = K.file()
  }
end

describe("IS3 input, added #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("IS3.2", function()
    spec_it("IS3.2 Show Lua interpretation: typing leaves the "
        .. "cursor after the typed text, highlighted", function(
      
    )
      at_end()
      K.type("local z")
      local classes = K.field_highlight()
      local first = { K.cursor() }
      K.type(" = 3")
      assert.is_true(0 < classes)
      assert.same({
        1,
        8
      }, first)
      assert.same({
        1,
        12
      }, { K.cursor() })
      assert.is_true(classes < K.field_highlight())
      assert.same("local z = 3", K.draft())
    end)

    spec_it("IS3.2 Show Lua interpretation: a draft retained "
        .. "with Shift+Ins is shown canonically formatted",
        function()
      retain({ "z=3" }, 1, 3)
      assert.same(FILE .. "z = 3\n", K.file())
      assert.same("z = 3", K.draft())
    end)
  end)

  describe("IS3.6", function()
    before_each(function()
      K.reset({ ["main.lua"] = FILE })
    end)

    spec_it("IS3.6 Execute console input: an accepted " ..
        "submission is executed at once", function()
      K.type("edit(\"main.lua\")")
      local before = K.app_state()
      K.keys("return")
      assert.same("ready", before)
      assert.same("editor", K.app_state())
    end)

    spec_it("IS3.6 Execute console input: the field is clear "
        .. "once the command has run", function()
      K.type("z = 3")
      local typed = K.console_draft()
      K.keys("return")
      assert.same("z = 3", typed)
      assert.same("", K.console_draft())
    end)

    spec_it("IS3.6 Execute console input: the activity the " ..
        "command starts takes the input, the field clear",
        function()
      -- K.open types edit("main.lua") into the console and
      -- presses Enter: a console submission
      K.open()
      local started = {
        K.app_state(),
        K.state(),
        K.draft(),
        K.console_draft()
      }
      K.type("z")
      assert.same({
        "editor",
        "browsing",
        "",
        ""
      }, started)
      assert.same("z", K.draft())
      assert.same("", K.console_draft())
    end)

    spec_it("IS3.6 Execute console input: a Lua draft that " ..
        "fails the check is not executed", function()
      K.type("edit(\"main.lua\") = = 1")
      K.keys("return")
      assert.same("ready", K.app_state())
      assert.same("edit(\"main.lua\") = = 1", K.console_draft())
    end)
  end)

  describe("IS3.9, a draft refused for size", function()
    spec_it("IS3.9 Preserve cursor through formatting: at the "
        .. "draft's start, it stays at the start", function()
      refuse("  v1=1", 1, 0)
      assert.same("  v1 = 1", line_of(2))
      assert.same({
        1,
        1
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: at the "
        .. "draft's end, it stays at the end", function()
      refuse("  v1=1", 15, 3)
      assert.same("  v1 = 1", line_of(2))
      assert.same({
        15,
        4
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: before "
        .. "an element, it stays before that element", function(
      
    )
      -- "  v1  =  1", the cursor before "="
      refuse("  v1  =  1", 2, 6)
      assert.same("  v1 = 1", line_of(2))
      assert.same({
        2,
        6
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: after "
        .. "an element, it stays after that element", function()
      -- "  v1  =  1", the cursor after "v1"
      refuse("  v1  =  1", 2, 4)
      assert.same("  v1 = 1", line_of(2))
      assert.same({
        2,
        5
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: inside "
        .. "an element, it keeps its offset there", function()
      -- "  v1=1;foo=2", the cursor after "fo"
      refuse("  v1=1;foo=2", 2, 9)
      assert.same("  v1 = 1", line_of(2))
      assert.same("  foo = 2", line_of(3))
      assert.same({
        3,
        5
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: in an "
        .. "unchanged gap, it keeps its offset there", function(
      
    )
      -- one character into the indentation, which stays
      refuse("  v1=1", 2, 1)
      assert.same("  v1 = 1", line_of(2))
      assert.same({
        2,
        2
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: in a "
        .. "replaced gap, it goes before the next element",
        function()
      -- "  v1   =   1", the cursor two spaces after "v1"
      refuse("  v1   =   1", 2, 6)
      assert.same("  v1 = 1", line_of(2))
      assert.same({
        2,
        6
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: in " ..
        "replaced indentation, it goes before the text",
        function()
      refuse("      v1=1", 2, 4)
      assert.same("  v1 = 1", line_of(2))
      assert.same({
        2,
        3
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: in a "
        .. "removed gap with nothing after, it goes to the end"
        , function()
      -- the last line typed "end   ", the cursor one space
      -- after "end"
      refuse("  v1=1", 15, 4, "end   ")
      assert.same("end", line_of(15))
      assert.same({
        15,
        4
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: the " ..
        "mapping follows the same occurrence", function()
      -- "  v1=v1+v1", the cursor after the second "v1"
      refuse("  v1=v1+v1", 2, 7)
      assert.same("  v1 = v1 + v1", line_of(2))
      assert.same({
        2,
        10
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: the " ..
        "replacement target is unchanged", function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.browse_to(2)
      K.keys("f2")
      K.keys("lctrl", "home")
      K.keys("lctrl", "k")
      local lines = K.block_lines(15)
      lines[2] = "  v1=1"
      K.type_lines(lines)
      K.keys("return")
      assert.same("  v1 = 1", line_of(2))
      assert.same(2, K.target())
      assert.same(2, K.position())
      assert.same(FILE, K.file())
    end)
  end)

  describe("IS3.9, a draft retained with Shift+Ins", function()
    spec_it("IS3.9 Preserve cursor through formatting: " ..
        "retained, at the draft's start, it stays there",
        function()
      retain({ "  z=3" }, 1, 0)
      assert.same("z = 3", K.draft())
      assert.same({
        1,
        1
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: " ..
        "retained, at the draft's end, it stays there",
        function()
      retain({ "z=3  " }, 1, 5)
      assert.same("z = 3", K.draft())
      assert.same({
        1,
        6
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: " ..
        "retained, before an element, it stays before it",
        function()
      -- "z  =  3", the cursor before "="
      retain({ "z  =  3" }, 1, 3)
      assert.same("z = 3", K.draft())
      assert.same({
        1,
        3
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: " ..
        "retained, inside an element, it keeps its offset",
        function()
      -- "a=1;foo=2", the cursor after "fo"
      retain({ "a=1;foo=2" }, 1, 6)
      assert.same("a = 1\nfoo = 2", K.draft())
      assert.same({
        2,
        3
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: " ..
        "retained, in a replaced gap, it goes before the next",
        function()
      -- "z   =   3", the cursor two spaces after "z"
      retain({ "z   =   3" }, 1, 3)
      assert.same("z = 3", K.draft())
      assert.same({
        1,
        3
      }, { K.cursor() })
    end)

    spec_it("IS3.9 Preserve cursor through formatting: " ..
        "retained, the mapping follows the same occurrence",
        function()
      -- "z=z+z", the cursor after the second "z"
      retain({ "z=z+z" }, 1, 3)
      assert.same("z = z + z", K.draft())
      assert.same({
        1,
        6
      }, { K.cursor() })
    end)
  end)

  describe("IS3.11 and IS3.12", function()
    spec_it("IS3.11 Preserve state on refusal: a refused move "
        .. "keeps a replacement as it was", function()
      edit(2)
      K.type("0")
      K.keys("home")
      K.keys("right")
      local before = held_state()
      K.keys("lalt", "up")
      assert.same(2, before.target)
      assert.same({
        1,
        2
      }, before.cursor)
      assert.same(before, held_state())
    end)

    spec_it("IS3.11 Preserve state on refusal: a refused Edit "
        .. "elsewhere keeps a replacement as it was", function()
      edit(2)
      K.type("0")
      K.keys("home")
      K.keys("right")
      K.keys("lctrl", "up")
      local before = held_state()
      K.keys("f2")
      assert.same(2, before.target)
      assert.same(1, before.position)
      assert.same("y = 20", before.draft)
      assert.same(before, held_state())
    end)

    spec_it("IS3.11 Preserve state on refusal: a write that "
        .. "fails keeps the draft and the cursor", function()
      at_end()
      K.type("z = 3")
      K.keys("left")
      local before = held_state()
      K.fail_writes("the card is full")
      K.keys("return")
      assert.same(before, held_state())
      --- a notice names the failure (IS1.7)
      assert.is_not_nil(K.message())
    end)

    spec_it("IS3.12 Keep deletion keys in the draft: at the "
        .. "ends of a replacement draft they change nothing",
        function()
      edit(2)
      K.keys("lctrl", "end")
      K.keys("delete")
      local at_its_end = held_state()
      K.keys("lctrl", "home")
      K.keys("backspace")
      assert.same({
        1,
        6
      }, at_its_end.cursor)
      assert.same("y = 2", at_its_end.draft)
      assert.same({
        draft = "y = 2",
        cursor = {
          1,
          1
        },
        position = 2,
        target = 2,
        file = FILE
      }, held_state())
    end)

    spec_it("IS3.12 Keep deletion keys in the draft: Ctrl+K "
        .. "leaves the cursor where it was", function()
      at_end()
      K.type_lines({
        "abc def",
        "gh"
      })
      K.keys("lctrl", "home")
      for _ = 1, 3 do
        K.keys("right")
      end
      K.keys("lctrl", "k")
      assert.same("abc\ngh", K.draft())
      assert.same({
        1,
        4
      }, { K.cursor() })
    end)

    spec_it("IS3.12 Keep deletion keys in the draft: Ctrl+K "
        .. "removes every row of a wrapped line", function()
      at_end()
      K.type_lines({
        "ab" .. string.rep("x", 150),
        "gh"
      })
      local rows = #K.field_rows()
      K.keys("lctrl", "home")
      K.keys("right")
      K.keys("right")
      K.keys("lctrl", "k")
      -- the long line took more than one row
      assert.is_true(2 < rows)
      assert.same("ab\ngh", K.draft())
      assert.same({
        1,
        3
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)
  end)

  describe("IS3.15", function()
    spec_it("IS3.15 Break a line: Shift+Enter breaks a " ..
        "replacement draft, the target kept", function()
      edit(2)
      K.keys("home")
      K.keys("right")
      K.keys("lshift", "return")
      assert.same({
        draft = "y\n = 2",
        cursor = {
          2,
          1
        },
        position = 2,
        target = 2,
        file = FILE
      }, held_state())
    end)

    spec_it("IS3.15 Break a line: Alt+Enter breaks a " ..
        "replacement draft, the target kept", function()
      edit(2)
      K.keys("home")
      K.keys("right")
      K.keys("lalt", "return")
      assert.same({
        draft = "y\n = 2",
        cursor = {
          2,
          1
        },
        position = 2,
        target = 2,
        file = FILE
      }, held_state())
    end)

    spec_it("IS3.15 Break a line: Shift+Enter breaks a draft "
        .. "whose syntax is wrong", function()
      at_end()
      K.type("z = = (")
      K.keys("left")
      K.keys("left")
      K.keys("lshift", "return")
      assert.same("z = =\n (", K.draft())
      assert.same({
        2,
        1
      }, { K.cursor() })
      assert.same(FILE, K.file())
      assert.same("end", K.position())
    end)

    spec_it("IS3.15 Break a line: Alt+Enter leaves the cursor "
        .. "at the start of the new line", function()
      at_end()
      K.type("abcd")
      K.keys("left")
      K.keys("left")
      K.keys("lalt", "return")
      assert.same("ab\ncd", K.draft())
      assert.same({
        2,
        1
      }, { K.cursor() })
      assert.same("end", K.position())
    end)

    spec_it("IS3.15 Break a line: Shift+Enter at the end of a "
        .. "complete draft submits nothing", function()
      at_end()
      K.type("z = 3")
      K.keys("lshift", "return")
      assert.same("z = 3\n", K.draft())
      assert.same({
        2,
        1
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)
  end)

  describe("IS3.16", function()
    spec_it("IS3.16 Show the key card: Escape does nothing to "
        .. "a draft while F1 is held", function()
      edit(2)
      K.type("0")
      local before = held_state()
      K.hold("f1")
      K.keys("escape")
      local card = K.key_card()
      K.release("f1")
      assert.is_not_nil(card)
      assert.same(before, held_state())
      assert.same("editor", K.app_state())
    end)

    spec_it("IS3.16 Show the key card: Escape does not leave "
        .. "the file while F1 is held", function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.hold("f1")
      K.keys("escape")
      local card = K.key_card()
      K.release("f1")
      assert.is_not_nil(card)
      assert.same("editor", K.app_state())
    end)

    spec_it("IS3.16 Show the key card: the card changes " ..
        "nothing of the edit", function()
      edit(2)
      K.type("0")
      K.keys("home")
      K.keys("lctrl", "up")
      local before = held_state()
      K.hold("f1")
      local card = K.key_card()
      local during = held_state()
      K.release("f1")
      assert.is_not_nil(card)
      assert.same(1, before.position)
      assert.same(2, before.target)
      assert.same(before, during)
      assert.same(before, held_state())
    end)

    spec_it("IS3.16 Show the key card: the status line shows "
        .. "its contents unchanged", function()
      edit(2)
      local before = K.status_text()
      K.hold("f1")
      local card = K.key_card()
      local during = K.status_text()
      K.release("f1")
      assert.is_not_nil(card)
      assert.same(before, during)
      assert.same(before, K.status_text())
    end)

    spec_it("IS3.16 Show the key card: once F1 is released, "
        .. "the card goes and the keys act again", function()
      at_end()
      K.hold("f1")
      K.type("z")
      local held = {
        K.draft(),
        K.key_card() ~= nil
      }
      K.release("f1")
      K.type("z")
      assert.same({
        "",
        true
      }, held)
      assert.is_nil(K.key_card())
      assert.same("z", K.draft())
    end)

    spec_it("IS3.16 Show the key card: a browsing key does " ..
        "nothing while F1 is held", function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.browse_to(2)
      K.hold("f1")
      K.keys("up")
      K.keys("f2")
      K.keys("lctrl", "delete")
      K.release("f1")
      assert.same(2, K.position())
      assert.same("browsing", K.state())
      assert.same(FILE, K.file())
    end)

    spec_it("IS3.16 Show the key card: Ctrl+Q does nothing " ..
        "while F1 is held", function()
      edit(2)
      K.type("0")
      local before = held_state()
      K.hold("f1")
      K.keys("lctrl", "q")
      local card = K.key_card()
      K.release("f1")
      assert.is_not_nil(card)
      assert.same("editor", K.app_state())
      assert.same("main.lua", K.file_name())
      assert.same(before, held_state())
    end)
  end)
end)
