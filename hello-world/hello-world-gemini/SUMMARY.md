# Promise Hello World Summary

## What Was Built
I built a classic "hello, world" program in the new statically-typed, natively-compiled Promise programming language. The code defines a standard entry point using the `main()` function and utilizes the auto-imported standard library function `print_line` to print `"hello, world"` to stdout.

## Compilation and Execution
- **Compiled on the first try?** Yes, it compiled successfully on the first attempt using the command `promise build hello.pr`.
- **Ran on the first try?** Yes, the compiled native binary `./hello` executed successfully on the first attempt.
- **Program Output:**
  ```
  hello, world
  ```

## Observations and Surprises about Promise
Since Promise is not in my training data, reviewing the language guide and compiler help uncovered several interesting design decisions:
- **Rust-like ownership with Go-like ease of use:** Types like strings are move-by-default, but the compiler automatically infers borrows based on parameter declarations. There is no need to write `&` or `~` reference symbols at the call site.
- **Failable functions and automatic error propagation:** Functions that can fail are suffixed with a `!` (e.g., `main!()`). Errors auto-propagate via bare function calls or `?^` inside failable functions, while `?!` explicitly panics.
- **Constructors and properties:** Object constructors require named arguments (e.g., `Point(x: 1, y: 2)`), and getter methods use property syntax without parentheses (e.g., `nums.len` instead of `nums.len()`).
- **Map literals:** Empty maps cannot be defined as `{}` (which is rejected); they must be written as `{:}` to distinguish them from empty structures/blocks.
