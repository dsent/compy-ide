-- Shared fixture for the input contract suite. Builds the
-- real love.handlers wiring over a real ConsoleController,
-- a project input widget (production builds one per run), the
-- click/update path and a keypress-level driver — so a
-- contract test reads as a one-line statement (see
-- tests/helpers/input_session). All MVC/gfx/font
-- boilerplate the suite needs lives here; consumed, never
-- copied.

-- view.view stub: the real module calls gfx.newFont at load and
-- needs a graphics context absent here. Set BEFORE any view
-- require below.
package.preload['view.view'] = function()
  View = {
    prev_draw      = nil,
    main_draw      = nil,
    snapshot       = nil,
    clear_snapshot = function() end,
    draw           = function() end,
    drawFPS        = function() end,
  }
end

local mock = require('tests.mock')
local TU   = require('tests.testutil')

-- Mouse position the click path samples; tests drive it through
-- set_mouse_pos to make drift detection observable.
local mx, my = 0, 0
-- Held-button state the widget's drag-select reads through
-- love.mouse.isDown; see mock_runtime below.
local mouse_down = false

local function mock_runtime()
  mock.mock_love({
    state = {
      app_state             = 'ready',
      user_input            = nil,
      user_input_controller = nil,
      editor                = nil,
    },
    DEBUG   = false,
    PROFILE = false,
    event   = { quit = function() end, push = function() end },
    audio   = {
      newSource = function() return { } end,
      stop      = function() end,
      play      = function() end,
    },
    -- isDown is real production input: the widget's drag-select
    -- consults it on every mousemoved
    -- (userInputModel, "mouse_drag"). Driven by
    -- F.set_mouse_down so a case can hold a button over a move.
    mouse      = {
      getPosition = function() return mx, my end,
      isDown      = function() return mouse_down end,
    },
    paths      = { project_path = '/tmp' },
    filesystem = { getInfo = function() end },
    -- The console prepares serial support at build time and asks
    -- love.system.getOS() to pick a backend; the mock love has no
    -- `system`, so stub it (a desktop OS -> the null backend).
    system     = { getOS = function() return 'Linux' end },
  })
end

local canvas_stub = setmetatable({ }, {
  __index = function() return function() end end,
})

-- Enrich the graphics mock enough to build the terminal/canvas
-- the console model allocates — no real display is opened.
local function enrich_gfx()
  local gfx = love.graphics
  gfx.newCanvas = function() return canvas_stub end
  gfx.getCanvas = function() return nil end
  gfx.setCanvas = function() end
  gfx.setFont   = function() end
  gfx.setColor  = function() end
  gfx.clear     = function() end
  gfx.push      = function() end
  gfx.pop       = function() end
  -- love.update walks into the snapshot branch as soon as a
  -- project raise sets 'snapshot', so this has to exist. It is
  -- a no-op that never invokes its callback, modelling "the
  -- screenshot has not been delivered yet" — the state a run
  -- sits in between suspend_run and suspend. Cases wanting the
  -- far side of that boundary call CC:suspend() themselves.
  gfx.captureScreenshot = function() end
end

-- A monospace font is a leaf dependency of the terminal; stub
-- the metrics it queries at construction.
local font_stub = setmetatable({
  getHeight     = function() return 32 end,
  getWidth      = function() return 16 end,
  setFallbacks  = function() end,
  setLineHeight = function() end,
}, { __index = function() return function() end end })

local function build_cfg()
  require('util.color')
  local cfg = TU.mock_view_cfg()
  cfg.view.font   = font_stub
  cfg.view.colors = require('conf.colors')
  cfg.view.w      = 1024
  cfg.view.h      = 600
  cfg.view.fw     = 16
  cfg.view.lh     = 1
  cfg.mode        = 'dev'
  return cfg
end

local function require_modules()
  require('model.consoleModel')
  require('model.input.userInputModel')
  require('model.interpreter.eval.evaluator')
  require('controller.consoleController')
  require('view.consoleView')
  require('controller.userInputController')
  require('controller.controller')
end

-- The Console MVC the way main.lua wires it; ConsoleView's
-- constructor calls CC:init_view(self) internally.
local function build_console(cfg)
  local CM = ConsoleModel(cfg)
  local CC = ConsoleController(CM, Controller)
  ConsoleView(cfg, CC)
  return CC
end

-- A project widget, published to love.state.user_input_controller
-- the way production's build_input_widget does at the run seam;
-- the compy.input wrappers resolve it from there.
local function build_widget(cfg)
  -- Its OWN evaluator, as production's build_input_widget does:
  -- the evaluator resolves this widget's highlighter slot, so
  -- sharing one would resolve every widget's highlighter to
  -- whichever bound it last.
  local m = UserInputModel(cfg, Evaluator.plain('text input'))
  local c = UserInputController(m, true)
  -- The project widget's shipped lifecycle seating, mirroring
  -- build_input_widget: a fixture widget without it would let
  -- a spec assert the class defaults while a project meets
  -- something else (doc/development/decisions/input.md,
  -- D-LIFECYCLE-FLAGS, statement 3).
  c:seat_lifecycle({ clear_on_submit = true })
  c:init_view({ render = function() end, draw = function() end })
  -- The same call production makes, not a fixture-local
  -- equivalent: a widget built here must be wired the way
  -- build_input_widget wires one.
  c:bind_highlighter()
  love.state.user_input_controller = c
  return c
end

-- The world below is built from each spec file's busted
-- `setup()` (via F.setup), NOT at module-load time. NOTE:
-- busted 2 already insulates _G and package.loaded per spec
-- file (envmode='insulate'), so this is not guarding a live
-- cross-file collision — it makes the fixture explicit and
-- every (split) spec file runnable standalone. F.reset still
-- runs per-test; setup/teardown bracket the whole file.
local cfg, CC, widget, session

-- F for Fixture. Fields
-- (F.cc/console/editor/widget/session/cfg) are nil until
-- F.setup runs; reading them at describe-body scope is a bug.
-- `F.widget` is NOT a field: the project widget lives for one
-- project run (doc/development/decisions/input.md,
-- D-WIDGET-AT-BOOT as amended), so a captured reference goes
-- stale the moment a case runs or stops a project. It resolves
-- to whichever widget is current, which is what a project sees
-- through compy.input.
local F = setmetatable({}, {
  __index = function(_, k)
    if k == 'widget' then
      return love.state.user_input_controller
    end
  end,
})

function F.setup()
  if CC then return end -- already built for this spec file
  mock_runtime()
  enrich_gfx()
  cfg = build_cfg()
  require_modules()

  -- Production builds the project widget at the run seam, and
  -- most cases here drive the surface without running a
  -- project — so the fixture stands one up itself and F.reset
  -- replaces it per case. A case that wants the real lifetime
  -- uses F.run_project.
  widget = build_widget(cfg)
  CC = build_console(cfg)
  Controller.set_default_handlers(CC, CC.view)
  -- set_love_update (above) wires love.update, which drives the
  -- click-timer distinguishing single- from double-click
  -- (controller.lua set_love_update); tests advance it with
  -- F.love_update(dt).
  session = require('tests.helpers.input_session').new(CC)

  F.cc        = CC
  F.console   = CC.input
  F.editor    = CC.editor
  F.session   = session
  F.cfg       = cfg
end

-- Symmetric partner to F.setup, deliberately shallow:
-- require-cached class globals cannot be un-required, and
-- busted 2's per-file insulation reverts _G/package.loaded
-- anyway — so we only undo the fixture's own semantic state and
-- the two globals mock_love writes. NOT reverted by that
-- insulation is `package.loaders`: the merged controller keeps a
-- project open at all times and installs its loader there, so
-- this CC must remove the loaders it cached, or the next file's
-- first require trips a stale project loader (get_loader logs
-- unconditionally) with no `Log` global in sight.
function F.teardown()
  if Controller and Controller.project_input then
    Controller.project_input:deactivate()
  end
  if CC then
    for _, lf in pairs(CC.loaders) do
      local i = 1
      while i <= #package.loaders do
        if package.loaders[i] == lf then
          table.remove(package.loaders, i)
        else
          i = i + 1
        end
      end
    end
  end
  _G.love, _G.TESTING = nil, nil
  cfg, CC, widget, session = nil, nil, nil, nil
  F.cc, F.console, F.editor = nil, nil, nil
  F.session, F.cfg = nil, nil
end

-- The project-facing public surface (compy.input.show/hide); it
-- resolves the widget exactly as a project does.
function F.compy_input()
  return CC:get_project_env().compy.input
end

-- Is an input widget visible to the framework? Reads
-- love.state.user_input rather than the widget's own
-- is_shown(): the draw loop paints for exactly as long as that
-- field is set (controller.lua, both get_user_input() sites),
-- so this is the observable "the user sees the widget"
-- rather than the widget's self-report, and it stays honest if
-- the two disagree.
function F.is_widget_visible()
  return love.state.user_input ~= nil
end

function F.set_mouse_pos(x, y)
  mx, my = x, y
end

--- Hold or release the primary button for love.mouse.isDown.
--- @param down boolean
function F.set_mouse_down(down)
  mouse_down = down
end

function F.love_update(dt)
  love.update(dt)
end

-- Activate the test fixture widget directly.
function F.show_widget(opts)
  -- The CURRENT widget, not the fixture's local: after
  -- F.run_project the run built its own, and showing the stale
  -- one would assert against an object nothing else reads.
  local w = love.state.user_input_controller
  w:show(opts)
  return w
end

-- This is the narrow activation seam: the full runner also
-- loads and executes a project file, but these cases need
-- controlled handlers. It invokes the real route installer;
-- events still use love.handlers.
function F.activate_project(handlers)
  love.state.app_state = 'running'
  -- A real run builds the widget at this same boundary
  -- (D-WIDGET-AT-BOOT as amended), so the narrow seam does too
  -- — otherwise a case that stops and re-activates would find
  -- no widget where production gives it a fresh one.
  widget = build_widget(cfg)
  Controller.set_user_handlers(handlers or { }, CC)
  return F.compy_input()
end

-- The SIMPLE surface's namespace (compy.ask / on_answer /
-- on_key / unask), resolved exactly as a project resolves it —
-- off the live project env, so a case reads the same clone the
-- stubs read at fire time (D-SIMPLE-SURFACE, statement 4).
function F.compy()
  return CC:get_project_env().compy
end

-- activate_project's simple-surface twin: same narrow seam,
-- returning the namespace instead of the precise API.
function F.activate_simple(handlers)
  F.activate_project(handlers)
  return F.compy()
end

-- A selection-enabled widget seeded with multi-line text, so a
-- pointer event lands an OBSERVABLE selection (the production
-- the widget disables selection, making pointer delivery a
-- no-op — doc/development/internals/user_input.md, "Input
-- widget mouse"). Witnesses pointer delivery to the widget
-- half.
function F.show_selectable_widget(lines)
  local m = UserInputModel(cfg, InputEvalText)
  local w = UserInputController(m, false)
  w:init_view({ render = function() end, draw = function() end })
  w.model:set_text(lines or { 'aa', 'bb', 'cc' })
  love.state.user_input = { M = m, C = w, V = w.view }
  -- The dispatch chain resolves its terminal consumer from
  -- love.state.user_input_controller, not from the published
  -- handle, so a case that wants this widget to receive chain
  -- traffic has to stand it up there too. F.reset puts the
  -- fixture's own widget back.
  w:always_shown()
  love.state.user_input_controller = w
  return w
end

-- Drive the REAL ConsoleController:run_project with a chunk
-- supplied here, because a unit test has no project on disk.
-- Only the loader is stubbed; everything the run does around
-- the chunk (state transitions, widget lifetime, teardown) is
-- production. `fn` is the project's top-level code.
--- @param fn function?
function F.run_project(fn)
  local P = CC.model.projects
  local prev_current, prev_run = P.current, P.run
  P.current = { name = 'p' }
  P.run = function()
    return function() if fn then fn() end end, nil, '/tmp/p'
  end
  CC:run_project('p')
  P.current, P.run = prev_current, prev_run
end

-- A SECOND project widget, published as the current one. The
-- shape a per-run widget lifetime produces: the surface a
-- project holds must follow the live widget, not the one that
-- happened to exist when the surface was built. F.reset puts
-- the shared widget back.
function F.other_widget()
  return build_widget(cfg)
end

-- Production stop owns route/output teardown, the widget's
-- shownness included. What remains here is either fixture-owned
-- state production never creates, or content production keeps
-- on purpose between runs.
function F.reset()
  -- Undo a show_selectable_widget swap before teardown runs, so
  -- stop_project_run tears down the fixture's widget rather
  -- than a case-local one.
  love.state.user_input_controller = widget
  CC:stop_project_run()
  -- The stop DESTROYS the widget, as a real stop does. A case
  -- that never runs a project still needs one to drive, so the
  -- fixture stands the next one up here — which is also what
  -- makes each case's widget its own (D-WIDGET-AT-BOOT as
  -- amended).
  widget = build_widget(cfg)
  -- The device outlives a test the way a keyboard outlives a
  -- keystroke: a chord that never released leaves its modifier
  -- down for the next test unless the reset lifts it.
  mock.release_keys()
  love.state.app_state          = 'ready'
  love.state.editor             = nil
  -- Otherwise leaks into the next test's suspend(): a
  -- stale message from an earlier suspend_run() would set
  -- an unrelated console error (discovered via the route-
  -- lifecycle inspect case, m5c chunk 4).
  love.state.suspend_msg        = nil
  love.update(1.0)
  CC.input:clear()
  CC.editor.input:clear()
  -- Only the widget's CONTENT: production teardown hides the
  -- widget but deliberately keeps its text. `widget.shown =
  -- false` used to be forced here too, which quietly
  -- compensated for stop_project_run not lowering the flag —
  -- and hid that bug from the whole suite.
  widget:clear()
end

--- A chain participant that records itself and then decides
--- whether the walk carries on. One paradigm per suite instead
--- of a bespoke closure per test: `local p = F.tracer(seen)`,
--- then `p('shortcut', true)` is a consuming shortcut and
--- `p('hook')` a hook that falls through. `seen` ends up
--- holding the participants that ran, in call order.
--- @param seen table   filled in call order
--- @return fun(who: string, consume: boolean?): function
function F.tracer(seen)
  return function(who, consume)
    return function()
      seen[#seen + 1] = who
      return consume or false
    end
  end
end

return F
