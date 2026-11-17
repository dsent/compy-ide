require("view.input.userInputView")
require("controller.editorController")
require("controller.userInputController")
require("controller.projectInputController")


local class = require('util.class')
local Blink = require('view.input.cursorBlink')
local LANG = require("util.eval")
local FS = require('util.filesystem')
local End = require('util.program_end')
local display = require('conf.display')
local Application = require('util.application')
local usb = require('util.usb')
require("util.key")
require("util.table")
local TerminalTest = require("util.test_terminal")
local KeyCard = require('model.editor.keyCard')
local ConsoleKeys = require('model.input.consoleKeys')

--- What the console's commands say when they refuse: in the
--- output, through CanvasModel:write_refusal (the maintainer's
--- ruling of November 15, 2026)
local messages = {
  nothing_running = 'Nothing is running.',
  nothing_paused  = 'Nothing is paused.',
  already_running = 'A project is already running: Ctrl+Q stops it.',
  needs_a_name    = 'A project needs a name: project("name").',
  --- the reset specification's scoped resets are later work
  --- (Beads compy-ide-reset-runtime-reset)
  reset_alone     = 'Only reset() exists yet, with nothing between the brackets.',
  --- the reset specification's IS4.1
  reset_done      = function(project)
    return 'Runtime reset for ' .. project .. '. All files kept.'
  end,
  --- only a card that cannot hold scratchpad leaves none open
  no_project      = 'No project is open: the SD card cannot be used.',
  --- a pause shows the console; a picture the program drew
  --- waits behind it (decision 7 of November 17, 2026, after
  --- the maintainer's "press F12 to see the drawing canvas")
  picture_hint    = 'F12 shows the picture',
  --- run() makes no project: project() does
  no_such_project = function(name)
    return string.format('There is no project %s: project(%q) creates it.',
      name, name)
  end,
}
--- the modules programs loaded first, by name
local program_loaded = { }

--- What a program set in the graphics state goes when its run
--- ends for good (a stop, Ctrl+Q, an error in its first lines,
--- a project's close) and again before the next run, never at
--- a pause: LÖVE's own reset (colour, background colour,
--- blending, colour mask, scissor, shader, stencil test,
--- wireframe, lines, points, the current transform), and what
--- it pushed and never popped, first, so that no pop('all')
--- brings its state back: a stop, a run or a reset a program
--- asks for is made once its code has returned
--- (util.program_end), so no push of the program's own is still
--- to be popped. The IDE's own pushes (view.ownState, the draw
--- wrapper) stay: none is popped while one is under way
--- (util.program_end's ide_pushes). The canvas is the IDE's: the
--- one bound stays bound. The font is the IDE's too, and
--- run_project sets it after.
local function reset_graphics()
  --- the target bound now: a push the program left saved the
  --- state it was made in, its canvas bound, and popping it puts
  --- that binding back (round c2's first finding)
  local canvas = gfx.getCanvas()
  if End.ide_pushes == 0 and gfx.getStackDepth then
    while gfx.getStackDepth() > 0 do gfx.pop() end
  end
  gfx.reset()
  if canvas then gfx.setCanvas({ canvas, stencil = true }) end
end

--- @class ConsoleController
--- @field typing integer? --- the depth of program code a typed line runs at
--- @field forget_question function? --- drops compy.ask's armed question (the simple surface's)
--- @field time number
--- @field model Model
--- @field main_ctrl table
--- @field pre_env LuaEnv
--- @field base_env LuaEnv
--- @field project_env LuaEnv
--- @field loaders function[]
--- @field input UserInputController
--- @field editor EditorController
--- @field view ConsoleView?
--- @field cfg Config
--- @field paused_mouse table? the paused program's, see suspend
--- @field run_live boolean? the run is not stopped
--- @field collect_garbage function? --- collectgarbage, or a stand-in in tests
--- @field state_left boolean? --- a typed line left state the flush has not ended
--- @field entry string? --- the file the live run runs from, nil for main.lua
--- methods
--- @field edit function
--- @field finish_edit function
ConsoleController = class.create()

--- @param M Model
function ConsoleController.new(M, main_ctrl)
  -- a project's love is a copy of this one: its quits must be
  -- tagged before the copy is made (Application.tag_quits)
  Application.tag_quits(love and love.event)
  local pre_env = table.clone(getfenv())
  local config = M.cfg
  pre_env.font = config.view.font
  local IC = UserInputController(M.input)
    :always_shown()
    -- Escape clears the console line, because this instance
    -- asks for it rather than because the widget destroys
    -- unconditionally (doc/development/decisions/input.md,
    -- D-LIFECYCLE-FLAGS, statement 3). The line never ran, so
    -- the history does not keep it.
    :seat_lifecycle({ clear_on_cancel = true })
    -- its errors show as the editor's do, in the notice band
    -- above the status line (the ruling "The console shows an
    -- error as the editor does")
    :messages_above()
  -- Console history navigation: at the vertical boundary the
  -- widget fires on_limit_reached; the console maps up/down to
  -- history back/forward (doc/development/decisions/input.md,
  -- D-EDIT-CALLBACKS), retiring the old keypressed
  -- return-value channel. The walk is the classic shell's
  -- (model/input/history.lua).
  IC.callbacks.on_limit_reached = function(dir)
    if dir == 'up' then IC:history_back() end
    if dir == 'down' then IC:history_fwd() end
  end
  local self = setmetatable({
    time        = 0,
    model       = M,
    main_ctrl   = main_ctrl,
    input       = IC,
    -- copy of the application's env before the prep
    pre_env     = pre_env,
    -- the project env where we make the API available
    base_env    = {},
    -- this is the env in which the user project runs
    -- subject to change, for example when switching projects
    project_env = {},

    loaders     = {},
    --- the keys whose press reached the console's own key
    --- handler, until their release (EditorController.pressed)
    pressed     = {},

    view        = nil,

    cfg         = config
  }, ConsoleController)
  --- the editor has to know about us
  local EC = EditorController(M.editor, self)
  self.editor = EC
  --- the console's status line names the open project (FR4.6)
  M.input.project_source = function()
    local p = M.projects and M.projects.current
    return p and p.name
  end
  --- and the screen's mode, where it shows (model/screenModel.lua)
  M.input.screen_source = function()
    return M.screen and M.screen:get()
  end
  -- initialize the user environment
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
    --- a stop, a run or a reset the code asked for ends it
    --- here, no error, and is made once it has returned
    --- (util.program_end): the run is still the one that began
    ok, call_err = End.call(f)
    if project_path and ok then
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
--- path cannot grow its own arrangement. The framework's forced
--- restore of global device state is flush_program_state, which
--- calls this first on a stop, and only removes the hook on a
--- crash. See
--- doc/development/technical_debt/input.md, "A project that
--- raises leaves global device state dirty".
---
--- Uninstalling AFTER the call, never before, is what makes a
--- parting reinstallation from inside the hook unreachable.
--- @param compy table
local function framework_before_exit(compy)
  local project_hook = compy.before_exit
  if project_hook then
    --- a lifecycle call in the hook ends it and is dropped: the
    --- stop under way goes on (util.program_end)
    local ok, err = End.call(project_hook)
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
--- The console's and the editor's widgets are
--- unaffected: those surfaces live as long as the app does.
--- Its own evaluator, NOT the shared `InputEvalText` instance:
--- the evaluator resolves this widget's highlighter slot
--- (`bind_highlighter`), so a shared one would resolve every
--- widget's highlighter to whichever bound it last. The
--- evaluator is part of what the run owns.
--- @param cfg table
--- @param on_accepted function --- called as the field takes an
---   answer
local function build_input_widget(cfg, on_accepted)
  local eval = Evaluator.plain('text input')
  local model = UserInputModel(cfg, eval)
  local widget = UserInputController(model)
  widget.on_accepted = on_accepted
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
--- 'running' → 'ready' transition — a non-blocking
--- project lives idle and still owns its widget
--- there (D-ROUTE-LIFETIME, and the asymmetry its amendment
--- deleted).
local function destroy_input_widget()
  hide_input_widget()
  love.state.user_input_controller = nil
end

--- The mouse as the console needs it: absolute, free, shown,
--- with the system cursor. A program may capture it (relative
--- mode is pointer capture on Android, where the pointer then
--- hides and moves a cursor nobody sees) and leave it so.
local CONSOLE_MOUSE = {
  relative = false, grabbed = false, visible = true,
}

--- @return table? mouse what the program has set, for set_mouse
local function get_mouse()
  local m = love.mouse
  if not m then return end
  return {
    relative = m.getRelativeMode(),
    grabbed = m.isGrabbed(),
    visible = m.isVisible(),
    cursor = m.isCursorSupported() and m.getCursor() or nil,
  }
end

--- @param mouse table? from get_mouse, or CONSOLE_MOUSE
local function set_mouse(mouse)
  local m = love.mouse
  if not (m and mouse) then return end
  m.setRelativeMode(mouse.relative)
  m.setGrabbed(mouse.grabbed)
  m.setVisible(mouse.visible)
  if m.isCursorSupported() then m.setCursor(mouse.cursor) end
end

--- @param cc ConsoleController
local function close_project(cc)
  local ok = cc:close_project(function()
    print('Project closed')
  end)
  if not ok then
    Log.err('error in closing')
  end
end

--- The open project, or nil after saying why there is none.
--- A project is always open (open_project); only an SD card
--- that cannot hold scratchpad, when a project closes or the
--- IDE starts, leaves none, and every command that needs one
--- asks here.
--- @return Project?
function ConsoleController:open_or_refuse()
  local p = self.model.projects.current
  if not p then
    self.model.output:write_refusal(messages.no_project)
  end
  return p
end

--- Format a project file the way the editor's Alt+F
--- formats it, at a Compy's width: the REPL's `tidy(name)`.
--- The file is written with LF line ends (BufferModel:save).
--- It writes only when the text changes, and says why when
--- it leaves the file alone.
--- @param name string
--- @return boolean tidy --- the file is formatted now
function ConsoleController:tidy(name)
  local PS = self.model.projects
  local p = self:open_or_refuse()
  if not p then return false end
  local said = self.model.output
  if not FS.exists(p:get_path(name)) then
    said:write_refusal(PS.messages.not_in_project(name))
    return false
  end
  local text = self:_readfile(name)
  if not text then return false end
  local buf = BufferModel(name, text, function(out)
    return self:_writefile(name, out)
  end)
  local lines = buf:snapshot().lines
  local out, formatted, why = buf.syntax.format(lines,
    display.columns)
  if not formatted then
    said:write_refusal(name .. ' ' .. why)
    return false
  end
  if string.unlines(out) == string.unlines(lines) then
    return true
  end
  buf:replace_text(out)
  local ok, err = buf:save()
  if not ok then
    said:write_refusal(err)
    return false
  end
  return true
end

--- @param name string
--- @param quiet boolean? a missing file is not said
--- @return string?
function ConsoleController:_readfile(name, quiet)
  local PS              = self.model.projects
  local p               = PS.current
  local ok, text_or_err = p:readfile(name)
  if ok then
    return text_or_err
  elseif not quiet then
    self.model.output:write_refusal(text_or_err)
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
--- @param content str --- lines, or the file's text
--- @return boolean success
--- @return string? err
--- @param project Project? --- default: the current one
--- @param durable boolean? --- see Project:writefile
function ConsoleController:_writefile(name, content, project,
                                      durable)
  local P = self.model.projects
  local p = project or P.current
  local text = string.unlines(content)
  return p:writefile(name, text, durable)
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
    self.model.output:write_refusal(err)
  end
end

--- @return boolean
local function on_android()
  return love.system.getOS() == 'Android'
end

--- Put a hex file on the micro:bit. On Android it goes down
--- the USB cable to the board's interface chip, never to its
--- drive: this returns at once, and the console says how it
--- goes and how it ended. On a desktop it is written to the
--- board's drive.
--- @param content any
--- @param on table? on Android: on.read(image) hears the
---   file read, on.sending() the sending begin, on.took() the
---   board take it
--- @return boolean? success
--- @return string? err
function ConsoleController:flash_microbit(content, on)
  local width = self.model.output.terminal.width
  local ok, err
  if on_android() then
    ok, err = SerialPort:flash(content, function(line)
      print(ConsoleController.wrapped(line, width))
    end, on)
  else
    ok, err = self:flash_to_drive(content)
  end
  if err then err = ConsoleController.wrapped(err, width) end
  return ok, err
end

--- A line broken between words to the console's width, which
--- breaks a longer line where it falls, mid-word
--- @param text string
--- @param width integer
--- @return string
function ConsoleController.wrapped(text, width)
  return table.concat(string.wrap_words(text, width), '\n')
end

--- @param content any
--- @return boolean? success
--- @return string? err
function ConsoleController:flash_to_drive(content)
  local p = self:open_or_refuse()
  if not p then
    return false
  end
  -- the board restarts with the new firmware, and what was
  -- queued for the old one would be typed into its new REPL
  SerialPort:drop()
  return p:flash_microbit(content)
end

--- Look for the micro:bit. On Android it is the board the
--- USB serial connection has open, named by the unique id
--- its chip gave, or 'micro:bit' until it has. On a desktop
--- it is the board's drive, whose path is kept in
--- love.paths.microbit_path.
--- @return string? found nil if no board is plugged in
function ConsoleController:detect_microbit()
  if on_android() then
    if not SerialPort:isConnected() then return nil end
    local board = SerialPort:board()
    return board and board.id or 'micro:bit'
  end
  local path = usb.detect()
  if type(love) == 'table' and love.paths then
    love.paths.microbit_path = path
  end
  return path
end

_G.o_loadfile = _G.loadfile
--- @param name string
--- @return function?
function ConsoleController:loadfile(name)
  local PS    = self.model.projects
  local p     = PS.current
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
--- @param stopped boolean? --- the caller has just stopped
---   what was live (restart, Ctrl+R): the seam does not again
--- @param entry string? --- a file of the project to run as the
---   program, main.lua when nil (run(nil, "second.lua"), Option
---   2 of the multi-entry-point proposal)
function ConsoleController:run_project(name, stopped, entry)
  --- what the program's first lines ask for (a stop, a run) is
  --- made once the run has begun (util.program_end)
  return End.held(self._run_project, self, name, stopped, entry)
end

--- Whether a run of `name`'s `entry` can start, said in the
--- output when it cannot; nothing changes either way. Asked
--- again when the run is made: a program's run() is refused at
--- the call, its code going on, and made after the code ends.
--- @param name string?
--- @param entry string?
--- @return boolean accepted
--- @param replaces boolean? --- a program's own run(): it
---   replaces the program that runs, as Ctrl+R does
function ConsoleController:_run_accepted(name, entry, replaces)
  if not replaces and (love.state.app_state == 'inspect' or
      love.state.app_state == 'running')
  then
    self.model.output:write_refusal(messages.already_running)
    return false
  end
  local P   = self.model.projects
  local cur = P.current
  if not name and not self:open_or_refuse() then return false end
  --- a run opens a project it names and makes none: a name
  --- no project has is refused, and nothing changes
  if name and not (cur and cur.name == name) then
    local valid, invalid = ProjectService.valid_name(name)
    if not valid then
      self.model.output:write_refusal(invalid)
      return false
    end
    if not ProjectService.is_project(ProjectService.path, name) then
      self.model.output:write_refusal(messages.no_such_project(name))
      return false
    end
  end
  --- an entry point is a file the project holds, named as files
  --- are, checked before anything changes
  if entry then
    local valid, invalid = Project.writable_name(entry)
    if not valid then
      self.model.output:write_refusal(invalid)
      return false
    end
    local holder = (name and not (cur and cur.name == name))
        and FS.join_path(
          ProjectService.is_project(ProjectService.path, name), entry)
        or cur:get_path(entry)
    if not FS.exists(holder, 'file') then
      self.model.output:write_refusal(P.messages.not_in_project(entry))
      return false
    end
  end
  --- the file to run must give its text, as ProjectService:run
  --- reads it (round 17): one that cannot be read is refused
  --- before anything ends
  local file = entry or ProjectService.MAIN
  local holder = (name and not (cur and cur.name == name))
      and { path = ProjectService.is_project(ProjectService.path, name) }
      or cur
  --- the open project reads as it reads itself; another, by
  --- its path, as Project:readfile reads
  local read = holder and (holder.readfile
    or (holder.path and Project.readfile))
  if read then
    local readable, why = read(holder, file)
    if not readable then
      self.model.output:write_refusal(why)
      return false
    end
  end
  return true
end

--- @private
function ConsoleController:_run_project(name, stopped, entry)
  if not self:_run_accepted(name, entry) then return end
  --- a program takes the keys from here: the screen at rest
  --- under it, never a scrolled view no key reaches
  self.model.output:to_rest()
  local P   = self.model.projects
  local cur = P.current
  local ok, opened
  if cur and (not name or cur.name == name) then
    ok = true
  else
    ok = self:open_project(name or '', false)
    opened = true
  end

  if ok then
    --- The run seam, one thing (the maintainer's ruling "A run
    --- starts from a clean environment"): end a run that is
    --- live exactly as a stop does (its handlers, input hooks
    --- and shortcuts, before_exit, serial handlers, widget,
    --- modules); with nothing live there is nothing to end, and
    --- only the modules go. Then a new environment, as opening
    --- the project makes it, then start. Opening another
    --- project has just done both. What a run leaves stays for
    --- inspection until the next run; continue() and dofile()
    --- never pass here.
    --- a stop is the flush, which makes the environment anew
    --- and resets the graphics state; with nothing live, the
    --- seam does those itself
    if not opened then
      if stopped then
        --- the caller stopped (Ctrl+R)
      elseif self.run_live then
        self:stop_project_run()
      else
        self:evacuate_required()
        self:_reset_executor_env()
        reset_graphics()
        --- the slots every environment shares, which a new one
        --- does not clear: what typed lines set there goes, as
        --- at reset(), an exit hook removed and not called
        --- (round 21: a run starts clean)
        self:get_project_env().compy.before_exit = default_before_exit
        self.main_ctrl.clear_user_handlers(self)
        SerialPort:programEnded()
      end
    end
    local runner_env = self:get_project_env()
    -- A run starts on a blank canvas, whatever the last one
    -- left there; a project that fails to load leaves the
    -- error on a blank console, not under the old picture.
    -- Its text shows until it draws.
    self.model.output:clear_canvas()
    self.model.screen:run_starts()
    --- the project to run is the open one by now: it is not
    --- looked for again
    local f, load_err, path, refused = P:run(nil, runner_env, entry)
    if f then
      --- the entry point this run runs from, which Ctrl+R
      --- restarts while it is live; the run's end forgets it
      self.entry = entry
      local n = name or P.current.name or 'project'
      Log.info('Running \'' .. n .. '\'')
      self:restore_console_mouse()
      self.run_live = true
      love.state.app_state = 'running'
      -- Before the project's top-level code, which may show the
      -- widget on its first line. This is the run seam, chosen
      -- over the OPEN seam because restart() and the Ctrl+T
      -- quickswitch call stop+run directly, never re-open:
      -- construct-at-open would leave every restart on the
      -- previous run's widget.
      --- an answer the program's field takes brings the output's
      --- screen back, as a console line that runs does
      build_input_widget(self.cfg, function()
        self.model.output:to_rest()
      end)
      --- its status line names the screen's mode, as the
      --- console's does (round j1)
      local field = love.state.user_input_controller
      if field then
        field.model.screen_source = function()
          return self.model.screen:get()
        end
      end
      -- The program speaks for the board from here on; the
      -- console's own listeners wait until it has stopped.
      SerialPort:programStarted()
      gfx.setFont(self.cfg.view.font)
      --- a stop or a run the first lines ask for is made after
      --- this one has finished starting (util.program_end)
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
        -- ...then the one flush, as a stop's: nothing survives
        -- the project that raised, its globals included.
        -- before_exit is removed but NOT called: the hook is
        -- scoped to stop paths and excludes a crash.
        self:flush_program_state(false)
        self.model.output:write_error('Error: ' .. tostring(run_err))
      else
        if not self.main_ctrl.user_is_blocking() then
          -- The route is NOT released here. A non-blocking run
          -- reaching the idle state keeps every channel until
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
          --- a pause the first lines asked for goes on, and
          --- continue() resumes the program idle (p1)
          if love.state.app_state == 'snapshot' then
            love.state.paused_from = 'ready'
          else
            love.state.app_state = 'ready'
            --- a program that can do nothing more has ended: its
            --- natural end is a stop (stage 4)
            if not self.main_ctrl.program_owns_input() then
              self:end_naturally(true)
              return
            end
          end
          -- Without a widget or a pointer handler nothing of the
          -- program answers the pointer, and the console is on
          -- screen: it needs its mouse now, even if keys or the
          -- board still reach the program.
          if not self.main_ctrl.user_is_interactive() then
            self:restore_console_mouse()
          end
        end
      end
    elseif refused then
      self.model.output:write_refusal(load_err)
    else
      self.model.output:write_error(load_err)
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
  end
  --- a module no one had loaded is the program's: the next
  --- run loads it afresh (ConsoleController:evacuate_required).
  --- One the IDE loaded itself stays shared.
  local first = package.loaded[name] == nil
  local m = o_require(name)
  if first then program_loaded[name] = true end
  return m
end

_G.o_dofile = _G.dofile
--- @param cc ConsoleController
--- @param filename string
--- @param env LuaEnv?
local function project_dofile(cc, filename, env)
  local P = cc.model.projects
  local fn = filename
  local open = P.current
  local chunk, load_err = open:load_file(fn)
  if chunk then
    if env then
      setfenv(chunk, env)
    end
    return true, chunk()
  elseif load_err then
    --- the file is there and Lua does not load it
    cc.model.output:write_error(load_err)
  else
    cc.model.output:write_refusal(P.messages.not_in_project(filename))
  end
end


-- Set up audio table
local compy_audio = require("util.audio")
local compy_graphics = {
  shape2d = require("util.graphics.shape2d")
}

--- compy.screen for a program or a typed line: what the screen
--- shows of the console's text and the program's picture
--- (model/screenModel.lua). The maintainer ruled the shape
--- (pre-release rulings, "The picture and the text"); its names
--- are LÖVE's kind (docs: the user API naming proposal).
--- @param cc ConsoleController
--- @return table
local function screen_api(cc)
  local modes = '"text", "combined" or "picture"'
  return {
    --- show(mode): one of the three; a wrong one stops the
    --- program at the line that called it, as gotoxy does
    show = function(m)
      if not ScreenModel.is_mode(m) then
        error('compy.screen.show: the mode is ' .. modes
          .. ', not ' .. (type(m) == 'string'
            and string.format('%q', m) or tostring(m)), 2)
      end
      cc.model.screen:choose(m)
    end,
    --- @return ScreenMode
    getMode = function()
      return cc.model.screen:get()
    end,
  }
end

--- compy.graphics for a program: its shape2d's fills and
--- strokes say that it drew (ConsoleController:drew), as its
--- love.graphics calls do
--- @param cc ConsoleController
--- @return table
local function drawing_graphics(cc)
  local shape2d = { }
  for name, f in pairs(compy_graphics.shape2d) do
    if name:match('_fill$') or name:match('_stroke$') then
      shape2d[name] = function(...)
        cc:drew()
        return f(...)
      end
    else
      shape2d[name] = f
    end
  end
  return { shape2d = shape2d }
end
-- Builds the `compy.terminal` sub-namespace — the console
-- OUTPUT surface. These wrap the live `terminal` (the
-- REPL/console text grid): position the grid cursor
-- (gotoxy) and clear the screen. The grid's cursor is not
-- the program's to show (the maintainer's ruling "Programs
-- lose show_cursor and hide_cursor"). This is
-- where a project WRITES to the console; always present
-- while the project runs. Contrast with `compy.input`
-- below, the input solicitation surface.
local get_compy_terminal = function(terminal)
  return {
    --- What is not a number fails in the program's own call,
    --- on its line; a number written as text moves, as it
    --- always did. The grid puts any number on the grid.
    --- @param x number
    --- @param y number
    gotoxy = function(x, y)
      if not (tonumber(x) and tonumber(y)) then
        error('compy.terminal.gotoxy: x and y must be numbers', 2)
      end
      return terminal:move_to(x, y)
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

--- A cursor a program moves shows steadily for a while, as one
--- a person moves does (H-NFR4.4); a call that leaves it where
--- it was restarts nothing.
--- @param ui UserInputController?
--- @param l integer?
--- @param c integer? --- where the cursor was before the call
local function blink_if_moved(ui, l, c)
  if not ui then return end
  local nl, nc = ui:get_cursor_pos()
  if nl ~= l or nc ~= c then Blink.restart() end
end

--- @param ui UserInputController?
--- @return integer? line
--- @return integer? col
local function cursor_of(ui)
  if ui then return ui:get_cursor_pos() end
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
  local l, c = cursor_of(ui)
  if ui then ui:show(next_cfg) end
  blink_if_moved(ui, l, c)
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
  local ui = get_widget()
  local l, c = cursor_of(ui)
  ui:set_cursor_pos(pair[1], pair[2])
  blink_if_moved(ui, l, c)
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
  local ui = get_widget()
  local l, c = cursor_of(ui)
  ui:set_text(
    checked_text('compy.input.set_text', text), keep_cursor)
  blink_if_moved(ui, l, c)
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
      local l, c = cursor_of(ui)
      ui:clear()
      blink_if_moved(ui, l, c)
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
--- produces text. With Ctrl or Alt held the key is a chord,
--- whose text the event gate stops (Key.chord_text), so a
--- chord over a printable IS reportable. On a computer, AltGr
--- is no Ctrl and no Alt (Key.ctrl, Key.alt): a printable
--- pressed under it arrives as the text the layout composes.
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

  --- A question belongs to the widget it was asked on: one
  --- asked at the console with nothing live, or by a run that
  --- has ended, is forgotten, never restored over a later run's
  --- field (round 22)
  --- @return boolean own --- the question was this widget's
  local function disarm()
    if not armed then return false end
    local saved = armed
    armed = nil
    if saved.widget ~= love.state.user_input_controller then
      return false
    end
    restore_config(input, saved.config)
    return true
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
        armed = { widget = love.state.user_input_controller,
          config = save_config(input) }
      end
      --- a copy: configure merges the widget's callbacks into
      --- the table it is given, and the shared flags would keep a
      --- stopped program's callbacks and environment alive (Beads
      --- compy-ide-ask-flags-keep-a-stopped-programs-callbacks)
      input.configure(table.clone(ASK_FLAGS))
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
      if disarm() then input.hide() end
    end,

    --- The IDE's, never a program's: the program that asked
    --- ends, and its question goes with it, holding neither
    --- its widget nor what its callbacks captured (round 23:
    --- the terminate flush releases what a program created)
    forget = function()
      armed = nil
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
    graphics = cc and drawing_graphics(cc) or compy_graphics,
    screen = cc and screen_api(cc) or nil,
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
    if cc then cc.forget_question = simple.forget end
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

--- Prepare the unified user environment: console commands and
--- project API both live here. The console the user types into is
--- simply the currently open project's environment.
--- @param cc ConsoleController
function ConsoleController.prepare_project_env(cc)
  require("controller.userInputController")
  require("model.input.userInputModel")
  require("view.input.userInputView")
  local cfg                    = cc.model.cfg
  ---@type table
  local project_env            = cc:get_pre_env_c()

  local P                      = cc.model.projects

  -- The env the old prepare_env wired was the global environment,
  -- so its `gfx` write surfaced as the global the console core
  -- (use_canvas) and the projects read; main.lua sets the same
  -- global for the app. Keep that alias on the unified prep.
  gfx                          = love.graphics
  --- A program's screen is its canvas: setCanvas() with no
  --- target binds it, as LÖVE's binds the screen, and
  --- getCanvas() answers nil there, so code written for the
  --- screen draws where it would under LÖVE, a program that
  --- draws through a canvas of its own included. The `gfx`
  --- alias is the same table.
  local program_gfx            = project_env.love.graphics
  --- the screen, as a program names it: no target, nil, or a
  --- table without a canvas, which `{ getCanvas() }` makes there
  local function names_the_screen(n, t)
    if n == 0 or t == nil then return true end
    return n == 1 and type(t) == 'table' and t[1] == nil
  end
  program_gfx.setCanvas        = function(...)
    if names_the_screen(select('#', ...), (...)) then
      return love.graphics.setCanvas({
        cc.model.output.canvas, stencil = true })
    end
    return love.graphics.setCanvas(...)
  end
  program_gfx.getCanvas        = function()
    if love.graphics.getCanvas() == cc.model.output.canvas then
      return nil
    end
    return love.graphics.getCanvas()
  end
  --- the ground a program or a typed line chooses is kept with
  --- its picture, as it is chosen: neither the flush's reset nor
  --- the state a draw gives back after its frame changes it
  --- (rounds c1 and c2)
  program_gfx.setBackgroundColor = function(...)
    love.graphics.setBackgroundColor(...)
    cc.model.output:keep_background(love.graphics.getBackgroundColor())
  end
  --- a pop of the program's puts back the ground its push saved,
  --- as LÖVE's does; one that changes it is a choice too (round
  --- c3)
  program_gfx.pop              = function()
    local r, g, b, a = love.graphics.getBackgroundColor()
    love.graphics.pop()
    local r2, g2, b2, a2 = love.graphics.getBackgroundColor()
    if r ~= r2 or g ~= g2 or b ~= b2 or a ~= a2 then
      cc.model.output:keep_background(r2, g2, b2, a2)
    end
  end
  --- a program's reset() makes its canvas the target, as LÖVE's
  --- makes the screen, and its ground black (round c3)
  program_gfx.reset            = function()
    love.graphics.reset()
    love.graphics.setCanvas({ cc.model.output.canvas, stencil = true })
    cc.model.output:keep_background(love.graphics.getBackgroundColor())
  end
  --- each drawing call says that the program drew
  --- (ConsoleController:drew); clear() erases, and draws none
  for _, name in ipairs({ 'arc', 'circle', 'draw', 'drawInstanced',
    'drawLayer', 'ellipse', 'line', 'points', 'polygon', 'print',
    'printf', 'rectangle' }) do
    program_gfx[name] = function(...)
      cc:drew()
      return love.graphics[name](...)
    end
  end
  project_env.gfx              = program_gfx

  --- @param f function
  local check_microbit_path    = function(f, ...)
    if not love.paths.microbit_path then
      cc.model.output:write_refusal(P.messages.no_microbit_board)
    else
      return f(...)
    end
  end

  project_env.require          = function(name)
    return project_require(name)
  end
  --- `f`, for a command that needs a project: with none open
  --- it says why and does nothing (ConsoleController:open_or_refuse)
  --- @param f function
  --- @return function
  local function needs_project(f)
    return function(...)
      if not cc:open_or_refuse() then return end
      return f(...)
    end
  end

  project_env.dofile           = needs_project(function(name)
    return project_dofile(cc, name, cc:get_project_env())
  end)

  --- project management

  project_env.list_projects    = function()
    local ps = P:list()
    if ps:is_empty() then
      -- no projects, display a message about it
      print(P.messages.no_projects)
    else
      -- below what is on the screen, as list_contents() prints
      -- (the maintainer's ruling "Console scrollback, first
      -- version")
      print(P.messages.list_header)
      for _, p in ipairs(ps) do
        print('> ' .. p.name)
      end
    end
  end

  --- The calls that end or replace a run, made from code, end
  --- that code and are made once it has returned
  --- (util.program_end). A refusal is said at the call, and the
  --- code goes on: nothing ended.

  --- @param name string
  project_env.project          = function(name)
    if not name then
      return cc.model.output:write_refusal(messages.needs_a_name)
    end
    local valid, invalid = ProjectService.valid_name(name)
    if not valid then
      return cc.model.output:write_refusal(invalid)
    end
    return End.request(function() return cc:open_project(name) end)
  end

  project_env.close_project    = function()
    End.request(function() close_project(cc) end)
  end

  project_env.current_project  = needs_project(function()
    print('Currently open project: ' .. P.current.name)
  end)

  project_env.example_projects = function()
    local ok, err = P:deploy_examples()
    if not ok then
      cc.model.output:write_refusal(
        'The examples could not be copied (' .. tostring(err) .. ').')
    end
  end

  project_env.clone            = function(old, new)
    local ok, err = P:clone(old, new)
    if not ok then
      cc.model.output:write_refusal(err)
    end
  end

  --- reset(): the flush, a program live or not, then the
  --- console emptied as Ctrl+L empties it. A program that runs
  --- is stopped, its before_exit called; with nothing live what
  --- typed lines left goes, a before_exit they set removed and
  --- not called.
  project_env.reset            = function(...)
    if select('#', ...) > 0 then
      return cc.model.output:write_refusal(messages.reset_alone)
    end
    return End.request(function() return cc:reset() end)
  end

  project_env.reset_scratchpad = function()
    End.request(function() cc:reset_scratchpad() end)
  end

  --- file access

  project_env.list_contents    = needs_project(function()
    local p = P.current
    local items = p:contents()
    print(P.messages.project_header(p.name))
    for _, f in pairs(items) do
      print('• ' .. f.name)
    end
  end)

  --- @param name string
  --- @param quiet boolean? says nothing when there is no such
  ---   file, for a caller that says it in its own words
  --- @return string?
  project_env.readfile         = needs_project(function(name, quiet)
    --- @diagnostic disable-next-line: invisible
    return cc:_readfile(name, quiet)
  end)

  --- @param name string
  --- @return string[]?
  project_env.readlines        = needs_project(function(name)
    --- @diagnostic disable-next-line: invisible
    return cc:_readlines(name)
  end)

  --- @param name string
  --- @param content string[]
  project_env.writefile        = needs_project(function(name, content)
    return cc:writefile(name, content)
  end)

  --- @param content string
  --- @param on table? see ConsoleController:flash_microbit
  --- @return boolean? success
  --- @return string? err
  project_env.flash_microbit   = function(content, on)
    if on_android() then return cc:flash_microbit(content, on) end
    return check_microbit_path(cc.flash_microbit, cc, content)
  end

  --- look for the micro:bit, see detect_microbit above
  --- @return string? found
  project_env.detect_microbit  = function()
    return cc.detect_microbit(cc)
  end

  --- @param name string
  --- @return function? chunk
  project_env.loadfile         = needs_project(function(name)
    return cc:loadfile(name)
  end)

  --- An edit from a program idle behind the console stops it
  --- first: that edit is made once the program's code returns.
  --- During a stop (in compy.before_exit) it opens nothing and
  --- the hook goes on, as edit() has always done there.
  --- @param name string
  project_env.edit             = function(name)
    if not End.ending and love.state.app_state ~= 'running'
        and cc:_program_live() then
      --- refused at the call, the code going on (round 17)
      if not cc:_edit_admit(name) then return end
      return End.request(function() return cc:edit(name) end)
    end
    return cc:edit(name)
  end

  --- Format a file the way the editor writes code
  --- @param name string? --- default main.lua
  --- @return boolean
  project_env.tidy             = function(name)
    return cc:tidy(name or ProjectService.MAIN)
  end

  --- execution control

  --- @param name string? --- a project, the open one when nil
  --- @param entry string? --- its file to run, main.lua when nil
  --- A typed run() while a program runs or is paused is
  --- refused; a program's own replaces it once its code has
  --- returned: the stop, then the run, as Ctrl+R makes them.
  project_env.run_project      = function(name, entry)
    local replaces = End.user > 0 and End.user ~= cc.typing
        and cc.run_live
    if not cc:_run_accepted(name, entry, replaces) then return end
    End.request(function()
      if replaces then
        cc:stop_project_run()
        cc:run_project(name, true, entry)
      else
        cc:run_project(name, nil, entry)
      end
    end)
  end
  project_env.run              = project_env.run_project

  --- @param msg string?
  project_env.pause            = function(msg)
    if not cc.run_live then
      return cc.model.output:write_refusal(messages.nothing_running)
    end
    cc:suspend_run(msg)
  end
  project_env.stop             = function()
    if not cc.run_live then
      return cc.model.output:write_refusal(messages.nothing_running)
    end
    End.request(function() cc:stop_project_run() end)
  end
  project_env.continue         = function()
    if love.state.app_state == 'inspect' then
      -- resume, in the state the pause found the program in
      love.state.app_state = love.state.paused_from or 'running'
      love.state.paused_from = nil
      SerialPort:programContinued()
      cc.model.output:to_rest()
      cc.model.screen:resume()
      cc.main_ctrl.restore_user_handlers(cc)
      -- After the handlers: a cursor the program has released
      -- raises here, and the program runs on regardless.
      local mouse = cc.paused_mouse
      cc.paused_mouse = nil
      set_mouse(mouse)
    else
      cc.model.output:write_refusal(messages.nothing_paused)
    end
  end

local terminal              = cc.model.output.terminal
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
  --- @param on boolean? false stops it
  --- @param frame string? a line the board is to say a
  ---   program's end in, which echo says in words instead
  --- @param rest string? what the board said before, not
  ---   shown yet, read first as if it came now
  --- @return boolean? true when echo is on, rest taken
  project_env.echo            = function(on, frame, rest)
    local port = SerialPort:table_for('console')
    if on == false then
      SerialPort.echo:off()
      port.onBytes = nil
      return
    end
    SerialPort.echo:on()
    if frame then SerialPort.echo:expect(frame) end
    port.onBytes = function(chunk)
      SerialPort.echo:bytes(chunk)
    end
    if rest then SerialPort.echo:bytes(rest) end
    return true
  end

  local compy_namespace      = get_compy_namespace(terminal,
    true, cc, SerialPort:table_for('program'))
  project_env.compy          = compy_namespace
  project_env.tty            = compy_namespace.terminal

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

  project_env.appver         = function()
    local ver = FS.read('ver.txt', true)
    if ver then print(ver) end
  end

  project_env.quit           = function()
    Application.request_exit()
  end

  local base                 = table.clone(project_env)
  local project              = table.clone(project_env)
  cc:_set_base_env(base)
  cc:_set_project_env(project)
end

---@param dt number
function ConsoleController:pass_time(dt)
  self.time = self.time + dt
  --- a running program's field that comes up while the view is
  --- scrolled brings the screen back, so that its prompt is
  --- seen before any key; a paused program's field waits, and
  --- the keys scroll its output
  local w = love.state.user_input_controller
  local st = love.state.app_state
  local field = self.run_live and (st == 'running' or st == 'ready')
      and w ~= nil and w:is_shown()
  if field and not self.field_shown then
    self.model.output:to_rest()
  end
  self.field_shown = field
  self:fit_output()
  --- the text cursor blinks on the frames' time
  Blink.pass_time(dt)
  self.model.output.terminal:update(dt)
end

--- Whether no input field is drawn: the console's is hidden
--- behind a program that owns the input (ConsoleView:draw), and
--- the program shows none of its own.
--- @return boolean
function ConsoleController:fieldless()
  if not self.main_ctrl.program_owns_input() then return false end
  local w = love.state.user_input_controller
  return not (w ~= nil and w:is_shown())
end

--- With no field drawn under it the output has the field's row.
--- Asked at each frame's step and again as the screen is drawn
--- (ConsoleView:draw): a program's update that shows or hides
--- its field comes between the two, and the grid drawn is as
--- high as the screen that frame shows.
function ConsoleController:fit_output()
  self.model.output:field_drawn(not self:fieldless())
end

--- What the status line says while no field is drawn: the
--- project, the file the run started from, and that it runs.
--- @return Status
function ConsoleController:running_status()
  local P = self.model.projects
  return {
    custom = {
      project = P.current and P.current.name,
      name = self.entry or 'main.lua',
      state = 'running',
    },
    mode = self.model.screen:get(),
  }
end

---@return number
function ConsoleController:get_timestamp()
  return self.time
end

--- What Enter says on a statement that is not finished, when
--- it begins the statement's next line instead of running it
local UNFINISHED = 'Unfinished code: type the rest, then press Enter.'

function ConsoleController:evaluate_input()
  --- what the line asks for (a stop, a run, a reset) is made
  --- once the line and its echo are done (util.program_end)
  return End.held(self._evaluate_input, self)
end

--- @private
function ConsoleController:_evaluate_input()
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
      local run_env = self:get_project_env()
      local f, load_err = codeload(code, run_env)
      if f then
        --- the line is taken: it enters the history and the
        --- output before it runs, and leaves the field however
        --- it ends; Up brings it back. Its error is written to
        --- the output after what it printed, and nowhere else:
        --- the band is the field's, for a line not taken (the
        --- maintainer's rulings of November 15 and 16, 2026)
        inter:remember()
        --- a line that runs brings the output's screen back from
        --- a scrolled view, so that its echo and what it prints
        --- are seen; typing it did not (CanvasModel:to_rest)
        self.model.output:to_rest()
        self.model.output:echo(text)
        --- a typed line leaves state for a flush to end, as a
        --- live run does
        self.state_left = true
        --- the typed line's own depth of program code: a run()
        --- there is the console's, one deeper the program's
        local was = self.typing
        self.typing = End.user + 1
        local _, err = run_user_code(f, self)
        self.typing = was
        if err then
          self.model.output:write_error(err)
        end
        inter:clear_text()
      else
        Log.error('Load error:', LANG.get_call_error(load_err))
        inter:set_error(load_err)
      end
    else
      local eval_err = res
      if eval_err then
        inter:set_error(eval_err)
      else
        --- the statement goes on: Enter has begun its next
        --- line, and says why it ran nothing
        inter:notice({ UNFINISHED })
      end
    end
  end
end

function ConsoleController:_reset_executor_env()
  self:_set_project_env(table.clone(self.base_env))
end

--- The console's reset(): the one flush, then the console's
--- output and kept rows erased, as Ctrl+L erases them; the
--- history and the editor's files stay
function ConsoleController:reset()
  if self.run_live then
    self:stop_project_run()
  else
    self:flush_program_state(false)
  end
  --- a reset is the explicit silence: what a stop lets play out
  --- stops here (the reset specification: a runtime reset stops
  --- audio)
  if love.audio and love.audio.stop then love.audio.stop() end
  self.model.output:erase()
  --- and the picture: the canvas is cleared as the output is
  self.model.output:clear_canvas()
  self.model.screen:ended()
  local P = self.model.projects
  local name = P.current and P.current.name or ProjectService.DEFAULT
  print(messages.reset_done(name))
  --- the reset specification's API4.1; a typed line's value is
  --- not printed, so the console shows only the line above
  return { scope = 'runtime', project = name, snapshot = nil }
end

--- Ctrl+R on a live program: the stop the run seam would make,
--- made first, so that a run that is going or paused ends even
--- when no run can start after it, then a run from the entry
--- point the program was running from (the stop forgets it)
function ConsoleController:restart()
  local entry = self.entry
  self:stop_project_run()
  self:run_project(nil, true, entry)
end

---@return LuaEnv
function ConsoleController:get_pre_env_c()
  return table.clone(self.pre_env)
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
  return self:get_project_env()
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

--- A pause's text with how to see the picture behind it: on the
--- pause's own row, in brackets after its text, where both fit,
--- so that the band covers no more of the output; on a row of
--- its own where they do not (the ruling of November 17, 2026:
--- ASCII alone in the words the screen shows), the text
--- cut to the band's rows less the hint's, as the band cuts a
--- message, so that the hint is always seen; alone after a
--- pause with no text. The text is measured as the band shows
--- it: bytes that are not UTF-8 made shown first (k1).
--- @param text string?
--- @param visible VisibleContent?
--- @return string|string[]
local function with_picture_hint(text, visible)
  local hint = messages.picture_hint
  if not text then return hint end
  local w = visible and visible.wrap_w or 64
  local plain = (string.scrub(text):gsub('\r\n?', '\n'))
  local lines = string.lines(plain)
  if #lines > 1 and lines[#lines] == '' then lines[#lines] = nil end
  local rows = { }
  for _, line in ipairs(lines) do
    for _, row in ipairs(string.wrap_words(line, w)) do
      rows[#rows + 1] = row
    end
  end
  --- a word wider than a row is cut by characters, as the band
  --- cuts it (k2)
  rows = string.wrap_array(rows, w)
  if #rows == 1
      and string.ulen(rows[1]) + 3 + string.ulen(hint) <= w then
    return rows[1] .. ' (' .. hint .. ')'
  end
  local room = UserInputView.NOTICE_ROWS - 1
  if #rows > room then
    for i = #rows, room + 1, -1 do rows[i] = nil end
    rows[room] = string.usub(rows[room], 1, w - 1) .. '…'
  end
  rows[#rows + 1] = hint
  return rows
end

function ConsoleController:suspend()
  if love.state.app_state ~= 'snapshot' then
    return
  end
  local runner_env = self:get_project_env()
  Log.info('Suspending project run')
  love.state.app_state = 'inspect'
  self.model.output:to_rest()
  --- the console shows while the program waits; its picture
  --- stays on its canvas
  self.model.screen:pause()
  --- a pause is the debugger's: what it says shows in the
  --- band as a notice, and the program's screen is not touched
  --- (the maintainer's ruling of November 16, 2026)
  local msg = love.state.suspend_msg
  love.state.suspend_msg = nil
  local says = msg ~= nil and tostring(msg) or nil
  if self.model.output:is_drawn() then
    says = with_picture_hint(says, self.input.model.visible)
  end
  if says then self.input:notice(says) end

  self.model.output:invalidate_terminal()

  -- The console takes over while the program waits: it gets
  -- its mouse, and continue() gives the program back its own.
  self.paused_mouse = get_mouse()
  set_mouse(CONSOLE_MOUSE)
  self.main_ctrl.save_user_handlers(runner_env['love'])
  --- the program's serial handlers wait with it (p1)
  SerialPort:programPaused()
  self.main_ctrl.set_default_handlers(self, self.view)
end

--- @param msg string?
--- A program that runs, or one idle behind the console that
--- can still act (its key handlers alone, say), pauses: the
--- console and its field come back, and continue() gives the
--- program back the state it was paused in
function ConsoleController:suspend_run(msg)
  local st = love.state.app_state
  if st ~= 'running' and not (st == 'ready' and self.run_live
        and self.main_ctrl.program_owns_input()) then
    return
  end
  love.state.paused_from = st
  love.state.app_state = 'snapshot'
  love.state.suspend_msg = msg
end

--- @param name string
--- @param play boolean?
--- @return boolean success
--- @param fresh boolean? --- the environment was just made anew
---   (close_project's flush): it is not made again
function ConsoleController:open_project(name, play, fresh)
  self.model.output:to_rest()
  local P = self.model.projects
  if not name then
    self.model.output:write_refusal(messages.needs_a_name)
    return false
  end
  --- a refused command changes nothing: a name that cannot be
  --- a project's is refused before the open project closes,
  --- its run stopped and its files with it
  if not play then
    local valid, invalid = ProjectService.valid_name(name)
    if not valid then
      self.model.output:write_refusal(invalid)
      return false
    end
  end
  local cur = P.current
  local closed_fresh = false
  if cur then
    --- close directly: no redirect to the default project here,
    --- otherwise its loader would be inserted and leak
    local _, made = self:_close_project()
    closed_fresh = made and not self.stopping
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
    --- env resets on every project switch, once: when closing
    --- the one that was open made it anew, not again
    if not fresh and not closed_fresh then
      self:_reset_executor_env()
    end
  elseif cur then
    --- a project is always open: one that cannot be opened or
    --- made on the card leaves the one that was open, its
    --- loader back in place
    P.current = cur
    local lf = self:get_loader(cur.name)
    if lf and not table.is_member(package.loaders, lf) then
      table.insert(package.loaders, 1, lf)
    end
  end
  if open then
    print('Project ' .. name .. ' opened')
  elseif create then
    print('Project ' .. name .. ' created')
  else
    self.model.output:write_refusal(err)
  end
  return ok
end

--- Close the current project without opening another.
--- @return boolean success
--- Closing ends the project, so it ends the project's run,
--- whatever its state: going, which can reach close_project
--- from its own env; paused in `inspect`; or idle in 'ready'
--- with its handlers still set. The run leaves by its exit
--- path, stop_project_run: compy.before_exit fires, the
--- handlers go, and continue() has nothing to resume.
--- Otherwise a closed project's code ran on in the next one.
--- With nothing running the exit path changes nothing. The
--- project to close is read after it, since a before_exit
--- hook may itself have switched projects.
---
--- The widget ends with the project too (D-WIDGET-AT-BOOT as
--- amended): unconditional, ahead of the has-a-project check,
--- since with no project there is no widget either.
--- @return boolean success
--- @return boolean? fresh --- the stop made the environment anew
function ConsoleController:_close_project()
  local P = self.model.projects
  local fresh
  if P.current then
    fresh = self:stop_project_run()
  end
  --- the editor's files are this project's: they go with it,
  --- after the exit hook the stop runs
  if love.state.app_state == 'editor' then
    self:finish_edit()
  elseif self.editor:get_active_buffer() then
    self.editor:close()
  end
  destroy_input_widget()
  local open = P.current
  if open then
    local name = P.current.name
    --- the project's modules went with the stop above: the
    --- next project, or this one reopened, starts from a new
    --- env, and require runs its files again to fill it
    local ok = P:close()
    local lf = self:get_loader(name)
    if lf then
      table.delete_by_value(package.loaders, lf)
    end
    return ok, fresh
  end
  return true, fresh
end

--- Close the current project and return to the default project.
--- @param closed function? called once the project is closed,
---   before the default one opens
--- @param stopped boolean? --- the caller's stop made the
---   environment anew, so the close's own stop ended nothing
--- @return boolean success
function ConsoleController:close_project(closed, stopped)
  self.model.output:to_rest()
  --- a project that was open was stopped as it closed; when
  --- that stop's flush made the environment anew (not inside
  --- an outer stop, whose flush goes on after) the open does not
  --- make it again
  local reentrant = self.stopping
  local ok, fresh = self:_close_project()
  local flushed = (fresh or stopped) and not reentrant
  if ok then
    if closed then closed() end
    return self:open_project(ProjectService.DEFAULT, nil, flushed)
  end
  return ok
end

--- @return Project?
function ConsoleController:get_current_project()
  local P = self.model.projects
  return P.current
end

--- Forget the modules the open project's loader loaded, and
--- only those: a module of the IDE's that shares a project
--- file's name stays, and one from a subfolder goes
function ConsoleController:evacuate_required()
  --- a bundled library a program loaded first, so that the
  --- next run gets its own copy, its timers and state gone
  for modname in pairs(program_loaded) do
    package.loaded[modname] = nil
  end
  program_loaded = { }
  local open = self:get_current_project()
  if not open then return end
  for modname in pairs(open.required or {}) do
    package.loaded[modname] = nil
  end
  open.required = {}
end

--- Once at a time: a before_exit hook that closes or switches
--- the project reaches here again, and returns at once.
--- The editor steps aside first, its files kept for Ctrl+T:
--- the gate's restart (Ctrl+R) reaches here from it.
function ConsoleController:stop_project_run()
  self.model.output:to_rest()
  if self.stopping then return end
  if love.state.app_state == 'editor' then
    self:hide_editor()
  end
  self.stopping = true
  local ok, res = pcall(self._stop_project_run, self)
  self.stopping = false
  if not ok then
    End.ending = false
    -- A step ahead of the reset raised: the console still
    -- gets its mouse.
    self:restore_console_mouse()
    error(res, 0)
  end
  return res
end

--- Whatever plays goes on to its end, and no longer repeats.
--- LÖVE 11's love.audio.pause() pauses every playing source and
--- returns them, which lists them without a registry; each is
--- made a one-shot and played again from where it was. A source
--- the program paused or stopped is not playing, and stays as it
--- is. One that cannot loop (a queueable one) plays on.
--- the master volume as LÖVE starts it, which the IDE keeps
local IDE_VOLUME = 1

local function end_looping()
  local audio = love.audio
  if not (audio and audio.pause) then return end
  for _, source in ipairs(audio.pause() or { }) do
    pcall(source.setLooping, source, false)
    source:play()
  end
end

--- The mouse as the console needs it (CONSOLE_MOUSE): the
--- flush puts it back, and so do a run's start and a program
--- that idles with nothing that answers the pointer, and
--- main.lua once when the IDE starts.
function ConsoleController:restore_console_mouse()
  self.paused_mouse = nil
  set_mouse(CONSOLE_MOUSE)
end

--- The one flush (Beads compy-ide-terminate-flush; the
--- maintainer's invariant of 2026-06-12): terminating a program
--- returns the IDE to its own baseline, however the program
--- behaved. stop(), Ctrl+Q, a project's close, an error in a
--- program's first lines, the run seam's stop and reset() all
--- end here; a program's natural end and a pause do not.
--- What a program left, globals included, goes; the console's
--- output, kept rows and history and the editor's files stay.
--- Idempotent: safe with nothing run, and twice.
--- @param call_exit boolean? --- a stop calls the program's
---   compy.before_exit before it goes; a crash only removes it
--- @return boolean ended --- there was state to end, and the
---   environment was made anew
function ConsoleController:flush_program_state(call_exit)
  --- Two halves. Ending what a program left happens once for
  --- each end, by construction, as the run seam knows it: there
  --- is something to end while a run is live, a program holds
  --- the screen or waits paused, or a typed line has run since
  --- the last flush, and this flush clears all three; a second
  --- path to the same end (a stop in first lines that then
  --- raise, play mode's quit and its close) finds nothing to
  --- end. Putting the IDE's baseline back is idempotent and
  --- happens every time.
  local was_ending = End.ending
  End.ending = true
  local ended = self.run_live
  local st = love.state.app_state
  --- a program is live: it runs, is paused, or idles with its
  --- handlers or picture
  local live = ended or (st ~= 'ready' and st ~= 'editor')
  local to_end = live or self.state_left
  self.state_left = false
  if to_end then
    -- What the run queued for the board and has not sent goes
    -- first: its before_exit hook may send the board a last
    -- line on purpose, and that one stays.
    SerialPort:drop()
    local compy = self:get_project_env().compy
    --- the hook is a live run's: with none, one a typed line set
    --- is removed and not called (round 22)
    if call_exit and live then
      --- program code, drawing on the program's canvas
      self:use_canvas(function() framework_before_exit(compy) end)
    else
      compy.before_exit = default_before_exit
    end
  end
  --- after the exit hook, which may itself require a module
  self:evacuate_required()
  -- After the project's own hook, which may still use the
  -- mouse as it left it.
  self:restore_console_mouse()
  self.main_ctrl.set_default_handlers(self, self.view)
  self.main_ctrl.set_love_update(self)
  -- After the exit hook: it may still drive compy.input, and
  -- it must find a widget there when it does.
  destroy_input_widget()
  --- a question the program left unanswered goes with its
  --- widget
  if self.forget_question then self.forget_question() end
  -- What the run drew stays on its canvas, a record as the
  -- console's output is, to be seen in a mode that shows it
  -- (the proposal "The Program's Canvas and the Viewing Modes",
  -- built as if accepted on November 17, 2026); a run's start
  -- and reset() clear it. The ground the program chose goes
  -- with the graphics state below; the canvas has kept it as the
  -- program set it (setBackgroundColor, prepare_project_env). The
  -- console shows.
  self.model.screen:ended()
  --- the IDE draws on from here: under the program's scissor,
  --- colour or wireframe its key card and editor came out
  --- clipped and outlined (the device night of November 16)
  reset_graphics()
  --- what the program set playing plays out, and a loop stops
  --- repeating (the maintainer's ruling of November 16, 2026:
  --- "clear the repeat, but what is there, still there");
  --- reset() is the explicit silence
  end_looping()
  --- and at the volume the IDE starts with, LÖVE's own: the IDE
  --- sets none
  if love.audio and love.audio.setVolume then
    love.audio.setVolume(IDE_VOLUME)
  end
  --- the keyboard as the IDE set it at its start (main.lua)
  local kb = love.keyboard
  if kb and kb.setKeyRepeat then kb.setKeyRepeat(true) end
  if kb and kb.setTextInput then kb.setTextInput(true) end
  self.run_live = false
  love.state.paused_from = nil
  --- the entry point lives with the run (the maintainer's
  --- ruling of November 16, 2026)
  self.entry = nil
  self.main_ctrl.set_love_draw(self, self.view)
  self.main_ctrl.clear_user_handlers(self)
  -- The program's serial handlers go with its other handlers:
  -- a stopped project must not keep hearing the board.
  SerialPort:programEnded()
  --- the program's globals go with it (the maintainer's ruling
  --- of November 16, 2026: "a stop clears the globals too");
  --- what a run that ended here held is freed now, twice for
  --- finalizers (with nothing run there is nothing to free)
  if to_end then
    self:_reset_executor_env()
    if ended then
      local collect = self.collect_garbage or collectgarbage
      collect('collect')
      collect('collect')
    end
  end
  self.main_ctrl.report()
  love.state.app_state = 'ready'
  End.ending = was_ending
  return to_end
end

--- A stop is the flush, the program's exit hook called. A
--- paused run (Ctrl+Pause, an error in a handler) has not
--- reached here, nor has one that finished its first lines
--- with nothing live (the sine example): it is idle, not
--- stopped, and its picture and globals stay.
function ConsoleController:_stop_project_run()
  return self:flush_program_state(true)
end

--- A program's natural end: its code has ended and it can no
--- longer act (Controller.program_owns_input). It is the stop's
--- flush, before_exit and sounds playing out included (the
--- maintainer's ruling "The natural end is a stop; the build
--- waits for the canvas", built in stage 4 of the canvas plan).
--- At the end of its first lines a program that drew leaves its
--- picture on show until a key or a click (decision 1 of
--- November 17, 2026); one found ended as an event comes
--- leaves the console, which that event reaches, or the picture
--- when it is on show as the end is made (`shown`; stage 2's k5
--- and k6: the screen after the end is set here, by the end
--- itself, whether it is made at once or once the frame's update
--- returns, after the event that found it).
--- @param at_last_line boolean
--- @param shown ScreenMode? --- what shows as the end is made
function ConsoleController:end_naturally(at_last_line, shown)
  if not self.run_live then return end
  --- a pause, asked for or made, is no end (round c5)
  local st = love.state.app_state
  if st == 'snapshot' or st == 'inspect' then return end
  self:stop_project_run()
  --- read after the stop: what before_exit drew is the picture
  --- too (round j1)
  local drawn = self.model.output:is_drawn()
  if (at_last_line and drawn) or shown == 'picture' then
    self.model.screen:ended_by_itself()
  end
end

function ConsoleController:quit_project()
  local stopped = self:stop_project_run()
  --- a clean console first, so what closing says stays on it
  self.model.output:reset()
  self.input:reset()
  self:close_project(nil, stopped)
end

--- Set the default project aside under a backup name and start
--- it again with factory contents.
--- @return boolean success
function ConsoleController:reset_scratchpad()
  local P = self.model.projects
  local name = ProjectService.DEFAULT
  if P.current and P.current.name == name then
    self:_close_project()
  else
    self:close_project()  --- lands on the scratchpad
    self:_close_project() --- close it directly (no redirect)
  end
  --- the old scratchpad is kept, never deleted
  local kept = P:set_aside(name)
  if kept then
    print(P.messages.kept_as(name, kept))
  else
    self.model.output:write_refusal(P.messages.not_kept(name))
  end
  return self:open_project(name)
end

--- Whether edit() can open `name`, said where the person is
--- when it cannot (the editor's field or the console), nothing
--- changing either way. Asked at a program's edit() before it
--- ends the program's code (util.program_end), and again by the
--- edit itself.
--- @param name string?
--- @param must_exist boolean?
--- @return table? admitted --- p, filename, fpath, text, from_console
function ConsoleController:_edit_admit(name, must_exist)
  local PS = self.model.projects
  local p  = self:open_or_refuse()
  if not p then return end
  local filename = name or ProjectService.MAIN
  local fpath = p:get_path(filename)
  local ex    = FS.exists(fpath)
  --- a refusal is said where the person is: over the
  --- editor's field, or in the console
  local function refuse(msg)
    if love.state.app_state == 'editor' then
      self.editor:refuse({ msg })
    else
      self.model.output:write_refusal(msg)
    end
  end
  --- an edit in progress is resolved first (FR1.2): opening
  --- a file empties the field, and a cut block may be held
  --- nowhere else
  if love.state.app_state == 'editor'
      and self.editor:state_name() ~= 'browsing' then
    refuse('Finish the text first: Enter keeps it, Esc drops it.')
    return
  end
  local from_console = love.state.app_state ~= 'editor'
  --- a file is on the editor's stack once
  if not from_console and self.editor:_find_buffer(fpath) then
    self.editor:refuse({ filename .. ' is already open.' })
    return
  end
  --- a file the editor could never save stays shut: every
  --- submission to it would be refused
  local writable, invalid = Project.writable_name(filename)
  if not writable then
    refuse(string.format(
      '%s cannot be saved (%s), so it cannot be opened.',
      filename, invalid))
    return
  end
  local text
  if ex then
    --- a file that is there and cannot be read stays shut
    --- (IS1.2): opened empty, its first submission would
    --- write over it
    local ok, got = p:readfile(filename)
    if not ok or type(got) ~= 'string' then
      local why = type(got) == 'string' and got ~= ''
          and string.format(' (%s)', got) or ''
      refuse(string.format(
        '%s could not be read%s, so it cannot be opened.',
        filename, why))
      return
    end
    text = got
  end
  if must_exist and not ex then
    self.editor:refuse({ PS.messages.not_in_project(filename) })
    return
  end
  --- admission (IS1.2): text that is not UTF-8 stays shut,
  --- and the caller keeps its file and state (IS1.5)
  if type(text) == 'string' and not utf8.len(text) then
    refuse(filename
      .. ' is not UTF-8 text, so it cannot be opened.')
    return
  end

  return { p = p, filename = filename, fpath = fpath, text = text,
    from_console = from_console }
end

--- Open a file. From the console (edit("name"), or Ctrl+T
--- with no file to go back to) it starts the editor anew,
--- the file alone on its stack (IS1.1): the files a run came
--- from go, as leaving the editor takes them (IS1.6), and
--- Ctrl+T alone goes back to them (IS1.4). From the editor
--- (Ctrl+J) it opens in front of its caller (IS1.5).
--- @param name string?
--- @param must_exist boolean? --- a file followed to (IS1.5)
--- is one the project holds; edit("name") creates its own
function ConsoleController:edit(name, must_exist)
  if love.state.app_state == 'running' then return end
  --- a program's exit hook runs while it stops: showing the
  --- editor stops a live program first (_enter_editor), and
  --- this stop, already under way, returns at once, so a
  --- file asked for then would be asked for without end
  if self.stopping then return end

  local admitted = self:_edit_admit(name, must_exist)
  if not admitted then return end
  local p, filename, fpath = admitted.p, admitted.filename,
      admitted.fpath
  local text, from_console = admitted.text, admitted.from_console

  if not self:_enter_editor() then
    return self:edit(name, must_exist)
  end
  --- a hidden editor holds no edit in progress: a run is
  --- refused during one (refuse_to_leave)
  if from_console then
    self.editor:close()
  end
  --- Editor accept path: a save is durable before the
  --- editor reports acceptance (spec 2.6), so a force-stop
  --- after an accepted edit cannot lose it: the data is
  --- synced before the rename that puts it in place, and the
  --- rename is on the card when it returns, the card being
  --- mounted dirsync (FS.replace). Durable only here —
  --- writefile and bulk paths stay async.
  --- the file's own project, whichever is current by then
  local save = function(newcontent)
    return self:_writefile(filename, newcontent, p, true)
  end
  self.editor:open(filename, text, save, fpath)
end

function ConsoleController:close_buffer()
  self.editor:close_buffer()
end

--- The editor steps aside for a run, its files kept as they
--- are for the way back (IS1.4)
function ConsoleController:hide_editor()
  self.model.output:to_rest()
  self.editor:hide()
  love.state.app_state = love.state.prev_state
  love.state.prev_state = nil
end

--- @private
--- @return boolean --- a program's code can still run: it
--- runs, it is paused, or it idles behind the console with
--- its handlers and hooks still connected (run_live)
function ConsoleController:_program_live()
  local st = love.state.app_state
  return self.run_live == true or st == 'running'
      or st == 'inspect' or st == 'snapshot'
end

--- @private
--- Every way the file editor comes to the screen passes here
--- (Ctrl+T, edit() from the console or from a program):
--- no program runs or idles behind it, so that none of its
--- handlers or hooks takes the editor's keys, or stops,
--- runs or closes the project during an edit (FR1.2). A live
--- program is stopped first, as Ctrl+T stops it, and nothing
--- is shown yet: its exit hook may have changed the project
--- and its files, so the caller asks again.
--- @return boolean entered --- the editor's state is on
function ConsoleController:_enter_editor()
  if love.state.app_state == 'editor' then return true end
  if self:_program_live() then
    self:stop_project_run()
    return false
  end
  love.state.prev_state = love.state.app_state
  love.state.app_state = 'editor'
  self.model.output:to_rest()
  self.editor:came_forward()
  return true
end

--- The editor's files again, as a run left them
--- @return boolean shown --- false when a program had to stop
--- first (_enter_editor)
function ConsoleController:show_editor()
  if not self:_enter_editor() then return false end
  self.editor:show()
  return true
end

--- Leave the editor: its files go (IS1.6)
function ConsoleController:finish_edit()
  self:hide_editor()
  self.editor:close()
end

--- Handlers ---

--- The console's key card while it shows (KeyCard.shows),
--- nil otherwise: the console's own and the one a paused
--- program hands over.
--- @return string[]?
function ConsoleController:key_card()
  if love.state.app_state == 'editor' then return nil end
  if not KeyCard.shows(self.pressed) then return nil end
  return self.view.editor.key_card:console_lines(self.run_live,
    self.input:is_empty())
end

--- Whether a key card shows, the console's or the file
--- editor's, whichever is in front
--- @return boolean
function ConsoleController:card_shows()
  if love.state.app_state == 'editor' then
    return KeyCard.shows(self.editor.pressed)
  end
  return KeyCard.shows(self.pressed)
end

--- A key is released wherever its press went
--- @param k string
function ConsoleController:key_released(k)
  self.pressed[k] = nil
  self.editor:key_released(k)
end

--- @param t string
function ConsoleController:textinput(t)
  if love.state.app_state == 'editor' then
    self.editor:textinput(t)
  elseif self.cfg.mode == 'play' then
    --- console is disabled in this mode
  else
    --- the key card suspends the console's keys (IS3.16)
    if self:key_card() then return end
    local input = self.input
    --- a glyph typed over an error closes it and lands on
    --- the line under it; on the device it may come before
    --- its key press. A chord's own glyph never comes here:
    --- the event gate stops it (Key.chord_text)
    input:clear_error()
    input:textinput(t)
  end
end

--- The debug build's terminal test (Ctrl+Alt+T): it runs,
--- and any key once it waits ends it
function ConsoleController:_terminal_test()
  local out = self.model.output
  if love.state.app_state ~= 'ready' then
    return
  end
  if not love.state.testing then
    love.state.testing = 'running'
    self.input:discard_draft()
    TerminalTest.test(out.terminal)
  elseif love.state.testing == 'waiting' then
    TerminalTest.reset(out.terminal)
    love.state.testing = false
  end
end

--- What the console's key tables' actions do (consoleKeys.lua)
local ACTIONS = {
  none = function() end,
  --- the console's text field's own key
  field = function(cc, k) cc.input:keypressed(k) end,
  run = function(cc)
    if not cc.input:has_error() then cc:evaluate_input() end
  end,
  clear_terminal = function(cc) cc.model.output:erase() end,
  scroll_row = function(cc, k)
    cc.model.output:scroll_row(k == 'up' and -1 or 1)
  end,
  scroll_page = function(cc, k)
    cc.model.output:scroll_page(k == 'pageup' and -1 or 1)
  end,
  --- with text in the field, the field's Home and End
  scroll_end = function(cc, k)
    local out = cc.model.output
    if not cc.input:is_empty() then
      cc.input:keypressed(k)
    elseif k == 'home' then
      out:to_oldest()
    else
      out:to_rest()
    end
  end,
  --- Ctrl+PgUp and Ctrl+PgDn, whatever the field holds
  output_edge = function(cc, k)
    local out = cc.model.output
    if k == 'pageup' then out:to_oldest() else out:to_rest() end
  end,
  terminal_test = function(cc)
    if love.DEBUG then cc:_terminal_test() end
  end,
}

--- The output's own scrolling actions (consoleKeys.lua), which
--- it takes behind a program that leaves them (output_key)
local SCROLLS = {
  scroll_row = true, scroll_page = true, scroll_end = true,
  output_edge = true,
}

--- Rows a wheel's notch scrolls the output
local WHEEL_ROWS = 3

--- The output stays in use behind a program that owns the
--- input (ruling 1.1 of November 17, 2026: "the scrollback
--- area is visible so it takes keys and mouse events that
--- normally belong to it, if the program doesn't take these
--- keys and events"): a key the program's chain left that is
--- one of the output's scrolling keys scrolls it. Home and End
--- go to the oldest row and back to rest, the field being
--- hidden, as Ctrl+PgUp and Ctrl+PgDn do. Nothing else of the
--- console's keys acts.
--- @param k string
--- @param isrepeat boolean?
--- @return boolean scrolled
function ConsoleController:output_key(k, isrepeat)
  local entry = ConsoleKeys:lookup('live', Key.combo(k))
  if not (entry and SCROLLS[entry.act]) then return false end
  if isrepeat and not entry.repeats then return true end
  local out = self.model.output
  if entry.act == 'scroll_end' then
    if k == 'home' then out:to_oldest() else out:to_rest() end
  else
    ACTIONS[entry.act](self, k)
  end
  return true
end

--- The wheel scrolls the output, a notch WHEEL_ROWS rows, in
--- the console and behind a program that left it (ruling 1.1)
--- @param y number
function ConsoleController:output_wheel(y)
  if not y or y == 0 then return end
  local dir = y > 0 and -1 or 1
  for _ = 1, WHEEL_ROWS * math.abs(y) do
    self.model.output:scroll_row(dir)
  end
end

--- In the console a key is looked up by its full chord in the
--- table of the console's state (consoleKeys.lua), then in the
--- text field's (fieldKeys.lua); a chord neither names does
--- nothing.
--- @param k string
--- @param sc string? --- LÖVE's scancode, unused
--- @param isrepeat boolean? --- the key is held
function ConsoleController:keypressed(k, sc, isrepeat)
  local input = self.input
  if love.state.app_state == 'editor' then
    --- a key that took the console to the editor, as Ctrl+T,
    --- brings its screen back too
    self.model.output:to_rest()
    self.editor:keypressed(k, sc, isrepeat)
    input:update_view()
    return
  end
  local chord = Key.combo(k)
  local state = self.run_live and 'live' or 'idle'
  local entry = ConsoleKeys:lookup(state, chord)
  local field = not entry and input:names(chord)
  local bound = entry or field
  --- a held key repeats only if its entry says so, and only
  --- where its press acted: one held since the editor or a
  --- program had it does nothing here
  local repeats = bound and bound.repeats and self.pressed[k]
  if isrepeat and not repeats then return end
  --- a bare F1's press brings the card up; a press the card
  --- holds back is not the console's, so neither are its
  --- repeats (IS3.16)
  local help = chord == KeyCard.KEY
  if help then self.pressed[k] = true end
  if self:key_card() then return end
  if k ~= KeyCard.KEY or help then self.pressed[k] = true end
  if love.state.testing == 'running' then
    return
  end
  if love.state.testing == 'waiting' then
    self:_terminal_test()
    return
  end

  -- A message is a hint that blocks nothing (IS3.14): the
  -- next key dismisses it and does its usual work, Enter and
  -- Escape included. A modifier or a lock alone leaves it.
  if input:has_error() and not Key.is_lone(k) then
    input:clear_error()
  end

  if entry then
    ACTIONS[entry.act](self, k)
  elseif field then
    input:keypressed(k, sc, isrepeat)
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
  elseif not self:key_card() then
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
    --- a release goes where its press went: the gate drops the
    --- release of a press the card held back, and hands this
    --- one the release of a press made before the card (p1)
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
  elseif not self:key_card() then
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
  elseif not self:key_card() then
    self:output_wheel(y)
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
  elseif not self:key_card() then
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
    --- a release goes where its touch began: the gate drops the
    --- release of one the card held back, and hands this one the
    --- release of one begun before the card (p2)
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
  elseif not self:key_card() then
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

--- A stop a program's call asks for is made once the call has
--- returned, off the canvas (util.program_end): nothing the call
--- draws comes after the stop's clear.
--- @param f function
--- @return any ... result of f
--- Run program code, or a typed line, drawing on the program's
--- canvas: every entry point does (top-level code and typed
--- lines, routed events, love.update, love.draw, before_exit).
--- What the code pushed and did not pop is popped when it
--- returns, raised or was ended, before the target goes back: a
--- push saves the state it is made in, the program's canvas
--- bound, and one left behind would bind it again where it is
--- popped (the ruling of November 17, 2026, on rounds c1 and
--- c2).
--- @param f function
function ConsoleController:use_canvas(f)
  local canvas = self.model.output.canvas
  --- inside program code already (a stop's before_exit, a run
  --- a handler starts) the canvas stays bound after
  local outer = gfx.getCanvas()
  local depth = gfx.getStackDepth and gfx.getStackDepth()
  gfx.setCanvas({
    canvas, -- this is actually [1] = canvas
    stencil = true
  })
  local r = { pcall(f) }
  if depth then
    while gfx.getStackDepth() > depth do gfx.pop() end
  end
  if outer == canvas then
    gfx.setCanvas({ canvas, stencil = true })
  else
    gfx.setCanvas()
  end
  if not r[1] then error(r[2], 0) end
  return unpack(r, 2)
end

--- A program or a typed line drew on the program's canvas
--- (through the drawing calls of its love.graphics and
--- compy.graphics, prepare_project_env): the canvas holds a
--- picture, and the screen shows it, a running program's first
--- drawing as its picture, a typed line's under the console's
--- text (ScreenModel). Called for each drawing call, so the
--- common case returns at once.
function ConsoleController:drew()
  local output, screen = self.model.output, self.model.screen
  --- the typed line's own code, not a program's handler it ran
  --- (an owed release at continue(): round c4)
  if self.typing and End.user <= self.typing then
    output.drawn = true
    screen:typed_drew()
    return
  end
  if output.drawn and screen.switched then return end
  output.drawn = true
  screen:program_drew()
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
