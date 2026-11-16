-- LV-100

-- TODO : rethink character coloring to simplify stuff

local utf8 = require("utf8")

-- The good old 3-bit color scheme.
local basic_scheme = {
    [0] = { 0, 0, 0, 1 },
    { 1, 0, 0, 1 },
    { 0, 1, 0, 1 },
    { 1, 1, 0, 1 },
    { 0, 0, 1, 1 },
    { 1, 0, 1, 1 },
    { 0, 1, 1, 1 },
    { 1, 1, 1, 1 }
}

-- Origin of this snippet : https://stackoverflow.com/a/43139063
local function utf8_sub(s, i, j)
    i = utf8.offset(s, i)
    j = utf8.offset(s, j + 1) - 1
    return string.sub(s, i, j)
end

-- A cursor position on the grid, as a classic terminal takes a
-- move: a whole number, outside the grid the nearest edge, and
-- one that is no number (NaN) the first cell.
local function on_grid(v, last)
    v = math.floor(v)
    if v ~= v or v < 1 then return 1 end
    if v > last then return last end
    return v
end

-- The whole cells from `first` to `last` that are on a grid of
-- `size` cells: none (a first after the last) when no number.
local function on_grid_span(first, last, size)
    first, last = math.floor(first), math.floor(last)
    if first ~= first or last ~= last then return 1, 0 end
    return math.max(first, 1), math.min(last, size)
end

local function terminal_update_character(terminal, x, y, new_char)
    -- a cell outside the grid is no cell: what lands there is lost
    if not (x >= 1 and x <= terminal.width
            and y >= 1 and y <= terminal.height) then
        return
    end
    terminal.buffer[y][x] = new_char
    local char_color = terminal.cursor_color
    local char_backcolor = terminal.cursor_backcolor
    terminal.state_buffer[y][x].color = {
        char_color[1], char_color[2], char_color[3], char_color[4] }
    terminal.state_buffer[y][x].backcolor = {
        char_backcolor[1], char_backcolor[2],
        char_backcolor[3], char_backcolor[4] }
    terminal.state_buffer[y][x].reversed = terminal.cursor_reversed
    terminal.state_buffer[y][x].dirty = true
end

local function terminal_hide_cursor(terminal)
    table.insert(terminal.stdin, { type = "hide_cursor" })
end

local function terminal_show_cursor(terminal)
    table.insert(terminal.stdin, { type = "show_cursor" })
end

local function terminal_set_cursor_color(terminal, red, blue, green, alpha)
    -- Argument processing
    if type(red) == "table" and blue == nil then
        red, blue, green, alpha = red[1], red[2], red[3], red[4]
    end
    table.insert(terminal.stdin, {
        type = "cursor_color",
        red = red,
        blue = blue,
        green = green,
        alpha = (alpha or 1)
    })
end

local function terminal_set_cursor_backcolor(terminal, red, blue, green, alpha)
    -- Argument processing
    if type(red) == "table" and blue == nil then
        red, blue, green, alpha = red[1], red[2], red[3], red[4]
    end
    table.insert(terminal.stdin, {
        type = "cursor_backcolor",
        red = red,
        blue = blue,
        green = green,
        alpha = (alpha or 1)
    })
end


-- The commands that set how what follows looks, not what is on
-- the grid
local SETS_STYLE = {
    cursor_color = true, cursor_backcolor = true, reverse = true,
    show_cursor = true, hide_cursor = true,
}

-- What waits to be written, oldest first. `stdin` holds it from
-- `stdin_head + 1` on: the entries before that are written
-- already and stay until the queue is packed (terminal_update).
local function terminal_waiting(terminal)
    local stdin, i = terminal.stdin, terminal.stdin_head
    return function()
        i = i + 1
        return stdin[i]
    end
end

-- Drop what waits to be written, keeping the styles that the
-- waiting commands set for what follows
local function terminal_discard(terminal)
    local keep = {}
    for c in terminal_waiting(terminal) do
        if type(c) == "table" and SETS_STYLE[c.type] then
            keep[#keep + 1] = c
        end
    end
    terminal.stdin = keep
    terminal.stdin_head = 0
end

-- What comes next starts a row of its own: on the next row when
-- the cursor's row already holds text, else at its start
local function terminal_fresh_row(terminal)
    table.insert(terminal.stdin, { type = "fresh_row" })
end

local function terminal_move_to(terminal, x, y)
    table.insert(terminal.stdin, {
        type = "move",
        x = math.floor(x),
        y = math.floor(y)
    })
end

local function terminal_reverse(terminal, set)
    table.insert(terminal.stdin, { type = "reverse", value = set })
end

local function terminal_clear(terminal, x, y, w, h)
    x = x or 1
    y = y or 1
    w = w or terminal.width
    h = h or terminal.height
    table.insert(terminal.stdin, { type = "clear", x = x, y = y, w = w, h = h })
end

local line_style = "┌┐└┘─│"
local thick_style = "┏┓┗┛━┃"
local block_style = "██████"
local function terminal_frame(terminal, style, x, y, w, h)
    table.insert(terminal.stdin, {
        type = "frame",
        style = style,
        x = math.floor(x),
        y = math.floor(y),
        w = math.floor(w),
        h = math.floor(h)
    })
end

-- A row's states move with its characters; the row leaving the
-- top comes back at the bottom, blank in the cursor's colors.
local function terminal_roll_up(terminal, how_many)
    local buffer, state_buffer = terminal.buffer, terminal.state_buffer
    for _ = 1, how_many do
        -- the row leaving the top, characters and states, whole
        local first_row, first_states = buffer[1], state_buffer[1]
        if terminal.on_row_leaving then
            terminal.on_row_leaving(first_row, first_states)
        end
        for y = 2, terminal.height do
            buffer[y - 1] = buffer[y]
            state_buffer[y - 1] = state_buffer[y]
        end
        buffer[terminal.height] = first_row
        state_buffer[terminal.height] = first_states
        for x = 1, terminal.width do
            terminal_update_character(terminal, x, terminal.height, ' ')
        end
    end
    -- every row moved: all of it is to be drawn again
    for _, states in ipairs(state_buffer) do
        for _, state in ipairs(states) do
            state.dirty = true
        end
    end
    terminal.dirty = true
end

local function wrap_if_bottom(terminal)
    if terminal.cursor_y > terminal.height then
        -- more rolls than rows leave the same blank grid
        terminal_roll_up(terminal, math.min(
            terminal.cursor_y - terminal.height, terminal.height))
        terminal.cursor_y = terminal.height
    end
end

local function terminal_update(terminal, dt)
    if #terminal.stdin == terminal.stdin_head then return end
    local frame_budget = terminal.speed * dt + terminal.accumulator
    local stdin_index = terminal.stdin_head + 1
    while frame_budget > terminal.char_cost do
        local char_or_command = terminal.stdin[stdin_index]
        if char_or_command == nil then break end
        stdin_index = stdin_index + 1
        frame_budget = frame_budget - terminal.char_cost

        if type(char_or_command) == "string" then
            if char_or_command == '\b' then
                terminal.cursor_x = math.max(terminal.cursor_x - 1, 1)
            elseif char_or_command == '\n' then
                terminal.cursor_x = 1
                terminal.cursor_y = terminal.cursor_y + 1
                wrap_if_bottom(terminal)
            else
                terminal_update_character(terminal,
                    terminal.cursor_x,
                    terminal.cursor_y,
                    char_or_command)
                terminal.cursor_x = terminal.cursor_x + 1
                if terminal.cursor_x > terminal.width then
                    terminal.cursor_x = 1
                    terminal.cursor_y = terminal.cursor_y + 1
                    wrap_if_bottom(terminal)
                end
                terminal.dirty = true
            end
        elseif char_or_command.type == "clear" then
            local x, y = char_or_command.x or 1, char_or_command.y or 1
            local w, h =
                char_or_command.w or terminal.width,
                char_or_command.h or terminal.height
            local left, right = on_grid_span(x, x + w - 1, terminal.width)
            local top, bottom = on_grid_span(y, y + h - 1, terminal.height)
            for y = top, bottom do
                for x = left, right do
                    terminal_update_character(terminal, x, y, " ")
                end
            end
            terminal.dirty = true
        elseif char_or_command.type == "hide_cursor" then
            terminal.cursor_visible = false
        elseif char_or_command.type == "show_cursor" then
            terminal.cursor_visible = true
        elseif char_or_command.type == "cursor_color" then
            terminal.cursor_color[1] = char_or_command.red
            terminal.cursor_color[2] = char_or_command.blue
            terminal.cursor_color[3] = char_or_command.green
            terminal.cursor_color[4] = char_or_command.alpha
        elseif char_or_command.type == "cursor_backcolor" then
            terminal.cursor_backcolor[1] = char_or_command.red
            terminal.cursor_backcolor[2] = char_or_command.blue
            terminal.cursor_backcolor[3] = char_or_command.green
            terminal.cursor_backcolor[4] = char_or_command.alpha
        elseif char_or_command.type == "fresh_row" then
            local holds = false
            for _, c in ipairs(terminal.buffer[terminal.cursor_y]) do
                if c ~= " " then holds = true break end
            end
            terminal.cursor_x = 1
            if holds then
                terminal.cursor_y = terminal.cursor_y + 1
                wrap_if_bottom(terminal)
            end
        elseif char_or_command.type == "move" then
            terminal.cursor_x = on_grid(char_or_command.x, terminal.width)
            terminal.cursor_y = on_grid(char_or_command.y, terminal.height)
        elseif char_or_command.type == "reverse" then
            if char_or_command.value == nil then
                terminal.cursor_reversed = not terminal.cursor_reversed
            else
                terminal.cursor_reversed = char_or_command.value
            end
        elseif char_or_command.type == "save" then
            terminal.saved_cursor_x = terminal.cursor_x
            terminal.saved_cursor_y = terminal.cursor_y
        elseif char_or_command.type == "load" then
            terminal.cursor_x = terminal.saved_cursor_x
            terminal.cursor_y = terminal.saved_cursor_y
        elseif char_or_command.type == "frame" then
            local style = char_or_command.style
            if style == "line" then
                style = line_style
            elseif style == "thick" then
                style = thick_style
            elseif style == "block" then
                style = block_style
            else
                assert(false, string.format("Unrecognized style %s", style))
            end

            local buffer = terminal.buffer
            local state_buffer = terminal.state_buffer
            local char_color = terminal.cursor_color
            local x, y, width, height =
                char_or_command.x, char_or_command.y,
                char_or_command.w, char_or_command.h

            local left, right = x, x + width - 1
            local top, bottom = y, y + height - 1
            terminal_update_character(terminal, left, top, utf8_sub(style, 1, 1))
            terminal_update_character(terminal, right, top, utf8_sub(style, 2, 2))
            terminal_update_character(terminal, left, bottom, utf8_sub(style, 3, 3))
            terminal_update_character(terminal, right, bottom, utf8_sub(style, 4, 4))

            local horizontal_char = utf8_sub(style, 5, 5)
            local vertical_char = utf8_sub(style, 6, 6)
            -- the edges' cells on the grid; corners and edges off
            -- it are not drawn
            local from, to = on_grid_span(left + 1, right - 1, terminal.width)
            for i = from, to do
                terminal_update_character(terminal, i, top, horizontal_char)
                terminal_update_character(terminal, i, bottom, horizontal_char)
            end
            from, to = on_grid_span(top + 1, bottom - 1, terminal.height)
            for i = from, to do
                terminal_update_character(terminal, left, i, vertical_char)
                terminal_update_character(terminal, right, i, vertical_char)
            end
            terminal.dirty = true
        else
            assert(false, "Unrecognized command", char_or_command.type)
        end
    end
    terminal.accumulator = frame_budget
    -- What was written leaves the queue by moving its head, so
    -- most frames cost what they wrote, however much still
    -- waits. The written entries are dropped once they are more
    -- than half of the table: that frame copies all that waits,
    -- once per halving, and the table holds at most twice what
    -- waits.
    local stdin, written = terminal.stdin, stdin_index - 1
    if written == #stdin then
        terminal.stdin, terminal.stdin_head = {}, 0
    elseif written * 2 > #stdin then
        local rest = {}
        for i = stdin_index, #stdin do
            rest[#rest + 1] = stdin[i]
        end
        terminal.stdin, terminal.stdin_head = rest, 0
    else
        terminal.stdin_head = written
    end
end

--- @param terminal table
local function terminal_draw(terminal)
    local char_width, char_height = terminal.char_width, terminal.char_height
    if terminal.dirty then
        local previous_color = { love.graphics.getColor() }
        local previous_canvas = love.graphics.getCanvas()

        love.graphics.push()
        love.graphics.origin()

        love.graphics.setCanvas(terminal.canvas)
        -- love.graphics.clear(unpack(terminal.clear_color))
        love.graphics.setFont(terminal.font)
        local font_height = terminal.font:getHeight()
        for y, row in ipairs(terminal.buffer) do
            for x, char in ipairs(row) do
                local state = terminal.state_buffer[y][x]
                if state.dirty then
                    local left, top =
                        (x - 1) * char_width,
                        (y - 1) * char_height
                    -- Character background
                    if state.reversed then
                        love.graphics.setColor(unpack(state.color))
                    else
                        love.graphics.setColor(unpack(state.backcolor))
                    end
                    love.graphics.rectangle("fill",
                        left, top + (font_height - char_height),
                        terminal.char_width, terminal.char_height)

                    -- Character
                    if state.reversed then
                        love.graphics.setColor(unpack(state.backcolor))
                    else
                        love.graphics.setColor(unpack(state.color))
                    end
                    love.graphics.print(char, left, top)
                    state.dirty = false
                end
            end
        end
        terminal.dirty = false
        love.graphics.pop()

        love.graphics.setCanvas(previous_canvas)
        love.graphics.setColor(unpack(previous_color))
    end

    love.graphics.draw(terminal.canvas)
    if terminal.cursor_visible then
        love.graphics.setFont(terminal.font)
        if love.timer.getTime() % 1 > 0.5 then
            love.graphics.print("_",
                (terminal.cursor_x - 1) * char_width,
                (terminal.cursor_y - 1) * char_height)
        end
    end
end

-- Drop bytes that are not valid UTF-8. The terminal renders
-- UTF-8 only, and utf8.codes raises on a malformed sequence, so
-- an undefended write of a stray byte (e.g. from a serial board)
-- takes the whole output down. Defend here, at the one sink all
-- writes pass through, dropping what is not text -- the same
-- policy model/serial/echo.lua already applies to its own path.
local function utf8_clean(s)
    local out = s
    local ok, bad = utf8.len(out)
    while not ok do
        out = out:sub(1, bad - 1) .. out:sub(bad + 1)
        ok, bad = utf8.len(out)
    end
    return out
end

local function terminal_print(terminal, x, y, ...)
    local res_string = nil

    -- argument processing
    -- shortcut : no coordinates => print at cursor position
    if type(x) == "string" then
        res_string = x
    else
        terminal:move_to(x, y)
        res_string = string.format(...)
    end

    for i, p in utf8.codes(utf8_clean(res_string)) do
        table.insert(terminal.stdin, utf8.char(p))
    end
end

local function terminal_blit(terminal, x, y, str)
    for line in str:gmatch("[^\r\n]+") do
        terminal_print(terminal, x, y, "%s", line)
        y = y + 1
    end
end


local function terminal_save_position(terminal)
    table.insert(terminal.stdin, { type = "save" })
end

local function terminal_load_position(terminal)
    table.insert(terminal.stdin, { type = "load" })
end

--- @class Terminal table
--- @field width integer
--- @field height integer
--- @field update function
--- @field cursor_visible boolean
--- @field cursor_x integer
--- @field cursor_y integer
--- @field saved_cursor_x integer
--- @field saved_cursor_y integer
--- @field cursor_color table
--- @field cursor_backcolor table
--- @field cursor_reversed boolean
--- @field dirty boolean
--- @field char_width integer
--- @field char_height integer
--- @field speed integer
--- @field char_cost integer
--- @field accumulator integer
--- @field stdin table --- what waits, after `stdin_head` written entries
--- @field stdin_head integer
--- @field waiting fun(self: Terminal): fun(): any --- what waits, in order
--- @field clear_color table
--- @field clear_color_alpha table
--- @field canvas love.Canvas
--- @field buffer table
--- @field state_buffer table
--- @field on_row_leaving fun(chars: string[], states: table[])?
--- called with the row leaving the top while it is still whole

--- @return Terminal
local function terminal(self, width, height,
                        font, custom_char_width, custom_char_height)
    local char_width = custom_char_width or font:getWidth('█')
    local char_height = custom_char_height or font:getHeight()
    local num_columns = math.floor(width / char_width)
    local num_rows = math.floor(height / char_height)
    local instance = {
        width = math.floor(num_columns),
        height = math.floor(num_rows),
        font = font,

        cursor_visible = true,
        cursor_x = 1,
        cursor_y = 1,
        saved_cursor_x = 1,
        saved_cursor_y = 1,
        cursor_color = { 1, 1, 1, 1 },
        cursor_backcolor = { 0, 0, 0, 1 },
        cursor_reversed = false,

        dirty = false,
        char_width = char_width,
        char_height = char_height,

        speed = 800,
        char_cost = 1,
        accumulator = 0,
        stdin = {},
        stdin_head = 0,

        clear_color = { 0, 0, 0 },
        clear_color_alpha = { 1, 1, 1, 0 },

        canvas = love.graphics.newCanvas(width, height),
        buffer = {},
        state_buffer = {},
    }

    for i = 1, num_rows do
        local row = {}
        local state_row = {}
        for j = 1, num_columns do
            row[j] = ' '
            state_row[j] = {
                color = { 1, 1, 1, 1 },
                backcolor = { 0, 0, 0, 1 },
                dirty = true
            }
        end
        instance.buffer[i] = row
        instance.state_buffer[i] = state_row
    end

    instance.update = terminal_update
    instance.draw = terminal_draw
    instance.print = terminal_print
    instance.blit = terminal_blit
    instance.clear = terminal_clear
    instance.save_position = terminal_save_position
    instance.load_position = terminal_load_position
    instance.move_to = terminal_move_to
    instance.fresh_row = terminal_fresh_row
    instance.discard = terminal_discard
    instance.waiting = terminal_waiting
    instance.hide_cursor = terminal_hide_cursor
    instance.show_cursor = terminal_show_cursor
    instance.reverse_cursor = terminal_reverse
    instance.set_cursor_color = terminal_set_cursor_color
    instance.set_cursor_backcolor = terminal_set_cursor_backcolor

    instance.frame = terminal_frame

    local previous_canvas = love.graphics.getCanvas()
    love.graphics.setCanvas(instance.canvas)
    love.graphics.clear(instance.clear_color)
    love.graphics.setCanvas(previous_canvas)

    return instance
end

local module = {
    _VERSION = 'lv-100 v0.0.1',
    _DESCRIPTION = "A simple terminal-like emulator for Love2D",
    _URL = "https://github.com/Eiyeron/LV-100",
    _LICENCE = [[
MIT License

Copyright (c) 2018 Florian Dormont

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]],
    terminal = terminal,
    schemes = {
        basic = basic_scheme
    }
}
setmetatable(module, { __call = module.terminal })

return module
