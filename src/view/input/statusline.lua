local class = require("util.class")
require("util.color")
local Layout = require("view.layout")

--- @class Statusline : ViewBase
Statusline = class.create(function(cfg)
  return { cfg = cfg }
end)


--- The columns between two parts of the line
local GAP = 2

--- A part's columns, a column for each character: a character
--- wider than its column is the fonts' defect, and overruns
--- until they are fixed (Beads
--- compy-ide-fonts-characters-wider-than-a-cell; the
--- maintainer's ruling of November 18, 2026)
--- @param text string?
--- @return integer
local function len(text)
  return text and string.ulen(text) or 0
end

--- A line's or a column's number in the console's and a
--- program's cursor: whole up to 9999, in thousands with a K
--- above, 10K for 10000 to 10999. The editor's file position
--- writes every number in full and does not use this.
--- @param n integer
--- @return string
local function count(n)
  if type(n) == 'number' and n > 9999 then
    return math.floor(n / 1000) .. 'K'
  end
  return tostring(n)
end

--- `text` in at most `n` columns, the last an ellipsis where it
--- is cut; never less than the ellipsis. Any text is cut so,
--- arrows in it included (review e7)
--- @param text string
--- @param n integer
--- @return string
local function cut(text, n)
  local l = len(text)
  if l <= n then return text end
  if n <= 1 then return '…' end
  return string.usub(text, 1, n - 1) .. '…'
end

--- The fewest columns a part of the left side is cut to before
--- the next is cut: two characters and the ellipsis (the state
--- word's arrow counts among them)
local FLOOR = 3

--- The left side's parts, { t = text, tail = never cut } in the
--- order they are cut, fitted into `room` columns, a gap after
--- each, a tail (the state word's arrow) after its text and
--- never cut (the
--- maintainer's ruling of November 18, 2026: "nothing should be
--- dropped fully, only cut"): each in turn is cut down to FLOOR,
--- until all fit. Where even the floors do not fit, the left
--- side is drawn as far as its clip, which ends before the
--- right block (review e6), and nothing overlaps.
--- @param room integer
--- @param parts table[]
local function fit_left(room, parts)
  local total = 0
  for _, p in ipairs(parts) do
    if p.t then total = total + len(p.t) + len(p.tail) + GAP end
  end
  for _, p in ipairs(parts) do
    if total <= room then return end
    if p.t then
      local l = len(p.t)
      local least = math.max(1, FLOOR - len(p.tail))
      local n = math.max(math.min(l, least), l - (total - room))
      if n < l then
        p.t = cut(p.t, n)
        total = total - (l - len(p.t))
      end
    end
  end
end

--- A name or a label as it can be shown, on the line's one
--- row: a program's prompt may hold bytes that are not UTF-8,
--- and a control character, a line break or a tab among them,
--- is a space (review e3).
--- @param text any
--- @return string?
local function shown(text)
  if not text then return nil end
  return (string.scrub(tostring(text)):gsub('%c', ' '))
end

--- What a status line's picture takes from the IDE beside its
--- status: the state, which picks the colours, the debug
--- marks, and whether the Compy runs without an SD card. A draw
--- reads them here and nowhere else, and Statusline:key
--- compares by the same four.
--- @return string? state
--- @return any testing
--- @return any debug
--- @return any removable --- false: no SD card
local function ide_state()
  return love.state.app_state, love.state.testing, love.DEBUG,
      love.state.has_removable
end

--- In front of every line of the IDE's own, the console's, a
--- running program's, a pause's and the editor's, while the
--- Compy runs without an SD card, in the theme's `mark` tone;
--- never cut. A program's own field has none (the maintainer's
--- ruling of November 17, 2026: "[no sd card] stays in front";
--- and of November 18: "shorten [no sd card] to [no sd]").
local NO_CARD = '[no sd]'

--- After the open file's name on the editor's line while the
--- file does not load, in the theme's `mark` tone; never cut
--- (rulings.md, "A file that does not load is marked on the
--- status line").
local BROKEN = '[broken]'

--- The screen's mode as the line prints it, with the key that
--- shows the next (the maintainer's rulings of November 19,
--- 2026: `text>F12`, `comb>F12`, and on F12 into the full
--- picture `view>F12`). Only the console's lines carry a mode
--- (UserInputModel.screen_source, running_status,
--- picture_status), and F12 steps it in each of them; the
--- editor's and a program's own field's have none.
--- @type table<ScreenMode, string>
local MODE_LABEL = {
  text = 'text>F12',
  combined = 'comb>F12',
  picture = 'view>F12',
}

--- The line's colours, by their name in the theme: the editor
--- is blue, a pause red, and the console dark gray, a running
--- program's line included (the maintainer's rulings of
--- November 17, 2026: the colour "clearly indicates the mode
--- (but is never the single differentiating indicator)", and
--- "keep the bar dark gray, just add 'running' in yellow as a
--- status"). The words say each too, after the project and the
--- file, in the state's yellow: the editor its state, the
--- console "console", the bare line behind a program "running"
--- (ConsoleController:running_status), a pause "paused".
--- @param app_state string?
--- @return InputTheme
local function theme_of(app_state)
  if app_state == 'editor' then return 'editor' end
  if app_state == 'inspect' then return 'inspect' end
  return 'console'
end

--- `v` spelled for a comparison: a string, a number or a
--- boolean by its value, a table by every key and value it
--- holds, and a table deeper than any status goes, a function
--- or an object as `tostring` gives it. Two statuses made the
--- same way spell the same; the same fields set in another
--- order may not, which costs one draw.
--- @param v any
--- @param out string[]
--- @param depth integer
local function spell(v, out, depth)
  local t = type(v)
  if t == 'table' and depth < 6 then
    out[#out + 1] = '{'
    for k, x in pairs(v) do
      spell(k, out, depth + 1)
      spell(x, out, depth + 1)
    end
    out[#out + 1] = '}'
  elseif t == 'string' then
    out[#out + 1] = 's' .. #v .. ':' .. v
  else
    out[#out + 1] = t:sub(1, 2) .. tostring(v)
  end
end

--- What a draw reads of the IDE's state (ide_state), as one
--- string: a field kept rendered is rendered again when it
--- changes (UserInputView:draw).
--- @return string
function Statusline:ide_key()
  local out = { }
  spell({ ide_state() }, out, 0)
  return table.concat(out, ' ')
end

--- What a draw of `status` reads that can differ between two
--- frames, as one string: the IDE's state (ide_state) and the
--- whole of `status`, every field of it, read by this draw or
--- not. Two draws with equal keys draw the same line for the
--- statuses the IDE makes, of texts, numbers and flags, so a
--- canvas that holds one need not be drawn again for the other
--- (UserInputView:draw). A new field of a status is in the key
--- by itself; a new read of the IDE's state belongs in
--- ide_state. Where the line is drawn is the caller's.
--- @param status Status
--- @return string
function Statusline:key(status)
  local out = { }
  spell({ ide_state() }, out, 0)
  spell(status, out, 0)
  return table.concat(out, ' ')
end

--- @param status Status
--- @param start_y integer?
--- @param last_row boolean? --- on the screen's last row: the
---   ground covers the bottom strip too
function Statusline:draw(status, start_y, last_row)
  local gfx = love.graphics
  local cf = self.cfg
  local app_state, testing, debug, removable = ide_state()
  local theme = theme_of(app_state)
  local colors = cf.colors.statusline[theme]

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
  --- one cell on each side of the line (the maintainer's
  --- ruling of November 18, 2026: "Have just one space on each
  --- side")
  local margin = cf.fw
  local endTextX = start_box.x + w - margin
  local midX = (start_box.x + w) / 2

  local function drawBackground()
    local pic = status.mode == 'picture'
    local bg = pic and Color.with_alpha(
      cf.colors.statusline.console.bg,
      cf.colors.screen.combined.ground) or colors.bg
    gfx.setColor(bg)
    gfx.setFont(font)
    gfx.rectangle("fill", start_box.x, start_box.y, w,
      last_row and band + lay.bottom or band)
  end

  local function drawStatus()
    local state = app_state
    local custom = status.custom
    local y = start_box.y + pad
    local left_x = start_box.x + margin
    local fw = cf.fw
    --- The input's label, as the program gave it (its prompt),
    --- with its tone; an empty one shows nothing. The editor's
    --- line names its state in the label's place
    local label, tone
    if status.label and not (custom and custom.state) then
      label = status.label
      if type(label) == 'table' then
        tone = label.tone
        label = label.text
      end
      label = shown(label)
      if label == '' then label = nil end
    end
    local label_color = colors.fg
    if tone and tone ~= 'default' and colors[tone] then
      label_color = colors[tone]
    end

    --- The right block, packed to the right edge, left to right:
    --- the screen's mode, Caps Lock, and the position. In the
    --- editor, the position is the file line and the file's line
    --- count (`L1080/1200`, in `colors.indicator` at the end
    --- position), and while inserting or replacing the cursor's
    --- column (`:32`) one column to its right in the state's
    --- yellow, with every number written in full. Elsewhere, it
    --- is how far the output is scrolled back (`L-N`) and the
    --- draft's cursor (`line:column`) in the state's yellow, with
    --- numbers above 9999 in thousands (`10K`). Each part stands
    --- next to the one to its right, moving left only as that
    --- grows; none is cut or dropped, and no room is kept for a
    --- wider one.
    local right = { }
    --- @param list table[]
    --- @param t string?
    --- @param color table
    --- @param sep integer? --- the columns before it, GAP if nil
    local function add(list, t, color, sep)
      if t and t ~= '' then
        list[#list + 1] = { t = t, color = color, sep = sep or GAP }
      end
    end
    --- @param list table[]
    --- @return integer
    local function width_of(list)
      local n = 0
      for i, p in ipairs(list) do
        n = n + len(p.t) + (i > 1 and p.sep or 0)
      end
      return n
    end
    add(right, MODE_LABEL[status.mode], colors.fg2 or colors.fg)
    add(right, status.caps, colors.indicator)
    local c = type(status.cursor) == 'table' and status.cursor or nil
    local editor = custom ~= nil and custom.line ~= nil and c ~= nil
    if editor then
      add(right, 'L' .. custom.line .. '/' .. (custom.total or 0),
        custom.end_position and colors.indicator or colors.fg)
      if custom.state ~= 'browsing' then
        add(right, ':' .. c.c,
          colors.state or colors.fg2 or colors.fg, 1)
      end
    else
      if status.back then
        --- how far the output is scrolled back from rest (the
        --- maintainer's ruling of November 18, 2026: "when we
        --- scroll, we can show L-4"); nothing at rest
        add(right, 'L-' .. status.back, colors.fg)
      end
      if c then
        add(right, count(c.l) .. ':' .. count(c.c),
          colors.state or colors.fg2 or colors.fg)
      end
    end
    local width = width_of(right)
    local right_x = endTextX - width * fw

    --- The left side: the no-card mark, never cut; the input's
    --- label (a program's prompt), the project, the file with
    --- `[broken]` after it (one space between, never cut) when
    --- the file does not load, and the state word, in the state's
    --- yellow. Short of room the label is cut first, then the
    --- state word, then the project, the file the last (the
    --- maintainer's ruling of November 18, 2026: "the project name
    --- gets cut next, and the file name only if nothing more
    --- can"); see fit_left.
    local project = shown(custom and custom.project or status.project)
    local name = shown(custom and custom.name or status.name)
    local word = custom and custom.state or status.state
    local mark = word and removable == false and NO_CARD or nil
    local broken = custom and custom.broken and BROKEN or nil
    local p_label = { t = label }
    --- the arrow toward the edit's target, after the word, in
    --- its tone, and never cut: a cut word's ellipsis comes
    --- before it
    local p_state = { t = word,
      tail = word and custom and custom.arrow or nil }
    local p_project = { t = project }
    local p_name = { t = name }
    local room = math.floor((right_x - left_x) / fw)
        - (mark and len(mark) + GAP or 0)
        - (broken and len(broken) + 1 or 0)
    fit_left(room, { p_label, p_state, p_project, p_name })

    --- drawn inside a clip that ends a gap before the right
    --- block, so that where even the floors do not fit the left
    --- side is cut off there and covers none of it (review e6).
    --- The clip is in the target's pixels: the line's corners
    --- go through the transform in force.
    gfx.push('all')
    if gfx.intersectScissor and gfx.transformPoint then
      local x1, y1 = gfx.transformPoint(start_box.x, start_box.y)
      local x2, y2 = gfx.transformPoint(right_x - GAP * fw,
        start_box.y + band)
      if x1 and y1 and x2 and y2 then
        gfx.intersectScissor(x1, y1, math.max(0, x2 - x1),
          math.max(0, y2 - y1))
      end
    end
    local x = left_x
    local function put(t, color, after, after_color)
      if not t then return end
      gfx.setColor(color)
      gfx.print(t, x, y)
      x = x + len(t) * fw
      if after then
        x = x + fw
        gfx.setColor(after_color)
        gfx.print(after, x, y)
        x = x + len(after) * fw
      end
      x = x + GAP * fw
    end
    local mark_color = colors.mark or colors.warning
    put(mark, mark_color)
    put(p_label.t, label_color)
    put(p_project.t, colors.fg)
    put(p_name.t, colors.fg, broken, mark_color)
    put(p_state.t and p_state.t .. (p_state.tail or ''),
      colors.state or colors.fg2 or colors.fg)
    gfx.pop()

    x = right_x
    for i, p in ipairs(right) do
      if i > 1 then x = x + p.sep * fw end
      gfx.setColor(p.color)
      gfx.print(p.t, x, y)
      x = x + len(p.t) * fw
    end
    gfx.setColor(colors.fg)

    if debug then
      gfx.setColor(cf.colors.debug)
      if testing then
        gfx.print('testing', midX - (8 * fw), y)
      end
      local sl = state or '???'
      gfx.print(sl, midX - cols(sl) / 2, y)
      gfx.setColor(colors.fg)
    end
  end

  gfx.push('all')
  drawBackground()
  drawStatus()
  gfx.pop()
end
