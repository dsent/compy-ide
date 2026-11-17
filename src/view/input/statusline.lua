local class = require("util.class")
local Layout = require("view.layout")

--- @class Statusline : ViewBase
Statusline = class.create(function(cfg)
  return { cfg = cfg }
end)


--- The columns `text` takes with the gap after it.
--- @param text string?
--- @return integer
local function need(text)
  return text and string.ulen(text) + 2 or 0
end

--- `text` in at most `chars` columns, the last an ellipsis
--- when it is cut; nil when under two fit.
--- @param text string?
--- @param chars integer
--- @return string?
local function fit(text, chars)
  if not text or string.ulen(text) <= chars then
    return text
  end
  if chars < 2 then return nil end
  return string.usub(text, 1, chars - 1) .. '…'
end

--- A name or a label as it can be shown: a program's prompt
--- may hold bytes that are not UTF-8.
--- @param text any
--- @return string?
local function shown(text)
  if not text then return nil end
  return string.scrub(tostring(text))
end

--- @param status Status
--- @param start_y integer?
function Statusline:draw(status, start_y)
  local gfx = love.graphics
  local cf = self.cfg
  local colors = (function()
    local state = love.state.app_state
    if state == 'inspect' then
      return cf.colors.statusline.inspect
    elseif state == 'running' then
      return cf.colors.statusline.user
    elseif state == 'editor' then
      return cf.colors.statusline.editor
    else
      return cf.colors.statusline.console
    end
  end)()

  local h = start_y or 0
  local w = cf.w
  local font = cf.font
  --- the status line's own row; its text sits as in any row,
  --- with the pixels the line gains split above and below it
  local lay = Layout(cf)
  local band = lay.status_h
  local pad = lay.status_pad

  --- The width of `text` in the monospace font: its columns.
  --- @param text string
  --- @return number
  local function cols(text)
    return string.ulen(text) * cf.fw
  end

  local start_box = { x = 0, y = h }
  local margin = 2 * cf.fw
  local endTextX = start_box.x + w - margin
  local midX = (start_box.x + w) / 2

  local function drawBackground()
    gfx.setColor(colors.bg)
    gfx.setFont(font)
    gfx.rectangle("fill", start_box.x, start_box.y, w, band)
  end

  --- @param m More?
  --- @return string
  local function morelabel(m)
    if not m then return '' end

    if m.up and not m.down then
      return '↑↑'
    elseif not m.up and m.down then
      return '↓↓ '
    elseif m.up and m.down then
      return '↕↕ '
    else
      return ''
    end
  end

  local function drawStatus()
    local state = love.state.app_state
    local custom = status.custom
    local start_text = {
      x = start_box.x + margin,
      y = start_box.y + pad,
    }

    gfx.setColor(colors.fg)
    local left_x = start_text.x
    --- What the status line names (FR4.6, H-NFR4.4), after
    --- the input's label: the open project, the open file,
    --- the editor's state, and Caps Lock while it is on. Left
    --- of `limit`, the project's name gives way first, then
    --- the file's.
    --- @param limit number?
    local function drawLeft(limit)
      local project = shown(custom and custom.project
          or status.project)
      local name = shown(custom and custom.name)
      local state = custom and custom.state
      local caps = status.caps
      if limit then
        local room = math.floor((limit - left_x) / cf.fw)
        room = room - need(state) - need(caps)
        name = fit(name, room - 2)
        project = fit(project, room - need(name) - 2)
      end
      local x = left_x
      local function put(text, color)
        if not text then return end
        gfx.setColor(color)
        gfx.print(text, x, start_text.y)
        x = x + need(text) * cf.fw
      end
      put(project, colors.fg)
      put(name, colors.fg)
      put(state, colors.fg2 or colors.fg)
      put(caps, colors.indicator)
      gfx.setColor(colors.fg)
    end
    --- in the file editor the state is the kind of input
    --- expected, and takes the label's place
    local label = status.label
    if label and not (custom and custom.state) then
      local text = label
      if type(label) == 'table' then
        text = label.text
        local tone = label.tone
        if tone and tone ~= 'default' and colors[tone] then
          gfx.setColor(colors[tone])
        end
      end
      text = shown(text) or ''
      gfx.print(text, start_text.x, start_text.y)
      gfx.setColor(colors.fg)
      left_x = left_x + cols(text .. '  ')
    end
    if love.DEBUG then
      gfx.setColor(cf.colors.debug)
      if love.state.testing then
        gfx.print('testing',
          midX - (8 * cf.fw),
          start_text.y)
      end
      local sl = state or '???'
      local lw = cols(sl) / 2
      gfx.print((sl),
        midX - lw, start_text.y)
      gfx.setColor(colors.fg)
    end

    local c = status.cursor
    if type(c) == 'table' then
      if custom then
        local t_ic = ' ' .. c.l .. ':' .. c.c
        local lim = custom.buflen
        local sel, t_bbp, t_blp
        -- local more_i = ''
        if custom.spans_lines then
          sel = custom.selection
          t_bbp = 'B' .. sel .. ' '
          t_blp = custom.range and custom.range:ln_label() or ''
        else
          sel = custom.selection
          t_blp = 'L' .. sel
        end
        local more_i = morelabel(status.input_more) .. ' '

        gfx.setColor(colors.fg)
        local font = gfx.getFont()
        local w_il  = cols(" 99:999")
        local w_mi  = cols("  ↕↕ ")
        local cw_p  = cols(t_blp)
        local cw_il = cols(t_ic)
        local sxl   = endTextX - (cw_p + w_il + w_mi)
        local s_mi  = endTextX - w_il
        --- the left text ends before the position; scrolling
        --- the view changes nothing here (IS2.2), so what the
        --- view hides is no part of the line
        local s_pos = sxl
        if t_bbp then
          s_pos = s_pos - cols(t_bbp)
        end

        drawLeft(s_pos)

        gfx.setFont(self.cfg.font)
        gfx.setColor(colors.fg)
        if colors.fg2 then gfx.setColor(colors.fg2) end
        --- cursor pos
        gfx.print(t_ic, endTextX - cw_il, start_text.y)
        --- input more
        gfx.print(more_i, s_mi, start_text.y - 3)

        gfx.setColor(colors.fg)
        --- block line range / line
        gfx.print(t_blp, sxl, start_text.y)
        gfx.setColor(colors.fg)
        --- block number
        if custom.spans_lines then
          local bpw = cols(t_bbp)
          local sxb = sxl - bpw
          if sel == lim then
            gfx.setColor(colors.indicator)
          end
          gfx.print(t_bbp, sxb, start_text.y)
        end
        gfx.setColor(colors.fg)
      else
        --- normal statusline
        local pos_c = ':' .. c.c
        local ln, l_lim
        if custom then
          ln = custom.line
          l_lim = custom.buflen
        else
          ln = c.l
          l_lim = status.n_lines
        end
        local pos_l = 'L' .. ln

        local lw = cols(pos_l)
        local cw = cols(pos_c)
        local sx = endTextX - (lw + cw)
        --- the project's name ends before the position
        drawLeft(sx)
        if ln == l_lim then
          gfx.setColor(colors.indicator)
        end
        gfx.print(pos_l, sx, start_text.y)
        gfx.setColor(colors.fg)
        gfx.print(pos_c, sx + lw, start_text.y)
      end
    else
      --- a status with no cursor names things alone: what runs
      --- behind a hidden field. A long name is cut, the state
      --- kept whole, within the screen.
      drawLeft(endTextX)
    end
  end

  gfx.push('all')
  drawBackground()
  drawStatus()
  gfx.pop()
end
