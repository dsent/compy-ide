require("util.dequeue")
require("util.string.string")
require("util.view")
local class = require('util.class')
local Terminal = require("lib.terminal")
require("model.keptRows")

local gfx = love.graphics

--- @class CanvasModel
--- @field terminal table
--- @field kept KeptRows --- the rows scrolled off its top
--- @field view_top integer? --- the scrolled view's first row
--- @field canvas love.Canvas
--- @field term_canvas love.Canvas
--- @field cfg table
--- @field write function
--- @field push function
--- @field reset function
--- @field update function
--- @field get_canvas function
--- @field draw_to function
--- @field restore_main function
CanvasModel = class.create()

--- @param cfg Config
function CanvasModel.new(cfg)
  local w, h
  if cfg.view.sizedebug then
    w = cfg.view.debugwidth * cfg.view.fw
    h = cfg.view.debugheight * cfg.view.fh
  else
    w = cfg.view.w
    -- h = ViewUtils.get_drawable_height(cfg.view)
    h = cfg.view.h
  end
  local canvas = gfx.newCanvas(w, h)
  local custom_height = cfg.view.fh
  -- The terminal spans only the visible console region: the full
  -- view height minus the statusline and input line. Sizing it to
  -- the full height gives it rows that render under the input line,
  -- where a final un-terminated output line lands off-screen and is
  -- only revealed once a newline scrolls the buffer up (#149). The
  -- drawing canvas above keeps the full size, so canvas programs are
  -- unaffected.
  local term_h = h
  if not cfg.view.sizedebug then
    term_h = ViewUtils.get_drawable_height(cfg.view)
  end
  local term = Terminal(w, term_h, cfg.view.font,
    nil, custom_height)

  local color = cfg.view.colors.terminal
  term:hide_cursor()
  term:set_cursor_color(unpack(color.fg))
  term:set_cursor_backcolor(unpack(color.bg))
  term:clear()
  local t_canvas = term.canvas
  local kept = KeptRows(cfg.output_kept)
  term.on_row_leaving = function(chars, states)
    kept:keep(chars, states)
  end
  local self = setmetatable({
    terminal = term,
    kept = kept,
    canvas = canvas,
    term_canvas = t_canvas,
    cfg = cfg,
  }, CanvasModel)

  return self
end

function CanvasModel:write(text)
  if string.is_non_empty_string(text) then
    self.terminal:print(text)
    self.terminal.dirty = true
  end
end

function CanvasModel:push(newResult)
  if type(newResult) == 'table' then
    local t = string.unlines(newResult)
    self:write(t)
  else
    self:write(tostring(newResult) .. '\n')
  end
end

--- Clear the 16 rows, as a clear from code does: what was on
--- them is gone, and the kept rows stay
function CanvasModel:reset()
  self.terminal:clear()
  self.terminal:move_to(1, 1)
  self.terminal.dirty = true
end

--- The user's own clear (Ctrl+L): the screen and the kept rows
function CanvasModel:erase()
  self:reset()
  self.kept:forget()
  self:to_rest()
end

-------------------------
--- the scrolled view ---
-------------------------
--- The console's text is one sequence: the kept rows, numbered
--- `kept.first` to `kept.last`, then the rows on screen down
--- to the last one that holds text, numbered on from
--- `kept.last + 1`. At rest the console shows the screen as it
--- is; scrolled, it shows a window of as many rows as the
--- screen has, `view_top` its first, drawn from the kept rows
--- and the screen without changing either. A number names the
--- same row while newer rows arrive, so new output leaves a
--- scrolled view on the rows it shows.

--- The last row on screen that holds text, 0 when none does
--- @return integer
function CanvasModel:last_text_row()
  local buffer = self.terminal.buffer
  for y = #buffer, 1, -1 do
    for _, c in ipairs(buffer[y]) do
      if c ~= ' ' then return y end
    end
  end
  return 0
end

--- The sequence's last row, and the top of the view that the
--- first step from rest shows: the last row that holds text at
--- its bottom and history above it, or the oldest kept row at
--- its top when there is too little history to fill it
--- @return integer last, integer filled
function CanvasModel:view_bounds()
  local k, h = self.kept, self.terminal.height
  local last = k.last + self:last_text_row()
  local bottom = math.min(k.last + h - 1, last)
  return last, math.max(k.first, bottom - h + 1)
end

--- @return boolean
function CanvasModel:is_scrolled()
  return self.view_top ~= nil
end

--- @param top integer?
function CanvasModel:show(top)
  if top ~= self.view_top then
    self.view_top = top
    self.terminal.dirty = true
  end
end

function CanvasModel:to_rest()
  self:show(nil)
end

--- The view's top, the oldest kept row when the rows it
--- showed were dropped at the limit
--- @return integer?
function CanvasModel:top()
  local t = self.view_top
  if t and t < self.kept.first then
    t = self.kept.first
    self.view_top = t
  end
  return t
end

--- One row toward older output (`-1`) or newer (`1`). From rest
--- the first step shows the filled view; from it a step toward
--- newer output returns to rest. Nothing while no row is kept.
--- @param dir integer
function CanvasModel:scroll_row(dir)
  if self.kept:count() == 0 then return end
  local _, filled = self:view_bounds()
  local t = self:top()
  if not t then
    if dir < 0 then self:show(filled) end
  elseif dir < 0 then
    self:show(math.max(self.kept.first, t - 1))
  elseif filled < t + 1 then
    self:to_rest()
  else
    self:show(t + 1)
  end
end

--- A page of one row fewer than the screen: toward older
--- output the row at the top of the view goes to its bottom,
--- toward newer the bottom row goes to its top. At rest the
--- view is the screen's rows. A page that would reach the
--- filled view or past it returns to rest.
--- @param dir integer
function CanvasModel:scroll_page(dir)
  if self.kept:count() == 0 then return end
  local k, h = self.kept, self.terminal.height
  local _, filled = self:view_bounds()
  local t = self:top()
  if dir < 0 then
    local from = t or k.last + 1
    self:show(math.max(k.first, from - (h - 1)))
  elseif t then
    local next = t + (h - 1)
    if filled <= next then
      self:to_rest()
    else
      self:show(next)
    end
  end
end

--- The oldest kept row at the top of the view
function CanvasModel:to_oldest()
  if self.kept:count() == 0 then return end
  self:show(self.kept.first)
end

--- @class ViewRow
--- @field kept KeptRow? --- a kept row
--- @field y integer? --- or a row on screen

--- The scrolled view's rows, top to bottom (a row past the
--- sequence's end is an empty table), and whether older rows
--- lie above it and newer ones below; nil at rest
--- @return ViewRow[]? rows, boolean above, boolean below
function CanvasModel:window()
  local t = self:top()
  if not t then return nil, false, false end
  local k, h = self.kept, self.terminal.height
  local last = self:view_bounds()
  local rows = { }
  for i = 0, h - 1 do
    local n = t + i
    if n <= k.last then
      rows[#rows + 1] = { kept = k:get(n) }
    elseif n - k.last <= h then
      rows[#rows + 1] = { y = n - k.last }
    else
      rows[#rows + 1] = { }
    end
  end
  return rows, k.first < t, t + h - 1 < last
end

function CanvasModel:invalidate_terminal()
  self.terminal.dirty = true
end

function CanvasModel:update(dt)
  self.terminal:update(dt)
end

function CanvasModel:get_canvas()
  return self.canvas
end

--- Clear the whole canvas, whatever graphics state a program
--- left: a scissor or a color mask would spare part of it.
--- The caller's scissor, mask and render target come back.
function CanvasModel:clear_canvas()
  local sx, sy, sw, sh = gfx.getScissor()
  local r, g, b, a = gfx.getColorMask()
  gfx.setScissor()
  gfx.setColorMask(true, true, true, true)
  self.canvas:renderTo(function()
    gfx.clear(0, 0, 0, 0)
  end)
  gfx.setColorMask(r, g, b, a)
  if sx then
    gfx.setScissor(sx, sy, sw, sh)
  end
end

function CanvasModel:draw_to()
  gfx.setCanvas(self.canvas)
end

function CanvasModel:restore_main()
  gfx.setCanvas()
end
