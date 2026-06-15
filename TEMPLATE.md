<!-- Copy this to a new task folder as README.md. Put the shared prompt in
     prompt.md; each agent's run lands in <task>-<agent>/ via bin/record.sh,
     which also writes that run's context.md (provenance + how it went). -->

# <task name>

<One line: what the agent is asked to build, and what the task probes.>

Prompt: [`prompt.md`](prompt.md) — sent verbatim to each agent.

Each agent's run is in its own `<task>-<agent>/` subdir: the generated `.pr`, the
recording (`demo.gif`), and `context.md` (that run's provenance + how it went).

## Results

| Agent | Outcome | Run |
|---|---|---|
| Claude Code | <compiled first try? · N iterations · ~time> | [`<task>-claude/`](<task>-claude/) |
| Gemini CLI | <…> | [`<task>-gemini/`](<task>-gemini/) |

## Caveats

- **Non-deterministic** — each run is "what happened that time," not a verbatim repro.
- **Version-pinned** — the Promise version for each run is in its `context.md`.
- Promise is early and not production-ready.
