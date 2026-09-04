# neper

A minimal procedural language designed to be **written by language models and read by
people**: stack-resident records, arena memory, direct machine code for CPU and GPU,
and no LLVM anywhere in the pipeline.

```
use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    try io.print("hello, neper\n")
    ret ok
}
```

Source files end in `.e`. Compiled modules end in `.em`, one per target
(`math.x64-windows.em`, `math.spv.em`), in the style of Delphi's DCU files.

## Why it exists

The expected author is a model. The expected reader is a human reviewing what that
model wrote, or a tool searching and amending it. neper is built to be read fluently
and audited quickly — not to be typed by hand all day.

That inverts the usual trade. Every top-level declaration starts at column 0 with a
keyword, names are never overloaded, casts are always written down, and a file's path
is its module name. `grep -n "^fn parse_expr"` returns exactly one line in any
module, every time.
Where verbosity buys certainty, verbosity wins: keystrokes are spent by a generator,
but ambiguity is paid for by the reviewer.

The performance goals come from the same place. Most languages force a choice between
compiling fast and running fast; a small language with a direct machine-code emitter
and no hidden allocation gets both, at the cost of an optimiser that starts out
simpler than LLVM's. Generated code is regenerated often, so a slow compiler taxes
every iteration.

## Status

Design draft with the M0 bootstrap walking skeleton implemented. The throwaway C99
compiler lexes and parses the M0 procedural subset, resolves the bundled bootstrap
modules, checks the fixed program-entry signature, emits x86-64 assembly and object
files, links with the system linker, and runs `examples/hello.e` on Windows and
Linux. Startup constructs the root arena and UTF-8 `args`; `try` propagates named
errors; bounds and invalid-division checks exit through the trap path; and emitted
objects carry line, symbol, unwind and compact `.nepersym`/`.nepsym` data. The
self-hosted compiler and later milestones have not started.

On Windows with the Visual Studio C++ tools installed:

```powershell
./scripts/build-bootstrap.ps1
./build/neper.exe run ./examples/hello.e
./tests/m0/run.ps1
```

On Linux:

```sh
./scripts/build-bootstrap.sh
./build-linux/neper run ./examples/hello.e
./tests/m0/run.sh
```

- [`docs/spec.md`](docs/spec.md) — the language specification
- [`docs/grammar.ebnf`](docs/grammar.ebnf) — normative concrete grammar and token registry
- [`docs/tooling.md`](docs/tooling.md) — normative harness, JSONL, span and formatter contracts
- [`docs/diagnostics.md`](docs/diagnostics.md) — stable diagnostic-code registry
- [`docs/roadmap.md`](docs/roadmap.md) — implementation milestones
- [`DECISIONS.md`](DECISIONS.md) — settled architecture decisions and their reasoning
- [`docs/modules.md`](docs/modules.md) — the standard library and package plan
- [`docs/module-apis.md`](docs/module-apis.md) — exact proposed APIs for toolchain modules
- [`docs/modules.json`](docs/modules.json) — machine-readable module catalogue
- [`docs/general-purpose-verification.md`](docs/general-purpose-verification.md) — workload and LLM-generation acceptance plan
- [`docs/pacman.md`](docs/pacman.md) — the M6 package manager architecture
- [`examples/sample.e`](examples/sample.e) — every construct in the language, once, in one program
- [`examples/`](examples/) — what the language is meant to look like

## Shape of the thing

| | |
|---|---|
| Memory | Stack and explicit arenas. No GC, no global allocator. |
| Errors | `(T, err)` multi-return with the `try` keyword. No exceptions. |
| Abstraction | Compile-time parameters in `[...]`, monomorphised. No macros. |
| Vectors | Builtin `Vec[T, N]` over a closed width table, explicit `simd` intrinsics. No auto-vectoriser. |
| CPU targets | x64, aarch64, x86-32 — emitted directly, no LLVM |
| GPU targets | SPIR-V (Vulkan), PTX (CUDA) — explicit `@gpu` kernels, also runnable on the CPU for debugging. Apple via MoltenVK now, native Metal at M5 |
| Safety | Bounds, null and overflow checks on in debug, elided in release; division traps in every mode; a failed check prints `file:line:col`, the values and a backtrace |
| Testing | `@test` functions found by the compiler; `neper test` runs one process per test, captures it, and reports deterministic JSONL — a trap is one test's outcome, not the end of the run |
| Compiler | Work-stealing across all cores, parallel parse, per-thread arenas, deterministic output |
A provider-agnostic benchmark for the language's LLM search and editability goal is
available in [`benchmarks/llm_edit`](benchmarks/llm_edit/README.md).
