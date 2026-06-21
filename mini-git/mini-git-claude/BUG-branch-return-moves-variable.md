Please file this upstream at https://github.com/promise-language/promise/issues

# Move inside a branch that `return`s poisons the variable on the fall-through path

## Version / platform
- `promise version 2026.1 (commit 134062029f2156f915b98b41fb991d44eb23b0ae)`
- macOS 26.5.1 (arm64), Darwin 25.5.0

## Summary
Move analysis is not branch-sensitive for early returns. If a move-type variable
(e.g. `string`, `map[..]`) is moved inside an `if` branch whose body `return`s,
the compiler then reports the variable as "moved" on the path *after* the `if` —
even though that path is only reached when the branch did **not** execute (so no
move actually happened on it).

This rejects the very common "early-out, then keep using the value" shape.

## Minimal repro
`bug.pr`:
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
promise build bug.pr
```

## Verbatim output
```
bug.pr:4:9: use of moved variable 's'
      if cond { return s; }
  >   return s;
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
The flow analysis joins the post-`if` state by treating a move that occurs on a
*diverging* (returning/never-returning) branch as if it reached the merge point.
A branch that ends in `return` (or otherwise can't fall through) should contribute
nothing to the moved-set at the merge, but here it does, marking the variable
moved for the continuation.

## Workaround used in mini-git
Avoid `return <localvar>` inside an early branch when the same local is used
afterward. In `load_index()` the empty-repo early return was replaced with a
guarded body and a single trailing `return idx;`:

```promise
map[string, string] idx = {:};
string p = index_path();
if path_exists(p) {
    string content = read_text(p);
    for line in content.split("\n") { /* ... fill idx ... */ }
}
return idx;            // single return; no branch moves idx
```
