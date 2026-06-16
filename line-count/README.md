# line-count

A concurrent line-counting CLI: the agent builds a tool that takes file paths,
counts each file's lines on its own goroutine, prints per-file counts plus a
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

**▶ Watch the run** — faithful playback in the asciinema player (a GIF can't render
the live TUI cleanly):

[![asciicast](https://asciinema.org/a/htmLPSuiBf1INIHq.svg)](https://asciinema.org/a/htmLPSuiBf1INIHq)

## Results

| Agent | Outcome | Run |
|---|---|---|
| Claude Code | ⚠️ compiled & ran correctly (20 byte-identical runs) — but only after several iterations past **4 reproducible compiler bugs**, captured as `BUG-*.md` · ~18m | [`line-count-claude/`](line-count-claude/) · [▶ watch](https://asciinema.org/a/htmLPSuiBf1INIHq) |
| Gemini | _not yet run_ | — |

**Compiler bugs this run found** — each minimized (with a verified "compiles fine" control) and filed upstream:

- [#1](https://github.com/promise-language/promise/issues/1) — `go f(arg)` task-handle double-frees a consumed heap argument
- [#2](https://github.com/promise-language/promise/issues/2) — plain `string p` parameter consumes, contradicting the guide
- [#3](https://github.com/promise-language/promise/issues/3) — `use x := failable()` codegen panic
- [#4](https://github.com/promise-language/promise/issues/4) — `value` field beside a heap field codegen panic

## Caveats

- **Non-deterministic** — each run is "what happened that time," not a verbatim repro.
- **Version-pinned** — the Promise version for each run is in its `context.md`.
- Promise is early and not production-ready.
