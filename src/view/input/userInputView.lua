require("view.input.statusline")

local class = require('util.class')
require("util.debug")
require("util.view")


--- The rows a notice may take under the draft (IS3.14): one,
--- or up to three when it is wider than the field
local NOTICE_ROWS = 3

--- @param cfg ViewConfig
--- @param ctrl UserInputController
local new = function(cfg, ctrl)
  local gfx = love.graphics
  local w = gfx.getWidth()
  --- max lines + statusline
  local h = cfg.input_max * cfg.fh + cfg.fh
  --- and a notice's rows under the draft's
  local canvas_h = h + NOTICE_ROWS * cfg.fh
  return {
    cfg = cfg,
    controller = ctrl,
    statusline = Statusline(cfg),
    start_h = h,
    canvas = gfx.newCanvas(w, canvas_h),
  }
end

--- @class UserInputView : ViewBase
--- @field controller UserInputController
--- @field statusline table
--- @field canvas love.Canvas
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
  if string.is_non_empty_string_array(err) then
    if self:_shows_notice() then
      return draft + math.min(#err, NOTICE_ROWS)
    end
    return math.min(#err, max)
  end
  return draft
end

--- Whether the message shown is a notice (IS3.14): it goes
--- under the draft's rows, where an error takes their place
--- @private
--- @return boolean
function UserInputView:_shows_notice()
  local e = self.controller.model.error
  return type(e) == 'table' and e.notice == true
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


  local vpH = gfx.getHeight()
  self.start_h = vpH - (inLines + 1) * fh

  local function drawCursor()
    --- the line's end is on its last row, also when that row
    --- is full: the cursor then stands past the last column
    local rows = wrap_forward[cl] or { 1 }
    local yi = math.min(math.floor(acc / w) + 1, #rows)
    local vcl = field_row(rows[yi] or 1)

    if vcl < 1 then return end

    local ch = vcl * fh
    local x_offset = acc - (yi - 1) * w
    local x = (x_offset - .5) * fw

    gfx.push('all')
    gfx.setColor(cf_colors.input.cursor)
    gfx.print('|', x, ch)
    --- at either edge of the field half the bar is cut off:
    --- a second one stands inside it
    if x_offset == 0 then
      gfx.print('|', x + 4, ch)
    elseif x_offset >= w then
      gfx.print('|', x - 4, ch)
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
  self.statusline:draw(status, 0)
  gfx.pop()

  if highlight then
    gfx.push('all')
    local hl = highlight.hl
    local perr = highlight.parse_err
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
        --- a draft that is only unfinished has none (IS3.5)
        if el and not perr.at_end and (at_l > el
              or (at_l == el and ec and at_c >= ec)) then
          color = cf_colors.input.error
        end
        local selected = (function()
          local sel = input.selection
          local startl = sel.start and sel.start.l
          local endl = sel.fin and sel.fin.l
          if startl then
            local startc = sel.start.c
            local endc = sel.fin.c
            if startc and endc then
              if startl == endl then
                local sc = math.min(sel.start.c, sel.fin.c)
                local endi = math.max(sel.start.c, sel.fin.c)
                return l == startl and c >= sc and c < endi
              else
                return
                    (l == startl and c >= sel.start.c) or
                    (l > startl and l < endl) or
                    (l == endl and c < sel.fin.c)
              end
            end
          end
        end)()
        local dy = row * fh
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
        ViewUtils.write_line(row, str, fh, 0, self.cfg)
      end
    end
    gfx.pop()
  end

  if true then
    drawCursor()
  end
end

--- @param err_text string[]
--- @param status Status?
function UserInputView:render_error(err_text, status)
  local colors = self.cfg.colors
  local fh = self.cfg.fh
  local vpH = gfx.getHeight()

  --- the canvas has input_max rows under the statusline; a
  --- longer message shows its head and ends in '...'
  local max = self.cfg.input_max
  if #err_text > max then
    err_text = table.slice(err_text, 1, max)
    err_text[max] = '...'
  end

  local inLines = #err_text
  self.start_h = vpH - (inLines + 1) * fh
  local drawableWidth = self.cfg.drawableWidth
  local apparentHeight = #err_text
  local start_y = fh -- statusline

  local drawBackground = function()
    gfx.setColor(colors.input.error_bg)
    gfx.rectangle("fill",
      0,
      fh,
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
  if self.controller.model.editing then
    --- the refusal frame is the editor's 2.4.3; the
    --- console and project inputs keep their plain
    --- error text
    gfx.rectangle("line",
      1,
      fh + 1,
      drawableWidth - 2,
      apparentHeight * fh - 2)
  end

  for l, str in ipairs(err_text) do
    local breaks = 0 -- starting height is already calculated
    ViewUtils.write_line(l, str, start_y, breaks, self.cfg)
  end
  gfx.pop()
end

--- A notice under the draft's rows (IS3.14): it blocks no
--- input, so the draft stays shown above it. Call after
--- render_input, which places the field.
--- @param err_text string[]
function UserInputView:render_notice(err_text)
  local colors = self.cfg.colors
  local fh = self.cfg.fh
  local rows = math.min(#err_text, NOTICE_ROWS)
  local draft_rows = (gfx.getHeight() - self.start_h) / fh - 1
  local top = (draft_rows + 1) * fh
  self.start_h = self.start_h - rows * fh

  gfx.push('all')
  gfx.setFont(self.cfg.font)
  gfx.setColor(colors.input.error_bg)
  gfx.rectangle("fill", 0, top,
    self.cfg.drawableWidth, rows * fh)
  gfx.setColor(colors.input.error)
  for l = 1, rows do
    gfx.print(err_text[l], 0, top + (l - 1) * fh)
  end
  gfx.pop()
end

--- @param input InputDTO
--- @param status Status
function UserInputView:render(input, status, time)
  local gfx = love.graphics
  --- @diagnostic disable-next-line: undefined-field
  if gfx.mock then return end
  local err_text = input.wrapped_error or {}
  local isError = string.is_non_empty_string_array(err_text)

  self.canvas:renderTo(function()
    gfx.clear(0, 0, 0, 1)
    gfx.push('all')
    local notice = isError and self:_shows_notice()
    if isError and not notice then
      self:render_error(err_text, status)
    else
      self:render_input(input, status, time)
      if notice then self:render_notice(err_text) end
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
  if self.controller ~= love.state.user_input_controller then
    self.controller:update_view()
  end
  local b = self.cfg.statusline_border / 2
  local h = self.start_h - b
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
