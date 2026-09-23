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
end)
