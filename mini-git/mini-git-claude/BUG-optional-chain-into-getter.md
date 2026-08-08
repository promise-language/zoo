Please file this upstream at https://github.com/promise-language/promise/issues

# Optional chaining into a getter crashes: compiler ICE for built-in getters, segfault for user getters

`promise version 2026.6 (channel stable)` · macOS 26.5.1 (arm64, Apple Silicon)

## Minimal repro

`chain_string_len.pr` — optional chain into a built-in getter (`string.len`):

```promise
main() {
  string? name = "promise";
  int? size = name?.len;
  print_line("{size}");
}
```

```sh
promise build chain_string_len.pr
```

Verbatim output (exit 2):

```
panic: codegen: undeclared getter string.len

goroutine 1 [running]:
github.com/promise-language/promise/compiler/internal/codegen.(*Compiler).genFieldOnValue(0x14003252a88, {0x105bc7338, 0x14000517dc0}, {0x105bc3ed0, 0x140000bca00}, {0x14002a85d10, 0x3})
	/Users/runner/work/promise/promise/compiler/internal/codegen/expr.go:14568 +0x80c
github.com/promise-language/promise/compiler/internal/codegen.(*Compiler).genOptionalChainExpr(0x14003252a88, 0x14002affc20)
	/Users/runner/work/promise/promise/compiler/internal/codegen/expr.go:14497 +0x228
github.com/promise-language/promise/compiler/internal/codegen.(*Compiler).genExpr(0x14003252a88, {0x105bc6918?, 0x14002affc20})
	/Users/runner/work/promise/promise/compiler/internal/codegen/expr.go:486 +0x8c4
github.com/promise-language/promise/compiler/internal/codegen.(*Compiler).genTypedVarDecl(0x14003252a88, 0x14002ac2900)
	/Users/runner/work/promise/promise/compiler/internal/codegen/stmt.go:1562 +0xf04
...
main.main()
	/Users/runner/work/promise/promise/compiler/cmd/promise/main.go:291 +0x800
```

`chain_user_getter.pr` — optional chain into a *user-declared* getter. This one
compiles cleanly and then dies at runtime:

```promise
type Box `public {
  string value;
  get size int => this.value.len;
}

main() {
  Box? box = Box(value: "abc");
  int? size = box?.size;
  print_line("{size}");
}
```

```sh
promise build chain_user_getter.pr   # Compiled chain_user_getter.pr → chain_user_getter
./chain_user_getter
```

```
fatal: segmentation fault at 0x0000000000000008
```

## Expected behavior

`opt?.getter` should evaluate the getter when `opt` is present and short-circuit
to `none` when it is absent — i.e. `name?.len` should print `7` and `box?.size`
should print `3`, exactly like the `if`-binding form does. At minimum it must
never be an ICE or a segfault; a "not supported" diagnostic would be acceptable.

## What triggers it

Each row was compiled and (where it built) run as a standalone file.

| Source | Result |
|---|---|
| `box?.value` — plain struct field, present | works, prints `abc` |
| `box?.size` — user getter, `box = none` | works, prints `none` (chain short-circuits before the getter) |
| `box?.size` — user getter, present | compiles, **segfaults at runtime** |
| `name?.len` — built-in `string` getter | **compiler panic:** `undeclared getter string.len` |
| `xs?.len` — built-in `Vector[int]` getter | **compiler panic:** `undeclared getter Vector[int].len` |
| `name?.is_empty` — built-in `string` getter | works, prints `false` |
| `name?.to_upper()` — method call through `?.` | clean compile error: `cannot call non-function type () -> string?` |
| `if present := name { present.len }` | works, prints `7` |

So: only the *present* path of a getter access is broken, `is_empty` happens to
survive while `len` does not, and method calls through `?.` are rejected up front
rather than crashing.

## Best guess at the cause

`genOptionalChainExpr` (expr.go:14497) routes the member access through
`genFieldOnValue`, which looks the name up in the *declared field/getter* table
of the unwrapped type. Built-in getters like `string.len` and `Vector.len` are
not in that table — they are synthesized elsewhere — so the lookup fails and the
compiler panics. For a user-declared getter the name *is* found, but it appears
to be emitted as a struct field load instead of a getter call, so the `int` at
offset 8 is read as a pointer/`this` and the process faults.

## Workaround used in the real code

Unwrap first, then touch the getter — and, because `?.` also cannot call
methods, hand-roll the one optional map that was needed
(`text.pr`, `clone_optional`):

```promise
clone_optional(string? value) string? `public {
  if value is absent {
    return none;
  }
  return value.clone();   // `value?.clone()` does not compile
}
```
