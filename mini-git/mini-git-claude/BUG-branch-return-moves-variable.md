Please file this upstream at https://github.com/promise-language/promise/issues

# Move inside a branch that `return`s poisons the variable on the fall-through path

## Version / platform
- `promise version 2026.1 (channel stable, commit 4bf7e22)`
- macOS 26.5.1 (arm64), Darwin 25.5.0

## Summary
Move analysis is not branch-sensitive for early returns. If a move-type variable
(e.g. `string`, `map[..]`) is moved inside an `if` branch whose body `return`s,
the compiler then reports the variable as "moved" on the path *after* the `if` —
even though that path is only reached when the branch did **not** execute (so no
move actually happened on it).

This rejects the very common "early-out, then keep using the value" shape, e.g.
returning an accumulator early on one condition and continuing to build it
otherwise.

(Still reproduces on commit `4bf7e22`; this was hit again building mini-git's
`load_index`, which wanted `if !exists { return idx; } …; return idx;`.)

## Minimal repro
`repro.pr`:
```promise
f(bool cond) string {
    string s = "x";
    if cond { return s; }   // move only happens when we return
    return s;               // compiler: "use of moved variable 's'"
}
main() { print_line(f(false)); }
```

Build:
```sh
promise build repro.pr
```

## Verbatim output
```
repro.pr:4:11: use of moved variable 's'
        if cond { return s; }
  >     return s;
               ^
```
Expected: compiles; `f(false)` returns `"x"`.

## What does / doesn't trigger it
| Variant | Result |
|---|---|
| `if cond { return s; } return s;` | **rejected** ("use of moved s") |
| `if cond { return s.clone(); } return s;` (move a clone in the branch) | compiles |
| `if cond { return s; } else { return s; }` (no fall-through use) | compiles |
| body guarded with no early return: `if cond { ...use s... } return s;` | compiles |
| same shape with a `map[string,string]` instead of `string` | **rejected** (any move type) |

## Best guess at cause
The move checker unions the moved-set across the branch and the fall-through
edge instead of intersecting along control flow. A `return` (or any divergent
terminator) inside the branch should remove that branch's moves from what reaches
the code after the `if`, because the only way to fall through is for the branch
not to have run.

## Workaround
Restructure so the value is never moved on a returning branch — invert the guard
into a single non-returning `if`, use `else`, or clone in the early-return branch.
mini-git's `load_index` uses the inverted-guard form:
`if io.File.exists(INDEX) { … fill idx … } return idx;`.
