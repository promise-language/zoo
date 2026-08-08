# line-count — Promise 2026.6

A concurrent line-counting CLI (`main.pr`). It takes file paths as arguments,
fans out **one goroutine per file** (`go count_file(...)` → a `Task[FileResult]`),
counts newlines in each (matching `wc -l`), then fans back in — awaiting the tasks
in argument order so the report is deterministic even though the reads race — and
prints a per-file count plus a grand total. Unreadable files are handled by turning
the I/O error into a `Skipped` enum *value* (never a raised error), so one bad path
is reported on stderr and skipped instead of aborting the run. Data goes to stdout,
diagnostics to stderr, so the totals stay clean when a file is skipped.

Scaffolded with `promise init`, built to a single binary with `promise build`, run
directly. Output on a mixed set (a 3-line file, a no-trailing-newline file, an empty
file, this source, and a missing path):

```
3	/tmp/three.txt
0	/tmp/nonl.txt
0	/tmp/empty.txt
57	main.pr
line-count: /tmp/does-not-exist.txt: no such file or directory   (stderr)
60	total
```

All counts match `wc -l`.

## Did it compile and run on the first try?

Not on the *first* `promise build`, but it took two small fixes — both were me
getting Promise's rules right, **not** compiler bugs, and the compiler's error
messages pointed straight at each one:

1. **`stderr.write_line` is failable; `print_line` is not.** I chose stderr for
   diagnostics (the correct Unix split), which made those calls failable and forced
   `main!()`. Slightly surprising that the plain `print_line` free function is
   infallible while the `Writer`-handle `write_line` is failable — a reasonable
   design (the handle can genuinely fail), just an asymmetry to learn.

2. **The borrow in a `? e { }` handler outlives into the handler body.** In
   `read_content(path) ? e { ... }`, `path` is still borrowed by the failed call
   *inside* the handler, so `move path` there is rejected — I `path.clone()` in the
   `Skipped` branch. After the handler, the borrow has ended, so `move path` is
   accepted in the success branch. The borrow checker is precise enough to allow the
   move in one branch and forbid it in the other, which is exactly what you'd want.
   Consuming the error's own field also needs `move e.message`.

Nothing needed a workaround, and the third re-record in a row (2026.2 → 2026.3 →
2026.6) hit **zero compiler bugs**. No `BUG-*.md` or `FEATURE-*.md` files this run —
the concurrency (`go`/`Task[T]`/`<-`), the enum-as-result pattern, the error
operators, and the ownership annotations all did exactly what the task needed.

## Small things that read nicely

- Modeling the per-file outcome as `enum FileResult { Counted, Skipped }` and
  `match`-ing on `<-t` at the fan-in makes "skip gracefully" a total, exhaustive
  branch rather than scattered error handling — the compiler enforces both cases.
- `go count_file(path.clone())` returning a typed `Task[FileResult]` you later `<-`
  is a clean, statically-typed fork/join with no channel plumbing for this shape.
