require("util.color")

---@alias InputTheme
---| 'console'
---| 'user'
---| 'inspect'
---| 'editor'

---@alias RGB integer[]

--- @class BaseColors
--- @field bg RGB
--- @field fg RGB

--- @class EditorColors : BaseColors
--- @field highlight RGB
--- @field highlight_loaded RGB
--- @field highlight_special RGB
--- @field results BaseColors
--- @field cue CueColors
--- @field wrap_mark WrapMarkTheme

--- The continuation cue (FR4.8): the edge row's own background
--- laid over it, `fade` opaque at the edge and clear at the
--- row's other side, and in the row's last column the mark,
--- `^` or `v`, `mark_alpha` opaque on a box `box_alpha` opaque
--- (the maintainer's ruling of November 15, 2026)
--- @class CueColors
--- @field fade number
--- @field mark RGB
--- @field mark_alpha number
--- @field box RGB
--- @field box_alpha number

--- @class InputColors
--- @field console BaseColors
--- @field user BaseColors
--- @field inspect BaseColors
--- @field cursor RGB
--- @field error RGB  -- TODO pair these
--- @field error_bg RGB  -- TODO pair these
--- @field notice NoticeColors

--- The notice band above the status line, in the editor and
--- the console: black, an error in red and a notice in orange.
--- It is set apart from a program's own error display
--- (`error_bg`, `error`), which has the same colours today.
--- @class NoticeColors
--- @field bg RGB
--- @field error RGB --- a syntax or run error
--- @field warning RGB --- a notice: a refusal

--- @class SyntaxColors
--- @field indices table<string, integer>
--- @field colors table<string, RGB>

--- @class StatuslineColors
--- @field bg RGB
--- @field fg RGB
--- @field fg2 RGB?
--- @field indicator RGB
--- @field special RGB
--- @field warning RGB
--- @field error RGB

local indicator = Color[Color.cyan + Color.bright]
local special = Color[Color.cyan]
local warning = Color[Color.orange]
local error = Color[Color.red]

local lua_i = require('conf.lua')
local md_i = require('conf.md')

--- @class Colors
--- @field debug RGB
--- @field terminal BaseColors
--- @field editor EditorColors
--- @field lua_syntax SyntaxColors
--- @field md_syntax SyntaxColors
--- @field input InputColors
--- @field statusline table<InputTheme, StatuslineColors>
return {
  debug = Color[Color.yellow],
  terminal = {
    fg = Color[Color.black],
    bg = Color[Color.white],
  },
  editor = {
    fg = Color[Color.black],
    bg = Color[Color.white],
    highlight = Color[Color.white + Color.bright],
    highlight_loaded = Color[Color.yellow + Color.bright],
    highlight_special = special,
    results = {
      fg = Color[Color.black],
      bg = Color[Color.white],
    },
    cue = {
      fade = .75,
      mark = Color[Color.black],
      mark_alpha = .5,
      box = Color[Color.gray],
      box_alpha = .25,
    },
    --- the mark at the top left of a row that continues a line
    --- (view/wrapMark.lua): black, a fillet of 6 pixels with
    --- a square outer corner
    wrap_mark = {
      color = Color[Color.black],
      size = 6,
      round = 0,
    },
  },
  input = {
    console = {
      bg = Color[Color.white],
      fg = Color[Color.black],
    },
    user = {
      bg = Color[Color.white],
      fg = Color[Color.black],
    },
    inspect = {
      bg = Color[Color.white],
      fg = Color[Color.blue + Color.bright],
    },
    cursor = Color[Color.white + Color.bright],
    error = Color[Color.red],
    error_bg = Color[Color.black],
    notice = {
      bg = Color[Color.black],
      error = Color[Color.red],
      warning = Color[Color.orange],
    },
  },
  lua_syntax = {
    indices = lua_i,
    colors = (function()
      local r = {}
      for k, v in pairs(lua_i) do
        r[k] = Color[v]
      end
      return r
    end)()
  },
  md_syntax = {
    indices = md_i,
    colors = (function()
      local r = {}
      for k, v in pairs(md_i) do
        r[k] = Color[v]
      end
      return r
    end)()
  },
  statusline = {
    --- a near-black gray, #181818, so that the black notice
    --- band above it stands apart while '[no sd card]' keeps
    --- the orange of the other status lines (the maintainer's
    --- ruling of November 15, 2026); the palette has no such
    --- gray, so it is given as it is
    console = {
      fg = Color[Color.white + Color.bright],
      bg = { 24 / 255, 24 / 255, 24 / 255, 1 },
      indicator = indicator,
      special = special,
      warning = warning,
      error = error,
    },
    user = {
      bg = Color[Color.blue],
      fg = Color[Color.white],
      indicator = indicator,
      special = special,
      warning = warning,
      error = error,
    },
    inspect = {
      bg = Color[Color.red],
      fg = Color[Color.black],
      indicator = indicator,
      special = special,
      warning = warning,
      error = error,
    },
    editor = {
      fg = Color[Color.white + Color.bright],
      fg2 = Color[Color.yellow + Color.bright],
      bg = Color[Color.blue],
      indicator = indicator,
      special = special,
      warning = warning,
      error = error,
    },
  },
}
