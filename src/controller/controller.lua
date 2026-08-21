Prof = require("controller.profiler")
require("view.view")
require("controller.projectInputController")

require("util.string.string")
require("util.key")
require("util.lua")
local LANG = require("util.eval")
local FS = require("util.filesystem")
local Application = require("util.application")

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
--- @type boolean
-- set when a project installs any pointer/click handler.
-- Together with a shown input widget it marks a non-blocking
-- project (one that overrides no update/draw, e.g. a
-- pen-and-paper game) as still "live"
-- (doc/development/technical_debt/input.md, "Input-only /
-- pointer-only projects stay live in `project_open` (RESOLVED,
-- ruling a)"): keep the project route, Ctrl+Esc -> console.
local user_pointer

-- One lifetime, several names for subsets of it. Every channel
-- installs the same way, runs the same chain, and is released
-- at the same moment: the project's stop. The split that
-- existed here (keyboard released at running->project_open,
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
  CC:suspend_run(user_msg)
  print(user_msg)
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
local function wrap(f, CC, ...)
  local function on_error(msg)
    user_error_handler(CC, msg)
  end
  local args, n = { ... }, select('#', ...)
  return xpcall(function()
    return f(unpack(args, 1, n))
  end, on_error)
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
    return CC:use_canvas(function()
      local ok, res = wrap(fn, CC, unpack(args))
      if ok then return res end
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


--- An event the project's chain did not consume goes back to
--- the console, which is where it went before a project run
--- held every channel for its whole lifetime
--- (doc/development/internals/event_dispatch_layers.md,
--- "Layer 2 — `love.<event>`, the active route's handler").
--- Two guards, and both are the point rather than defence:
--- `user_draw` because a project painting over the console
--- would otherwise let the user type into a prompt they cannot
--- see, and the nil check because the two derived clicks have
--- no console default at all (`_defaults`, above).
--- `user_is_blocking()` cannot serve as the first guard: it
--- also answers true for a project that hooks only `update`,
--- which is exactly the class this serves.
--- @param event string
local function fall_through(event, ...)
  if user_draw then return end
  local console = Controller._defaults[event]
  if not console then return end
  return console(...)
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
-- with no project handlers: the walk decides, per event, and an
-- unconsumed one falls back to the console unless the project
-- owns the screen (fall_through, above). (`userlove` rename:
-- technical_debt.)
local function occupy_input(userlove, CC)
  local pic = Controller.project_input
  local compy = CC:get_project_env().compy
  pic:activate(project_handlers(userlove, CC), compy.input)
  -- with_canvas_and_errors here, not around each participant:
  -- route IS the boundary, so every tier of the walk runs with
  -- the project canvas bound and one error handler above it.
  -- Wrapped (not assigned) to bind `pic` as method receiver:
  -- `love.keypressed = pic.keypressed` would drop `self`.
  for _, k in ipairs(_bindable) do
    love[k] = with_canvas_and_errors(CC, function(...)
      -- LÖVE discards a handler's return, so the
      -- walk's verdict is spent here or not at all.
      if pic[k](pic, ...) then return end
      return fall_through(k, ...)
    end)
  end
end

--- `user_pointer` marks a non-blocking project as still
--- interactive, so it keeps the route in 'project_open'
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

--- @param userlove table
local function hook_draw(userlove)
  local udr = userlove.draw
  local mdr = View.main_draw
  if udr and udr ~= mdr then
    --- @diagnostic disable-next-line: duplicate-set-field
    local ndr = function()
      udr()
      View.drawFPS()
    end
    love.draw = ndr
    user_draw = true
  end
end

-- `userlove` = the project's sandboxed `love` table 
-- (also used in occupy_* and hook_* above); 
--- @param userlove table
--- @param CC ConsoleController
local set_handlers = function(userlove, CC)
  occupy_input(userlove, CC)
  mark_pointer_liveness(userlove, CC)
  hook_update(userlove)
  hook_draw(userlove)
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

local click_delay = 0.4
local drift_tolerance = 2.5

local click_count = 0
local click_timer = 0
--- @type Point?
local click_pos = nil

--- @param prev Point?
--- @param cur Point?
--- @return boolean
local function no_drift(prev, cur)
  if prev and cur
  then
    local px, py = prev.x, prev.y
    local cx, cy = cur.x, cur.y
    if px and cx and math.abs(px - cx) < drift_tolerance
    then
      if py and cy and math.abs(py - cy) < drift_tolerance
      then
        return true
      end
    end
  end
  return false
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
  local combo = ''
  for _, m in ipairs(COMBO_MODS) do
    if MOD_HELD[m[3]]() then
      combo = combo .. m[3] .. '+'
    end
  end
  return combo .. k:lower()
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
    local function keypressed(k, _, isr)
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
      CC:keypressed(k)
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
    local function update(dt)
      if love.PROFILE then
        Prof.update()
      end
      if Serial and SerialPort then
        for _, f in ipairs(SerialPort:update(dt)) do
          print('serial fault [' .. f.env .. ']: ' ..
            tostring(f.err))
        end
      end
      if click_timer > 0 then
        click_timer = click_timer - dt
      end
      if click_timer <= 0 then
        -- Synthesis only: decide WHICH derived event the raw
        -- presses amount to, then emit it through the gateway
        -- like any native one. Who receives it, whether it is
        -- error-wrapped and whether anyone consumes it are the
        -- route's business, not this timer's.
        local derived
        if click_count == 1 then
          derived = 'singleclick'
        elseif click_count >= 2 then
          derived = 'doubleclick'
        end
        -- Drift discards the click outright rather than
        -- degrading it to presses: moving between the two
        -- invalidates both (doc/input_api.md, "Pointer and
        -- click hooks"). A project that wants the raw
        -- presses binds mousereleased, which is untouched.
        if derived then
          local x, y = love.mouse.getPosition()
          if no_drift(click_pos, { x = x, y = y }) then
            love.handlers[derived](x, y)
          end
        end
        click_count = 0
      end

      local ddr = View.prev_draw
      local ldr = love.draw
      if ldr ~= ddr then
        local draw = function()
          if ldr then
            gfx.push('all')
            wrap(ldr, CC)
            gfx.pop()
          end
          local ui = get_user_input()
          if ui then
            ui.V:draw()
          end
        end

        View.prev_draw = draw
        love.draw = draw
      end
      CC:pass_time(dt)

      local uup = Controller._userhandlers.update
      if user_update and uup
      then
        CC:use_canvas(function()
          wrap(uup, CC, dt)
        end)
      end
      if love.state.app_state == 'snapshot' then
        gfx.captureScreenshot(function(img)
          local snap = gfx.newImage(img)
          if View.snapshot then View.snapshot:release() end
          View.snapshot = snap
          CC:suspend()
        end)
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
    local function draw()
      View.draw(CC, CV)
      local ui = get_user_input()
      if ui then ui.V:draw() end
      View.drawFPS()
    end
    love.draw = draw

    View.prev_draw = love.draw
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

    local function quit()
      --- flush pending writes before the process can exit
      --- (spec 2.6): a graceful quit loses nothing. One
      --- syscall; force-stop is covered by per-accept fsync
      FS.sync()
      if Application.consume_application_exit_request() then
        Application.return_home_before_exit()
        return false
      end
      if love.state.app_state == 'shutdown' then
        Application.return_home_before_exit()
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
      -- pointer-only projects stay live in `project_open`
      -- (RESOLVED, ruling a)"). An idle console in project_open
      -- falls through: the app quits.
      if love.state.app_state == 'running'
          or (love.state.app_state == 'project_open'
              and Controller.user_is_interactive()) then
        CC:stop_project_run()
        return true
      end
      Application.return_home_before_exit()
    end
    love.quit = quit
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
  --- 'running' -> 'project_open' transition releases nothing,
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
    local function reserved_quickswitch()
      if playback then return end
      local st = love.state.app_state
      if st == 'running' or st == 'inspect'
          or st == 'project_open' then
        CC:stop_project_run()
        local ed = love.state.editor
        if ed then CC:edit(ed.buffer.filename, ed)
        else CC:edit() end
      elseif st == 'editor'
          and CC.editor:is_normal_mode() then
        local ed_state = CC:finish_edit()
        love.state.editor = ed_state
        CC:run_project()
      end
    end

    local function reserved_suspend()
      if playback then return end
      CC:suspend_run(messages.user_break)
    end

    local function reserved_quit()
      if playback then return end
      CC:quit_project()
    end

    -- Bare Ctrl+S must not gain an editor branch: the key
    -- is UNCLAIMED there, and the rework's checkpoint is
    -- Ctrl+K (technical_debt/input.md, T-CTRL-S-UNCLAIMED).
    local function reserved_stop_run()
      if playback then return end
      if love.state.app_state == 'running' then
        CC:stop_project_run()
      end
    end

    local function reserved_reset()
      if playback then return end
      CC:reset()
    end

    -- Restart stays live in playback too (matches the old
    -- restart() call, made in both branches).
    local function reserved_restart()
      CC:restart()
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

    -- The gate's own reservations
    -- (doc/development/decisions/input.md, D-RESERVE-TABLE): a
    -- SECOND, PRIVILEGED table, structurally separate from a
    -- project's own compy.input.shortcuts — consulted before
    -- any route exists, and never overridable by one.
    -- Opposite contract from a project's shortcut table: a
    -- project's entry CONSUMES the key by returning truthy: a
    -- reservation NEVER CONSUMES, so the key still reaches the
    -- route afterward exactly as it did before this table.
    local RESERVED = {
      keypressed = {
        ['ctrl+t']           = reserved_quickswitch,
        ['ctrl+pause']       = reserved_suspend,
        ['ctrl+q']           = reserved_quit,
        ['ctrl+s']           = reserved_stop_run,
        ['ctrl+shift+r']     = reserved_reset,
        ['ctrl+alt+r']       = reserved_restart,
        ['ctrl+alt+p']       = reserved_profile_start,
        ['ctrl+alt+shift+p'] = reserved_profile_stop,
        ['f10']              = reserved_overlay,
      },
      -- Ctrl+Escape lives on release, matching the key it quits
      -- on (doc/development/decisions/input.md,
      -- D-RESERVE-TABLE).
      keyreleased = {
        ['ctrl+escape'] = Application.request_application_exit,
      },
    }

    handlers.keypressed = function(k, sc, isr)
      -- Not a reservation: this fires on ANY key in playback
      -- while shutting down, not on one combo, so it cannot be
      -- a table entry.
      if playback and love.state.app_state == 'shutdown' then
        love.event.quit()
      end
      local reservation = RESERVED.keypressed[combo_string(k)]
      if reservation then reservation() end

      -- This is `love.handlers.keypressed`, the raw
      -- event-pump entry; `love.keypressed` below holds the
      -- active route's handler (console via
      -- set_love_keypressed, project via occupy_input).
      -- Forwarding = invoke whichever route is installed.
      -- Widgets are reached inside the route, never gated
      -- here. (Mirrors stock LÖVE's love.handlers[name] ->
      -- love[name].) See doc/development/decisions/input.md #1
      -- "route-centric routing" + #11.
      if love.keypressed then
        return love.keypressed(k, sc, isr)
      end
    end

    handlers.textinput = function(t)
      if love.textinput then
        return love.textinput(t)
      end
    end

    handlers.keyreleased = function(k, sc)
      local reservation = RESERVED.keyreleased[combo_string(k)]
      if reservation then reservation() end
      if love.keyreleased then
        return love.keyreleased(k, sc)
      end
    end

    --- @param x integer
    --- @param y integer
    --- @param btn integer
    --- @param touch boolean
    --- @param presses number
    -- The gateway entry: hand the event to whoever occupies
    -- the slot. Under a project run that is the project
    -- route's chain; otherwise the console's own handler.
    handlers.mousepressed = function(x, y, btn, touch, presses)
      if love.mousepressed then
        return love.mousepressed(x, y, btn, touch, presses)
      end
    end

    --- @param x integer
    --- @param y integer
    --- @param btn integer
    --- @param touch boolean
    --- @param presses number
    handlers.mousereleased = function(x, y, btn, touch, presses)
      if btn == 1 then
        click_count = click_count + 1
        click_timer = click_delay
        click_pos = { x = x, y = y }
      end
      if love.mousereleased then
        return love.mousereleased(x, y, btn, touch, presses)
      end
    end

    --- @param x number
    --- @param y number
    --- @param dx number
    --- @param dy number
    --- @param touch boolean
    handlers.mousemoved = function(x, y, dx, dy, touch)
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
      if love.touchpressed then
        return love.touchpressed(id, x, y, dx, dy, pressure)
      end
    end

    --- @param id userdata
    --- @param x number
    --- @param y number
    --- @param dx number?
    --- @param dy number?
    --- @param pressure number?
    handlers.touchreleased = function(id, x, y, dx, dy, pressure)
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
      if love.touchmoved then
        return love.touchmoved(id, x, y, dx, dy, pressure)
      end
    end


    --- @diagnostic disable-next-line: undefined-field
    table.protect(love.handlers)
  end,

  set_user_handlers = set_handlers,

  user_is_blocking = function()
    return (user_update or user_draw)
  end,

  --- A non-blocking project is still "live" while it has an
  --- active input widget or a pointer/click handler — it keeps
  --- the project route and Ctrl+Esc returns to the console.
  user_is_interactive = function()
    return (love.state.user_input ~= nil) or user_pointer
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
    set_handlers(Controller._userhandlers, CC)
  end,

  --- @param CC ConsoleController?
  clear_user_handlers = function(CC)
    Controller._userhandlers = {}
    View.clear_snapshot()
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
