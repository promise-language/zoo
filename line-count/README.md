# line-count

A concurrent line-counting CLI: the agent builds a tool that takes file paths,
counts each file's lines on its own green thread, prints per-file counts plus a
grand total, and skips unreadable files instead of crashing. Probes Promise's
concurrency model, error operators, and ownership annotations on a real
multi-file program — and whether the result reads cleanly.

Prompt: [`prompt.md`](prompt.md) — the task-specific ask, wrapped with the repo-root
[`PROMPT_PREFIX.md`](../PROMPT_PREFIX.md) / [`PROMPT_SUFFIX.md`](../PROMPT_SUFFIX.md)
before being sent to each agent.

Each agent's run is in its own `line-count-<agent>/` subdir: the generated `.pr`, the
recording (`demo.cast`, played with the asciinema player), `SUMMARY.md` (the
agent's TL;DR of how it went), `context.md` (that run's provenance), and any
`BUG-*.md` / `FEATURE-*.md` it filed (a reproducible compiler bug, or a missing
stdlib module / language feature — captured for filing upstream).

## Results

| Agent | Outcome | Run |
|---|---|---|
| Claude Code | <compiled first try? · N iterations · ~time> | [`line-count-claude/`](line-count-claude/) |
| Gemini | <…> | [`line-count-gemini/`](line-count-gemini/) |

## Caveats

- **Non-deterministic** — each run is "what happened that time," not a verbatim repro.
- **Version-pinned** — the Promise version for each run is in its `context.md`.
- Promise is early and not production-ready.
