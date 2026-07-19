local OS = require("util.os") --- pulls in string

local FS = {
  path_sep = (function()
    if love and love.system
        and OS.get_name() == "Windows" then
      return '\\'
    end
    return '/'
  end)(),
  messages = {
    enoent = function(name, type)
      local n = name or ''
      if type == 'directory' or type == 'dir' then
        return n .. ' is not a directory'
      end
      return n .. ' does not exist'
    end,
    mkdir_err = function(name, err)
      local n = name or ''
      local err = err or ''
      return "Unable to create directory " .. n .. ': ' .. err
    end,
    unreadable = function(name)
      local n = name or ''
      return "Unable to read " .. n
    end,
    cannot_open = function(name)
      local n = name or ''
      return "Can't open " .. n
    end,
  }
}

--- @param path string
--- @return string
FS.remove_dup_separators = function(path)
  local function undup(str, sep)
    return str:gsub(sep .. sep .. "+", sep)
  end

  local result = undup(path, "/")
  result = undup(result, "\\")

  return result
end

--- @return string
FS.join_path = function(...)
  local sep = FS.path_sep
  local args = { ... }
  local filtered = {}
  for _, v in pairs(args) do
    if string.is_non_empty_string(v) then
      table.insert(filtered, v)
    end
  end
  local raw = string.join(filtered, sep)
  return FS.remove_dup_separators(raw)
end

--- @param path string
--- @return boolean
FS.is_absolute = function(path)
  if love.system.getOS() == "Windows" then
    --- TODO: untested
    --- starts with 'C:\' or any other drive letter
    return string.matches_r(path, '^%a:\\')
  else
    return string.matches_r(path, '^' .. FS.path_sep)
  end
end

if love and not TESTING then
  local _fs

  LFS = love.filesystem

  --- @param path string
  --- @param filtertype love.FileType?
  local getDirectoryItemsInfo = function(path, filtertype)
    local items = {}
    local ls = LFS.getDirectoryItems(path)
    for _, n in ipairs(ls) do
      local fi = LFS.getInfo(FS.join_path(path, n), filtertype)
      if fi then
        --- @diagnostic disable-next-line: inject-field
        fi.name = n
        table.insert(items, fi)
      end
    end
    return items
  end


  if love.system and love.system.getOS() == "Web" then
    _fs = {
      read = function(...)
        return LFS.read(...)
      end,
      write = function(...)
        return LFS.write(...)
      end,
      lines = function(...)
        return LFS.lines(...)
      end,
      getInfo = function(...)
        return LFS.getInfo(...)
      end,
      createDirectory = function(...)
        return LFS.createDirectory(...)
      end,
      getDirectoryItemsInfo = getDirectoryItemsInfo,
      mount = function(...)
        return LFS.mount(...)
      end,
    }
  else
    _fs = require("lib.nativefs.nativefs")
  end

  --- @param path string
  --- @param filtertype love.FileType?
  --- @param vfs boolean?
  --- @return boolean
  function FS.exists(path, filtertype, vfs)
    if vfs then
      return LFS.getInfo(path, filtertype) and true or false
    else
      return _fs.getInfo(path, filtertype) and true or false
    end
  end

  --- @param path string
  --- @return boolean success
  function FS.mkdir(path)
    return _fs.createDirectory(path)
  end

  --- @param path string
  --- @return boolean success
  --- @return string? err
  function FS.mkdirp(path)
    local sep = FS.path_sep
    local segments = string.split(path, sep)
    for i, _ in ipairs(segments) do
      local partial = table.slice(segments, 1, i)
      local p = string.join(partial, sep)
      local ok = FS.mkdir(p)
      if not ok then
        return false, FS.messages.mkdir_err(p)
      end
    end
    return true
  end

  --- @param path string
  --- @param filtertype love.FileType?
  --- @param vfs boolean?
  --- @return table
  function FS.dir(path, filtertype, vfs)
    local items = (function()
      if vfs then
        return getDirectoryItemsInfo(path, filtertype)
      end
      return _fs.getDirectoryItemsInfo(path, filtertype)
    end)()

    return items
  end

  --- @param path string
  --- @return table
  function FS.lines(path)
    local ret = {}
    if FS.exists(path) then
      for l in _fs.lines(path) do
        table.insert(ret, l)
      end
    end
    return ret
  end

  --- @param path string
  --- @param vfs boolean?
  --- @return string?
  function FS.read(path, vfs)
    local contents
    if vfs then
      contents = LFS.read(path)
    else
      contents = _fs.read('string', path, nil)
    end

    ---@diagnostic disable-next-line: return-type-mismatch
    return contents
  end

  --- @param path string
  --- @return string?
  function FS.combined_read(path)
    return FS.read(path, true) or FS.read(path)
  end

  --- Durability helpers (bionic/glibc via LuaJIT FFI).
  --- FS.write is async (see its contract below); the
  --- editor accept path opts into durability with
  --- FS.fsync, and lifecycle handlers use FS.sync as a
  --- cheap whole-filesystem net.
  local _durable = (function()
    local ffi_ok, ffi = pcall(require, 'ffi')
    if not ffi_ok then return nil end
    pcall(ffi.cdef, [[
      int open(const char* path, int flags);
      int close(int fd);
      int fsync(int fd);
      void sync(void);
    ]])
    local O_RDONLY = 0
    return {
      file = function(path)
        local fd = ffi.C.open(path, O_RDONLY)
        if fd < 0 then return false end
        local r = ffi.C.fsync(fd)
        ffi.C.close(fd)
        return r == 0
      end,
      all = function() ffi.C.sync() end,
    }
  end)()

  --- Flush one file's data through to stable storage.
  --- The editor accept path calls this after a save
  --- (spec 2.6 "written immediately"). Do NOT add it to
  --- FS.write: bulk deploy/clone and the user-facing
  --- writefile must stay async. Best-effort — returns
  --- false when the platform lacks the syscall or the
  --- path cannot be opened.
  --- @param path string
  --- @return boolean durable
  function FS.fsync(path)
    if not _durable then return false end
    local ok, res = pcall(_durable.file, path)
    return (ok and res) or false
  end

  --- Flush all pending writes filesystem-wide in one
  --- syscall. Cheap broad net for background/quit; does
  --- not cover a force-stop mid-edit (that is FS.fsync).
  --- @return boolean ran
  function FS.sync()
    if not _durable then return false end
    return pcall(_durable.all)
  end

  --- Write data to path, overwriting. Async by default:
  --- the bytes reach the OS but are NOT flushed to stable
  --- storage, so a power-cut or SIGKILL can lose them
  --- while an (exfat dirsync) directory entry persists.
  --- Callers needing durability opt in via FS.fsync(path)
  --- after a successful write — the editor accept path
  --- does; bulk deploy/clone and writefile do not.
  --- @param path string
  --- @param data string
  --- @return boolean success
  --- @return string? error
  function FS.write(path, data)
    local wok, werr = _fs.write(path, data)
    return wok or false, werr
  end

  --- @param source string
  --- @param target string
  --- @param vfs boolean? -- use VFS for source
  --- @return boolean success
  --- @return string? error
  function FS.cp(source, target, vfs)
    local getInfo = (function()
      if vfs then
        return LFS.getInfo
      end
      return _fs.getInfo
    end)()
    local srcinfo = getInfo(source)
    if not srcinfo or srcinfo.type ~= 'file' then
      return false, FS.messages.enoent('source ' .. source)
    end

    local tgtinfo = _fs.getInfo(target)
    local to
    if not tgtinfo or tgtinfo.type == 'file' then
      to = target
    end
    if tgtinfo and tgtinfo.type == 'directory' then
      local parts = string.split(source, '/')
      local fn = parts[#parts]
      to = FS.join_path(target, fn)
    end
    if not to then
      return false, FS.messages.enoent('target ' .. target)
    end

    --- @type string
    --- @diagnostic disable-next-line: assign-type-mismatch
    local content, s_err = (function()
      if vfs then return LFS.read('string', source) end
      return _fs.read('string', source)
    end)()
    if not content then
      return false, tostring(s_err)
    end

    local out, t_err = FS.write(to, content)
    if not out then
      return false, t_err
    end
    return true
  end

  --- @param source string
  --- @param target string
  --- @param vfs boolean? -- use VFS for source
  --- @return boolean success
  --- @return string? error
  function FS.cp_r(source, target, vfs)
    local getInfo = (function()
      if vfs then
        return LFS.getInfo
      end
      return _fs.getInfo
    end)()
    local cp_ok = true
    local cp_err
    local srcinfo = getInfo(source)
    local tgtinfo = _fs.getInfo(target)
    if not srcinfo or srcinfo.type ~= 'directory' then
      return false, FS.messages.enoent('source', 'dir')
    end
    if not tgtinfo then
      local ok, err = FS.mkdir(target)
      if not ok then
        Log.error(FS.messages.mkdir_err(target, err))
      end
    end
    tgtinfo = _fs.getInfo(target)
    if not tgtinfo or tgtinfo.type ~= 'directory' then
      return false, FS.messages.enoent('target', 'dir')
    end

    FS.mkdir(target)
    local items = FS.dir(source, nil, vfs)
    for _, i in pairs(items) do
      local s = FS.join_path(source, i.name)
      local t = FS.join_path(target, i.name)

      local ok, err = FS.cp(s, t, vfs)
      if not ok then
        cp_ok = false
        cp_err = err
      end
    end

    return cp_ok, cp_err
  end

  --- @param source string
  --- @param target string
  --- @return boolean success
  --- @return string? error
  function FS.mv(source, target)
    local cpok, cperr = FS.cp(source, target)
    if cpok then
      return FS.rm(source)
    end
    return false, cperr
  end

  --- @param target string
  --- @param vfs boolean?
  --- @return boolean success
  --- @return string? error
  function FS.rm(target, vfs)
    if vfs then
      return LFS.remove(target)
    end
    return _fs.remove(target)
  end

  --- @param path string
  --- @param target string
  --- @return boolean success
  function FS.mount(path, target)
    local ok = _fs.mount(path, target)
    return ok
  end
else
  --- used in unit tests where love utils are not available
  local lfs = require("lfs")

  --- @param path string
  --- @param data string
  --- @return boolean success
  --- @return string? error
  function FS.write(path, data)
    local f, oerr = io.open(path, 'w')
    if f then
      io.output(f)
      local _, err = io.write(data)
      io.close(f)
      io.output(io.stdout)
      return true, err
    end
    return false, oerr
  end

  --- @param path string
  --- @return boolean success
  --- @return string data|error
  function FS.read(path)
    local handle = io.open(path, "r")
    if handle then
      local content = handle:read("*a")
      handle:close()
      return true, content
    else
      return false, FS.messages.unreadable(path)
    end
  end

  --- @param source string
  --- @param target string
  --- @return boolean success
  --- @return string? error
  function FS.cp(source, target)
    local src = FS.exists(source)
    if not src then
      return false, FS.messages.cannot_open(source)
    end

    local rok, cont_err = FS.read(source)
    if rok and cont_err then
      local wok, werr = FS.write(target, cont_err)
      return wok, werr
    else
      return false, cont_err
    end
  end

  --- @param path string
  --- @return boolean success
  --- @return string? error
  function FS.mkdir(path)
    return lfs.mkdir(path)
  end

  --- @param path string
  --- @return boolean success
  --- @return string? error
  function FS.mkdirp(path)
    if FS.exists(path) then
      local a = lfs.attributes(path, 'mode')
      return a == 'directory'
    end
    return FS.mkdir(path)
  end

  --- @param path string
  --- @return boolean exists
  function FS.exists(path)
    local f = io.open(path, 'r')
    if f then
      io.close(f)
      return true
    end
    return false
  end

  --- @param path string
  --- @return boolean success
  --- @return string? error
  function FS.unlink(path)
    return os.remove(path)
  end

  --- @param content str
  --- @param ext string?
  --- @param fixname string?
  function FS.write_tempfile(content, ext, fixname)
    local function create_temp()
      local cmd = 'mktemp -u -p .'
      if string.is_non_empty_string(ext) then
        cmd = string.format('%s --suffix .%s', cmd, ext)
      end
      local _, result = OS.runcmd(cmd)
      return result
    end
    local name =
        string.is_non_empty_string(fixname)
        and fixname .. (ext and '.' .. ext or '')
        or create_temp()
    local mok, merr = FS.mkdirp('./.debug')
    if not mok then
      return false, merr
    end
    local path = FS.join_path('./.debug', name)

    local data = string.unlines(content)
    local ok, err = FS.write(path, data)
    if not ok then
      return false, err
    end
    return ok
  end
end


return FS
