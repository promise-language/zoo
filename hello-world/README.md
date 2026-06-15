# hello, world

The simplest task: can an agent, with **no prior knowledge of Promise**, learn the
language from the toolchain (`promise --help`, `promise guide`) and produce a
working "hello, world"?

Prompt: [`prompt.md`](prompt.md) — sent verbatim to each agent.

Each agent's run is in its own `hello-world-<agent>/` subdir: the generated `.pr`,
the recording (`demo.gif`), and `context.md` (that run's provenance + how it went).

## Results

| Agent | Outcome | Run |
|---|---|---|
| Claude Code | <compiled first try? · iterations · ~time> | [`hello-world-claude/`](hello-world-claude/) |
| Gemini CLI | <compiled first try? · iterations · ~time, or remove if not run> | [`hello-world-gemini/`](hello-world-gemini/) |

## Caveats

- **Non-deterministic** — each run is "what happened that time," not a verbatim repro.
- **Version-pinned** — the Promise version for each run is in its `context.md`.
- Promise is early and not production-ready.
