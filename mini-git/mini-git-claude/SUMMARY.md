# mini-git — build summary

## What I built
A self-contained "mini-git" in a single Promise source file (`main.pr`), scaffolded
with `promise init` and compiled to one binary with `promise build`. It implements
all ten subcommands: `init`, `add`, `rm`, `status`, `commit -m`, `log`, `show`,
`diff`, `checkout`, and `reset`.

All state lives on disk under `.minigit/`:
- `objects/<hash>` — raw file bytes, content-addressed with FNV-1a (64-bit, 16 hex
  digits). Reads and writes go through a byte-level path, so blobs are binary-safe
  (verified: a 5 KB `/dev/urandom` file round-trips byte-for-byte through
  `add` → `commit` → `checkout`).
- `commits/<id>` — each commit as canonical text (parent, time, message, and the
  sorted `file <hash> <name>` list). A commit's id is the FNV-1a hash of that exact
  text, so ids are reproducible from content.
- `HEAD` — the current commit id; `index` — the staging area.

Output is deterministic: filenames and commit file lists are always sorted, and
the failure cases in the spec (missing file, empty staging area, already-initialized
repo, unknown commit id, unstaging something not staged, no repo) each print a clear
`mini-git: …` message and exit with code 1.

## Did it compile and run on the first try?
The *logic* was right the first time — once it compiled, every command behaved
correctly on the first run, and no behavioral bug surfaced in testing. But it did
**not** compile on the first try: I hit several language realities that contradict
the bundled `promise guide`, plus two genuine compiler bugs (below). Fixing those
was iterative. After they were resolved, the end-to-end workflow worked immediately.

## Program output (representative session)
```
$ mini-git init
Initialized empty mini-git repository in .minigit/
$ mini-git add notes.txt
added notes.txt  (69e70ffc7ee5f13f)
$ mini-git status
Staged files:
  notes.txt
$ mini-git commit -m "initial notes"
committed eac5476786837522
$ mini-git commit -m "add a third line"      # after editing + re-adding notes.txt
committed f82b04f0fbd068f4
$ mini-git log
commit f82b04f0fbd068f4
date   1781799564
    add a third line

commit eac5476786837522
date   1781799564
    initial notes

$ mini-git diff eac5476786837522 f82b04f0fbd068f4
modified  notes.txt
```
`show`, `checkout`, and `reset` were exercised the same way: `checkout` restores
recorded files to disk and moves HEAD; `reset` moves HEAD only and leaves the
working tree untouched (both verified by inspecting file contents afterward).

## Two compiler bugs found (filed separately)
Both are minimized with controls and written up for upstream:

1. **`BUG-bare-failable-call-in-interpolation.md`** — a bare auto-propagating
   failable call inside string interpolation (`"{twice(21)}"`) doesn't return its
   result: it yields the zero value for `int` (`0`) and **stack-overflows** for
   `string`. The same call works in assignment, in a plain argument position, and
   with explicit `?^`/`?!`. The guide advertises this construct, so it's a real
   codegen bug.

2. **`BUG-branch-return-moves-variable.md`** — move analysis isn't branch-sensitive
   for early returns: `if cond { return s; } return s;` is rejected with "use of
   moved variable 's'", even though the move only happens on the returning path.
   Affects any move type (`string`, `map`, …).

## One missing capability (filed separately)
**`FEATURE-wallclock-time.md`** — Promise has no wall-clock time. `std` only offers
a *monotonic* `Instant`, and the `time` catalog module is documented but
unimplemented (`promise doc time` says so). Commit timestamps therefore shell out
to the system `date` via `os.execute` — in-language, but it needs an external `date`
binary and yields only a raw epoch integer (hence `log` prints `date 1781799564`
rather than a human-readable date). A single `std` wall-clock primitive, or landing
the planned `time` module, would fix this cleanly.

## What surprised me / had to be worked out (Promise is young)
The language is pleasant — failable functions with auto-propagation, exhaustive
`match`, ownership annotations, getters, named-arg constructors. The friction was
mostly that the **bundled `promise guide` disagrees with the compiler** in a few
places. Things I had to discover empirically:

- **Ownership of plain parameters is the opposite of what the guide says.** The
  guide states "plain `T` param is a borrow; add `~T` to consume." In reality a
  plain `string` parameter **moves/consumes the argument at the call site** (the
  caller can't use it again), yet *inside* the callee that same parameter behaves
  like a borrow (you can't move it out — e.g. you can't return it or store it in a
  field). The actual borrow form is `string& s`. I ended up declaring all read-only
  string params as `string&` and using `.clone()` whenever an owned copy was needed
  (notably to feed std calls like `io.File.read_content`, `path.join`, and
  `Builder.write_string`, which all consume their string arguments). This is the
  single biggest ergonomic surprise — it's easy to write a natural-looking function
  and have it silently consume its caller's data. Clearer guide wording (and maybe
  a lint/diagnostic distinguishing "moved at call site" from "can't move out of
  borrow") would help a lot.

- **`error.message` is a getter, not a method.** The guide shows `e.message()`
  in multiple examples, but the compiler rejects it: "`message` is a property on
  error, not a method — remove ()". (The diagnostic is excellent, to be fair.)

- **`scan[int]` works fine on its own** — my initial "scan returns 0" symptom was
  actually the interpolation bug above (`"{scan[int](s)}"`), not a scan problem.
  Assigning to a local first parses correctly. Worth flagging because it's an easy
  trap: the natural way to print a parsed value is exactly the broken form.

- **`u8[]&` (a borrowed vector) can't be `for … in` iterated** — I had to index it
  (`for i in 0..data.len { u8 b = data[i]; }`) in the FNV hasher. Iterating an
  *owned* vector is fine; only the borrowed form is rejected.

- **`promise init` scaffolds an unbuildable project on this toolchain.** `init`
  wrote `epoch = "2026.0"` into `promise.toml`, but the installed compiler is
  `2026.1`, so every `promise build`/`doc` failed with "epoch 2026.0 is not
  installed", and `promise update 2026.0` *also* errors with the same message
  (no way to install it). I fixed it by editing `promise.toml` to `epoch = "2026.1"`.
  A fresh `init` should default to an epoch the local toolchain can actually build.

None of these were hard blockers once understood, and the compiler's diagnostics
are generally clear and point at the right line — but the guide/compiler mismatch
on ownership cost the most time.
