local usb = require('util.usb')

describe('usb detection #usb', function()
  describe('parse_mounts', function()
    it('extracts device, path and fstype', function()
      local m = usb.parse_mounts(
        '/dev/sdb1 /media/user/MICROBIT vfat rw,nosuid,nodev 0 0\n' ..
        '/dev/block/vold/8:1 /storage/1234-ABCD exfat rw 0 0\n' ..
        '/dev/fuse /storage/emulated/0 fuse rw,nosuid 0 0\n')
      assert.are.equal(3, #m)
      assert.are.equal('/dev/sdb1', m[1].device)
      assert.are.equal('/media/user/MICROBIT', m[1].path)
      assert.are.equal('vfat', m[1].type)
      assert.are.equal('/storage/1234-ABCD', m[2].path)
      assert.are.equal('exfat', m[2].type)
      assert.are.equal('/storage/emulated/0', m[3].path)
      assert.are.equal('fuse', m[3].type)
    end)

    it('skips blank and malformed lines', function()
      local m = usb.parse_mounts('\ntmpfs /dev/shm tmpfs 0 0\n')
      assert.are.equal(1, #m)
      assert.are.equal('/dev/shm', m[1].path)
    end)
  end)

  describe('is_removable_fat', function()
    it('accepts FAT filesystems under removable paths', function()
      assert.is_true(usb.is_removable_fat('vfat', '/media/user/MICROBIT'))
      assert.is_true(usb.is_removable_fat('exfat', '/storage/1234-ABCD'))
      assert.is_true(usb.is_removable_fat('fuseblk', '/run/media/user/USB'))
      assert.is_true(usb.is_removable_fat('vfat', '/mnt/media_rw/1234-ABCD'))
    end)

    it('rejects non-FAT and non-removable paths', function()
      assert.is_false(usb.is_removable_fat('ext4', '/mnt/data'))
      assert.is_false(usb.is_removable_fat('vfat', '/'))
      assert.is_false(usb.is_removable_fat('vfat', '/home/user/foo'))
      --- Android internal storage is FUSE too
      assert.is_false(usb.is_removable_fat('fuse', '/storage/emulated/0'))
      assert.is_false(usb.is_removable_fat('fuse', '/storage/self/primary'))
    end)

    it('accepts FUSE only at a USB volume id', function()
      --- how Android shows apps a micro:bit on a Compy
      assert.is_true(usb.is_removable_fat('fuse', '/storage/2702-1974'))
      assert.is_false(usb.is_removable_fat('fuse', '/mnt/media_rw/2702-1974'))
      assert.is_false(usb.is_removable_fat('fuse', '/storage/2702-1974/x'))
    end)
  end)
end)