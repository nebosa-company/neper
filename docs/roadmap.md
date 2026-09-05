# neper — roadmap

Sequenced so that each implementation milestone produces something runnable, the
bootstrap compiler is discarded as early as possible, and no implementation starts
against a moving language or harness contract.

**The labels name deliverables, not a simple numeric order.** The order is: S0, M0,
`neper-0`, the M2 rewrite of the compiler in `neper-0`, M1 implemented inside that
self-hosted compiler, the rest of M2 (`.em`, the pool and the own linker), M3 and M4.
M5 follows M4. Pacman P0/P1 may proceed after M2; P2/P3 and M6 completion follow M4
independently of M5. The later library waves remain deliberately unnumbered. M1 and
M2 overlap by design; every other dependency is stated at its milestone.

The normative documents divide authority rather than duplicate it: [`spec.md`](spec.md)
defines language semantics, [`grammar.ebnf`](grammar.ebnf) defines concrete syntax
and the closed token/syntax-node registries, [`tooling.md`](tooling.md) and
[`schemas/neper-v1.schema.json`](schemas/neper-v1.schema.json) define machine
interfaces, [`diagnostics.md`](diagnostics.md) owns stable diagnostic codes,
[`modules.json`](modules.json) owns the module/package plan, and
[`module-apis.md`](module-apis.md) fixes proposed toolchain APIs. The prose grouping
in [`modules.md`](modules.md) explains that machine plan. A change that crosses these
boundaries updates every affected document and fixture in the same change.

The product commitment follows `modules.json`'s ordered delivery tiers. `core` gates
the first stable CPU release. `extended` modules are stable only once independently
delivered and do not delay that release. `experimental` APIs carry no compatibility
promise. Dependency layers remain an orthogonal implementation constraint.

## S0 — Specification, API and harness freeze

This is documentation and test-data work only. It precedes compiler implementation
and turns the current design into an executable contract for humans, harnesses and
models.

- Resolve every contradiction among the language specification, grammar, tooling
  protocol, diagnostic registry, module plan, API catalogue, package-manager design
  and general-purpose verification plan. Record intentional tradeoffs in
  [`DECISIONS.md`](../DECISIONS.md); do not leave behavior to an implementation
  choice.
- Validate `grammar.ebnf` mechanically and give every grammar production an accepted
  fixture and every stated restriction a rejected fixture with a registered primary
  diagnostic. Establish the normative `tests/conformance/{accept,reject,format,
  tokens,parse,tools}/` layout and version every expected result.
- Validate every tooling record and document against
  `schemas/neper-v1.schema.json`. Add sequence, key-order, sorting, lossless-source,
  recovery and cross-record tests for constraints JSON Schema cannot express.
- Freeze the one-heading/one-`neper`-fence API-extraction contract for all 107
  toolchain modules. Check that `modules.json`, `modules.md` and `module-apis.md`
  contain the same names; that tiers are ordered, exhaustive and disjoint; that
  layers, direct dependencies, blockers, surfaces, schedules and milestones are
  valid; and that the graph is acyclic. Keep the 6
  `x.<owner>.*` entries classified as package reservations, never implicit modules.
- Design GP-01 through GP-14 before implementation: contracts, expected module
  graphs, failure injection, portability targets, resource budgets, deterministic
  artifacts and comparison implementations. A workload may expose a specification
  gap; it may not silently define new language behavior.
- Freeze the generated-code benchmark corpus and prompts. Record model, model
  version, tokenizer, compiler/formatter/schema versions, first-pass parse/type-check/
  test rates, repair turns, model tokens, tokens per non-comment line and syntax
  node, unrelated formatted diff, hallucinated features/APIs, name/import collisions
  and cleanup/lifetime/race defects. Include equivalent C, C++, Rust, Go, Python,
  Java and C# tasks; never infer token efficiency from spelling length.
- Make documentation checks runnable as a single read-only validation command whose
  output is deterministic and suitable for CI and agent harnesses.

**Done when:** all normative documents and schemas validate; every registry and
cross-document reference is closed and consistent; every proposed module API is
mechanically extractable; the complete conformance and benchmark fixture manifests
exist; the GP workloads have reviewable designs; and no unresolved item can change
the grammar, semantics, diagnostic identity, machine protocol or public API beneath
M0. Later specification changes remain possible, but require an explicit version or
compatibility decision and updated fixtures.

## M0 — Bootstrap compiler, walking skeleton

Throwaway C99. Enough language to print "hello, neper".

**Implemented (2026-09-04).** `bootstrap/neper.c` and `scripts/build-bootstrap.*`
produce the native bootstrap on Windows and Linux. `tests/m0/run.*` exercise the
cross-directory program root, both x64 argument paths, UTF-8 startup arguments,
control flow, calls across register and stack arguments, slices, named-error
propagation, deterministic rejection diagnostics, traps, and retained debug and
compact-symbol metadata. M0 is complete and the incremental `neper-0` extension,
including the first self-hosted compiler modules, is in progress.

- Lexer and parser generated or checked against grammar revision 1, including exact
  original-byte/scalar/UTF-16 position tracking, normalized line handling, the closed
  token registry and recovery barriers. The bootstrap need not expose `tokens` or
  `parse`, but it must not create a second concrete language
- Order-independent module resolution and type checking, with registered diagnostic
  codes and deterministic source ordering from the first rejected fixture
- NIR (typed SSA-lite IR), linear-scan register allocator
- x64 emitter, System V + Windows x64 ABIs
- Emit object files, link with the system linker
- Line tables, symbol tables and unwind info — enough for `lldb` breakpoints,
  stepping and stack traces, and enough for profilers to symbolise. The incremental
  `neper-0` implementation below now adds the specified locals-and-types subset
  (spec §13, D9)
- Subset: `fn`, `let`/`var`, integers, `if`/`while`, calls, structs by value, `use`,
  `err`/`try`/`ok`, pointer types and `[]T` slices over any element with `.len` and
  indexing (string literals as `[]const u8`; `main`'s `*mem.Arena` and `[]str`), and
  an `e.mem` stub declaring `Arena` and `arena_from` — exactly what `hello.e`
  needs and no more
- `io.print` and the startup code over a fixed bootstrap intrinsic set — `os.write`,
  `os.stdout`, `os.stderr`, `os.exit`, `os.reserve`, `os.commit`, `os.args`; the
  general `extern` form and
  `e.os` land in M1
- The `main` entry signature (spec §13, D34): startup code that reserves the root
  arena, builds `args`, calls `main`, and maps its `err` to the exit code and the
  `error: <name>` line; the trap protocol's stderr record and exit code `134`
  (spec §11) — the backtrace reads the `.nepersym` line-and-symbol section
  (`.nepsym` on COFF/PE) the
  compiler emits into every object file (spec §13), which the system linker carries
  into the executable unchanged
- Program roots (spec §2, D41): `neper run <file.e>` names a file declaring `fn
  main`; a file outside every source root is module `<filename>`, so
  `examples/hello.e` is module `hello` with no package around it, and `e.*` is
  found in the toolchain's own `lib/` beside the binary

**Done when:** `neper run examples/hello.e` works on Windows and Linux, from any
working directory; and the bootstrap passes the applicable S0 lexical, syntactic,
module, type and trap fixtures with the expected primary codes and source spans.

## neper-0 — the bootstrap subset

The throwaway C99 compiler (D4) implements exactly this subset and nothing beyond
it, and the self-hosted compiler is written in it. `neper-0` is the language a
compiler needs — `list.e` is `neper-0` code — and no more.

**In progress (started 2026-09-04).** The first executable increment implements
typed integer range `for`, `break`, `continue`, integer local `+=`, and lexical block
scopes in the C99 bootstrap. `tests/neper0/run.*` cover signed ascending and empty
ranges, early loop exits, sibling-scope name reuse, out-of-scope rejection, and invalid loop control on
Windows and Linux. A second increment implements local fixed arrays with explicit or
inferred literal lengths, `zero`/`undef` initialization, `.len`, element-size-aware
reads and writes, mutable slice-element assignment, and bounds traps. The same suite
covers adjacent narrow elements, signed loads, checked mutation, immutability, count
mismatches, bounds failures, and non-overlapping slice/local frame slots. A third
increment adds one-binding and index/value `for` iteration over arrays and slices,
with iteration values held as immutable copies. A fourth increment adds checked
`[lo..hi]`, `[lo..]`, and `[..hi]` slicing with array-to-slice mutability propagation.
The aggregate-foundation increment adds named struct declarations, deterministic
natural layout and padding, source-ordered named-field literals including nested
structs, `zero`/`undef` storage, field places, pointer-recursive layouts, chained
pointer auto-dereference, `&`/`*`, mutation through `*T`, rejection through
`*const T`, and the one-way mutable-to-const pointer conversion. A subsequent
aggregate-value increment adds exact struct and array copies through bindings,
assignments, nested literals, indexed places and by-value iteration; arrays may nest
or hold structs; aggregates of at most two words use integer argument lanes, larger
arguments use immutable hidden references, and aggregate returns use caller-owned
slots on both x64 ABIs. The enum-and-variant increment adds explicit integer-backed
enums with implicit or explicit checked values, bare-union shared storage, tagged
`union enum` layout and literals, implicit `.tag` enums, debug tag checks on payload
access, payload-copy `as` bindings, scalar cases and exhaustive non-fallthrough
`switch`. It also enforces duplicate cases, `default`, enum zeroability, branch
scopes, and `break`/`continue` targeting on both x64 ABIs. The cleanup increment adds
both forms of lexical `defer`, immediate left-to-right
argument capture for deferred calls, place capture for deferred blocks, reverse-order
cleanup on normal and structured exits, per-iteration cleanup, deliberate discarded
fallible calls, and return-value preservation. The iterator increment adds the
compiler-generated `<type>_next(*Type) -> (T, bool)` lookup used by `for value in
iterator`, requires a mutable variable or mutable pointer subject, and implements
the two-result x64 ABI needed for scalar and aggregate yields. Direct source-level
destructuring now supports `let`/`var` bindings, `_` discards, and assignment to
mutable locals for register- and caller-slot-returned result sets. The constant
increment adds order-independent integer `const` declarations, dependency-cycle and
overflow diagnostics, runtime constant references, and integer folding for array
lengths. Generic functions now specialize `[T: type]` and `[N: usize]` parameters
from explicit arguments or structural value-argument inference, cache duplicate
instances, and substitute parameters through signatures, bodies, and array layouts.
Generic aggregate types now share that canonical specialization cache, substitute
field types and array lengths, compute concrete layouts, and support specialized
aggregate literals. The fixed bootstrap host increment adds the complete
`os.open`/`read`/`write`/`close`, standard-handle, directory, process,
argument, virtual-memory and clock surface through a small C99 runtime object.
Intrinsic signatures are compiler-owned, fallible calls use one deterministic
caller-owned result layout on both x64 ABIs, host failures map to stable qualified
`os.*` errors, and the Windows/Linux suite exercises success, failure and process
exit paths. The first memory increment gives `mem.Arena` its specified 24-byte value
layout and field places, and adds compiler-owned `mem.arena_from` and generic
`mem.alloc[T]` bootstrap intrinsics. Allocation lowers every concrete element type
to one runtime entry point with hidden size/alignment constants; zero-count,
alignment, capacity, multiplication-overflow, cursor-stability and qualified
`mem.Exhausted` behavior are covered on both x64 ABIs. Compound type arguments use
structural specialization keys rather than colliding with their element types. The
next memory increment adds `mem.mark`, source-located bounds-checked `mem.reset`,
and allocation-free `mem.stats`; the suite verifies scoped rewind, alignment after a
rewind, stable capacity reporting and the reset trap protocol on both hosts. The
debug-info increment adds DWARF 4 DIEs on ELF and CodeView type and
symbol records on COFF for functions, parameters, named locals, primitives,
structures, bare and tagged unions, enums, pointers with pointee constness, slices,
arenas, and arrays. Every source local has one stable frame slot and one `rbp`-based
location for the full function; larger by-value parameters are copied out of their
ABI-indirect input into those slots. Linux validation rejects malformed DIEs and
location/range-list sections; Windows validation parses the COFF record streams,
and DIA verification confirms the linked PDB reconstructs locals and recursive
types. Generated functions whose local frame reaches one page now call a freestanding
page probe before allocation on Windows and Linux, retaining Windows unwind metadata
without adding a C-runtime dependency; both M0 suites execute a 16 KiB-frame
regression and inspect the emitted probe call. The first self-hosted compiler
checkpoint is built by the bootstrap on
Windows and Linux. Its grammar revision 1 lexer now lives in `src/lex.e`;
`src/main.e` imports and exercises that module. The lexer owns all 94 token kinds and
scans keywords, comments, CR/LF/CRLF, original-byte spans, strict numeric and quoted/raw
literal boundaries, invalid bytes and the complete longest-match punctuation set.
Numeric lexing validates base digits, separator placement, exponents, and the closed
integer/float suffix sets. Strings, raw strings and comments validate UTF-8 scalars
and their context-specific control bytes; character literals decode to exactly one
byte. Tokens carry half-open original-byte endpoints and normalized one-based
start/end lines with both scalar and UTF-16 columns, including BOM, CRLF, BMP and
astral-scalar fixtures. Invalid UTF-8 recovery consumes Unicode maximal subparts as
one position unit; valid non-ASCII scalars in ASCII-only token positions remain one
`Invalid` token rather than fragmenting by encoded byte. Every token owns its exact
leading byte range, including the BOM and trailing trivia on EOF, so the stream
partitions the original source without gaps. That range is now enumerable as exact-
span BOM, maximal space-run and whole-comment trivia with scalar and UTF-16 columns.
Comment recovery survives an invalid-byte token and keeps the rest of that physical
line in comment trivia rather than reinterpreting it as code. Malformed quoted and
raw-string tokens consume through their matching delimiter before recovery, while an
unterminated ordinary quote stops before the next physical newline.
The C99 bootstrap now loads transitive modules from the nearest project's `lib/` and
`src/`, resolves default and explicit import qualifiers, canonicalizes cross-module
functions, types, constants and errors, rejects duplicate qualifiers and import
cycles, and attributes diagnostics to their source file. `tests/selfhost/run.*`
covers that module boundary, including a nested aliased module and an invalid
imported module, on Windows and Linux. The parser foundation now lives in
`src/parse.e` alongside the exact 54-kind grammar revision 1 registry in
`src/syntax.e`. It owns the reusable token cursor and writes into caller-supplied
node and child slices rather than embedding a fixed buffer in every tree. Top-level
declarations and attributes own their exact token children; the `File` root
interleaves those nodes with original separator and EOF tokens. Ranges are exclusive,
delimiter errors produce `ErrorNode`s, and recovery resumes at top-level newline
barriers. The first self-hosted `parse` command uses that lossless ordering and tests
bounded-capacity failure. Function declarations now parse compile-time parameters,
ordinary and variadic parameters, return specifications and their body into nested
nodes; a malformed signature recovers at the next top-level newline barrier. Type
declarations now parse generic parameters, aliases, struct and bare-union fields,
enum members and tagged-union members into the corresponding frozen node kinds;
empty enum bodies recover to the following declaration. Function blocks now own
classified binding, assignment, call, `try`, `defer`, control-flow, return,
`@nocheck` and `shared var` statement nodes. A malformed statement becomes a nested
`ErrorNode`, resumes at the next block newline and preserves both its enclosing
`Block`/`FnDecl` and following statements. Every statement now uses its grammar
production; the legacy raw token-balancing fallback has been removed. Return values
now produce primary, prefix, precedence-aware binary, call, field and bracket-postfix
expression nodes,
including grouped and member-shorthand primaries. Binding and assignment statements
now retain their binding/target and initializer subtrees; call and `try` statements
retain their call trees; `zero` and `undef` remain lossless initializer tokens; and
failed statement parses roll back partial nodes before inserting an `ErrorNode`.
Return statements now retain every value in a multiline or trailing-comma
multiple-return list while preserving ordinary single-expression grouping. Bracket-
postfix conformance now covers empty contents, indices, every open/closed range form,
multi-index lists, soft newlines and trailing commas, and rejects mixtures of ranges
and argument lists.
Named, generic and fixed/inferred-array aggregate literals now retain a structured
`NamedType` or `ArrayType` header and ordered `LiteralItem` children, including nested
literals, named payloads, positional values and bare PascalCase members. Local type
annotations now recursively retain named, pointer, slice, array and function-type nodes, including
array-length expressions, parameters and return specifications. Function
declarations now reuse the same trees for typed comptime parameters, ordinary
parameters and single- or multiple-type returns. Signature conformance covers named
and bare declaration variadics, bare function-
type variadics, trailing commas and empty comptime arguments; it rejects named
function-type variadics, one-item return-type lists and missing parameter commas.
Type aliases, aggregate fields and union payloads now recurse through those nodes;
enum discriminants retain expression
nodes; and enums and tagged unions retain their backing type. `if`/`else if`/`else`,
`while` and `when` now retain condition expressions and recursively parsed blocks;
canonical-casing lookahead disambiguates PascalCase aggregate literals from lowercase
and SCREAMING_SNAKE values followed by a block. Array literal items, including
one-letter comptime values such as `N`, remain `NameExpr`s; bare PascalCase members
are recognized only in named aggregates. Block-introducing `if`, `while`, `when`, and
`switch` expressions retain one-letter values at their outer depth while allowing
aggregates in nested calls. `for` now retains iterable or bounded-range expressions
and a recursively parsed body while preserving one- or two-name iterator bindings
as source tokens; a one-letter comptime range endpoint before the body remains a
`NameExpr`. `defer` now owns its structured simple statement or recursive
block, `@nocheck` owns a validated directive block, `shared var` owns its type and
optional initializer, and `break`/`continue` reject trailing syntax. `switch` now
owns its subject and ordered `SwitchArm` children; arms retain multiple case
expressions, optional captures, recursive statements and local error recovery.
Both the colon and the final successful arm statement require their grammar-mandated
physical newline; the closing brace cannot share the statement line. An empty arm
requires a blank line so its leading and trailing separators are both explicit.
Module `const`/`var` declarations now retain type and initializer trees, including
the special variable initializer forms, and failed top-level parses transactionally
discard partial nodes before recovery. Attributes now retain ordered expression
arguments, including multiline lists, and recovery distinguishes a malformed
attribute from a valid attribute on a malformed declaration. Attribute blocks now
reject blank or comment-only gaps and cannot attach to `use`. Assignment parsing
retains ordered multi-place targets, accepts multiline and trailing-comma forms plus
chained explicit-dereference places, and rejects one-place pseudo-tuples,
non-dereference unary or binary targets and storage-only `undef` values. Function
types reject declaration-only named variadics. Soft newlines are now
consumed only inside grammar-approved parentheses, brackets, literal bodies and type
bodies; the lossless token stream retains them, block newlines stay hard, and parser
recovery restores delimiter state after malformed nested syntax. Unterminated
continuations now stop at declaration, switch-arm, containing-block and EOF recovery
barriers; transactional rollback restores both syntax storage and error counts.
Top-level nodes carry an internal root marker and are gathered from caller-owned node
storage, so declaration count is no longer capped by an embedded 256-entry array. The
postorder node stream now records parent adoption as well. Aggregate literals gather
their direct children from that stream, removing their embedded 127-item ceiling in
favor of the caller's explicit node and child capacities. Call/bracket arguments,
generic type arguments, return-type/value lists, function-type parameters, tuple
assignments and attributes now use the same capacity-transparent path rather than
embedded 32/64-entry child-ID arrays. Blocks, switch arms/cases, function signatures,
type bodies and generic type declarations now use it as well. Every unbounded grammar
list is therefore limited only by explicit caller node/child capacity; the remaining
local child-ID arrays correspond to fixed-arity productions. The Windows and Linux
self-host suites parse 261 top-level declarations and a 130-item aggregate in one
source, crossing both former hidden limits. The parser's former 16-node/64-child
validation shortcut is removed; CLI and test callers now declare their storage
budgets explicitly. The
remaining grammar productions and their conformance coverage are the next
parser-front-end increments; this callout does not mark the `neper-0` milestone complete.
The first arena-backed source loader now lives in `src/source.e`. The self-hosted CLI
uses the fixed `e.os` file surface to grow a byte buffer through `mem.alloc[u8]`,
preserve exact source bytes across growth, close every opened file, and drive
`scan-file`/`parse-file`; cross-platform tests scan the compiler's own source, parse a
loaded fixture and verify stable missing-file propagation. This is a source-loading
checkpoint. The next discovery increment adds `src/project.e`: it finds the nearest
ancestor containing `lib/` or `src/`, handles relative, POSIX and Windows path roots,
and derives canonical dotted names for files below either source root while retaining
the bare-name rule for an explicitly named file outside them. It now selects a matching
OS or architecture variant ahead of the plain module, rejects simultaneous matches and
handles nested module paths. `src/graph.e` completes the discovery pipeline by reading
the parser's `UseDecl` nodes, loading every reachable module with project-root
precedence and toolchain fallback, and rejecting missing or multiply rooted modules,
duplicate local qualifiers, malformed reached sources and import cycles. The first
semantic pass in `src/resolve.e` collects every module-scope type and value declaration
before resolving references, keeps the type and qualifier/value namespaces separate,
enforces builtin-name and duplicate rules, and validates qualified type and value
members through local import aliases. It resolves the self-hosted compiler's own
reachable source graph on both hosts, with the fixed compiler-owned `e.mem`/`e.os`
names seeded explicitly rather than invented as source declarations. Its lexical
scope pass now covers parameters, ordinary and tuple bindings, loop bindings, switch
captures and `shared var`; active or module-level shadowing is rejected while names
may be reused in disjoint sibling scopes. Running that pass over the compiler removed
three pre-existing collisions. The same scope-aware pass now resolves unqualified
expression and type names, including forward module declarations, generic type and
value parameters, binding initializers, loop bodies, switch cases and captures,
top-level initializers and implicit deferred-statement scopes. It rejects unknown
names and types, use before binding and references after a lexical scope ends on both
hosts. The first `src/check.e` increments now build caller-owned function, parameter,
token, local and recursive type tables and check scalar literal context, bindings,
lexical inference, exact-type arithmetic and comparisons, conditions, return
statements and guaranteed returns through `if`, forward local and source-module-
qualified direct calls, argument arity and types, numeric casts, mutability and
explicit `void`. Pointer, slice and
fixed-array types now compare structurally, including nested forms and zero-length
arrays; `str` is canonical with `[]const u8`; mutable pointer/slice weakening is
one-way; contextual `nil` covers pointers and slices; and address-of/dereference
enforce binding and pointee mutability while rejecting `*void` dereference. Array
lengths accept all integer-literal bases and checked `usize` literal arithmetic with
overflow and division-by-zero rejection. The bootstrap's x64 emitter now uses
unsigned division, remainder and relational instructions for unsigned operand types,
including the full `usize` range. Qualified calls into loaded source modules now use
the target function's collected signature for arity, argument and return checking.
Non-generic aliases now canonicalize recursively through imported names, pointers,
slices and arrays while nominal aggregates retain identity; every alias cycle is
rejected even when it passes through pointer indirection. Integer constants now use
an order-independent dependency graph across loaded modules. Suffixed initialisers may
infer the constant type; forward and qualified references, cycles, invalid runtime-state
references, division by zero, type mismatches and checked range or bootstrap-word
arithmetic overflow are covered. Evaluated constants type-check in function bodies and
drive array lengths in function, local and alias type positions; a preliminary/final
alias pass makes local and qualified constants available to aliases independent of
declaration order. Unary minus and `+`, `-`, `*`, `/`, `%` are the current folding
subset. The checker now installs all fixed `os` signatures plus `mem.mark`, `mem.reset`
and `mem.stats` as compiler-owned declarations, then checks their arity and structural
pointer/slice arguments. Signatures retain complete ordered return lists; source and
intrinsic result sets are consumed through tuple bindings or assignments with `_`
discards, and multi-value function bodies check every returned expression. Statement-
level `try` consumes a trailing `err` in a whole binding initializer, assignment RHS or
error-only call statement, while enforcing fallible caller/callee signatures. Returned
values cannot be silently ignored. Compiler-owned `mem.alloc[T]` now specializes its
arena/count arguments and `([]T, err)` results for primitive, local or qualified named,
aliased-composite and pointer `T`. Bracket arguments retain directly written pointer,
slice and fixed-array types as type nodes without misclassifying array-literal arguments,
covering every `neper-0` allocation element form. Generic source functions now collect
`[T: type]` and `[N: usize]` parameters, bind explicit or structurally inferred trailing
arguments, substitute composite signatures and symbolic array lengths, cache concrete
instances, and check each instantiated body, including forwarded, fallible and qualified
calls. Array, slice and `str` indices and slice bounds take `usize` context; `.len`, open
ranges, pointee-aware slice mutability, indexed address-of, element assignment and
explicit-dereference assignment use the same place rules. Typed `zero`/`undef`
initializers inherit their declared context. Non-generic struct, union, tagged-union
and fixed/inferred-array literals now validate complete field or element sets, including
nested and qualified forms. Named field access auto-dereferences pointers; field
address-of and assignment share the same pointee-aware place mutability rules. Generic
aggregate types preserve explicit type and `usize` arguments in nominal identity,
specialize symbolic array fields at concrete use sites, and flow through generic
function parameters and instantiated bodies. Recursive specialization reserves stable
field ranges for nested generic aggregates, and concrete aliases preserve their nominal
instance identity. Enum declarations and contextual, local type-qualified or imported
type-qualified members now check nominally; source and fixed intrinsic error values are
typed as `err`. Integer shifts require an independently unsigned count, every compound
assignment checks its place and operator family, and integer-range, array, slice and
string `for` loops install scoped index/value bindings with loop-valid
`break`/`continue`. Pointer equality and enum equality/ordering are checked, and an
unbroken `while true` is non-fallthrough for guaranteed-return analysis. The entire
self-hosted compiler, including `src/check.e` and `src/main.e`, now passes this checker
on Windows and Linux. Wider intermediate constant arithmetic, bitwise and shift
constant expressions, wrapping constant operators, tagged-union tag checks remain outside the
`check-file` checkpoint. Unsupported expression and statement
forms fail explicitly rather than being accepted unchecked. The next type-checking
increments replace those boundaries with remaining control flow and declaration-time
generic checks.

- Everything in M0
- Slices, arrays, `union` and `union enum`, `enum`, `defer`, `switch` (exhaustive),
  `for`
- `err`/`try`/`ok`, arenas (`e.mem`), `let`/`var` with `= zero`/`= undef`
- `[T: type]` and `[N: usize]` comptime parameters with monomorphisation. The
  interpreter does **integer constant folding only**: `const N: usize = 4096` and
  `[N*2]u8` evaluate (an array length is `usize`, spec §3); a function call in a
  `const` does not
- The debug-mode checks of spec §11 and the trap protocol
- Line tables, symbols, unwind info, and the fixed DWARF/CodeView
  locals-and-types subset (spec §13) — hundreds of lines, and it means the
  self-hosted compiler can be debugged with locals while the bootstrap still builds
  it
- A **fixed intrinsic set** standing in for `extern` and `e.os`: `os.open`,
  `os.read`, `os.write`, `os.close`, `os.stdout`, `os.stderr`, `os.readdir`,
  `os.spawn`, `os.wait`, `os.exit`, `os.args`, `os.reserve`, `os.commit`,
  `os.clock` — what a
  single-threaded compiler needs to read sources, write `.em` files and objects,
  spawn `--linker=system` and time itself

Not in `neper-0`, and therefore not written in C: argument packs and
`printf`/`format` (the self-hosted compiler formats its diagnostics with
`str.push_*`), the general compile-time interpreter, threads and atomics, function
  pointers and the `K: fn` comptime kind, `@test` and `neper test`, `neper fmt`,
  `neper tokens`, `neper parse`, `neper index` and `neper info`, general `extern`
and `e.os`, `Vec[T, N]`/`simd`, `when`/`target`, `@gpu`, generic protocol dispatch
and `e.meta` (the compiler-generated iterator `next` lookup is the sole protocol
exception; the bootstrap's own containers are otherwise written per element type,
by hand). Each is implemented
once, in the self-hosted compiler, after it compiles itself.

**Size, recorded against D4.** `neper-0` in C99 is roughly 15k lines: lexer 1k,
parser 2.5k, resolve and typecheck 3.5k, NIR and monomorphisation 2.5k, linear-scan
allocator 1.5k, x64 emitter 2.5k, ELF/COFF object writer with the debug subset
1.5k. The full M1 language in C would be some 35k — the interpreter, packs, threads,
the test runner, `fmt`, `index`, the `extern` ABI, `simd` and `e.os` on top —
and every line of it thrown away. The subset halves what is written twice.

**Done when:** the language can express a compiler — containers over arenas,
interning, hash maps — with no heap, and the bootstrap compiles the self-hosted
compiler's source; the bootstrap and self-hosted front ends accept and reject the
same `neper-0` corpus and emit the same versioned diagnostics and recovery spans.
M2 gates on this.

## M1 — The full CPU language

Everything in the spec that is not GPU-specific. The bootstrap stops at `neper-0`
(above); every item below that `neper-0` lacks is implemented in the self-hosted
compiler, so M1 completes after M2's rewrite compiles itself, not before.

- Slices, arrays, unions (untagged and `union enum`), enums, `defer`, `switch`
  (exhaustive over enums and tagged unions), `for` — no tuples: `(A, B)` is a return
  convention only (spec §5, D17)
- `err` + `try`, arenas, compile-time parameters in `[...]` and monomorphisation
- Compile-time interpreter for `const` and `[...]` arguments
- The full debug-mode check table of spec §11 — bounds, null, tag, overflow,
  narrow, shift, enum, align — the trap protocol, `unreachable()`, and the arena
  fills
- `Vec[T, N]`, `Mask[T, N]` and the `simd` module (spec §4, D40): the closed width
  table, register-class passing, and lowering at every `--cpu` level including the
  split below the vector's width
- Debug info on the default path (spec §13, D9, D64): the fixed DWARF (ELF/Mach-O)
  and CodeView (PE) locals-and-types subset with `DW_OP_fbreg` locations, so
  `lldb`, `gdb`, WinDbg, `lldb-dap` and `codelldb` show locals from here — VS Code
  and Zed debugging with zero adapters of our own. Debug builds do not inline;
  `--g` adds the subset and `inlined_subroutine` records to a release build
- The finite-command JSONL contract for `build`, `check`, `run`, `test`, `fmt`,
  `tokens`, `parse`, `index`, `dis` and `info`: one version header, advertised
  `language_profiles`, closed record discriminators, diagnostics in-stream, one final
  result and no human text on stdout. Validate every record with the v1 schema and
  every non-schema ordering rule with the S0 tooling corpus (D65)
- Lossless `tokens`/`parse` output over grammar revision 1's closed 94-token and
  54-syntax-node registries in `grammar.ebnf`: trivia, BOM, physical newline
  spelling, invalid-byte capture,
  `ErrorNode` recovery and reconstruction of every original byte. Spans retain
  original byte offsets plus normalized one-based scalar and UTF-16 columns
- Complete deterministic `index` output for every specified symbol and reference,
  including unresolved references and compiler-origin protocol, iterator and
  formatting calls. Stable diagnostic codes come only from `diagnostics.md`; fixes
  carry non-overlapping original-byte edits and expected-source hashes
- `neper fmt` implements the complete canonical-layout contract: LF/UTF-8 output,
  four-space indentation, deterministic 100-scalar wrapping, preserved comments and
  literal spelling, sorted eligible `use` declarations, exact failure behavior,
  idempotence and golden output
- `@test` discovery uses one child process and fresh arena per test, parallel
  scheduling with deterministic report order, capture, the 60-second timeout and
  structured outcomes. `run --json` captures arbitrary child bytes without corrupting
  JSONL; every duration is the sole normalized volatile field in golden comparisons
- Every build writes the canonical v1 build manifest with language/grammar versions,
  normalized source identities, SHA-256 inputs/dependencies/libraries/artifacts and
  effective options. Generated-source maps use exact tooling spans and hashes; stale
  or malformed maps fail with `E-TOOL-0001` and never change compilation semantics
- `extern` declarations with `@import`/`@cc` (spec §5, D32): the C ABI for every
  crossing type on System V and win64, C variadics, `*void` and `mem.cast`,
  `@cc` callbacks; `e.os` per target — files, directories, processes, memory
  reservation, clock, threads, wait/wake, sockets, polling and dynamic loading —
  over raw syscalls on Linux and
  `kernel32` on Windows. **M1 depends on this landing first:** every other
  `lib/e` module that touches the OS is written over `e.os`
- Builtin `Atomic[T]` and orderings; `e.thread` over OS threads
- Protocols and `e.meta` (spec §9, D52, D53): `T.f(...)` resolution at
  instantiation, `for` over a `next`, the comptime-unrolled `for`, and
  `fields`/`members`/`type_name`/`get`/`set`. **`e.data.map`, `e.data.sort` and every
  `fmt.*` module depend on these**
- M1 library set, using canonical qualified names from `docs/modules.json`:
  `e.mem`, `e.meta`, `e.math`, `e.simd`, `e.atomic`, `e.bytes`, `e.str`, `e.path`,
  `e.data.list`, `e.data.map`, `e.data.sort`, `e.data.iter`, `e.os`, `e.io`,
  `e.thread`, `e.time`, `e.test`. Implement exactly the M1 declarations frozen in
  `module-apis.md`; a module is not delivered while a declared surface is missing

**Done when:** every item above is implemented in the self-hosted compiler, and
`lib/e` builds and its tests pass under `neper test`; all applicable conformance
fixtures validate byte-for-byte after the specified duration normalization; tooling
streams reconstruct source exactly and validate against the schema; formatter
idempotence holds; every M1 API fence matches extracted source declarations; and the
S0 generated-code benchmark has been rerun with no unexplained regression.

## M2 — Self-hosting and `.em` modules

- Rewrite the compiler in `neper-0`, compiled by the bootstrap; single-threaded at
  first, gaining the pool and the rest of M1 once it compiles itself
- Bootstrap compiler frozen, then deleted
- Work-stealing thread pool, per-thread arenas, sharded intern table
- Parallel parse phase, then function-granular parallel codegen
- Determinism harness: byte-identical output across `-j 1` and `-j N`, **and
  byte-identical output from an incremental rebuild and a clean build** of the same
  sources, over an edit script that touches bodies of inlined, generic and
  comptime-executed functions (spec §12, D36); the device-reached case is added to
  the same harness at M3, when `@gpu` exists
- `.em` format: per-declaration signature and body hashes, fine-grained `Deps`
  edges, NIR with body hashes, machine code, standard-format debug sections
- Incremental and parallel module compilation on the edge rule of spec §12
- Cross-module inlining via NIR, capped at 40 NIR instructions per callee, each
  inlined body recorded as a body-hash edge
- Monomorphised instances and device-compiled helpers emitted into the
  instantiating module's `.em` with module-local linkage; the own linker folds
  copies by content hash
- M2 library set from the machine plan: `e.data.deque`, `e.data.ring`,
  `e.data.heap`, `algo.rand`, `algo.uuid`, `algo.hash`, `algo.bitset`, `e.fs`,
  `e.proc`, `e.sync`, `e.channel`,
  `fmt.json`, `fmt.csv` and `fmt.ini`, with the exact frozen APIs and only their
  declared direct dependencies
- Module-plan validation in CI: source imports are a subset of each module's
  `direct_dependencies`; no layer violation, cycle, undeclared public symbol or
  package reservation enters the toolchain graph; implemented surfaces advance to
  `surface:"source"` only in the same plan revision that verifies their extracted
  public declarations
- Own linker, easy case first: freestanding ELF executables, and PE executables
  with a fixed `kernel32` import table (spec §13, D13), so `hello.e`, the compiler
  and `lib/e` link on Windows too with no object files and no process spawn.
  No PDB yet: Windows symbolication by external tools stays on `--linker=system`
  until M4

**Done when:** `neper` compiles itself; GP-01 passes its applicable correctness,
failure-injection and deterministic-build cases; a one-function edit rebuilds in
milliseconds on Linux and Windows; clean, incremental, relocated, `-j 1`, every
supported worker count and perturbed-schedule builds produce byte-identical
deterministic artifacts; every M2 API matches source; and the language- and
tool-complete release gates below pass.

## M3 — GPU

- `@gpu(X, Y, Z)` profile enforcement with call-chain diagnostics; device types,
  device slices and address spaces (`[]shared T`); `shared var` (spec §10, D37)
- SPIR-V emitter on the Vulkan 1.2 floor — `PhysicalStorageBuffer64`, scalar block
  layout, `NoContraction` on every result, correctly rounded division and square
  root sequences; Vulkan compute runtime written over `extern` (spec §5, D32).
  Its `libvulkan` import needs the M4 dynamic-import linking stage, so a program
  that opens a `.Vulkan` (or, once the PTX emitter exists, a `.Cuda`) device links
  under `--linker=system` until that stage lands (spec §13)
- CPU backend (spec §10, D38): a launch runs workgroup by workgroup on the calling
  thread; a workgroup runs on one host thread by barrier loop-fission, with
  per-invocation slots for locals that cross a barrier, the `barrier` divergence
  trap and the `0xCD` fill of `shared` — same semantics, steppable
- `e.gpu`: `Device`, `Queue`, `Buf[T]`, synchronous staging `upload`/`write`,
  asynchronous `launch[K]` with the compile-time pack check, in-order `release`,
  syncing `download`, `gpu.sync`, `grid1/2/3` as invocation counts,
  `gpu.barrier`, `gpu.memory_barrier`, `gpu.atomic_*` with scopes, the subgroup
  set, capability inference into the `.em` and the launch check
  — the implementation and documentation must match the exact `e.gpu` API fence in
  `module-apis.md`
- Device-callable inference: plain functions reached from a kernel compile for the
  device into the kernel-owning module's `.em` (spec §12, D24), with call-chain
  diagnostics on violations
- Floating point (spec §11, D39): no contraction anywhere, `math.fma` the only
  FMA, denormals preserved, `@gpu(..., ftz)` as the opt-in
- The M2 determinism harness gains the device-reached edit case (spec §12, D36)

**Done when:** GP-09 and GP-10 pass on every backend available at M3, and every
kernel in the test suite that uses no approximate builtin —
the `e.math` transcendentals `sin cos tan asin acos atan atan2 exp exp2 log log2
log10 pow`, `math.rsqrt`, and the float `gpu.subgroup_add/min/max` reductions (spec
§11) — produces **bit-identical** output on the CPU backend and on a Vulkan device (linked with `--linker=system`,
above),
the `saxpy` kernel of `examples/saxpy.e` among them (the example is a program root
run as `neper run examples/saxpy.e`, spec §2; it runs on `.Cpu`, then on `.Vulkan`
when one is present, and prints both checksums); and every
kernel that uses one agrees within its stated ULP bound.
The performance-language gate is rerun whenever M4 or M5 adds an applicable CPU or
GPU backend; published comparisons use identical algorithms and report distributions,
compile time, runtime and memory rather than isolated best cases.

## M4 — Breadth and depth

- aarch64 emitter (macOS, Linux, Windows on ARM)
- x86-32 emitter
- PTX emitter
- Own linker, hard case: dynamic imports by name from any `.dll`/`.so`/`.dylib`,
  plus ad-hoc code signing on Apple Silicon, plus the PDB writer — MSF container,
  DBI, module, symbol and line streams, no type stream (spec §13, D13).
  `--linker=system` remains for static archives
- neper-format debug side table in `.em` — types, locals, scopes, variable
  locations over the serialised type table — beside the standard subset, never
  instead of it (spec §13, D9)
- Debug engine: process control, breakpoints, single-step, stack walking, location
  rendering
- `neper dap` over that engine, plus VS Code and Zed extensions — the optimisation
  over the M1 `lldb-dap`/`codelldb` path. DAP keeps its framed JSON transport and
  rejects `--json` and `--absolute-paths`; it is the intentional exception to the
  finite-command JSONL envelope
- Optimiser depth: better inlining heuristics, load/store forwarding, scheduling;
  cross-`.em` inlining stays under the M2 cap

M4 expands the platform matrix for all applicable conformance, ABI, determinism,
debugging and GP workloads. It does not by itself claim general-purpose completion:
networking, advanced pure domains, interchange formats and multi-package verification
remain in the later library waves and M6.

**Done when:** every promised M4 target passes the applicable language/tooling corpus
and bidirectional C ABI fixtures; clean and incremental outputs remain deterministic;
the native debug path agrees with standard debugger locations on shared fixtures; and
GP-09/GP-10 have been rerun for every new applicable backend.

## Later toolchain-library waves — unnumbered

The 75 entries with `schedule:"later"` and `milestone:null` in `modules.json` are
real proposed toolchain modules, but this roadmap does not disguise them as part of
M4, M5 or M6. They may begin when their declared dependencies exist. Before each
wave starts, its `surface:"planned"` API is frozen; delivery requires tests, extracted
source/API equality and a same-change transition to `surface:"source"`.
Their position here does not order them before M5 or M6; independent waves may run
in parallel once their prerequisites and specifications are ready.

- **Extended containers and graph algorithms:** `e.data.tree`,
  `e.data.disjoint_set`, `e.data.graph`, `e.data.slot_map` and `algo.graph`. Existing
  collections gain deterministic non-mutating iterators; `e.data.heap` also gains
  comparator/context and linear-time bulk construction. Graph delivery covers BFS,
  DFS, deterministic topological sorting, weak/strong components and Dijkstra over
  immutable CSR views.
- **Extended pure algorithms, text and cryptography:** `algo.stat`, `algo.complex`,
  `algo.decimal`, `algo.bignum`, `algo.deflate`,
  `algo.linalg.matrix`, `algo.linalg.tensor`, `text.utf8`, `text.unicode`,
  `text.encoding`, `text.normalize`, `text.collate`, `text.regex`, `text.locale`,
  `crypto.hash`, `crypto.aead`,
  `crypto.sign`, `crypto.kx` and `crypto.random`. Preserve caller-owned allocation,
  caller-supplied entropy and the declared dependency edges. Cryptographic delivery
  requires published standard vectors, malformed-input cases and verification of
  every API that explicitly promises constant-time behavior.
- **Extended host and application services:** `text.io`, `e.task`, `e.time.calendar`, `e.tz`,
  `e.fs.mmap`, `e.fs.watch`, `e.concurrent.queue`, `e.concurrent.map`, `e.debug`,
  `e.metrics`, `e.log`, `e.cli`, `e.async`, `e.async.io`, `e.net`, `e.net.tls`,
  `e.net.http` and `e.net.ws`.
  These build over the M1/M2 platform boundary and must demonstrate cancellation,
  backpressure, bounded buffers, partial I/O, deterministic shutdown and no hidden
  allocation or entropy. They unlock the GP-04 service workload.
- **Interchange formats:** `fmt.uri`, `fmt.mime`, `fmt.gzip`, `fmt.zstd`, `fmt.zip`,
  `fmt.tar`, `fmt.yaml`, `fmt.xml`, `fmt.html`, `fmt.bson`, `fmt.msgpack` and
  `fmt.protobuf`. These consume caller-provided slices/readers and writers, never
  open resources themselves, and require malformed, streaming, bounds and round-trip
  corpora in addition to API equality. `fmt.html` additionally runs the pinned
  html5lib tokenizer and tree-construction fixtures for the WHATWG behavior frozen by
  that toolchain release.
- **Experimental collection conveniences:** `e.data.stack`, `e.data.queue` and
  `e.data.linked` remain available for workload evaluation but have no compatibility
  promise. `e.gpu.tensor` is likewise experimental, follows both M3 `e.gpu` and
  extended `algo.linalg.tensor`, and keeps every operation as an explicit queue
  submission. Promotion requires an applicable general-purpose workload and a
  recorded compatibility decision.
- **Experimental declarative GPU UI:** pure `gfx.geometry`, `gfx.paint`, `gfx.image`,
  `text.shape`, `text.layout`, `ui.style` and `ui.layout` support `gfx.scene`,
  `e.asset`, `ui.asset`, `ui.window`, `ui.input`, `ui.widget`, `ui.animation`,
  `ui.accessibility`, `ui.testing` and `ui.app`. Delivery follows the staged vertical slice and exact
  lifetime/reconciliation contracts in `ui-framework.md`; implementation remains
  blocked on reviewed embedded-asset linking, native-window, GPU-presentation and
  accessibility primitives.
  GP-15 must pass before any module in this family is promoted.

The 6 owner-qualified `x.*` reservations are actual vendor packages, not a
fifth wave. Each gets a separate package specification only after its upstream API
version, supported targets, ownership rules and licensing boundary are selected.
`x.neper.*` is forbidden: Neper-owned locale, URI/MIME, TLS, compression, archive and
time-zone facilities use toolchain namespaces and pin their standards/data snapshots
to the toolchain version.

## M5 — Native Metal

- Metal backend: MSL or AIR emitter plus a Metal runtime, replacing MoltenVK as the
  first-tier Apple GPU path
- Metal-only capabilities exposed where they map onto the GPU profile

Sequenced after M4 because a GPU backend costs an emitter *and* a runtime, and Apple
is one vendor. Until then Apple GPUs are reached through MoltenVK, supported but
second-tier (spec §10).

**Done when:** the Metal backend passes the same capability, ABI, source-map,
determinism and GP-10 correctness/ULP fixtures as the other applicable GPU backends,
and its published performance results satisfy the performance-language gate.

## M6 — pacman package manager

Pacman starts after M2 stabilizes self-hosting and `.em`; its remote and task stages
land after M4 stabilizes the platform and dynamic-linking path. It does not wait for
M5's independent Metal backend. It is bundled as the portable `neper pacman` command group;
the package manager remains outside compilation, and the compiler never accesses the
network. The normative design is [`pacman.md`](pacman.md).

- **P0, formats and resolution:** strict `project.yaml` subset including normalized
  root asset declarations, canonical
  `project.lock`, SemVer 2.0 constraints, deterministic PubGrub resolution and
  explanations, module-export collision checks, language-version checks, and golden
  fixtures
- **P1, local and offline:** deterministic asset hashing and read-only executable
  embedding, path dependencies, global immutable content-addressed
  cache, atomic concurrent population, `sync --frozen --offline`, a read-only virtual
  package-module map, reproducible dependency source identities, and compiler build-
  manifest/cache integration. Every vendored root has the canonical
  `neper-package.json` shape from the v1 schema; package source identities use the
  same root/path rules as compiler tooling
- **P2, remote sources:** signed central/private registry protocol, immutable release
  archives, Git dependencies pinned to commit and tree hash through an external Git
  adapter, credential-store integration, publish/yank, cache verification and explicit
  garbage collection
- **P3, generated inputs:** root-only explicit tasks instead of dependency lifecycle
  hooks, argument-array execution, scratch directories, capability approval, locked
  tools, content-addressed outputs and v1 generated-source maps with exact hashes and
  spans. Install and `sync` never execute package code
- Portable CLI: `init`, `add`, `remove`, `resolve`, `sync`, `upgrade`, `build`, `run`,
  `task`, `vendor`, `publish`, `cache`, and `info`, all with the toolchain's versioned
  JSON output conventions, shared diagnostic registry, deterministic record ordering
  and schema validation
- The public namespace policy reserves `e.*`, `algo.*`, `text.*`, `crypto.*`,
  `fmt.*`, `gfx.*` and `ui.*` to the toolchain;
  registry packages normally export `x.<owner>.*`

**Done when:** GP-12 passes; the same manifest and signed registry snapshot resolve to
a byte-identical lockfile on Windows, Linux, macOS, and in a container; a clean cache
can be populated from the lock and then build byte-identically under
`sync --frozen --offline`; mutable Git refs cannot alter a locked sync; concurrent
syncs expose no partial entry; and neither transitive packages nor denied tasks can
execute code.

## Cross-milestone verification and release claims

[`general-purpose-verification.md`](general-purpose-verification.md) is the
authority for the workloads, metrics and decision rule. The roadmap supplies
sequencing only. A workload starts as soon as its prerequisites exist and is rerun
when a relevant backend, ABI, module, package or protocol changes.

| Workloads | Primary enabling delivery |
|---|---|
| GP-01 self-hosted compiler | `neper-0` and M2 |
| GP-02 CLI, GP-03 parallel executor, GP-06 streaming parser, GP-07 bounded cache, GP-13 binary format | M1 tooling plus the M2 library set |
| GP-04 HTTP service | later `e.async`, `e.net` and `e.net.http` |
| GP-05 database client, GP-08 plugin C ABI | M1 FFI, M4 dynamic linking and a selected external package/API |
| GP-09 SIMD codec | M1 SIMD; rerun for each M4 CPU backend |
| GP-10 CPU/GPU numerical work | M3; rerun for M4 PTX, M5 Metal and later `e.gpu.tensor` |
| GP-11 terminal application | platform support plus a separately specified terminal package owned by its actual provider |
| GP-12 multi-package application | M6 |
| GP-14 image/audio pipeline | M2 concurrency, M4 target/FFI coverage and a separately specified media package |
| GP-15 declarative GPU desktop app | experimental `e.asset`/`gfx.*`/`ui.*` family plus asset linking, native window, presentation and accessibility blockers |

The four named release gates are cumulative:

1. **Language-complete:** `spec.md` and `grammar.ebnf` have no unresolved
   contradiction; every syntax/semantic rule has planned conformance coverage;
   non-goals have constructions or excluded workloads; no GP design requires an
   unapproved language feature. S0 must satisfy this gate before M0.
2. **Tool-complete:** formatter, lossless tokens/parse, complete index, stable
   diagnostics/fixes, tests, build manifests and source maps obey their versioned
   contracts; all locations have exact original-byte spans; clean, incremental,
   parallel and relocated builds are deterministic. M2 cannot complete without it.
3. **General-purpose:** GP-01 through GP-08 and GP-12 pass on Windows and Linux;
   long-running profiles have bounded resources; FFI and failure-injection suites
   pass every promised host ABI; and the LLM thresholds pass on at least two
   independently trained model families. This gate necessarily waits for M6 and the
   required later networking/package work; no earlier milestone implies it.
4. **Performance-language:** GP-09 and GP-10 are correct on every applicable backend,
   and comparable C, C++, Rust and Go results publish distributions for compile time,
   runtime and memory using the same algorithms. M3 establishes the first result;
   M4, M5 and later GPU work reopen it.

The initial LLM thresholds are release criteria, not aspirations: at least 95% of
local edits parse first pass, at least 90% type-check first pass, median unrelated
formatted diff is zero, at least 95% of compiler-error repairs finish in one
additional turn, no task requires parsing human diagnostics, and no accepted task
uses undocumented behavior or intrinsics. Thresholds may tighten after a versioned
baseline, but may not be silently relaxed. A syntax/API change is justified by total
model effort, repair behavior and review risk across the supported model/tokenizer
matrix—not by character count or a single tokenizer.

## Deliberately not scheduled

Auto-vectorisation, an LSP beyond the public `neper parse`/`neper index` data, and any
form of runtime reflection.
Each is a real cost against the two headline goals. Package management is scheduled
as M6 under the deliberately constrained pacman design above.
