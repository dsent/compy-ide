require("view.input.userInputView")
require("controller.editorController")
require("controller.userInputController")
require("controller.projectInputController")


local class = require('util.class')
local LANG = require("util.eval")
local FS = require('util.filesystem')
local Application = require('util.application')
require("util.key")
require("util.table")
local TerminalTest = require("util.test_terminal")

local messages = {
  file_does_not_exist = function(name)
    local n = name or ''
    return 'cannot open ' .. n .. ': No such file or directory'
  end,
}
--- @class ConsoleController
--- @field time number
--- @field model Model
--- @field main_ctrl table
--- @field main_env LuaEnv
--- @field pre_env LuaEnv
--- @field base_env LuaEnv
--- @field project_env LuaEnv
--- @field loaders function[]
--- @field input UserInputController
--- @field editor EditorController
--- @field view ConsoleView?
--- @field cfg Config
--- methods
--- @field edit function
--- @field finish_edit function
ConsoleController = class.create()

--- @param M Model
function ConsoleController.new(M, main_ctrl)
  local env = getfenv()
  local pre_env = table.clone(env)
  local config = M.cfg
  pre_env.font = config.view.font
  local IC = UserInputController(M.input)
    :always_shown()
    -- Escape clears the console line and remembers it, exactly
    -- as it always has -- now because this instance asks for
    -- it rather than because the widget destroys
    -- unconditionally (doc/development/decisions/input.md,
    -- D-LIFECYCLE-FLAGS, statement 3).
    :seat_lifecycle({ clear_on_cancel = true })
  -- Console history navigation: at the vertical boundary the
  -- widget fires on_limit_reached; the console maps up/down to
  -- history back/forward (doc/development/decisions/input.md,
  -- D-EDIT-CALLBACKS), retiring the old keypressed
  -- return-value channel.
  IC.callbacks.on_limit_reached = function(dir)
    if dir == 'up' then IC:history_back() end
    if dir == 'down' then IC:history_fwd() end
  end
  local self = setmetatable({
    time        = 0,
    model       = M,
    main_ctrl   = main_ctrl,
    input       = IC,
    -- console runner env
    main_env    = env,
    -- copy of the application's env before the prep
    pre_env     = pre_env,
    -- the project env where we make the API available
    base_env    = {},
    -- this is the env in which the user project runs
    -- subject to change, for example when switching projects
    project_env = {},

    loaders     = {},

    view        = nil,

    cfg         = config
  }, ConsoleController)
  --- the editor has to know about us
  local EC = EditorController(M.editor, self)
  self.editor = EC
  -- initialize the stub env tables
  ConsoleController.prepare_env(self)
  ConsoleController.prepare_project_env(self)

  return self
end

--- @param V ConsoleView
function ConsoleController:init_view(V)
  self.view = V
  self.input:init_view(V.input)
  self.input:update_view()
end

--- @param name string
--- @param f function
function ConsoleController:cache_loader(name, f)
  self.loaders[name] = f
end

--- @param name string
--- @return function?
function ConsoleController:get_loader(name)
  return self.loaders[name]
end

--- @param f function
--- @param cc ConsoleController
--- @param project_path string?
--- @return boolean success
--- @return string? errmsg
local function run_user_code(f, cc, project_path)
  local output = cc.model.output
  local env = cc:get_base_env()

  local ok, call_err
  cc:use_canvas(function()
    if project_path then
      env = cc:get_project_env()
    end
    ok, call_err = pcall(f)
    if project_path and ok then -- user project exec
      if love.PROFILE then
        love.PROFILE.frame = 0
        love.PROFILE.report = {}
      end
      cc.main_ctrl.set_user_handlers(env['love'], cc)
    end
    output:restore_main()
  end)
  if not ok then
    local msg = LANG.get_call_error(call_err)
    return false, msg
  end
  return true
end

local function default_before_exit()
  Log.debug('compy.before_exit noop')
end

--- The framework's own teardown, and the ONLY place a project's
--- `compy.before_exit` is ever invoked.
---
--- Stopping is the framework's business, not the project's.
--- A hook at all is a convenience — somewhere to save a score
--- or stop a timer — so it is called here, directly, inside a
--- pcall, and never through the dispatch chain. That is the
--- point of the indirection rather than a call at the stop
--- site: a chain consumer signals by returning truthy, and no
--- later edit should be able to give a project's teardown hook
--- that meaning by accident. Nothing reads what it returns, and
--- there is no return value here for a caller to read either.
---
--- Single invocation point by construction, so a second stop
--- path cannot grow its own arrangement. It is also where
--- forced restore of global device state belongs once that is
--- built: the framework has teardown of its own to do, and
--- this is the seam for it. See
--- doc/development/technical_debt/input.md, "A project that
--- raises leaves global device state dirty".
---
--- Uninstalling AFTER the call, never before, is what makes a
--- parting reinstallation from inside the hook unreachable.
--- @param compy table
local function framework_before_exit(compy)
  local project_hook = compy.before_exit
  if project_hook then
    local ok, err = pcall(project_hook)
    if not ok then
      Log.error('compy.before_exit raised: '
        .. tostring(err))
    end
  end
  compy.before_exit = default_before_exit
end

--- Called at both ends of a run — the stop path and the
--- failed-run path. Down THROUGH the widget, never by clearing
--- `love.state.user_input`: the widget's own `shown` flag has
--- to fall with the handle, or the next project's show() is
--- refused as a repeat (doc/development/decisions/input.md,
--- D-WIDGET-AT-BOOT). `hide()` fires no cancel flow
--- (D-EDIT-LIFECYCLE) — teardown is not a user-facing dismiss.
local function hide_input_widget()
  local widget = love.state.user_input_controller
  if widget then return widget:hide() end
  love.state.user_input = nil
end

--- The project's widget is built when a run starts and dropped
--- when it stops (doc/development/decisions/input.md,
--- D-WIDGET-AT-BOOT as amended): a store a project leaves on it
--- cannot reach the next project, because the object it lived
--- on is gone.
--- The console's, editor's and search strip's widgets are
--- unaffected: those surfaces live as long as the app does.
--- Its own evaluator, NOT the shared `InputEvalText` instance:
--- the evaluator resolves this widget's highlighter slot
--- (`bind_highlighter`), so a shared one would resolve every
--- widget's highlighter to whichever bound it last. The
--- evaluator is part of what the run owns.
--- @param cfg table
local function build_input_widget(cfg)
  local eval = Evaluator.plain('text input')
  local model = UserInputModel(cfg, eval)
  local widget = UserInputController(model, true)
  -- The project widget's one shipped default, seated on the
  -- LEAST-DESTRUCTIVE basis: submit consumes the content,
  -- because a project processes a submission through its
  -- callbacks and the next entry starts empty. Cancel seats
  -- NOTHING — hiding or clearing on Escape is opt-in, and a
  -- project that shows once with no re-show path cannot be
  -- stranded by a stray Escape
  -- (doc/development/decisions/input.md, D-LIFECYCLE-FLAGS,
  -- statement 3).
  widget:seat_lifecycle({ clear_on_submit = true })
  widget:init_view(UserInputView(cfg.view, widget))
  widget:bind_highlighter()
  love.state.user_input_controller = widget
end

--- Down THROUGH the widget first: `hide()` lowers its own shown
--- flag and clears the published handle, and only then is the
--- widget itself dropped. Bound to the STOP, never to the
--- 'running' → 'project_open' transition — a non-blocking
--- project lives in `project_open` and still owns its widget
--- there (D-ROUTE-LIFETIME, and the asymmetry its amendment
--- deleted).
local function destroy_input_widget()
  hide_input_widget()
  love.state.user_input_controller = nil
end

--- @param cc ConsoleController
local function close_project(cc)
  local ok = cc:close_project()
  if ok then
    print('Project closed')
  else
    Log.err('error in closing')
  end
end

--- @private
--- @param name string
--- @return string?
--- @param name string
--- @return string
local function checkpoint_name(name)
  return name .. '.~save'
end

--- Modification time of a project file, nil if absent
--- @param name string
--- @return integer? modtime
function ConsoleController:file_modtime(name)
  local p = self.model.projects.current
  if not p then return end
  local info = FS.getInfo(p:get_path(name))
  return info and info.modtime
end

--- @param name string
--- @return integer? modtime of the checkpoint
function ConsoleController:checkpoint_modtime(name)
  return self:file_modtime(checkpoint_name(name))
end

--- Copy the file to its checkpoint (spec 2.6)
--- @param name string
--- @return boolean ok
function ConsoleController:write_checkpoint(name)
  local p = self.model.projects.current
  if not p then return false end
  local ok = FS.cp(
    p:get_path(name),
    p:get_path(checkpoint_name(name)))
  return ok and true or false
end

--- Write the checkpoint back over the file (spec 2.6)
--- @param name string
--- @return boolean ok
function ConsoleController:restore_checkpoint(name)
  local p = self.model.projects.current
  if not p then return false end
  local cp = p:get_path(checkpoint_name(name))
  if not FS.exists(cp) then return false end
  local ok = FS.cp(cp, p:get_path(name))
  return ok and true or false
end

function ConsoleController:_readfile(name)
  local PS              = self.model.projects
  local p               = PS.current
  local ok, text_or_err = p:readfile(name)
  if ok then
    return text_or_err
  else
    print(text_or_err)
  end
end

--- @private
--- @param name string
--- @return string[]?
function ConsoleController:_readlines(name)
  local s = self:_readfile(name)
  if s then
    return string.lines(s)
  end
end

--- @private
--- @param name string
--- @param content string[]
--- @return boolean success
--- @return string? err
function ConsoleController:_writefile(name, content)
  local P = self.model.projects
  local p = P.current
  local text = string.unlines(content)
  return p:writefile(name, text)
end

function ConsoleController:writefile(name, content)
  local P = self.model.projects
  local p = P.current
  local fpath = p:get_path(name)
  local ex = FS.exists(fpath)
  if ex then
    -- TODO: confirm overwrite
  end
  local ok, err = self:_writefile(name, content)
  if ok then
    print(name .. ' written')
  else
    print(err)
  end
end

_G.o_loadfile = _G.loadfile
--- @param name string
--- @return function?
function ConsoleController:loadfile(name)
  local PS               = self.model.projects
  local p                = PS.current
  local chunk = p:load_file(name)
  return chunk
end

-- (wrap_handler and get_compy_handler removed together: both
-- existed for compy.singleclick / compy.doubleclick, which are
-- now ordinary events reached through the dispatch chain. The
-- one surviving way to run project code — canvas bound, errors
-- routed, return propagated — is `guarded` in controller.lua,
-- applied where a route is entered. wrap_handler differed from
-- it only by discarding the return, which nothing needed.)

--- @param name string?
function ConsoleController:run_project(name)
  if love.state.app_state == 'inspect' or
      love.state.app_state == 'running'
  then
    self.input:set_error(
      { "There's already a project running!" })
    return
  end
  local P   = self.model.projects
  local cur = P.current
  local ok
  if cur and (not name or cur.name == name) then
    ok = true
  else
    ok = self:open_project(name or '', false)
  end

  if ok then
    local runner_env = self:get_project_env()
    local f, load_err, path = P:run(name, runner_env)
    if f then
      local n = name or P.current.name or 'project'
      Log.info('Running \'' .. n .. '\'')
      love.state.app_state = 'running'
      -- Before the project's top-level code, which may show the
      -- widget on its first line. This is the run seam, chosen
      -- over the OPEN seam because restart() and the Ctrl+T
      -- quickswitch call stop+run directly, never re-open:
      -- construct-at-open would leave every restart on the
      -- previous run's widget.
      build_input_widget(self.cfg)
      -- The program speaks for the board from here on; the
      -- console's own listeners wait until it has stopped.
      SerialPort:programStarted()
      gfx.setFont(self.cfg.view.font)
      local rok, run_err = run_user_code(f, self, path)
      if not rok then
        -- Top-level code raised, so the route was never
        -- connected. Release, then take down any widget the
        -- project managed to show first: D-ROUTE-LIFETIME's
        -- teardown invariant says a widget whose owning route
        -- is inactive goes unhonoured, and a shown one is not
        -- (doc/development/decisions/input.md,
        -- D-ROUTE-LIFETIME).
        self.main_ctrl.release_keyboard_route(self)
        destroy_input_widget()
        -- ...and the participants it installed before raising.
        -- Same invariant, same reason: nothing survives the
        -- project that installed it. before_exit is uninstalled
        -- but NOT fired: the hook is scoped to stop paths and
        -- excludes crash, yet a slot left holding the dead
        -- project's function would fire for the next one.
        self.main_ctrl.clear_user_handlers(self)
        self:get_project_env().compy.before_exit =
            default_before_exit
        -- Its serial handlers go the same way, by the same
        -- invariant, and the console is heard again.
        SerialPort:programEnded()
        love.state.app_state = 'project_open'
        print('Error: ', run_err)
      else
        if not self.main_ctrl.user_is_blocking() then
          -- The route is NOT released here. A non-blocking run
          -- reaching 'project_open' keeps every channel until
          -- the project actually stops. That is the pre-feature
          -- lifecycle: at the PR base nothing was released
          -- before suspend or stop, and the keyboard-only
          -- release this feature added was what forced pointer
          -- to be exempted from it. With every channel on one
          -- route there is nothing left to exempt.
          -- (doc/development/decisions/input.md,
          -- D-ROUTE-LIFETIME.)
          -- Serial is the exception: the program is idle, not
          -- stopped, so its handlers stay, but it is no longer
          -- the one speaking and the console listens again.
          SerialPort:programIdle()
          love.state.app_state = 'project_open'
        end
      end
    else
      --- TODO extract error message here
      print(load_err)
    end
  end
end

local o_require = _G.require
_G.o_require = o_require
--- @param name string
--- @param run 'run'?
local function project_require(name, run)
  if run then
    Log.info('req', name)
  end
  if _G.web and name == 'bit' then
    return o_require('util.luabit')
  else
    return o_require(name)
  end
end

_G.o_dofile = _G.dofile
--- @param cc ConsoleController
--- @param filename string
--- @param env LuaEnv?
local function project_dofile(cc, filename, env)
  local P = cc.model.projects
  local fn = filename
  local open = P.current
  if open then
    local chunk = open:load_file(fn)
    if chunk then
      if env then
        setfenv(chunk, env)
      end
      return true, chunk()
    else
      print(messages.file_does_not_exist(filename))
    end
  end
end


-- Set up audio table
local compy_audio = require("util.audio")
local compy_graphics = {
  shape2d = require("util.graphics.shape2d")
}
-- Builds the `compy.terminal` sub-namespace — the console
-- OUTPUT surface. These wrap the live `terminal` (the
-- REPL/console text grid): position the grid cursor
-- (gotoxy), show/hide it, and clear the screen. This is
-- where a project WRITES to the console; always present
-- while the project runs. Contrast with `compy.input`
-- below, the input solicitation surface.
local get_compy_terminal = function(terminal)
  return {
    --- @param x number
    --- @param y number
    gotoxy = function(x, y)
      return terminal:move_to(x, y)
    end,
    show_cursor = function()
      return terminal:show_cursor()
    end,
    hide_cursor = function()
      return terminal:hide_cursor()
    end,
    clear = function()
      terminal:move_to(1, 1)
      return terminal:clear()
    end
  }
end

-- Builds the `compy.input` sub-namespace — the input
-- solicitation surface, complementary to compy.terminal
-- (above): compy.terminal is the always-present console OUTPUT
-- grid the project writes to; compy.input is the transient
-- input widget the project shows to ask the user for text and
-- get a value back. The two "cursor" notions differ:
-- terminal.gotoxy moves the console grid cursor,
-- input.get_cursor/set_cursor address the caret WITHIN the
-- input widget. By architectural contract these wrappers are
-- the ONLY project-facing surface for that widget: they wrap
-- UserInputController (love.state.user_input_controller);
-- projects never touch the controller directly. Namespace +
-- lifecycle docs: doc/development/internals/user_input.md.
-- compy.input's write boundary
-- (doc/development/decisions/input.md, D-FROZEN-SHELL): the
-- container and the IDENTITY of its three sub-tables (shortcuts
-- / hooks / callbacks) are frozen — a project cannot replace
-- them (compy.input.shortcuts = {} raises). Every LEAF inside
-- is freely writable: shortcuts[event][combo] = fn (through the
-- combo table's own normalising __newindex, D-COMBO-TABLES),
-- hooks[event] = fn, callbacks[name] = fn. One structural rule
-- replaces the old enumerated 11-name allowlist — nothing to
-- keep in sync with the API surface.
--- @param k any
local function unassignable_error(k)
  error("compy.input: '" .. tostring(k)
    .. "' is not assignable", 2)
end

--- A read-only view over private state: reads resolve through
--- `resolve`, every write is refused. The empty table is the
--- point: a metatable defends only the keys its table does
--- not hold, so nothing may be a real field here.
--- Three surfaces share this shape: the shortcuts sub-table
--- (frozen per-event combo tables), the wrapper table, and
--- the compy.input container itself.
--- @param resolve fun(k: any): any
--- @param name fun(k: any): string   what the error reports
--- @return table
local function build_frozen_view(resolve, name)
  return setmetatable({ }, {
    __index = function(_, k) return resolve(k) end,
    __newindex = function(_, k) unassignable_error(name(k)) end,
  })
end

--- shortcuts sub-table: per-event combo tables whose identities
--- are frozen (shortcuts.keypressed = {} raises); leaf combo
--- writes reach the combo table's own normalising __newindex
--- (doc/development/decisions/input.md, D-COMBO-TABLES).
--- @param shortcuts table
local function build_shortcuts_surface(shortcuts)
  return build_frozen_view(
    function(event) return shortcuts[event] end,
    function(event) return 'shortcuts.' .. tostring(event) end)
end

--- The dispatch wrappers
--- (doc/development/decisions/input.md, D-IGNORE-REPEAT and
--- D-STOP-AND-SIDE), reached as compy.input.fn.*. Stateless and
--- orthogonal:
--- `ignore_repeat` decides whether the handler RUNS,
--- `stop_here`/`side_run` decide whether the event PROPAGATES —
--- each returns a fixed truthy/falsy in place of whatever the
--- handler returned — and neither knows about the other. The
--- combination most bindings want is
--- `stop_here(ignore_repeat(fn))`: act once per press, and let
--- nothing downstream see the key.
local INPUT_FN = {
  --- Skip the handler on an OS key repeat. Says nothing about
  --- propagation: a fresh press returns what the handler
  --- returned, a skipped repeat returns nothing.
  ignore_repeat = function(fn)
    return function(k, sc, isr)
      if isr then return end
      return fn(k, sc, isr)
    end
  end,
  --- Run `fn` if given, then consume. With no `fn` the
  --- binding's only job is to swallow the event.
  stop_here = function(fn)
    return function(...)
      if fn then fn(...) end
      return true
    end
  end,
  --- Run `fn` if given, and let the event carry on regardless
  --- of what it returned — the binding is a side effect, not a
  --- claim on the key.
  side_run = function(fn)
    return function(...)
      if fn then fn(...) end
      return false
    end
  end,
}

local input_fn_surface = build_frozen_view(
  function(k) return INPUT_FN[k] end,
  function(k) return 'fn.' .. tostring(k) end)

--- Assemble the compy.input surface: reads resolve the three
--- frozen sub-tables (shortcuts / hooks / callbacks), the
--- wrapper table, or a callable method; every write to the
--- container itself is refused loudly (D-FROZEN-SHELL — frozen
--- container, writable leaves).
--- @param state table
--- @param methods table
--- @return table
local function build_input_surface(state, methods)
  -- hooks and callbacks are handed over as themselves: only
  -- their IDENTITY is frozen, which the container's own refusal
  -- above already does, and every leaf inside them is writable.
  -- A pass-through proxy over them reproduced plain table
  -- behaviour exactly. "Frozen" binds the PROJECT, not the
  -- framework: callbacks is the live widget's table, so its
  -- identity is stable for exactly as long as a project can
  -- observe it — its own run.
  local resolve = {
    shortcuts = build_shortcuts_surface(state.shortcuts),
    hooks = state.hooks,
    fn = input_fn_surface,
  }
  -- callbacks is NOT in the table above: it lives on the
  -- widget, so it is resolved per access rather than captured
  -- (see widget_store).
  return build_frozen_view(function(k)
    if k == 'callbacks' then return state.callbacks end
    return resolve[k] or methods[k]
  end, tostring)
end

-- A config table carries keys of exactly two kinds, and the
-- two behave differently enough to be named apart.

-- STICKY: one `state` entry each, shared by the config key and
-- the direct compy.input.callbacks write, and kept across shows
-- until overwritten (doc/input_api.md, "Callback assignments").
local CALLBACK_KEYS = {
  'on_text_entered',
  'on_limit_reached',
  'validator',
  'highlighter',
}

-- SHOW-ONLY keys, mapped to where they DO belong so a refusal
-- can name the call instead of only refusing this one. The
-- three are here for two different reasons, and neither is "it
-- describes this session": `text`/`cursor` are the USER's
-- content and only activation seats them, while `force` answers
-- "replace the widget that is already shown", which
-- configure()
-- never faces. See doc/development/decisions/input.md,
-- D-UNKNOWN-RAISES's show-only category, added there by
-- D-CFG-BOUNDARY. The four lifecycle flags are NOT in it
-- (D-LIFECYCLE-FLAGS, statement 2): they are machinery, and
-- the user does not own lifecycle.
local SHOW_ONLY_KEYS = {
  text    = 'show(), or set_text on a live widget',
  cursor  = 'show(), or set_cursor on a live widget',
  force   = 'show()',
}

--- @param names string[]
--- @return table set
local function key_set(names)
  local set = { }
  for _, k in ipairs(names) do set[k] = true end
  return set
end

-- Project-owned, and kept across shows exactly as the sticky
-- ones are. They differ only in WHERE they live: on the widget
-- itself rather than in the store above.
local WIDGET_KEYS = {
  'prompt',
  'clear_on_submit', 'hide_on_submit',
  'clear_on_cancel', 'hide_on_cancel',
}

-- What each entry point accepts. The difference between them is
-- exactly SHOW_ONLY_KEYS: everything else is project-owned and
-- both calls take it, set-if-given (D-CFG-BOUNDARY, statement
-- 3).
local CONFIGURE_KEYS = key_set(CALLBACK_KEYS)
local SHOW_KEYS = key_set(CALLBACK_KEYS)
for _, k in ipairs(WIDGET_KEYS) do
  CONFIGURE_KEYS[k] = true
  SHOW_KEYS[k] = true
end
for k in pairs(SHOW_ONLY_KEYS) do SHOW_KEYS[k] = true end

-- Lifecycle callbacks are compy.input.callbacks assignments,
-- never config-table keys. Naming one here is the likeliest
-- mistake, so it earns a message that says where it belongs.
local LIFECYCLE_KEYS = {
  before_submit = true, after_submit = true,
  before_cancel = true, after_cancel = true,
}

--- @param fname string
--- @param key any
--- @return string
local function bad_key_message(fname, key)
  local name = tostring(key)
  if LIFECYCLE_KEYS[name] then
    return fname .. ": assign '" .. name ..
      "' on compy.input.callbacks, do not pass it here"
  end
  local belongs_to = SHOW_ONLY_KEYS[name]
  if belongs_to then
    return fname .. ": '" .. name .. "' belongs to " ..
      belongs_to .. ', do not pass it here'
  end
  return fname .. ": unknown config key '" .. name .. "'"
end

--- Strict contract enforcement
--- (doc/development/decisions/input.md, D-UNKNOWN-RAISES):
--- the config table is CLOSED, so a key
--- outside it can only be an authoring error — raise, and let
--- the project stop at the typo instead of running on in a
--- shape nobody asked for. Level 3 puts the trace on the
--- project's own show()/configure() line.
--- Runtime STATE no-ops (the widget already active, or
--- hidden) are NOT this: they keep warning, per
--- D-WIDGET-AT-BOOT.
---
--- Level 4 puts the trace on the project's own line, and holds
--- only while every caller sits at the same depth: project →
--- the api table's one-line closure → api_show/api_configure →
--- here. That is why `configure` is lifted out into
--- `api_configure` rather than doing the work inline — inline
--- it was one frame shallower, and the same constant pointed
--- `show`'s raise at this file instead of at the project.
--- @param cfg table
--- @param fname string
--- @param allowed table
local function check_keys(cfg, fname, allowed)
  for key in pairs(cfg) do
    if not allowed[key] then
      error(bad_key_message(fname, key), 4)
    end
  end
end

--- A cursor is a {line, col} pair of numbers. A malformed one
--- is an authoring error and is refused the way a bad KEY is —
--- with a framework message naming the shape, rather than the
--- raw "bad argument to 'min'" that used to come back out of
--- the clamp (doc/development/technical_debt/input.md,
--- "T-CURSOR-SHAPE"). An out-of-RANGE number is a different
--- thing: it is well-formed and still clamps, which is what
--- doc/input_api.md promises.
---
--- Falsey is the uniform unset (D-CFG-BOUNDARY, statement 3),
--- so a computed cursor that came to nothing seats none instead
--- of raising, and normalising it to nil here is what lets the
--- activation path keep one absence to test for. Same level-4
--- depth rule as check_keys above.
--- @param fname string
--- @param cursor any
--- @return table? pair
local function checked_cursor(fname, cursor)
  if not cursor then return nil end
  local pair = type(cursor) == 'table' and cursor or { }
  if type(pair[1]) == 'number'
    and type(pair[2]) == 'number' then
    return pair
  end
  error(fname ..
    ': cursor must be a {line, col} pair of numbers', 4)
end

--- A DENSE array of strings, counted over every key rather than
--- walked with ipairs: ipairs stops at the first hole and skips
--- non-integer keys, so { [1]='a', [3]=42 } and { foo=42 }
--- would both pass a walk and then lose content downstream,
--- which is the failure this check exists to prevent.
--- @param t table
--- @return boolean
local function is_line_list(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do
    if type(t[i]) ~= 'string' then return false end
  end
  return true
end

--- Sibling of checked_cursor, same level-4 depth rule. Content
--- is normalised, never validated, once it is inside the model
--- (doc/development/decisions/input.md, D-CONTENT-NORM) — what
--- cannot be normalised is refused here: a value that is not
--- text, or a table that is not a list of lines, is a structure
--- error rather than a spelling of the shape, and repairing it
--- would turn a caller's mistake into content nobody wrote.
--- @param fname string
--- @param text any
--- @return string|string[]|nil text
local function checked_text(fname, text)
  if not text then return nil end
  if type(text) == 'string' then return text end
  if type(text) == 'table' and is_line_list(text) then
    return text
  end
  error(fname ..
    ': text must be a string or a list of line strings', 4)
end

-- The two stores compy.input keeps for a project live ON the
-- widget, and the surface RESOLVES them instead of holding
-- them: a widget lives for a project RUN, so a captured
-- reference would be the previous run's table
-- (doc/development/decisions/input.md, D-WIDGET-AT-BOOT).
-- Between runs there is no widget and no store — every reader
-- below reads "no store" as "nothing to remember" and does
-- nothing, which is the rule the rest of this surface already
-- follows.
local WIDGET_STORES = { callbacks = true }

--- @param k any
--- @return table?
local function widget_store(k)
  if not WIDGET_STORES[k] then return nil end
  local w = love.state.user_input_controller
  return w and w[k]
end

--- Merge the sticky output-callback state into a show()/
--- configure() config in place: an explicit value wins and is
--- written back onto the widget; an absent one defaults to the
--- last-known value.
--- @param state table
--- @param cfg table
local function merge_callback_keys(state, cfg)
  local callbacks = state.callbacks
  if not callbacks then return end
  for _, k in ipairs(CALLBACK_KEYS) do
    if cfg[k] ~= nil then callbacks[k] = cfg[k] end
    cfg[k] = callbacks[k]
  end
end

--- The two that DO something, lifted out of the api table below
--- so they read as functions rather than as entries. Everything
--- still in the table is a one-line delegation to the widget.
--- @param get_widget fun(): UserInputController?
--- @param state table
--- @param cfg table?
local function api_show(get_widget, state, cfg)
  local next_cfg = cfg or { }
  check_keys(next_cfg, 'compy.input.show', SHOW_KEYS)
  next_cfg.cursor =
    checked_cursor('compy.input.show', next_cfg.cursor)
  next_cfg.text =
    checked_text('compy.input.show', next_cfg.text)
  merge_callback_keys(state, next_cfg)
  local ui = get_widget()
  if ui then ui:show(next_cfg) end
end

--- Lifted out for check_keys' depth rule, like api_configure.
--- @param get_widget fun(): UserInputController?
--- @param get_active fun(): table?
--- @param line any
--- @param col any
local function api_set_cursor(get_widget, get_active, line, col)
  if not get_active() then
    Log.warn('compy.input.set_cursor ignored — hidden')
    return
  end
  local pair =
    checked_cursor('compy.input.set_cursor', { line, col })
  get_widget():set_cursor_pos(pair[1], pair[2])
end

--- Lifted out for the same depth rule as api_set_cursor: the
--- shared error level has to land on the project's line from
--- here as well as from api_show.
--- @param get_widget fun(): UserInputController?
--- @param get_active fun(): boolean?
--- @param text any
--- @param keep_cursor boolean?
local function api_set_text(get_widget, get_active,
                            text, keep_cursor)
  if not get_active() then
    Log.warn('compy.input.set_text ignored — hidden')
    return
  end
  get_widget():set_text(
    checked_text('compy.input.set_text', text), keep_cursor)
end

--- Sibling of api_show, and lifted out for the same reason it
--- is: both entry points must reach check_keys at the same
--- call depth, or one shared error level cannot put the trace
--- on the project's line for both.
--- @param get_widget fun(): UserInputController?
--- @param state table
--- @param cfg table?
local function api_configure(get_widget, state, cfg)
  local next_cfg = cfg or { }
  check_keys(next_cfg, 'compy.input.configure',
    CONFIGURE_KEYS)
  merge_callback_keys(state, next_cfg)
  local ui = get_widget()
  if ui then ui:configure(next_cfg) end
end

--- @param get_widget fun(): UserInputController?
local function api_hide(get_widget)
  local ui = get_widget()
  if ui then ui:hide() end
end

-- Builds the compy.input surface: the three-consumer dispatch
-- surface (doc/development/decisions/input.md, D-CHAIN-OF-3) a
-- project registers against. `shortcuts[event]` are the
-- doc/development/decisions/input.md, D-COMBO-TABLES per-event
-- combo sub-tables (normalising); `hooks[event]` is the one
-- seeded hook per event (D-HOOKS-SEEDED). show/hide drive the
-- widget (resolved from love.state, never held by the project).
-- The widget-method surface a project drives (show/hide/
-- configure/set_text/get_text/set_cursor/get_cursor/clear),
-- parameterized by instance: any adopter — not only the project
-- widget — gets the same ergonomics over ITS OWN widget by
-- supplying its own resolvers. `get_widget` resolves the
-- UserInputController; `get_active_flag` reports shown-ness
-- (truthy = shown); `state` is the sticky output-callback store
-- show()/configure() read. The project widget closes the two
-- resolvers over the love.state globals — behaviour-identical
-- to the pre-factory inline shape.
--- @param get_widget fun(): UserInputController?
--- @param get_active_flag fun(): table?
--- @param state table
--- @return table
local function build_widget_api(get_widget, get_active_flag, state)
  return {
    show = function(cfg) api_show(get_widget, state, cfg) end,
    hide = function() api_hide(get_widget) end,
    -- doc/development/decisions/input.md, D-ONE-STATE-ASK: the
    -- one state question a project may ask the widget. It
    -- cannot read this itself — a project's `love` is a
    -- sandboxed clone, so `love.state.user_input` is always nil
    -- inside a project (internals/project_sandbox_env.md).
    is_shown = function()
      return get_active_flag() or false
    end,
    -- doc/development/internals/user_input.md, "Cursor
    -- manipulation and \"reset\"": 1-based (line, col); nil
    -- when hidden — a plain read of "nothing to report", not
    -- a refused mutation, so unlike set_cursor/set_text
    -- below it does not warn (same section).
    get_cursor = function()
      if not get_active_flag() then return nil end
      return get_widget():get_cursor_pos()
    end,
    -- doc/input_api.md, "Live changes": the content read,
    -- answering the string spelling on_text_entered
    -- delivers — set_text takes either spelling and means
    -- the same by both, so a string round-trips and names no
    -- type the guide does not have. nil when hidden, and
    -- silent for get_cursor's reason above.
    get_text = function()
      if not get_active_flag() then return nil end
      return string.unlines(get_widget():get_text())
    end,
    -- doc/development/internals/user_input.md, "Cursor
    -- manipulation and \"reset\"": clamped move; no-op +
    -- warn while hidden.
    set_cursor = function(line, col)
      api_set_cursor(get_widget, get_active_flag, line, col)
    end,
    -- doc/input_api.md, "Live changes": replace content
    -- (cursor to end, or kept + clamped); no-op + warn
    -- while hidden; view updates via the controller's
    -- set_text (no re-show).
    set_text = function(text, keep_cursor)
      api_set_text(
        get_widget, get_active_flag, text, keep_cursor)
    end,
    -- doc/development/internals/user_input.md,
    -- "configure(config)": the project-owned fields, applied
    -- the same way whether the widget is shown or hidden —
    -- there
    -- is nothing to defer, because the fields are written onto
    -- the widget and the widget outlives its own visibility.
    -- Hidden is not a refusal and does not warn. text/cursor
    -- never arrive: check_keys refuses them above
    -- (doc/development/decisions/input.md, D-CFG-BOUNDARY).
    -- Between runs there is no widget, so this is inert rather
    -- than a raise — the rule the rest of this surface follows.
    configure = function(cfg)
      api_configure(get_widget, state, cfg)
    end,
    -- doc/development/internals/user_input.md, "clear()": empty
    -- content + cursor to start, no callback; no-op + warn
    -- while hidden. Refreshes the view directly (no re-show) —
    -- reuses the controller's existing clear() (content + error
    -- state).
    clear = function()
      if not get_active_flag() then
        Log.warn('compy.input.clear ignored — hidden')
        return
      end
      local ui = get_widget()
      ui:clear()
      ui:update_view()
    end,
  }
end

local get_compy_input = function()
  -- This closure runs ONCE for the application, so it reads no
  -- widget: callbacks is RESOLVED per access
  -- through the state metatable below (owner ruling 2026-07-20,
  -- re-made 2026-08-27: compy.input.callbacks resolves to the
  -- current widget's table). NEVER reassign a resolved
  -- table — only mutate it.
  -- One combo table per channel, from the list the route
  -- dispatches on — not a copy of it, so a channel cannot exist
  -- for dispatch and be missing here.
  local shortcut_tables = { }
  for _, ev in ipairs(ProjectInputController.EVENTS) do
    shortcut_tables[ev] = Key.new_handler_table()
  end
  -- shortcuts: per-event combo tables (D-COMBO-TABLES,
  -- normalising). hooks: one fn per event, seeded once at
  -- activation (D-HOOKS-SEEDED). Both are the surface's own and
  -- start empty (leaves fill on project write). callbacks is
  -- NOT a field — it is the widget's, reached through __index
  -- (widget_store), and it carries the widget's stay-shown
  -- defaults.
  local state = setmetatable({
    shortcuts = shortcut_tables,
    hooks = { },
  }, {
    __index = function(_, k) return widget_store(k) end,
  })
  -- get_active resolves the widget's OWN shown flag (is_shown),
  -- never love.state directly.
  local function get_active()
    local w = love.state.user_input_controller
    return w and w:is_shown()
  end
  local methods = build_widget_api(
    function() return love.state.user_input_controller end,
    get_active,
    state)
  return build_input_surface(state, methods)
end

-- Builds the `compy.*` table injected into a sandbox env
-- (terminal, audio, graphics, fonts, and — for a project —
-- input); called while preparing both environments.
--
-- `with_input` is the asymmetry, and it is a ruling rather
-- than an oversight: the input surface resolves whichever
-- widget is current, so a console-side copy reaches a running
-- project's widget and reconfigures it, while its own hooks
-- are dispatched by nobody (technical_debt/input.md,
-- T-CONSOLE-SURFACE-INTERFERES; internals/console.md, "The
-- console environment"). Refusing the KEY in both namespaces
-- is deliberate too — without it, a console-side
-- `compy.input = {}` would succeed and hand the caller a
-- plain table it believes is the API.
--- @param terminal table
--- @param with_input boolean?
-----------------------------
--- the simple surface ------
-----------------------------

-- doc/development/decisions/input.md, D-SIMPLE-SURFACE: ask /
-- on_answer / on_key / unask, over the SAME widget the precise
-- API drives — no second widget, no second state, no second
-- event path. The stubs below READ the namespace slots when
-- they fire rather than capturing them (statement 4), which is
-- also what keeps them correct across env clones: table.clone
-- copies fields and shares the metatable, so a captured table
-- would be the pre-clone one.

--- The one-shot disposal a question seats: it disposes of
--- itself however it ends (statement 6).
local ASK_FLAGS = {
  clear_on_submit = true, hide_on_submit = true,
  clear_on_cancel = true, hide_on_cancel = true,
}

--- Whether this key will arrive as text, and so is textinput's
--- rather than on_key's. A single-character key constant is a
--- printable; `space` is the one multi-character name that
--- produces text. Ctrl/Alt suppress textinput, so a chord over
--- a printable IS reportable.
--- @param k string
--- @return boolean
local function arrives_as_text(k)
  if Key.ctrl() or Key.alt() then return false end
  return #k == 1 or k == 'space'
end

--- Save what `ask` is about to overwrite, so answering can put
--- it back. Content and prompt are NOT saved: they are the
--- user's, and restoring them would be show() undoing itself.
--- @param input table  the precise surface
--- @return table
local function save_config(input)
  local w = love.state.user_input_controller or { }
  local cb = input.callbacks or { }
  return {
    flags = {
      clear_on_submit = w.clear_on_submit or false,
      hide_on_submit  = w.hide_on_submit or false,
      clear_on_cancel = w.clear_on_cancel or false,
      hide_on_cancel  = w.hide_on_cancel or false,
    },
    on_text_entered = cb.on_text_entered or false,
    after_cancel    = cb.after_cancel or false,
    keypressed      = input.hooks.keypressed,
  }
end

--- @param input table
--- @param saved table
local function restore_config(input, saved)
  input.configure(saved.flags)
  local cb = input.callbacks
  cb.on_text_entered = saved.on_text_entered
  cb.after_cancel = saved.after_cancel
  input.hooks.keypressed = saved.keypressed
end

--- The simple surface's names. `get_env` resolves the LIVE
--- project environment: a project writes on_answer/on_key on
--- its own env clone, and the stubs must read that clone
--- rather than the table this closure was built with.
--- @param input table             the precise surface
--- @param get_env fun(): table?
--- @return table
local function build_simple_surface(input, get_env)
  -- One armed question at a time, per application: the widget
  -- is one, so a second ask re-shows rather than nesting.
  -- `armed` holds what to put back; whether we ARE armed is
  -- read off the installed stub instead, because a question
  -- can be lost without concluding (statement 6's uncovered
  -- path) and a stale save would then be restored over a
  -- later question's configuration.
  local armed = nil
  local key_stub

  --- @param k any
  local function slot(k)
    local env = get_env()
    local ns = env and rawget(env, 'compy')
    return ns and rawget(ns, k)
  end

  local function disarm()
    if not armed then return end
    local saved = armed
    armed = nil
    restore_config(input, saved)
  end

  --- The boilerplate `ask` installs on both conclusions
  --- (owner, 2026-09-09): revert every configuration tweak
  --- FIRST, then notify. Restoring before notifying is what
  --- lets on_answer ask the next question with a plain ask.
  --- @param payload string?
  local function conclude(payload)
    disarm()
    local cb = slot('on_answer')
    if cb then cb(payload) end
  end

  --- Statement 7: the return value decides consumption, and
  --- everything not reportable passes through untouched — so
  --- `ask` needs no list of the keys editing owns.
  key_stub = function(k, sc, isr)
    local w = love.state.user_input_controller
    if not (w and w:is_shown()) then return end
    if Key.is_mod(k) then return end
    if arrives_as_text(k) then return end
    local cb = slot('on_key')
    if cb then return cb(k, sc, isr) end
  end

  --- The collision the owner ruled a RAISE rather than a
  --- chain (2026-09-09): a project owns its keypressed hook,
  --- and nothing is blocked by refusing — the precise API
  --- builds whatever the project wants.
  local function check_hook_free()
    local hk = input.hooks.keypressed
    if hk and hk ~= key_stub then
      error('compy.ask: compy.input.hooks.keypressed is'
        .. ' already set — a question installs its own;'
        .. ' use the precise API (compy.input.show) instead',
        3)
    end
    local env = get_env()
    local lv = env and rawget(env, 'love')
    if lv and lv.keypressed then
      error('compy.ask: this project defines love.keypressed —'
        .. ' a question installs its own key handler; use the'
        .. ' precise API (compy.input.show) instead', 3)
    end
  end

  return {
    --- @param prompt string?
    --- @param highlighter function?
    --- @param text string?
    --- @param cursor table?
    ask = function(prompt, highlighter, text, cursor)
      check_hook_free()
      if input.hooks.keypressed ~= key_stub then
        armed = save_config(input)
      end
      input.configure(ASK_FLAGS)
      local cb = input.callbacks
      cb.on_text_entered = function(t) conclude(t) end
      cb.after_cancel = function() conclude(nil) end
      input.hooks.keypressed = key_stub
      input.show({
        force       = true,
        prompt      = prompt,
        highlighter = highlighter,
        text        = text,
        cursor      = cursor,
      })
    end,

    --- Programmatic withdrawal. It disposes and restores, and
    --- concludes NOTHING: on_answer(nil) is the USER
    --- abandoning, and a program that withdrew its own
    --- question already knows.
    unask = function()
      if not armed then return end
      disarm()
      input.hide()
    end,
  }
end

local get_compy_namespace = function(terminal, with_input,
                                    cc, serial)
  require("util.namespace.fonts")
  -- Two members are held as upvalues rather than fields, and
  -- for the same reason: a metatable's __newindex only fires
  -- for a key the table does NOT hold, so a raw field cannot be
  -- defended. `input` must refuse assignment (D-FROZEN-SHELL)
  -- and `before_exit` must intercept it. UNSETTLED: an upvalue
  -- also survives table.clone by reference, so every env clone
  -- shares ONE before_exit slot. Nothing relies on that;
  -- nothing rules it out either. See
  -- doc/development/technical_debt/input.md,
  -- "`compy.before_exit` is a closure slot".
  local before_exit_slot = default_before_exit
  local input_surface = with_input and get_compy_input() or nil
  -- `serial` is held as an upvalue for the same reason as
  -- `input`: table.clone is deep, and a copied serial table
  -- would collect an env's handlers where the dispatcher
  -- never reads them. An upvalue survives the clone by
  -- reference, so every env talks to the platform port.
  local serial_surface = serial
  local ns = {
    terminal = get_compy_terminal(terminal),
    audio = compy_audio,
    graphics = compy_graphics,
    fonts = CompyFonts(),
  }
  -- D-SIMPLE-SURFACE statement 2: the simple names are PLAIN
  -- FIELDS, so each env clone owns its own on_answer/on_key
  -- slot rather than sharing one the way before_exit does.
  -- Only where the precise surface exists: the two are one API
  -- and the wrapper has nothing to wrap without it.
  if input_surface then
    local simple = build_simple_surface(input_surface,
      function() return cc and cc:get_project_env() end)
    ns.ask = simple.ask
    ns.unask = simple.unask
  end
  return setmetatable(ns, {
    __index = function(t, k)
      if k == 'before_exit' then return before_exit_slot end
      if k == 'input' then return input_surface end
      if k == 'serial' then return serial_surface end
      return rawget(t, k)
    end,
    __newindex = function(t, k, v)
      if k == 'before_exit' then
        before_exit_slot = v
      elseif k == 'input' then
        -- D-FROZEN-SHELL's first clause. compy.input's own
        -- metatable cannot defend this: replacing the
        -- container is a write to `compy`, one table up.
        error("compy.input is not assignable — write to its"
          .. ' sub-tables (shortcuts / hooks / callbacks)', 2)
      elseif k == 'serial' then
        error('compy.serial is not assignable — write to its'
          .. ' fields (onLine / onBytes / onConnect ...)', 2)
      else
        rawset(t, k, v)
      end
    end,
  })
end

function ConsoleController.prepare_env(cc)
  local prepared            = cc.main_env
  prepared.gfx              = love.graphics

  local P                   = cc.model.projects

  prepared.require          = function(name)
    return project_require(name)
  end

  --- @param f function
  local check_open_pr       = function(f, ...)
    if not P.current then
      print(P.messages.no_open_project)
    else
      return f(...)
    end
  end

  prepared.require          = project_require

  prepared.dofile           = function(name)
    return check_open_pr(function()
      return project_dofile(cc, name)
    end)
  end

  prepared.list_projects    = function()
    local ps = P:list()
    if ps:is_empty() then
      -- no projects, display a message about it
      print(P.messages.no_projects)
    else
      -- list projects
      cc.model.output:reset()
      print(P.messages.list_header)
      for _, p in ipairs(ps) do
        print('> ' .. p.name)
      end
    end
  end

  --- @param name string
  local open_project        = function(name)
    return cc:open_project(name)
  end

  prepared.project          = open_project

  prepared.close_project    = function()
    close_project(cc)
  end

  prepared.current_project  = function()
    if P.current and P.current.name then
      print('Currently open project: ' .. P.current.name)
    else
      print(P.messages.no_open_project)
    end
  end

  prepared.example_projects = function()
    local ok, err = P:deploy_examples()
    if not ok then
      print('err: ' .. err)
    end
  end

  prepared.clone            = function(old, new)
    local ok, err = P:clone(old, new)
    if not ok then
      print(err)
    end
  end

  prepared.list_contents    = function()
    return check_open_pr(function()
      local p = P.current
      local items = p:contents()
      print(P.messages.project_header(p.name))
      for _, f in pairs(items) do
        print('• ' .. f.name)
      end
    end)
  end

  --- @param name string
  --- @return string?
  prepared.readfile         = function(name)
    return check_open_pr(cc._readfile, cc, name)
  end

  --- @param name string
  --- @return function? chunk
  prepared.loadfile         = function(name)
    return check_open_pr(cc.loadfile, cc, name)
  end

  --- @param name string
  --- @return string[]?
  prepared.readlines        = function(name)
    return check_open_pr(cc._readlines, cc, name)
  end

  --- @param name string
  --- @param content string[]
  prepared.writefile        = function(name, content)
    return check_open_pr(cc.writefile, cc, name, content)
  end

  --- @param name string
  prepared.edit             = function(name)
    return check_open_pr(cc.edit, cc, name)
  end

  prepared.run_project      = function(name)
    cc:run_project(name)
  end

  local terminal            = cc.model.output.terminal
  require('model.serial.init')
  if love.system.getOS() == 'Android' then
    require('model.serial.backend_android')
    SerialPort = Serial.new(AndroidBackend.new())
  else
    require('model.serial.backend_null')
    SerialPort = Serial.new(NullBackend.new())
  end

  --- Show what the board sends, or stop showing it. Off
  --- until something asks for it.
  --- @param on boolean?
  prepared.echo             = function(on)
    local port = SerialPort:table_for('console')
    if on == false then
      SerialPort.echo:off()
      port.onBytes = nil
      return
    end
    SerialPort.echo:on()
    port.onBytes = function(chunk)
      SerialPort.echo:bytes(chunk)
    end
  end

  local compy_namespace     = get_compy_namespace(terminal,
    false, cc, SerialPort:table_for('console'))
  prepared.compy            = compy_namespace
  prepared.tty              = compy_namespace.terminal

  prepared.run              = prepared.run_project

  prepared.eval             = LANG.eval
  prepared.print_eval       = LANG.print_eval

  prepared.appver           = function()
    local ver = FS.read('ver.txt', true)
    if ver then print(ver) end
  end

  prepared.quit             = function()
    Application.request_exit()
  end
end

--- API functions for the user
--- @param cc ConsoleController
function ConsoleController.prepare_project_env(cc)
  require("controller.userInputController")
  require("model.input.userInputModel")
  require("view.input.userInputView")
  local cfg                   = cc.model.cfg
  ---@type table
  local project_env           = cc:get_pre_env_c()

  project_env.require         = function(name)
    return project_require(name)
  end
  project_env.dofile          = function(name)
    return project_dofile(cc, name, cc:get_project_env())
  end
  -- project_env.require         = function(name)
  --   return project_require(name, 'run')
  -- end

  --- @param name string
  --- @return string?
  --- Restore a file from its checkpoint; no prompt
  --- @param name string? --- default main.lua
  --- @return boolean
  project_env.revert          = function(name)
    name = name or ProjectService.MAIN
    return cc:restore_checkpoint(name)
  end

  project_env.readfile        = function(name)
    --- @diagnostic disable-next-line: invisible
    return cc:_readfile(name)
  end

  --- @param name string
  --- @return string[]?
  project_env.readlines       = function(name)
    --- @diagnostic disable-next-line: invisible
    return cc:_readlines(name)
  end

  --- @param name string
  --- @param content string[]
  project_env.writefile = function(name, content)
    return cc:writefile(name, content)
  end

  --- @param name string
  --- @return function? chunk
  project_env.loadfile         = function(name)
    return cc:loadfile(name)
  end

  --- @param msg string?
  project_env.pause           = function(msg)
    cc:suspend_run(msg)
  end
  project_env.stop            = function()
    cc:stop_project_run()
  end
  project_env.run             = function()
    if love.state.app_state == 'inspect' then
      cc:stop_project_run()
      cc:run_project()
    end
  end
  project_env.run_project     = project_env.run

  project_env.continue        = function()
    if love.state.app_state == 'inspect' then
      -- resume
      love.state.app_state = 'running'
      cc.main_ctrl.restore_user_handlers(cc)
    else
      print('No project halted')
    end
  end

  project_env.close_project   = function()
    close_project(cc)
  end

  --- @param name string
  project_env.edit           = function(name)
    return cc:edit(name)
  end

  project_env.gfx            = love.graphics

  local terminal             = cc.model.output.terminal
  local compy_namespace      = get_compy_namespace(terminal,
    true, cc, SerialPort:table_for('program'))
  project_env.compy          = compy_namespace

  project_env.LuaHighlighter = LuaHighlighter
  project_env.LuaSyntaxValidator = LuaSyntaxValidator
  project_env.LineValidators = LineValidators
  -- WITHHELD, not exported. project_env starts as a clone of
  -- the application env, which carries these four globals, so
  -- the assignment REMOVES each from a project's reach.
  -- Projects configure validation through compy.input's
  -- validator callback; they do not install evaluator objects
  -- (doc/development/internals/user_input.md,
  -- "Evaluator and validation").
  for _, name in ipairs({
    'InputEvalText',
    'InputEvalLua',
    'ValidatedTextEval',
    'LuaEditorEval',
  }) do
    project_env[name] = nil
  end

  project_env.eval           = LANG.eval
  project_env.print_eval     = LANG.print_eval

  local base                 = table.clone(project_env)
  local project              = table.clone(project_env)
  cc:_set_base_env(base)
  cc:_set_project_env(project)
end

---@param dt number
function ConsoleController:pass_time(dt)
  self.time = self.time + dt
  self.model.output.terminal:update(dt)
end

---@return number
function ConsoleController:get_timestamp()
  return self.time
end

function ConsoleController:evaluate_input()
  local inter = self.input

  local text = inter:get_text()
  if text:is_empty() then return end
  local eval = inter:get_eval()

  local eval_ok, res = inter:evaluate()

  if eval_ok and not string.is_non_empty(res) then
    return
  end

  if eval and eval.parser then
    if eval_ok then
      local code = string.unlines(text)
      local run_env = (function()
        if love.state.app_state == 'inspect' then
          return self:get_project_env()
        end
        return self:get_console_env()
      end)()
      local f, load_err = codeload(code, run_env)
      if f then
        local _, err = run_user_code(f, self)
        if err then
          inter:set_error({ err })
        else
          inter:clear()
        end
      else
        Log.error('Load error:', LANG.get_call_error(load_err))
        inter:set_error(load_err)
      end
    else
      local eval_err = res
      if eval_err then
        inter:set_error(eval_err)
      end
    end
  end
end

function ConsoleController:_reset_executor_env()
  self:_set_project_env(table.clone(self.base_env))
end

function ConsoleController:reset()
  self:quit_project()
  self.input:reset(true) -- clear history
end

function ConsoleController:restart()
  self:stop_project_run()
  self:run_project()
end

---@return LuaEnv
function ConsoleController:get_pre_env_c()
  return table.clone(self.pre_env)
end

---@return LuaEnv
function ConsoleController:get_console_env()
  return self.main_env
end

---@return LuaEnv
function ConsoleController:get_project_env()
  return self.project_env
end

---@return LuaEnv
function ConsoleController:get_base_env()
  return self.base_env
end

---@return LuaEnv
function ConsoleController:get_effective_env()
  if
      love.state.app_state == 'running'
      or love.state.app_state == 'inspect'
  then
    return self:get_project_env()
  else
    return self:get_console_env()
  end
end

---@param t LuaEnv
function ConsoleController:_set_project_env(t)
  self.project_env = t
end

---@param t LuaEnv
function ConsoleController:_set_base_env(t)
  self.base_env = t
  table.protect(t)
end

function ConsoleController:suspend()
  if love.state.app_state ~= 'snapshot' then
    return
  end
  local runner_env = self:get_project_env()
  Log.info('Suspending project run')
  love.state.app_state = 'inspect'
  local msg = love.state.suspend_msg
  if msg then
    self.input:set_error({ tostring(msg) })
    love.state.suspend_msg = nil
  end

  self.model.output:invalidate_terminal()

  self.main_ctrl.save_user_handlers(runner_env['love'])
  self.main_ctrl.set_default_handlers(self, self.view)
end

--- @param msg string?
function ConsoleController:suspend_run(msg)
  if love.state.app_state ~= 'running' then
    return
  end
  love.state.app_state = 'snapshot'
  love.state.suspend_msg = msg
end

--- @param name string
--- @param play boolean
--- @return boolean success
function ConsoleController:open_project(name, play)
  local P = self.model.projects
  if not name then
    print('No project name provided!')
    return false
  end
  local cur = P.current
  if cur then
    self:close_project()
  end

  local open, create, err = P:opreate(name, play)
  local ok = open or create
  if ok then
    local project_loader =
        P.current:get_loader(function()
          return self:get_effective_env()
        end)
    self:cache_loader(name, project_loader)

    if not table.is_member(package.loaders, project_loader)
    then
      table.insert(package.loaders, 1, project_loader)
    end
    love.state.app_state = 'project_open'
  end
  if open then
    print('Project ' .. name .. ' opened')
  elseif create then
    print('Project ' .. name .. ' created')
  else
    print(err)
  end
  return ok
end

--- @return boolean success
--- Closing ends the project, so it ends the project's widget:
--- reachable from a running project's own env and from the
--- console during `inspect`, and without this a closed
--- project's widget outlives it (D-WIDGET-AT-BOOT as amended).
--- Unconditional, ahead of the has-a-project check: with no
--- project there is no widget either, so it is a no-op there,
--- and the invariant does not depend on the bookkeeping order.
---
--- Only the widget, deliberately. The whole exit path belongs
--- here — `stop_project_run` fires `compy.before_exit` and
--- tears the handlers down, and `quit_project` calls it before
--- closing. Whether its absence here was purposeful is not
--- established, so this does the narrow correct thing rather
--- than guess. See doc/development/technical_debt/input.md,
--- "`close_project` bypasses the run's exit path".
function ConsoleController:close_project()
  destroy_input_widget()
  local P = self.model.projects
  local open = P.current
  if open then
    local name = P.current.name
    local ok = P:close()
    local lf = self:get_loader(name)
    if lf then
      table.delete_by_value(package.loaders, lf)
    end
    self:_reset_executor_env()
    self.model.output:clear_canvas()
    View.clear_snapshot()
    love.state.app_state = 'ready'
    return ok
  end
  return true
end

--- @return Project?
function ConsoleController:get_current_project()
  local P = self.model.projects
  return P.current
end

function ConsoleController:evacuate_required()
  local open = self:get_current_project()
  if not open then return end
  local files = open:contents()
  local lua = '.lua$'
  for _, v in ipairs(files) do
    if string.matches(v.name, lua, true) then
      local fn = v.name
      local modname = fn:gsub(lua, '')
      if package.loaded[modname] then
        package.loaded[modname] = nil
      end
    end
  end
end

function ConsoleController:stop_project_run()
  self:evacuate_required()
  local compy = self:get_project_env().compy
  framework_before_exit(compy)
  self.main_ctrl.set_default_handlers(self, self.view)
  self.main_ctrl.set_love_update(self)
  -- After framework_before_exit above: the project's own
  -- before_exit hook may still drive compy.input, and it must
  -- find a widget there when it does.
  destroy_input_widget()
  View.clear_snapshot()
  self.main_ctrl.set_love_draw(self, self.view)
  self.main_ctrl.clear_user_handlers(self)
  -- The program's serial handlers go with its other handlers:
  -- a stopped project must not keep hearing the board.
  SerialPort:programEnded()
  self.main_ctrl.report()
  love.state.app_state = 'project_open'
end

function ConsoleController:quit_project()
  self:stop_project_run()
  self:close_project()
  self.model.output:reset()
  self.input:reset()
end

--- @param name string
--- @param state EditorState
function ConsoleController:edit(name, state)
  if love.state.app_state == 'running' then return end

  local PS = self.model.projects
  local p  = PS.current
  if not p then return end
  local filename
  -- if state and state.buffer then
  --   filename = state.buffer.filename
  -- else
  filename    = name or ProjectService.MAIN
  -- end
  local fpath = p:get_path(filename)
  local ex    = FS.exists(fpath)
  local text
  if ex then
    text = self:_readfile(filename)
  end

  if love.state.app_state ~= 'editor' then
    love.state.prev_state = love.state.app_state
    love.state.app_state = 'editor'
  end
  --- Editor accept path: a save is durable before the
  --- editor reports acceptance (spec 2.6), so a force-stop
  --- after an accepted edit cannot lose it. fsync only
  --- here — writefile and bulk paths stay async.
  local save = function(newcontent)
    local ok, err = self:_writefile(filename, newcontent)
    if ok then FS.fsync(fpath) end
    return ok, err
  end

  self.editor:open(filename, text, save)
  self.editor:restore_state(state)
end

--- @return EditorState?
function ConsoleController:close_buffer()
  self.editor:close_buffer()
end

--- @return EditorState?
function ConsoleController:finish_edit()
  self.editor:save_state()
  self.editor:close()
  local ok = true
  local errs = {}
  if ok then
    love.state.app_state = love.state.prev_state
    love.state.prev_state = nil
  else
    print(string.unlines(errs))
  end
  self.buffers = {}
  return self.editor:get_state()
end

--- Handlers ---

--- @param t string
function ConsoleController:textinput(t)
  if love.state.app_state == 'editor' then
    self.editor:textinput(t)
  elseif self.cfg.mode == 'play' then
    --- console is disabled in this mode
  else
    local input = self.input
    if input:has_error() then
      input:clear_error()
    else
      if Key.ctrl() and Key.shift() then
        return
      end
      input:textinput(t)
    end
  end
end

--- @param k string
function ConsoleController:keypressed(k)
  local input = self.input

  local function terminal_test()
    local out = self.model.output
    if love.state.app_state ~= 'ready' then
      return
    end
    if not love.state.testing then
      love.state.testing = 'running'
      input:discard_draft()
      TerminalTest.test(out.terminal)
    elseif love.state.testing == 'waiting' then
      TerminalTest.reset(out.terminal)
      love.state.testing = false
    end
  end

  if love.state.app_state == 'editor' then
    self.editor:keypressed(k)
  else
    if love.state.testing == 'running' then
      return
    end
    if love.state.testing == 'waiting' then
      terminal_test()
      return
    end

    if input:has_error() then
      if k == 'space' or Key.is_enter(k)
          or k == "up" or k == "down" then
        input:clear_error()
      end
      return
    end

    if k == "pageup" then
      input:history_back()
    end
    if k == "pagedown" then
      input:history_fwd()
    end
    -- History navigation at the vertical boundary is driven by
    -- the widget's on_limit_reached callback (set at
    -- construction), not by keypressed's return value (retired,
    -- doc/development/decisions/input.md, D-EDIT-CALLBACKS).
    -- keypressed still runs for its editing side effects; its
    -- return is unused.
    input:keypressed(k)
    if not Key.shift() and Key.is_enter(k) then
      if not input:has_error() then
        self:evaluate_input()
      end
    end

    -- Ctrl held
    if Key.ctrl() then
      if k == "l" then
        self.model.output:reset()
      end
      if love.DEBUG then
        if Key.alt() and k == 't' then
          terminal_test()
          return
        end
      end
    end
  end
  input:update_view()
end

--- @param k string
function ConsoleController:keyreleased(k)
  self.input:keyreleased(k)
  self.input:update_view()
end

--- @param x integer
--- @param y integer
--- @param btn integer
--- @param touch boolean
--- @param presses number
function ConsoleController:mousepressed(
    x, y, btn, touch, presses)
  if love.DEBUG then
    Log.info(string.format('click! {%d, %d}', x, y))
  end
  if love.state.app_state == 'editor' then
    if self.cfg.editor.mouse_enabled then
      self.editor:mousepressed(x, y, btn, touch, presses)
    end
  else
    self.input:mousepressed(x, y, btn, touch, presses)
  end
end

--- @param x integer
--- @param y integer
--- @param btn integer
--- @param touch boolean
--- @param presses number
function ConsoleController:mousereleased(
    x, y, btn, touch, presses)
  if love.state.app_state == 'editor' then
    if self.cfg.editor.mouse_enabled then
      self.editor.input:mousereleased(x, y, btn, touch, presses)
    end
  else
    self.input:mousereleased(x, y, btn, touch, presses)
  end
end

--- @param x number
--- @param y number
--- @param dx number
--- @param dy number
--- @param touch boolean
function ConsoleController:mousemoved(x, y, dx, dy, touch)
  if love.state.app_state == 'editor' then
    if self.cfg.editor.mouse_enabled then
      self.editor.input:mousemoved(x, y, dx, dy, touch)
    end
  else
    self.input:mousemoved(x, y, dx, dy, touch)
  end
end

--- @param x number
--- @param y number
function ConsoleController:wheelmoved(x, y)
  if love.state.app_state == 'editor' then
    if self.cfg.editor.mouse_enabled then
      self.editor.input:wheelmoved(x, y)
    end
  else
    self.input:wheelmoved(x, y)
  end
end

--- @param id userdata
--- @param x number
--- @param y number
--- @param dx number?
--- @param dy number?
--- @param pressure number?
function ConsoleController:touchpressed(id, x, y,
                                        dx, dy, pressure)
  if love.state.app_state == 'editor' then
    if self.cfg.editor.touch_enabled then
      self.editor.input:touchpressed(id, x, y, dx, dy, pressure)
    end
  else
    self.input:touchpressed(id, x, y, dx, dy, pressure)
  end
end

--- @param id userdata
--- @param x number
--- @param y number
--- @param dx number?
--- @param dy number?
--- @param pressure number?
function ConsoleController:touchreleased(id, x, y,
                                         dx, dy, pressure)
  if love.state.app_state == 'editor' then
    if self.cfg.editor.touch_enabled then
      self.editor.input:touchreleased(id, x, y,
        dx, dy, pressure)
    end
  else
    self.input:touchreleased(id, x, y, dx, dy, pressure)
  end
end

--- @param id userdata
--- @param x number
--- @param y number
--- @param dx number?
--- @param dy number?
--- @param pressure number?
function ConsoleController:touchmoved(id, x, y,
                                      dx, dy, pressure)
  if love.state.app_state == 'editor' then
    if self.cfg.editor.touch_enabled then
      self.editor.input:touchmoved(id, x, y, dx, dy, pressure)
    end
  else
    self.input:touchmoved(id, x, y, dx, dy, pressure)
  end
end

--- @return Terminal
function ConsoleController:get_terminal()
  return self.model.output.terminal
end

--- @return love.Canvas
function ConsoleController:get_canvas()
  return self.model.output.canvas
end

--- @param f function
--- @return any ... result of f
function ConsoleController:use_canvas(f)
  local canvas = self.model.output.canvas
  gfx.setCanvas({
    canvas, -- this is actually [1] = canvas
    stencil = true
  })
  local r = { pcall(f) }
  gfx.setCanvas()
  if not r[1] then error(r[2], 0) end
  return unpack(r, 2)
end

--- @return ViewData
function ConsoleController:get_viewdata()
  return {
    w_error = self.input:get_wrapped_error(),
  }
end

function ConsoleController:autotest()
  --- @diagnostic disable-next-line undefined-global
  local autotest = prequire('tests.autotest')
  if autotest then
    autotest(self)
  end
end
