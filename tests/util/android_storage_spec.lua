local AndroidStorage = require('util.androidStorage')

--- Mount lines as a Compy lists them with its SD card and a
--- micro:bit drive attached, options shortened.
local card_vold = '/dev/block/vold/public:179,17 '
  .. '/mnt/media_rw/6BBF-F260 exfat rw,dirsync,nosuid 0 0'
local card_fuse = '/dev/fuse /storage/6BBF-F260 fuse '
  .. 'rw,lazytime,nosuid,allow_other 0 0'
local card_pass = '/dev/block/vold/public:179,17 '
  .. '/mnt/pass_through/0/6BBF-F260 exfat rw,dirsync 0 0'
local usb_vold = '/dev/block/vold/public:8,0 '
  .. '/mnt/media_rw/2702-1974 vfat rw,dirsync,nosuid 0 0'
local usb_fuse = '/dev/fuse /storage/2702-1974 fuse '
  .. 'rw,lazytime,nosuid,allow_other 0 0'
local emulated = '/dev/fuse /storage/emulated fuse '
  .. 'rw,lazytime,nosuid,allow_other 0 0'

local function mounts(...)
  return table.concat({ ... }, '\n') .. '\n'
end

--- Where no card is found, the IDE uses internal storage.
describe('Android SD card lookup #util', function()
  it('chooses the card over a micro:bit drive listed first',
    function()
      local text = mounts(emulated, usb_vold, usb_fuse,
        card_vold, card_fuse, card_pass)
      assert.same('/storage/6BBF-F260',
        AndroidStorage.find_card(text))
    end)

  it('chooses the card over a volume without a vold line',
    function()
      assert.same('/storage/6BBF-F260', AndroidStorage.find_card(
        mounts(usb_fuse, card_vold, card_fuse)))
    end)

  it('never chooses a micro:bit drive alone', function()
    assert.is_nil(AndroidStorage.find_card(
      mounts(emulated, usb_vold, usb_fuse)))
    assert.is_nil(AndroidStorage.find_card(
      mounts(emulated, usb_fuse)))
  end)

  it('never chooses a card without its vold line', function()
    assert.is_nil(AndroidStorage.find_card(
      mounts(usb_vold, usb_fuse, card_fuse)))
    assert.is_nil(AndroidStorage.find_card(
      mounts(emulated, card_fuse, card_pass)))
  end)

  it('finds nothing when no vold lines exist', function()
    assert.is_nil(AndroidStorage.find_card(
      mounts(usb_fuse, card_fuse)))
  end)

  it('finds nothing without a portable volume', function()
    assert.is_nil(AndroidStorage.find_card(mounts(emulated)))
    assert.is_nil(AndroidStorage.find_card(''))
    assert.is_nil(AndroidStorage.find_card(nil))
  end)
end)
