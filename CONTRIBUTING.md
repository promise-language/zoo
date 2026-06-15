# Contributing to the Promise Zoo

The **Promise Zoo** is part of the **Promise Lang** project, hosted in the
`promise-language` organization and maintained under Promise Lang LLC.

## Contributor License Agreement (CLA) required

Before any pull request can be merged, you must sign the **Promise Lang
Contributor License Agreement**. When you open your first pull request, the CLA
Assistant bot will post a link to sign. You only need to sign once — it covers
all future contributions across the project.

- **Individual contributors** sign the Individual CLA.
- **Contributors acting on behalf of an employer** also have their employer sign
  the Corporate CLA.

You retain copyright in your contribution; the CLA grants Promise Lang LLC the
rights it needs to administer, distribute, and sublicense it as part of the
project.

## Licensing of contributions

Unless you state otherwise, any contribution you intentionally submit for
inclusion is dual-licensed under the [Apache License 2.0](LICENSE-APACHE) and
the [MIT License](LICENSE-MIT), with no additional terms or conditions. This is
core, LLC-covered code: contributions must **not** introduce code under a
copyleft license (GPL, LGPL, AGPL, EUPL, or similar) or code of uncertain
provenance.

## How to contribute

The zoo is a gallery of real programs built in Promise by AI agents — each entry
is one run, with its prompt, the agent and model, the Promise version, and an
honest account of how it went (see the [README](README.md)).

1. Open an issue describing the task or agent you'd like to add, where practical.
2. Capture the run with [`bin/record.sh`](bin/record.sh) so the entry carries the
   same provenance as the others — the generated `.pr`, `context.md`,
   `SUMMARY.md`, and the asciinema recording.
3. Keep it honest: record what actually happened, including where the agent got
   stuck. The zoo keeps the rough edges, not just the clean wins.
4. Open a pull request and sign the CLA when prompted.
