# Summary

## What I built

A concurrent line-counting CLI (`main.pr`). It reads file paths from `os.args`,
spawns **one goroutine per file**, and each goroutine streams its file a line at a
time (`io.File.read_line`) to count lines. Results come back over a `channel`;
`main` gathers them, sorts by the original command-line index so output is
deterministic regardless of which goroutine finishes first, then prints a
right-aligned per-file count plus a grand total. Unreadable files are **skipped
gracefully**: each goroutine recovers from its own I/O error (`? e { … }`) and
reports a `skip` line instead of crashing the batch.

Example run:

```
       3  /tmp/lc_a.txt
       2  /tmp/lc_b.txt
       0  /tmp/lc_empty.txt
    skip  /tmp/does_not_exist.txt  (no such file or directory)
      86  main.pr
      91  total
```

Built with `promise build` into a single self-contained binary; output is
byte-identical across 20 runs (verified).

One deliberate semantic choice: I count *lines of text* via `read_line`, so a
final line with no trailing newline still counts (the `2` for `/tmp/lc_b.txt`,
which holds `"alpha\nbeta"`). That differs from `wc -l`, which counts newline
*characters* and would report `1`. Empty file → `0`, as expected either way.

## Did it compile and run on the first try?

No — the program itself is small, but getting data to and from goroutines was a
minefield. The *final* shape is clean, but I reached it only after hitting **three
distinct compiler bugs**, all on the goroutine-data-passing surface this task is
built to exercise. The natural first thing to write — `for path in paths { t := go
count_file(path); … }` — is broken three different ways depending on how you pass
the argument:

- pass it **by move** (`go f(move x)`) → heap **double-free** crash in a loop;
- pass it **by borrow** (`go f(x)`) and await later → **use-after-free**, silently
  wrong (sometimes empty) results;
- make the goroutine function **failable** (`go f!()`) → the **compiler panics** in
  codegen.

What finally works, and reads cleanly, is: a `go { … }` *block* (not the `go
f(arg)` call form) that captures the path by `move`, calling a **non-failable**
function that handles its own error, with results returned over a `channel`. That
sidesteps all three bugs at once. Each is minimized with verified controls and
written up for upstream (see below).

## What surprised me / had to work out

- **The error operators are precise and worth respecting.** `?!` is *always*
  panic, never propagate; in a failable (`!`) function you just call bare and the
  error auto-propagates. `<-t` on a goroutine yields a *plain* value, so a
  goroutine's failure has nowhere to go at the await boundary — which is the
  language nudging you toward "each worker handles its own error and returns a
  result," exactly what graceful skipping wants.
- **Ownership across the goroutine boundary is the whole game.** A borrow can't
  outlive the goroutine, and a `move` consumes the loop variable — both reasonable,
  but the compiler enforces them *unevenly* here (it correctly blocks moving a
  still-borrowed value, yet wrongly accepts a borrow escaping into a goroutine).
  The mental model that works: hand a goroutine **ownership** (via a `move`-capturing
  `go {}` block) or share via `Ref[T]`; never lend it a borrow.
- **`sort` via the structural `Ordered` interface is delightful** — define `==` and
  `<` on `FileCount` and `sort(results)` just works, no comparator plumbing.
- **Small parser sharp edges:** `slots[idx] = move r;` (a `move` on the RHS of an
  index-assignment) fails to parse, and `T?[].filled(none, …)` mis-reads the `?` of
  the optional element type as an error operator. Both were easy to route around
  (collect-then-`sort` instead of placing by index), so I didn't write them up as
  full bugs — but they're rough.

## Rough edges filed for upstream

Three `BUG-*.md` files, each with a minimal repro and verified "compiles/runs fine"
controls — **please submit these**:

1. **`BUG-go-call-move-heap-arg-double-free.md`** — `go f(move s)` in a loop, where
   `f` returns a heap value holding the moved `s`, double-frees → `fatal: invalid
   free (bad header magic)`.
2. **`BUG-go-call-borrowed-heap-arg-escapes-goroutine-uaf.md`** — a borrowed heap
   argument passed to `go f(arg)` escapes into the goroutine; accepted with no
   error, then read after free → non-deterministic wrong/empty results. (Should be
   a compile error.)
3. **`BUG-go-spawn-failable-call-codegen-panic.md`** — `go <failable-call>` panics
   the compiler in codegen (`store operands are not compatible` bare; `non-call
   expr *ast.ErrorPanicExpr` with `?!`) instead of compiling or diagnosing.

No `FEATURE-*.md`: the standard library had everything the task needed
(`os.args`, `io.File`, channels, goroutines, `sort`). The gaps here are bugs in
existing features, not missing ones.
