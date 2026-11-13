### Dev utilities

#### compyfmt

The editor's formatting, gates and lints, at a Compy's width.

```shell
# run from repo root, use lua 5.1 or luajit
# report what formatting would change and what it cannot resolve
luajit util/compyfmt.lua src/examples/tixy/*.lua
# fix: format the files in place, then report what is left
luajit util/compyfmt.lua --fix src/examples/tixy/examples.lua
# strict: report the strict lints as well
luajit util/compyfmt.lua --strict src/examples/tixy/*.lua
```

Reports read `file:line: what`. Both modes exit 1 when they
report anything, 2 when a file cannot be read or, with `--fix`,
written.

A lint's report ends with its rule's name. The lints
(`src/model/lang/lua/lint.lua`) are the limits of
`doc/development/conventions/code.md` and the conventions of
Compy programs such as the examples. The strict ones,
`module-local`, `one-char-name` and `function-name`, are
conventions much existing code breaks.

#### make-tpbot

Makes the microbit project's `tpbot.lua` and `tpbot-radio.lua`
again from the bundled `MICROBIT.hex`: its start-up script and
version, with the robot lessons' words, the block in the
current `tpbot.lua`, added before the script's own setup. Run
it after `MICROBIT.hex` changes, or after the words change in
`tpbot.lua`.

```shell
# run from repo root, use lua 5.1 or luajit
luajit util/make-tpbot.lua
```

## Unit tests

Run the full Lua 5.1 suite from the repository root:

```sh
just ut_all
```

The test entrypoint selects LuaJIT or Lua 5.1 and verifies that Busted is
installed for that runtime before starting the suite.
