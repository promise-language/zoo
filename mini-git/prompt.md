Build a small version-control tool in Promise — a self-contained "mini-git." Scaffold it with `promise init`, build the whole project into a single binary with `promise build`, and run it. The tool operates on the current directory and keeps all its data under a hidden repository directory (e.g. `.minigit/`). It supports these subcommands:

- `init` — create the repository directory; if one already exists, say so and exit cleanly.
- `add <file>` — read the file's raw bytes, compute a content hash, save the bytes as a content-addressed blob in the repository, and stage the filename.
- `rm <file>` — unstage a filename (remove it from the staging area); report it if the file wasn't staged.
- `status` — print the staged filenames, sorted, or indicate that nothing is staged.
- `commit -m "<message>"` — record a commit holding the staged files and their blob hashes, the message, a timestamp, and the previous commit's id; identify the commit by hashing its own contents, then advance the "current commit" pointer and clear the staging area. Refuse to commit when nothing is staged.
- `log` — walk the commit chain newest-to-oldest, printing each commit's id, timestamp, and message.
- `show <commit>` — print one commit's details: its id, timestamp, message, and its files (each with its blob hash), sorted.
- `diff <commit-a> <commit-b>` — compare the two commits' file sets by blob hash and report what was added, removed, or modified between them.
- `checkout <commit>` — restore the working directory to a commit: for each file the commit recorded, write its blob's bytes back to disk; then point "current commit" at it and clear the staging area.
- `reset <commit>` — move "current commit" to the given commit and clear the staging area, but leave the working-directory files untouched (that's the difference from `checkout`).

For content addressing, hash the raw bytes with a stable, deterministic hash so commit ids are reproducible across runs — use Promise's standard-library hashing or roll a simple one yourself (FNV-1a is plenty); the only constraint is to stay within the language and its standard library rather than reaching for a third-party dependency. Persist everything to the local filesystem so the tool works across separate runs (state lives on disk, not in memory), and keep the output deterministic: sort filenames, and print nothing stray. Handle the obvious failure cases — a missing file, an empty staging area, an already-initialized repo, an unknown commit id, unstaging something that isn't staged — with a clear message and a sensible exit code instead of crashing.

Write idiomatic Promise — explicit types, the error operators, ownership annotations — and make it read cleanly: I should be able to open the source and know exactly what it does.
