Please file this upstream at https://github.com/promise-language/promise/issues

# `use x := failable()` with implicit error auto-propagation crashes codegen

**promise version:** 2026.0 (commit 6adc8907003f3939c5fd8eaf88445893c37b23de)
**Platform:** macOS 26.5.1 (arm64)

## Summary

Binding a `use` resource to the result of a failable call that relies on **implicit**
error auto-propagation (a bare call inside a `!` function) panics the compiler during
codegen. Adding the explicit propagate operator `?^` to the initializer compiles fine,
as does a plain (non-`use`) binding of the same call. So the unwrap that codegen needs
is inserted for `?^` and for plain bindings, but not for a `use` binding's bare
initializer.

## Minimal repro

`main.pr` (no `io` needed — a user-defined failable factory reproduces it):

```promise
type Res {
  int id;
  make!(int id) Res `factory { return Res(id: id); }
  close!(~this) {}
}
build!() int {
  use r := Res.make(7);   // bare failable call as a `use` initializer
  return r.id;
}
main!() { print_line("{build()}"); }
```

Build command:

```sh
promise build
```

## Verbatim output

```
panic: store operands are not compatible: src={ i1, { i8*, i8* }, i8* }; dst={ i8*, i8* }*

goroutine 1 [running]:
github.com/llir/llvm/ir.NewStore(...)
	.../llir/llvm@v0.3.6/ir/inst_memory.go:224 +0x154
github.com/promise-language/promise/compiler/internal/codegen.(*Compiler).genUseVarDecl(...)
	.../compiler/internal/codegen/stmt.go:1933 +0x23c
```

The `src` aggregate `{ i1, { i8*, i8* }, i8* }` is the failable-result tuple (error flag
+ payload); `dst` `{ i8*, i8* }*` is the unwrapped `Res` slot. Codegen tries to store the
raw failable result into the unwrapped destination without unwrapping it first.

## Expected behavior

Compile and print `7`, identical to the `?^` and plain-binding variants below — a `use`
binding should auto-propagate (and unwrap) exactly like a normal binding in a `!` function.

## What does / doesn't trigger it

| Variant | Result |
|---|---|
| `use r := Res.make(7);` (implicit auto-propagate) | **codegen panic** |
| `use r := Res.make(7)?^;` (explicit propagate) | compiles, prints 7 |
| `Res r = Res.make(7);` (plain binding, implicit auto-propagate) | compiles, prints 7 |
| `use r := Res(id: 7);` (non-failable `use` initializer) | compiles, prints 7 |

So the trigger is precisely **`use` binding + failable initializer + implicit
auto-propagation** (bare call, no `?^`).

## Best guess at cause

`genUseVarDecl` (compiler/internal/codegen/stmt.go:1933) emits the store of the
initializer into the `use` variable's slot without first running the
auto-propagation/unwrap lowering that the normal var-decl and the explicit `?^` paths
apply. It stores the failable-result aggregate directly into the unwrapped destination
type, which `llir` rejects.

## Workaround used

Add an explicit `?^` to the `use` initializer. In `main.pr`'s `count_lines`:

```promise
use f := io.File.open(path, readonly: true)?^;
```

The `?^` is harmless documentation in a `!` function anyway (it is the explicit form of
the auto-propagation), so the workaround costs nothing at the use site.
