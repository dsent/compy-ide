# metalua (vendored)

The part of [Metalua](https://github.com/compy-toys/metalua) the Compy editor
reads: the front end that turns Lua source into a checked AST, plus the printer
that turns an AST back into source.

## Origin

- Upstream: `https://github.com/compy-toys/metalua.git`, branch `dev`
- Imported at commit `d0dbd0d982f87512b806949ea697ea71f39cd0b4`
- That commit is `refs/pull/3/head`. PR #3 was merged into `dev` by
  rebase, so `dev` carries the same five commits under different
  hashes and its head `a42b3918` has an identical tree
  (`5e4d41cc483fad980d742b92a1ab44cd05b93665`). The import is `dev`'s
  content, reached by the hash the IDE was pinned at.
- Upstream of that fork: Eclipse Koneki Metalua 0.7.2

## What is here

`metalua-parser`'s modules, which upstream packages separately from the
bytecode compiler:

- `metalua/grammar/lexer.lua`, `metalua/grammar/generator.lua`
- `metalua/compiler/parser.lua` and `metalua/compiler/parser/*`
- `metalua/compiler.lua` — the front end `model.lang.lua.parser` instantiates
- `metalua/pprint.lua`
- `checks.lua` — argument checking, required by the front end; installs a
  global `checkers` table

Plus one module from `metalua-compiler`:

- `metalua/compiler/ast_to_src.lua` — the source printer the editor uses to
  render a chunk back to text

`checks.lua` and `ast_to_src.lua`'s stringutils dependency resolve through the
editor's own `src/util/string`, reached as `util.string.string`.

## What was left behind

The bytecode compiler (`metalua/compiler/bytecode*`), the metaprogramming
loader (`metalua/loader.lua`, `metalua/compiler/globals.lua`), the CLI
(`metalua.lua`), and every `.mlua` source — extensions, `repl`, `treequery`,
`dollar`. Nothing loads the Metalua loader at runtime, so no `.mlua` file is
reachable. The AST test corpus moved to `tests/interpreter/ast_inputs.lua`.

## License

Metalua is dual-licensed MIT and EPL-1.0 upstream. This copy is carried under
MIT alone; see `LICENSE`. The per-file headers keep the authors' copyright and
contributor lines and name MIT as the single grant.

## Changing this code

Edit it here. This is a vendored copy, not a submodule, and the fork it came
from already diverges from Eclipse Metalua in `grammar/lexer.lua`,
`grammar/generator.lua`, `compiler.lua`, and `compiler/ast_to_src.lua`.
