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

Design draft with the M0 bootstrap walking skeleton implemented and `neper-0`
implementation in progress. The throwaway C99
compiler lexes and parses the M0 procedural subset, resolves the bundled bootstrap
modules, checks the fixed program-entry signature, emits x86-64 assembly and object
files, links with the system linker, and runs `examples/hello.e` on Windows and
Linux. The first `neper-0` increment adds typed integer range `for`, `break`,
`continue`, integer local `+=`, and lexical block scopes. Startup constructs the
root arena and UTF-8 `args`; `try` propagates named errors; bounds and
invalid-division checks exit through the trap path; and emitted objects carry line,
symbol, unwind and compact `.nepersym`/`.nepsym` data. The first self-hosted compiler
slice now builds and runs under the bootstrap on both hosts. Its lexer lives in
`src/lex.e`; `src/main.e` imports it through the ordinary project-module resolver.
The lexer declares the frozen 94-kind grammar vocabulary and scans original-byte
spans, normalized newlines, comments, keywords, strict numeric and string forms, and
longest-match punctuation. Numeric lexing validates base digits, separator placement,
exponents, and the closed integer/float suffix sets. Quoted source, raw strings and
comments validate UTF-8 scalars and their context-specific control bytes; character
literals decode to exactly one byte. Every token now carries half-open original-byte
endpoints plus normalized one-based start/end lines and both scalar and UTF-16
columns. Invalid UTF-8 consumes Unicode maximal subparts as one recovery unit, and a
valid non-ASCII scalar in an ASCII-only token position remains one `Invalid` token.
Each token also owns the exact leading byte range since the preceding token, so BOM,
spaces, comments and trailing trivia through EOF partition the original input without
loss. The lexer enumerates that range as exact-span `Bom`, maximal-run `Space`, and
whole-line `Comment` trivia, including scalar and UTF-16 coordinates. The bootstrap
preserves comment context across an `Invalid` token, so the remaining line cannot be
mis-tokenized as code. The bootstrap now loads
transitive project modules,
resolves explicit import aliases and qualified declarations, rejects import cycles
and duplicate qualifiers, and reports diagnostics against the originating file.
The self-hosted front end also declares the frozen 54-kind syntax-node registry in
`src/syntax.e`. `src/parse.e` writes into caller-supplied node and child slices. Each
declaration owns its exact token children; the `File` root interleaves those nodes
with original separator and EOF tokens, while malformed input produces recoverable
`ErrorNode`s. Function declarations now expose nested compile-time parameters,
parameters, return specifications, and blocks. The first `parse` command path
exercises this lossless ordering and signature-level recovery. Type declarations
now expose generic parameters, named/pointer/slice/array/function aliases, aggregate
type nodes, struct/union fields, enum members, and tagged-union members. Function
blocks now own classified binding, assignment, call, propagation, cleanup, control,
return and compiler-directive statement nodes, with recovery contained inside the
surrounding block. Every statement now uses its grammar production; the legacy raw
token-balancing fallback has been removed. Return values now form primary, prefix,
precedence-aware binary, call, field and bracket-postfix expression trees while
preserving their source tokens in the lossless child stream. Bindings, assignments,
call statements and `try` statements now retain those expression subtrees too,
including tuple-binding syntax, typed bindings and the special `zero`/`undef`
initializer forms. Return statements accept multiline, trailing-comma multiple-return
lists and retain each value as an ordered expression child. Named, generic and fixed/inferred-array
aggregate literals now expose a structured `NamedType` or `ArrayType` header and
ordered `LiteralItem` children, including nested literals, named payloads, positional
values and bare PascalCase members. Local type annotations now recursively expose
named, pointer, slice, array and function-type
nodes, including array-length expressions, parameters and return specifications.
Function declarations now reuse the same trees for typed comptime parameters,
ordinary parameters and single- or multiple-type return specifications. Type
aliases, aggregate fields and union payloads now recurse through those type nodes;
enum discriminants retain expressions, and tagged types retain their backing type.
`if`/`else if`/`else`, `while` and `when` now retain condition expressions and
recursively parsed branch/body blocks. PascalCase lookahead distinguishes named
aggregate literals from block-introducing lowercase condition names. `for` now
retains iterable or bounded-range expressions and a recursively parsed body while
preserving one- or two-name iterator bindings as source tokens. `defer` owns its
structured simple statement or block, `@nocheck` owns a validated directive block,
`shared var` owns its type and optional initializer, and jump statements are exact.
`switch` now owns its subject and ordered `SwitchArm` children; arms retain multiple
case expressions, optional captures, recursive statements, and local error recovery.
Module `const`/`var` declarations now retain type and initializer trees, and failed
top-level parses transactionally discard partial nodes before recovery. Attributes
now retain ordered expression arguments, including multiline lists, and recovery
distinguishes a malformed attribute from a valid attribute on a malformed declaration.
Attribute blocks must be contiguous with their declaration, and `use` cannot carry one.
Assignment parsing now retains ordered multi-place targets, accepts multiline and
trailing-comma forms, accepts chained explicit-dereference places, and rejects
one-place pseudo-tuples, non-dereference unary or binary targets, and storage-only
`undef` values. Function types reject declaration-only named variadics.
Soft newlines are now consumed only while a grammar-approved `(`, `[`, literal body,
or type body remains open. They stay in the lossless token stream, block newlines
remain statement boundaries, and recovery restores delimiter state after an error.
Unterminated continuations stop at declaration, switch-arm, containing-block and EOF
barriers without consuming recoverable syntax or double-counting rolled-back errors.

Local fixed arrays are also underway: explicit and inferred literal lengths,
`zero`/`undef`, `.len`, element-size-aware reads and writes, mutable slice-element
assignment, array/slice `for` iteration, and bounds traps are implemented. Array
and slice range construction now covers omitted bounds and mutability propagation.
Named structs now have deterministic declaration-order layout, exact padding,
source-ordered named-field literals (including nested structs), `zero`/`undef`
storage, field places, and chained pointer auto-dereference. Address-of and explicit
dereference support mutable pointer writes, enforce pointee `const`, and permit the
one-way `*T` to `*const T` conversion.

Aggregate values now copy exactly through bindings, assignments, indexed fields,
array elements and nested literals. Arrays may contain structs or other arrays and
can be iterated by value. Internal calls pass aggregates of at most two machine
words in integer lanes, pass larger arguments by immutable hidden reference, and
return every aggregate through caller-provided storage on both x64 ABIs.
Protocol-style `for value in iterator` resolves the declaring type's
`<type>_next(*Type) -> (T, bool)`, requires a mutable iterator, and supports scalar
and aggregate yielded values. Multiple-return calls can be consumed with
`let (a, b) = call()` or assigned with `(a, b) = call()`, including `_` discards.
Integer `const` declarations are folded with checked arithmetic and can drive array
lengths in declarations, annotations, and literals.
Generic functions accept explicit or inferred `[T: type]` and `[N: usize]`
parameters, with cached concrete specializations emitted per argument set.
Generic structs use the same concrete identity and substitution rules, including
specialized field layout and literals such as `Buffer[i64, 4]{ ... }`.
The fixed `neper-0` host surface is implemented on Windows and Linux: files,
standard handles, directory enumeration, child processes, startup arguments,
virtual-memory reserve/commit, process exit, and wall/monotonic clocks. Generated
programs link a small platform runtime object, and native failures retain stable
qualified `os.*` error identities across both x64 ABIs.
Default builds now also emit the fixed debug subset on both hosts. ELF executables
carry DWARF 4 compile units, functions, parameters, locals, types, and frame-base
locations without location or range lists. COFF objects carry matching CodeView
type and symbol records; the system-linked PDB exposes parameters and locals at
stable `rbp` offsets, including materialized by-value aggregate parameters.
Explicit-backing enums, unchecked bare unions,
tagged `union enum` values, exact tag/payload layout, tag-checked payload access,
contextual and qualified member names, and non-fallthrough `switch` are implemented.
Enum and tagged-union switches require exhaustive cases unless they have `default`;
tagged cases can bind payload copies with `as`.

Lexical `defer` is also implemented in both forms. Deferred calls capture arguments
left to right when registered; deferred blocks read their referenced places at exit.
Cleanup runs in reverse order on normal block exit, `ret`, propagated `try`, `break`,
and `continue`, including once per loop iteration, while preserving return values.

On Windows with the Visual Studio C++ tools installed:

```powershell
./scripts/build-bootstrap.ps1
./scripts/build-selfhost.ps1
./build/neper.exe run ./examples/hello.e
./tests/m0/run.ps1
./tests/neper0/run.ps1
./tests/selfhost/run.ps1
```

On Linux:

```sh
./scripts/build-bootstrap.sh
./scripts/build-selfhost.sh
./build-linux/neper run ./examples/hello.e
./tests/m0/run.sh
./tests/neper0/run.sh
./tests/selfhost/run.sh
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
- [`docs/ui-framework.md`](docs/ui-framework.md) — experimental declarative GPU UI architecture
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
