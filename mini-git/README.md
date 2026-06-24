# mini-git

A content-addressed version-control tool — `init` / `add` / `rm` / `status` /
`commit` / `log` / `show` / `diff` / `checkout` / `reset` — backed by a content hash
and on-disk state. Probes Promise's filesystem I/O, raw-byte handling,
CLI plumbing, error operators, and ownership annotations on a real multi-command
program — and whether the result reads cleanly.

Prompt: [`prompt.md`](prompt.md) — the task-specific ask, wrapped with the repo-root
[`PROMPT_PREFIX.md`](../PROMPT_PREFIX.md) / [`PROMPT_SUFFIX.md`](../PROMPT_SUFFIX.md)
before being sent to each agent.

Each agent's run is in its own `mini-git-<agent>/` subdir: the generated `.pr`, the
recording (`demo.cast`, played with the asciinema player), `SUMMARY.md` (the agent's
TL;DR of how it went), `context.md` (that run's provenance), and any `BUG-*.md` /
`FEATURE-*.md` it filed (a reproducible compiler bug, or a missing stdlib module /
language feature — captured for filing upstream).

**▶ Watch the run** — faithful playback in the asciinema player (a GIF can't render
the live TUI cleanly):

<!-- cast:claude width=50% -->
<a href="https://asciinema.org/a/Zm8HoT1IEtIyjAk0"><img src="https://asciinema.org/a/Zm8HoT1IEtIyjAk0.svg" width="50%" alt="asciicast — mini-git, Claude Code"></a>
<!-- /cast:claude -->

## Attribution — and why this is *not* a benchmark

This task is **inspired by** the "MiniGit" exercise from
[`ai-coding-lang-bench`](https://github.com/mame/ai-coding-lang-bench) by
[mame (Yusuke Endoh)](https://github.com/mame) — a quantitative study of how
efficiently Claude Code writes the same small program across 13 languages (writeup:
[English](https://dev.to/mame/which-programming-language-is-best-for-claude-code-508a) ·
[日本語](https://zenn.dev/mametter/articles/3e8580ec034201)). Full credit for the
original idea goes there.

The prompt in [`prompt.md`](prompt.md) is **our own, written from scratch.** That
project carries no license, so we did **not** copy its task specification, its exact
output strings, its mandated hash constants, or its test suite — we describe a similar
mini-git-like tool in our own words.

**These results are not comparable to that benchmark.** Different task wording; a
language (Promise) it never tested; a single non-deterministic run rather than 20×
per language; this zoo's interactive harness with its shared "learn Promise first"
preamble and "write a SUMMARY, file bugs upstream" postamble that the original never
used; and a different model and date. Read each entry below as one qualitative run in
Promise — not as a data point against the original's time / cost / lines-of-code
numbers.

## Results

| Agent | Outcome | Run |
|---|---|---|
| Claude Code | ⚠️ built all 10 subcommands; once it compiled, logic was correct on the first run — past **2 reproducible compiler bugs** (one a silent use-after-move soundness hole) + several guide/compiler mismatches. The earlier run's missing-wall-clock-time gap is now **resolved** (`time.DateTime.now()` works). Captured as `BUG-*.md` · ~17m | [`mini-git-claude/`](mini-git-claude/) · [▶ watch](https://asciinema.org/a/Zm8HoT1IEtIyjAk0) |
| Gemini | _not yet run_ | — |

**What this run found** — each minimized (with a verified "compiles fine" control) and captured for upstream:

- [`BUG-map-assign-moves-heap-string.md`](mini-git-claude/BUG-map-assign-moves-heap-string.md) — silent use-after-move: `map[k] = h` for a heap `string` moves the value into the map but doesn't flag `h` as moved; once the map is passed to any function, a later read of `h` returns an empty `string` (a soundness hole — it produced an empty hash in `add`'s success line)
- [`BUG-branch-return-moves-variable.md`](mini-git-claude/BUG-branch-return-moves-variable.md) — move analysis isn't branch-sensitive: a value moved inside an `if` branch that `return`s is still marked moved on the fall-through path

The earlier run's missing wall-clock-time gap is **resolved** in this toolchain (`time.DateTime.now()` now works), so no `FEATURE-*.md` this run.

## Prior runs

> **2 runs** · Promise 2026.1→2026.1 · compiler bugs hit 2→2

| Agent | Date | Promise | Bugs | Links |
|---|---|---|---|---|
| Claude Code | 2026-06-18 | 2026.1 | 2 | [▶ play](https://asciinema.org/a/R0W7ESiJeloezs86) · [browse](https://github.com/promise-language/zoo/tree/2f0a4df9a956c86d12b2119c7ca2fd13c04f836e/mini-git/mini-git-claude) |

## Caveats

- **Non-deterministic** — each run is "what happened that time," not a verbatim repro.
- **Version-pinned** — the Promise version for each run is in its `context.md`.
- Promise is early and not production-ready.
