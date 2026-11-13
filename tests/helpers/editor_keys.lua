-- Drives the editor the way a user does: every key and every
-- character goes through love.handlers (input_fixture's
-- session), over a project held in memory, and files open by
-- typing edit("name") in the console. Tests READ state
-- through the accessors below and never DRIVE the editor by
-- calling a controller or a model.

local F = require("tests.helpers.input_fixture")
local mock = require("tests.mock")
local FS = require("util.filesystem")

local K = { }

-- the memory project's name, as the status line shows it
K.PROJECT = "demo"
local files, writes, restore
-- a write fails with this reason while it is set
local write_failure
-- Caps Lock, a device state its key toggles
local caps = false

function K.setup()
  F.setup()
end
function K.teardown()
  F.teardown()
end

-- A root no real path shares, so the stubs below can tell
-- the memory project's files from every other path.
local ROOT = "/memory-k/"

local function path_of(_, f)
  return ROOT .. f
end

local function read(_, f)
  return true, files[f]
end

local function write(_, f, text)
  if write_failure then
    return false, write_failure
  end
  writes[#writes + 1] = f
  files[f] = text
  return true
end

local function memory_project()
  return {
    name = K.PROJECT,
    path = ROOT,
    required = { },
    get_path = path_of,
    readfile = read,
    writefile = write
  }
end

--- FS.exists answered for the memory project, `exists` asked
--- for every other path.
local function exists_over(exists)
  return function(path)
    local f = path:match("^/memory%-k/(.+)$")
    if f then
      return files[f] ~= nil
    end
    return exists(path)
  end
end

--- Stub the filesystem calls the editor makes; returns what
--- puts them back.
local function stub_fs()
  local exists, fsync = FS.exists, FS.fsync
  FS.exists = exists_over(exists)
  function FS.fsync()
    return true
  end
  return function()
    FS.exists, FS.fsync = exists, fsync
  end
end

--- love.keyboard answers whether Caps Lock is on, as LÖVE's
--- isModifierActive does; returns what puts it back.
local function stub_caps()
  local kb = love.keyboard
  local active = kb.isModifierActive
  function kb.isModifierActive(m)
    if m == "capslock" then
      return caps
    end
    return active and active(m) or false
  end
  return function()
    kb.isModifierActive = active
  end
end

-- each stands in for a boundary and returns what puts it back
local STUBS = {
  stub_fs,
  stub_clipboard,
  stub_run,
  stub_caps
}

--- Open the memory project; returns what puts the previous
--- project and the filesystem back.
--- The system clipboard as a value of the test's own, which
--- the fixture's runtime does not keep; returns what puts the
--- runtime's back.
local function stub_clipboard()
  local sys, clip = love.system, ""
  local get, set = sys.getClipboardText, sys.setClipboardText
  function sys.getClipboardText()
    return clip
  end
  function sys.setClipboardText(t)
    clip = t
  end
  return function()
    sys.getClipboardText, sys.setClipboardText = get, set
  end
end

--- Open the memory project; returns what puts the previous
--- project, the filesystem and the clipboard back.
--- A run (Ctrl+T) loads main.lua from the memory project, as
--- the project loader does from the card; returns what puts
--- the service's own loader back.
local function stub_run(projects)
  local run = projects.run
  function projects.run(_, _, env)
    local chunk = assert(
      loadstring(files["main.lua"] or "", "main.lua")
    )
    return setfenv(chunk, env), nil, ROOT
  end
  return function()
    projects.run = run
  end
end

--- Open the memory project; returns what puts the previous
--- project, its loader, the filesystem and the clipboard back.
local function stub_all(projects)
  local undo = { }
  for _, stub in ipairs(STUBS) do
    undo[#undo + 1] = stub(projects)
  end
  return function()
    for _, u in ipairs(undo) do
      u()
    end
  end
end

local function use_memory_project()
  local projects = K.cc.model.projects
  local prev = projects.current
  projects.current = memory_project()
  local unstub = stub_all(projects)
  return function()
    projects.current = prev
    unstub()
    mock.release_keys()
  end
end

--- Reset the fixture; when a test left the editor broken (it
--- raised half-way through a key), build a new one, so one
--- crash fails one test, not every test after it.
local function fresh_fixture()
  if pcall(F.reset) then
    return
  end
  F.teardown()
  F.setup()
  F.reset()
end

--- Call in before_each. `contents` maps file names to text;
--- the default is one file, main.lua, holding `x = 1`.
--- @param contents table<string, string>?
function K.reset(contents)
  K.cleanup()
  fresh_fixture()
  K.cc, K.ed = F.cc, nil
  -- the editor remembers positions and state across opens;
  -- a test starts with none
  K.cc.editor.pos_memory = { }
  K.cc.editor.state = nil
  files = contents or { ["main.lua"] = "x = 1\n" }
  writes, write_failure, caps = { }, nil, false
  restore = use_memory_project()
end

--- A fresh console over the same memory card: the files as
--- they are now, every other state reset. For a test that
--- opens a second file from the console.
function K.restart()
  K.reset(files)
end

--- Call in after_each: the project, the filesystem and the
--- clipboard go back.
function K.cleanup()
  if restore then
    restore()
  end
  restore = nil
end

--- @param name string?  main.lua when omitted
--- Open a file as the user does: type edit("name") in the
--- console and press Enter.
function K.open(name)
  K.type("edit(\"" .. (name or "main.lua") .. "\")")
  K.keys("return")
  K.ed = K.cc.editor
end

--- Change a file on the card, not through the editor: as
--- another program, or another device, would.
function K.write_outside(name, text)
  files[name] = text
end

--- From now on, every write fails with `reason`, as a full or
--- removed card would answer.
--- @param reason string
function K.fail_writes(reason)
  write_failure = reason
end

-- keystrokes -------------------------------------------------
-- A person's keystrokes are frames apart, and a key with a
-- character sends it between its press and its release, as
-- LÖVE does. The editor depends on both (a Space that answers
-- a question swallows its own character, until the next
-- frame).

--- Let one frame pass.
--- @param dt number?  seconds, 1/60 when omitted
function K.frame(dt)
  F.love_update(dt or 1 / 60)
end

-- the character a key sends on its own, or with Shift
local GLYPH = { space = " " }

local function glyph(key, shifted)
  local g = GLYPH[key] or (#key == 1 and key) or nil
  local as_is = not shifted or not g
  if as_is then
    return g
  end
  return g:match("%l") and g:upper() or nil
end

local MODS = {
  lshift = "shift",
  rshift = "shift",
  lctrl = "other",
  rctrl = "other",
  lalt = "other",
  ralt = "other",
  lgui = "other",
  rgui = "other"
}

--- The character a chord types, or nil: only a key alone, or
--- with Shift, types one.
local function chord_glyph(ks)
  local shifted = false
  for i = 1, #ks - 1 do
    local m = MODS[ks[i]]
    if m ~= "shift" then
      return nil
    end
    shifted = true
  end
  return glyph(ks[#ks], shifted)
end

local function chord(ks, ch)
  caps = caps ~= (ks[#ks] == "capslock")
  for _, k in ipairs(ks) do
    F.session.press(k)
  end
  if ch then
    F.session.type(ch)
  end
  for i = #ks, 1, -1 do
    F.session.release(ks[i])
  end
  K.frame()
end

--- Press and release a chord, modifiers first and released
--- last, then a frame: K.keys('lctrl', 'up'). A printable key
--- types its character, as on the device.
function K.keys(...)
  local ks = { ... }
  chord(ks, chord_glyph(ks))
end

--- Type several lines into the draft, Shift+Enter between
--- them, as IS3.15 breaks a line.
--- @param lines string[]
function K.type_lines(lines)
  for i, l in ipairs(lines) do
    if 1 < i then
      K.keys("lshift", "return")
    end
    K.type(l)
  end
end

--- Press `k` and keep it down, then a frame: for what happens
--- while a key is held (K.release lets it go).
function K.hold(k)
  F.session.press(k)
  K.frame()
end

function K.release(k)
  F.session.release(k)
  K.frame()
end

-- presses enough for any file a test holds
local MAX_PRESSES = 200

--- Browse to the end position with bare Down, which browses
--- while the field is empty (IS2.1).
function K.browse_to_end()
  for _ = 1, MAX_PRESSES do
    if K.position() == "end" then
      return
    end
    K.keys("down")
  end
  error("the end position was not reached")
end

--- Browse to block `b` with Ctrl+Up and Ctrl+Down, as many
--- presses as it takes: a tall block may scroll first (IS2.2).
function K.browse_to(b)
  for _ = 1, MAX_PRESSES do
    local p = K.position()
    if p == b then
      return
    end
    local up = p == "end" or b < p
    K.keys("lctrl", up and "up" or "down")
  end
  error("block " .. b .. " was not reached")
end

--- A repeat event for a held key, as the keyboard sends it.
function K.repeat_key(k)
  F.session.repeat_press(k)
  K.frame()
end

--- The keys that type `ch`, or nil when it has no key of its
--- own on the keyboard (it is then sent as text alone).
local function keys_for(ch)
  local key = ch == " " and "space" or ch:lower()
  local has_key = key == "space" or key:match("^[%l%d]$")
  if not has_key then
    return nil
  end
  if ch:match("^%u$") then
    return {
      "lshift",
      key
    }
  end
  return { key }
end

--- Type `text` a character at a time, each with its key where
--- it has one, a frame after each. A line break is a key
--- (Shift+Enter), not text: K.type refuses it.
--- @param text string  UTF-8
function K.type(text)
  assert(not text:find("[%c]"), "K.type takes no control " ..
      "character; press its keys with K.keys")
  local char = "[%z\1-\127\194-\244][\128-\191]*"
  for ch in text:gmatch(char) do
    local ks = keys_for(ch)
    if ks then
      chord(ks, ch)
    else
      F.session.type(ch)
      K.frame()
    end
  end
end

-- read-only accessors ----------------------------------------
-- In the spec's terms, so that a test reads as its item does.

--- The number of blocks in the open file.
function K.blocks()
  return K.buffer():get_content_length()
end

--- The browsing position: a block's number, or "end".
function K.position()
  local sel = K.buffer():get_selection()
  if K.blocks() < sel then
    return "end"
  end
  return sel
end

--- The replacement target's block number, or nil.
function K.target()
  return K.buffer().loaded
end

--- "browsing", "inserting" or "replacing".
function K.state()
  if K.target() then
    return "replacing"
  end
  if K.draft() ~= "" then
    return "inserting"
  end
  return "browsing"
end

--- The draft, its lines joined with a line break.
function K.draft()
  local t = K.ed.input:get_text()
  if type(t) == "table" then
    return table.concat(t, "\n")
  end
  return t
end

--- @return integer line, integer column
function K.cursor()
  return K.ed.input.model:get_cursor_pos()
end

--- The open file's name, the top of the editor's stack; nil
--- when no file is open.
function K.file_name()
  local b = K.buffer()
  return b and b.name
end

local TYPES = {
  lua = "lua",
  md = "markdown",
  plain = "plain"
}

--- The open file's type: "lua", "markdown" or "plain"; nil
--- when no file is open.
function K.file_type()
  local b = K.buffer()
  return b and TYPES[b.content_type]
end

--- The message shown over the field, its parts joined, or
--- nil when none shows.
local function part_text(v)
  if type(v) == "table" then
    return tostring(v.msg or v[1])
  end
  return tostring(v)
end

function K.message()
  local e = K.ed.input.model.error
  if type(e) ~= "table" then
    return e and tostring(e)
  end
  local out = { }
  for i, v in ipairs(e) do
    out[i] = part_text(v)
  end
  return table.concat(out, " ")
end

--- The console's draft, its lines joined.
function K.console_draft()
  local t = F.console:get_text()
  if type(t) == "table" then
    return table.concat(t, "\n")
  end
  return t
end

function K.buffer()
  return K.ed:get_active_buffer()
end
function K.app_state()
  return love.state.app_state
end
function K.has_error()
  return K.ed.input:has_error()
end
function K.clipboard()
  return love.system.getClipboardText()
end

--- What the file holds on the memory card.
--- @param name string?  main.lua when omitted
function K.file(name)
  return files[name or "main.lua"]
end

--- The names written, in order, since the last reset.
function K.writes()
  local out = { }
  for i, w in ipairs(writes) do
    out[i] = w
  end
  return out
end

-- test data ------------------------------------------------

--- The lines of one Lua block `n` lines long, canonically
--- formatted (the formatter leaves it as it is): a function
--- with `n - 2` assignments.
function K.block_lines(n)
  local t = { "function f()" }
  for i = 1, n - 2 do
    t[#t + 1] = "  v" .. i .. " = " .. i
  end
  t[#t + 1] = "end"
  return t
end

--- That block as file text, its last line terminated.
function K.block(n)
  return table.concat(K.block_lines(n), "\n") .. "\n"
end

-- what the screen shows ------------------------------------

--- The console's text: its rows, then what is still being
--- printed.
function K.console_text()
  local term = K.cc.model.output.terminal
  local rows, pending = { }, { }
  for y, row in ipairs(term.buffer) do
    rows[y] = table.concat(row):gsub("%s+$", "")
  end
  for _, c in ipairs(term.stdin) do
    if type(c) == "string" then
      pending[#pending + 1] = c
    end
  end
  return table.concat(rows, "\n") .. table.concat(pending)
end

local function doc_view()
  return K.ed.view:get_current_buffer()
end

--- The document view's rows, numbered, of block `b`.
local function rows_of(b)
  local bv, out = doc_view(), { }
  local lines = { b }
  if bv.content_type == "lua" then
    local pos = bv.content:get_block_pos(b)
    lines = pos and pos:enumerate() or { }
  end
  for _, l in ipairs(lines) do
    for _, r in ipairs(bv.content.wrap_forward[l] or { }) do
      out[#out + 1] = r
    end
  end
  return out
end

--- How many rows block `b` has, and how many of them the
--- document view shows.
function K.rows_shown(b)
  local rows, range = rows_of(b), doc_view().content.range
  local shown = 0
  for _, r in ipairs(rows) do
    if range:inc(r) then
      shown = shown + 1
    end
  end
  return #rows, shown
end

--- Every row of block `b` is in the document view.
function K.in_view(b)
  local rows, shown = K.rows_shown(b)
  return 0 < rows and rows == shown
end

--- The text of the rows the document view shows.
function K.view_rows()
  local out = { }
  for i, r in ipairs(doc_view().content:get_visible()) do
    out[i] = r
  end
  return out
end

-- What a recorded draw collects: the colour last set, and
-- each filled rectangle with its colour.
local rec = {
  colour = {
    1,
    1,
    1,
    1
  },
  fills = { },
  texts = { }
}

local function rec_set_color(c, ...)
  rec.colour = type(c) == "table" and c
       or {
    c,
    ...
  }
end

local function rec_get_color()
  return unpack(rec.colour)
end

local function rec_rectangle(mode, _, y)
  if mode ~= "fill" then
    return
  end
  rec.fills[#(rec.fills) + 1] = {
    y = y,
    colour = rec.colour
  }
end

local function rec_print(text)
  rec.texts[#(rec.texts) + 1] = {
    text = text,
    colour = rec.colour
  }
end

local function no_op()
  
end

-- the graphics calls the document view's draw makes
local RECORDING = {
  setColor = rec_set_color,
  getColor = rec_get_color,
  rectangle = rec_rectangle,
  print = rec_print,
  setBlendMode = no_op
}

--- Run the document view's draw with the recording calls in
--- place of love.graphics', put those back, and return the
--- fills.
local function swap_in(lg, calls)
  local saved = { }
  for name, f in pairs(calls) do
    saved[name], lg[name] = lg[name], f
  end
  return saved
end

local function record_draw()
  rec.fills, rec.texts = { }, { }
  local saved = swap_in(love.graphics, RECORDING)
  local ok, e = pcall(function()
    doc_view():draw()
  end)
  swap_in(love.graphics, saved)
  assert(ok, e)
  return rec.fills
end

local function same_colour(a, b)
  for i = 1, 3 do
    local near = math.abs((a[i] or 0) - (b[i] or 0)) < 0.001
    if not near then
      return false
    end
  end
  return true
end

local function kind_of(colour, colours)
  if same_colour(colour, colours.highlight) then
    return "white"
  end
  if same_colour(colour, colours.highlight_loaded) then
    return "yellow"
  end
end

--- The block a row of the document view belongs to, counted
--- from the view's top row.
local function block_at(view_row)
  local abs = doc_view().content.range.start + view_row - 1
  for b = 1, K.blocks() do
    for _, r in ipairs(rows_of(b)) do
      if r == abs then
        return b
      end
    end
  end
end

local function add_fill(out, kind, row)
  out.rows[kind] = (out.rows[kind] or 0) + 1
  local b, list = block_at(row), out[kind]
  local is_new = b and list[#list] ~= b
  if is_new then
    list[#list + 1] = b
  end
end

local function new_highlights()
  return {
    white = { },
    yellow = { },
    rows = { }
  }
end

--- What the document view draws highlighted: the blocks under
--- the white browsing highlight and under the yellow target
--- highlight, read from the fills of its draw, each block
--- once; `rows` counts the highlighted rows of each colour.
--- @return { white: integer[], yellow: integer[], rows: table }
function K.highlights()
  local bv = doc_view()
  -- the row height the view draws with (bufferView.lua)
  local fh = bv.cfg.fh * 1.032
  local out = new_highlights()
  for _, f in ipairs(record_draw()) do
    local kind = kind_of(f.colour, bv.cfg.colors.editor)
    local row = math.floor(f.y / fh + 0.5) + 1
    if kind then
      add_fill(out, kind, row)
    end
  end
  return out
end

local function colour_key(c)
  return string.format(
    "%.2f,%.2f,%.2f",
    c[1] or 0,
    c[2] or 0,
    c[3] or 0
  )
end

-- the glyph the view fills a selected token's background with
local FILL_GLYPH = "█"

local function is_text(t)
  local s = type(t) == "string" and t
  return s and s:match("%S")
       and not s:find(FILL_GLYPH, 1, true)
end

--- The colours the document view draws its text in, as a
--- set of "r,g,b" keys, each with the text drawn in it.
function K.text_colours()
  record_draw()
  local out = { }
  for _, t in ipairs(rec.texts) do
    if is_text(t.text) then
      local key = colour_key(t.colour)
      out[key] = (out[key] or "") .. t.text
    end
  end
  return out
end

--- The highlight drawn on the browsing position, as before:
--- its colour and block, or nil when none is drawn.
function K.highlight()
  local h = K.highlights()
  if h.white[1] then
    return "white", h.white[1]
  end
  if h.yellow[1] then
    return "yellow", h.yellow[1]
  end
  return nil
end

--- The text of the rows the editor field shows.
function K.field_rows()
  local out = { }
  for i, r in ipairs(K.ed.input.model.visible:get_visible()) do
    out[i] = r
  end
  return out
end

--- What the editor field's render colours the draft from:
--- the number of token classes in it, and where the parse
--- error that turns the rest red starts, as line and column
--- (nil when the draft parses). Read from the field's model,
--- which its render reads: the field draws to a canvas the
--- fixture does not render.
local function count_classes(hl)
  local seen, n = { }, 0
  for _, row in pairs(hl or { }) do
    for _, c in pairs(row) do
      if not seen[c] then
        seen[c], n = true, n + 1
      end
    end
  end
  return n
end

local function error_at(e)
  if type(e) ~= "table" then
    return nil
  end
  return {
    e.l,
    e.c
  }
end

function K.field_highlight()
  local h = K.ed.input.model:get_highlight() or { }
  return count_classes(h.hl), error_at(h.parse_err)
end

--- The key card shown while the help key is held (FR4.9): its
--- lines, or nil while none shows. The editor draws no card
--- yet, so this reads nil until it does; the card's own
--- model is read here once it exists.
function K.key_card()
  return nil
end

--- Everything the status line shows, as one string.
local function walk(v, out)
  if type(v) == "table" then
    for _, x in pairs(v) do
      walk(x, out)
    end
  elseif v ~= nil then
    out[#out + 1] = tostring(v)
  end
end

function K.status_text()
  local out = { }
  walk(K.ed.input:get_status(), out)
  table.sort(out)
  return table.concat(out, " ")
end

return K
