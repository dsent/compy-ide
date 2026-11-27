require("view.input.statusline")

local class = require('util.class')
local Layout = require("view.layout")
local Cue = require("view.continuationCue")
local WrapMark = require("view.wrapMark")
local Blink = require('view.input.cursorBlink')
local own = require('view.ownState')
require("util.debug")
require("util.view")


--- @param cfg ViewConfig
--- @param ctrl UserInputController
local new = function(cfg, ctrl)
  local gfx = love.graphics
  local w = gfx.getWidth()
  --- the statusline, max lines, and the strip under them
  local l = Layout(cfg)
  local h = l.status_h + cfg.input_max * cfg.fh + l.bottom
  return {
    cfg = cfg,
    controller = ctrl,
    statusline = Statusline(cfg),
    start_h = h,
    canvas = gfx.newCanvas(w, h),
  }
end

--- @class UserInputView : ViewBase
--- @field controller UserInputController
--- @field statusline table
--- @field canvas love.Canvas
--- @field field_hidden boolean? --- the console's field behind a program that owns the input: its status line alone
--- @field bare_status Status? --- what the status line says while no field is drawn under it; it is then the screen's last row
--- @field bare_drawn string? --- what the canvas holds while it holds that status line alone (_bare_key)
--- @field ide_shown string? --- the IDE's state its last render's status line was drawn in (Statusline:ide_key)
UserInputView = class.create(new)

local get_colors = function(cf_colors)
  if love.state.app_state == 'inspect' then
    return cf_colors.input.inspect
  elseif love.state.app_state == 'running' then
    return cf_colors.input.user
  else
    return cf_colors.input.console
  end
end

--- The rows the field takes for `input`, the statusline
--- apart: the draft's rows up to the field's display limit
--- (IS3.13), or the rows of an error shown in its place
--- @param input InputDTO
--- @return integer
function UserInputView:get_rows(input)
  local max = self.cfg.input_max
  local err = input.wrapped_error or {}
  local draft = self:_draft_rows(input)
  if self:_message_elsewhere() then return draft end
  if string.is_non_empty_string_array(err) then
    return math.min(#err, max)
  end
  return draft
end

--- Where the status line starts on the screen when the field
--- takes `rows` rows under it: the field's rows end at the
--- screen's bottom, or at the strip reserved there.
--- @param rows integer
--- @return number
function UserInputView:status_y(rows)
  local l = Layout(self.cfg)
  return love.graphics.getHeight() - l.bottom
      - rows * self.cfg.fh - l.status_h
end

--- Where the field's row `r` starts in the field's canvas,
--- under the status line.
--- @param r number
--- @return number
function UserInputView:row_y(r)
  return Layout(self.cfg).status_h
      + (r - 1) * self.cfg.fh
end

--- The draft's cell under a point of the screen: its wrapped
--- row and the column, nil outside the rows the field shows.
--- The field's rows end at the screen's bottom (status_y),
--- the first showing the visible range's first row. A field
--- that shows an error in the draft's place has no cell.
--- @param x number
--- @param y number
--- @param input InputDTO
--- @return integer? row --- of the draft's wrapped rows
--- @return integer? col --- where a click puts the cursor
--- @return integer? cell --- the column of the cell itself
function UserInputView:cell_at(x, y, input)
  local cfg = self.cfg
  if not self:_message_elsewhere()
      and string.is_non_empty_string_array(input.wrapped_error)
  then
    return nil
  end
  local rows = self:_draft_rows(input)
  local top = self:status_y(rows) + self:row_y(1)
  local inside = top <= y and y < top + rows * cfg.fh
      and 0 <= x
  if not inside then return nil end
  local row = math.floor((y - top) / cfg.fh) + 1
  local a, b = math.modf(x / cfg.fw)
  --- a click on a cell's right half lands after it
  local col = a + 1 + (b > .5 and 1 or 0)
  return row + input.visible.offset, col, a + 1
end

--- Whether a message leaves this field as it is: the file
--- editor and the console show their messages in the notice
--- band (draw_notice), and neither the field nor the status
--- line moves for one (IS3.14). A project's input shows an
--- error in the field's place.
--- @private
--- @return boolean
function UserInputView:_message_elsewhere()
  return self.controller.model.message_band == true
end

--- The rows a message may take in the band: one, or up to
--- three when it is wider than the screen
local NOTICE_ROWS = 3

--- The rows of the message the band shows, nil when none
--- shows; one longer than the band ends in an ellipsis.
--- @return string[]?
function UserInputView:notice_rows()
  if not self:_message_elsewhere() then return nil end
  local all = self.controller:get_wrapped_error()
  if not all or #all == 0 then return nil end
  local rows = { }
  for i = 1, math.min(#all, NOTICE_ROWS) do
    rows[i] = all[i]
  end
  if #all > NOTICE_ROWS then
    local w = self.cfg.drawableChars
    local last = string.usub(rows[NOTICE_ROWS], 1, w - 1)
    rows[NOTICE_ROWS] = last .. '…'
  end
  return rows
end

--- The colour of a message's text in the band: an error's
--- or a notice's (`colors.input.notice`).
--- @private
--- @return RGB
function UserInputView:_notice_color()
  local colors = self.cfg.colors
  if self.controller:message_kind() == 'notice' then
    return colors.input.notice.warning
  end
  return colors.input.notice.error
end

--- The notice band: a message, a notice or an error's,
--- directly above the status line, over the last rows of
--- what is drawn above it (IS3.14). It is a hint that blocks
--- nothing: neither the status line nor the field moves for
--- it, and what is above neither scrolls nor is laid out
--- again; the rows under it are hidden until the next key.
--- The rows above are `pitch` high from `origin`, and the
--- band covers each of them it reaches into whole. Call
--- after the field's draw, which places the status line.
--- @param pitch number
--- @param origin number
--- @param bottom number? --- top of the visible status line; defaults to self.start_h
function UserInputView:draw_notice(pitch, origin, bottom)
  local rows = self:notice_rows()
  if not rows then return end
  local err = self.controller.model.error
  if type(err) == 'table' then err.seen = true end
  local cf = self.cfg
  local fh = cf.fh
  local width = gfx.getWidth()
  bottom = bottom or self.start_h
  local top = bottom - #rows * fh
  local from = origin
      + math.floor((top - origin) / pitch) * pitch

  gfx.push('all')
  gfx.setFont(cf.font)
  gfx.setColor(cf.colors.input.notice.bg)
  gfx.rectangle('fill', 0, from, width, bottom - from)
  gfx.setColor(self:_notice_color())
  for i, row in ipairs(rows) do
    gfx.print(row, 0, top + (i - 1) * fh)
  end
  gfx.pop()
end

--- The draft's rows in the field, up to its display limit
--- (IS3.13). A line's end is on its last row, also when the
--- row is full, as the model has it.
--- @private
--- @param input InputDTO
--- @return integer
function UserInputView:_draft_rows(input)
  local vc = input.visible
  local cap = vc.size_max or self.cfg.input_max
  return math.max(1, math.min(vc:get_content_length(), cap))
end

--- @param input InputDTO
--- @param status Status
function UserInputView:render_input(input, status, time)
  local gfx = love.graphics
  local cfg = self.cfg
  local cf_colors = cfg.colors
  local colors = get_colors(cf_colors)

  local fh = cfg.fh
  local fw = cfg.fw
  local drawableWidth = cfg.drawableWidth
  local w = cfg.drawableChars
  -- drawtest hack
  if drawableWidth < gfx.getWidth() / 3 then
    w = w * 2
  end

  local cursorInfo = self.controller:get_cursor_info()
  local cl, cc = cursorInfo.cursor.l, cursorInfo.cursor.c
  local acc = cc - 1

  local text = input.text
  local vc = input.visible
  local inLines = self:_draft_rows(input)

  --- the field's row of the draft's wrapped row `r`
  local function field_row(r)
    return r - vc.offset
  end

  local inHeight = inLines * fh
  local apparentHeight = inHeight

  local wrap_forward = vc.wrap_forward


  self.start_h = self:status_y(self.bare_status and 0 or inLines)

  local function drawCursor()
    --- the cursor blinks (H-NFR4.4): in its hidden phase
    --- nothing is drawn for it
    if not self.cursor_shown then return end
    --- the line's end is on its last row, also when that row
    --- is full: the cursor then stands past the last column
    local rows = wrap_forward[cl] or { 1 }
    local yi = math.min(math.floor(acc / w) + 1, #rows)
    local vcl = field_row(rows[yi] or 1)

    if vcl < 1 then return end

    local ch = self:row_y(vcl)
    local x_offset = acc - (yi - 1) * w

    gfx.push('all')
    gfx.setColor(cf_colors.input.cursor)
    if input.selection and input.selection.fin then
      --- beside a selection, a bar at the cell's left edge, so
      --- that the selected cell it stands on stays seen; past a
      --- full row's last column, at the field's right edge
      gfx.rectangle('fill', math.min(x_offset * fw, w * fw - 2),
        ch, 2, fh)
    elseif x_offset >= w then
      --- past the last column of a full row there is no
      --- cell: a bar at the field's right edge, where half of
      --- it is cut off, and a second one inside it
      local x = (x_offset - .5) * fw
      gfx.print('|', x, ch)
      gfx.print('|', x - 4, ch)
    else
      --- a block on the cursor's cell, the character under
      --- it in the text's colour, so that it stays readable
      local x = x_offset * fw
      gfx.rectangle('fill', x, ch, fw, fh)
      local under = string.usub(text[cl] or '', cc, cc)
      if string.is_non_empty_string(under) then
        gfx.setColor(colors.fg)
        gfx.print(under, x, ch)
      end
    end
    gfx.pop()
  end

  local drawBackground = function()
    gfx.setColor(colors.bg)
    gfx.rectangle("fill",
      0,
      0,
      drawableWidth,
      apparentHeight * fh)
  end

  local highlight = input.highlight
  local visible = vc:get_visible()
  gfx.setFont(self.cfg.font)
  drawBackground()

  gfx.push('all')
  self.statusline:draw(self.bare_status or status, 0,
    self.bare_status ~= nil)
  gfx.pop()
  --- hidden behind a program that owns the input: the status
  --- line alone, the field's rows background, no cursor
  if self.field_hidden then return end

  local shown = vc:get_range()
  local function row_y(r) return self:row_y(field_row(r)) end
  --- the edges beyond which rows of the draft lie, each to
  --- carry a continuation cue; a field of one row carries none
  --- (the maintainer's ruling of November 19, 2026: its marks
  --- are a later issue)
  local cued = 1 < inLines
  local above = cued and 1 < shown.start
  local below = cued and shown.fin < vc:get_content_length()
  --- a wrapped line's marks, under the draft's text; an edge
  --- row with a continuation cue takes no mark in its last
  --- column
  local first, last = vc.offset + 1, vc.offset + inLines
  local bare = { }
  if above then bare[first] = true end
  if below then bare[last] = true end
  WrapMark.draw(WrapMark.places(vc.wrap_reverse, first, last,
    vc:get_content_length(), bare), row_y, w * fw, fh,
    cf_colors.editor.wrap_mark)

  --- whether the draft's character at (tl, tc) is selected:
  --- from the selection's first position up to its last
  local sel = input.selection
  local sel_from, sel_to
  if sel and sel.start and sel.fin then
    local a, b = sel.start, sel.fin
    if a.l > b.l or (a.l == b.l and a.c > b.c) then a, b = b, a end
    sel_from, sel_to = a, b
  end
  local function is_selected(tl, tc)
    if not sel_from or not tl then return false end
    local after = tl > sel_from.l
        or (tl == sel_from.l and tc >= sel_from.c)
    local before = tl < sel_to.l
        or (tl == sel_to.l and tc < sel_to.c)
    return after and before
  end

  if highlight or sel_from then
    gfx.push('all')
    local hl = highlight and highlight.hl
    local perr = highlight and highlight.parse_err
    local el, ec
    if perr then
      el = perr.l
      ec = perr.c
    end
    for l, s in ipairs(visible) do
      local ln = l + vc.offset
      local tl = string.ulen(s)
      if not tl then
        gfx.pop()
        return
      end

      local row = field_row(ln)
      for c = 1, row < 1 and 0 or tl do
        local char = string.usub(s, c, c)
        local color = colors.fg

        local tlc = vc:translate_from_visible(Cursor(l, c))

        if tlc then
          local ci = (function()
            if hl and hl[tlc.l] then
              return hl[tlc.l][tlc.c]
            end
          end)()
          if ci then
            color = Color[ci] or colors.fg
          end
        end
        --- IS3.4: red from the failing character on, in the
        --- draft's own lines and columns; a wrapped row is no
        --- line
        local at_l = tlc and tlc.l or ln
        local at_c = tlc and tlc.c or c
        if el and (at_l > el
              or (at_l == el and ec and at_c >= ec)) then
          color = cf_colors.input.error
        end
        --- in the draft's own lines and columns, as the red
        local selected = is_selected(tlc and tlc.l, tlc and tlc.c)
        local dy = self:row_y(row)
        local dx = (c - 1) * fw
        ViewUtils.write_token(dy, dx,
          char, color, colors.bg, selected)
      end
    end
    gfx.pop()
  else
    gfx.push('all')
    gfx.setColor(colors.fg)
    for l, str in ipairs(visible) do
      local row = field_row(l + vc.offset)
      if 0 < row then
        ViewUtils.write_line(row, str, self:row_y(1), 0,
          self.cfg)
      end
    end
    gfx.pop()
  end

  --- the continuation cue (FR4.8, IS3.13) at an edge of the
  --- field beyond which rows of the draft lie
  local function cue(edge, r)
    Cue.draw({
      edge = edge, y = self:row_y(r), h = fh,
      width = drawableWidth, fw = fw, font = cfg.font,
      theme = cf_colors.editor.cue,
      paint = { { x = 0, w = drawableWidth, color = colors.bg } },
    })
  end
  if above then cue('top', 1) end
  if below then cue('bottom', inLines) end

  drawCursor()
end

--- @param err_text string[]
--- @param status Status?
function UserInputView:render_error(err_text, status)
  local colors = self.cfg.colors
  local fh = self.cfg.fh

  --- the canvas has input_max rows under the statusline; a
  --- longer message shows its head and ends in '...'
  local max = self.cfg.input_max
  if #err_text > max then
    err_text = table.slice(err_text, 1, max)
    err_text[max] = '...'
  end

  local inLines = #err_text
  self.start_h = self:status_y(inLines)
  local drawableWidth = self.cfg.drawableWidth
  local apparentHeight = #err_text
  local start_y = self:row_y(1)

  local drawBackground = function()
    gfx.setColor(colors.input.error_bg)
    gfx.rectangle("fill",
      0,
      start_y,
      drawableWidth,
      apparentHeight * fh)
  end

  --- the status line stays while a message shows (FR4.6)
  if status then
    gfx.push('all')
    gfx.setFont(self.cfg.font)
    self.statusline:draw(status, 0)
    gfx.pop()
  end

  gfx.push('all')
  drawBackground()

  gfx.setColor(colors.input.error)
  for l, str in ipairs(err_text) do
    local breaks = 0 -- starting height is already calculated
    ViewUtils.write_line(l, str, start_y, breaks, self.cfg)
  end
  gfx.pop()
end

--- What a render of the bare status line is compared by: the
--- status line's own key, which holds what its draw reads
--- (Statusline:key), and the window's size, by which the
--- render places the line (status_y). Of what else the render
--- reads, the ground's colours go by the same state of the
--- IDE, and the draft's rows only size a ground that is higher
--- than the canvas at one row. Nil while a field is drawn.
--- @private
--- @return string?
function UserInputView:_bare_key()
  local bare = self.field_hidden and self.bare_status
  if not bare then return nil end
  local gfx = love.graphics
  return self.statusline:key(bare) .. ' ' .. gfx.getWidth()
      .. 'x' .. gfx.getHeight()
end

--- @param input InputDTO
--- @param status Status
function UserInputView:render(input, status, time)
  local gfx = love.graphics
  --- what this render shows of the cursor's blink, and the
  --- IDE's state its status line was drawn in
  self.cursor_shown = Blink.shown(self.cfg.blink)
  self.ide_shown = self.statusline:ide_key()
  self.caps_shown = status and status.caps
  --- what the canvas holds from this render on
  self.bare_drawn = self:_bare_key()
  --- @diagnostic disable-next-line: undefined-field
  if gfx.mock then return end
  local err_text = input.wrapped_error or {}
  local isError = string.is_non_empty_string_array(err_text)

  --- in the IDE's own graphics state: a render also runs from
  --- a program's show() or set_text(), or a key, outside any
  --- draw (view/ownState.lua)
  own(self.cfg.font, self.canvas.renderTo, self.canvas, function()
    gfx.clear(0, 0, 0, 1)
    gfx.push('all')
    if isError and not self.field_hidden
        and not self:_message_elsewhere() then
      self:render_error(err_text, status)
    else
      self:render_input(input, status, time)
    end
    gfx.pop()
  end)
end

--- Draw the pre-rendered canvas to screen
-- doc/development/internals/user_input.md, "Submit and cancel —
-- widget-owned callback sequences": oneshot is gone; the
-- published input widget instance is the one view that skips
-- this continuous per-frame update_view(). The boot-provisioned
-- input widget owns its rendering updates; other controllers
-- update before drawing. See the identity-redraw debt entry for
-- the migration constraint.
function UserInputView:draw()
  --- a project's field renders when it changes, and when its
  --- cursor's blink turns over
  local project = love.state.user_input_controller
  local shown = Blink.shown(self.cfg.blink)
  local turned = shown ~= self.cursor_shown
  --- and when the IDE's state its status line was drawn in
  --- changes, which picks its colours and a pause's word: a
  --- field rendered during a pause, by a line typed then, does
  --- not keep "paused" once the program goes on
  local ided = self.statusline:ide_key() ~= self.ide_shown
  --- The bare status line behind a running program is the
  --- same frame after frame: the canvas that holds it is kept
  --- until anything its draw reads changes (_bare_key), or
  --- anything else is rendered (its render cost a Compy about
  --- 1.5 ms of every frame).
  local key = self:_bare_key()
  local kept = key ~= nil and key == self.bare_drawn
  if not kept
      and (self.controller ~= project or turned or ided
        or self.caps_shown ~= self.controller.model:get_caps())
  then
    self.controller:update_view()
  end
  local h = self.start_h
  gfx.push('all')
  gfx.setColor(1, 1, 1, 1)
  gfx.setBlendMode("replace")
  gfx.draw(self.canvas, 0, h)
  gfx.setBlendMode("alpha")
  gfx.pop()
end

--- Whether the cursor is at limit, accounting for word wrap.
--- If it's not at a limit line according to the model, it can't
--- be there according to the view, but the reverse is not true,
--- hence this utility function.
--- @param dir VerticalDir
--- @return boolean
function UserInputView:is_at_limit(dir)
  local ml = self.controller.model:is_at_limit(dir)
  if not ml then
    return false
  else
    local model = self.controller.model
    local w = self.cfg.drawableChars
    local cur = model:get_cursor_info().cursor
    if dir == 'up' then
      if cur.l ~= 1 then
        return false
      else
        return cur.c < w
      end
    else
      local nl = model:get_n_text_lines()
      if cur.l ~= nl then
        return false
      else
        local ll = string.ulen(model:get_current_line())
        local il = math.floor(ll / w)
        local c  = math.floor(cur.c / w)
        return il == c
      end
    end
  end
end
