Please file this upstream at https://github.com/promise-language/promise/issues

# `raise` / `return` as a bare match-arm body fails to parse, with a misleading cascade of errors

A match arm whose body is a bare jump statement — `raise …` or `return …` — is
rejected by the parser. Every other arm body works: a call expression, a literal,
or the *same* `raise` wrapped in a block `{ … }`. The diagnostic never mentions
`raise`; it points at the `match` line and the function signature and emits a
cascade of `no viable alternative` / `rule semi failed predicate` messages that
send you looking in the wrong place.

- **`promise version`:** `promise version 2026.4 (channel stable)`
- **Platform:** macOS 26.5.2 (arm64), Darwin 25.5.0 arm64

## Minimal repro

`bug.pr` — a bare `raise` arm:

```promise
pick!(int n) {
  match n {
    0 => print_line("zero"),
    _ => raise error(message: "nonzero"),
  }
}
main() { pick(0) ? e {}; }
```

Command:

```sh
promise build bug.pr     # (promise check bug.pr fails identically)
```

## Verbatim error output

```
bug.pr:4:9: no viable alternative at input 'matchn{0=>print_line("zero"),_=>raise'
        0 => print_line("zero"),
  >     _ => raise error(message: "nonzero"),
             ^
bug.pr:2:10: no viable alternative at input '{'
    pick!(int n) {
  >   match n {
              ^
bug.pr:3:6: rule semi failed predicate: {p.GetTokenStream().LT(1).GetTokenType() == PromiseParserRBRACE}?
      match n {
  >     0 => print_line("zero"),
          ^
bug.pr:4:6: mismatched input '=>' expecting ':='
        0 => print_line("zero"),
  >     _ => raise error(message: "nonzero"),
          ^
bug.pr:6:0: extraneous input '}' expecting {<EOF>, 'type', 'enum', IDENT}
      }
  > }
    ^
```

(Trimmed for length; the real output repeats the `rule semi failed predicate`
line for every arm. `return <expr>` as a bare arm body fails the same way.)

## Expected behavior

Either:

1. Accept `raise`/`return` as a bare match-arm body (they are diverging
   statements — the natural way to write an "impossible / error" arm, and they
   are already legal inside the block form of the very same arm); **or**
2. If bare jump statements are intentionally disallowed as arm bodies, reject
   them with a diagnostic that names the actual problem and points at the
   `raise`/`return` token — e.g. *"`raise` is a statement; wrap it in a block:
   `_ => { raise …; }`"* — rather than an ANTLR-level `no viable alternative`
   cascade anchored to the function signature.

## What does and doesn't trigger it

| Arm body                                   | Result   |
|--------------------------------------------|----------|
| `_ => raise error(message: "x")`           | **fails to parse** |
| `_ => return 0` (in a value-returning fn)  | **fails to parse** |
| `_ => { raise error(message: "x"); }`      | compiles |
| `_ => print_line("x")` (call expression)   | compiles |
| `_ => "x"` (literal expression)            | compiles |

All three "compiles" rows were verified with `promise check`; the two "fails"
rows were verified with `promise build`.

## Best guess at the cause

The grammar production for a match arm is `pattern '=>' expression`, and `raise`
/ `return` are parsed as *statements*, not expressions (unlike Rust, where they
have the never type `!` and are expressions). When the parser hits `raise` after
`=>`, it can't reduce it as an expression, fails the arm, then unwinds all the
way out of the `match` — which is why the top-level error blames the `match`
keyword and the function's opening brace instead of the offending token. The
block form works because a block *is* an expression and its interior is a normal
statement list where `raise` is fine.

## Workaround used in the real code

Wrap the diverging arm in a block. In `main.pr`'s command dispatcher:

```promise
match cmd {
  "init" => cmd_init(),
  // …
  _ => { raise error(message: "unknown command '{cmd}' (try 'minigit help')"); },
}
```

The `{ … }` around the `raise` is load-bearing — dropping it reproduces the
parse failure above.
