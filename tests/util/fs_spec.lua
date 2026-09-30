local FS = require("util.filesystem")

describe("FS utils", function()
  describe("removes duplicate separators", function()
    local remove_duplicate_separators = FS.remove_dup_separators

    it("should remove duplicate forward slashes", function()
      local input = "/home//user///documents////file.txt"
      local expected = "/home/user/documents/file.txt"
      assert.are.equal(expected, remove_duplicate_separators(input))
      local input2 = "//home/user//file.txt"
      local res = "/home/user/file.txt"
      assert.are.equal(res, remove_duplicate_separators(input2))
    end)

    it("should remove duplicate backslashes", function()
      local input = "C:\\\\Users\\\\John\\\\\\Documents\\\\\\file.txt"
      local expected = "C:\\Users\\John\\Documents\\file.txt"
      assert.are.equal(expected, remove_duplicate_separators(input))
    end)

    it("should handle mixed forward slashes and backslashes", function()
      local input = "C:/Users\\\\John//Documents\\\\file.txt"
      local expected = "C:/Users\\John/Documents\\file.txt"
      assert.are.equal(expected, remove_duplicate_separators(input))
    end)

    it("should not modify paths without duplicate separators", function()
      local input = "/home/user/documents/file.txt"
      assert.are.equal(input, remove_duplicate_separators(input))
    end)

    it("should handle paths with only separators", function()
      local input = "//////"
      local expected = "/"
      assert.are.equal(expected, remove_duplicate_separators(input))
    end)

    it("should return an empty string for empty input", function()
      assert.are.equal("", remove_duplicate_separators(""))
    end)
  end)

  describe('joins paths', function()
    it('single', function()
      assert.are.equal('a', FS.join_path('a'))
      assert.are.equal('a', FS.join_path(nil, 'a'))
      assert.are.equal('a', FS.join_path('', 'a'))
    end)
    it('simple', function()
      assert.are.equal('a/b', FS.join_path('a', 'b'))
      assert.are.equal('a/b/c', FS.join_path('a', 'b', 'c'))
    end)
  end)

  describe('gets file information', function()
    local path

    after_each(function()
      if path then os.remove(path) end
    end)

    it('returns metadata and applies the type filter', function()
      path = os.tmpname()
      local ok = FS.write(path, 'x = 1\n')
      assert.is_true(ok)

      local info = assert(FS.getInfo(path, 'file'))
      assert.same('file', info.type)
      assert.same(6, info.size)
      assert.is_number(info.modtime)
      assert.is_nil(FS.getInfo(path, 'directory'))
    end)
  end)

  describe('renames', function()
    local dir

    before_each(function()
      dir = '/tmp/compy_fs_rename_' .. tostring(math.floor(os.clock() * 1e6))
      os.execute('mkdir -p ' .. dir)
    end)

    after_each(function()
      os.execute('rm -rf ' .. dir)
    end)

    it('moves source to target atomically', function()
      local src = FS.join_path(dir, 'src.hex')
      local dst = FS.join_path(dir, 'microbit.hex')
      assert.is_true(FS.write(src, 'firmware'))
      local ok, err = FS.rename(src, dst)
      assert.is_true(ok)
      assert.is_nil(err)
      assert.is_false(FS.exists(src))
      assert.is_true(FS.exists(dst))
      local rok, content = FS.read(dst)
      assert.is_true(rok)
      assert.are.equal('firmware', content)
    end)

    it('fails for a missing source', function()
      local ok, err = FS.rename(FS.join_path(dir, 'nope'), FS.join_path(dir, 'dst'))
      assert.is_false(ok)
      assert.is_not_nil(err)
    end)
  end)

  describe('writes', function()
    it('and fails when the data does not reach the file', function()
      --- /dev/full takes the write into its buffer and fails
      --- when the buffer goes out, at close
      local ok, err = FS.write('/dev/full', 'x = 1\n')
      assert.is_false(ok)
      assert.is_not_nil(err)
    end)
  end)

  describe('replaces a file', function()
    local dir, target, temp

    local function read(path)
      local f = assert(io.open(path, 'rb'))
      local c = f:read('*a')
      f:close()
      return c
    end

    before_each(function()
      dir = '/tmp/compy_fs_replace_' .. tostring(math.floor(os.clock() * 1e6))
      os.execute('mkdir -p ' .. dir)
      target = FS.join_path(dir, 'main.lua')
      temp = FS.join_path(dir, '.main.lua.tmp')
      assert.is_true(FS.write(target, 'x = 1\n'))
    end)

    after_each(function()
      os.execute('rm -rf ' .. dir)
    end)

    it('with the new content, and no temporary file left', function()
      assert.is_true(FS.replace(target, 'x = 2\n'))
      assert.same('x = 2\n', read(target))
      assert.is_false(FS.exists(temp))
    end)

    it('byte for byte as it was when the write fails', function()
      --- the temporary file cannot be written: a directory
      --- stands in its place
      os.execute('mkdir ' .. temp)
      local ok, err = FS.replace(target, 'x = 2\n')
      assert.is_false(ok)
      assert.is_not_nil(err)
      assert.same('x = 1\n', read(target))
      assert.is_false(FS.exists(temp))
    end)

    it('as it was when the rename fails, and the temporary gone',
      function()
        local rename = FS.rename
        finally(function() FS.rename = rename end)
        FS.rename = function() return false, 'refused' end
        local ok = FS.replace(target, 'x = 2\n')
        assert.is_false(ok)
        assert.same('x = 1\n', read(target))
        assert.is_false(FS.exists(temp))
      end)

    it('removing a temporary file a power cut left', function()
      assert.is_true(FS.write(temp, 'half a fi'))
      assert.is_true(FS.replace(target, 'x = 2\n'))
      assert.same('x = 2\n', read(target))
      assert.is_false(FS.exists(temp))
    end)

    it('durably only when asked', function()
      local fsync = FS.fsync
      finally(function() FS.fsync = fsync end)
      local synced = {}
      FS.fsync = function(path)
        synced[#synced + 1] = path
        return true
      end
      assert.is_true(FS.replace(target, 'x = 2\n'))
      assert.same({}, synced)
      assert.is_true(FS.replace(target, 'x = 3\n', true))
      assert.same({ temp }, synced)
    end)

    it('by a copy that replaces', function()
      local src = FS.join_path(dir, 'main.lua.~save')
      assert.is_true(FS.write(src, 'x = 0\n'))
      local rename = FS.rename
      finally(function() FS.rename = rename end)
      FS.rename = function() return false, 'refused' end
      assert.is_false(FS.cp(src, target, nil, true))
      assert.same('x = 1\n', read(target))
      FS.rename = rename
      assert.is_true(FS.cp(src, target, nil, true))
      assert.same('x = 0\n', read(target))
      assert.is_false(FS.exists(temp))
    end)
  end)
end)
