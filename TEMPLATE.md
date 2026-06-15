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
agent's TL;DR of how it went), and `context.md` (that run's provenance).

## Results

| Agent | Outcome | Run |
|---|---|---|
| Claude Code | <compiled first try? · N iterations · ~time> | [`<task>-claude/`](<task>-claude/) |
| Gemini CLI | <…> | [`<task>-gemini/`](<task>-gemini/) |

## Caveats

- **Non-deterministic** — each run is "what happened that time," not a verbatim repro.
- **Version-pinned** — the Promise version for each run is in its `context.md`.
- Promise is early and not production-ready.
