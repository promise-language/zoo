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

Use a linked image sized to **~half the README width** via the `<img>` `width` attr:

```html
**▶ Watch the run** — faithful playback in the asciinema player (a GIF can't render
the live TUI cleanly):

<a href="https://asciinema.org/a/<CAST_ID>"><img src="https://asciinema.org/a/<CAST_ID>.svg" width="50%" alt="asciicast — <task>, <agent>"></a>
```

Rules:
- Use the HTML `<a><img width="50%"></a>` form, **not** the markdown
  `[![asciicast](…svg)](…)` form — the latter renders full-width (too big).
- The `<CAST_ID>` is the asciinema.org id (same one used in the Results `▶ watch` link).
- **Multiple runs** (e.g. Claude + Gemini): put the `<a><img></a>` blocks in a
  side-by-side table instead. A 2-column table already renders each image at ~half
  width, so **drop the `width` attr** there (`width="50%"` inside a 2-col cell would
  shrink to ~quarter). See [`hello-world/README.md`](hello-world/README.md).
- Single run: keep `width="50%"`. See [`line-count/`](line-count/README.md) and
  [`mini-git/`](mini-git/README.md).
- Always keep the per-row `· [▶ watch](https://asciinema.org/a/<CAST_ID>)` link in the
  Results table too.
