# Promise Zoo — conventions for adding/recording runs

This repo is a gallery of Promise programs built by AI agents. Each **task** is a
folder; each **agent run** lands in a `<task>-<agent>/` subdir. When you add or record
a run, keep every task's `README.md` on the same structure so entries read uniformly.

## Task README structure

Copy [`TEMPLATE.md`](TEMPLATE.md) as the task's `README.md` and fill it in. The order is:

1. `# <task name>` + one-line description of what's built and what it probes.
2. Prompt pointer (`prompt.md`, wrapped with `PROMPT_PREFIX.md` / `PROMPT_SUFFIX.md`).
3. "Each agent's run is in its own `<task>-<agent>/` subdir…" paragraph.
4. **Recording block** (see below) — placed high, right after the subdir paragraph.
5. (Optional) `## Attribution` if the task is inspired by outside work.
6. `## Results` table: `| Agent | Outcome | Run |`, with a `▶ watch` link in the Run cell.
7. (Optional) bug/feature findings list.
8. `## Caveats` (non-deterministic / version-pinned / early).

## Recording block — the standard

Every recorded run gets a **prominent, clickable cast image** near the top of the task
README — NOT just a buried `▶ watch` link in the Results table. The image draws the
eye; the table link is the secondary, per-row pointer (keep both).

Each agent's cast lives between **agent-scoped cast markers**, sized to **~half the
README width** via the `<img>` `width` attr. `bin/upload.sh` fills the `<a><img>` embed
in once the recording is uploaded; until then it's a "pending" note:

```html
**▶ Watch the run** — faithful playback in the asciinema player (a GIF can't render
the live TUI cleanly):

<!-- cast:claude width=50% -->
<a href="https://asciinema.org/a/<CAST_ID>"><img src="https://asciinema.org/a/<CAST_ID>.svg" width="50%" alt="asciicast — <task>, Claude Code"></a>
<!-- /cast:claude -->
```

Rules:
- **Markers are required.** `<!-- cast:<agent>[ width=<pct>] -->` … `<!-- /cast:<agent> -->`
  is how `bin/upload.sh` and `bin/record.sh --rerecord` find and rewrite each agent's
  cast unambiguously. The optional `width=` on the marker controls the embed: keep
  `width=50%` for a single cast; **omit it** for side-by-side casts (see below).
- Use the HTML `<a><img></a>` form, **not** the markdown `[![asciicast](…svg)](…)` form
  — the latter renders full-width (too big). Don't hand-edit a cast URL: run
  `bin/upload.sh` and it stamps the embed + the Results `▶ watch` link for you.
- **Multiple runs** (e.g. Claude + Gemini): put each agent's marker block in its own
  cell of a side-by-side table and **drop `width=`** — a 2-col table already renders
  each at ~half width (`width="50%"` inside a cell would shrink to ~quarter). See
  [`hello-world/README.md`](hello-world/README.md).
- Single run: keep `width=50%`. See [`line-count/`](line-count/README.md) and
  [`mini-git/`](mini-git/README.md).
- Always keep the per-row `· [▶ watch](https://asciinema.org/a/<CAST_ID>)` link in the
  Results table too (also stamped by `bin/upload.sh`; `PENDING` until then).

## Recording a run

- **First run:** `bin/record.sh <agent> <task-dir>` records the agent into
  `<task>-<agent>/`, then `bin/upload.sh <agent> <task-dir>` uploads the cast and
  **auto-stamps** the URL into `context.md` (the `Recording` row) and the README (the
  agent's cast embed + `▶ watch` link). Fill in the editorial bits (Outcome cell, any
  findings list) by hand.
- **Re-recording against a newer toolchain:** `bin/record.sh --rerecord <agent> <task-dir>`.
  It refuses unless the existing run is **committed and clean** (it relies on git
  history to preserve the old run), then:
  - wipes the run dir and re-runs the agent fresh (as a first run would);
  - keeps **only the current** source + summary in-tree — old source/summary/cast stay
    in git history, reached via pinned-commit links;
  - grows a **`## Prior runs`** table in the README (newest-first; `Agent · Date ·
    Promise · Bugs · ▶ play · browse@commit`) with a one-line **progress aggregate**
    (`> **N runs** · Promise <oldest>→<current> · compiler bugs hit b₀→…→b_now`), and a
    **`## Previous runs`** lineage in `context.md` (with `SUMMARY` / `demo.cast` /
    `browse` links pinned to the old commit);
  - resets this agent's cast/`▶ watch` to `pending`/`PENDING`.
  Then run `bin/upload.sh <agent> <task-dir>` to stamp the new recording, and review
  the agent's Outcome cell + findings list (those stay editorial). Bug counts in the
  table/aggregate come from each run's `BUG-*.md` files at its commit.
