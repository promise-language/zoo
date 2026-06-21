Please file this upstream at https://github.com/promise-language/promise/issues

# No wall-clock time in the standard library (and `time` catalog module is unimplemented)

## Version / platform
- `promise version 2026.1 (commit 134062029f2156f915b98b41fb991d44eb23b0ae)`
- macOS 26.5.1 (arm64), Darwin 25.5.0

## What I needed and why
mini-git records a timestamp on every commit (`commit -m`), so `log` and `show`
can report when each commit was made. That requires reading the current
wall-clock time (Unix epoch seconds is plenty).

## What's missing
There is no way to read wall-clock time from Promise code today:
- `std` exposes only **monotonic** time: `Instant.now()` / `Duration`. Monotonic
  time has no defined relationship to the calendar — it's only good for measuring
  elapsed intervals, not for "when did this happen".
- The `time` catalog module (which would provide `DateTime.now()`,
  `from_unix_secs`, formatting, etc.) is documented but not implemented —
  `promise doc time` prints "**Planned module** — this module is not yet
  implemented."
- `os` has process/env helpers but nothing time-related.

So the obvious, in-language way to get a commit timestamp does not exist.

## Did it block me?
Not outright — it forced a workaround. mini-git stays in-language by shelling out
to the system `date` via `os.execute`, which is part of the standard library:

```promise
now_timestamp!() string {
    r := os.execute("date", ["+%s"]);
    return r.standard_output.trim();
}
```

This works but is unsatisfying: it depends on an external `date` binary existing
on `PATH`, it can't run on a target without a shell (e.g. `wasm32-wasi`), and it
yields a raw epoch integer with no way to format it for humans — so `log` prints
`date   1781799445` instead of a readable date.

## Sketch of the API that would have made it clean
Either land the planned `time` module:

```promise
use time;
int secs = time.DateTime.now().unix_secs;          // for the stored timestamp
string when = time.DateTime.from_unix_secs(secs).to_string();  // "2026-06-18T16:30:45Z"
```

…or, at minimum, expose a single wall-clock primitive in `std` next to `Instant`,
mirroring the design doc's planned PAL `promise_wallclock`:

```promise
// std
get wall_now_nanos int;   // nanoseconds since the Unix epoch (CLOCK_REALTIME)
```

Even just `wall_now_nanos` would let a program get a real timestamp without a
subprocess; calendar formatting could follow in the `time` module.
