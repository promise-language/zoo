Please file this upstream at https://github.com/promise-language/promise/issues

# `use io;` in two files of the same project is a redeclaration error, so a source file cannot declare its own imports

`promise version 2026.6 (channel stable)` · macOS 26.5.1 (arm64, Apple Silicon)

## Minimal repro

A two-file application project where both files import `io`:

`promise.toml`

```toml
[module]
name = "dupuse"
epoch = "2026.6"
main = "main.pr"
```

`helper.pr`

```promise
use io;

helper_exists(string p) bool `public => io.File.exists(p);
```

`main.pr`

```promise
use io;

main() {
  print_line("{helper_exists("/etc/hosts")} {io.File.exists("/etc/hosts")}");
}
```

```sh
promise build
```

Verbatim output (exit 1):

```
/tmp/proj/main.pr:1:0: io redeclared in this scope (previous at /tmp/proj/helper.pr:1:0)
  > use io;
    ^
```

## Expected behavior

Each file should be able to declare the modules it uses; importing the same
module in two files of one project should be idempotent, not a redeclaration.
Today the only way to build is to delete the `use` from all but one file, which
means a file's dependencies are invisible in that file — `store.pr` in this
project calls `io.File`/`path.join` with no `use` anywhere in it, and a reader has
to know that `main.pr` imported them.

## What triggers it

| Setup | Result |
|---|---|
| `use io;` in `helper.pr` **and** `main.pr` | **`io redeclared in this scope`** |
| `use io;` in `helper.pr` only; `main.pr` still writes `io.File.exists(...)` | compiles, prints `true true` |
| `use io;` in `main.pr` only; `helper.pr` still writes `io.File.exists(...)` | compiles, prints `true true` |
| `use io;` once, `use io as _;` in a second file | not tried |

The second and third rows are the interesting part: the import is
*project-global*, so the prefix works in every file regardless of which file
imported it — the error is purely about naming the import twice.

## Best guess at the cause

A project's `.pr` files are merged into one scope (which is also why top-level
`public` functions are visible across files with no import at all), and `use`
inserts the module alias into that shared scope with an unconditional
"redeclared in this scope" check instead of treating an identical import as a
no-op.

## Workaround used in the real code

All four modules are imported once, in `main.pr`, with a comment pointing at this
bug so the other files' bare `io.`/`path.`/`time.` prefixes are not a mystery:

```promise
// A project's .pr files share one scope, so every module the project uses is
// imported once, here, and reached as `io.`/`path.`/... from any file.
use io;
use os;
use path;
use time;
```
