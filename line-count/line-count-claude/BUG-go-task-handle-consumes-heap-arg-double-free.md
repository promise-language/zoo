Please file this upstream at https://github.com/promise-language/promise/issues

# `go f(arg)` task handle double-frees a heap argument the callee consumes (`fatal: invalid free`)

**promise version:** 2026.0 (commit 6adc8907003f3939c5fd8eaf88445893c37b23de)
**Platform:** macOS 26.5.1 (arm64)

## Summary

The task-handle form of `go` — `t := go f(x); r := <-t;` — corrupts the heap when
`f` consumes a heap-allocated argument by ownership (e.g. a `~string` that is not a
string literal). The program compiles, prints the correct result, and then aborts
with `fatal: invalid free (bad header magic)`, which is a double-free of the
argument's backing buffer. The equivalent fire-and-forget `go { ... }` block + channel
form is unaffected.

## Minimal repro

`main.pr`:

```promise
type R { int n; }
f(~string p) R { return R(n: p.len); }
main() {
  string s = "alpha";
  t := go f(s.clone());   // heap string moved into the goroutine call
  r := <-t;
  print_line("n={r.n}");
}
```

Build & run command:

```sh
promise run        # (or: promise build && ./<binary>)
```

## Verbatim output

```
n=5
fatal: invalid free (bad header magic)
```

(The correct line count `n=5` prints first; the abort happens as the task is reaped.)

## Expected behavior

`n=5` and a clean exit, exactly like the channel-based control below.

## What does / doesn't trigger it

All cases below compile; the table is about runtime behavior.

| Variant | Result |
|---|---|
| `t := go f(s.clone()); <-t` with `f(~string p)` (consumes heap string) | **double-free abort** |
| same but argument is a string literal: `go f("alpha")` | OK (n=5) |
| same but `f` takes a borrow `f(string &p)` instead of `~string` | OK (n=5) |
| `f(~string)` called synchronously (no `go`) with a heap clone | OK (n=5) |
| `go { ch.send(f(s.clone())); }` + `if r := <-ch { }` (channel, not handle) | OK (n=5) |
| `go work(21); <-t` with `work(int)` (Copy arg, nothing to free) | OK |

So the trigger is the conjunction of: the **`Task[T]` handle** form (`go f(...)` awaited
with `<-`), **ownership transfer** of the argument into the callee (`~T`), and a
**heap-allocated** argument value (a clone / computed string, not a static literal).

## Best guess at cause

The task-handle path appears to free the moved-in argument when the `Task`/`G` is
reaped, while the caller's binding for the same value is also freed at its scope exit —
a double free. With a borrow param the caller retains sole ownership (one free); with a
string literal the buffer is presumably statically allocated (not heap-freed); with the
`go { }` block + channel form, ownership flows through the closure capture path, which
is handled correctly.

## Workaround used

Use the `go { ... }` block + channel form instead of the task-handle form whenever an
owned heap value is handed to the goroutine:

```promise
channel[R] ch = channel[R](capacity: n);
go { ch.send(f(s.clone())); };
if r := <-ch { ... }
```

This is what `main.pr` in this project does (one goroutine per file, each `send`-ing its
result down a channel).
