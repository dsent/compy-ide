local require = _G.o_require or _G.require
FS = require("util.filesystem")

require("util.string.string")
require("util.debug")

local Timer = require("lib.hump.timer")
local timer = Timer.new()
local frame_time = 0.001

--- @class Harmony
--- @field run function
--- @field timer hump.Timer
--- @field lock boolean
--- @field pre string
--- @field unpre function
--- @field utils HarmonyUtils

local instance
local lock
local debug_print = function(...)
  -- Log.debug(...)
end

--- The run's report goes to standard output: print reaches
--- the IDE's console, on the screen the scenarios capture
--- @param s string
local function report(s)
  io.stdout:write('harmony: ' .. s .. '\n')
  io.stdout:flush()
end

Harmony = {
  --- @private
  pre = '',
  unpre = function(s)
    if not s then return end
    return string.sub(s, string.len(Harmony.pre) + 1)
  end,
}
Harmony.__index = Harmony

--- The exit status a quit event's value holds: the IDE tags
--- the quits it and its projects ask for (util.application)
--- @param a any
--- @return any
local function untagged(a)
  local _, status = require("util.application").untag(a)
  return status
end

local function new(_lock)
  local inject = function()
    local function harmonius_run()
      if love.load then
        ---@diagnostic disable-next-line: undefined-field, redundant-parameter
        love.load(love.arg.parseGameArguments(arg), arg)
      end

      if love.timer then love.timer.step() end

      local dt = 0

      local main_loop = function()
        if love.event then
          love.event.pump()
          for name, a, b, c, d, e, f in love.event.poll() do
            if name == 'die' then
              -- debug_print('die')
              -- die = true
              return a or 0
            end
            local sazed_says =
                string.starts_with(name, Harmony.pre)
            if sazed_says then
              local n = Harmony.unpre(name)
              if n == "quit" then
                if not love.quit or not love.quit(a) then
                  -- break
                  return untagged(a) or 0
                end
              end
              ---@diagnostic disable-next-line: undefined-field
              love.handlers[n](a, b, c, d, e, f)
            else
              if
                  name == "quit"
                  or name == "keypressed" and a == 'escape'
              then
                if not love.quit or not love.quit(a) then
                  return untagged(a) or 0
                end
              end
            end
          end
        end

        if love.timer then dt = love.timer.step() end

        if love.update then love.update(dt) end

        if love.graphics and love.graphics.isActive() then
          local gfx = love.graphics
          gfx.origin()
          gfx.clear(
            gfx.getBackgroundColor()
          )

          if love.draw then love.draw() end

          love.graphics.present()
        end

        if love.timer then love.timer.sleep(frame_time) end
      end

      return main_loop
    end

    --- override mainloop
    love.run = harmonius_run
  end

  lock = _lock
  if lock then
    Harmony.pre = 'sazed_'
    Harmony.lock = true
  end
  --- @private
  Harmony.timer = timer
  Harmony.timer_update = function(dt)
    timer:update(dt)
  end

  love.harmony = Harmony
  inject()
end

setmetatable(Harmony, {
  __call = function(_cls, ...)
    if not instance then
      instance = new(...)
    end
    return instance
  end,
})

local messages = {
  not_loaded = function(reason)
    local msg = 'Harmony.load() was not called'
    if reason then
      return msg .. 'needed for: ' .. reason
    end
    return msg
  end
}

local load_guard = function(reason)
  if not Harmony.loaded then
    error(messages.not_loaded(reason))
  end
end

--- Utility functions that depend on love being loaded already

local function utils()
  if not love.harmony then return end
  if love.harmony.utils then return end

  local gfx = love.graphics

  --- @param name love.Event
  local love_event = function(name, ...)
    local n = Harmony.pre .. name
    love.event.push(n, ...)
  end

  local mods = {
    C     = 'lctrl',
    Ctrl  = 'lctrl',
    S     = 'lshift',
    Shift = 'lshift',
    M     = 'lalt',
    Meta  = 'lalt',
    Alt   = 'lalt',
    A     = 'lalt',
    Super = 'lgui',
    Hyper = 'lgui',
    H     = 'lgui',
  }
  -- Scripted modifiers live here and are answered by the
  -- patched isDown; they never enter the event stream. That is
  -- sufficient while modifier state is read from the device
  -- (doc/development/decisions/input.md, "D-ASK-THE-DEVICE —
  -- modifier state is read from the device"). A consumer that
  -- instead counts key events to mirror what is held would see
  -- no modifier here, and would misjudge silently.
  local held = {
    lctrl  = false,
    rctrl  = false,
    lshift = false,
    rshift = false,
    lalt   = false,
    ralt   = false,
    --- aka Super / Hyper / Win / Cmd
    lgui   = false,
    rgui   = false,
  }
  local shortcuts = {
    toggle = 'C-t'
  }


  --- @param tag string
  local take_screenshot = function(tag)
    local fn = tag .. '.png'
    local tmp = Harmony.tmpdir or '/tmp'
    local dir = FS.join_path(tmp, 'screenshots')

    local ctx = _G.context
    if type(ctx) == 'table' and
        type(ctx.file) == 'string'
    then
      dir = FS.join_path(dir, ctx.file)
      local t = ctx.tag
      if string.is_non_empty_string(t) then
        fn = t .. '.' .. fn
      end
    end

    FS.mkdirp(dir)
    --- @param img_data love.ImageData
    gfx.captureScreenshot(function(img_data)
      if img_data then
        local from = FS.join_path(
          love.filesystem.getSaveDirectory(), fn
        )
        local to = FS.join_path(dir, fn)
        img_data:encode('png', fn)
        local ok, err = FS.mv(from, to)
        if not ok then
          print(err)
        end
      end
    end)
  end

  local release_keys = function()
    for k, v in pairs(held) do
      if v then
        held[k] = false
      end
    end
  end

  --- @class HarmonyUtils
  --- @field patch_isDown function
  --- @field patch_setTitle function
  --- @field love_event function
  --- @field love_key function
  --- @field love_text function
  --- @field screenshot function
  --- @field release_keys function
  --- @field release_mods function
  --- @field hold function
  --- @field key_repeat function
  --- @field let_go function
  --- @field shortcuts table
  return {
    patch_isDown = function()
      local down = love.keyboard.isDown
      local isDown = function(...)
        local keys = { ... }
        for _, key in ipairs(keys) do
          if held[key] then return true end
        end
        if not lock then
          return down(...)
        end
        return false
      end
      love.keyboard.isDown = isDown
    end,
    patch_setTitle = function()
      local set_title = love.window.setTitle
      local setTitle = function(title)
        local t = (title or '') .. ' - Harmony mode'
        set_title(t)
      end
      love.window.setTitle = setTitle
    end,

    love_event = love_event,
    love_text = function(t)
      timer:script(function(wait)
        debug_print('text: ' .. t)
        love_event('textinput', t)
        wait(frame_time * 5)
      end)
    end,
    love_key = function(keys)
      local key = keys
      if string.matches(keys, '-') then
        local ks = string.split(keys, '-')
        debug_print()
        for _, v in ipairs(ks) do
          local m = mods[v]
          if m then
            debug_print(m .. ' held')
            held[m] = true
          else
            love_event('keypressed', v)
            debug_print('\tkey ' .. v)
            love_event('keyreleased', v)
            -- release_keys()
          end
        end
      else
        love_event('keypressed', key)
        debug_print('key ' .. key)
        love_event('keyreleased', key)
      end
    end,

    release_keys = release_keys,
    --- let go of the modifiers alone: a key held with hold
    --- stays held
    release_mods = function()
      for _, m in pairs(mods) do held[m] = false end
    end,

    --- press `key` and keep it held: isDown answers true for
    --- it until let_go, and no release is sent, as a hand that
    --- holds F1
    --- @param key string
    hold = function(key)
      held[key] = true
      love_event('keypressed', key, key, false)
    end,
    --- a held key's repeat, as LÖVE sends it while the key
    --- stays down: the key, its scancode, and isrepeat true
    --- @param key string
    key_repeat = function(key)
      love_event('keypressed', key, key, true)
    end,
    --- @param key string
    let_go = function(key)
      held[key] = false
      love_event('keyreleased', key, key)
    end,

    shortcuts = shortcuts,

    screenshot = function(tag)
      timer:script(function(wait)
        wait(frame_time)
        take_screenshot(tag)
      end)
    end,
  }
end

local function runner()
  if not love.harmony then return end
  if love.harmony.runner then return end


  local context = {}
  local scenarios = {}
  local done = true

  function scenario(tag, f)
    context.tag = tag
    local id = context.file .. '.' .. tag
    table.insert(scenarios, {
      context = table.clone(context),
      id = id,
      sc = f,
    })
    context.tag = nil
  end

  function hm_done(label)
    done = true
    love.harmony.utils.release_keys()
    local ctxl = (function()
      local c = _G.context
      if type(c) == 'table' then
        return string.join({ c.file, c.tag }, '.')
      else
        return ''
      end
    end)()
    debug_print('done ' .. (label or ctxl))
  end

  local scrun

  return {
    load_scenarios = function()
      local ls = FS.dir("src/harmony/scenarios")
      --- in name order, whatever order the directory lists
      table.sort(ls, function(a, b) return a.name < b.name end)
      for _, d in ipairs(ls) do
        if d.type == 'file' then
          local module_name = string.sub(d.name, 1, -5)
          context.file = module_name
          require("harmony.scenarios." .. module_name)
        end
        context.file = nil
      end

      context.file = '_'
      scenario('done', function(wait)
        love.harmony.utils.love_text("for _, c in")
        wait(.2)
        love.harmony.utils.love_text(" ipairs({'D', 'o', 'n', 'e'})")
        wait(.2)
        love.harmony.utils.love_text(" do print(c) end")
        wait(.2)
        love.harmony.utils.love_key('return')

        hm_done()
      end)

      scrun = coroutine.create(function()
        -- timer = Timer.new()
        for _, v in ipairs(scenarios) do
          local tag = v.id
          local sc = v.sc
          Harmony.current = tag
          report(tag)
          done = false
          timer:script(function(wait)
            _G.context = v.context

            sc(wait)
          end)
          coroutine.yield()
        end

        Harmony.current = nil
        report(string.format('%d scenarios passed', #scenarios))
        if Harmony.lock then
          Harmony.exit()
        end
        coroutine.yield()
      end)
    end,

    run_scenarios = function()
      timer:script(function(wait)
        while coroutine.status(scrun) ~= "dead" do
          wait(.5)
          if done then
            _G.context = nil
            coroutine.resume(scrun)
          end
        end
      end)
    end,

  }
end

function Harmony.load()
  Harmony.loaded = true
  require('util.debug')

  Harmony.utils = utils()
  Harmony.utils.patch_isDown()
  Harmony.utils.patch_setTitle()
  love.window.setTitle(love.window.getTitle())

  Harmony.runner = runner()

  --- A failed check or an error ends the run at once, the
  --- scenario named and the exit status 1, rather than at an
  --- error screen that waits for a key no one presses
  if lock then
    love.errorhandler = function(msg)
      report('FAILED in ' .. tostring(Harmony.current))
      io.stdout:write(debug.traceback(tostring(msg), 2), '\n')
      io.stdout:flush()
      return function() return 1 end
    end
    love.errhand = love.errorhandler
  end
end

function Harmony.screenshot(tag)
  load_guard('filesystem')
  return Harmony.utils.screenshot(tag)
end

function Harmony.run()
  --- the run's storage and screenshots, so that a caller
  --- finds its own run's among others under /tmp
  report('storage ' .. tostring(Harmony.tmpdir))
  timer:after(.1, function()
    Harmony.runner.load_scenarios()
    Harmony.runner.run_scenarios()
  end)
end

function Harmony.exit()
  love.harmony.timer:script(function(wait)
    wait(.5)
    Harmony.utils.love_event('quit')
  end)
end

return Harmony
