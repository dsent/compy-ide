require('model.editor.bufferModel')
local parser = require('model.lang.lua.parser')()

require('util.table')

describe('Buffer #editor', function()
  local w = 64
  local chunker = function(t, single)
    return parser.chunker(t, w, single)
  end

  local printer = parser.pprint
  local hl = parser.highlighter

  local noop = function() end

  it('renders plaintext', function()
    local l1 = 'line 1'
    local l2 = 'line 2'
    local l3 = 'x = 1'
    local l4 = 'the end'
    local tst = { l1, l2, l3, l4 }
    local cbuffer = BufferModel('untitled', tst, noop)
    local bc = cbuffer:get_content()
    assert.same('text', cbuffer.syntax.name)
    --- a block per line, and nothing after the last (IS8)
    assert.same(4, #bc)
    assert.same({ l1 }, bc[1].lines)
    assert.same({ l4 }, bc[4].lines)
    assert.is_nil(bc[5])
    assert.same(tst, cbuffer:get_text_content():items())
  end)

  --- blocks that would not give back every line as read are
  --- not trusted: the file comes a line per block, as text
  --- that does not parse does, every line as it is
  it('keeps every line when the blocks would lose one', function()
    local lua = require('model.syntax.lua')
    local lossy = setmetatable({
      blocks = function(t)
        local blocks = lua.blocks(t)
        if blocks and #blocks > 1 then blocks:remove(2) end
        return blocks
      end,
    }, { __index = lua })
    local text = { 'x = 1', '-- note', '', 'y = 2' }
    local buf = BufferModel('untitled.lua', text, noop, lossy)
    assert.same(text, buf:get_text_content():items())
    assert.is_true(buf.invalid)
    assert.same(4, buf:get_content_length())
  end)

  it('renders lua', function()
    local l1 = '--- comment 1'
    local l2 = '--- comment 2'
    local l3 = 'x = 1'
    local l4 = '--- comment end'
    local tst = { l1, l2, l3, l4 }
    local cbuffer = BufferModel('untitled.lua', tst, noop, chunker, hl)
    local bc = cbuffer:get_content()
    assert.same(cbuffer.content_type, 'lua')
    assert.same(4, #bc)
    assert.same({ l1 }, bc[1].lines)
    assert.same({ l2 }, bc[2].lines)
    assert.same({ l3 }, bc[3].lines)
    assert.same({ l4 }, bc[4].lines)
  end)

  describe('setup', function()
    local buffer, bufcon
    local meat = [[function sierpinski(depth)
  lines = { '*' }
  for z = 2, depth + 1 do
    sp = string.rep(' ', 2 ^ (z - 2))
    tmp = {} -- comment
    for idx, line in ipairs(lines) do
      tmp[idx] = sp .. line .. sp
      tmp[idx + #lines] = line .. ' ' .. line
    end
    lines = tmp
  end
  return table.concat(lines, '\n')
end]]
    local txt = string.lines([[--- @param depth integer
]] .. meat .. [[


print(sierpinski(4))]])

    lazy_setup(function()
      buffer = BufferModel('test.lua', txt,
        noop, chunker, hl)
      bufcon = buffer:get_content()
    end)
    it('sets name', function()
      assert.same('test.lua', buffer.name)
    end)
    it('sets content', function()
      assert.same('block', bufcon:type())
      assert.same(4, #bufcon)
      assert.same({ '--- @param depth integer' }, bufcon[1].lines)
      assert.same(string.lines(meat), bufcon[2].lines)
      assert.is_true(table.is_instance(bufcon[3], 'empty'))
      assert.same({ 'print(sierpinski(4))' }, bufcon[4].lines)
    end)
  end)

  describe('modifications', function()
    local trtl =
    'Turtle graphics game inspired the LOGO family of languages.'
    local turtle_doc = {
      '',
      trtl,
    }
    local turtle = {
      '--- @diagnostic disable',
      'width, height = gfx.getDimensions()',
      'midx = width / 2',
      'midy = height / 2',
      'incr = 5',
      '',
      'tx, ty = midx, midy',
      'debug = false',
      'debugColor = Color.yellow',
      '',
      'bg_color = Color.black',
      '',
      'local function drawHelp()',
      '  gfx.setColor(Color[Color.white])',
      '  gfx.print("Press [I] to open console", 20, 20)',
      '  gfx.print("Enter \'forward\', \'back\', \'left\', or \'right\' to move the turtle!", 20, 40)',
      'end',
      '',
      'local function drawDebuginfo()',
      '  gfx.setColor(Color[debugColor])',
      '  local label = string.format("Turtle position: (%d, %d)", tx, ty)',
      '  gfx.print(label, width - 200, 20)',
      'end',
      '',
      'function love.draw()',
      '  drawBackground()',
      '  drawHelp()',
      '  drawTurtle(tx, ty)',
      '  if debug then drawDebuginfo() end',
      'end',
      '',
      'function love.keypressed(key)',
      '  if love.keyboard.isDown("lshift", "rshift") then',
      '    if key == \'r\' then',
      '      tx, ty = midx, midy',
      '    end',
      '  end',
      '  if key == \'space\' then',
      '    debug = not debug',
      '  end',
      '  if key == \'pause\' then',
      '    stop()',
      '  end',
      'end',
      '',
      'function love.keyreleased(key)',
      '  if key == \'i\' then',
      '    input_text(r)',
      '  end',
      '  if key == \'return\' then',
      '    eval()',
      '  end',
      '',
      '  if love.keyboard.isDown("lctrl", "rctrl") then',
      '    if key == "escape" then',
      '      love.event.quit()',
      '    end',
      '  end',
      'end',
      '',
      'local t = 0',
      'function love.update(dt)',
      '  t = t + dt',
      '  if ty > midy then',
      '    debugColor = Color.red',
      '  end',
      'end',
      '',
    }
    local buffer
    describe('lua', function()
      local bc
      lazy_setup(function()
        buffer = BufferModel('main.lua', turtle,
          noop, chunker, hl)
        bc = buffer:get_content()
      end)
      local n_blocks = 25
      it('invariants', function()
        assert.same(n_blocks, #bc)
        assert.same(n_blocks, buffer:get_content_length())

        assert.same(turtle, buffer:get_text_content())

        assert.same(1, buffer:get_selection())
        local ln = buffer:get_selection_start_line()
        assert.same(1, ln)
        buffer:move_selection('down', nil, true)
        assert.same(n_blocks, buffer:get_selection())
        assert.same(68, buffer:get_selection_start_line())
      end)

      describe('line navigation', function()
        local lnbuf
        lazy_setup(function()
          lnbuf = BufferModel('main.lua', turtle,
            noop, chunker, hl)
        end)

        it('starts at the top', function()
          assert.same(1, lnbuf:get_selection())
          assert.same(1, lnbuf:get_active_line())
        end)

        it('walks lines within a block', function()
          local span = lnbuf:get_selection_lines()
          for _ = span.start, span.fin - 1 do
            assert.is_true(lnbuf:move_line('down'))
          end
          --- still inside block 1, on its last line
          assert.same(1, lnbuf:get_selection())
          assert.same(span.fin, lnbuf:get_active_line())
        end)

        it('crosses the boundary downwards', function()
          assert.is_true(lnbuf:move_line('down'))
          assert.same(2, lnbuf:get_selection())
          local span = lnbuf:get_selection_lines()
          assert.same(span.start, lnbuf:get_active_line())
        end)

        it('crosses back upwards', function()
          assert.is_true(lnbuf:move_line('up'))
          assert.same(1, lnbuf:get_selection())
          local span = lnbuf:get_selection_lines()
          assert.same(span.fin, lnbuf:get_active_line())
        end)

        it('clamps on block jumps', function()
          lnbuf:move_selection('down', nil, true)
          local span = lnbuf:get_selection_lines()
          assert.same(span.start, lnbuf:get_active_line())
          lnbuf:set_selection(3)
          span = lnbuf:get_selection_lines()
          assert.same(span.start, lnbuf:get_active_line())
        end)

        it('jumps blocks per 2.2', function()
          local jb = BufferModel('main.lua', turtle,
            noop, chunker, hl)
          --- down: the next block's first line
          assert.is_true(jb:jump_block('down'))
          assert.same(2, jb:get_selection())
          local sp = jb:get_selection_lines()
          assert.same(sp.start, jb:get_active_line())

          --- inside a multi-line block, up returns to
          --- its first line
          local multi
          for i = 1, jb:get_content_length() do
            jb:set_selection(i)
            if jb:get_selection_lines():len() > 1 then
              multi = i
              break
            end
          end
          assert.truthy(multi, 'fixture has a big block')
          jb:set_selection(multi)
          local spm = jb:get_selection_lines()
          jb:set_active_line(spm.fin)
          assert.is_true(jb:jump_block('up'))
          assert.same(multi, jb:get_selection())
          assert.same(spm.start, jb:get_active_line())

          --- already there: up goes to the block before
          assert.is_true(jb:jump_block('up'))
          assert.same(multi - 1, jb:get_selection())
          assert.same(jb:get_selection_lines().start,
            jb:get_active_line())

          --- walking up bottoms out at the first block
          while jb:jump_block('up') do end
          assert.same(1, jb:get_selection())
          assert.same(1, jb:get_active_line())
        end)

        it('plaintext follows the selection', function()
          local pb = BufferModel('notes.txt',
            { 'one', 'two', 'three' }, noop)
          assert.same(1, pb:get_active_line())
          assert.is_true(pb:move_line('down'))
          assert.same(2, pb:get_selection())
          assert.same(2, pb:get_active_line())
          assert.is_true(pb:move_line('up'))
          assert.same(1, pb:get_selection())
          assert.same(1, pb:get_active_line())
        end)
      end)

      it('dropping blocks', function()
        local delbuf = table.clone(buffer)
        delbuf:move_selection('up', nil, true)
        assert.same(1, delbuf:get_selection())
        delbuf:delete_selected_text()
        assert.same(n_blocks - 1, delbuf:get_content_length())
        delbuf:delete_selected_text()
        assert.same(n_blocks - 2, delbuf:get_content_length())
        assert.same(1, delbuf:get_selection())
        assert.same({ turtle[3] }, delbuf:get_selected_text())
      end)

      --- end ---
    end)
  end)
end)
