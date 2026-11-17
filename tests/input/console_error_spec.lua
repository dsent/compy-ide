-- An error message: how a project's field draws one in its
-- own place, and what the console's keys do while its message
-- shows in the notice band (the ruling "The console shows an
-- error as the editor does"; doc/development/internals/
-- user_input.md, "Error state"). A line the console does not
-- take stays in the field to be corrected, and the next key
-- dismisses the message and does its work.
--
-- Every case drives the full route (F.session), the way a
-- keystroke arrives from LÖVE: key press, then its glyph, then
-- the release.

local F = require('tests.helpers.input_fixture')

describe('console error message #input', function()
  setup(function() F.setup() end)
  teardown(function() F.teardown() end)
  before_each(function() F.reset() end)

  --- a line the console does not take: it parses, and Lua
  --- refuses to load it, so its message shows in the band (a
  --- line that runs and fails says so in the output; the
  --- maintainer's ruling of November 15, 2026)
  local failing = 'break'

  --- One keystroke of a character, as a keyboard sends it.
  --- @param ch string
  local function key(ch)
    F.session.press(ch)
    F.session.type(ch)
    F.session.release(ch)
  end

  --- @param s string
  local function type_line(s)
    for ch in s:gmatch('.') do key(ch) end
  end

  --- @param k string
  local function stroke(k)
    F.session.press(k)
    F.session.release(k)
  end

  --- Submit a line that fails and leave its message up.
  local function fail()
    type_line(failing)
    stroke('return')
    assert.is_true(F.console:has_error())
  end

  local function text()
    return table.concat(F.console:get_text(), '\n')
  end

  -- A failed require lists every path it tried, one per line
  -- after a tab. The message used to be wrapped with those
  -- line breaks inside it, and each wrapped piece was printed
  -- with its own breaks too, so pieces ran over the rows below
  -- them. A project's field shows its error in the field's
  -- place; the console shows its own in the notice band
  -- (tests/editor/spec/added_console_notice_spec.lua).
  describe('drawing in a project\'s field', function()
    --- The field's error, as a project's validator gives it
    --- @param errors any
    local function set_error(errors)
      F.widget:set_error(errors)
    end

    --- The failed require's message
    local function fail()
      local _, e = pcall(require, 'nosuch')
      set_error({ e })
    end

    --- Draw the message with a recording gfx.
    --- @return { s: string, y: number }[]
    local function draw_error()
      local rows = { }
      local prev = _G.gfx
      _G.gfx = setmetatable({
        getHeight = function() return 600 end,
        print = function(s, _, y)
          rows[#rows + 1] = { s = s, y = y }
        end,
      }, { __index = function() return function() end end })
      local ok, err = pcall(function()
        local view = UserInputView(F.cfg.view, F.widget)
        view:render_error(F.widget:get_wrapped_error())
      end)
      _G.gfx = prev
      assert(ok, err)
      return rows
    end

    it('puts every line of the message on a row of its own',
      function()
        fail()
        local rows = draw_error()
        local ys = { }
        for _, r in ipairs(rows) do
          assert.is_nil(r.s:find('[\n\t]'),
            'row carries a break: ' .. r.s)
          assert.is_true(
            string.ulen(r.s) <= F.cfg.view.drawableChars,
            'row wider than the screen: ' .. r.s)
          assert.is_nil(ys[r.y], 'two rows at y=' .. r.y)
          ys[r.y] = true
        end
        assert.equal('Errors:', rows[1].s)
        assert.truthy(rows[2].s:find("module 'nosuch' not found"))
      end)

    it('keeps a program\'s own colours: the theme\'s error on '
      .. 'error_bg, not the notice band\'s', function()
      fail()
      local c = F.cfg.view.colors.input
      -- the band's colours apart from the field's, for this
      -- draw: today both are black and red
      local saved = c.notice
      c.notice = { bg = { 0, 0, 1, 1 }, error = { 0, 1, 0, 1 },
        warning = { 0, 1, 0, 1 } }
      local fills, texts, colour = { }, { }, nil
      local prev = _G.gfx
      _G.gfx = setmetatable({
        getHeight = function() return 600 end,
        setColor = function(col) colour = col end,
        rectangle = function() fills[#fills + 1] = colour end,
        print = function() texts[#texts + 1] = colour end,
      }, { __index = function() return function() end end })
      local ok, err = pcall(function()
        local view = UserInputView(F.cfg.view, F.widget)
        view:render_error(F.widget:get_wrapped_error())
      end)
      _G.gfx = prev
      c.notice = saved
      assert(ok, err)
      assert.equal(c.error_bg, fills[#fills])
      assert.equal(c.error, texts[#texts])
    end)

    it('fits the rows the input area has', function()
      fail()
      local rows = draw_error()
      assert.is_true(#rows <= F.cfg.view.input_max,
        #rows .. ' rows drawn')
    end)

    it('shows the head of a long message and ends in ...',
      function()
        local msg = { 'first line' }
        for i = 1, 30 do
          msg[#msg + 1] = '\tpath ' .. i
        end
        set_error({ table.concat(msg, '\n') })
        local rows = draw_error()
        local max = F.cfg.view.input_max
        assert.equal(max, #rows)
        assert.equal('Errors:', rows[1].s)
        assert.equal('first line', rows[2].s)
        assert.equal('  path 1', rows[3].s)
        assert.equal('...', rows[max].s)
      end)

    --- A message of n lines under the header.
    --- @param n integer
    local function set_lines(n)
      local msg = { }
      for i = 1, n do msg[i] = 'line ' .. i end
      set_error({ table.concat(msg, '\n') })
    end

    it('draws a message of exactly the rows whole', function()
      local max = F.cfg.view.input_max
      set_lines(max - 1)
      local rows = draw_error()
      assert.equal(max, #rows)
      assert.equal('line ' .. (max - 1), rows[max].s)
    end)

    it('ends a message one row too tall in ...', function()
      local max = F.cfg.view.input_max
      set_lines(max)
      local rows = draw_error()
      assert.equal(max, #rows)
      assert.equal('line ' .. (max - 2), rows[max - 1].s)
      assert.equal('...', rows[max].s)
    end)

    -- A message from a file or a program may break its lines
    -- with \r\n or \r; the \r must not count as a character.
    it('breaks a line at \\r\\n and \\r as at \\n', function()
      local w = F.cfg.view.drawableChars
      set_error({
        string.rep('a', w) .. '\r\n' .. 'tail\rend' })
      assert.same(
        { 'Errors:', string.rep('a', w), 'tail', 'end' },
        F.widget:get_wrapped_error())
    end)
  end)

  describe('keys', function()
    it('a glyph typed over the message closes it and lands',
      function()
        fail()
        key('x')
        assert.is_false(F.console:has_error())
        assert.equal(failing .. 'x', text())
      end)

    -- The device may deliver a glyph before its key press.
    it('a glyph that comes before its key lands once',
      function()
        fail()
        F.session.type('x')
        F.session.press('x')
        F.session.release('x')
        assert.is_false(F.console:has_error())
        assert.equal(failing .. 'x', text())
      end)

    -- The message is a hint, not a dialog (IS3.14): Escape
    -- dismisses it and does the console's Escape, which
    -- clears the line
    it('Escape dismisses the message and clears the line',
      function()
        fail()
        stroke('escape')
        assert.is_false(F.console:has_error())
        assert.equal('', text())
      end)

    it('Backspace closes the message and deletes', function()
      fail()
      stroke('backspace')
      assert.is_false(F.console:has_error())
      assert.equal(failing:sub(1, -2), text())
    end)

    -- The report's walk: erase the failed line, type a good
    -- one, press Enter, and it runs.
    it('a line retyped after an error runs on Enter',
      function()
        fail()
        for _ = 1, #failing do stroke('backspace') end
        type_line('print(333)')
        assert.equal('print(333)', text())
        stroke('return')
        assert.is_false(F.console:has_error())
        assert.equal('', text())
      end)

    -- the failing line was not taken, so the history holds
    -- the line before it: Up shows that one
    it('Up dismisses the message and walks the history',
      function()
        type_line('x=1')
        stroke('return')
        fail()
        stroke('up')
        assert.is_false(F.console:has_error())
        assert.equal('x=1', text())
      end)

    --- Count the runs of the input while f is called.
    --- @param f function
    --- @return integer
    local function runs(f)
      local n = 0
      local orig = F.cc.evaluate_input
      F.cc.evaluate_input = function(...)
        n = n + 1
        return orig(...)
      end
      local ok, err = pcall(f)
      F.cc.evaluate_input = orig
      assert(ok, err)
      return n
    end

    --- @param mod string
    --- @param k string
    local function chord(mod, k)
      F.session.press(mod)
      stroke(k)
      F.session.release(mod)
    end

    it('Enter dismisses the message and runs the line again',
      function()
        fail()
        local n = runs(function() stroke('return') end)
        assert.equal(1, n)
        assert.is_true(F.console:has_error())
        assert.equal(failing, text())
      end)

    -- A modifier pressed on its own leaves the message up; the
    -- key it is held for dismisses it and does the chord's work:
    -- Shift+Enter and Alt+Enter break the line, and Ctrl+Enter
    -- is bound to nothing
    for _, case in ipairs({
      { 'lctrl', failing },
      { 'lalt', failing .. '\n' },
      { 'lshift', failing .. '\n' },
    }) do
      local mod, want = case[1], case[2]
      it(mod .. '+Enter dismisses the message and runs nothing',
        function()
          fail()
          local n = runs(function() chord(mod, 'return') end)
          assert.equal(0, n)
          assert.is_false(F.console:has_error())
          assert.equal(want, text())
        end)
    end

    it('Shift+Escape dismisses the message and keeps the line',
      function()
        fail()
        chord('lshift', 'escape')
        assert.is_false(F.console:has_error())
        assert.equal(failing, text())
      end)

    -- Shift's own press leaves the message up; a field has no
    -- selection (the ruling of November 14, 2026), so
    -- Shift+Home dismisses the message and does nothing else
    it('Shift+Home dismisses the message, and a glyph is added',
      function()
        fail()
        F.session.press('lshift')
        stroke('home')
        F.session.release('lshift')
        assert.is_false(F.console:has_error())
        key('x')
        assert.equal(failing .. 'x', text())
      end)
  end)
end)
