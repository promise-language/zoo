# line-count — summary

## What I built

A small command-line tool (`main.pr`) that takes file paths as arguments and counts the
lines in each, **one goroutine per file**, then prints a per-file count and a grand
total. Each goroutine sends its result down a `channel[FileCount]`; `main` gathers them
into a `map[int, FileCount]` keyed by the file's argument index so the output is printed
in the original argument order even though goroutines finish in any order. Unreadable
files (missing, no permission, etc.) are caught with a `? e { ... }` handler and reported
as skipped — one bad path can't crash the run, and the grand total counts only the
readable files. Scaffolded with `promise init`, built to a single self-contained binary
with `promise build`.

Line semantics: it counts each newline-terminated line plus a final unterminated line if
present (via `io.File.read_line`), so a file ending without a newline still counts its
last line — slightly different from `wc -l`, which counts newline characters.

## Did it compile and run on the first try?

No — the *design* was right early, but it took several iterations to get past the
language's rough edges (details below). Once it compiled, it ran correctly the first
time, and 20 back-to-back runs produced byte-identical, correctly-ordered output (no
races, no crashes).

## Program output

```
$ ./line-count-claude sample/fruits.txt sample/nums.txt sample/empty.txt sample/missing.txt
       3  sample/fruits.txt
       4  sample/nums.txt
       0  sample/empty.txt
       -  sample/missing.txt  (skipped: no such file or directory)
       7  total
(1 file(s) skipped)
```

With no arguments it prints a short usage message instead.

## What surprised me / had to work out

Promise isn't in my training data, so I learned it from `promise guide` and
`promise doc <module>`. Things that bit me:

- **`error.message` is a getter, not a method.** The guide's own examples write
  `e.message()`, but the compiler rejects that — it's `e.message` (property syntax).
- **Concurrency ownership is subtle.** Passing an owned string into the *task-handle*
  form `t := go f(x); <-t` double-frees and aborts at runtime. I had to fall back to the
  `go { ch.send(...) }` block + channel form, which is clean. (Bug #1 below.)
- **The move-checker is not flow-sensitive** the way I expected, and **plain `string p`
  parameters consume rather than borrow** — directly contradicting the guide. This
  produced a stream of "use of moved variable" errors on code the guide says is valid,
  and pushed me to redesign the result struct so it no longer stores the path (the path
  list already lives in `main`). Explicit `string &p` is the real borrow. (Bug #4 below.)
- **Three different inputs crashed the *compiler* itself** (Go panics / LLVM-IR errors),
  rather than producing diagnostics. Each took some bisection to pin to a minimal
  trigger. (Bugs #2 and #3, plus #1's runtime abort.)
- Nice surprises: `channel[T]` + `for v in ch`, the `? e { ... }` recovery handler, and
  `use x := resource` cleanup are genuinely pleasant once you know the gotchas, and the
  `promise doc` output is accurate and fast to navigate.

## Upstream issues to file

I minimized each to the smallest triggering source and verified the "compiles fine"
controls actually compile. Four files, one issue each — **please submit these**:

1. `BUG-go-task-handle-consumes-heap-arg-double-free.md` — `t := go f(x); <-t`
   double-frees a heap argument the callee consumes (`fatal: invalid free`). Workaround:
   `go { }` block + channel (what this program uses).
2. `BUG-use-binding-implicit-autopropagate-codegen-panic.md` — `use x := failable()` with
   implicit auto-propagation panics codegen (`genUseVarDecl`). Workaround: add `?^`.
3. `BUG-value-field-in-non-value-struct-codegen-panic.md` — a `` `value `` field mixed
   with a heap field panics codegen instead of giving a diagnostic. Workaround: drop the
   unnecessary `` `value `` annotations.
4. `BUG-plain-string-param-consumes-contradicts-guide.md` — plain `string p` consumes its
   argument, contradicting the guide's "plain `T` param is a borrow." Workaround: use
   `string &p` for an actual borrow; treat plain params as consuming.

No `FEATURE-*.md`: the standard library had everything the task needed (`os.args`,
`io.File`, channels, goroutines, `map`). The friction was all bugs/semantics, not gaps.
