Please file this upstream at https://github.com/promise-language/promise/issues

# Spawning a failable call with `go f()` panics the compiler (codegen) instead of compiling

- **Promise version:** `promise version 2026.2 (channel stable, commit a68ffb4)`
- **Platform:** macOS 26.5.1 (Darwin 25.5.0), arm64

## What happens

`go <failable-call>` crashes the compiler in codegen with a raw Go panic and stack
trace — no source diagnostic. It happens whether the call is spawned bare or with
an error operator; the two forms panic in different places, which suggests neither
path is implemented:

- `go work()` (bare, `work!()` failable) → `panic: store operands are not compatible: src={ i1, i64, i8* }; dst=i64*`
  (the failable result aggregate `{ ok: i1, value: i64, err: i8* }` is being stored
  into a plain `i64` task-result slot)
- `go work()?!` → `panic: codegen: go expression with non-call expr *ast.ErrorPanicExpr not supported`
  (`?!` binds tighter than `go`, so the compiler sees `go (work()?!)` and has no
  codegen case for a non-call `go` operand)

A compiler should never panic on well-formed input; at worst it should emit a clear
"cannot spawn a failable function with `go`" diagnostic.

## Minimal repro

`main.pr` (a `promise init` project, this as the only source file):

```promise
work!() int { return 1; }                 // failable function
main!() {
    t := go work();                       // spawn a failable call
    int n = <-t;
    print_line("{n}");
}
```

Build:

```
promise build
```

Verbatim output (first lines):

```
panic: store operands are not compatible: src={ i1, i64, i8* }; dst=i64*

goroutine 1 [running]:
github.com/llir/llvm/ir.NewStore(...)
...
```

The `?!` variant (`t := go work()?!;`) instead prints:

```
panic: codegen: go expression with non-call expr *ast.ErrorPanicExpr not supported

goroutine 1 [running]:
github.com/promise-language/promise/compiler/internal/codegen.(*Compiler).genGoExpr(...)
...
```

## Expected behavior

Either (a) support spawning failable functions — the awaited `<-t` would yield a
failable result the caller can handle — or (b) reject it at type-check time with a
proper diagnostic. A naked codegen panic with an internal Go stack trace is wrong
either way. (Note `<-t` for a non-failable goroutine currently yields a plain
value, so today there is no surfaced way to get the error out anyway — which is
consistent with this simply being unimplemented.)

## What does / doesn't trigger it

Verified — repros panic, control compiles & runs:

| Variant | Result |
|---|---|
| `go work()` with `work!()` **failable**, return type `int` | **panic** (`store operands are not compatible`) |
| `go work()?!` with `work!()` failable | **panic** (`non-call expr *ast.ErrorPanicExpr`) |
| `go work()` with `work()` **non-failable** (`work() int`) | compiles & runs → prints `7` |

So the trigger is precisely: the spawned function is **failable** (`!`). Making it
non-failable compiles and runs fine.

## Best guess at the cause

The goroutine result slot is typed from the function's *declared return type*
(`int`) while a failable function actually returns the failable aggregate
`{ i1, i64, i8* }` — codegen tries to store the aggregate into the `i64` slot and
asserts. The `?!` form is a second, unrelated gap: `go`'s operand grammar/codegen
only handles a bare call expression, so any wrapping expression (`ErrorPanicExpr`,
and presumably others) hits an unhandled case.

## Workaround used in the real program

Don't spawn failable functions. Make the goroutine's entry point a **non-failable**
function that handles its own errors internally and returns a result struct
encoding success-or-skip — which is also exactly what "skip unreadable files
gracefully" wants:

```promise
count_file(int index, string move path) FileCount {        // NOT failable
    int lines = count_lines(path) ? e {                    // recover here
        // ... record the skip ...
        0;
    };
    // ... return a FileCount that says ok / skipped ...
}
// spawned as: go { ch.send(count_file(i, move path)); };
```
