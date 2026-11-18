require("view.editor.visibleStructuredContent")

local class = require("util.class")
local Layout = require("view.layout")
local Cue = require("view.continuationCue")
local WrapMark = require("view.wrapMark")
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
    more = { up = false, down = false },

    buffer = nil
  }
end

--- @class BufferView : ViewBase
--- @field content VisibleStructuredContent
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
  self.buffer = buffer
  if not self.buffer then
    error('no buffer')
  end
  self.content = VisibleStructuredContent({
      wrap_w = self.wrap_w,
      overscroll_max = self.SCROLL_BY,
      size_max = self.LINES,
      cfg = self.cfg,
    },
    buffer:get_content(),
    buffer:get_highlight())

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

function BufferView:refresh()
  if not self.content then
    error('no buffer is open')
  end
  self.content:wrap(self.buffer:get_text_content())
  self.content:load_blocks(self.buffer.content,
    self.buffer:get_highlight())
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
  local known = 0 < b and b <= #(cont.v_blocks)
  local pos = known and cont:get_block_pos(b)
  local lines = pos and pos:enumerate() or {}
  for _, l in ipairs(lines) do
    for _, r in ipairs(cont.wrap_forward[l] or {}) do
      out[#out + 1] = r
    end
  end
  return out
end

--- The first and the last of the view's rows of block `b`,
--- the ends of `_block_rows`, read from its first and last
--- lines alone: the cost does not grow with the block. None
--- for the end position.
--- @param b integer?
--- @return integer? first
--- @return integer? last
function BufferView:_block_span(b)
  local cont = self.content
  if not b or b < 1 or #(cont.v_blocks) < b then return nil end
  local pos = cont:get_block_pos(b)
  local a = pos and cont.wrap_forward[pos.start]
  local z = pos and cont.wrap_forward[pos.fin]
  if not (a and a[1] and z and z[#z]) then return nil end
  return a[1], z[#z]
end

--- Where the replacement target lies while the view draws no
--- row of its yellow highlight: '↑' above the view's first
--- row, '↓' below its last; nil while any row of it is drawn,
--- and with no target. It reads the rows the highlight is drawn
--- from (draw_highlight: the target's wrapped rows, _block_span,
--- within the content's range), so that it never says otherwise
--- than the view shows (review e7: a target's wrapped rows).
--- @return string?
function BufferView:target_side()
  local s, e = self:_block_span(self.buffer.loaded)
  if not s then return nil end
  local range = self.content.range
  if e < range.start then return '↑' end
  if range.fin < s then return '↓' end
  return nil
end

--- First and last view row of the browsing position; at the
--- end position the first lies past the last
--- @private
--- @return integer first
--- @return integer last
function BufferView:_browsed_rows()
  local s, e = self:_block_span(self.buffer:get_selection())
  if not s then
    local total = self.content:get_text_length()
    return total + 1, total
  end
  return s, e
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

--- Where PgDn or PgUp goes (the maintainer's ruling of
--- November 14, 2026), as browsing. While rows of the browsed
--- block are hidden beyond the view's edge in `dir`, the view
--- moves a page further into it, to the block's own edge at
--- most, and the browsing position stays (as IS2.2 does a row
--- at a time). Otherwise PgDn goes to the first block not
--- wholly visible below, shown from the view's top, and PgUp
--- to the last block not wholly visible above, shown to the
--- view's bottom; with none, PgDn goes to the end position
--- and PgUp to the first block, the view following.
--- @param dir VerticalDir
--- @return integer? b --- the block to browse to, nil while
--- the view moves through the browsed block
--- @return integer? top --- the view's first row, nil to
--- follow the browsing position
function BufferView:page(dir)
  --- the view as the person sees it: following the position
  --- first would move it by its row of context
  local top = self.content:get_range().start
  local h = self:get_height()
  local bottom = top + h - 1
  local s, e = self:_browsed_rows()
  if s <= e and dir == 'down' and bottom < e then
    return nil, math.min(bottom + 1, e - h + 1)
  end
  if s <= e and dir == 'up' and s < top then
    return nil, math.max(top - h, s)
  end
  local n = self.buffer:get_content_length()
  if dir == 'down' then
    for b = 1, n do
      local rows = self:_block_rows(b)
      if 0 < #rows and bottom < rows[#rows] then
        return b, rows[1]
      end
    end
    return n + 1, nil
  end
  for b = n, 1, -1 do
    local rows = self:_block_rows(b)
    if 0 < #rows and rows[1] < top then
      return b, math.max(1, rows[#rows] - h + 1)
    end
  end
  return 1, nil
end

--- Show the view from row `top`, as far as the file allows
--- @param top integer
function BufferView:show_from(top)
  self:_show_from(top)
end

--- Source line at a vertical pixel position, if any
--- @param y number
--- @return integer? ln
function BufferView:line_at(y)
  local pitch = self:row_height()
  local row = math.floor((y - self:top()) / pitch) + 1
  row = math.max(1, row)
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
--- screen's one row height, so that the view's rows are where
--- the console's output rows and the field's rows are.
--- @return number
function BufferView:row_height()
  return self.cfg.fh
end

--- Where the view's first row starts: under the strip the
--- screen may reserve at its top.
--- @return number
function BufferView:top()
  return Layout(self.cfg).top
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
  local content_text = vc:get_visible()
  local width, height = gfx.getDimensions()
  local range = vc.range
  local off = vc.offset
  local rows_n = self:get_height()
  --- The view draws whole rows only, on the screen's grid.
  --- What its rows leave above the status line, if anything,
  --- is the last row's: its background and highlight run on
  --- to the line. A strip reserved at the screen's top takes
  --- the first row's.
  local top = self:top()
  local edge = top + rows_n * fh
  local strip = 0
  if bottom then
    strip = math.max(0, bottom - edge)
  end

  --- @param v integer --- a wrapped row of the content
  --- @return number
  local function row_y(v)
    return top + (v - off - 1) * fh
  end

  local draw_background = function()
    gfx.push('all')
    gfx.setColor(colors.bg)
    gfx.rectangle("fill", 0, 0, width, height)
    gfx.setColor(Color.with_alpha(colors.fg, .0625))
    local n = math.min(#content_text, rows_n)
    if 0 < n then
      local bh = top + n * fh
      if n == rows_n then
        bh = bh + strip
      end
      gfx.rectangle("fill", 0, 0, width, bh)
    end
    gfx.pop()
  end

  local draw_highlight = function()
    --- the rows of a block from `s` to `e` that the view shows
    --- @param s integer?
    --- @param e integer?
    --- @param color RGB
    --- @param inset number
    local fill = function(s, e, color, inset)
      if not s then return end
      gfx.setColor(color)
      for v = math.max(s, range.start), math.min(e, range.fin) do
        local y, h = row_y(v), fh
        if v == off + rows_n then
          h = fh + strip
        end
        if v == range.start then
          y, h = 0, h + y
        end
        gfx.rectangle('fill', inset, y, width - 2 * inset, h)
      end
    end

    --- white on the browsed block; yellow, which stays, on
    --- the replacement target. Where the two are one block,
    --- the white shows as a strip one character cell wide at
    --- each side of the yellow.
    local sel = self.buffer:get_selection()
    local target = self.buffer.loaded
    local bs, be = self:_block_span(sel)
    if special then
      fill(bs, be, colors.highlight_special, 0)
    else
      fill(bs, be, colors.highlight, 0)
      if target then
        local inset = target == sel and fw or 0
        local ts, te = self:_block_span(target)
        fill(ts, te, colors.highlight_loaded, inset)
      end
    end
  end

  --- Rows of highlighted text, each on its row of the view
  --- when it is one; a row beyond the view's is not drawn.
  --- @param text string[]
  --- @param hl table?
  --- @param to_row fun(l: integer): integer --- the content's
  --- wrapped row of text's row `l`
  local draw_rows = function(text, hl, to_row)
    local color = colors.fg
    for l, line in ipairs(text) do
      local len = string.ulen(line)
      local v = to_row(l)
      if not len or range.fin < v then return end
      local shown = range.start <= v
      for c = 1, len do
        local ci = hl[l] and hl[l][c]
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
    for _, block in ipairs(vc:get_visible_blocks()) do
      local rs = block.app_pos.start
      --- @type WrappedText
      local wt = block.wrapped
      draw_rows(wt:get_text(), block.highlight,
        function(l) return l + rs - 1 end)
    end

    if love.DEBUG then
      --- phantom text
      gfx.setColor(Color.with_alpha(colors.fg, 0.3))
      local text = string.unlines(content_text)
      gfx.print(text, 0, top)
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

  --- The edges of the view that carry a continuation cue
  --- (FR4.8, IS2.2): those beyond which rows of the browsed
  --- block or of the replacement target lie, a block the view
  --- merely cuts has none; each with the kind of its row
  local sel = self.buffer:get_selection()
  local target = self.buffer.loaded
  local cut = { }
  do
    local function look(b, kind)
      local s, e = self:_block_span(b)
      if not s then return end
      if s < range.start and range.start <= e then
        cut.top = cut.top or kind
      end
      if range.fin < e and s <= range.fin then
        cut.bottom = cut.bottom or kind
      end
    end
    if target and not special then
      look(target, target == sel and 'both' or 'target')
    end
    look(sel, 'browsed')
  end

  --- a wrapped line's marks, under the text; a cue's edge row
  --- takes no mark in its last column, where the cue stands
  local draw_marks = function()
    local bare = { }
    if cut.top then bare[range.start] = true end
    if cut.bottom then bare[range.fin] = true end
    WrapMark.draw(WrapMark.places(vc.wrap_reverse, range.start,
      range.fin, vc:get_text_length(), bare), row_y, self.cfg.drawableChars * fw, fh,
      colors.wrap_mark)
  end

  --- The continuation cue at each edge in `cut`. The edge row
  --- fades into its own highlight.
  local draw_cues = function()
    local white = special and colors.highlight_special
        or colors.highlight
    local yellow = colors.highlight_loaded
    local paint = {
      browsed = { { x = 0, w = width, color = white } },
      target = { { x = 0, w = width, color = yellow } },
      both = {
        { x = 0, w = fw, color = white },
        { x = fw, w = width - 2 * fw, color = yellow },
        { x = width - fw, w = fw, color = white },
      },
    }
    for edge, kind in pairs(cut) do
      local v = edge == 'top' and range.start or range.fin
      Cue.draw({
        edge = edge, y = row_y(v), h = fh, width = width,
        fw = fw, font = font, theme = colors.cue,
        paint = paint[kind],
      })
    end
  end

  draw_background()
  draw_highlight()
  draw_marks()
  draw_text()
  draw_cues()
  draw_debuginfo()
end
