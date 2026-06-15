# Hello, world

The simplest possible run — can an agent, with no prior knowledge of Promise,
learn the language from the toolchain and produce a working "hello, world"?

| | |
|---|---|
| **Agent / model** | <fill after run — e.g. Claude Opus 4.x / Gemini 2.x> |
| **Promise version (epoch)** | 2026.0 (commit 6adc890) |
| **OS / platform** | macOS <version> (<arch>) |
| **Date** | 2026-06-15 |
| **Outcome** | <fill after run — compiled first try? · N iterations · ~time> |

## Prompt

The exact prompt given to the agent, verbatim:

> **Promise is a brand-new statically-typed, natively-compiled programming
> language.** Its compiler is already installed on this machine as the `promise`
> command, but the language is *not* in your training data — so **first learn it:
> run `promise --help` and `promise guide`** to pick up the syntax and the project
> workflow. Then write the classic **"hello, world"** program in Promise, build it,
> and run it so we can see the output.

## Demo

<!-- Optional but encouraged — a short asciinema GIF of the agent building it,
     and/or the interactive cast link. Drop the file in this folder. -->
![demo](demo.gif)

## How it went

<fill after run — what worked, where it got stuck, whether it needed `promise
guide` more than once, any wrong guesses.>

## The project

The generated files are in this folder. Build & run:

```sh
promise build <entry.pr>
./<binary>
```

## Output

```
<paste the build + run output>
```
