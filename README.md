# Promise Zoo 🦉

A gallery of real programs built in [Promise](https://promise-lang.org) by AI
agents — each with the exact prompt, the model that wrote it, the language
version, and an honest account of how the run actually went.

## What this is

[Promise](https://promise-lang.org) is a statically-typed, natively-compiled
language designed so an AI agent can write **correct, maintainable** code — and
whose own compiler and standard library are themselves written by AI agents.

This repo is a record of that in practice. Each entry is one run: hand an agent a prompt, have it
build something in Promise, and record what happened — the prompt, the agent and
model, the Promise version, how many iterations / how long it took, **where it got
stuck**, and the resulting project.

It's meant to be read for yourself, not a benchmark — and it keeps the rough
edges, not just the clean wins.

## How it's organized

Each **task** is a folder with its own `prompt.md` (the task-specific ask) and a
`README.md` results table across agents (see [`TEMPLATE.md`](TEMPLATE.md)). The
prompt actually sent to each agent wraps that `prompt.md` with the repo-root
[`PROMPT_PREFIX.md`](PROMPT_PREFIX.md) (shared "learn Promise first" preamble) and
[`PROMPT_SUFFIX.md`](PROMPT_SUFFIX.md) (shared "write a SUMMARY, and report any
compiler bug or missing-library gap upstream" postamble). Each
**agent's run** lands in a `<task>-<agent>/` subdir (e.g.
`hello-world/hello-world-claude/`) — named so Promise's folder-derived binary is
descriptive (`./hello-world-claude`) — containing the generated `.pr` source,
`SUMMARY.md` (the agent's own TL;DR of how it went), `context.md` (provenance), and
the recording (`demo.cast`, viewed with the [asciinema player](https://docs.asciinema.org/manual/player/)
— `asciinema play demo.cast`). Runs are captured with [`bin/record.sh`](bin/record.sh).
A run that trips over a reproducible compiler bug, or needs something Promise doesn't
have yet, also leaves a `BUG-*.md` or `FEATURE-*.md` in its subdir — so each entry is
not just "did it build" but feedback on what to fix, what library module to add, or how
Promise could implement the prompt better.

## Honest caveats

- **Non-deterministic.** Agents don't produce identical output twice — each entry
  is "what happened in this run," not "run this and reproduce it exactly."
- **Version-pinned.** Every run records the Promise version it was built against;
  the language is evolving fast, so older runs may not build on newer epochs.
- **Early.** Promise is under active development and not production-ready.

## Attribution

Some tasks are inspired by work done elsewhere; where they are, the task's own
`README.md` gives full credit and links the source. In particular,
[`mini-git/`](mini-git/) is inspired by the MiniGit exercise from
[`ai-coding-lang-bench`](https://github.com/mame/ai-coding-lang-bench) by mame
(Yusuke Endoh). The zoo's prompts are written from scratch — we don't reproduce
others' task specs or test suites — and because the language, harness, and run
conditions all differ, **zoo runs are never comparable to the benchmarks that
inspired them.**

## License

Dual-licensed **Apache-2.0 OR MIT** (at your option), matching the Promise project
— see [LICENSE-APACHE](LICENSE-APACHE), [LICENSE-MIT](LICENSE-MIT), and
[NOTICE](NOTICE).

## About

Maintained by **Promise Lang LLC**. Learn about the language at
[promise-lang.org](https://promise-lang.org). Questions or want an early look?
**early@promise-lang.org**.
