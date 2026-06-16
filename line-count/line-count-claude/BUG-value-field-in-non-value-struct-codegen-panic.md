Please file this upstream at https://github.com/promise-language/promise/issues

# A `` `value `` field mixed with a non-value field crashes codegen instead of giving a diagnostic

**promise version:** 2026.0 (commit 6adc8907003f3939c5fd8eaf88445893c37b23de)
**Platform:** macOS 26.5.1 (arm64)

## Summary

Marking some — but not all — of a struct's fields with `` `value `` (when the struct
also has a heap field such as a `string`) panics the compiler during layout
computation. Whether this combination is meant to be supported or rejected, the result
should be a clean diagnostic, not an unrecovered Go panic with `not yet supported`.

## Minimal repro

`main.pr`:

```promise
type R {
  int n `value;
  string s;
}
main() { r := R(n: 1, s: "x"); print_line("{r.n} {r.s}"); }
```

Build command:

```sh
promise build
```

## Verbatim output

```
panic: codegen: non-instance field placement not yet supported for R.n

goroutine 1 [running]:
github.com/promise-language/promise/compiler/internal/codegen.computeUserTypeLayout(...)
	.../compiler/internal/codegen/layout.go:345 +0x106c
github.com/promise-language/promise/compiler/internal/codegen.(*Compiler).computeAllTypeLayouts.func1(...)
```

## Expected behavior

Either:
- compile and print `1 x` (treating `` `value `` on individual fields of a heap struct
  as a no-op / inline placement, which is what one would expect for a Copy field), or
- emit a normal compile error explaining that `` `value `` fields require an all-value
  struct.

Anything but an uncaught `panic:` with a Go stack trace.

## What does / doesn't trigger it

| Variant | Result |
|---|---|
| `int n `` `value ``; ` + `string s;` (mixed) | **codegen panic** |
| `bool ok `` `value ``; ` + `string s;` (mixed, different field type) | **codegen panic** |
| `int n;` + `string s;` (no `` `value ``) | compiles, prints `1 x` |
| `int n `` `value ``; int m `` `value ``;` (all value, no heap field) | compiles |

So the trigger is **a `` `value `` field coexisting with a non-value (heap) field** in
the same struct; the value field's type is irrelevant.

## Best guess at cause

`computeUserTypeLayout` (compiler/internal/codegen/layout.go:345) supports `` `value ``
fields only for fully-value (stack-allocated, auto-copy) structs. When the struct is
heap-allocated because it contains a non-value field, it has no code path for placing a
value field inline ("non-instance field placement"), so it panics instead of either
falling back to ordinary inline placement or rejecting the program in the type checker.

## Workaround used

Drop the `` `value `` annotations from the result struct. In `main.pr`, `FileCount` is a
plain heap struct; its `int`/`bool` fields are Copy primitives and are stored inline
without any annotation:

```promise
type FileCount {
  int index;
  int lines;
  bool ok;
  string error;
}
```

The `` `value `` annotations were never necessary here — this only surfaced because I
reflexively tagged the small scalar fields.
