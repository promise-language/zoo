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

Each run is a folder containing:

- a `README.md` with the run's provenance — see [`TEMPLATE.md`](TEMPLATE.md),
- the generated project (the `.pr` source), and
- the build/run output (plus an asciinema cast or GIF where there is one).

## Honest caveats

- **Non-deterministic.** Agents don't produce identical output twice — each entry
  is "what happened in this run," not "run this and reproduce it exactly."
- **Version-pinned.** Every run records the Promise version it was built against;
  the language is evolving fast, so older runs may not build on newer epochs.
- **Early.** Promise is under active development and not production-ready.

## License

Dual-licensed **Apache-2.0 OR MIT** (at your option), matching the Promise project
— see [LICENSE-APACHE](LICENSE-APACHE), [LICENSE-MIT](LICENSE-MIT), and
[NOTICE](NOTICE).

## About

Maintained by **Promise Lang LLC**. Learn about the language at
[promise-lang.org](https://promise-lang.org). Questions or want an early look?
**early@promise-lang.org**.
