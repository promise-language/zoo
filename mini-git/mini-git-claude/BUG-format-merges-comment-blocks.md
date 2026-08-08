Please file this upstream at https://github.com/promise-language/promise/issues

# `promise format` deletes the blank line between two top-level comment blocks, merging a file header into the next declaration's doc comment

`promise version 2026.6 (channel stable)` · macOS 26.5.1 (arm64, Apple Silicon)

Cosmetic, but it hits every multi-file project: the file-level header comment and
the doc comment of the first declaration end up as one undifferentiated block.

## Minimal repro

`fmtblank.pr`:

```promise
// File header: what this file is about.

// What this function does.
answer() int => 42;

main() {
  print_line("{answer()}");
}
```

```sh
promise format fmtblank.pr
```

Output file (the blank line on line 2 is gone; the result is stable under a
second `promise format`, so it is not an idempotence problem — the line is just
dropped):

```promise
// File header: what this file is about.
// What this function does.
answer() int => 42;

main() {
  print_line("{answer()}");
}
```

## Expected behavior

A blank line separating two comment blocks is meaningful — it is what makes
"this is the file" distinguishable from "this is the next function" — and should
be preserved, the same way the blank line before `main()` is.

## What triggers it

| Source shape | Result |
|---|---|
| comment, blank, comment, declaration | **blank line deleted** (the two comments merge) |
| comment, blank, declaration | blank line deleted (comment attaches to the declaration) |
| declaration, blank, declaration | blank line preserved |
| comment, blank, blank, comment | not tried |

## Best guess at the cause

The formatter attaches comments to the following declaration as leading trivia
and re-emits them as a single run, discarding blank lines *inside* that trivia
while keeping the blank line it inserts *between* declarations.

## Workaround used in the real code

The blank line after each file's header comment was put back by hand after
running `promise format`; a future `promise format` on this project will merge
them again.
