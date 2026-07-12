# mini-git in Promise — summary

## What I built

A self-contained content-addressed VCS in a single file (`main.pr`, ~380 lines), scaffolded
with `promise init` and built to one binary with `promise build`. All ten subcommands work:
`init`, `add`, `rm`, `status`, `commit -m`, `log`, `show`, `diff`, `checkout`, `reset`.

State lives on disk under `.minigit/` — `objects/<hash>` (blobs), `commits/<id>`, `HEAD`,
and `index` (the staging area) — so it works across separate runs. Content addressing is
FNV-1a/64 over raw bytes rendered as 16 hex digits; a commit's id is the hash of its own
serialized body, so ids are reproducible. Files are read and written as raw `u8[]`, so the
store is binary-safe: I round-tripped a file containing NUL bytes and invalid UTF-8
(`\x00\x01\x02\xff\xfe\x80`) plus an empty file and a UTF-8 file, and all three came back
byte-identical through `checkout`. I also re-derived every blob hash and commit id with an
independent Python FNV-1a implementation to confirm the content addressing is right.
Listings are sorted by name, so output is deterministic.

## Did it compile and run on the first try?

**No.** Roughly four rounds of compile errors, then two genuine compiler bugs that only
showed up at runtime.

The compile errors were all my own fault and the diagnostics were good:
- trailing commas in multi-line call arguments are rejected;
- struct construction **consumes** its field values, so a borrowed parameter can't be stored
  in a field — it needs `move` on the parameter or an explicit `.clone()`;
- `sort()` couldn't infer its type argument from `map.keys()` directly (`sort[string](…)`
  or binding to a typed local first both work).

The two runtime bugs were the interesting part, and **both were silent** — the program did
the right work and then either lost the error or corrupted the heap:

1. **`match` arms silently swallow errors** (`BUG-match-arm-drops-failable.md`). My CLI
   dispatch was a `match` with bare expression arms (`"add" => cmd_add(...)`). Every failure
   case — missing file, empty staging area, unknown commit, unstaged file, no repo — printed
   *nothing* and exited *0*. The errors were raised correctly and then vanished on the way
   out of the `match`. A bare failable call in a match **expression** arm doesn't get the
   auto-propagation transform; the same call in a `{ block }` arm works fine. The same defect
   in *value* position crashes the compiler outright (`panic: insertvalue elem type mismatch,
   expected i64, got { i1, i64, i8* }`). Workaround: every dispatch arm is a `{ block }`.

2. **`sort()` on a borrowed vector double-frees** (`BUG-sort-borrowed-vector-double-free.md`).
   `minigit commit` wrote the commit correctly, printed `committed <id> (2 file(s))`, and then
   aborted with `fatal: invalid free (bad header magic)` (exit 134). `sort[T](T[] vec)` takes a
   **shared borrow** but returns a vector aliasing the caller's buffer; moving that into an
   owned struct field gives the buffer two owners. Memory-unsafe with no `unsafe`, no `move`,
   and no diagnostic. Workaround: `Commit.record` takes `Entry[] move files` (which is the
   honest signature anyway — the commit owns its entries).

Both are minimized to a few lines with a full does/doesn't-trigger table, and I verified the
repros fail and the controls compile before writing them down.

## Program output

```
$ minigit init
initialized empty minigit repository in .minigit/
$ minigit add a.txt
added a.txt (a9bc80cca21f28b3)
$ minigit add b.txt
added b.txt (e277e67d7e50251b)
$ minigit status
staged files:
  a9bc80cca21f28b3  a.txt
  e277e67d7e50251b  b.txt
$ minigit commit -m "first commit"
committed 8c04b1ff8122f984 (2 file(s))

$ minigit commit -m "modify a, add c, drop b"
committed 043f2fde63215039 (2 file(s))
$ minigit log
commit 043f2fde63215039
date   2026-07-12T09:31:03+00:00

    modify a, add c, drop b

commit 8c04b1ff8122f984
date   2026-07-12T09:31:02+00:00

    first commit

$ minigit show 8c04b1ff8122f984
commit 8c04b1ff8122f984
date   2026-07-12T09:31:02+00:00

    first commit

files:
  a9bc80cca21f28b3  a.txt
  e277e67d7e50251b  b.txt
$ minigit diff 8c04b1ff8122f984 043f2fde63215039
modified  a.txt  a9bc80cca21f28b3 -> 4d0c68f207458ae2
removed   b.txt  e277e67d7e50251b
added     c.txt  a6dfc978673f387c
$ minigit checkout 8c04b1ff8122f984
checked out 8c04b1ff8122f984 (2 file(s) restored)   # a.txt back to "hello", b.txt restored
$ minigit reset 043f2fde63215039
reset to 043f2fde63215039 (working directory untouched)

# failure cases
$ minigit add nope.txt
minigit: no such file: 'nope.txt'                    [exit 1]
$ minigit rm ghost.txt
minigit: 'ghost.txt' is not staged                   [exit 1]
$ minigit commit -m "empty"
minigit: nothing staged to commit                    [exit 1]
$ minigit show deadbeefdeadbeef
minigit: unknown commit 'deadbeefdeadbeef'           [exit 1]
$ minigit init
minigit: repository already exists at .minigit/      [exit 0]
$ minigit bogus
minigit: unknown command 'bogus' + usage             [exit 2]
```

## What surprised me / had to work out

**Flow-sensitive narrowing is better than I expected.** After

```promise
int? split_at = text.index_of("\n\n");
if split_at is absent { raise error(message: "…"); }
```

`split_at` is narrowed to a plain `int` for the rest of the function, because the `raise`
diverges — writing `split_at!` afterwards is a *compile error* ("unwrap (!) requires an
optional expression"). I initially read that error as a bug and went to minimize it; it's
actually the compiler being smart. Nice. The one wrinkle: narrowing flows into a branch
**body** but not across an `else if` chain to a later arm, so in a 3-way `if before is absent
/ else if after is absent / else` the third arm still saw `after` as optional. That
asymmetry is surprising and cost me a compile cycle.

**Ownership on struct construction is the thing to internalize.** `Type(field: x)` *consumes*
`x`. Combined with "a borrow parameter cannot be moved out", this means the signature of a
constructor-ish function is forced by whether the struct keeps the data: `record(string move
message, …)` rather than `record(string message, …)`. Once that clicked the rest fell out —
and it's exactly the discipline that would have *prevented* the `sort` double-free if `sort`'s
own signature were honest (`T[] move vec`).

**The two silent-failure bugs are the real feedback.** Promise's whole pitch is
static types + ownership, i.e. "the compiler catches this class of thing." Both bugs I hit
were in that contract: one silently discarded errors in the language's *documented* default
idiom (bare call auto-propagates), and one produced a heap double-free through a
memory-safe-looking stdlib call. The `sort` one in particular is a stdlib **signature** bug —
the type says "I borrow this" and the implementation consumes it. Fixing the signature turns a
silent heap corruption into a compile error.

**`promise doc <module>` is excellent** and is what made this tractable without the language
in memory — accurate signatures, getters vs. methods marked, failability marked. Two caveats:
the `time` module's one-line blurb says "placeholder — pending native PAL support" but
`time.DateTime.now()` works fine and is what I used for commit timestamps; and the guide shows
`sort(xs)` inferring its type parameter, which doesn't hold when the argument is `map.keys()`.

**Gap: there is no way to write to stderr** (`FEATURE-no-stderr-writer.md`). `std` gives you
`print`/`print_line` (stdout only); `io` gives you `read_line`/`read_stdin` (stdin only). The
only `stderr` in the stdlib is for reading a *subprocess's* stderr. So a CLI cannot put
diagnostics on stderr — mine go to stdout with a `minigit:` prefix and a correct non-zero exit
code. Even the non-portable `/dev/stderr` escape hatch fails (`permission denied` on macOS).
For a language aimed at CLI tooling this is a conspicuous hole; `eprint_line`, or `io.stdout` /
`io.stderr` as first-class `Writer`s, would fix it (and would also make output testable,
since `print_line` is unmockable today).

## Files to file upstream

- `BUG-match-arm-drops-failable.md` — bare failable call in a `match` expression arm loses its
  error: silently swallowed in void position, compiler panic in value position.
- `BUG-sort-borrowed-vector-double-free.md` — `sort()` takes a borrow but returns an aliasing
  vector; moving the result into a struct field double-frees.
- `FEATURE-no-stderr-writer.md` — no way for a program to write to its own stderr.
