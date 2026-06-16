Please file this upstream at https://github.com/promise-language/promise/issues

# Plain `string p` parameter consumes its argument — contradicts the guide ("plain `T` param is a borrow")

**promise version:** 2026.0 (commit 6adc8907003f3939c5fd8eaf88445893c37b23de)
**Platform:** macOS 26.5.1 (arm64)

## Summary

`promise guide` states, under Ownership & Borrowing:

> `borrow(string s) { }` // shared borrow — caller still owns; callee may not consume
> Move types: string, collections, heap types — plain `T` param is a borrow; add `~T` to consume.

But in practice a plain `string p` parameter **consumes (moves)** its argument: after
passing a variable to such a parameter, the caller can no longer use it — not even
`.clone()` it. Only an explicit `string &p` parameter behaves as the documented shared
borrow. So either the compiler is wrong (plain `T` should borrow) or the guide is wrong
(plain `T` consumes; use `&T` to borrow). The two disagree, and the guide's wording cost
real time to debug.

## Minimal repro

`main.pr`:

```promise
type R { string s; }
look(string p) int { return p.len; }   // guide: "plain T param is a borrow"
main() {
  string path = "abcd";
  look(path);                 // if this only borrows, `path` is still usable after
  R r = R(s: path);           // move `path` into R
  print_line(r.s);
}
```

Build command:

```sh
promise build
```

## Verbatim output

```
main.pr:3:54: use of moved variable 'path'
    look(string p) int { return p.len; }
  > main() { string path = "abcd"; look(path); R r = R(s: path); print_line(r.s); }
                                                          ^
```

## Expected behavior

Per the guide, `look(path)` is a shared borrow and the caller still owns `path`, so
`R r = R(s: path)` should compile and the program should print `abcd`. (Equivalently:
if plain `T` is *intended* to consume, the guide should be corrected and the error
message should say so, rather than the docs promising a borrow.)

## What does / doesn't trigger it

| Variant | Result |
|---|---|
| `look(string p)`, then move arg into a struct | **error: use of moved variable** |
| `look(string p)`, then `.clone()` the arg | **error: use of moved variable** |
| `look(string p)`, then only *borrow* the arg again (string interpolation `{path}`) | compiles (arg seems usable) |
| `look(string &p)` (explicit borrow), then move / clone the arg | compiles |
| no intervening call, single move of the arg | compiles |

The "later borrow still works but later move doesn't" row is the most confusing part:
after `look(path)`, `{path}` interpolation compiles, yet `path.clone()` and moving
`path` are both rejected as "moved". That inconsistency is what makes the true ownership
state of the argument hard to reason about from the error alone.

## Best guess at cause

Either (a) parameter-mode inference treats a plain move-type parameter as a consume
(`~T`) rather than a shared borrow, contradicting the guide; or (b) it really is a
borrow but the move-checker fails to release the borrow at the call's end, leaving the
argument in a half-moved state that still permits reads but not moves/clones. The
explicit `string &p` form takes a different, correct path in either case.

## Workaround used

Be explicit about borrowing, and structure code so an owned value is moved at most once:

- Use `string &p` when a function only needs to read a string it shouldn't consume —
  e.g. the display loop in `main.pr` borrows the path: `string &path = paths[i];`.
- Where a value *is* consumed downstream (e.g. `count_lines(path)` opening the file),
  treat plain `string p` as a consume and simply don't touch the value afterward.

This is mostly an ergonomics + documentation issue rather than a crash, but it
repeatedly produced "use of moved variable" errors on code that the guide says is valid,
and forced a redesign of the result struct (it no longer stores the path).
