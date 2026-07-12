Please file this upstream at https://github.com/promise-language/promise/issues

# A bare failable call in a `match` **expression arm** loses its error — silently in void position, codegen panic in value position

- **`promise version`:** `promise version 2026.3 (channel stable, commit fe13dcd)`
- **Platform:** macOS 26.5.1 (arm64), Darwin 25.5.0

Two manifestations of what looks like one defect: a `match` arm written as a bare
expression (`=> call(),`) does not get the failable auto-propagation transform.
The same call in a **block** arm (`=> { call(); },`) is handled correctly.

## Manifestation A — silent swallow (void position)

The error is computed and then discarded. No message, no non-zero exit, no warning.
This is the dangerous one: the program silently behaves as if the call succeeded.

`swallow.pr`:

```promise
boom!() { raise error(message: "bang"); }

// bare failable call as a match *expression* arm
dispatch!(string c) {
  match c {
    "a" => boom(),
    _ => {},
  }
}

main() {
  dispatch("a") ? e { print_line("caught: {e.message}"); return; };
  print_line("*** SWALLOWED: dispatch returned normally, error vanished ***");
}
```

```sh
$ promise run swallow.pr
*** SWALLOWED: dispatch returned normally, error vanished ***
```

**Expected:** `caught: bang` — a bare call in a failable function auto-propagates,
per the guide ("In a failable (`!`) function, just call failable functions bare —
errors auto-propagate").

## Manifestation B — codegen panic (value position)

When the arm's value is actually consumed, the raw error-union leaks into the result
slot and LLVM IR construction panics.

`panic.pr`:

```promise
boom_val!() int { raise error(message: "bang"); }

f!(string c) int {
  return match c { "a" => boom_val(), _ => 0, };
}

main() { print_line("{f("b")?!}"); }
```

```sh
$ promise build panic.pr
panic: insertvalue elem type mismatch, expected i64, got { i1, i64, i8* }

goroutine 1 [running]:
github.com/llir/llvm/ir.NewInsertValue(...)
	/Users/runner/go/pkg/mod/github.com/llir/llvm@v0.3.6/ir/inst_aggregate.go:103 +0x1a4
github.com/promise-language/promise/compiler/internal/codegen.(*Compiler).wrapOk(...)
	/Users/runner/work/promise/promise/compiler/internal/codegen/compiler.go:6236 +0x338
github.com/promise-language/promise/compiler/internal/codegen.(*Compiler).genReturnStmt(...)
	/Users/runner/work/promise/promise/compiler/internal/codegen/stmt.go:9515 +0xca0
...
```

Assigning instead of returning panics the same way with a different message:

```promise
f!(string c) int { int v = match c { "a" => boom_val(), _ => 0, }; return v; }
// panic: store operands are not compatible: src={ i1, i64, i8* }, dst=i64*
```

**Expected:** compiles; the error propagates out of `f`.

## What triggers it

`boom!()` is void-failable, `boom_val!() int` is value-failable. All inside a failable (`!`) function.

| # | Arm form | Result |
|---|---|---|
| 1 | `match c { "a" => boom(), … }` — expr arm, bare call | **silently swallowed** |
| 2 | `match c { "a" => boom()?^, … }` — expr arm, explicit `?^` | propagates ✅ |
| 3 | `match c { "a" => { boom(); }, … }` — **block** arm, bare call | propagates ✅ |
| 4 | `match c { "a" => { boom()?^; }, … }` — block arm, `?^` | propagates ✅ |
| 5 | `match c { "a" => { raise error(…); }, … }` — `raise` in block arm | propagates ✅ |
| 6 | `return match c { "a" => boom_val(), … }` — value expr arm | **codegen panic** |
| 7 | `int v = match c { "a" => boom_val(), … }` — value expr arm | **codegen panic** |
| 8 | `return match c { "a" => boom_val()?^, … }` — value arm, `?^` | compiles ✅ |
| 9 | `return match c { "a" => 1, … }` — no failable call (control) | compiles ✅ |
| 10 | `if c == "a" { boom(); }` — same call, no `match` (control) | propagates ✅ |
| 11 | `int v = boom_val();` — same call, no `match` (control) | compiles ✅ |

So the trigger is precisely: **a bare failable call in a `match` arm's _expression_ position**.
Adding `?^`, or wrapping the arm in a `{ block }`, avoids it in every case. `if`/`else` is unaffected.

## Best guess at the cause

Match arms in expression position appear to be compiled without the failable
calling-convention unwrap that ordinary call sites get. The callee returns the
error-union `{ i1, i64, i8* }` (ok-flag, value, error-ptr):

- In **void/statement** position the union is produced and dropped on the floor — no
  branch on the ok-flag is emitted, so the error is lost (manifestation A).
- In **value** position the union is fed straight into the arm's result slot, which is
  typed as the arm's *value* type (`i64`), so `wrapOk` / the store hits a type mismatch
  and panics (manifestation B).

Block arms go through the normal statement path, which does emit the propagation
branch — hence the discrepancy. One fix (route match-arm expressions through the same
failable-propagation transform as other expression contexts) should address both.

## Workaround used in the real code

Every arm of the CLI dispatch `match` in `main.pr` is a `{ block }`, never a bare
`=> call()`:

```promise
match cmd {
  "init" => { cmd_init(); },
  "add" => { cmd_add(arg(argv, 1, "file")); },
  "status" => { cmd_status(); },
  …
}
```

This bit hard: the first version used bare expression arms, and **every** failure case
(missing file, unstaged file, empty staging area, unknown commit, no repository) printed
nothing and exited 0 — the errors were raised correctly and then vanished on the way out
of the `match`.
