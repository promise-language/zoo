# mini-git — build summary

## What I built

A self-contained "mini-git" in a single Promise file (`main.pr`), scaffolded with
`promise init` and compiled to one binary with `promise build`. It implements all
ten subcommands — `init`, `add`, `rm`, `status`, `commit -m`, `log`, `show`,
`diff`, `checkout`, `reset` — operating on the current directory and persisting
everything under a hidden `.minigit/` directory:

```
.minigit/objects/<hash>   raw file bytes, content-addressed (a blob)
.minigit/commits/<id>     a commit, addressed by the hash of its own text
.minigit/index            the staging area (one "<hash> <name>" line per file)
.minigit/HEAD             the current commit id (absent until the first commit)
```

Content addressing is a hand-rolled 64-bit **FNV-1a**, rendered as a zero-padded
16-char hex string — stable and deterministic, so blob and commit ids reproduce
across runs (I verified the same bytes hash identically after wiping and
re-adding). Commits are hashed over a canonical, sorted text serialization, so a
commit's id is a hash of its own contents. Output is deterministic: filenames are
sorted everywhere, and each failure case (missing file, empty staging area,
already-initialized repo, unknown commit, unstaging something not staged, no
repository) prints a clear `minigit: …` message and exits non-zero.

One design point worth flagging, because it's faithful to the spec but differs
from real git: a commit holds **exactly the staged files** and committing clears
the staging area. There is no carried-forward tree — so if you stage only
`poem.txt` for the second commit, `data.csv` from the first commit is *not* in the
second, and `diff` correctly reports it as removed. The task defines `commit` as
"record a commit holding the staged files … clear the staging area," so this is
the intended minimal model, not an oversight.

## Did it compile and run on the first try?

**It did not compile on the first try** — the language isn't in my training data,
so I learned it from `promise guide` / `promise doc` and hit a handful of things I
had to correct (see below). But once it type-checked, it **ran correctly on the
first execution**: every subcommand worked, binary (non-UTF-8) files round-tripped
byte-for-byte through blob storage and `checkout` (I tested all 256 byte values),
multi-line commit messages survived serialize→parse, and hashes were stable across
runs. No runtime or logic bugs surfaced after the compile stage.

## Program output (representative session)

```
$ minigit init
initialized empty minigit repository in .minigit/
$ minigit add poem.txt ; minigit add data.csv
staged poem.txt (830781d8d58d7c18)
staged data.csv (22d48dce7926f8d9)
$ minigit commit -m "initial import"
committed 298a8050ff826a6f
$ minigit log
commit a80cae58ed84a5f8
date:    2026-07-15T12:12:22+00:00

    extend the poem

commit 298a8050ff826a6f
date:    2026-07-15T12:12:22+00:00

    initial import
$ minigit diff 298a8050ff826a6f a80cae58ed84a5f8
- data.csv
~ poem.txt
$ minigit checkout 298a8050ff826a6f
checked out 298a8050ff826a6f (2 files restored)
```

Error cases (all exit 1): `minigit: not a minigit repository (run 'minigit init'
first)`, `minigit: cannot add 'nope.txt': no such file`, `minigit: nothing staged
to commit`, `minigit: unknown commit 'deadbeef…'`, `minigit: cannot unstage
'b.txt': not staged`.

## What surprised me / had to work out about Promise

Things that aren't obvious and cost me a compile cycle or two:

- **No C-style ternary.** `cond ? a : b` doesn't exist — `?:` is the *elvis*
  operator for optionals. I rewrote conditional values as `if/else`.
- **No top-level variables.** Module scope holds only functions and types;
  `string REPO_DIR = ".minigit";` at the top level is a parse error. I made the
  constants nullary expression-bodied functions (`repo_dir() string => ".minigit";`).
- **`as` casts bind very loosely.** `c as int - '0' as int` misparses (the `-`
  gets a `char` operand); it needs `(c as int) - ('0' as int)`. Also `char as int`
  yields a **non-optional** `int` code point — handy, but I'd expected an optional.
- **Strings are move types, and storing one consumes it.** Inserting into a map
  (`idx[file] = hash`) or constructing a struct *moves* the string, and the borrow
  checker then flags any later use (e.g. printing a confirmation). The fix is an
  explicit `.clone()` at the point of storage — the compiler catches every
  use-after-move at compile time, which is genuinely nice once you expect it.
- **`sort` consumes its argument and needs an explicit type arg** for
  `map.keys()` (`sort[string](m.keys())`), and `move` applies only to *named*
  bindings — you can't `move` a temporary like `m.keys()`.
- **No string→int in std.** `int.parse` takes a `Reader`, not a string, so I
  hand-rolled a small `to_int` for the stored timestamp.
- **`time` is labelled "placeholder — pending native PAL support," but
  `DateTime.now()` works fine** on macOS and gave me real Unix seconds + RFC-3339
  formatting.
- Reading raw bytes is a `File.read` loop into a `u8[]`; `string.bytes()` and
  `string.from_bytes()` convert both ways.

## Two rough edges filed for upstream

Both are written up in their own files in this directory — please submit them:

1. **`BUG-raise-return-not-allowed-as-bare-match-arm.md`** — a bare `raise …` or
   `return …` as a match-arm body fails to *parse*, with a misleading `no viable
   alternative` cascade that blames the `match`/function line, not the offending
   token. The same `raise` wrapped in a block `{ … }` compiles, which is the
   workaround I used in the command dispatcher. Minimized to the smallest trigger
   with compiling controls, verified on 2026.4.
2. **`FEATURE-no-stderr-writer.md`** — Promise exposes the standard streams for
   *input* only. `print`/`print_line` are hardwired to stdout and there's no
   `eprint`, no `io.stderr`, and no way to wrap fd 2 in a `Writer`. A CLI can't put
   diagnostics on stderr, so `2>/dev/null` can't silence them and errors can
   interleave into piped data. Not a hard blocker (I send diagnostics to stdout +
   a non-zero exit), but it makes the tool less composable. This gap was already
   present in 2026.3 and is unchanged in 2026.4.
