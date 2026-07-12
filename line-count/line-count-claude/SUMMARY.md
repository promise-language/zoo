# Summary

A small concurrent line-counter in Promise. It takes file paths as arguments,
spawns **one goroutine per file** (`go count_file(path.clone())`) so all the
reads race, then fans in by awaiting each `Task[FileResult]` in argument order —
so the output stays deterministic even though the reads finish in whatever order.
Each file reports its line count (newline characters, matching `wc -l`), and a
grand total is printed at the end. Unreadable files are captured as a `Skipped`
enum variant rather than a raised error, so a missing path or a directory is
reported and skipped instead of crashing the run.

## Did it compile and run first try?

Almost. It **ran correctly the first time it compiled**, but the first `promise
build` failed on two ownership errors, both inside the file-read error handler:

1. `cannot move 'path' while it is borrowed` — I tried to `move path` into the
   `Skipped` result *inside* the `? e { ... }` handler of
   `io.File.read_content(path)`. The borrow of `path` by `read_content` is
   considered live across its own error handler, so the move is rejected. Fix:
   `path.clone()` in the (rare) error path, and keep the `move` on the success
   path where no borrow is outstanding.
2. `consuming 'e.message' requires 'move e.message'` — reading a `string` field
   out of the error binding is a move; `e.message.clone()` fixes it.

Both were reasonable borrow-checker messages that pointed straight at the fix.

## Program output

```
$ ./line-count-claude three.txt notrail.txt empty.txt five.txt does-not-exist.txt /some/dir
3	three.txt
1	notrail.txt
0	empty.txt
5	five.txt
skipped	does-not-exist.txt (no such file or directory)
skipped	/some/dir (is a directory)
9	total
```

The counts match `wc -l` exactly. With no arguments it prints a usage line.

## What surprised me / had to work out

- **The concurrency model is genuinely pleasant.** `go count_file(...)` returns a
  `Task[FileResult]`, you collect them into a `Task[FileResult][]`, and `<-t`
  awaits. The fan-out/fan-in shape is a few lines and reads clearly. Notably,
  passing an owned `string move path` into a goroutine worked without any of the
  friction I half-expected around escaping heap values — I just had to hand the
  goroutine ownership (a `.clone()` off the borrowed loop variable).
- **A borrow lives across its own error handler.** This is the one non-obvious
  rule I hit: after `read_content(path)` fails, `path` is still considered
  borrowed inside the `? e { }` block, so you can't move it out there. Once you
  know it, cloning in the error branch is a fine idiom (errors are rare), but it
  surprised me since conceptually the call has already returned by the time the
  handler runs.
- **Line-count semantics.** I count `'\n'` characters (so `wc -l` semantics: a
  final line with no trailing newline isn't counted). Iterating a string with
  `for c in content` yields `char`s, which made this a clean four-line loop.

## Rough edges

Nothing that rises to a compiler bug or a missing feature — no `BUG-*.md` or
`FEATURE-*.md` this run. One minor ergonomic note, not filed:

- **`promise run` has no way to forward argv to the program.** `promise run
  main.pr -- foo.txt` and `promise run . foo.txt` both treat the trailing paths
  as *additional source files to compile* (you get a parse error on the file's
  contents), rather than passing them to the program's `os.args`. For a tool that
  takes file arguments this means you must `promise build` and invoke the binary
  directly to exercise it. That's exactly what the task asked for, so it wasn't a
  blocker — but a `promise run <target> -- <args...>` passthrough would make the
  edit/run loop nicer.
