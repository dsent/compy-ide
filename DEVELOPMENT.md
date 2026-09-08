## Cloning

A plain clone gives you everything:

```shell
git clone
```

The libraries under `src/lib/` are tracked files, so there is
nothing to initialize afterwards. Each carries its own `README.md`
recording where it came from and at which commit; edit those copies
here rather than upstream.

## Installing

To run the code, [LÖVE2D] is required. It's been tested and
developed on version 11.5 (Mysterious Mysteries).

For unit tests, we are using the [busted] framework. Also, we
need to supply a [utf-8][luautf8] library, one of which comes
with LOVE, but is not available for Lua 5.1 / Luajit by default.
[Luafilesystem][lfs] is used in some tests and utility scripts
used for generating documentation.

The recommended way of installing these is with [LuaRocks]:

```sh
luarocks --local --lua-version 5.1 install busted
luarocks --local --lua-version 5.1 install luautf8
luarocks --local --lua-version 5.1 install luafilesystem
```

For information about installing [LÖVE2D] and [LuaRocks], visit
their respective webpages.

### Web version

Hacking on this requires [Node.js][node] and [NPM][npm] (or your
[node runtime][deno] and [package manager][yarn] of choice), to
run [love.js].

### Tools

* [Just](just)
* [nodemon]
* [live-server]
* [rsync]

For automating tasks, we use [just][just]. For example, to set
up the [web version](#web-version) for development, you can run

```sh
just setup-web-dev
```

## Development

### [OOP](doc/development/OOP.md)

### `util/lua.lua` (luautils)

The contents of this module will be put into the global
namespace (`_G`). However, the language server does not pick up
on this (yet), so usages will be littered with warnings unless
silenced.

#### `prequire()`

Analogous to `pcall()`, require a lua file that may or may not
exist. Example:

```lua
--- @diagnostic disable-next-line undefined-global
local autotest = prequire('tests/autotest')
if autotest then
  autotest(self)
end
```

### Web version

[lovejs][love.js]

## Test mode


The game can be run with a `test` subcommand, which causes it to
launch in test mode.

```sh
love src test
```
### flags

#### auto

```sh
love src test --auto
```

Run the autotest function on startup. This is optionally defined
in `tests/autotest.lua` with the following signature:
```lua
--- @param self ConsoleController
local function autotest(self)
  --- commands here
end

return autotest
```

#### size

```sh
love src test --size
```

This is causes the terminal and the input field to be smaller
(so overflows are clearly visible).

#### draw

```sh
love src test --draw
```

For testing blend modes, draws several small canvases
(implies `--size`).

### Running unit tests

In project root:

```sh
busted tests
```

## Environment variables

### Debug mode

Certain diagnostic key combinations are only available in debug
mode, to access this, run the project with the `DEBUG`
environment variable set (it's value doesn't matter, just that
it's set):

```sh
DEBUG=1 love src
```

In this mode, a VT-100 terminal test can be activated with ^T
(C-t, or Ctrl+t).

### HiDPI

Similarly, to set double scaling, set the `HIDPI` variable to
`true`:

```sh
HIDPI=true love src
```

[löve2d]: https://love2d.org
[busted]: https://lunarmodules.github.io/busted/
[lfs]: https://lunarmodules.github.io/luafilesystem/
[luautf8]: https://github.com/starwing/luautf8
[luarocks]: https://luarocks.org/
[love.js]: https://github.com/Davidobot/love.js
[node]: https://nodejs.org/
[npm]: https://nodejs.org/en/learn/getting-started/an-introduction-to-the-npm-package-manager
[deno]: https://deno.land/
[yarn]: https://yarnpkg.com/
[just]: https://github.com/casey/just
[live-server]: https://github.com/tapio/live-server
[nodemon]: https://nodemon.io/
[rsync]: https://rsync.samba.org/
