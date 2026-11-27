require("util.color")

--- The status line's themes: the console's, a running
--- program's line included, a pause's and the editor's
---@alias InputTheme
---| 'console'
---| 'inspect'
---| 'editor'

---@alias RGB integer[]

--- @class BaseColors
--- @field bg RGB
--- @field fg RGB

--- @class TerminalColors : BaseColors
--- @field echo RGB --- an accepted line written to the output
--- @field error RGB --- a run's error written to it
--- @field refusal RGB --- a command's refusal written to it

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
--- @field state RGB? --- a program's state word ("running"), where it is not fg2
--- @field mark RGB? --- the crossed-out save icon in front of the line

local indicator = Color[Color.cyan + Color.bright]
local special = Color[Color.cyan]
local warning = Color[Color.orange]
--- the crossed-out save icon in front of the IDE's status lines:
--- the same orange at full brightness, 9.0:1 on the console's
--- gray, 6.1:1 on the editor's blue and 4.3:1 on the pause's
--- red, where the warning orange gives 5.2, 3.5 and 2.4:1; a
--- pause can come without a card, from the Compy's own storage
local mark = Color[Color.orange + Color.bright]
local error = Color[Color.red]

local lua_i = require('conf.lua')
local md_i = require('conf.md')

--- @class Colors
--- @field debug RGB
--- @field terminal TerminalColors
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
    --- the maintainer's ruling "Console scrollback, first
    --- version": an echoed line reads as code
    echo = Color[Color.blue],
    --- the maintainer's rulings of November 15, 2026: a run's
    --- error is said in the output in the theme's red, which
    --- is for errors alone, and a command's refusal, which is
    --- no error, in a burnt orange that reads on the output's
    --- gray about as well (3.6:1 to the red's 3.5:1); the
    --- palette has no such orange, so it is given as it is
    error = Color[Color.red],
    refusal = { 0x93 / 255, 0x49 / 255, 0, 1 },
  },
  --- The screen's modes (model/screenModel.lua). In the
  --- combined mode the output is drawn over the program's
  --- picture: `ground` is the opacity of the output's ground
  --- over the picture, `text` the opacity of its characters.
  --- Decision 5 of November 17, 2026 starts here, the picture
  --- dimmed and the text whole, for legibility; the
  --- maintainer's words, "the text half-transparent over the
  --- canvas", are ground 0 and text 0.5. The maintainer chooses.
  screen = {
    combined = {
      ground = .6,
      text = 1,
    },
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
    --- the marks of a wrapped line (view/wrapMark.lua): the
    --- status lines' orange, a fillet of 8 pixels with a square
    --- outer corner
    wrap_mark = {
      color = warning,
      size = 8,
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
    --- band above it stands apart while the save icon keeps
    --- the orange of the other status lines (the maintainer's
    --- ruling of November 15, 2026); the palette has no such
    --- gray, so it is given as it is. A running program's line
    --- is the console's too. The state word, "console",
    --- "running" or "paused", is in the yellow of the editor's
    --- (the maintainer's rulings of November 17, 2026: "keep the
    --- bar dark gray, just add 'running' in yellow as a status",
    --- and "We can write 'paused' in yellow as well")
    console = {
      fg = Color[Color.white + Color.bright],
      bg = { 24 / 255, 24 / 255, 24 / 255, 1 },
      state = Color[Color.yellow + Color.bright],
      indicator = indicator,
      special = special,
      warning = warning,
      mark = mark,
      error = error,
    },
    --- a pause: a darker red than the palette's, #A00000, with
    --- white text and "paused" in yellow (the maintainer's
    --- ruling of November 17, 2026: "maybe make red darker and
    --- keep white text?"). White on it is 8.4:1 where the
    --- palette's red gives 6.5:1, the yellow 7.8:1 and the cyan
    --- indicator 6.7:1; a red darker still comes too close to
    --- the console's gray for a protanope. The palette has no
    --- such red, so it is given as it is
    inspect = {
      bg = { 160 / 255, 0, 0, 1 },
      fg = Color[Color.white + Color.bright],
      state = Color[Color.yellow + Color.bright],
      indicator = indicator,
      special = special,
      warning = warning,
      mark = mark,
      error = error,
    },
    editor = {
      fg = Color[Color.white + Color.bright],
      fg2 = Color[Color.yellow + Color.bright],
      bg = Color[Color.blue],
      indicator = indicator,
      special = special,
      warning = warning,
      mark = mark,
      error = error,
    },
  },
}
