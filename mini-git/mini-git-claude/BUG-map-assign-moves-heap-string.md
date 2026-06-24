Please file this upstream at https://github.com/promise-language/promise/issues

# `map[key] = heapString` consumes the value without flagging it — later use silently reads an empty string

## Version / platform
- `promise version 2026.1 (channel stable, commit 4bf7e22)`
- macOS 26.5.1 (arm64), Darwin 25.5.0

## Summary
Assigning a **heap-allocated** `string` into a map via subscript (`m[k] = h`)
moves the value into the map but does **not** mark the source variable `h` as
moved. The compiler then accepts a later read of `h`, and at runtime that read
returns an **empty string** (the moved-from zero value) instead of being a
compile error or preserving the value.

The corruption only becomes observable once the map is **passed to another
function** between the insert and the reuse — passing the map (even by a plain
shared borrow) is enough to clobber the moved-from slot. Without an intervening
call the stale slot still happens to hold the right bytes, so it prints
correctly; that fragility is itself the tell that this is a missed move, not a
copy.

Two facts pin it down:
- A **literal** string (`"deadbeef"`, lives in `.rodata`) survives the exact same
  shape — moving a literal is a no-op copy, so there is nothing to lose.
- Cloning into the map (`m[k] = h.clone()`) leaves `h` untouched and reads fine.

So the rule "`m[k] = v` consumes `v`" is being applied at runtime but is missing
from move analysis, which should either reject the later use of `h` or (if map
insert is meant to copy) keep `h` valid.

## Minimal repro
`repro.pr`:
```promise
make_heap(string a, string b) string { return a + b; }   // a non-literal (heap) string
take_map(map[string, string] m) { }                      // merely borrows the map

main() {
  // TRIGGER: insert a heap string, pass the map to a function, then reuse the var
  string h = make_heap("dead", "beef");
  map[string, string] m = {:};
  m["k"] = h;
  take_map(m);
  print_line("trigger : '{h}'   (want deadbeef)");

  // CONTROL: identical, but no function call between the insert and the reuse
  string h2 = make_heap("dead", "beef");
  map[string, string] m2 = {:};
  m2["k"] = h2;
  print_line("control : '{h2}'   (want deadbeef)");
}
```

Build & run:
```sh
promise build repro.pr && ./repro
```

## Verbatim output
```
trigger : ''   (want deadbeef)
control : 'deadbeef'   (want deadbeef)
```
Expected: both lines print `deadbeef` (or the trigger is rejected at compile time
as use-after-move). It is deterministic across runs.

## What does / doesn't trigger it
| Variant | Result |
|---|---|
| heap string, `m[k]=h`, **pass map to a fn**, then read `h` | **`h` reads empty** |
| heap string, `m[k]=h`, no intervening call, then read `h` | prints correctly |
| heap string, `m[k]=h`, intervening call that does **not** take the map | prints correctly |
| **literal** string, same shape with intervening `take_map(m)` | prints correctly |
| `m[k] = h.clone()`, then read `h` | prints correctly |
| reading the **map's** stored value `m[k]` afterward | correct (only the source var is lost) |

(Key kind — literal `"k"` vs a `string` parameter — makes no difference; failable
vs non-failable enclosing function makes no difference.)

## Best guess at cause
Map subscript-assignment lowers to a *move* of the RHS into the map's slot (no
retain/deep-copy for an owned heap `string`), but the move is not recorded in the
move/borrow checker, so the source binding is left pointing at a buffer it no
longer owns. The later borrow of the map appears to perturb/free that buffer
(or the binding is reset to the empty-string representation), surfacing the
already-broken state as an empty read. Literal strings dodge it because their
"move" is a trivial pointer copy into immutable `.rodata`.

## Workaround
Clone on insert when the source variable is still needed afterward:
`idx[file] = h.clone();` — used in `cmd_add` so the success line can still print
the hash held in `h`.
