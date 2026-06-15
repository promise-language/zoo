# Promise "hello, world"

## What I built

A minimal Promise program, `hello.pr`, with a single `main()` entry point that calls
the auto-imported `print_line` to write `hello, world` to stdout:

```promise
main() {
  print_line("hello, world");
}
```

Built and run with `promise run hello.pr`.

## Did it work?

Yes — it compiled and ran on the **first try**. No errors, no fixups.

## Output

```
hello, world
```

## What surprised me / had to work out

Promise isn't in my training data, so I learned it from `promise --help` and
`promise guide`. A few things that stood out:

- **`main()` needs no return type and no `use`.** The standard library (`std`),
  including `print_line`, is auto-imported, so the program is genuinely just three
  lines — no imports, no boilerplate.
- **`promise run`** compiles and runs in one step (vs. `promise build` to produce a
  standalone executable), which is handy for a quick smoke test.
- **Distinctive error-handling model:** functions — not types — are marked failable
  with a `!` suffix (`main!()`), and inside them bare calls auto-propagate errors.
  The trailing operators are easy to mix up: `?^` propagates, `?!` *panics* (not
  propagates), and `? e { ... }` recovers. None of this was needed for hello world,
  but it's the most unfamiliar part of the language.
- **Other notable idioms** (from the guide): Rust-like ownership with `&x`/`~x` but
  **no borrow markers at call sites** (the compiler auto-borrows), getters accessed
  as properties (`vec.len`, not `vec.len()`), named-argument constructors
  (`Point(x: 1.0, y: 2.0)`), and `{expr}` string interpolation with braces.
