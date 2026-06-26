Please file this upstream at https://github.com/promise-language/promise/issues

# A borrowed heap argument passed to `go f(arg)` escapes into the goroutine — accepted, then read after free (non-deterministic wrong results)

- **Promise version:** `promise version 2026.2 (channel stable, commit a68ffb4)`
- **Platform:** macOS 26.5.1 (Darwin 25.5.0), arm64

## What happens

`go f(arg)` where `arg` is a **borrow** of a heap value (e.g. a `string` loop
variable) lets that borrow escape into the goroutine, which outlives the borrow's
scope. The compiler accepts it with no error. At runtime the goroutine reads the
argument after the source slot has been freed/reused, so the result is a
**use-after-free**: output is non-deterministic — usually correct, but sometimes a
field comes back empty/garbage. No crash, no diagnostic; just silently wrong data.

This is the dangerous sibling of the `move` crash (separate file): the `move` form
*should* work but crashes; this borrow form *should be rejected* but is accepted.

## Minimal repro

`main.pr` (a `promise init` project, this as the only source file):

```promise
type Box { string s; }
keep(string p) Box { return Box(s: p.clone()); }   // borrows p (no move), clones into the result
main!() {
    string[] xs = ["alpha", "bravo", "charlie"];
    Task[Box][] ts = [];
    for x in xs { ts.push(go keep(x)); }   // <-- borrow of a heap loop var escapes into the goroutine
    for t in ts { Box b = <-t; print_line("[{b.s}]"); }
}
```

Build & run **several times**:

```
promise build && ./<module-name>
```

Verbatim output across two runs (note the difference — it is non-deterministic):

```
[alpha]
[bravo]
[charlie]
---
[alpha]
[]            <-- "bravo" came back empty: read after free
[charlie]
```

## Expected behavior

A borrow may not outlive the value it borrows. A goroutine can outlive the loop
iteration whose local it borrowed, so passing a borrow of `x` into `go keep(x)`
should be a **compile-time error** ("borrowed value does not live long enough" /
"borrow escapes into goroutine") — the same way the guide says borrows are
stack-bounded and can't be stored in fields. Forcing the caller to transfer
ownership (`move`) or share via `Ref[T]` would make the lifetime sound. What must
*not* happen is silent acceptance followed by a racy use-after-free.

## What does / doesn't trigger it

Verified — repro is racy/wrong, every "fine" control is sound:

| Variant | Result |
|---|---|
| `go keep(x)` (borrow), handles awaited after the loop | **non-deterministic wrong data** (UAF) |
| Same, but await *immediately* inside the loop iteration (`t := go keep(x); <-t`) | happens to work — borrow still alive at await time |
| Direct call `Box b = keep(x)` (no `go`) | ok |
| `go { ch.send(keep_owned(move x)); }` — block capture + ownership transfer | ok ← the sound form |

The "await immediately" case working is itself a tell: correctness depends on
*when* the goroutine is scheduled relative to the borrow's scope, which is exactly
the lifetime hole.

## Best guess at the cause

Escape analysis for borrows doesn't account for the `go f(arg)` boundary: a
goroutine call is treated like an ordinary call for borrow-lifetime purposes, so a
borrow whose lifetime ends at the end of the loop iteration is allowed to flow into
a task that may run later. The goroutine then dereferences a freed/overwritten
slot — hence the non-determinism (it depends on scheduling and allocator reuse).

## Workaround used in the real program

Never pass a borrow into a goroutine. Transfer ownership of the per-item heap value
into a `go { … }` block by `move`, and return results over a channel:

```promise
for i, path in paths {
    go { ch.send(count_file(i, move path)); };   // ownership moves in; nothing borrowed escapes
}
```
