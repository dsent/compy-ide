Prof = require("controller.profiler")
require("view.view")
require("controller.projectInputController")

require("util.string.string")
require("util.key")
require("util.lua")
local LANG = require("util.eval")
local End = require("util.program_end")
local FS = require("util.filesystem")
local Application = require("util.application")
local Blink = require("view.input.cursorBlink")
local own = require("view.ownState")
local KeyCard = require('model.editor.keyCard')

local messages = {
  user_break = "BREAK into program",
  exit_anykey = "Press any key to exit.",
  exec_error = function(err)
    Log.error((debug.traceback(
      "Error: " .. tostring(err), 1):gsub("\n[^\n]+$", "")
    ))
    return 'Execution error at ' .. err
  end
}

local get_user_input = function()
  if love.state.app_state == 'inspect' then return end
  return love.state.user_input
end


--- @type boolean
local user_update
--- @type boolean
local user_draw
--- The program's own love.draw, which the IDE's draw calls onto
--- the program's canvas each frame (draw_program); nil while
--- none is installed, at a pause included
--- @type function?
local program_draw
--- @type boolean
-- set when a project installs any pointer/click handler.
-- Together with a shown input widget it marks a non-blocking
-- project (one that overrides no update/draw, e.g. a
-- pen-and-paper game) as still "live"
-- in 'ready' (doc/development/technical_debt/input.md,
-- "Input-only / pointer-only projects stay live", RESOLVED,
-- ruling a): keep the project route, and its own quit stops it
-- back to the console.
local user_pointer

-- One lifetime, several names for subsets of it. Every channel
-- installs the same way, runs the same chain, and is released
-- at the same moment: the project's stop. The split that
-- existed here (keyboard released at running->ready,
-- pointer exempted so pen-and-paper projects survived it) came
-- with this feature and is gone: at the PR base nothing was
-- released before suspend or stop. The subsets below name what
-- a group CARRIES, never how it is routed: keyboard/text events
-- have a combo trigger and therefore a shortcuts tier.
local _keyboard = {
  'keypressed',
  'keyreleased',
  'textinput',
}

local _pointer = {
  'mousemoved',
  'mousepressed',
  'mousereleased',
  'wheelmoved',

  'touchmoved',
  'touchpressed',
  'touchreleased',
}

-- Derived events: not LÖVE's. The click timer in
-- set_love_update synthesises them from raw presses. They
-- travel gateway and route like native ones, so a project reads
-- through compy.input.hooks like anything else. They stay a
-- named subset only because the timer needs to know which
-- events it synthesises — never to decide how one is bound.
local _derived = {
  'singleclick',
  'doubleclick',
}

local _supported = {}
for _, k in ipairs(_keyboard) do
  table.insert(_supported, k)
end
for _, k in ipairs(_pointer) do
  table.insert(_supported, k)
end

-- Every channel a project can bind, native and derived. One
-- list, because seeding, teardown and dispatch have to agree
-- about what a channel is, and three hand-kept subsets did not:
-- a project writing love.singleclick got nothing, while the
-- same project writing love.mousepressed got a seeded hook.
local _bindable = {}
for _, k in ipairs(_supported) do
  table.insert(_bindable, k)
end
for _, k in ipairs(_derived) do
  table.insert(_bindable, k)
end

--- @param CC ConsoleController
--- @param msg any
local function user_error_handler(CC, msg)
  msg = tostring(msg)
  Log.debug('user error: ' .. msg)
  local err = LANG.get_call_error(msg) or ''
  local user_msg = messages.exec_error(err)
  --- said once, in the output: the pause adds nothing
  CC:suspend_run()
  CC.model.output:write_error(user_msg)
end

--- @param f function
--- @param CC ConsoleController
--- @param ...   any
--- @return boolean success
--- @return any result
--- @return any ...
-- The message handler MUST be a closure binding CC: xpcall
-- calls it with exactly one argument (the error), so passing
-- user_error_handler directly bound CC to the error string,
-- left msg nil, and raised inside the handler — where xpcall
-- swallowed it, so a project raise vanished with no error
-- window at all (doc/development/technical_debt/input.md,
-- "`wrap`'s error handler is called with the wrong arity").
--
-- The arguments are CLOSED OVER, not passed through xpcall.
-- `xpcall(f, h, ...)` forwarding arguments to `f` is a
-- LuaJIT/5.2 extension; PUC Lua 5.1 takes exactly two and
-- drops the rest, calling every handler with nil for all of
-- its parameters. This form asks nothing of the runtime, so
-- there is no platform branch to get wrong — the previous one
-- keyed off `_G.web` (the Web build, which is PUC 5.1) and so
-- missed `busted` running on PUC 5.1, where it cost 107 red
-- cases (`doc/development/technical_debt/input.md`, RETIRED,
-- "`wrap` guards the `xpcall` arity hazard on the platform").
--
-- `select('#')`, not `#args`: an explicit nil argument is an
-- argument, and the two disagree about that.
---
--- A lifecycle call in the program (stop(), run(), ...) ends it
--- with util.program_end's ENDED, which is no error: nothing is
--- said, and the call reports success with no result.
local function wrap(f, CC, ...)
  local function on_error(msg)
    if End.is(msg) then return msg end
    user_error_handler(CC, msg)
  end
  local args, n = { ... }, select('#', ...)
  End.enter()
  local ok, res = xpcall(function()
    return f(unpack(args, 1, n))
  end, on_error)
  End.leave()
  if not ok and End.is(res) then return true end
  return ok, res
end

--- Run `fn` the way project code must always be run: drawing
--- routed onto the project's canvas, errors routed to the
--- project error handler, return value propagated.
---
--- Applied where a route is ENTERED, not around each chain
--- participant: the walk carries no error handling of its own,
--- so wrapping participants left a raise in `shortcuts[...]`
--- or a directly-assigned `hooks[...]` escaping the chain, and
--- made a raise in the widget look like "did not consume", so
--- the walk carried on past it.
--- @param CC ConsoleController
--- @param fn function
--- @return function
local function with_canvas_and_errors(CC, fn)
  return function(...)
    local args = { ... }
    --- what the program asked for is made off the canvas, once
    --- the route has returned (util.program_end)
    return End.held(function()
      return CC:use_canvas(function()
        local ok, res = wrap(fn, CC, unpack(args))
        if ok then return res end
      end)
    end)
  end
end

--- The project's own handler for an event, raw; nil when the
--- project did not define one. NOT wrapped — the boundary
--- covers it once the route is entered, which is what makes a
--- seeded handler an ordinary chain participant rather than a
--- specially-protected one (doc/development/decisions/input.md,
--- D-HOOKS-SEEDED).
---
--- The guard is load-bearing, not ceremony: without it a
--- project that never overrode an event seeds `hooks[event]`
--- with the framework's own default, which would then run as
--- if it were the project's.
---
--- Early return rather than an `if` around the body: an `if`
--- would nest what follows a level deeper.
--- @param userlove table
--- @param key string
--- @return function? handler
local function project_handler(userlove, key)
  local new = userlove[key]
  if not new or new == Controller._defaults[key] then return end
  return new
end

--- The project's own keyboard/text handlers, for seeding as
--- hooks[event] (doc/development/decisions/input.md,
--- D-HOOKS-SEEDED) — raw, so a seeded hook is an ordinary chain
--- participant: it consumes on truthy and falls through on
--- falsey exactly like one the project assigned itself.
--- @param userlove table
--- @param CC ConsoleController
--- @return table handlers
local function project_handlers(userlove, CC)
  local out = {}
  for _, k in ipairs(_bindable) do
    out[k] = project_handler(userlove, k)
  end
  return out
end


--- The release events, each the end of a press
local RELEASES = { keyreleased = true, mousereleased = true,
  touchreleased = true }

--- The serial handlers a program may set, by field
local SERIAL_FIELDS = { 'onConnect', 'onDisconnect', 'onBytes',
  'onLine', 'onTick' }

--- Whether the program whose route holds the input can still
--- act: an update or a draw, a hook or a non-empty shortcut
--- table on any channel, its own shown field, or a serial
--- handler. Such a program owns all input (the maintainer's
--- ruling of November 17, 2026: "all input is the program's
--- while it runs"); one that can do none of these has ended at
--- its last line, and the input is the console's again. Asked
--- as each event comes, since hooks and shortcuts come and go;
--- the hook table is the one record (a program's own love.*
--- handlers are seeded there when its run begins).
--- @param compy_input table?
--- @return boolean
local function can_act(compy_input)
  if user_update or user_draw then return true end
  if compy_input then
    for _, event in ipairs(_bindable) do
      if compy_input.hooks[event] then return true end
      if next(compy_input.shortcuts[event] or { }) then
        return true
      end
    end
  end
  local field = love.state.user_input_controller
  if field ~= nil and field:is_shown() == true then return true end
  local port = rawget(_G, 'SerialPort')
  local serial = port and port.table_for and port:table_for('program')
  if serial then
    for _, f in ipairs(SERIAL_FIELDS) do
      if serial[f] then return true end
    end
  end
  return false
end

--- The project route occupies the keyboard/text handlers for
--- the run; the project's own handlers ride along for
--- delegation (never route owners themselves).
--- @param userlove table
--- @param CC ConsoleController
-- `userlove`: the project's sandboxed `love` table. `occupy`:
-- take over the keyboard/text handlers for the project route's
-- run (doc/development/decisions/input.md D-ROUTE-LIFETIME uses
-- this verb). Giving the project route its own connect path —
-- not a generic route swap — is deliberate: the three routes
-- are not yet fully symmetric (the editor is still reached via
-- the console fork), so PIC is wired explicitly here. See
-- doc/development/decisions/input.md #1 "route-centric routing"
-- + #11 "route connects only while running". It installs even
-- with no project handlers: per event, a program that can act
-- (can_act, above) owns it, and one that can act no more gives
-- the route back to the console. (`userlove` rename:
-- technical_debt.)
--- Who has the keys now: 'console' (the console and the file
--- editor), or the number of the program run whose route holds
--- them; a pause and continue() keep the run's number, a new
--- run takes the next (set_user_handlers)
local route_owner, program_count = 'console', 0

--- Whether a receiver the gate recorded is a program run's
--- @param to any
--- @return boolean
local function to_program(to)
  return type(to) == 'number'
end
--- Releases a paused program is owed, by its number: a key it
--- got the press of and that was let go while it waited. They
--- come at continue(), and go with the run otherwise.
local owed_releases = { }

--- @param resume boolean? --- continue(): the hooks are as the
---   pause left them, and none is seeded anew (round 20)
local function occupy_input(userlove, CC, resume)
  local pic = Controller.project_input
  local compy = CC:get_project_env().compy
  pic:activate(not resume and project_handlers(userlove, CC) or nil,
    compy.input)
  -- with_canvas_and_errors here, not around each participant:
  -- route IS the boundary, so every tier of the walk runs with
  -- the project canvas bound and one error handler above it.
  -- Wrapped (not assigned) to bind `pic` as method receiver:
  -- `love.keypressed = pic.keypressed` would drop `self`.
  for _, k in ipairs(_bindable) do
    love[k] = with_canvas_and_errors(CC, function(...)
      --- a program that can no longer act has ended at its last
      --- line: the input is the console's again, this event
      --- first (asked as the event comes, before any chain)
      if not can_act(pic.compy_input) then
        Controller.release_keyboard_route(CC)
        --- a release is of a press the program got: it goes to
        --- no one, the console having seen no press (p3)
        if RELEASES[k] then return end
        local console = Controller._defaults[k]
        if console then return console(...) end
        return
      end
      -- LÖVE discards a handler's return, so the
      -- walk's verdict is spent here or not at all. What the
      -- program's chain leaves goes nowhere: a program that can
      -- act owns all input (November 17). A key it takes leaves
      -- a scrolled view where it is (ruling 1.2).
      if pic[k](pic, ...) then return end
      --- an event whose handler asked to stop or replace the run
      --- is that request's: the output does not get it either
      --- (util.program_end)
      if End.pending then return end
      --- the one exception, ruling 1.1: the output stays in use,
      --- and takes its own scrolling keys and the wheel when
      --- the program's chain left them
      if k == 'keypressed' then
        local key, _, isr = ...
        CC:output_key(key, isr)
      elseif k == 'wheelmoved' then
        local _, y = ...
        CC:output_wheel(y)
      end
    end)
  end
  route_owner = program_count
end

--- The releases a paused program is owed, at its continue():
--- after every handler is back, so that a release that stops
--- the run is the last word, and none after it is delivered
local function deliver_owed()
  local run = route_owner
  local due = owed_releases[run]
  owed_releases = { }
  for k, sc in pairs(due or { }) do
    --- a release that asked to stop or replace the run is the
    --- last the program sees (util.program_end)
    if End.pending then return end
    love.keyreleased(k, sc)
  end
end

--- `user_pointer` marks a non-blocking project as still
--- interactive, so it keeps the route in 'ready'
--- (doc/development/technical_debt/input.md, ruling (a)). Set
--- from the project's own pointer handlers and its click hooks.
--- @param userlove table
--- @param CC ConsoleController
local function mark_pointer_liveness(userlove, CC)
  for _, k in ipairs(_pointer) do
    if project_handler(userlove, k) then
      user_pointer = true
    end
  end
  -- Runs after occupy_input, so the hooks table is already
  -- seeded, so a click hook the project set in top-level code
  -- is visible here.
  local hooks = CC:get_project_env().compy.input.hooks
  for _, k in ipairs(_derived) do
    if hooks[k] then user_pointer = true end
  end
end

--- @param userlove table
local function hook_update(userlove)
  local up = userlove.update
  if up and up ~= Controller._defaults.update then
    user_update = true
    Controller._userhandlers.update = up
  end
end

--- A program's input field, which the IDE draws over the
--- program's picture or the console, in the IDE's own graphics
--- state (view/ownState.lua)
--- @param CC ConsoleController
--- @param V UserInputView
local function draw_field(CC, V)
  own(CC.cfg.view.font, V.draw, V)
end

--- A program's love.draw draws on its canvas, which the IDE's
--- own draw shows by the screen's mode (draw_program); the
--- IDE's draw stays love.draw
--- @param userlove table
local function hook_draw(userlove)
  local udr = userlove.draw
  if udr and udr ~= View.main_draw then
    program_draw = udr
    user_draw = true
  end
end

--- The program's frame, on its canvas: cleared first to the
--- ground the program chose (CanvasModel:get_background, which
--- a choice in love.draw reaches though the frame's state is
--- given back after it), as love.run clears the screen
--- before love.draw, the transform at its origin, and drawn in
--- the program's own graphics state, which is given back after
--- it: use_canvas pops the IDE's push and whatever the frame
--- pushed and did not pop, a stop in it included. A stop or a
--- run the program's draw asks for is made once the frame is
--- done (util.program_end). The canvas keeps the frame for a
--- mode that shows it, and through a pause.
--- @param CC ConsoleController
local function draw_program(CC)
  local udr = program_draw
  if not udr then return end
  End.ide_pushes = End.ide_pushes + 1
  local ok, err = pcall(CC.use_canvas, CC, function()
    gfx.push('all')
    gfx.origin()
    --- the canvas holds premultiplied colour (round c3)
    local r, g, b, a = unpack(CC.model.output:get_background())
    gfx.clear(r * a, g * a, b * a, a)
    wrap(udr, CC)
  end)
  End.ide_pushes = End.ide_pushes - 1
  if not ok then error(err, 0) end
end

local click_delay = 0.4
local drift_tolerance = 2.5
local click_timer = 0
local click_pos
local press_pos
local press_dragged = false
local click_generation = 0

local function no_drift(a, b)
  return a and b
    and math.abs(a.x - b.x) < drift_tolerance
    and math.abs(a.y - b.y) < drift_tolerance
end

local function reset_click_state()
  click_generation = click_generation + 1
  click_timer, click_pos, press_pos = 0, nil, nil
  press_dragged = false
end

local function emit_pending_click()
  local pos = click_pos
  click_timer, click_pos = 0, nil
  if pos then love.handlers.singleclick(pos.x, pos.y) end
end

local function track_click_motion(x, y)
  local pos = { x = x, y = y }
  if press_pos and not no_drift(press_pos, pos) then
    press_dragged = true
  end
  if click_pos and not no_drift(click_pos, pos) then
    emit_pending_click()
  end
end

local function finish_click(x, y)
  local pos = { x = x, y = y }
  local valid = press_pos and not press_dragged
    and no_drift(press_pos, pos)
  press_pos = nil
  if not valid then return end
  if click_pos and click_timer > 0 and no_drift(click_pos, pos) then
    click_timer, click_pos = 0, nil
    love.handlers.doubleclick(x, y)
  else
    -- An unrelated second click leaves the first one valid.
    -- Finish it before starting the next pairing window.
    local generation = click_generation
    if click_pos then emit_pending_click() end
    if generation ~= click_generation then return end
    click_pos, click_timer = pos, click_delay
  end
end

-- `userlove` = the project's sandboxed `love` table
-- (also used in occupy_* and hook_* above);
--- @param userlove table
--- @param CC ConsoleController
--- @param resume boolean? --- continue(), see occupy_input
local set_handlers = function(userlove, CC, resume)
  reset_click_state()
  occupy_input(userlove, CC, resume)
  mark_pointer_liveness(userlove, CC)
  hook_update(userlove)
  hook_draw(userlove)
  deliver_owed()
end

-- Teardown clears every bindable channel: else a stopped
-- project's pointer hook survives and blocks the NEXT project's
-- seeding (seed_hooks fills only a nil slot).
-- D-ROUTE-LIFETIME's teardown invariant covers all of them.
local HOOK_EVENTS = _bindable

--- @param t table
local function wipe_table(t)
  for k in pairs(t) do rawset(t, k, nil) end
end

--- Teardown of the project's compy.input registrations
--- (doc/development/decisions/input.md, D-ROUTE-LIFETIME):
--- clears the project's shortcuts and hooks. The callbacks
--- table lives on the widget, which the stop destroys outright,
--- so there is nothing to clear there. Reaches through the
--- frozen container's sub-tables — the container itself refuses
--- direct writes (D-FROZEN-SHELL).
--- @param CC ConsoleController
local function reset_compy_input(CC)
  local input = CC:get_project_env().compy.input
  -- Driven by the channel lists, not by iterating the surface:
  -- `shortcuts` and `hooks` are metatable proxies over private
  -- state, so `pairs` on them yields nothing. Every channel
  -- that can hold something is named in a list, and the list is
  -- what teardown walks.
  for _, ev in ipairs(_bindable) do
    wipe_table(input.shortcuts[ev])
  end
  for _, ev in ipairs(HOOK_EVENTS) do input.hooks[ev] = nil end
end

-- Shared l/r modifier-fold table (see util/key.lua
-- mod_triples): rows of { left-key, right-key, generic-name }
-- in precedence order.
local COMBO_MODS = Key.mod_triples


-- The device question behind each modifier row. Key exports one
-- helper per generic name and each folds its own l/r pair, so a
-- row is answered by one call rather than two lookups.
local MOD_HELD = {
  ctrl  = Key.ctrl,
  alt   = Key.alt,
  shift = Key.shift,
}

--- Serialise a key event into a canonical combo string
--- ("ctrl+s", "alt+shift+f4"). Held modifiers are prepended in
--- COMBO_MODS precedence, l/r folded to generic names, and come
--- from the keyboard itself
--- (doc/development/decisions/input.md, D-ASK-THE-DEVICE). No
--- buffer table: three concatenations, not an allocation per
--- call, and nothing here to make reentrancy-unsafe.
---
--- The trigger is lower-cased because registration is:
--- D-COMBO-TABLES canonicalises an assigned combo whole, so
--- 'Shift+I' is stored as 'shift+i' and a dispatch that kept
--- the typed case could never reach it. Only textinput
--- delivers a cased trigger — keypressed tokens are LÖVE key
--- constants.
--- @param k string            triggering key (raw LÖVE name)
--- @return string             canonical combo string
local function combo_string(k)
  return Key.combo(k)
end

--- Is any modifier held? The cheap pre-check the triggerless
--- (pointer) shortcut lookup runs before building a combo
--- string, so an unmodified motion event allocates nothing.
--- @return boolean
local function any_mod()
  for _, m in ipairs(COMBO_MODS) do
    if MOD_HELD[m[3]]() then
      return true
    end
  end
  return false
end

-- FPS-corner overlay cycle (love.PROFILE.fpsc), in display
-- order. Absent from the table = left alone, not wrapped to
-- 'off': matches the if-elseif chain this replaces, which did
-- nothing on an unlisted value.
local FPSC_CYCLE = {
  off   = 'T_L_B',
  T_L_B = 'T_R_B',
  T_R_B = 'T_L',
  T_L   = 'T_R',
  T_R   = 'off',
}

--- @class Controller
--- @field _defaults Handlers
--- @field _userhandler Handlers
--- public interface
--- @field set_love_draw function
--- @field setup_callback_handlers function
--- @field set_default_handlers function
--- @field save_user_handlers function
--- @field clear_user_handlers function
--- @field restore_user_handlers function
--- @field user_is_blocking function
-- Every console channel except keypressed forwards its
-- arguments to the console controller and does nothing else.
-- Nine copies of the same three lines were nine chances for
-- one to drift, and
-- their per-event @param blocks documented LÖVE's signatures
-- rather than anything this code decides.
--- @param event string
--- @return function
local function console_channel(event)
  return function(CC)
    local function handler(...)
      return CC[event](CC, ...)
    end
    Controller._defaults[event] = handler
    love[event] = handler
  end
end

-- The derived clicks get no console installer: the console does
-- not use them, so releasing them means emptying the slot.
-- The keyboard channels the console installs generically:
-- keypressed is excluded, it has debug hotkeys of its own.
local _keyboard_rest = { 'keyreleased', 'textinput' }

local _console_channels = { }
for _, k in ipairs(_keyboard_rest) do
  table.insert(_console_channels, k)
end
for _, k in ipairs(_pointer) do
  table.insert(_console_channels, k)
end

Controller = {
  --- @private
  -- Console defaults, per channel. The derived clicks have
  -- none: nothing occupies them outside a project run, so
  -- anything a project's sandboxed love table holds there is
  -- the project's own and seeds a hook (project_handler).
  _defaults = { },
  --- @private
  _userhandlers = {},

  combo_string = combo_string,
  any_mod = any_mod,

  ----------------
  --  keyboard  --
  ----------------
  --- @private
  --- @param CC ConsoleController
  set_love_keypressed = function(CC)
    local function keypressed(k, sc, isr)
      -- TODO(debt): these debug-hotkey if-blocks predate
      -- combos; migrate onto the combo-table mechanism
      -- (doc/development/decisions/input.md, D-COMBO-TABLES).
      -- See doc/development/technical_debt/input.md "Console
      -- debug hotkeys are ad-hoc".
      if Key.ctrl() and Key.shift() then
        if love.DEBUG then
          if k == "1" then
            table.toggle(love.debug, 'show_terminal')
            table.toggle(love.debug, 'show_buffer')
          end
          if k == "2" then
            table.toggle(love.debug, 'show_snapshot')
          end
          if k == "3" then
            table.toggle(love.debug, 'show_canvas')
          end
          if k == "5" then
            table.toggle(love.debug, 'show_input')
          end
        end
      end
      if Key.ctrl() and Key.alt() then
        if love.DEBUG then
          if k == "d" then
            Log.debug(Debug.termdebug(CC.model.output.terminal))
          end
        end
      end
      -- Widget visibility is state on the widget, never a
      -- routing condition (doc/development/decisions/input.md,
      -- D-ROUTE-OWNS): a project's widget is reached inside the
      -- PROJECT route's chain, and the console never holds the
      -- slot while one is up.
      CC:keypressed(k, sc, isr)
    end
    Controller._defaults.keypressed = keypressed
    love.keypressed = keypressed
  end,

  --------------
  --  update  --
  --------------
  --- @private
  --- @param CC ConsoleController
  set_love_update = function(CC)
    local update_body
    --- what the program's update, its serial handlers or a timer
    --- ask for is made once the frame's update has returned
    --- (util.program_end)
    local function update(dt)
      return End.held(update_body, dt)
    end
    update_body = function(dt)
      if love.PROFILE then
        Prof.update()
      end
      if Serial and SerialPort then
        --- a program's serial handlers are program code: on its
        --- canvas, through the one helper (round c3)
        local faults = CC:use_canvas(function()
          return SerialPort:update(dt)
        end)
        for _, f in ipairs(faults or { }) do
          print('serial fault [' .. f.env .. ']: ' ..
            tostring(f.err))
        end
      end
      if click_pos then
        click_timer = click_timer - dt
        if click_timer <= 0 then emit_pending_click() end
      end

      CC:pass_time(dt)

      local uup = Controller._userhandlers.update
      if user_update and uup
      then
        CC:use_canvas(function()
          wrap(uup, CC, dt)
        end)
      end
      --- the paused frame is on the program's canvas already
      if love.state.app_state == 'snapshot' then
        CC:suspend()
      end

      if love.harmony then
        love.harmony.timer_update(dt)
      end
    end

    if not Controller._defaults.update then
      Controller._defaults.update = update
    end
    love.update = update
  end,

  ---------------
  --    draw   --
  ---------------
  --- @private
  --- @param CC ConsoleController
  --- @param CV ConsoleView
  set_love_draw = function(CC, CV)
    -- The widget is painted on top of the console frame,
    -- mirroring what set_love_update's wrapper does on top of a
    -- PROJECT frame. Both paths are needed: the wrapper
    -- installs only when a project replaces love.draw, so a
    -- project that hooks no draw at all (an input-only one —
    -- technical_debt/input.md, ruling (a)) would otherwise show
    -- a widget that takes keystrokes and paints nothing.
    -- get_user_input() carries the inspect gate, so the
    -- suspended project's widget stays unhonoured
    -- (doc/development/internals/user_input.md,
    -- "inspect mode").
    --- a request a field's highlighter made as the field drew
    --- is made once the draw is done (util.program_end)
    local function draw()
      End.held(function()
        draw_program(CC)
        View.draw(CC, CV)
        local ui = get_user_input()
        if ui then draw_field(CC, ui.V) end
        View.drawFPS()
      end)
    end
    love.draw = draw

    View.main_draw = love.draw
    View.end_draw = function()
      local w, h = gfx.getDimensions()
      gfx.setColor(Color[Color.white])
      gfx.setFont(CC.cfg.view.font)
      gfx.clear()
      gfx.printf(messages.exit_anykey, 0, h / 3, w, "center")
    end
  end,


  --- Quit
  --- @private
  --- @param CC ConsoleController
  set_love_quit = function(CC)
    local cfg = CC.cfg

    --- The IDE leaves, and its window goes to the back once
    --- the micro:bit is let go (go_back below): the run should
    --- end as soon after as it can, since Android pauses a
    --- window at the back. From here an error cannot be shown
    --- to anyone.
    local function go_home()
      Controller.leaving = true
      Controller.home = true
    end
    Controller.leaving = false
    Controller.home = false

    --- The window goes to the back, once
    local function go_back()
      if not Controller.home then return end
      Controller.home = false
      local ok, err = pcall(Application.return_home_before_exit)
      if not ok then
        local out = rawget(_G, 'orig_print') or print
        pcall(out, 'The IDE could not go to the back as it quit: '
          .. tostring(err))
      end
    end

    local function quit()
      --- flush pending writes before the process can exit
      --- (spec 2.6): a graceful quit loses nothing. One
      --- syscall; force-stop is covered by per-accept fsync
      FS.sync()
      if Application.consume_application_exit_request() then
        go_home()
        return false
      end
      if love.state.app_state == 'shutdown' then
        go_home()
        return false
      end

      if cfg.mode == 'play' then
        CC:quit_project()
        love.state.app_state = 'shutdown'
        love.state.user_input = nil

        love.draw = View.end_draw
        return true
      end
      -- A running project stops to the console. So does the
      -- corner case: a paper-and-pen style project that is
      -- still interactive (input widget shown or pointer
      -- handlers installed —
      -- doc/development/technical_debt/input.md, "Input-only /
      -- pointer-only projects stay live", RESOLVED, ruling a).
      -- An idle console in ready falls through: the app quits.
      if love.state.app_state == 'running'
          or (love.state.app_state == 'ready'
              and Controller.user_is_interactive()) then
        CC:stop_project_run()
        return true
      end
      go_home()
    end
    --- An error that ends the IDE lets the micro:bit go too,
    --- before the error screen, which can leave without
    --- love.quit: a flash under way closes its stream, within
    --- a second, and the connection closes. Guarded, so a
    --- fault here cannot keep the error from being shown.
    local explore = love.errhand
    if explore and explore ~= Controller.errhand then
      Controller.errhand = function(msg)
        -- an error on the way out would open an error screen
        -- on a window gone to the back, whose loop waits for a
        -- key that never comes, and keeps this run going while
        -- Android starts the IDE again: the error goes to the
        -- log, and the run ends
        if Controller.leaving then
          local out = rawget(_G, 'orig_print') or print
          pcall(out, 'The IDE was leaving when this error came: '
            .. debug.traceback(tostring(msg), 2))
          if Serial and SerialPort then
            pcall(SerialPort.stop, SerialPort)
          end
          go_back()
          return function() return 1 end
        end
        if Serial and SerialPort then
          local ok, cut = pcall(SerialPort.stop, SerialPort)
          -- a flash cut off is said on the error screen, the
          -- one thing the person sees now
          if ok and cut then
            msg = tostring(msg) .. '\n\n' .. cut
          end
        end
        local loop = explore(msg)
        if type(loop) ~= 'function' then return loop end
        -- the error screen, once left, ends the run: the window
        -- goes to the back, as for a quit, so Android starts
        -- the IDE again
        return function(...)
          local r = loop(...)
          if r ~= nil then
            pcall(Application.return_home_before_exit)
          end
          return r
        end
      end
      love.errhand = Controller.errhand
    end
    --- An IDE that ends lets the micro:bit go: its USB
    --- connection closes, and the drive stays without a
    --- driver until the board is plugged in again, so the
    --- IDE that starts next, often in the same process,
    --- takes it without a tussle with Android.
    ---
    --- While a file goes to the board, a quit the person
    --- asked for waits, with words that say so. A quit
    --- Android asks for (it is closing the IDE, and waits for
    --- it) is never refused, and on Android the IDE always
    --- leaves then, a project running or not: the flash stops,
    --- its stream closed within a second, and says so. On a
    --- computer, a quit that only stops a project leaves the
    --- IDE, and its flash, going.
    --- A quit pushed from inside the app, by the IDE or a
    --- project, is one the person asked for: it goes out
    --- tagged, its exit status kept in the tag, and the IDE's
    --- love.run (Application.run) hands the tag to love.quit.
    --- Only Android's own quit comes without one.
    Application.tag_quits(love.event)
    --- @param value any the quit event's value
    love.quit = function(value)
      local asked = Application.untag(value)
      local port = Serial and SerialPort
      if port and port:isFlashing() then
        if asked then
          -- the quit is not going ahead: Ctrl+Esc's request
          -- must not carry over to a later quit
          Application.consume_application_exit_request()
          print('The Compy stays open while a file goes to the'
            .. ' micro:bit. Once it says how it went, you can'
            .. ' quit.')
          return true
        end
      end
      -- whether the IDE stays is decided first: a flash goes on
      -- in an IDE that stays, and ends, with words, in one that
      -- does not
      local androids = not asked and love.system
          and love.system.getOS() == 'Android'
      local qok, stay = xpcall(quit, debug.traceback)
      if not qok then
        local out = rawget(_G, 'orig_print') or print
        pcall(out, 'The quit could not decide whether the IDE'
          .. ' stays: ' .. tostring(stay))
        -- Android's own quit must end the IDE; any other shows
        -- the error, as it always did
        if not androids then error(stay, 0) end
        stay = false
      end
      -- Android waits for its own quit on its UI thread, and
      -- would wait for good on an IDE that stays: then the IDE
      -- leaves, whatever it would have stayed for, its window
      -- sent to the back as any quit's
      if stay and androids then
        stay = false
      end
      if not stay and androids then go_home() end
      if not stay then
        Controller.leaving = true
        -- nothing here may keep the run going: a fault is
        -- logged, and the quit goes ahead
        local ok, err = true, nil
        local timer = love.timer
        local t0 = timer and timer.getTime()
        if port then
          ok, err = pcall(function()
            if port:isFlashing() then port:abandon() end
            port:stop()
          end)
        end
        local out = rawget(_G, 'orig_print') or print
        if not ok then
          pcall(out, 'The micro:bit could not be let go as the'
            .. ' IDE quit: ' .. tostring(err))
        end
        pcall(out, 'Quit accepted: this run of the IDE ends'
          .. (t0 and string.format(', the board let go in %.0f ms',
            1000 * (timer.getTime() - t0)) or ''))
        go_back()
      end
      return stay
    end
  end,

  --- Background durability net (spec 2.6): a child
  --- leaving the app flushes pending writes. One syscall
  --- on focus loss; does not cover a force-stop mid-edit
  --- (per-accept fsync does).
  --- @private
  --- @param CC ConsoleController
  set_love_focus = function(CC)
    local function focus(f)
      if not f then FS.sync() end
    end
    love.focus = focus
  end,

  --- Companion to focus: Android reports a backgrounded
  --- window as not visible; flush there too.
  --- @private
  --- @param CC ConsoleController
  set_love_visible = function(CC)
    local function visible(v)
      if not v then FS.sync() end
    end
    love.visible = visible
  end,

  ----------------
  ---  public  ---
  ----------------
  --- Defensive cleanup after a project raises at top level:
  --- deactivate the route, hand EVERY channel the route could
  --- have taken back to the console, empty the derived click
  --- slots. The caller pairs it with clear_user_handlers for
  --- the rest.
  --- NOT a lifecycle step, despite the name: the
  --- 'running' -> 'ready' transition releases nothing,
  --- and every channel shares ONE lifetime that ends at the
  --- project's stop (doc/development/decisions/input.md,
  --- D-ROUTE-LIFETIME as amended — the keyboard-only release
  --- and the pointer exemption it forced are both gone).
  ---
  --- It returns the same set occupy_input takes, which is the
  --- property that matters and the one it lacked: it used to
  --- reinstall keypressed plus _keyboard_rest and leave the
  --- seven pointer channels bound to the dispatcher it had
  --- just deactivated. Reachable through a successful run
  --- followed by a failed one — the failing run alone occupies
  --- nothing, since set_user_handlers is on run_user_code's ok
  --- branch (doc/development/internals/user_input.md,
  --- "Dispatch chain").
  --- @param CC ConsoleController
  release_keyboard_route = function(CC)
    route_owner = 'console'
    reset_click_state()
    Controller.project_input:deactivate()
    Controller.set_love_keypressed(CC)
    for _, k in ipairs(_console_channels) do
      Controller['set_love_' .. k](CC)
    end
    -- The derived click slots have no console occupant to
    -- restore, the console not using them, so releasing means
    -- emptying them. Left set they would keep pointing at a
    -- deactivated route.
    for _, k in ipairs(_derived) do
      love[k] = nil
    end
  end,

  --- @param CC ConsoleController
  --- @param CV ConsoleView
  set_default_handlers = function(CC, CV)
    -- When the project route lets go of the keyboard/text
    -- callbacks they always return to the console: it is the
    -- default/restore route (doc/development/decisions/input.md
    -- #1), so the release must precede reinstalling the console
    -- below. The only console/PIC tie is this restore ordering
    -- + inspect suppression (doc/development/decisions/input.md
    -- #11/#12) — not a special-case beyond that.
    route_owner = 'console'
    reset_click_state()
    Controller.project_input:deactivate()

    -- SKIPPED textedited - IME support, TODO?
    Controller.set_love_keypressed(CC)
    for _, k in ipairs(_console_channels) do
      Controller['set_love_' .. k](CC)
    end

    --- SKIPPED joystick and gamepad support

    --- intented to run as kiosk app; focus/visible are
    --- wired only to flush pending writes on background
    Controller.set_love_focus(CC)
    Controller.set_love_visible(CC)
    --- SKIPPED mousefocus
    --- SKIPPED resize
    --- SKIPPED filedropped
    --- SKIPPED directorydropped

    --- target device has laptop form factor, hence disabled
    --- SKIPPED displayrotated

    --- SKIPPED threaderror
    --- SKIPPED lowmemory

    -- reset the user-handler presence flags, then (re)install
    -- the console's update/draw/quit as the love defaults.
    user_update = false
    Controller.set_love_update(CC)
    user_draw = false
    program_draw = nil
    user_pointer = false
    for _, k in ipairs(_derived) do
      love[k] = nil
    end
    Controller.set_love_draw(CC, CV)
    Controller._defaults.draw = View.main_draw
    Controller.set_love_quit(CC)
  end,

  --- @param CC ConsoleController
  setup_callback_handlers = function(CC)
    local cfg = CC.cfg
    local playback = cfg.mode == 'play'

    --- @diagnostic disable-next-line: undefined-field
    local handlers = love.handlers

    -- Reservations below run unconditionally in dev mode; in
    -- playback (cfg.mode == 'play') only restart/profile stay
    -- live (doc/development/decisions/input.md, D-ROUTE-OWNS) —
    -- each project/console-management one checks it and no-ops.
    --- An exit pressed during an edit is refused with the
    --- editor's notice (EditorController:refuse_to_leave)
    --- @return boolean refused
    local function refused()
      return love.state.app_state == 'editor'
          and CC.editor:refuse_to_leave()
    end

    local function reserved_quickswitch()
      if playback then return end
      local st = love.state.app_state
      if st == 'running' or st == 'inspect'
          or st == 'ready' then
        CC:stop_project_run()
        --- back to the files the run came from, as they were
        --- (IS1.4), or the main file when there are none
        if CC.editor and CC.editor:get_active_buffer() then
          CC:show_editor()
        else
          CC:edit()
        end
      elseif st == 'editor' then
        if refused() then return end
        CC:hide_editor()
        --- "main.lua only for now" (the maintainer's ruling of
        --- November 16, 2026)
        CC:run_project()
      end
    end

    local function reserved_suspend()
      if playback then return end
      CC:suspend_run(messages.user_break)
    end

    -- Ctrl+Q returns to the console, and the project stays
    -- open. From the file editor it leaves the editor with
    -- every file on its stack. Otherwise it stops the program:
    -- one that runs, one that is paused, and one that idles
    -- behind the console with its picture or its handlers
    -- still there (run_live). In the console with no program
    -- it does nothing. No key closes the project
    -- (doc/development/decisions/input.md, D-RESERVE-TABLE,
    -- the 2026-11-14 note).
    --- A program is live for Ctrl+Q and Ctrl+R alike: it runs,
    --- it is paused, or it idles behind the console with its
    --- picture or its handlers still there (run_live)
    --- @return boolean
    local function program_live()
      local st = love.state.app_state
      return st == 'running' or st == 'inspect'
          or (st == 'ready' and CC.run_live == true)
    end

    local function reserved_stop()
      if playback then return end
      if love.state.app_state == 'editor' then
        if refused() then return end
        CC:finish_edit()
      elseif program_live() then
        CC:stop_project_run()
      end
    end

    -- Ctrl+R restarts a live program from the entry point it
    -- runs from, and does nothing otherwise, in the console and
    -- in the editor ("Ctrl+R should do nothing at the console.
    -- End of story.", the maintainer's ruling of November 16,
    -- 2026). Playback restarts as before.
    local function reserved_restart()
      if playback or program_live() then CC:restart() end
    end

    local function reserved_profile_start()
      if not love.PROFILE then return end
      Prof.start_oneshot()
    end

    local function reserved_profile_stop()
      if not love.PROFILE then return end
      Prof.stop_profiler()
    end

    local function reserved_overlay()
      if not love.PROFILE then return end
      local nxt = FPSC_CYCLE[love.PROFILE.fpsc]
      if nxt then love.PROFILE.fpsc = nxt end
    end

    --- the screen's modes, where a console runs (a bare
    --- driver of the gate has none)
    local screen = CC.model and CC.model.screen

    --- F12: the screen's next mode in the console, idle,
    --- running or paused; the editor shows no mode, and
    --- playback no console
    local function reserved_screen_mode()
      if playback or not screen then return end
      if love.state.app_state == 'editor' then return end
      screen:step()
    end

    --- The full picture shows, and no program that can act
    --- runs: the screen is a picture to look at, with no field
    --- and no status line. Any key or button goes back from it
    --- to the text and goes nowhere else (the maintainer: "if
    --- any key gets us back into console, this is good
    --- enough"); text, the wheel and movement do
    --- nothing, as no field shows to take them. A program that
    --- can act keeps all its input, and F12 is its way back.
    --- @return boolean
    local function picture_only()
      return screen ~= nil and screen:get() == 'picture'
          and love.state.app_state ~= 'editor'
          and not Controller.program_owns_input()
    end

    -- The gate's own reservations
    -- (doc/development/decisions/input.md, D-RESERVE-TABLE): a
    -- SECOND, PRIVILEGED table, structurally separate from a
    -- project's own compy.input.shortcuts — consulted before
    -- any route exists, and never overridable by one.
    -- A reservation consumes its key for its whole press: the
    -- route sees neither its press, its repeats nor its release
    -- (D-RESERVE-TABLE's note of 2026-11-16, which reverses its
    -- "a reservation never consumes").
    -- The chords and what the key cards say of them live in
    -- model/input/reservedKeys.lua; Ctrl+Escape lives on
    -- release, matching the key it quits on
    -- (doc/development/decisions/input.md, D-RESERVE-TABLE).
    local ACTS = {
      quickswitch = reserved_quickswitch,
      suspend = reserved_suspend,
      stop = reserved_stop,
      restart = reserved_restart,
      profile_start = reserved_profile_start,
      profile_stop = reserved_profile_stop,
      overlay = reserved_overlay,
      screen_mode = reserved_screen_mode,
      exit = Application.request_application_exit,
    }
    local RESERVED = { keypressed = { }, keyreleased = { } }
    local REPEATS = { }
    -- The key card's gate (IS3.16): a key's press is passed on
    -- only while no card shows, and its repeats and release
    -- follow its press to its receiver. `delivered` holds each
    -- key from its press passed on to its release, with its
    -- receiver: the route in force at the press (route_owner),
    -- or the IDE for a reserved chord, whose key is the IDE's
    -- for the whole press (the maintainer's ruling of November
    -- 16, 2026: D-RESERVE-TABLE's reservations consume). A
    -- repeat or release whose receiver is gone goes nowhere; a
    -- paused program's release waits for continue(). Text
    -- carries no key, and the routing reads the modifiers held
    -- now: a key that comes up from Ctrl+R's R, Ctrl let go and
    -- R held on, types its repeats into the restarted program,
    -- its key events still the IDE's.
    -- Text carries no key and is held back only while the card
    -- shows: a key pressed under the card and still held when it
    -- closes types its repeats from then on, its key events
    -- still dropped. `owed` holds a release reservation decided
    -- at its key's press (Ctrl+Escape: the exit is owed once
    -- Escape goes down with Ctrl held, and comes on Escape's
    -- release whatever is held by then, the card up or not).
    local delivered, owed = { }, { }
    --- the keys that went back from the full picture, from
    --- their press to their release: the text they type goes
    --- nowhere either
    local went_back = { }
    for _, r in ipairs(require('model.input.reservedKeys')) do
      -- the profiling keys only where conf.lua set love.PROFILE,
      -- which it does before love.load builds this gate
      if love.PROFILE or not r.profiling then
        local event = r.release and 'keyreleased' or 'keypressed'
        RESERVED[event][r.chord] = assert(ACTS[r.name], r.name)
        REPEATS[r.chord] = r.repeats == true
      end
    end

    handlers.keypressed = function(k, sc, isr)
      --- a key press shows the text cursor (H-NFR4.4)
      Blink.restart()
      -- While a key card shows, in the editor or the console,
      -- every other key does nothing, the reserved chords
      -- included, and reaches no program behind the console
      -- either. A repeat goes on only for a key whose press did,
      -- and not under the card. Ctrl+Escape acts on its release,
      -- which is never held back: the way out that always works.
      if not isr then
        owed[k] = RESERVED.keyreleased[combo_string(k)]
      end
      -- Not a reservation: this fires on ANY key in playback
      -- while shutting down, not on one combo, so it cannot be
      -- a table entry.
      if playback and love.state.app_state == 'shutdown' then
        love.event.quit()
      end
      local card = CC:card_shows()
      local to = delivered[k]
      local chord = combo_string(k)
      local reservation = RESERVED.keypressed[chord]
      if isr then
        if card or not to then return end
        -- a held reservation acts on its repeats only where it
        -- reaches a natural stop (reservedKeys.lua): a held
        -- Ctrl+T does not flip between the run and the editor
        if type(to) == 'table' then
          if to.again then to.act() end
          return
        end
        --- a key whose press fell through to the console repeats
        --- there, whoever has the keys now
        if to == 'console' and route_owner ~= 'console' then
          --- not while the program owns the input: the console's
          --- field is hidden (p1)
          if Controller.program_owns_input() then return end
          local console = Controller._defaults.keypressed
          if console then return console(k, sc, isr) end
          return
        end
        if to ~= route_owner then return end
      elseif card and k ~= KeyCard.KEY then
        delivered[k] = nil
        return
      elseif picture_only() and not Key.is_lone(k)
          and reservation ~= reserved_screen_mode then
        -- back from the full picture: the key is the IDE's for
        -- its whole press, and a reserved chord acts as well
        -- (F12 is the cycle, whose next mode is text)
        screen:back()
        went_back[k] = true
        delivered[k] = { act = reservation, again = REPEATS[chord] }
        if not reservation then return end
        if CC.editor then CC.editor:key_begins() end
        reservation()
        if CC.editor then CC.editor:gate_key_done() end
        return
      elseif reservation or owed[k] then
        -- the IDE's for the whole press, Ctrl+Escape's Escape too
        delivered[k] = { act = reservation, again = REPEATS[chord] }
        if not reservation then return end
        if CC.editor then CC.editor:key_begins() end
        reservation()
        if CC.editor then CC.editor:gate_key_done() end
        return
      else
        delivered[k] = route_owner
      end
      if CC.editor then CC.editor:key_begins() end

      -- This is `love.handlers.keypressed`, the raw
      -- event-pump entry; `love.keypressed` below holds the
      -- active route's handler (console via
      -- set_love_keypressed, project via occupy_input).
      -- Forwarding = invoke whichever route is installed.
      -- Widgets are reached inside the route, never gated
      -- here. (Mirrors stock LÖVE's love.handlers[name] ->
      -- love[name].) See doc/development/decisions/input.md #1
      -- "route-centric routing" + #11.
      local handled
      if love.keypressed then
        handled = love.keypressed(k, sc, isr)
      end
      --- a press during which the input went back to the console
      --- (the program could no longer act) reached the console:
      --- its repeats and release go there. A repeat changes no
      --- receiver
      if not isr and to_program(delivered[k])
          and route_owner == 'console' then
        delivered[k] = 'console'
      end
      -- a refusal at the gate holds back this key press alone
      -- (EditorController:refuse_to_leave), never a later one
      if CC.editor then CC.editor:gate_key_done() end
      return handled
    end

    -- A modifier chord's own glyph is no typed text, and on
    -- the device it arrives as text all the same, before or
    -- after the key press (Key.chord_text). It is stopped
    -- here, at the one entry every text event has, so that it
    -- reaches no text field: not the console's, not the file
    -- editor's, not a project's input widget. A project's
    -- shortcuts and hook sit above its widget and are promised
    -- every text event, so the project route still offers it
    -- to them, and it goes no further: no fall-through to the
    -- console either. The glyph of a reserved chord (Ctrl+R's
    -- r) reaches no one: the chord is the gate's, before or
    -- after its key press.
    local chord_text = with_canvas_and_errors(CC, function(t)
      return Controller.project_input:chord_text(t)
    end)

    handlers.textinput = function(t)
      Blink.restart()
      if not love.textinput then return end
      if CC:card_shows() then return end
      if next(went_back) or picture_only() then return end
      if Key.chord_text(t) then
        if RESERVED.keypressed[combo_string(t)] then return end
        local console = Controller._defaults.textinput
        if love.textinput == console then return end
        return chord_text(t)
      end
      return love.textinput(t)
    end

    handlers.keyreleased = function(k, sc)
      -- here, whichever route has the keys: the help key's
      -- release ends its card wherever its press went
      CC:key_released(k)
      went_back[k] = nil
      local reservation = owed[k]
      owed[k] = nil
      if reservation then reservation() end
      -- a release goes on exactly for a press that did, to its
      -- receiver: the route in force, the console behind a
      -- program, or a paused program at its continue()
      local to = delivered[k]
      delivered[k] = nil
      if not to or type(to) == 'table' then return end
      if to == route_owner then
        if love.keyreleased then
          return love.keyreleased(k, sc)
        end
      elseif to == 'console' then
        local console = Controller._defaults.keyreleased
        if console then return console(k, sc) end
      else
        owed_releases[to] = owed_releases[to] or { }
        owed_releases[to][k] = sc or k
      end
    end

    --- @param x integer
    --- @param y integer
    --- @param btn integer
    --- @param touch boolean
    --- @param presses number
    -- While a key card shows, the mouse does nothing, as the
    -- keys do nothing (the maintainer's ruling of November
    -- 14, late): no press, release, move, wheel or derived
    -- click reaches the console, the editor or a program
    -- behind the console's card. A button's release goes
    -- where its press went: a press held back under the card
    -- holds back its release, after the card too, and a
    -- press that went through gets its release under the
    -- card, so that no route is left with half a click.
    -- Touches follow the same rule, paired by the touch's id.
    -- Each records its press's receiver, as the keys do: false
    -- for one the card held back, else the route in force; a
    -- release goes on only to that receiver, still in force
    -- (p2: a button the program got the press of, released while
    -- the console has the pointer, reaches neither).
    local press_to = { }
    local touch_to = { }

    --- whether a release recorded as `to` goes on now
    --- @param to any
    --- @return boolean
    local function release_goes(to)
      if to == false then return false end
      return to == nil or to == route_owner
    end

    -- The gateway entry: hand the event to whoever occupies
    -- the slot. Under a project run that is the project
    -- route's chain; otherwise the console's own handler.
    handlers.mousepressed = function(x, y, btn, touch, presses)
      Blink.restart()
      if CC:card_shows() then
        press_to[btn] = false
        return
      end
      --- a button goes back from the full picture, as a key
      --- does, and its release goes nowhere either
      if picture_only() then
        screen:back()
        press_to[btn] = false
        return
      end
      if btn == 1 then
        press_pos, press_dragged = { x = x, y = y }, false
      end
      local r
      if love.mousepressed then
        r = love.mousepressed(x, y, btn, touch, presses)
      end
      --- the receiver after the press: the route may have gone
      --- back to the console during it (p3)
      press_to[btn] = route_owner
      return r
    end

    --- @param x integer
    --- @param y integer
    --- @param btn integer
    --- @param touch boolean
    --- @param presses number
    handlers.mousereleased = function(x, y, btn, touch, presses)
      local to = press_to[btn]
      press_to[btn] = nil
      if not release_goes(to) then return end
      local result
      if love.mousereleased then
        result = love.mousereleased(x, y, btn, touch, presses)
      end
      if btn == 1 then finish_click(x, y) end
      return result
    end

    --- @param x number
    --- @param y number
    --- @param dx number
    --- @param dy number
    --- @param touch boolean
    handlers.mousemoved = function(x, y, dx, dy, touch)
      track_click_motion(x, y)
      if CC:card_shows() or picture_only() then return end
      if love.mousemoved then
        return love.mousemoved(x, y, dx, dy, touch)
      end
    end

    -- Wheel had no entry of compy's own until 2026-08-03. It
    -- still reached a project, but by accident: this function
    -- writes INTO love.handlers rather than replacing it, so
    -- LÖVE's stock wheelmoved survived and called
    -- love.wheelmoved. Declaring it makes the gateway
    -- self-contained instead of depending on that, and puts
    -- wheel on the same footing as every other pointer channel.
    --- @param x number
    --- @param y number
    handlers.wheelmoved = function(x, y)
      if CC:card_shows() or picture_only() then return end
      if love.wheelmoved then
        return love.wheelmoved(x, y)
      end
    end

    -- Derived click events, synthesised by the click timer in
    -- set_love_update. Same shape as every native entry above:
    -- hand it to whatever occupies the slot, and skip when
    -- nothing does. The console and editor do not use them, so
    -- on those routes the slot is simply empty.
    for _, name in ipairs(_derived) do
      handlers[name] = function(x, y)
        if CC:card_shows() or picture_only() then return end
        if love[name] then return love[name](x, y) end
      end
    end

    --- @param id userdata
    --- @param x number
    --- @param y number
    --- @param dx number?
    --- @param dy number?
    --- @param pressure number?
    handlers.touchpressed = function(id, x, y, dx, dy, pressure)
      if CC:card_shows() then
        touch_to[id] = false
        return
      end
      if picture_only() then
        screen:back()
        touch_to[id] = false
        return
      end
      local r
      if love.touchpressed then
        r = love.touchpressed(id, x, y, dx, dy, pressure)
      end
      touch_to[id] = route_owner
      return r
    end

    --- @param id userdata
    --- @param x number
    --- @param y number
    --- @param dx number?
    --- @param dy number?
    --- @param pressure number?
    handlers.touchreleased = function(id, x, y, dx, dy, pressure)
      local to = touch_to[id]
      touch_to[id] = nil
      if not release_goes(to) then return end
      if love.touchreleased then
        return love.touchreleased(id, x, y, dx, dy, pressure)
      end
    end

    --- @param id userdata
    --- @param x number
    --- @param y number
    --- @param dx number?
    --- @param dy number?
    --- @param pressure number?
    handlers.touchmoved = function(id, x, y, dx, dy, pressure)
      --- a touch begun under the card moves nothing after it
      if not release_goes(touch_to[id]) or CC:card_shows()
          or picture_only() then
        return
      end
      if love.touchmoved then
        return love.touchmoved(id, x, y, dx, dy, pressure)
      end
    end


    --- @diagnostic disable-next-line: undefined-field
    table.protect(love.handlers)
  end,

  set_user_handlers = function(userlove, CC)
    program_count = program_count + 1
    set_handlers(userlove, CC)
  end,

  user_is_blocking = function()
    return (user_update or user_draw)
  end,

  --- A non-blocking project is still "live" while it has an
  --- active input widget or a pointer/click handler — it keeps
  --- the project route, and a quit (not Ctrl+Esc's, which
  --- exits the IDE) stops it back to the console.
  user_is_interactive = function()
    return (love.state.user_input ~= nil) or user_pointer
  end,

  --- A program's route holds the input and the program can
  --- still act (can_act): it owns all input, and the console's
  --- field is hidden (ConsoleView:draw). False at a pause, a
  --- stop, and once the program can act no more.
  --- @return boolean
  program_owns_input = function()
    if route_owner == 'console' then return false end
    return can_act(Controller.project_input.compy_input)
  end,

  --- @param userlove table
  save_user_handlers = function(userlove)
    --- @param key string
    local function save_if_differs(key)
      local orig = Controller._defaults[key]
      local new = userlove[key]
      if orig and new and orig ~= new then
        Controller._userhandlers[key] = new
      end
    end

    -- input hooks
    for _, a in pairs(_supported) do
      save_if_differs(a)
    end

    save_if_differs('draw')
  end,

  --- @param CC ConsoleController
  restore_user_handlers = function(CC)
    set_handlers(Controller._userhandlers, CC, true)
  end,

  --- @param CC ConsoleController?
  clear_user_handlers = function(CC)
    Controller._userhandlers = {}
    if not CC then return end
    -- Only the surface's own stores. The widget's outputs are
    -- not re-seeded here and no longer can be: the widget
    -- belongs to the run and is destroyed with it
    -- (doc/development/decisions/input.md, D-WIDGET-AT-BOOT as
    -- amended), so the next run meets a fresh one.
    reset_compy_input(CC)
  end,

  oneshot = function()
    if not love.PROFILE then return end
    Prof.start_oneshot()
  end,

  report = function()
    if not love.PROFILE then return end
    local report = Prof.report()
    if report then
      Log.debug(report)
    end
  end,
}

for _, k in ipairs(_console_channels) do
  Controller['set_love_' .. k] = console_channel(k)
end

Controller.project_input = ProjectInputController()
