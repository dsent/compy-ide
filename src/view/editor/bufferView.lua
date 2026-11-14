require("model.input.cursor")
require("view.editor.visibleContent")
require("view.editor.visibleStructuredContent")

local class = require("util.class")
require("util.scrollable")
require("util.table")
-- local B = require("util.block")

--- @param cfg ViewConfig
local function new(cfg)
  local l = cfg.lines

  return {
    cfg = cfg,
    LINES = l,
    SCROLL_BY = math.floor(l / 2),
    wrap_w = cfg.drawableChars,

    content = nil,
    content_type = nil,
    more = { up = false, down = false },

    buffer = nil
  }
end

--- @class BufferView : ViewBase
--- @field content VisibleContent|VisibleStructuredContent
--- @field content_type ContentType
--- @field buffers Dequeue<BufferModel>
---
--- @field cfg ViewConfig
--- @field LINES integer
--- @field SCROLL_BY integer
--- @field wrap_w integer
--- @field more More
---
--- @field open function
--- @field refresh function
BufferView = class.create(new)

--- @private
--- @param r Range
function BufferView:_update_visible(r)
  self.content:set_range(r)
end

--- @param buffer BufferModel
function BufferView:open(buffer)
  local L = self.LINES
  self.buffer = buffer
  if not self.buffer then
    error('no buffer')
  end
  local ct = buffer.content_type
  self.content_type = ct

  if ct == 'plain' or ct == 'md' then
    local bufcon = buffer:get_text_content()
    self.buffer:highlight()
    self.content = VisibleContent(
      self.wrap_w, bufcon, self.SCROLL_BY, L)
    self.hl = self.buffer:get_highlight()
  elseif ct == 'lua' then
    local bufcon = buffer:get_content()
    self.content =
        VisibleStructuredContent({
            wrap_w = self.wrap_w,
            overscroll_max = self.SCROLL_BY,
            size_max = L,
            cfg = self.cfg,
          },
          bufcon,
          buffer.highlighter)
  else
    error 'unknown filetype'
  end

  local off = self.content.offset
  if off > 0 then
    self.more.up = true
  end

  local ir = self:_get_end_range()
  self:_update_visible(ir)
end

--- @return integer
function BufferView:get_max_size()
  --- the block limit is the input view height (spec: 14),
  --- not the buffer viewport height
  return self.cfg.input_max
end

--- @param moved integer?
function BufferView:refresh(moved)
  if not self.content then
    error('no buffer is open')
  end
  local text = self.buffer:get_text_content()
  self.hl = self.buffer:get_highlight()

  self.content:wrap(text)
  if self.content_type == 'lua' then
    self.content:load_blocks(self.buffer.content)
  end

  if moved then
    local sel = self.buffer:get_selection()
    if self.content_type == 'lua' then
      local vsc = self.content
      local blocks = vsc.v_blocks
      blocks:move(moved, sel)
      vsc:recalc_range()
    else
      local t = Dequeue(text)
      t:move(moved, sel)
      self.content:wrap(t)
    end
  end

  self:_show_from(1 + self.content.offset)
end

-------------------
---  scrolling  ---
-------------------

--- @return integer
function BufferView:get_offset()
  return self.content.offset
end

--- @private
--- @return Range
function BufferView:_get_end_range()
  local clen = self.content:get_text_length()
  return Scrollable.calculate_end_range(self.LINES, clen)
end

--- @param dir VerticalDir
--- @param by integer?
--- @param warp boolean?
function BufferView:scroll(dir, by, warp)
  local by = by or self.SCROLL_BY
  local l = self.content:get_content_length()
  local n = (function()
    if dir == 'up' then
      if warp then
        return -l
      else
        return -by
      end
    else
      local er = self:_get_end_range()
      local c = self.content:get_range()
      if warp then
        return er.start - c.start
      else
        return by
      end
    end
  end)()
  self.content:move_range(n)
end

--- @param off integer
function BufferView:scroll_to(off)
  self:scroll('up', nil, true)
  self:scroll('down', off)
end

--- Scroll so that source line `ln` is the top line
--- @param ln integer
function BufferView:scroll_to_line(ln)
  local wl = self.content.wrap_forward[ln]
  if not wl then return end
  self:scroll_to(wl[1] - 1)
end

--- The view's rows of block `b`, wrapped rows included;
--- none for the end position, which has no row of its own
--- @param b integer
--- @return integer[]
function BufferView:_block_rows(b)
  local cont = self.content
  local out = {}
  local lines = { b }
  if self.content_type == 'lua' then
    local known = 0 < b and b <= #(cont.v_blocks)
    local pos = known and cont:get_block_pos(b)
    lines = pos and pos:enumerate() or {}
  elseif b < 1 or cont:get_text_length() < 1
      or self.buffer:get_content_length() < b then
    lines = {}
  end
  for _, l in ipairs(lines) do
    for _, r in ipairs(cont.wrap_forward[l] or {}) do
      out[#out + 1] = r
    end
  end
  return out
end

--- First and last view row of the browsing position; at the
--- end position the first lies past the last
--- @private
--- @return integer first
--- @return integer last
function BufferView:_browsed_rows()
  local rows = self:_block_rows(self.buffer:get_selection())
  local total = self.content:get_text_length()
  if #rows == 0 then
    return total + 1, total
  end
  return rows[1], rows[#rows]
end

--- The rows the document view has: the field's rows above
--- its first cover the view's last ones
--- @return integer
function BufferView:get_height()
  return math.max(1, self.LINES - (self.covered or 0))
end

--- @param n integer --- view rows the editor field covers
function BufferView:set_covered(n)
  local covered = math.max(0, n or 0)
  if covered == (self.covered or 0) then return end
  self.covered = covered
  if self.content then self:follow_selection() end
end

--- @private
--- @param top integer --- the view's first row
function BufferView:_show_from(top)
  local total = self.content:get_text_length()
  local h = self:get_height()
  local first = math.max(1, math.min(top, total - h + 1))
  local last = math.min(first + h - 1, total + 1)
  self.content:set_range(Range(first, last))
  self.content.offset = first - 1
end

--- The view's first row once it shows rows `s` to `e` of
--- `total`: a block that fits gets a row of context on each
--- side where there is room; a taller one keeps the view
--- inside its rows, so it shows from its first row when the
--- view was above it and from its last when it was below.
--- @param top integer
--- @param total integer
--- @param s integer
--- @param e integer
--- @param h integer
--- @return integer
local function settle(top, total, s, e, h)
  local n = e - s + 1
  if h < n then
    return math.max(s, math.min(top, e - h + 1))
  end
  local margin = (2 < h and n + 2 <= h) and 1 or 0
  local from = math.max(1, s - margin)
  local to = math.min(total, e + margin)
  if from < top then
    return from
  end
  if top + h - 1 < to then
    return math.min(to - h + 1, from)
  end
  return top
end

--- Show the browsing position: the browsed block with its
--- context, or the end of the file at the end position
function BufferView:follow_selection()
  local s, e = self:_browsed_rows()
  local total = self.content:get_text_length()
  local top = self.content:get_range().start
  self:_show_from(settle(top, total, s, e, self:get_height()))
end

--- While a row of the browsed block is hidden beyond the
--- view's edge in `dir`, scroll one row that way; the
--- browsing position stays
--- @param dir VerticalDir
--- @return boolean scrolled
function BufferView:scroll_block(dir)
  local s, e = self:_browsed_rows()
  if e < s then return false end
  self:follow_selection()
  local top = self.content:get_range().start
  local bottom = top + self:get_height() - 1
  if dir == 'down' and bottom < e then
    self:_show_from(top + 1)
    return true
  end
  if dir == 'up' and s < top then
    self:_show_from(top - 1)
    return true
  end
  return false
end

--- Source line at a vertical pixel position, if any
--- @param y number
--- @return integer? ln
function BufferView:line_at(y)
  local row = math.max(1, math.floor(y / self:row_height()) + 1)
  local wrapped = self.content.offset + row
  if not self.content.range:inc(wrapped) then
    return nil
  end
  local rev = self.content.wrap_reverse
  return rev and rev[wrapped]
end

--- Scroll just enough to keep the active line visible
function BufferView:follow_line()
  local al = self.buffer:get_active_line()
  local wl = self.content.wrap_forward[al]
  if not wl then return end
  local r = self.content.range
  local first = wl[1]
  local last = wl[#wl]
  if first < r.start then
    self:scroll('up', r.start - first)
  elseif last > r.fin then
    self:scroll('down', last - r.fin)
  end
end

--------------
---  draw  ---
--------------

--- The height of one row of the view, in pixels: the
--- console's, the font's height at the configured line
--- height, so that the view's rows are where the console's
--- output rows are and 16 of them fill the space above the
--- status line.
--- @return number
function BufferView:row_height()
  return self.cfg.fh * self.cfg.lh
end

--- @param special boolean
--- @param bottom number? --- where the view's area ends: the
--- top of the status line's band
function BufferView:draw(special, bottom)
  local gfx = love.graphics
  local cf_colors = self.cfg.colors
  local colors = cf_colors.editor
  local font = self.cfg.font
  local fh = self:row_height()
  local fw = self.cfg.fw
  local vc = self.content
  --- @type VisibleContent|VisibleStructuredContent
  local content_text = vc:get_visible()
  local width, height = gfx.getDimensions()
  local range = vc.range
  local off = vc.offset
  local rows_n = self:get_height()
  --- The view draws whole rows only, from the screen's top.
  --- What its rows leave above the status line is the last
  --- row's: its background and highlight run on to the line.
  local edge = rows_n * fh
  local strip = 0
  if bottom then
    strip = math.max(0, bottom - edge)
  end

  --- @param v integer --- a wrapped row of the content
  --- @return number
  local function row_y(v)
    return (v - off - 1) * fh
  end

  local draw_background = function()
    gfx.push('all')
    gfx.setColor(colors.bg)
    gfx.rectangle("fill", 0, 0, width, height)
    gfx.setColor(Color.with_alpha(colors.fg, .0625))
    local n = math.min(#content_text, rows_n)
    if 0 < n then
      local bh = n * fh
      if n == rows_n then
        bh = bh + strip
      end
      gfx.rectangle("fill", 0, 0, width, bh)
    end
    gfx.pop()
  end

  local draw_highlight = function()
    --- @param rows integer[]
    --- @param color RGB
    --- @param inset number
    local fill = function(rows, color, inset)
      gfx.setColor(color)
      for _, v in ipairs(rows) do
        if range:inc(v) then
          local h = fh
          if v == off + rows_n then
            h = fh + strip
          end
          gfx.rectangle('fill', inset, row_y(v),
            width - 2 * inset, h)
        end
      end
    end

    --- white on the browsed block; yellow, which stays, on
    --- the replacement target. Where the two are one block,
    --- the white shows as a strip one character cell wide at
    --- each side of the yellow.
    local sel = self.buffer:get_selection()
    local target = self.buffer.loaded
    local browsed = self:_block_rows(sel)
    if special then
      fill(browsed, colors.highlight_special, 0)
    else
      fill(browsed, colors.highlight, 0)
      if target then
        local inset = target == sel and fw or 0
        fill(self:_block_rows(target),
          colors.highlight_loaded, inset)
      end
    end
  end

  --- Rows of highlighted text, each on its row of the view
  --- when it is one; a row beyond the view's is not drawn.
  --- @param text string[]
  --- @param hl table?
  --- @param to_row fun(l: integer): integer --- the content's
  --- wrapped row of text's row `l`
  --- @param ctf fun(c: Cursor): Cursor?
  local draw_rows = function(text, hl, to_row, ctf)
    local color = colors.fg
    for l, line in ipairs(text) do
      local len = string.ulen(line)
      local v = to_row(l)
      if not len or range.fin < v then return end
      local shown = range.start <= v
      for c = 1, len do
        local tlc = hl and ctf(Cursor(l, c))
        local ci = tlc and hl[tlc.l] and hl[tlc.l][tlc.c]
        if ci then
          color = Color[ci] or colors.fg
        end
        if shown then
          local char = string.usub(line, c, c)
          gfx.setColor(color)
          ViewUtils.write_token(row_y(v), (c - 1) * fw, char,
            color, colors.bg, false)
        end
      end
    end
  end

  local draw_text = function()
    gfx.setFont(font)
    local same = function(a) return a end
    if self.content_type == 'lua' then
      for _, block in ipairs(vc:get_visible_blocks()) do
        local rs = block.app_pos.start
        --- @type WrappedText
        local wt = block.wrapped
        draw_rows(wt:get_text(), block.highlight,
          function(l) return l + rs - 1 end, same)
      end

      if love.DEBUG then
        --- phantom text
        gfx.setColor(Color.with_alpha(colors.fg, 0.3))
        local text = string.unlines(content_text)
        gfx.print(text)
      end
    elseif self.content_type == 'md' then
      draw_rows(content_text, self.hl,
        function(l) return l + off end,
        function(a)
          --- @diagnostic disable-next-line: param-type-mismatch
          return vc:translate_from_visible(a)
        end)
    elseif self.content_type == 'plain' then
      gfx.setColor(colors.fg)
      for l, line in ipairs(content_text) do
        local v = l + off
        if range:inc(v) then
          gfx.print(line, 0, row_y(v))
        end
      end
    end
  end

  local draw_debuginfo = function()
    if not love.DEBUG then return end
    local showap = false
    local lnc = colors.fg
    local x = self.cfg.w - font:getWidth('   ') - 3
    local lnvc = Color.with_alpha(lnc, 0.2)
    gfx.setColor(lnvc)
    gfx.rectangle("fill", x, 0, 2, self.cfg.h)
    local seen = {}
    for ln = 1, rows_n do
      local vln = ln + off
      local l_y = row_y(vln)
      local ln_w = self.content.wrap_reverse[vln]
      if ln_w then
        local l = string.format('%3d', ln_w)
        local l_x = self.cfg.w - font:getWidth(l)
        local l_xv = l_x - font:getWidth(l) - 3.5
        if showap then
          gfx.setColor(lnvc)
          gfx.print(string.format('%3d', vln), l_xv, l_y)
        end
        if not seen[ln_w] then
          gfx.setColor(lnc)
          gfx.print(l, l_x, l_y)
          seen[ln_w] = true
        end
      end
    end
  end

  draw_background()
  draw_highlight()
  draw_text()
  draw_debuginfo()
end
