Please file this upstream at https://github.com/promise-language/promise/issues

# No way to write to stderr — a program can read the standard streams but not write to the error one

- **`promise version`:** `promise version 2026.3 (channel stable, commit fe13dcd)`
- **Platform:** macOS 26.5.1 (arm64), Darwin 25.5.0

## What I needed and why

mini-git is a CLI. The task called for the obvious failure cases (missing file, empty
staging area, unknown commit id, unstaging something that isn't staged, no repository) to
be reported "with a clear message and a sensible exit code". The universal convention for
a CLI is: **data on stdout, diagnostics on stderr, status in the exit code.** That
separation is what makes a tool composable — `minigit log | head` should pipe commit data,
not have error text interleaved into it, and `2>/dev/null` should be able to silence
diagnostics without discarding output.

I could set the exit code (`os.exit_process`), but I could not put the message anywhere
except stdout.

## What's missing

Promise 2026.3 exposes the standard streams for **input only**. The entire surface, from
`promise doc std` and `promise doc io`:

- `std` — `print(Format f)` and `print_line(Format f)`, both hardwired to **stdout**. No
  `eprint` / `eprint_line`, and no way to retarget them.
- `io` — free functions `io.read_line()` and `io.read_stdin()` (stdin), plus `io.File`.
  There is **no `io.stdout` / `io.stderr` handle**, and no factory for wrapping an existing
  file descriptor.
- The only `stderr` anywhere in the stdlib belongs to the *subprocess* API
  (`os.ProcessResult.standard_error`, `os.Process.take_standard_error()`) — i.e. a parent
  can read a **child's** stderr, but no program can write to its **own**.

There is a `Writer` structural interface (`write(~this, u8[]~ buf) int`), and `io.File`
satisfies it — but nothing hands you a `Writer` bound to fd 2.

## Did it block me?

**Not a hard blocker — but it forced a workaround that makes the tool objectively worse.**
All diagnostics go to stdout:

```promise
main() {
  …
  dispatch(argv) ? e {
    print_line("minigit: {e.message}");   // should be stderr
    os.exit_process(exit_error);
  };
}
```

Exit codes are still correct (1 for errors, 2 for usage, 0 for success), so scripts can
branch on `$?`. But error text lands in the data stream, so `minigit log | grep …` can see
diagnostics, and `2>/dev/null` silences nothing.

### The non-portable escape hatch doesn't work either

Opening the OS device by path is the usual last resort. On macOS it fails outright — so
there is genuinely *no* way to reach stderr from Promise here, portable or not:

```promise
use io;
main() {
  io.File f = io.File.append("/dev/stderr") ? e { print_line("FAILED: {e.message}"); return; };
  f.write_line("hello");
  f.close() ? e {};
}
```

```sh
$ promise run stderr.pr
FAILED: permission denied
```

`io.File.open("/dev/stderr", readonly: false)` fails the same way (`permission denied`).

## Sketch of the API that would have made this clean

The smallest thing that would work — two free functions in `std`, mirroring `print`/`print_line`:

```promise
eprint(Format f);        // write to stderr, no trailing newline
eprint_line(Format f);   // write to stderr, with newline

main() {
  dispatch(argv) ? e {
    eprint_line("minigit: {e.message}");
    os.exit_process(1);
  };
}
```

And, for anything beyond one-shot printing, the standard streams as first-class `Writer`s /
`Reader`s in `io` — so they compose with `Builder`, `format!(Writer~ w)`, buffering, and
redirection:

```promise
use io;

get stderr Writer;   // fd 2
get stdout Writer;   // fd 1
get stdin  Reader;   // fd 0

main!() {
  io.stderr.write_line("minigit: not a repository");

  // composes with the existing Format/Writer machinery:
  io.BufferedWriter w = io.BufferedWriter(io.stdout);
  commit.format(w);
  w.flush();
}
```

Being able to pass `io.stderr` as a `Writer~` would also make code testable — a function
that takes `Writer~ out` can be pointed at a `Builder` in a test and at `io.stderr` in
production, which is impossible today because `print_line` is hardwired.
