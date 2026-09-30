local OS = require("util.os") --- pulls in string

---@class FileInfo
---@field type love.FileType
---@field size number?
---@field modtime number?

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

--- The path the operating system reads for `path`. The same
--- path everywhere but the web build (see below).
--- @param path string
--- @return string
FS.system_path = function(path)
  return path
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
    --- a save cannot reach the C library here (FS.replace)
    FS.web = true
    _fs = {
      read = function(...)
        return LFS.read(...)
      end,
      write = function(...)
        return LFS.write(...)
      end,
      remove = function(...)
        return LFS.remove(...)
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
    --- The web build names files relative to LÖVE's save
    --- directory, but the operating system reads a relative
    --- path from the process's directory, the root there.
    FS.system_path = function(path)
      if FS.is_absolute(path) then return path end
      return FS.join_path(LFS.getSaveDirectory(), path)
    end
  else
    _fs = require("lib.nativefs.nativefs")
  end

  --- @param path string
  --- @param filtertype love.FileType?
  --- @param vfs boolean?
  --- @return FileInfo?
  function FS.getInfo(path, filtertype, vfs)
    if vfs then
      return LFS.getInfo(path, filtertype)
    else
      return _fs.getInfo(path, filtertype)
    end
  end

  --- @param path string
  --- @param filtertype love.FileType?
  --- @param vfs boolean?
  --- @return boolean
  function FS.exists(path, filtertype, vfs)
    return FS.getInfo(path, filtertype, vfs) and true or false
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
  --- The editor's saves reach it through FS.replace's
  --- durable write (spec 2.6 "written immediately"). Do NOT
  --- add it to FS.write: bulk deploy/clone and the
  --- user-facing writefile must stay async. Best-effort — returns
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
  --- Callers needing durability opt in via FS.fsync(path),
  --- as FS.replace's durable write does for the editor's
  --- saves; bulk deploy/clone and writefile do not.
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
  --- @param replace boolean? -- write through FS.replace,
  --- durably
  --- @return boolean success
  --- @return string? error
  function FS.cp(source, target, vfs, replace)
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

    local out, t_err
    if replace then
      out, t_err = FS.replace(to, content, true)
    else
      out, t_err = FS.write(to, content)
    end
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
      if not FS.is_replace_temp(i.name) then
        local s = FS.join_path(source, i.name)
        local t = FS.join_path(target, i.name)

        local ok, err = FS.cp(s, t, vfs)
        if not ok then
          cp_ok = false
          cp_err = err
        end
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
    if not f then return false, oerr end
    --- the data may wait in a buffer until close, so a write
    --- has succeeded only when both have
    local wok, werr = f:write(data)
    local cok, cerr = f:close()
    if not wok then return false, werr end
    if not cok then return false, cerr end
    return true
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

  --- @param path string
  --- @return boolean ok
  --- @return string content|error
  function FS.combined_read(path)
    return FS.read(path)
  end

  --- @param source string
  --- @param target string
  --- @param _ boolean? -- the VFS flag of the love branch
  --- @param replace boolean? -- write through FS.replace,
  --- durably
  --- @return boolean success
  --- @return string? error
  function FS.cp(source, target, _, replace)
    local src = FS.exists(source)
    if not src then
      return false, FS.messages.cannot_open(source)
    end

    local rok, cont_err = FS.read(source)
    if rok and cont_err then
      local wok, werr
      if replace then
        wok, werr = FS.replace(target, cont_err, true)
      else
        wok, werr = FS.write(target, cont_err)
      end
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
  --- @param filtertype love.FileType?
  --- @return FileInfo?
  function FS.getInfo(path, filtertype)
    local attrs = lfs.attributes(path)
    if not attrs then return end

    --- @type table<string, love.FileType>
    local types = {
      file = 'file',
      directory = 'directory',
    }
    local filetype = types[attrs.mode] or 'other'
    if filtertype and filtertype ~= filetype then return end

    return {
      type = filetype,
      size = attrs.size,
      modtime = attrs.modification,
    }
  end

  --- @param path string
  --- @param filtertype love.FileType?
  --- @return boolean exists
  function FS.exists(path, filtertype)
    return FS.getInfo(path, filtertype) and true or false
  end

  --- Directory listing for the unit-test branch. The LÖVE
  --- branch lists through love.filesystem; here lfs stands in,
  --- returning the same FileInfo-shaped entries (.name, .type,
  --- .size, .modtime) the project service and the console's
  --- list_contents/evacuate_required read.
  --- @param path string
  --- @param filtertype love.FileType?
  --- @return table FileInfo[]
  function FS.dir(path, filtertype)
    local items = {}
    local iter, state = lfs.dir(path)
    for entry in iter, state do
      if entry ~= '.' and entry ~= '..' then
        local fi = FS.getInfo(FS.join_path(path, entry))
        if fi and (not filtertype or fi.type == filtertype) then
          fi.name = entry
          table.insert(items, fi)
        end
      end
    end
    return items
  end

  --- @param path string
  --- @return boolean success
  --- @return string? error
  function FS.unlink(path)
    return os.remove(path)
  end

  --- @param target string
  --- @return boolean success
  --- @return string? error
  function FS.rm(target)
    return os.remove(target)
  end

  --- @return boolean ran
  function FS.sync()
    return true
  end

  --- @param path string
  --- @return boolean durable
  function FS.fsync(path)
    return true
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

--- Atomic rename on the same filesystem.
--- Uses the standard `os.rename` (rename(2)) so the target
--- only ever appears complete.
--- @param source string
--- @param target string
--- @return boolean success
--- @return string? error
function FS.rename(source, target)
  local ok, err = os.rename(FS.system_path(source),
    FS.system_path(target))
  return ok or false, err
end


--- A save's temporary file is `.<name>.compy-tmp` beside the
--- file. The namespace is reserved: a project refuses a file
--- of that name (Project validation), a listing or a copy
--- leaves such files out, and a save removes one it finds.
local TEMP_SUFFIX = '.compy-tmp'

--- A file name's longest, in bytes, on Linux and the card
local NAME_MAX = 255

--- A short, stable stand-in for a name: 32 bits of it, in
--- hex, by plain arithmetic, which every build has
--- @param name string
--- @return string
local function digest(name)
  local h = 2166136261
  for i = 1, #name do
    h = (h * 31 + string.byte(name, i)) % 4294967296
  end
  return string.format('%08x', h)
end

--- @param path string
--- @return string --- the temporary file FS.replace writes
--- beside `path`. A name so long the suffix would take it
--- past the length limit gets a digest of it in its place,
--- still in the namespace.
function FS.replace_temp(path)
  local dir, name = string.match(path, '^(.*[/\\])([^/\\]+)$')
  if not dir then dir, name = '', path end
  local temp = '.' .. name .. TEMP_SUFFIX
  if #temp > NAME_MAX then
    temp = '.' .. digest(name) .. TEMP_SUFFIX
  end
  return dir .. temp
end

--- @param name string
--- @return boolean --- a name in the temporary files'
--- namespace; exFAT ignores case, so this does too
function FS.is_replace_temp(name)
  return string.match(string.lower(name), '^%..+%.compy%-tmp$') ~= nil
end

--- Linux's C library, where LuaJIT's ffi reaches it: a save
--- creates its temporary file exclusively, which never
--- writes through a file or link already at that name.
--- Declared one at a time, since a reload of this module
--- declares them again.
local posix = (function()
  if FS.web then return nil end
  if type(jit) ~= 'table' or jit.os ~= 'Linux' then return nil end
  local ok, ffi = pcall(require, 'ffi')
  if not ok then return nil end
  for _, decl in ipairs({
    'int compy_open(const char *path, int flags, int mode) __asm__("open");',
    'long compy_write(int fd, const void *buf, unsigned long n) __asm__("write");',
    'int compy_close(int fd) __asm__("close");',
    'int compy_fsync(int fd) __asm__("fsync");',
    'char *compy_strerror(int errnum) __asm__("strerror");',
  }) do
    pcall(ffi.cdef, decl)
  end
  local C = ffi.C
  local found = pcall(function()
    return C.compy_open, C.compy_write, C.compy_close,
        C.compy_fsync, C.compy_strerror
  end)
  if not found then return nil end
  --- a file's mode, where the C library has statx, whose
  --- layout is the same on every architecture
  for _, decl in ipairs({
    [[typedef struct {
        uint32_t mask; uint32_t blksize; uint64_t attributes;
        uint32_t nlink; uint32_t uid; uint32_t gid;
        uint16_t mode; uint16_t spare; uint64_t rest[28];
      } compy_statx_t;]],
    'int compy_statx(int dirfd, const char *path, int flags,'
    .. ' unsigned int mask, compy_statx_t *buf) __asm__("statx");',
    'int compy_fchmod(int fd, unsigned int mode) __asm__("fchmod");',
  }) do
    pcall(ffi.cdef, decl)
  end
  local modes = pcall(function()
    return C.compy_statx, C.compy_fchmod
  end)
  return { ffi = ffi, C = C, modes = modes }
end)()

--- Linux, all architectures Compy runs on
local O_WRONLY, O_CREAT, O_EXCL = 1, 64, 128
local EEXIST = 17

--- @return string
local function errstr()
  return posix.ffi.string(posix.C.compy_strerror(posix.ffi.errno()))
end

--- A new file at `path`, created by this call alone. One
--- there already is a save's leftover, since the name is
--- reserved: it goes, a link by itself and never what it
--- points at, and the file is created again.
--- @param path string
--- @return integer? fd
--- @return string? err
local function create_new(path)
  local C = posix.C
  local flags = O_WRONLY + O_CREAT + O_EXCL
  local fd = C.compy_open(path, flags, 438)
  if fd < 0 and posix.ffi.errno() == EEXIST then
    os.remove(path)
    fd = C.compy_open(path, flags, 438)
  end
  if fd < 0 then return nil, errstr() end
  return fd
end

--- Flush an open file's data to stable storage
--- @param fd integer
--- @return boolean synced
function FS.sync_fd(fd)
  return posix.C.compy_fsync(fd) == 0
end

--- Flush a folder's entries, a rename among them, to stable
--- storage. Best effort: the card is mounted dirsync, where a
--- rename is on the card when it returns, and a folder that
--- cannot be synced this way is left as it is.
--- @param dir string
--- @return boolean synced
function FS.sync_dir(dir)
  if not posix then return false end
  local fd = posix.C.compy_open(dir, 0, 0)
  if fd < 0 then return false end
  local synced = posix.C.compy_fsync(fd) == 0
  posix.C.compy_close(fd)
  return synced
end

--- @param fd integer
--- @param data string
--- @return boolean ok
--- @return string? err
local function write_all(fd, data)
  local buf = posix.ffi.cast('const char *', data)
  local done, n = 0, #data
  while done < n do
    local w = tonumber(posix.C.compy_write(fd, buf + done, n - done))
    if w < 0 then return false, errstr() end
    done = done + w
  end
  return true
end

--- Give the new file the permissions of the one it replaces.
--- Best effort: the card has no such bits, and a C library
--- without statx leaves the new file's own. On the Linux
--- path only (write_temp_plain keeps none).
--- @param fd integer
--- @param target string
local function keep_mode(fd, target)
  if not posix.modes then return end
  local AT_FDCWD, STATX_MODE = -100, 2
  local st = posix.ffi.new('compy_statx_t')
  if posix.C.compy_statx(AT_FDCWD, target, 0, STATX_MODE, st) ~= 0 then
    return
  end
  posix.C.compy_fchmod(fd, bit.band(st.mode, 4095))
end

--- @param path string
--- @param data string
--- @param durable boolean?
--- @param target string --- the file it is to replace
--- @return boolean ok
--- @return string? err
local function write_temp_posix(path, data, durable, target)
  local fd, err = create_new(path)
  if not fd then return false, err end
  keep_mode(fd, target)
  local ok
  ok, err = write_all(fd, data)
  --- a durable save whose data does not reach the disk is
  --- no save: the file keeps what it had
  if ok and durable and not FS.sync_fd(fd) then
    ok, err = false, errstr()
  end
  if posix.C.compy_close(fd) ~= 0 and ok then
    ok, err = false, errstr()
  end
  return ok, err
end

--- Without the C library (the web build, a desktop other
--- than Linux, a plain Lua): a leftover at the reserved name
--- goes first. Less than the Linux path: the new file keeps
--- no mode, its sync is best effort and unchecked (the web
--- build has none), and no folder is synced.
--- @param path string
--- @param data string
--- @param durable boolean?
--- @return boolean ok
--- @return string? err
local function write_temp_plain(path, data, durable)
  if FS.exists(path) then FS.rm(path) end
  local ok, err = FS.write(path, data)
  if ok and durable then FS.fsync(path) end
  return ok, err
end

--- Write `data` over the file at `path` so that it holds its
--- old content or the new, never a part: the data goes to a
--- temporary file beside it (FS.replace_temp) and is renamed
--- over the file. On a full card the temporary write fails
--- and the file is untouched. A failure removes the
--- temporary file; a save finding one a power cut left
--- replaces it. The rename replaces an existing file, as it
--- does on Linux, Android and the card; Windows' refuses,
--- and there is no Windows build.
--- @param path string
--- @param data string
--- @param durable boolean? --- the data reaches stable
--- storage before the rename, and the rename after it; the
--- editor's saves ask for it, a program's writefile stays
--- async
--- @return boolean success
--- @return string? error
function FS.replace(path, data, durable)
  local tmp = FS.replace_temp(path)
  local write_temp = posix and write_temp_posix or write_temp_plain
  local ok, err = write_temp(tmp, data, durable, path)
  if ok then
    ok, err = FS.rename(tmp, path)
  end
  if not ok then
    FS.rm(tmp)
    return false, err
  end
  if durable then
    --- the rename itself reaches the disk with the folder's
    --- entries; on the card, dirsync has put it there already
    FS.sync_dir(string.match(path, '^(.*[/\\])') or '.')
  end
  return true
end

return FS
