<h1><img src="docs/gtm/logo/neper-lockup.svg" alt="neper" width="420"></h1>

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
symbol, unwind and compact `.nepersym`/`.nepsym` data. Large stack frames probe each
crossed page before allocation on Windows and Linux, so generated functions cannot
skip the thread's guard page. The first self-hosted compiler
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
mis-tokenized as code. Malformed quoted and raw-string tokens consume through their
matching delimiter before recovery; unterminated ordinary quotes stop before the next
physical newline. The bootstrap now loads
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
lists and retain each value as an ordered expression child. Bracket-postfix conformance
covers empty contents, indices, every open/closed range form, multi-index lists, soft
newlines and trailing commas, and rejects mixtures of ranges and argument lists.
Named, generic and fixed/inferred-array
aggregate literals now expose a structured `NamedType` or `ArrayType` header and
ordered `LiteralItem` children, including nested literals, named payloads, positional
values and bare PascalCase members. Local type annotations now recursively expose
named, pointer, slice, array and function-type
nodes, including array-length expressions, parameters and return specifications.
Function declarations now reuse the same trees for typed comptime parameters,
ordinary parameters and single- or multiple-type return specifications. Signature
conformance covers named and bare declaration variadics, bare function-
type variadics, trailing commas and empty comptime arguments; it rejects named
function-type variadics, one-item return-type lists and missing parameter commas.
Type aliases, aggregate fields and union payloads now recurse through those type nodes;
enum discriminants retain expressions, and tagged types retain their backing type.
`if`/`else if`/`else`, `while` and `when` now retain condition expressions and
recursively parsed branch/body blocks. Canonical-casing lookahead distinguishes
PascalCase aggregate literals from lowercase and SCREAMING_SNAKE values before a
block. Array literal items, including one-letter comptime values such as `N`, remain
`NameExpr`s; bare PascalCase members are recognized only in named aggregates.
Block-introducing `if`, `while`, `when`, and `switch` expressions likewise retain a
one-letter value at their outer depth while allowing aggregates in nested calls. `for`
now retains iterable or bounded-range expressions and a recursively parsed body while
preserving one- or two-name iterator bindings as source tokens; a one-letter comptime
range endpoint before the body remains a `NameExpr`. `defer` owns its
structured simple statement or block, `@nocheck` owns a validated directive block,
`shared var` owns its type and optional initializer, and jump statements are exact.
`switch` now owns its subject and ordered `SwitchArm` children; arms retain multiple
case expressions, optional captures, recursive statements, and local error recovery.
Both the colon and the final successful arm statement require their grammar-mandated
physical newline; the closing brace cannot share the statement line. An empty arm
requires a blank line so its leading and trailing separators are both explicit.
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
Top-level syntax nodes now carry an internal root marker and are gathered directly
from caller-owned node storage, removing the parser's hidden 256-declaration buffer.
Parent nodes also mark adopted children in the postorder node stream; aggregate
literals now discover direct children from that stream and no longer impose a hidden
127-item limit beyond the caller's node and child capacities. Call and bracket
arguments, generic type arguments, return-type and return-value lists, function-type
parameters, tuple-assignment places and attribute arguments now use the same
capacity-transparent path instead of embedded 32/64-entry arrays. Blocks, switch
arms and case lists, function declarations, type bodies and generic type declarations
have now migrated too; only fixed-arity productions retain correspondingly sized
local child-ID arrays. The cross-platform self-host regression parses 261 top-level
declarations and a 130-item aggregate in one source, exceeding both former limits.
The parser exposes no fixed-capacity validation shortcut: CLI and test callers pass
their node and child storage explicitly.
The self-hosted compiler now loads source paths through `src/source.e` and the fixed
`e.os` file surface. Its arena-backed buffer grows as needed, preserves all bytes
while moving between allocations, closes the file on every result path, and supplies
`scan-file` and `parse-file` CLI checkpoints without a compiler-side source-size cap.
`src/project.e` now finds the nearest ancestor containing `lib/` or `src/` and derives
canonical module names for project-root and explicitly named outside-root files,
including mixed Windows/POSIX separators and relative paths. It also selects complete
OS- or architecture-specific module files ahead of their plain fallback and rejects
a target for which both variants match.
`src/graph.e` consumes the parser's `UseDecl` nodes to load the complete reachable
module DAG. It applies `lib/`/`src/` precedence and toolchain fallback, reuses modules
imported under multiple aliases, and rejects duplicate qualifiers, duplicate roots,
missing modules, malformed reached sources and import cycles with caller-sized graph
and parser storage.
`src/resolve.e` now performs order-independent declaration collection over every
loaded module. It keeps type and qualifier/value namespaces separate, enforces
builtin reservations and duplicate rules, and resolves imported types, functions,
externs, constants, globals and errors through each module's local qualifier table.
The same pass now resolves the self-hosted compiler's own complete source graph on
Windows and Linux, including the compiler-owned `e.mem` and `e.os` bootstrap surface.
Its lexical-scope walk enforces parameter and local non-shadowing across ordinary,
tuple, loop, switch-capture and `shared var` bindings while allowing reuse after a
sibling scope ends. Applying that rule to the compiler also removed three existing
source/import or builtin collisions. The same walk now resolves every unqualified
expression and type name against its exact active scope, module declarations and
builtin types. It rejects unknown names and types, use before binding and references
after scope exit; generic type and value parameters, forward module declarations,
switch captures and implicit deferred-statement scopes are covered on both hosts.
`src/check.e` adds the first self-hosted type-checking checkpoints over caller-owned
function, parameter, token, local, recursive type, alias and constant-expression
storage. They check scalar literal context, bindings, lexical inference, exact-type
arithmetic and comparisons,
conditions, return statements and guaranteed returns through `if`, forward local and
source-module-qualified direct calls, argument arity and types, numeric casts,
mutability and explicit `void`.
Pointer, slice and fixed-array types now have structural identity; `str` canonicalizes
to `[]const u8`; mutable pointers and slices weaken to their `const` forms only; and
`nil`, `&` and `*` obey their contextual and pointee rules, including opaque `*void`.
Fixed lengths accept every integer-literal base and checked `usize` literal arithmetic.
Non-generic type aliases canonicalize recursively across modules and composites while
nominal aggregates retain their identity; direct and pointer-mediated alias cycles are
rejected. Integer constants now resolve through an order-independent, cross-module
dependency graph, infer a type only from a suffix, diagnose cycles, invalid runtime
references, division by zero and range or arithmetic overflow, and can be referenced
from bodies and every current array type position. A preliminary/final alias pass makes
local and qualified constants available inside alias right-hand sides without
declaration-order dependence. This checkpoint folds unary minus and `+`, `-`, `*`, `/`,
`%` over values whose magnitude fits the bootstrap word. Wider intermediate arithmetic,
bitwise, shift and wrapping constant operators remain outside this checkpoint. The
checker now installs the fixed `os` signatures plus `mem.mark`, `mem.reset` and
`mem.stats` without source declarations, structurally checks their pointer and slice
arguments and validates their arity. Function signatures retain every return type;
source and intrinsic result sets are checked through ordered tuple bindings and
assignments, including `_` discards, while multi-value function bodies validate each
returned expression. Statement-level `try` now consumes the trailing `err` in bindings,
assignments and error-only call statements, and verifies both the callee and enclosing
function propagation contracts. Calls with ignored results are rejected. Compiler-
owned `mem.alloc[T]` specializes its `(*mem.Arena, usize) -> ([]T, err)` signature for
primitive, local or qualified named, aliased-composite and pointer element types, then
uses the same explicit/`try` result paths. Bracket arguments now retain directly written
pointer, slice and fixed-array types as type nodes while preserving array literals as
expressions, completing the `neper-0` `mem.alloc` element forms. Generic source
functions now collect `[T: type]` and `[N: usize]` parameters, infer omitted trailing
arguments structurally, substitute through composite signatures and symbolic array
lengths, cache concrete instances, and check each instantiated body. Explicit,
inferred, partially inferred, forwarded, fallible and cross-module calls share the
ordinary result paths. Array, slice and `str` indices and slice bounds take `usize`
context; `.len`, open ranges, pointee-aware slice mutability, indexed address-of, element
assignment and explicit-dereference assignment are checked from the same place rules.
Typed `zero`/`undef` initializers share their declared context. Non-generic struct,
union, tagged-union and fixed/inferred-array literals now validate their complete field
or element sets, including nested and qualified forms. Named field access
auto-dereferences pointers; field address-of and assignment use those same place rules.
Generic aggregate types now preserve explicit type and `usize` arguments in nominal
identity, specialize symbolic array fields at concrete use sites, and flow through
generic function parameters and bodies. Recursive specialization reserves stable field
ranges for nested generic aggregates, and concrete generic aggregate aliases retain the
same nominal identity. The checker now validates enum members in contextual, local
type-qualified and imported type-qualified forms; source and fixed intrinsic error
values; integer shifts with independently unsigned counts; every compound assignment;
integer-range, array, slice and string `for` loops; and loop-scoped `break`/`continue`.
Pointer equality and enum equality/ordering use their declared operand types. Infinite
`while true` bodies without a reachable loop break satisfy non-fallthrough return
analysis. The complete self-hosted compiler, including `src/check.e` and `src/main.e`,
now passes its own checker on Windows and Linux. Deferred calls, discarded fallible
calls and block bodies enforce their no-escaping-control rule. Enum, tagged-union,
integer, `bool` and `err` switches validate constant cases, duplicates, payload
captures and exhaustiveness, and record guaranteed-return facts in caller-owned
storage. Tagged-union `.tag`, contextual tag members and local/imported
`Union.Tag.Member` values now have a distinct nominal tag type. Unsupported expression
and statement forms fail explicitly instead of being silently accepted; cross-platform
fixtures freeze both the implemented behavior and those temporary boundaries. The
bootstrap emitter also selects unsigned x64
division, remainder and relational instructions from operand types, including values
above `isize`'s maximum.

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
Integer `const` declarations are folded with checked arithmetic, bitwise operators,
typed shifts and width-preserving wrapping arithmetic. The same evaluator semantics
drive array lengths and concrete generic function and aggregate bounds.
Generic functions accept explicit or inferred `[T: type]` and `[N: usize]`
parameters, with cached concrete specializations emitted per argument set. Their
declarations are checked immediately for parameter-independent rules; operations
whose validity depends on a comptime argument are checked again after specialization.
Generic structs use the same concrete identity and substitution rules, including
specialized field layout and literals such as `Buffer[i64, 4]{ ... }`.
The fixed `neper-0` host surface is implemented on Windows and Linux: files,
standard handles, directory enumeration, child processes, startup arguments,
virtual-memory reserve/commit, process exit, and wall/monotonic clocks. Generated
programs link a small platform runtime object, and native failures retain stable
qualified `os.*` error identities across both x64 ABIs.
The first arena increment gives `mem.Arena` its frozen 24-byte value layout and
field places, then supplies compiler-owned `mem.arena_from` and generic
`mem.alloc[T]` bootstrap intrinsics. Concrete allocation calls pass the compiler's
element size and alignment to one runtime entry point; zero-count requests preserve
the cursor, capacity and multiplication failures preserve it and return
`mem.Exhausted`, and compound type arguments have distinct specialization keys.
`mem.mark`, source-located bounds-checked `mem.reset`, and allocation-free
`mem.stats` complete the arena cursor-management subset.
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

The self-hosted front end now accepts and rejects the same complete 51-file
`tests/neper0` corpus as the bootstrap on Windows and Linux. The shared gate covers
contextual ranges and zero values, enum discriminants and zeroability, aggregate
value-layout cycles, nested aggregate literals, the fixed arena/OS surface and
compiler-generated iterator protocol lookup. Every rejected fixture also emits the
same ordered versioned diagnostics from exact source-token spans on both hosts. The
self-hosted NIR and code-generation rewrite is next.

On Windows with the Visual Studio C++ tools installed:

```powershell
./scripts/build-bootstrap.ps1
./scripts/build-selfhost.ps1
./build/windows/neper.exe run ./examples/hello.e
./tests/m0/run.ps1
./tests/neper0/run.ps1
./tests/selfhost/run.ps1
```

On Linux:

```sh
./scripts/build-bootstrap.sh
./scripts/build-selfhost.sh
./build/linux/neper run ./examples/hello.e
./tests/m0/run.sh
./tests/neper0/run.sh
./tests/selfhost/run.sh
```

- [`docs/spec.md`](docs/spec.md) — the language specification
- [`docs/grammar.ebnf`](docs/grammar.ebnf) — normative concrete grammar and token registry
- [`docs/tooling.md`](docs/tooling.md) — normative version-1 harness, JSONL, span and formatter contracts
- [`docs/tooling-v2-draft.md`](docs/tooling-v2-draft.md) — scheduled, non-normative agent-tooling successor design
- [`docs/diagnostics.md`](docs/diagnostics.md) — stable diagnostic-code registry
- [`docs/roadmap.md`](docs/roadmap.md) — implementation milestones
- [`docs/work-queue.json`](docs/work-queue.json) — ordered unfinished compiler/tooling capabilities; the first item is the serial-session target
- [`docs/work-done.jsonl`](docs/work-done.jsonl) — completed compiler/tooling capability ledger consumed by the progress renderer
- [`docs/post-m2-llm-hardening.md`](docs/post-m2-llm-hardening.md) — post-M2 requirements split into the pre-M3 core gate, T2 tooling and E2 claim evaluation
- [`docs/hardening-tracks.json`](docs/hardening-tracks.json) — authoritative machine-readable ownership and status for those tracks
- [`docs/llm-hardening-recommendations.md`](docs/llm-hardening-recommendations.md) — prioritized R01–R16 recommendations for a language optimized for LLM processing end-to-end
- [`docs/llm-agent-compiler-toolchain-research.md`](docs/llm-agent-compiler-toolchain-research.md) — compiler/toolchain landscape and the evidence behind H30–H34's agent-experience requirements
- [`docs/decisions.md`](docs/decisions.md) — settled architecture decisions and their reasoning
- [`docs/modules.md`](docs/modules.md) — the standard library and package plan
- [`docs/module-apis.md`](docs/module-apis.md) — exact proposed APIs for toolchain modules
- [`docs/stdlib-hardening.md`](docs/stdlib-hardening.md) — adopted library composition, naming, cancellation, JSON, process/filesystem and stable image/codec contracts
- [`docs/modules.json`](docs/modules.json) — machine-readable module catalogue
- [`docs/general-purpose-verification.md`](docs/general-purpose-verification.md) — workload and LLM-generation acceptance plan
- [`docs/ui-framework.md`](docs/ui-framework.md) — experimental declarative GPU UI architecture
- [`docs/widget-library-proposal.md`](docs/widget-library-proposal.md) — desktop/mobile component catalogue and delivery design
- [`docs/widget-plan.json`](docs/widget-plan.json) — machine-readable widget phase, pickup and evidence inventory
- [`docs/pacman.md`](docs/pacman.md) — the M6 package manager architecture
- [`examples/sample.e`](examples/sample.e) — every construct in the language, once, in one program
- [`examples/`](examples/) — what the language is meant to look like

Those documents also render into one bookmarked PDF with a linked table of
contents and a source manifest. It is generated on demand rather than tracked:

```powershell
./scripts/build-docs-pdf.ps1
```

```bash
./scripts/build-docs-pdf.sh
```

Both wrappers provision a local virtual environment from pinned requirements and
write `docs/neper.pdf`.

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
