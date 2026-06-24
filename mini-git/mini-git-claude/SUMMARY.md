# mini-git — build summary

## What I built
A self-contained "mini-git" in a single Promise source file (`main.pr`),
scaffolded with `promise init` and compiled to one binary with `promise build`.
It implements all ten subcommands: `init`, `add`, `rm`, `status`, `commit -m`,
`log`, `show`, `diff`, `checkout`, and `reset`.

All state lives on disk under `.minigit/`:
- `objects/<hash>` — raw file bytes, content-addressed with FNV-1a (64-bit, 16
  hex digits). Reads and writes go through a byte-level path (`File.read`/`write`
  over `u8[]`), so blobs are binary-safe — verified by round-tripping a 5 KB
  `/dev/urandom` file through `add` → `commit` → `checkout` byte-for-byte
  (matching SHA-256).
- `commits/<id>` — each commit as canonical text (`parent`, `time`, the sorted
  `file <hash> <name>` list, then a `message` sentinel and the message). A
  commit's id is the FNV-1a of that exact text, so ids are reproducible from
  content.
- `HEAD` — the current commit id; `index` — the staging area.

Output is deterministic: filenames and a commit's files are always sorted, and
every failure case in the spec (missing file, empty staging area, already-init'd
repo, unknown commit id, unstaging something not staged, no repo) prints a clear
`mini-git: …` message and exits with code 1. (Already-initialized is reported but
exits 0, since the spec calls that "exit cleanly.")

## Did it compile and run on the first try?
No — but once it compiled, the logic was correct on the first run, and the only
runtime defect was a cosmetic empty-string print traced to a compiler bug (below).
The compile errors I worked through were all real language rules I had to learn,
since Promise isn't in my training data:
- **Module-level constants are getters.** `string REPO = ".minigit";` at top level
  is a syntax error; the working form is `get REPO string => ".minigit";`.
- **`sort` can't infer its type argument** from a `string[]` — it needs explicit
  `sort[string](xs)`.
- **Bit shifts are type-strict**: `u64 >> int` is rejected ("cannot use int as
  u64"); the shift amount must be `u64` too.
- **`is absent` narrows the optional** on the path after the guard, so a later
  `message!` then fails with "unwrap requires an optional expression" — you just
  use `message` directly.
- **Struct construction consumes its fields**: owned locals need an explicit
  `move` per named arg, and a borrowed parameter needs `.clone()`
  (`Commit(id: id.clone(), parent: move parent, …)`).

## Program output (representative session)
```
$ mini-git init
Initialized empty mini-git repository in .minigit/
$ mini-git add notes.txt
added notes.txt  (2925835410388969)
$ mini-git status
Staged files:
  notes.txt
$ mini-git commit -m "initial notes"
committed 992adfcc4c20b653
$ mini-git commit -m "add a third line"      # after editing + re-adding notes.txt
committed 2a4ebebace290ff0
$ mini-git log
commit 2a4ebebace290ff0
date   1782309453
    add a third line

commit 992adfcc4c20b653
date   1782309453
    initial notes

$ mini-git diff 992adfcc4c20b653 2a4ebebace290ff0
modified notes.txt
$ mini-git show 2a4ebebace290ff0
commit  2a4ebebace290ff0
date    1782309453
message add a third line
files:
  82c9fe9443eab41a notes.txt
```
`checkout` and `reset` were exercised the same way: `checkout` restores a
commit's recorded files to disk and moves HEAD (and clears staging); `reset`
moves HEAD only and leaves a dirtied working tree untouched — both verified by
inspecting file contents afterward.

## What surprised me / Promise feedback
Mostly positive: the failable-error operators (`?`, `?^`, bare auto-propagation
in `!` functions) made the error paths terse and readable; `use f := File.open(…)`
auto-closing is lovely; byte-level file I/O over `u8[]` is clean; and
`time.DateTime.now()` works (a prior run on an earlier 2026.1 build had to file a
missing-wallclock-time gap — that's now resolved, so no FEATURE file this time).

Two genuine compiler bugs slowed me down — both filed separately, please submit:

- **`BUG-map-assign-moves-heap-string.md`** — `map[k] = h` where `h` is a
  heap-allocated string moves the value into the map but doesn't flag `h` as
  moved; once the map is passed to any function, a later read of `h` returns an
  empty string. This is what produced an empty hash in `add`'s success line even
  though the blob and index were written correctly. Worked around with
  `h.clone()` on insert. This one is a soundness hole (silent use-after-move), so
  it's the more concerning of the two.
- **`BUG-branch-return-moves-variable.md`** — moving a value inside an `if` branch
  that `return`s marks it moved on the fall-through path too, rejecting the common
  "early-out, then keep using the value" shape. Hit it in `load_index`; worked
  around by inverting the guard so nothing is moved on a returning branch.

Minor papercut worth a mention: `sort` requiring an explicit type argument for a
concretely-typed `string[]` felt like it should be inferable.
