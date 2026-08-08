Please file this upstream at https://github.com/promise-language/promise/issues

# `promise run` cannot pass command-line arguments to the program it runs

`promise version 2026.6 (channel stable)` · macOS 26.5.1 (arm64, Apple Silicon)

## What I needed and why

The task was a CLI tool — `minigit init`, `minigit add <file>`,
`minigit commit -m "<message>"` — so every single iteration of the
edit/run/inspect loop needs argv. `promise run` is the advertised way to "compile
and run a Promise source file or project", but there is no way to hand the
program its arguments.

## What is missing

`promise run` treats every token after the source file as another source file,
including after a `--` separator. `promise run --help` documents no argument
forwarding and no `--` convention.

```promise
// argsprobe.pr
use os;
main() { print_line("args={os.args}"); }
```

```sh
$ promise run argsprobe.pr one two
error reading two: open two: no such file or directory

$ promise run argsprobe.pr -- one two
error reading two: open two: no such file or directory

$ promise run -- argsprobe.pr one
error reading one: open one: no such file or directory
```

`os.args` itself works fine — built with `promise build`, `./minigit add a.txt`
sees `[add, a.txt]`. The gap is only in `promise run`.

## Did it block me?

No — it forced a workaround. The task asked for `promise build` plus running the
binary anyway, so every check during development went through
`promise build && ./minigit <args>` from a scratch directory. For anyone
prototyping a CLI with `promise run`, though, this is the first wall they hit.

## Sketch of the API that would have made it clean

Adopt the `cargo run` / `go run` convention — everything after `--` is the
program's argv, never a source file:

```sh
promise run .                      # no arguments, as today
promise run . -- add a.txt         # os.args == ["add", "a.txt"]
promise run main.pr -- commit -m "hello"
```

Equivalently, once a project or a single source file has been resolved, treat all
remaining tokens as program arguments rather than extra inputs.
