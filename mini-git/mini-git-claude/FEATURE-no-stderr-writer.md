Please file this upstream at https://github.com/promise-language/promise/issues

# No way to write to stderr — a program can read the standard streams but not write to the error one

- **`promise version`:** `promise version 2026.4 (channel stable)`
- **Platform:** macOS 26.5.2 (arm64), Darwin 25.5.0 arm64

## What I needed and why

mini-git is a CLI. The task called for the obvious failure cases (missing file,
empty staging area, unknown commit id, unstaging something that isn't staged, no
repository) to be reported "with a clear message and a sensible exit code." The
universal convention for a CLI is: **data on stdout, diagnostics on stderr,
status in the exit code.** That separation is what makes a tool composable —
`minigit log | head` should pipe commit data, not have error text interleaved
into it, and `2>/dev/null` should be able to silence diagnostics without
discarding output.

I can set the exit code (`os.exit_process`), but I cannot put the message
anywhere except stdout.

## What's missing

Promise 2026.4 exposes the standard streams for **input only**. The entire
surface, from `promise doc std` and `promise doc io`:

- `std` — `print(Format f)` and `print_line(Format f)`, both hardwired to
  **stdout**. There is no `eprint` / `eprint_line`, and no way to retarget them.
- `io` — free functions `io.read_line()` and `io.read_stdin()` (stdin), plus
  `io.File`, `io.Dir`, and buffered reader/writer types. There is **no
  `io.stdout` / `io.stderr` handle**, and no factory for wrapping an existing
  file descriptor (fd 1 or fd 2) in a `File`/`Writer`.
- The only `stderr` anywhere in the stdlib belongs to the *subprocess* API
  (`os.ProcessResult.standard_error`, `os.Process.take_standard_error()`) — i.e.
  a parent can read a **child's** stderr, but no program can write to its **own**.

There is a `Writer` structural interface (`write(~this, u8[]~ buf) int`), and
`io.File` satisfies it — but nothing hands you a `Writer` bound to fd 2.

## Did it block me?

**Not a hard blocker — but it forced a workaround that makes the tool objectively
worse.** All diagnostics go to stdout:

```promise
main() {
  run(os.args) ? e {
    print_line("minigit: {e.message}");   // should be stderr
    os.exit_process(1);
  };
}
```

So `minigit status 2>/dev/null` on a non-repo still prints the error, and piping
`minigit log` into another tool risks interleaving a diagnostic into the data
stream.

## Sketch of an API that would make it clean

Any one of these would suffice; the first is the smallest and most idiomatic:

```promise
// 1. Mirror print / print_line for stderr in std (least surprising):
eprint("bad input");
eprint_line("minigit: {e.message}");

// 2. Expose the standard streams as Writers in io:
io.stderr.write_line("minigit: {e.message}");
io.stdout.write_line("data");

// 3. A factory to wrap an existing fd in a File/Writer:
io.File err = io.File.from_fd(2);
err.write_line("minigit: {e.message}");
```

Option 1 alone (`eprint` / `eprint_line`) would cover the 90% CLI case with no
new types.

## Note

This gap was already present in Promise 2026.3 and is unchanged in 2026.4.
