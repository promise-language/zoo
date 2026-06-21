Please file this upstream at https://github.com/promise-language/promise/issues

# Bare auto-propagating failable call inside string interpolation yields the zero value (and stack-overflows for `string`)

## Version / platform
- `promise version 2026.1 (commit 134062029f2156f915b98b41fb991d44eb23b0ae)`
- macOS 26.5.1 (arm64), Darwin 25.5.0

## Summary
A *bare* call to a failable function (`name!`) used directly inside a string
interpolation `"{ ... }"` does not return the call's result. For an `int`-returning
function it silently evaluates to `0` (the type's zero value); for a
`string`-returning function it crashes at runtime with `fatal: stack overflow`.

The same call works correctly everywhere else: assigned to a local, in a plain
function-argument position, or when written with the explicit `?^` / `?!`
operators. So this is specific to the **bare auto-propagation form inside string
interpolation**.

The language guide actively advertises the broken form — e.g.
`print_line("doubled={twice(n)?^}")` and `print_line("payload={encode(...)}")` —
so this is a real codegen bug, not misuse. (Note the guide example uses `?^`,
which happens to work; the bare form does not.)

## Minimal repro
`bug.pr`:
```promise
twice!(int n) int { return n * 2; }

main!() {
    print_line("bare  = {twice(21)}");    // expect 42 -> prints 0    <-- BUG
    print_line("prop  = {twice(21)?^}");  // expect 42 -> prints 42
    print_line("panic = {twice(21)?!}");  // expect 42 -> prints 42
    int v = twice(21);
    print_line("local = {v}");            // expect 42 -> prints 42
}
```

Build & run:
```sh
promise build bug.pr && ./bug
```

## Verbatim output
```
bare  = 0
prop  = 42
panic = 42
local = 42
```
Expected: every line prints `42`.

### `string`-returning variant (crashes)
`bug_str.pr`:
```promise
greet!(string n) string { return "hi {n}"; }
main!() {
    print_line("bare={greet("x")}");
}
```
```
fatal: stack overflow
```
Expected: `bare=hi x`.

## What does / doesn't trigger it
| Construct | Result |
|---|---|
| `"{twice(21)}"` — bare failable call in interpolation | `0` — **WRONG** |
| `"{greet("x")}"` — bare failable `string` call in interpolation | `fatal: stack overflow` — **WRONG** |
| `"{twice(21)?^}"` — explicit propagate in interpolation | `42` — ok |
| `"{twice(21)?!}"` — panic-on-error in interpolation | `42` — ok |
| `int v = twice(21); "{v}"` — assign to local, then interpolate | `42` — ok |
| `print_line(twice(21))` — bare failable as plain call argument | `42` — ok |
| `add(twice(10), twice(5))` — bare failable as nested arguments | `30` — ok |
| `"{id[int](7)}"` — generic but **non-failable** call in interpolation | `7` — ok |

So the trigger is exactly: *failable* function + *bare* (implicit auto-propagate)
call + *string-interpolation* expression position. Generics are irrelevant
(a non-generic `twice!` triggers it; a generic non-failable `id` does not).

## Best guess at cause
When lowering a string-interpolation expression, the compiler appears to evaluate
the embedded expression without the auto-propagation transform that bare failable
calls get in statement/assignment/argument positions. The interpolation slot ends
up reading the uninitialized/zero result slot (hence `0` for `int`), and for a
heap `string` result the missing unwrap leaves a self-referential/empty value that
sends `to_string` (or the formatter) into unbounded recursion (`stack overflow`).
The explicit `?^`/`?!` forms emit their own unwrap, which is why they work.

## Workaround used in mini-git
Never put a bare failable call inside interpolation. Assign the result to a typed
local first and interpolate the local (used throughout, e.g. in `cmd_log` /
`cmd_show`: `string cid = c.id; print_line("commit {cid}");`). `?^` also works if
an inline form is wanted.
