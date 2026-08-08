Please file this upstream at https://github.com/promise-language/promise/issues

# A bare call to a tuple-returning failable function destructures into (value, error) instead of propagating — unlike `?^`, which the guide calls equivalent

`promise version 2026.6 (channel stable)` · macOS 26.5.1 (arm64, Apple Silicon)

`promise guide` documents `foo()?^` as "Explicit propagate (same as bare call)".
For a failable function that returns a tuple the two forms are *not* the same:
the bare call is swallowed by the "capture raw failable result as `(value, error)`"
rule, so a two-element destructuring binds `(the whole tuple, error)` instead of
the tuple's two elements.

## Minimal repro

`tuple_failable_destructure.pr`:

```promise
split_at!(string line) (string, string) {
  if at := line.index_of(" ") {
    return (line[0:at], line[at + 1:]);
  }
  raise error(message: "no space in '{line}'");
}

main!() {
  (head, tail) := split_at("key value");   // bare call inside a failable function
  print_line("{head} / {tail}");
}
```

```sh
promise build tuple_failable_destructure.pr
```

Verbatim output (exit 1):

```
tuple_failable_destructure.pr:10:26: type error cannot be used in string interpolation (does not implement Format)
        (head, tail) := split_at("key value");
  >     print_line("{head} / {tail}");
                              ^
```

The diagnostic gives the binding away: `tail` is an `error`, and `head` is the
whole `(string, string)`.

## Expected behavior

Inside a failable function, a bare call is documented to auto-propagate, so
`(head, tail) := split_at("key value");` should bind `head = "key"` and
`tail = "value"` and propagate the raise — identical to the `?^` form. If the
`(value, error)` capture form is meant to win here, the two-element form should
be rejected with a diagnostic that says so, not silently typed as
`((string, string), error)`.

## What triggers it

| Source (each built as a standalone file) | Result |
|---|---|
| `(head, tail) := split_at(...)` — bare call, failable, tuple return | **fails**: `head` is the tuple, `tail` is `error` |
| `(head, tail) := split_at(...)?^` — explicit propagate | compiles, prints `key / value` |
| `(head, tail) := split_at(...)?!` — panic form | compiles, prints `key / value` |
| `(string, string) pair = split_at(...); (head, tail) := pair;` | compiles, prints `key / value` |
| identical function *without* `!`, bare call | compiles, prints `key value / key value` |

So only the combination "failable + tuple return + bare call + two-element
destructuring" misbehaves, and `?^` — documented as the same thing — is fine.

## Best guess at the cause

`(a, b) := expr` on a failable call is resolved as the raw-result capture form
before the callee's own return type is consulted, so an arity-2 destructuring is
always read as `(value, error)`. `?^` marks the call as propagating first, which
takes it off that path and lets the real `(string, string)` shape through.

## Workaround used in the real code

An explicit `?^` at every call site of the one tuple-returning failable helper
(`text.pr` / `store.pr` / `commit.pr`):

```promise
(blob, name) := split_first(line, " ")?^;
```
