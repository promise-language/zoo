# mini-git in Promise — summary

## What I built

`minigit`, a self-contained content-addressed version control tool: ~650 lines of
Promise across seven files, scaffolded with `promise init`, built into a single
binary with `promise build`, and driven entirely from the command line.

| file | what lives there |
|---|---|
| `main.pr` | argv dispatch; maps failures onto exit codes (1 = operation failed, 2 = misuse) |
| `commands.pr` | one function per subcommand, plus the argument checks |
| `store.pr` | the `.minigit/` directory: blobs, commits, index, HEAD, raw byte I/O |
| `commit.pr` | the `Commit` record and its canonical text format |
| `hash.pr` | FNV-1a (64-bit) content addressing |
| `text.pr` | shared line-format helpers (split, sort, escape) |
| `errors.pr` | `MiniGitError is error`, carrying the exit status |

State on disk is four things: `objects/<hash>` (raw bytes of every added file),
`commits/<id>` (one commit per file), `index` (the staging area) and `HEAD`. A
commit's id is the FNV-1a hash of its own serialized text — I verified that
independently by recomputing FNV-1a over `.minigit/commits/<id>` in Python and
getting the id back. Output is deterministic: every filename listing goes through
one `sorted_names` helper, and the blob lines inside a commit are sorted too, so
the id depends on the file *set* and not on staging order.

A commit records exactly what was staged (the task's wording), so it is a
snapshot of the staging area rather than a merge with its parent — `checkout`
then restores precisely that file set. Blobs are read and written as `u8[]`, not
strings, so binary files survive: a 5 KB random file round-tripped through
`add` → `commit` → `rm` → `checkout` with an identical MD5. Empty files,
filenames containing spaces, and nested paths (`nested/deep.txt`, whose parent
directory is recreated on checkout) all work.

## Did it compile and run the first try?

Not the first try — but every failure was a compile error, none was a wrong
answer at runtime. The first `promise build` produced three parse errors (trailing
commas in multi-line calls, and `return move x;`, which is not a thing), then a
round of semantic errors: duplicate `use` across files, a moved-out `blob`
variable, `move` needed on two constructor arguments, and optional chaining into
a method call. All were pinpointed with exact line/column and a suggested fix —
the ownership diagnostics in particular tell you what to do ("cannot move
borrowed parameter 'root'; declare the parameter with `move` to consume it").
Once it compiled, every subcommand behaved correctly on the first run; the only
post-compile change was cosmetic (`path.normalize`, so messages say `.minigit`
instead of `./.minigit`).

## Program output

```
$ minigit init
initialized empty minigit repository in .minigit
$ minigit add a.txt
staged a.txt a9bc80cca21f28b3
$ minigit add b.txt
staged b.txt e277e67d7e50251b
$ minigit status
a.txt
b.txt
$ minigit commit -m "first commit"
committed f77f436f81ed2cb1 (2 file(s))
$ minigit rm b.txt
unstaged b.txt
$ minigit status
a.txt
c.txt
$ minigit commit -m "edit a, add c"
committed 3456f044031f51ef (2 file(s))
$ minigit log
commit  3456f044031f51ef
date    2026-08-08T12:31:31Z
message edit a, add c

commit  f77f436f81ed2cb1
date    2026-08-08T12:31:31Z
message first commit
$ minigit show f77f436f81ed2cb1
commit  f77f436f81ed2cb1
parent  -
date    2026-08-08T12:31:31Z
message first commit
files
  a9bc80cca21f28b3  a.txt
  e277e67d7e50251b  b.txt
$ minigit diff f77f436f81ed2cb1 3456f044031f51ef
added    c.txt
removed  b.txt
modified a.txt
$ minigit checkout f77f436f81ed2cb1
restored a.txt
restored b.txt
checked out f77f436f81ed2cb1
$ cat a.txt
hello
$ minigit reset 3456f044031f51ef
reset to 3456f044031f51ef; working directory untouched
$ cat a.txt   # reset left the working file alone
hello
$ minigit add nope.txt
minigit: no such file: nope.txt
  (exit 1)
$ minigit commit -m "nothing staged"
minigit: nothing staged to commit
  (exit 1)
$ minigit show 0123456789abcdef
minigit: unknown commit '0123456789abcdef'
  (exit 1)
$ minigit diff f77f436f81ed2cb1
minigit: usage: minigit diff <commit-a> <commit-b>
  (exit 2)
```

`minigit status` in a directory with no repository prints
`minigit: not a minigit repository (run 'minigit init' first)` and exits 1; a
second `minigit init` says the repository already exists and exits 0.

## Filed upstream — please submit these

Five bugs and two feature gaps, each minimized to the smallest source that still
triggers it, with the closest compiling control verified rather than remembered:

- **`BUG-optional-chain-into-getter.md`** — the serious one. `name?.len` panics
  the compiler (`panic: codegen: undeclared getter string.len`, Go stack trace);
  `box?.size` on a *user-declared* getter compiles and then **segfaults at
  runtime**; `box?.value` on a plain field is fine, and `name?.is_empty` happens
  to work. Only the present-value path of a getter access through `?.` is broken.
- **`BUG-bare-call-on-tuple-returning-failable.md`** — `promise guide` says
  `foo()?^` is "the same as bare call", but for a failable function returning a
  tuple they differ: `(head, tail) := split_at(x)` binds `head` to the whole
  tuple and `tail` to an `error`, while `(head, tail) := split_at(x)?^` works.
- **`BUG-trailing-comma-rejected-in-argument-lists.md`** — trailing commas are
  fine in vector/map literals, match arms and enum bodies, and rejected in call,
  constructor, parameter and tuple lists.
- **`BUG-duplicate-use-across-project-files.md`** — `use io;` in two files of one
  project is `io redeclared in this scope`, so a file cannot declare its own
  imports; the import is project-global whether you write it or not.
- **`BUG-format-merges-comment-blocks.md`** — cosmetic: `promise format` deletes
  the blank line between a file-header comment and the next doc comment, merging
  them into one block.
- **`FEATURE-promise-run-cannot-pass-arguments.md`** — `promise run` has no way
  to pass argv to the program (extra tokens, even after `--`, are read as more
  source files), which is awkward for a CLI project.
- **`FEATURE-no-stdlib-digest-module.md`** — no `hash`/`digest`/`crypto` module in
  the catalog; the nearest things are `gzip.crc32` and the undocumented-stability
  `Hashable.hash`. Did not block me (the task allowed rolling my own), but every
  content-addressed project will ship its own copy of FNV-1a.

## What surprised me about Promise

**Flow-sensitive narrowing is stronger than I expected, in both directions.**
After `if value is absent { return none; }` the compiler treats `value` as a
plain `string` for the rest of the function — my `value!` unwrap after that guard
was rejected with "unwrap (!) requires an optional expression", which is a very
satisfying error to get. The same narrowing bit me in `cmd_log`: an early
`if cursor is absent { ...; return; }` narrowed `cursor` to `string`, so the
`while id := cursor` unwrap-loop below it no longer type-checked. Restructuring
around the narrowing (drop the early return, print "no commits yet" if the loop
never ran) made the function shorter, so the compiler was right.

**Ownership is unobtrusive right up until it isn't, and then it is specific.**
Roughly one error per fifteen lines on the first build, all of the form "you
borrowed this, you need to own it": `root.clone()` in a factory that stores its
argument, `move` on constructor arguments, `blob.clone()` because
`staged[file] = blob` consumes the value. Two asymmetries I had to learn by
experiment: map *keys* are copied implicitly while map *values* are moved, and
`return x;` moves an owned local — `return move x;` is a parse error even though
`move` is required at ordinary call sites.

**Failable functions are genuinely pleasant.** Writing `!` on a function and then
just calling `io.File.read_content(path)` bare, with errors auto-propagating,
removes almost all error plumbing; `MiniGitError is error` with an extra
`int status` field, caught once in `main` with `if failure is MiniGitError`, gave
me exit codes for free. The one sharp edge is that `?!` means *panic* even inside
a failable function, which reads like the opposite of what you'd guess.

**Small things that made the code shorter than I planned:**
`int.to_string(base: 16, width: 16, fill: '0')` renders a hash id in one call;
`sort(move names)` needs no comparator for strings; `use handle := io.File.open(...)`
closes the file at scope exit; triple-quoted strings hold the usage text verbatim;
`{expr}` interpolation accepts arbitrary expressions including `?:`.

**Documentation quality is high, with one stale spot.** `promise doc <module>`
gave me exact signatures for everything I used, and I never had to guess an API.
But `promise doc`'s module index still lists `time` as a "placeholder — pending
native PAL support" while `time.DateTime.now()`, `from_unix_secs` and RFC 3339
formatting all work — I nearly wrote my own timestamp formatting because of that
line.

**One design note rather than a complaint:** `io.File.read_content` returns a
`string`, so it is the wrong tool for a version control tool's blobs. The
byte-level path (`File.read` into a `u8[]`, `File.write` out of one) is there and
works, but `Writer.write` takes `u8[]~` — a *mutable* borrow — which forced `~`
annotations all the way up through `put_blob` for data that is only ever read. A
`write(u8[] data)` shared-borrow overload would remove that ripple.
