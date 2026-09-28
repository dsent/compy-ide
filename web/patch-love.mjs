// patch-love.mjs LOVE_JS: hand browser storage to the page.
//
// love.js loads the save directory from the browser's IndexedDB at start
// and writes it back only from a beforeunload listener, which a reload
// can end before it finishes. This replaces that block, exactly once, so
// Module.compyStorage in the page (index.html) loads it and saves it.
// A love.js that no longer holds the block fails the build here.
import fs from 'node:fs'

const file = process.argv[2]
const block = 'FS.syncfs(true,function(err){if(err){Module["printErr"](err)}' +
  'else{Module.removeRunDependency("IDBFS_sync")}});' +
  'window.addEventListener("beforeunload",function(event){' +
  'FS.syncfs(false,function(err){if(err){Module["printErr"](err)}})})'
const source = fs.readFileSync(file, 'utf8')
const found = source.split(block).length - 1
if (found !== 1) {
  console.error(`patch-love.mjs: ${file} holds love.js's storage block ` +
    `${found} times, not once, so the web build would lose work on a ` +
    'reload; check love.js in web/package.json against this script')
  process.exit(1)
}
fs.writeFileSync(file, source.replace(block, 'Module.compyStorage(FS)'))
console.log(`patch-love.mjs: storage handed to the page in ${file}`)
