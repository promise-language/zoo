# line-count-claude

Promise project. Use `promise guide` for the full language reference.

## Quick Start

```bash
promise run                     # build and run
promise build                   # build only
promise test                    # run tests
promise exec 'print_line("hi")' # run a one-liner
promise doc <module>            # show module API docs
```

## Error Handling

```
main!() {   # ! marks main failable (can return error)
  f();      # unhandled errors raise to caller
  f()?^;    # explicit propagation - raise error to caller
  f()?!;    # panic on error
  v := f() ? { fallback(); };  # catch with recovery block
}
```

## Module Rules

- Import with `use io;` — access as `io.File`, `io.Dir` (always module-qualified)
- Standard library (`std`) is auto-imported — `print_line`, `Vector`, `Map`, etc. need no prefix

## Available Modules

| Module | Purpose | Docs |
|--------|---------|------|
| `io` | File I/O, buffered readers/writers, directories | `promise doc io` |
| `os` | Environment, process execution, signals | `promise doc os` |
| `json` | JSON encode/decode, JsonValue | `promise doc json` |
| `path` | Path joining, dir/base/ext extraction | `promise doc path` |
| `math` | Extended math functions | `promise doc math` |
| `strings` | Extended string utilities | `promise doc strings` |
| `time` | Extended time utilities | `promise doc time` |
| `http` | HTTP client | `promise doc http` |
