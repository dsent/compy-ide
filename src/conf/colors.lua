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

--- @class InputColors
--- @field console BaseColors
--- @field user BaseColors
--- @field inspect BaseColors
--- @field cursor RGB
--- @field error RGB  -- TODO pair these
--- @field error_bg RGB  -- TODO pair these

--- @class SyntaxColors
--- @field indices table<string, integer>
--- @field colors table<string, RGB>

--- @class StatuslineColors
--- @field bg RGB
--- @field fg RGB
--- @field fg2 RGB?
--- @field indicator RGB
--- @field special RGB

local indicator = Color[Color.cyan + Color.bright]
local special = Color[Color.cyan]

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
    console = {
      fg = Color[Color.white + Color.bright],
      bg = Color[Color.black],
      indicator = indicator,
      special = special,
    },
    user = {
      bg = Color[Color.blue],
      fg = Color[Color.white],
      indicator = indicator,
      special = special,
    },
    inspect = {
      bg = Color[Color.red],
      fg = Color[Color.black],
      indicator = indicator,
      special = special,
    },
    editor = {
      fg = Color[Color.white + Color.bright],
      fg2 = Color[Color.yellow + Color.bright],
      bg = Color[Color.blue],
      indicator = indicator,
      special = special,
    },
  },
}
