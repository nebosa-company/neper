# Brief: write one Neper library module + its fixture

Repository: D:\repos\neper (work in the MAIN tree; do not touch git, docs/, modules.json, other modules, and never run test suites or WSL — only the two commands below). Never delete or clean the scratchpad directory or anything you did not create: put your own files in a subdirectory named after your module.

## Deliverables
1. `lib/e/<path>.e` — the module (caller-storage API, no allocation unless an `a: *mem.Arena` is the natural first parameter).
2. `tests/selfhost/fixtures/link/<fixture_name>/src/main.e` — a fixture whose checks each exit with their own code (`os.exit(1i32)`, `os.exit(2i32)`, …) and which prints `<name> ok\n` at the end. Expected values must come from a Python brute-force/reference computed in your scratchpad subdirectory (under D:\Temp\claude\D--repos-neper\779abd3d-a830-4415-922e-aa23a9b5bb22\scratchpad), never from hand arithmetic.
3. A final report: the public function list with one-line descriptions, the module's `use` lines, anything deferred (with a `ponytail:` comment in the code naming the ceiling), and compiler quirks you hit.

## Commands
- Type-check: `build/windows/neper-try.exe check-file lib/e/data/x.e . x64 windows` (prints `module check ok`).
- Build + run the fixture with both compilers: `bash build/fx.sh <fixture_name>` — both must print the ok line and `exit=0`. A trap prints a stack with file:line.
- Write files with the Write tool; bash heredocs and `sed` mangle backslashes and apostrophes. A hanging fixture = an infinite loop: run `timeout 10 build/fx_<name>.exe` and bisect with `try io.print("step N\n")`.

## Neper idioms (read `lib/e/data/treap.e`, `lib/e/data/spatial.e` and `tests/selfhost/fixtures/link/data_treap/src/main.e` first)
- Numbers are typed literals: `0usize`, `1u32`, `0.0f64`, `1i64`; `usize(x)` converts; NARROWING TRAPS (mask before `u8(x)`/`u32(x)`); `0i64 - x` negates; `+% -% *%` wrap; `u64(negative i64)` traps; shifts trap at the full width.
- Bitwise not is `~`; shifts take a `u32` count: `x >> 1u32`, `1u64 << u32(k)`; parenthesise `(x & 1u64) == 1u64`.
- `ret (zero, TooSmall)`; errors are declared `error TooSmall` / `error Invalid` at module scope and compared with `!= ok`, `== mod.Invalid`.
- `ret f()` cannot forward a tuple — bind first: `let (x, e) = f()` then `ret (x, e)`.
- `try` only inside a function returning plain `err`; in a tuple-returning function bind the error and `ret (zero, e)`. `try f(&local)` does not lower either.
- A discarded non-void call is refused: write `let _ = f()`.
- A local/parameter may NOT reuse the name of any module-scope fn of the same module, of an imported module alias, of a `.len` property, nor a name already bound in an enclosing scope of the same function; reserved: `case`, `error`, `target`, `shared`, `next`, `at`, `main`, `capacity`, `use`, `Vec`.
- Read-only slices: `[]const T`; mutable struct by pointer `*T`; field access through pointers is `t.field`; slice sub-ranges `xs[lo..hi]`, `xs[..n]`; `.len` on slices; a `*u64` parameter is read/written with `*p`.
- Structs: `type X = struct { a: []u32, n: usize }` — EVERY type declaration (`struct`, `union`, `enum u8 { A, B }`) on ONE line; literal `X { a: a, n: 0usize }`; enums used as `.A`; no enum→integer casts; fixed arrays `var x: [N]T = zero`, literals `[3]f64{ 1.0, 2.0, 3.0 }`; arrays of structs by element assignment; `x = zero` re-assignment of a var is refused; no if-expressions; no `break`; no `\u` escapes (`\xNN`); no `const X: f64/str` (use `fn pi() -> f64 { ret 3.14... }`).
- Strings: `str` indexes to `u8`; a `[]u8` result may be returned as `str`; `str` literals pass as `[]const u8`.
- `math.sqrt[f64](x)` (`use e.math`); `bytes.count_ones[u32]` for popcount; no `tanh` (use `exp`).
- Pointer-to-float parameters (`*f64`) work since D867, but prefer returning tuples or passing a record pointer.
- `while`/`if`/`else` without parens; `continue` exists; recursion is fine.
- Fixture skeleton:
  ```
  use e.data.foo as foo
  use e.io
  use e.mem
  use e.os
  fn main(a: *mem.Arena, args: []str) -> err {
      // 1: ...
      if ... { os.exit(1i32) }
      try io.print("data foo ok\n")
      ret ok
  }
  ```
- Keep fixtures under ~300 statements; large data is generated in-fixture by an LCG (`state = state *% 6364136223846793005u64 +% 1442695040888963407u64`, take `state >> 33u32`) and replicated in the Python reference; exit codes are read mod 256.
- Every public function named in the plan (`→ e.mod.fn` annotations) must exist under exactly that name; add the obvious companions (build/query/remove) so the module is usable.
