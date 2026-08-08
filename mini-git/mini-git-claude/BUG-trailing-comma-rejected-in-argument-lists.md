Please file this upstream at https://github.com/promise-language/promise/issues

# Trailing commas are accepted in collection literals, match arms and enum bodies, but rejected in call, constructor, parameter and tuple lists

`promise version 2026.6 (channel stable)` · macOS 26.5.1 (arm64, Apple Silicon)

## Minimal repro

`call_trailing_comma.pr`:

```promise
greet(string name, string mark) string => "hello, {name}{mark}";

main() {
  print_line(greet(
    name: "world",
    mark: "!",
  ));
}
```

```sh
promise build call_trailing_comma.pr
```

Verbatim output (exit 1):

```
call_trailing_comma.pr:7:4: no viable alternative at input ')'
            mark: "!",
  >     ));
        ^
```

Deleting the one comma after `"!"` compiles.

## Expected behavior

A trailing comma should be allowed in every comma-separated list, the way it
already is in vector literals, map literals, `match` arms and enum variant lists.
It is what makes a multi-line argument list diff-friendly — adding an argument
should not touch the previous line.

## What triggers it

Each row was built as a standalone file with `promise build <file>.pr`.

| Source | Result |
|---|---|
| `[1, 2, 3,]` — vector literal | compiles |
| `{"a": 1, "b": 2,}` — map literal | compiles |
| `match n { 1 => ..., _ => ..., }` — match arms | compiles |
| `enum E { A, B, }` — variant list | compiles |
| `greet(name: "world", mark: "!",)` — call, named args | **`no viable alternative at input ')'`** |
| `f(move s,)` — call, positional arg | **`no viable alternative at input ')'`** |
| `Point(x: 1, y: 2,)` — constructor | **`no viable alternative at input ')'`** |
| `s.split("-",)` — method call | **`no viable alternative at input 'string'`** |
| `greet(string name, string mark,)` — parameter list | **`extraneous input ')' expecting {'...', '(', '~', IDENT}`** |
| `(int, int) pair = (1, 2,);` — tuple literal | **`no viable alternative at input 'pair'`** |

## Best guess at the cause

The grammar's list rules are inconsistent: the literal/arm/variant rules end in
something like `(',' elem)* ','?` while `argumentList`, `parameterList` and the
tuple-literal rule lack the optional trailing `','?`. The parse error surfaces at
the `)` (or, for the method-call case, at the *next* statement), which points at
the argument-list rule rather than at anything type-related.

## Workaround used in the real code

Every multi-line call keeps its last argument comma-free, e.g. in `commit.pr`:

```promise
return Self(
  id: hash_text(body),
  parent: clone_optional(parent),
  timestamp: timestamp.clone(),
  message: message.clone(),
  files: move files
);
```
