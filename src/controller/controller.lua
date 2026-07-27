Prof = require("controller.profiler")
require("view.view")

require("util.string.string")
require("util.key")
local LANG = require("util.eval")
local FS = require("util.filesystem")

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

local _supported = {
  'keypressed',
  'keyreleased',
  'textinput',

  'mousemoved',
  'mousepressed',
  'mousereleased',
  'wheelmoved',

  'touchmoved',
  'touchpressed',
  'touchreleased',
}

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
local function wrap(f, CC, ...)
  if _G.web then
    local ok, r = pcall(f, ...)
    if not ok then
      user_error_handler(CC, r)
    end
    return r
  else
    return xpcall(f, user_error_handler, ...)
  end
end

--- @param userlove table
--- @param CC ConsoleController
local set_handlers = function(userlove, CC)
  --- @param key string
  local function hook_if_differs(key)
    local orig = Controller._defaults[key]
    local new = userlove[key]
    if orig and new and orig ~= new then
      --- @type function
      love[key] = CC:wrap_handler(new, wrap)
    end
  end

  -- input hooks
  for _, k in ipairs(_supported) do
    hook_if_differs(k)
  end
  -- update - special handling, inner updates
  local up = userlove.update
  if up and up ~= Controller._defaults.update then
    user_update = true
    Controller._userhandlers.update = up
  end

  -- drawing - separate table
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
Controller = {
  --- @private
  _defaults = {
    singleclick = function() end,
    doubleclick = function() end,
  },
  --- @private
  _userhandlers = {},

  ----------------
  --  keyboard  --
  ----------------
  --- @private
  --- @param CC ConsoleController
  set_love_keypressed = function(CC)
    local function keypressed(k)
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
      CC:keypressed(k)
    end
    Controller._defaults.keypressed = keypressed
    love.keypressed = keypressed
  end,

  --- @private
  --- @param CC ConsoleController
  set_love_keyreleased = function(CC)
    --- @diagnostic disable-next-line: duplicate-set-field
    local function keyreleased(k)
      CC:keyreleased(k)
    end
    Controller._defaults.keyreleased = keyreleased
    love.keyreleased = keyreleased
  end,

  --- @private
  --- @param CC ConsoleController
  set_love_textinput = function(CC)
    local function textinput(t)
      CC:textinput(t)
    end
    Controller._defaults.textinput = textinput
    love.textinput = textinput
  end,

  -------------
  --  mouse  --
  -------------
  --- @private
  --- @param CC ConsoleController
  set_love_mousepressed = function(CC)
    --- @param x number
    --- @param y number
    --- @param button number
    --- @param touch boolean
    --- @param presses number
    local function mousepressed(x, y, button, touch, presses)
      if love.DEBUG then
        Log.info(string.format('click! {%d, %d}', x, y))
      end
      CC:mousepressed(x, y, button, touch, presses)
    end

    Controller._defaults.mousepressed = mousepressed
    love.mousepressed = mousepressed
  end,

  --- @private
  --- @param CC ConsoleController
  set_love_mousereleased = function(CC)
    --- @param x number
    --- @param y number
    --- @param button number
    --- @param touch boolean
    --- @param presses number
    local function mousereleased(x, y, button, touch, presses)
      CC:mousereleased(x, y, button, touch, presses)
    end

    Controller._defaults.mousereleased = mousereleased
    love.mousereleased = mousereleased
  end,

  --- @private
  --- @param CC ConsoleController
  set_love_mousemoved = function(CC)
    --- @param x number
    --- @param y number
    --- @param dx number
    --- @param dy number
    --- @param touch boolean
    local function mousemoved(x, y, dx, dy, touch)
      CC:mousemoved(x, y, dx, dy, touch)
    end

    Controller._defaults.mousemoved = mousemoved
    love.mousemoved = mousemoved
  end,

  --- @private
  --- @param CC ConsoleController
  set_love_wheelmoved = function(CC)
    --- @param x number
    --- @param y number
    local function wheelmoved(x, y)
      CC:wheelmoved(x, y)
    end

    Controller._defaults.wheelmoved = wheelmoved
    love.wheelmoved = wheelmoved
  end,

  -------------
  --  touch  --
  -------------
  --- @private
  --- @param CC ConsoleController
  set_love_touchpressed = function(CC)
    --- @param id userdata
    --- @param x number
    --- @param y number
    --- @param dx number?
    --- @param dy number?
    --- @param pressure number?
    local function touchpressed(id, x, y, dx, dy, pressure)
      CC:touchpressed(id, x, y, dx, dy, pressure)
    end

    Controller._defaults.touchpressed = touchpressed
    love.touchpressed = touchpressed
  end,
  --- @private
  --- @param CC ConsoleController
  set_love_touchreleased = function(CC)
    --- @param id userdata
    --- @param x number
    --- @param y number
    --- @param dx number?
    --- @param dy number?
    --- @param pressure number?
    local function touchreleased(id, x, y, dx, dy, pressure)
      CC:touchreleased(id, x, y, dx, dy, pressure)
    end

    Controller._defaults.touchreleased = touchreleased
    love.touchreleased = touchreleased
  end,
  --- @private
  --- @param CC ConsoleController
  set_love_touchmoved = function(CC)
    --- @param id userdata
    --- @param x number
    --- @param y number
    --- @param dx number?
    --- @param dy number?
    --- @param pressure number?
    local function touchmoved(id, x, y, dx, dy, pressure)
      CC:touchmoved(id, x, y, dx, dy, pressure)
    end

    Controller._defaults.touchmoved = touchmoved
    love.touchmoved = touchmoved
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
      if click_timer > 0 then
        click_timer = click_timer - dt
      end
      if click_timer <= 0 then
        if click_count == 1 then
          -- single click confirmed after delay
          local handler = CC:get_compy_handler('singleclick')
          if handler then
            local h = CC:wrap_handler(handler, wrap)
            local x, y = love.mouse.getPosition()
            local cur = { x = x, y = y }
            if no_drift(click_pos, cur) then
              h(x, y)
            end
          end
        elseif click_count >= 2 then
          -- double click detected
          local dbl_handler =
              CC:get_compy_handler('doubleclick')
          if dbl_handler then
            local h = CC:wrap_handler(dbl_handler, wrap)
            local x, y = love.mouse.getPosition()
            local cur = { x = x, y = y }
            if no_drift(click_pos, cur) then
              h(x, y)
            end
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
    local function draw()
      View.draw(CC, CV)
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
      if love.state.app_state == 'shutdown' then
        return false
      end

      if cfg.mode == 'play' then
        CC:quit_project()
        love.state.app_state = 'shutdown'
        love.state.user_input = nil

        love.draw = View.end_draw
        return true
      end
      if love.state.app_state == 'running' then
        CC:stop_project_run()
        return true
      end
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
  --- @param CC ConsoleController
  --- @param CV ConsoleView
  set_default_handlers = function(CC, CV)
    Controller.set_love_keypressed(CC)
    Controller.set_love_keyreleased(CC)
    Controller.set_love_textinput(CC)
    -- SKIPPED textedited - IME support, TODO?

    Controller.set_love_mousemoved(CC)
    Controller.set_love_mousepressed(CC)
    Controller.set_love_mousereleased(CC)
    Controller.set_love_wheelmoved(CC)

    Controller.set_love_touchpressed(CC)
    Controller.set_love_touchreleased(CC)
    Controller.set_love_touchmoved(CC)

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

    user_update = false
    Controller.set_love_update(CC)
    user_draw = false
    Controller.set_love_draw(CC, CV)
    Controller._defaults.draw = View.main_draw
    Controller.set_love_quit(CC)
  end,

  --- @param CC ConsoleController
  setup_callback_handlers = function(CC)
    local cfg = CC.cfg
    local playback = cfg.mode == 'play'

    local clear_user_input = function()
      love.state.user_input = nil
    end

    --- @diagnostic disable-next-line: undefined-field
    local handlers = love.handlers

    handlers.keypressed = function(k)
      --- Power shortcuts
      local function quickswitch()
        if Key.ctrl() and not Key.alt() and k == 't' then
          if love.state.app_state == 'running'
              or love.state.app_state == 'inspect'
              or love.state.app_state == 'project_open'
          then
            CC:stop_project_run()
            local st = love.state.editor
            if st then
              CC:edit(st.buffer.filename, st)
            else
              CC:edit()
            end
          elseif love.state.app_state == 'editor' then
            if CC.editor:is_normal_mode() then
              local ed_state = CC:finish_edit()
              love.state.editor = ed_state
              CC:run_project()
            end
          end
        end
      end
      local function project_state_change()
        if Key.ctrl() then
          if k == "pause" then
            CC:suspend_run(messages.user_break)
          end
          if k == "q" then
            CC:quit_project()
          end
          if k == "s" then
            if love.state.app_state == 'running' then
              CC:stop_project_run()
            elseif love.state.app_state == 'editor' then
              --- bare Ctrl+S is reserved for the
              --- checkpoint (rework spec 2.6); saving
              --- is automatic, leaving is Shift+Esc
              if Key.shift() then
                CC:finish_edit()
              end
            end
          end
          if Key.shift() then
            --- Ensure the user can get back to the console
            if k == "r" then
              CC:reset()
            end
          end
        end
      end
      local function restart()
        if Key.ctrl() and Key.alt() and k == "r" then
          CC:restart()
        end
      end
      local function profile()
        if Key.ctrl() and Key.alt() and k == "p" then
          if Key.shift() then
            Prof.stop_profiler()
          else
            -- Prof.start_profiler()
            Prof.start_oneshot()
          end
        end
        if k == "f10" then
          if love.PROFILE.fpsc == 'off' then
            love.PROFILE.fpsc = 'T_L_B'
          elseif love.PROFILE.fpsc == 'T_L_B' then
            love.PROFILE.fpsc = 'T_R_B'
          elseif love.PROFILE.fpsc == 'T_R_B' then
            love.PROFILE.fpsc = 'T_L'
          elseif love.PROFILE.fpsc == 'T_L' then
            love.PROFILE.fpsc = 'T_R'
          elseif love.PROFILE.fpsc == 'T_R' then
            love.PROFILE.fpsc = 'off'
          end
        end
      end

      if playback then
        if love.state.app_state == 'shutdown' then
          love.event.quit()
        end
        restart()
        if love.PROFILE then
          profile()
        end
      else
        restart()
        quickswitch()
        if love.PROFILE then
          profile()
        end
        project_state_change()
      end

      local user_input = get_user_input()
      if user_input then
        user_input.C:keypressed(k)
      else
        if love.keypressed then return love.keypressed(k) end
      end
    end

    handlers.textinput = function(t)
      local user_input = get_user_input()
      if user_input then
        user_input.C:textinput(t)
      else
        if love.textinput then return love.textinput(t) end
      end
    end

    handlers.keyreleased = function(k)
      if Key.ctrl() then
        if k == "escape" then
          love.event.quit()
        end
      end
      local user_input = get_user_input()
      if user_input then
        user_input.C:keyreleased(k)
      else
        if love.keyreleased then return love.keyreleased(k) end
      end
    end

    --- @param x integer
    --- @param y integer
    --- @param btn integer
    --- @param touch boolean
    --- @param presses number
    handlers.mousepressed = function(x, y, btn, touch, presses)
      local user_input = get_user_input()
      if user_input then
        user_input.C:mousepressed(x, y, btn, touch, presses)
      else
      end
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
      local user_input = get_user_input()
      if user_input then
        user_input.C:mousereleased(x, y, btn, touch, presses)
      else
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
      local user_input = get_user_input()
      if user_input then
        user_input.C:mousemoved(x, y, dx, dy, touch)
      else
      end
      if love.mousemoved then
        return love.mousemoved(x, y, dx, dy, touch)
      end
    end

    handlers.userinput = function()
      local user_input = get_user_input()
      if user_input then
        clear_user_input()
      end
    end

    --- @param id userdata
    --- @param x number
    --- @param y number
    --- @param dx number?
    --- @param dy number?
    --- @param pressure number?
    handlers.touchpressed = function(id, x, y, dx, dy, pressure)
      local user_input = get_user_input()
      if user_input then
        user_input.C:touchpressed(id, x, y, dx, dy, pressure)
      else
      end
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
      local user_input = get_user_input()
      if user_input then
        user_input.C:touchreleased(id, x, y, dx, dy, pressure)
      else
      end
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
      local user_input = get_user_input()
      if user_input then
        user_input.C:touchmoved(id, x, y, dx, dy, pressure)
      else
      end
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

  clear_user_handlers = function()
    Controller._userhandlers = {}
    View.clear_snapshot()
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
