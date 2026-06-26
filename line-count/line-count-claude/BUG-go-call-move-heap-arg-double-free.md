Please file this upstream at https://github.com/promise-language/promise/issues

# `go f(move s)` in a loop double-frees a heap argument moved into the goroutine's heap return value

- **Promise version:** `promise version 2026.2 (channel stable, commit a68ffb4)`
- **Platform:** macOS 26.5.1 (Darwin 25.5.0), arm64

## What happens

Spawning a goroutine with the *call* form `go f(move s)` — where `s` is a heap
value (e.g. `string`), `f` consumes it by `move`, and `f` returns a heap value
that **stores** the moved `s` — corrupts the heap when the spawn is executed more
than once (i.e. in a loop). The first iteration is fine; a later one aborts with:

```
fatal: invalid free (bad header magic)
```

(When the task handles are stored and awaited *after* the loop, the same
corruption instead surfaces as `fatal: stack overflow`.)

## Minimal repro

`main.pr` (a `promise init` project, this as the only source file):

```promise
type Box { string s; }
store(string move s) Box { return Box(s: move s); }   // returns a heap value holding the moved string
main!() {
    string[] xs = ["aa", "bb", "cc"];
    for x in xs {
        t := go store(move x);   // <-- move a heap string into a goroutine *call*, in a loop
        Box b = <-t;
        print_line("{b.s}");
    }
}
```

Build & run:

```
promise build && ./<module-name>
```

Verbatim output:

```
aa
fatal: invalid free (bad header magic)
```

## Expected behavior

Each iteration moves a distinct heap string into its goroutine; `store` takes
ownership and hands it back inside a `Box`. There is exactly one owner at every
step, so this should print `aa`, `bb`, `cc` and exit cleanly — the same as the
non-`go` version does.

## What does / doesn't trigger it

Verified — repro aborts, every "compiles & runs fine" control actually runs clean:

| Variant | Result |
|---|---|
| `for x in xs { t := go store(move x); <-t }`, `store` returns `Box{s}` (heap, holds `s`) | **crash** (`invalid free`) |
| Same, but task handles pushed to an array and awaited after the loop | **crash** (`stack overflow`) |
| Same loop, **interpolated** fresh string `string x = "v{i}"` instead of a vector element | **crash** (`invalid free`) |
| Single spawn, no loop: `string x="a"; t := go store(move x); <-t` | ok |
| Two straight-line spawns of distinct vars (no loop) | ok |
| Loop, but `store` returns `int` (consumes `s`, returns a non-heap value) | ok |
| Loop, but **direct call** `Box b = store(move x)` (no `go`) | ok |
| Loop, but reuse of a shared **constant literal** `string x = "abc"` each iteration | ok (literal isn't a unique heap allocation) |
| Loop, but `go { ch.send(store(move x)); }` — **`go {}` block capture** + channel | ok ← workaround |

So the trigger is the conjunction: **(a)** the `go f(arg)` *call* form (not a
`go {}` block), **(b)** a genuinely heap-allocated argument passed by `move`,
**(c)** `f` returns a heap value that retains the moved argument, and **(d)** the
spawn runs more than once.

## Best guess at the cause

The moved heap argument appears to be freed twice: once on the path that hands it
across the goroutine call/return boundary into the returned `Box`, and again by
the per-iteration teardown of the (now-consumed) source slot — the `move` out of
the call-form argument doesn't fully transfer the free obligation, so on the
second iteration the allocator sees a stale/duplicate free (`bad header magic`).
That it depends on the return value *retaining* the string (heap return, control
"returns `int`" is clean) points at the move-through-`go`-call → returned-aggregate
ownership transfer specifically, not at the loop alone (the non-`go` loop is fine).

## Workaround used in the real program

Avoid the `go f(move s)` call form entirely. Spawn a `go { … }` block that
captures the heap value by `move` and sends the result back over a channel:

```promise
for i, path in paths {
    go { ch.send(count_file(i, move path)); };   // block capture, not go f(arg)
}
```

This runs cleanly and deterministically (verified over 20 byte-identical runs).
