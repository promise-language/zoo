<!-- Copy this to a new task folder as README.md. Put the task-specific prompt in
     prompt.md (it gets wrapped with the repo-root PROMPT_PREFIX.md / PROMPT_SUFFIX.md);
     each agent's run lands in <task>-<agent>/ via bin/record.sh, which writes that
     run's SUMMARY.md (the agent's TL;DR) and context.md (provenance). -->

# <task name>

<One line: what the agent is asked to build, and what the task probes.>

Prompt: [`prompt.md`](prompt.md) — the task-specific ask, wrapped with the repo-root
`PROMPT_PREFIX.md` / `PROMPT_SUFFIX.md` before being sent to each agent.

Each agent's run is in its own `<task>-<agent>/` subdir: the generated `.pr`, the
recording (`demo.cast`, played with the asciinema player), `SUMMARY.md` (the
agent's TL;DR of how it went), `context.md` (that run's provenance), and any
`BUG-*.md` / `FEATURE-*.md` it filed (a reproducible compiler bug, or a missing
stdlib module / language feature — captured for filing upstream).

**▶ Watch the run** — faithful playback in the asciinema player (a GIF can't render
the live TUI cleanly):

<!-- Each run's cast lives between its agent's cast markers; bin/upload.sh fills in the
     <a><img> embed once the recording is uploaded (and bin/record.sh --rerecord resets
     it to this pending note). `width=50%` on the marker = a single ~half-width cast.
     For multiple runs side by side, put each agent's marker block in its own cell of a
     2-col table and DROP `width=` (a 2-col table already renders each at ~half width). -->
<!-- cast:claude width=50% -->
_▶ recording pending — run `bin/upload.sh claude <task>` to embed it_
<!-- /cast:claude -->

## Results

| Agent | Outcome | Run |
|---|---|---|
| Claude Code | <compiled first try? · N iterations · ~time> | [`<task>-claude/`](<task>-claude/) · [▶ watch](PENDING) |
| Gemini | <…> | [`<task>-gemini/`](<task>-gemini/) · [▶ watch](PENDING) |

## Caveats

- **Non-deterministic** — each run is "what happened that time," not a verbatim repro.
- **Version-pinned** — the Promise version for each run is in its `context.md`.
- Promise is early and not production-ready.
