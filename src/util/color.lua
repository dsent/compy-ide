local vivid = {
  [16] = { 0xFF, 0xA5, 0x00 },
  [17] = { 0x96, 0x4B, 0x00 },
  [18] = { 0xFF, 0xCC, 0x99 },
  [19] = { 0x9A, 0xCD, 0x32 },
  [20] = { 0x00, 0xBF, 0xFF },
  [21] = { 0x8A, 0x2B, 0xE2 },
  [22] = { 0xFF, 0x69, 0xB4 },
  [23] = { 0x99, 0x99, 0x99 },
  [32] = { 0xFF, 0x7F, 0x50 },
  [33] = { 0xFF, 0xD7, 0x00 },
  [34] = { 0x32, 0xCD, 0x32 },
  [35] = { 0x00, 0xFF, 0x80 },
  [36] = { 0x40, 0xE0, 0xD0 },
  [37] = { 0x00, 0x80, 0xFF },
  [38] = { 0x6A, 0x5A, 0xCD },
  [39] = { 0xDC, 0x14, 0x3C },
  [48] = { 0xF0, 0xE6, 0x8C },
  [49] = { 0xFF, 0x80, 0x80 },
  [50] = { 0x99, 0xFF, 0xCC },
  [51] = { 0x99, 0xDD, 0xFF },
  [52] = { 0xCC, 0x99, 0xFF },
  [53] = { 0xDA, 0x70, 0xD6 },
  [54] = { 0x41, 0x69, 0xE1 },
  [55] = { 0x70, 0x80, 0x90 },
}

local function palette_color(c)
  local tier = math.floor(c / 16)
  local position = tier * 16 + c % 8
  local color = vivid[position]
  if not color then return end

  local scale = c % 16 >= 8 and 1 or 0.75
  local function channel(value)
    return math.floor(scale * value + 0.5) / 255
  end

  return {
    channel(color[1]),
    channel(color[2]),
    channel(color[3]),
    1,
  }
end

--- @class Color
Color = {
  color = {},
  __index = function(t, c)
    local rc = rawget(Color, c)
    if rc then return rc end
    if not Color.valid(c) then return end
    if c >= 16 then
      local color = palette_color(c)
      Color[c] = color
      return color
    end
    local bright = c > 7 and 1 or 0.75
    local oc = c
    local b = c % 2
    c = (c - b) / 2
    local r = c % 2
    c = (c - r) / 2
    local g = c % 2
    Color[oc] = { bright * r, bright * g, bright * b, 1 }
    return Color[oc]
  end,

  black = 0,   -- #000000
  blue = 1,    -- #0000BF #0000FF
  red = 2,     -- #BF0000 #FF0000
  magenta = 3, -- #BF00BF #FF00FF
  green = 4,   -- #00BF00 #00FF00
  cyan = 5,    -- #00BFBF #00FFFF
  yellow = 6,  -- #BFBF00 #FFFF00
  white = 7,   -- #BFBFBF #FFFFFF
  bright = 8,

  orange = 16,
  brown = 17,
  tan = 18,
  yellowgreen = 19,
  skyblue = 20,
  purple = 21,
  pink = 22,
  gray = 23,

  coral = 32,
  gold = 33,
  limegreen = 34,
  springgreen = 35,
  turquoise = 36,
  azure = 37,
  slateblue = 38,
  crimson = 39,

  khaki = 48,
  salmon = 49,
  mint = 50,
  powderblue = 51,
  lavender = 52,
  orchid = 53,
  royalblue = 54,
  slategray = 55,

  valid = function(c)
    return c
        and type(c) == 'number'
        and math.floor(c) == c -- weird way to isInt
        and c >= 0
        and c < 64
  end,

  --- @param color table
  --- @param alpha number
  with_alpha = function(color, alpha)
    if type(color) == "table" then
      local red, green, blue = color[1], color[2], color[3]
      return { red, green, blue, alpha }
    end
  end,

  --- @return string
  to_hex = function(r, g, b, a)
    local r, g, b, a = r, g, b, a
    if type(r) == 'table' then
      r, g, b, a = unpack(r)
    end
    local ah = ''
    if type(a) == "number" then
      ah = string.format("%02X", a * 255)
    end
    return string.format('#%02X%02X%02X%s',
      r * 255, g * 255, b * 255, ah)
  end,
}


setmetatable(Color, Color)
