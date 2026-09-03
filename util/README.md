### Dev utilities

#### compyfmt

```shell
# run from repo root, use lua 5.1 or luajit
luajit util/compyfmt [file]
# overwrite the original file with -w or --write
luajit util/compyfmt [file] -w
# example
luajit util/compyfmt.lua src/examples/tixy/examples.lua -w
```

## Unit tests

Run the full Lua 5.1 suite from the repository root:

```sh
just ut_all
```

The test entrypoint selects LuaJIT or Lua 5.1 and verifies that Busted is
installed for that runtime before starting the suite.
