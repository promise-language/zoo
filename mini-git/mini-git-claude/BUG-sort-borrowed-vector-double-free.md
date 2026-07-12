Please file this upstream at https://github.com/promise-language/promise/issues

# `sort()` on a **borrowed** vector returns an aliasing vector — moving the result into a struct field double-frees (`fatal: invalid free`)

- **`promise version`:** `promise version 2026.3 (channel stable, commit fe13dcd)`
- **Platform:** macOS 26.5.1 (arm64), Darwin 25.5.0

`sort[T: Ordered](T[] vec) T[]` takes its argument as a **shared borrow**, but behaves as
if it consumes it: the vector it returns aliases the caller's backing buffer rather than
being a fresh allocation. Storing that result into an owned struct field therefore creates
two owners of one buffer, and the program aborts at scope exit.

Memory-unsafe with no `unsafe`, no `move`, and no compiler diagnostic.

## Minimal repro

`repro.pr` — stdlib types only:

```promise
type C { string[] xs; }

mk(string[] xs) C {          // xs is a *borrow*
  string[] s = sort(xs);     // returns a vector aliasing the caller's buffer
  return C(xs: move s);      // the struct now owns it too
}

main() {
  string[] v = ["b", "a"];
  C c = mk(v);               // ...and `v` still owns it here
  print_line("{c.xs.len} {v.len}");
}
```

```sh
$ promise build repro.pr && ./repro
2 2
fatal: invalid free (bad header magic)
$ echo $?
134
```

The program prints the correct answer first and only dies during cleanup, which is what
makes this so easy to miss — the work all *looks* like it succeeded.

**Expected:** either `sort` returns an independent vector (so the move is sound), or the
borrow-checker rejects moving a value derived from a borrowed parameter into an owned field.

## What triggers it

| # | Shape | Result |
|---|---|---|
| 1 | `mk(string[] xs)` → `sort(xs)` → `move` into struct field | **fatal: invalid free** |
| 2 | `mk(string[] move xs)` → `sort(xs)` → `move` into field | ok ✅ |
| 3 | `mk(string[] xs)` → `xs.clone()` → `sort(copy)` → `move` into field | ok ✅ |
| 4 | `mk(string[] xs)` → `sort(xs)` → `return` the vector directly (no struct) | ok ✅ |
| 5 | `mk(string[] xs)` → `xs.clone()` → `move` into field (no `sort`) | ok ✅ |
| 6 | `sort(owned_local)` → `move` into field, inside a function | ok ✅ |
| 7 | `sort(owned_local)` → `move` into field, inline in `main` | ok ✅ |

So all three ingredients are required: **(a)** the vector arrives as a **borrowed**
parameter, **(b)** it is passed through `sort()`, and **(c)** the result is **moved into a
struct field**. Drop any one and it is fine. A custom `Ordered` element type is *not*
needed — plain `string[]` reproduces it.

Note #4: returning the sorted vector straight out of the function is fine, so the bug only
bites when the aliased buffer gets a *second* owner via a field.

## Best guess at the cause

`sort` is an in-place (iterative quicksort) implementation that sorts the caller's buffer
and returns a handle to that same buffer — consistent with the doc's phrasing, *"Sort a
vector and return it (use `v = sort(v)`)"*, and with the fact that `v = sort(v)` is the
documented idiom (self-assignment hides the aliasing). Its signature, though, is an
unmarked `T[] vec`, i.e. a **shared borrow**, so the compiler believes the caller retains
sole ownership. Moving the returned handle into a field hands ownership to the struct while
the caller's binding still owns the same allocation; both destructors run, and the second
`free` sees a poisoned header.

If `sort` really is in-place, its signature should be consuming — `sort[T: Ordered](T[] move vec) T[]`
— which would turn case #1 into a compile error at the call site instead of a silent
double-free. (That is exactly what case #2 shows: once the parameter is `move`, ownership is
single and everything is sound.)

## Workaround used in the real code

`Commit.record` in `main.pr` takes its entry list as `move` (case #2), which is also the
honest signature — the commit owns its entries:

```promise
record(string move parent, string move timestamp, string move message, Entry[] move files) Commit `factory {
  Entry[] sorted = sort(files);
  …
  return Commit(…, files: move sorted);
}
```

Sorting a `.clone()` of the borrowed vector (case #3) works too, at the cost of a copy.

The symptom in the real program was `minigit commit` writing the commit correctly, printing
`committed <id> (2 file(s))`, and *then* aborting with `fatal: invalid free (bad header
magic)` and exit code 134.
