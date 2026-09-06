# Neper implementation handoff

Status captured: 2026-09-06. Revised the same day after committing the `.em`
correctness increment and the generic-instance identity increment that followed
it.

This document is a continuation guide for a new development session. It records
what is implemented, what is only designed, what is currently uncommitted, and
the safest order for continuing. It is not a normative language specification.
Normative requirements remain in [`spec.md`](spec.md), [`roadmap.md`](roadmap.md),
[`module-apis.md`](module-apis.md), and [`modules.json`](modules.json).

## 1. Resume snapshot

- Repository: `D:\repos\neper`
- Branch: `master`
- Committed HEAD: `82ea479` (`Report the Windows suite result as its exit code`)
- Commit count at capture: 171
- Active milestone: **M2 underway, not complete**
- M0 is complete.
- M1 and M2 overlap by design. M1 completes inside the self-hosted compiler; it
  is not currently complete.
- M2.5 is designed and scheduled, but must not start until M2 is complete.
- The `.em` correctness feature formerly described in section 7 is committed as
  `88c20f3`. Section 7 now records the generic-instance increment that followed.

The latest complete verification was:

```text
Windows: tests/selfhost/run.ps1
Result:  selfhost tests passed

Linux:   wsl -d Ubuntu-24.04 -- bash /mnt/d/repos/neper/tests/selfhost/run.sh
Result:  selfhost tests passed
```

Both suites were rerun and stayed green after each of `88c20f3`, `109f760` and
`82ea479`. `git diff --check` passed for each increment. Git emits only the
existing PowerShell LF-to-CRLF working-copy warning.

`tests/selfhost/run.ps1` used to exit 1 even when it printed `selfhost tests
passed`, because its last native command is an expected-failure case. `82ea479`
fixed that, so the Windows suite's exit code is now meaningful. Invoke the Linux
suite from PowerShell, not from Git Bash, which rewrites the `/mnt/d/...` path.

## 2. Work completed

### 2.1 Specification and architecture

The language, modules, tooling, roadmap, UI, verification, and API documents were
reviewed deeply for missing contracts and ambiguity. The working tree contains a
large coordinated next-contract revision covering:

- precise language semantics and implementation/release gates;
- a machine-readable 128-module plan and exact public API catalogue;
- explicit distinction between designed, partial, specification-provided, and
  source-implemented module surfaces;
- deterministic finite-command JSONL tooling, lossless token/parse contracts,
  stable diagnostics, generated-source maps, and build manifests;
- general-purpose replacement verification cases;
- post-M2 language/compiler hardening aimed at visible dependencies, bounded
  context, reliable harness behavior, generated code, and LLM editing;
- standard-library composition, cancellation, ownership, I/O, codec, test, and
  package-delivery hardening;
- GPU/UI device selection and multi-device contracts;
- JavaScript and TypeScript comparison coverage in the LLM edit benchmark.

Important: most of this documentation work is currently uncommitted. It is a
design contract, not evidence that the corresponding code exists. See section 8
before staging anything.

### 2.2 M0 and the bootstrap subset

M0 was implemented at `ed36b51`. The tracked bootstrap is
[`../bootstrap/neper.c`](../bootstrap/neper.c), with its runtime in
[`../bootstrap/runtime.c`](../bootstrap/runtime.c). Subsequent commits extended
the frozen `neper-0` subset far enough to express the self-hosted compiler:

- scalar control flow, arrays, slices, checked ranges, structs, pointers, and
  aggregate ABI behavior;
- enums, unions, exhaustive `switch`, lexical `defer`, and protocol iteration;
- multiple-return destructuring, integer constant folding, and generic function
  and aggregate specialization;
- compiler-owned memory and OS intrinsics;
- bootstrap debug-local metadata;
- parser-capacity and large-stack probes on Windows and Linux.

The bootstrap remains tracked and has not been deleted. M2's eventual
"bootstrap frozen, then deleted" exit item is therefore still open.

### 2.3 Self-hosted front end

The compiler source lives in [`../src`](../src). Its major front-end files are:

- source and tokens: `source.e`, `lex.e`, `syntax.e`;
- parsing: `parse.e`;
- project/module loading: `project.e`, `graph.e`;
- name resolution and checking: `resolve.e`, `check.e`;
- entry point and finite commands: `main.e`.

Implemented front-end work includes:

- transitive project/module discovery with target source selection;
- structured parsing for declarations, expressions, aggregates, generics,
  control flow, attributes, tuple assignments, and recovery nodes;
- exact token positions, lossless byte ranges, trivia, invalid UTF-8 recovery,
  and bounded malformed-token recovery;
- caller-owned parser storage instead of the former fixed list caps;
- lexical scope and declaration resolution;
- scalar/composite checking, aliases, constants, generics, indexing/slicing,
  aggregates, multiple returns, `switch`, `defer`, and compiler intrinsics;
- bootstrap/self-hosted front-end acceptance and diagnostic parity.

Representative checkpoints are `d15eece` (checker pass), `1b82b74` (front-end
parity), and `720f61e` (diagnostic parity).

### 2.4 NIR, x86-64 backend, objects, and executables

The compiler now has canonical NIR, deterministic register allocation, x86-64
selection, and direct binary emission. The main files are:

- IR and lowering: `nir.e`, `lower.e`, `layout.e`;
- register allocation and machine code: `regalloc.e`, `codegen_x64.e`,
  `emit_x64.e`;
- object formats: `object_elf.e`, `object_coff.e`;
- native linkers: `link_elf.e`, `link_pe.e`;
- runtime payloads: `runtime_elf_x64_ext.e`, `runtime_pe_x64.e`, and their source
  assembly files.

Implemented behavior includes:

- scalar values, calls, `try`, locals, storage, branches, loops, casts, unary,
  bitwise, wrapping, division, shifts, comparisons, aggregates, checked indexing,
  and iterator lowering;
- System V and Windows x64 parameter/call behavior used by current fixtures;
- deterministic ELF and AMD64 COFF objects;
- directly linked runnable ELF and PE executables;
- fixed `kernel32` imports for the current PE linker;
- concrete generic function instances, lexical cleanup, and custom iterator
  protocols at the current bootstrap-compatible level.

Stage-two self-hosting has been reached on Linux (`f683d25`) and Windows
(`6156e0c`). Deterministic native self-host stages are exercised by `c204174`.
This is substantial M2 progress, but it does not satisfy every M1/M2 release gate.

### 2.5 Compiled modules (`.em`) and artifact linking

The `.em` implementation is primarily in `artifact_hash.e`, `binary.e`, `em.e`,
`em_link.e`, and `error_table.e`. Completed increments include:

- deterministic artifact hashing;
- canonical NIR function signatures;
- versioned deterministic compiled-module containers;
- complete current module interfaces;
- dependency edge reading and validation;
- foreign constant value dependencies;
- error-value collision detection and error-table merging;
- machine-code decoding and cached-code hash validation;
- executable linking from compatible `.em` artifacts.

Key checkpoints run from `de71815` through `db71af6`. The currently uncommitted
correctness extension is described separately in section 7.

### 2.6 Host/runtime coverage

The fixed host boundary now covers the bootstrap-compatible Linux and Windows
runtime paths used by the self-host compiler and test programs:

- Linux fixed host intrinsics (`380c651`);
- deterministic embedded PE runtime generation (`630d5d9`);
- Windows memory and clock intrinsics (`57a06bd`);
- Windows process/OS intrinsics (`de88d9a`);
- exact Windows startup argument decoding (`a3d530d`).

This does not yet mean the complete M1 `e.os` surface—threads, sockets, polling,
dynamic loading, and all frozen declarations—has passed its final API gate.

### 2.7 Implemented library modules

The following source modules and behavioral fixtures were implemented and
committed:

| Module | Commit | Notes |
| --- | --- | --- |
| `algo.hash` | `db50fcb` | FNV-1a 32/64, xxHash64 one-shot/streaming, CRC32 one-shot/streaming, Adler32 |
| `algo.bitset` | `dcb70dd` | Fixed-length bit sets, tail-bit invariant, algebra, scans, empty-set behavior |
| `e.data.ring` | `c839c80` | Generic fixed ring, wraparound, overwrite, iteration, zero capacity |
| `e.data.deque` | `7420f61` | Generic arena-grown deque, reserve/growth, wraparound, iteration |
| `e.data.list` | `2de9314` | Generic arena-grown list, insert/remove, views, copy, iteration |

Each committed module has exact source-surface checks in both self-host harnesses
and Windows/Linux behavioral coverage. The checker was also corrected so `.len`
is a pseudo-member only for arrays, slices, and strings; ordinary structs can have
a real field named `len`.

Current machine-plan status:

- M2 `surface:"source"`: `e.data.deque`, `e.data.ring`, `algo.hash`,
  `algo.bitset` (4 of 14 M2 modules).
- M2 `surface:"planned"`: 10 modules listed in section 9.
- M1 `surface:"source"`: `e.data.list`.
- `e.io` is `partial`; several compiler/runtime-owned M1 surfaces are marked
  `spec`; remaining M1 modules are not yet source-complete.

### 2.8 Progress site

The Neper progress site was updated during this work and was visible at:

`https://neper-progress.nebosa-company.chatgpt.site/`

The working tree contains untracked packaging scripts, staged site directories,
and deployment archives. Treat these as retained work products, not as compiler
source. A new session should verify the live site before claiming it still matches
the repository, because deployment state is external and can change.

## 3. Major committed checkpoints

This is a compact map of the 168-commit history, not a replacement for `git log`.

| Checkpoint | Commit |
| --- | --- |
| M0 bootstrap compiler | `ed36b51` |
| Bootstrap OS intrinsics | `cee0bb9` |
| Expanded module/UI architecture | `c84d90a` |
| Complete current self-hosted checker pass | `d15eece` |
| Bootstrap front-end parity | `1b82b74` |
| Canonical self-hosted NIR begins | `fd3b392` |
| Real deterministic object files | `8bd09e5` |
| Runnable ELF/PE direct linking | `06987db`, `90b5b7b` |
| Deterministic `.em` containers | `eb2f9e1` |
| Executable linking from `.em` | `84510fa` |
| Linux/Windows stage-two self-hosting | `f683d25`, `6156e0c` |
| Deterministic native self-host stages | `c204174` |
| Complete current fixed host increments | `380c651` through `a3d530d` |
| First four M2 source libraries | `db50fcb` through `7420f61` |
| M1 arena-grown list prerequisite | `2de9314` |

Use `git log --reverse --oneline` for the complete chronological history.

## 4. Current compiler source map

For quick navigation in a new session:

| Area | Files |
| --- | --- |
| CLI and orchestration | `src/main.e` |
| Source/project graph | `src/source.e`, `src/project.e`, `src/graph.e` |
| Lexer/parser/tree | `src/lex.e`, `src/parse.e`, `src/syntax.e` |
| Resolver/checker | `src/resolve.e`, `src/check.e` |
| Layout/NIR/lowering | `src/layout.e`, `src/nir.e`, `src/lower.e` |
| Register allocation/x64 | `src/regalloc.e`, `src/codegen_x64.e`, `src/emit_x64.e` |
| ELF/COFF objects | `src/object_elf.e`, `src/object_coff.e` |
| ELF/PE linking | `src/link_elf.e`, `src/link_pe.e` |
| `.em` artifacts | `src/artifact_hash.e`, `src/binary.e`, `src/em.e`, `src/em_link.e` |
| Error identity | `src/error_table.e` |
| Embedded runtimes | `src/runtime_elf_x64_ext.*`, `src/runtime_pe_x64.*` |
| C bootstrap | `bootstrap/neper.c`, `bootstrap/runtime.c` |

## 5. Tests and useful commands

Run the complete Windows self-host suite:

```powershell
& tests/selfhost/run.ps1
```

Run the complete Linux self-host suite through the configured WSL distribution:

```powershell
wsl -d Ubuntu-24.04 -- bash /mnt/d/repos/neper/tests/selfhost/run.sh
```

Audit only the current feature diff:

```powershell
git diff -- src/em.e src/lower.e src/codegen_x64.e tests/selfhost/run.ps1 tests/selfhost/run.sh tests/selfhost/fixtures/em/hash_module tests/selfhost/fixtures/em/host_dependency
git diff --check -- src/em.e src/lower.e src/codegen_x64.e tests/selfhost/run.ps1 tests/selfhost/run.sh
```

Inspect milestone/module status without relying on prose:

```powershell
$plan = Get-Content docs/modules.json -Raw | ConvertFrom-Json
$plan.modules | Where-Object milestone -eq 'M2' | Select-Object name,surface,direct_dependencies
```

## 6. Current milestone assessment

The accurate status is **M2 in progress**.

Already present:

- a self-hosted compiler that reaches native stage two on Linux and Windows;
- deterministic current-path NIR, x64 code, objects, executables, and `.em` files;
- initial `.em` dependency validation and direct artifact linking;
- the fixed runtime intrinsics needed by current self-host fixtures;
- 4 of 14 M2 libraries plus the M1 `e.data.list` prerequisite.

Not yet sufficient for an M2 completion claim:

- the complete M1 CPU language and library/API fence;
- the M2 thread pool and parallel parse/function-codegen pipeline;
- clean/incremental/relocated/worker-count/perturbed-schedule determinism over the
  complete required edit script;
- production incremental module compilation;
- capped cross-module NIR inlining with body-hash edges;
- generic instance ownership in `.em` and content-hash folding by the own linker;
- every remaining M2 library;
- complete language- and tool-complete release gates;
- bootstrap freeze/deletion at the specified point.

## 7. Most recent committed increments

### 7.1 `88c20f3` Canonicalize compiled-module IR dependencies

This is the feature the previous session left uncommitted. It is committed now.
Do not redo it.

Emitting all compiled modules for a real `algo.hash` program previously failed
with `em.InvalidArtifact` even though direct executable emission worked. Three
representation mismatches caused it:

1. No-result/control NIR instructions carried an invalid type, but canonical NIR
   serialization tried to serialize every instruction type.
2. Hidden aggregate-return storage and multi-value calls used an invalid type as
   an internal sentinel even though they produce NIR results.
3. Lowering rewrote host calls to linker symbols such as `neper_os_write`, while
   artifact dependency hashes must identify source interface declarations such as
   `write`.

`src/em.e` now canonicalizes an invalid type on a no-result instruction as
module-local `void` and rejects any other invalid result type; maps fixed
memory/OS linker symbols back to source declaration names before interning and
hashing dependency records; omits `neper_mem_alloc` as a signature edge; and
preserves linker-symbol names in relocation records. `src/lower.e` gives hidden
aggregate-return stack values the internal type `return-slot` and multi-value
call results the internal type `return-values`. `src/codegen_x64.e` recognizes
`return-values` as the two-register multiple-return ABI marker, retaining
compatibility with the earlier invalid-type sentinel.

### 7.2 `109f760` Give generic instances distinct code identity

Found while probing generic `.em` ownership, and a silent miscompilation rather
than an artifact-only defect.

NIR identified a function by module and name only. Every concrete instance of one
generic template therefore collapsed onto a single symbol:
`codegen_x64.resolve_calls` bound each call to the first NIR function of that
name, and `em_link` did the same when relinking compiled modules. A program that
instantiated one template at two types silently ran the wrong instance.
`tests/selfhost/fixtures/link/generic_instances` exits non-zero on the compiler
built at `88c20f3` and exits zero after this change.

- `check.Function` carries `instance_id`, assigned in `instantiate_function` as a
  deterministic per-template ordinal.
- `nir.Function` and `nir.FunctionRef` carry that discriminator. Both
  `begin_function` and `intern_function` take it, so distinct instances no longer
  intern to a single reference.
- `codegen_x64.resolve_calls` matches on it. Lowering passes it for every call
  except compiler-owned intrinsics, which stay at 0.
- `src/em.e` records it in the NIR section, in code function records and
  relocations, and in the canonical NIR and code content hashes. The
  compiled-module format is therefore **version 2**; `em_link` reads it back.
- `em.checked_function_for_nir` matches an instance exactly instead of guessing
  from lowering order.
- Distinct instances of one foreign template resolve to a single source
  declaration, so dependency edges are recorded once per declaration.
  `check-em-edge` now checks every edge that targets the given artifact instead
  of requiring the dependent to hold exactly one, which retires the first entry
  of section 11.

### 7.3 `82ea479` Report the Windows suite result as its exit code

`tests/selfhost/run.ps1` ends on an expected-failure case, so it exited 1 even
after printing `selfhost tests passed`.

### 7.4 Name-collision diagnostics

The earlier draft of this section reported a local or parameter shadowing a
module-scope function as a probable resolver bug. That was wrong about the
language. `docs/spec.md` §5 is explicit:

> A local or parameter name is declared once per **active lexical scope**. It may
> not reuse a parameter, a binding in an enclosing scope, a module-scope name of
> its own module, a `use` qualifier or a builtin type name (§2).

`resolve.ModuleShadow` is therefore correct, deliberate, and already covered by
`fixtures/scope/module_shadow`, `parameter_shadow` and `qualifier_shadow`. No
behavior changed. `fixtures/link/generic_instances/src/dep.e` still names its
parameters `a` and `b` because §5 forbids the alternative, not because of a bug.

What was genuinely wrong was the diagnostic. Every declaration and scope
collision reported `0:0` with the code `E-NAME-9999` and the text
`name resolution failed` — no position, no name, no indication of what collided.
The fix records the offending token and name in the resolver and reports the
codes `docs/diagnostics.md` already reserves:

| Resolver error | Code | Example |
| --- | --- | --- |
| `DuplicateName` | `E-NAME-0001` | ``main.e:3:4: error[E-NAME-0001]: `Thing` already names a module-scope error; each name may be declared once per namespace`` |
| `QualifierCollision` | `E-NAME-0002` | ``main.e:3:4: error[E-NAME-0002]: `d` collides with a use qualifier in this module`` |
| `ReservedName` | `E-NAME-0003` | ``main.e:1:4: error[E-NAME-0003]: `u8` is a reserved name and cannot name a declaration`` |
| `ModuleShadow` | `E-NAME-0003` | ``main.e:2:8: error[E-NAME-0003]: `value` already names a module-scope function; a local or parameter may not reuse it`` |
| `DuplicateLocal` | `E-NAME-0003` | ``main.e:3:9: error[E-NAME-0003]: `value` is already bound in an active scope`` |
| `ReservedLocal` | `E-NAME-0003` | ``main.e:2:9: error[E-NAME-0003]: `u8` is a reserved name and cannot name a local or parameter`` |

`resolve.add_local` now takes the graph and the offending token instead of a
pre-sliced name, and `resolve.add` derives a declaration's name token from its
node. Three fixtures were added for the module-scope cases that had none:
`fixtures/scope/declaration_duplicate`, `qualifier_collision` and
`reserved_declaration`. Both suites pin the exact line, column, code and message
for all nine cases, so any regression in position or wording fails the suite.

These are the first emitters of `E-NAME-0001` through `E-NAME-0003` from the
resolver. `docs/diagnostics.md` already registered all three, so no
specification change was needed.

### 7.5 Generic instance ownership

The other half of the section 10 contract. A concrete instance is now code in the
module that instantiated it, not in the module that declares the template, so a
library artifact no longer depends on its consumers. Emitting
`fixtures/link/generic_instances` used to put all four `dep` instances in
`dep.x64-*.em`; it now puts all seven functions in `main.x64-*.em` and leaves
`dep.x64-*.em` with no code at all.

- `check.Function` carries `owner_module_index`. `find_function_instance` and the
  per-template instance ordinal are keyed by owner, so every instantiating module
  gets its own copy.
- The `Checker` carries an active owner. A template body is walked in its
  declaring module's tree, so without it a nested instantiation
  (`list.from_slice` calling `list.init`) would be attributed to the library.
  Both `check.check_instance` and `lower.lower_owned_instances` set it.
- `lower.module` lowers the instances its module owns by parsing the declaring
  module's tree on demand, and repeats until no pending instance is left, because
  lowering an instance can create more.
- `nir.begin_function` and `nir.intern_function` take the owner, so instance calls
  are module-local.
- A module that instantiates a foreign template holds a copy of that template's
  code, so it records a `dependency_body_kind()` edge on the template instead of
  the signature edge it loses. A template has no NIR, so `em.body_hash` takes its
  body hash over the token spellings of its declaration: an edit to the template's
  code makes the edge stale, an edit to its comments does not.
- `em_link.assemble` folds functions with equal content hashes onto one body. The
  content hash already covers the code bytes and every relocation target, so equal
  hashes mean the same function.
- `main.init_cli_nir` needed larger pools. Per-module copies scale the NIR function
  count with instantiation sites rather than declarations, and the self-host build
  exhausted NIR capacity while lowering `src/layout.e` until the function, block,
  instruction and operand capacities were raised.

`fixtures/link/generic_folding` is the folding case: `one` and `two` both
instantiate `lib.pick[i64]`, so both artifacts carry that instance with an
identical content hash while `lib.x64-*.em` carries no code. Both suites assert
the code counts, the instance discriminators, the shared content hash, and that
the executable linked from the folded artifacts runs.

### 7.6 Bootstrap frames sized by measurement

`bootstrap/neper.c` sized every stack frame as
`align16(locals_end + 32 * 8 + 64)` — a fixed 320-byte guess for the scratch a
function might need. Temporaries are allocated per statement from `call_base`
downward, and outgoing stack arguments sit at the bottom of the same frame, so any
statement needing more than the guess addressed memory below `rsp`.

At the commit before the fix, 11 of the 811 emitted functions did this on both
platforms. `resolve_reserved` was the worst: a single `ret same(...) || same(...)`
chain reached `[rbp-736]` inside a 352-byte frame, 384 bytes past the stack
pointer. Writing below `rsp` is undefined rather than reliably fatal, which is why
it went unnoticed — it corrupted nothing most of the time, and adding fields to a
hot struct just moved which statement landed on something that mattered. That is
what made a third `usize` on `check.Function` segfault the stage-1 compiler on
Windows on any module that instantiated a generic.

`emit_function` now emits each function twice: once to the platform's null device
to measure the temporary high-water mark and the widest outgoing argument area,
then for real with `frame_size = align16(max_temp + outgoing_bytes + 16)`. Label
and debug-label counters are saved and restored around the measuring pass so both
passes produce identical labels, and the debug type and string tables are built
after all functions are emitted, so the extra pass cannot disturb them. If the null
device cannot be opened the old conservative size is kept.

Both suites now assert the invariant directly over every function the bootstrap
emits: build the compiler with `--emit-asm`, then check that no `[rbp-N]` in a
function body exceeds that function's frame size. The check fails on assembly
produced before the fix and passes after.

The constraint this placed on compiler state is lifted. `check.Function` was
verified to take 24 extra `usize` fields with no failure, and `source_start` and
`source_end` were moved back onto it: a declaration's source range describes the
function, not its generic parameters, and every instance needs it whether or not
it came from a template.

### 7.7 Protocol lookup at the instantiation

`T.cmp(a, b)` did not type-check at all. Spec section 9 makes `T.f(...)` a protocol
call wherever T is a comptime type parameter, resolving to `fn <t>_<f>` in the
module that declares the type T is bound to, with `<t>` that type's name in
snake_case.

Delivered:

- `check.protocol_name_matches` generalizes the snake_case stem matcher that was
  hard-wired to `_next` for iterators; iterator lookup is now a wrapper on it.
- `check.check_protocol_call` resolves the receiver, finds the declared function
  and enforces rule 3, that the first parameter is the type by value.
- A generic template's own body is checked before any instantiation binds T, so the
  receiver is still symbolic there. Such a call is marked `protocol_pending` and its
  result follows the context, which defers resolution to the instantiation site
  where rule 5 puts the error.
- Rule 4's supplied `cmp` for `Integer`, `Bool` and `Err`. There is nothing to call,
  so `lower.emit_supplied_cmp` emits it inline. The language has no bool-to-integer
  cast, so the three results come from branches into one slot, in the same idiom
  `&&` and `||` already use. Codegen takes comparison signedness from the left
  operand's own type, so unsigned ordering is correct; the fixture covers
  `4000000000u32`, which a signed comparison would order wrongly.
- Rule 4's precedence: a `fn` declared in the type's own module always wins, which
  falls out of looking the declaration up first.

Not delivered, and each still reports a missing protocol:

- `cmp` for enums. A `u64`-backed enum would need its backing type threaded to the
  comparison for unsigned ordering, and the receiver type reaching codegen is the
  named enum, not its backing integer.
- `cmp` for floats (no scalar float support yet), and for slices, arrays, vectors
  and tagged unions, which rule 4 defines by recursion.
- The `hash`, `eq` and `format` fallbacks entirely.
- A generic protocol function for an instantiated nominal generic type
  (`Box[i32].hash` needing `fn box_hash[T: type]`). This is detected and reported
  as unsupported rather than mis-resolved.
- Lookup edges. Spec section 12 (D36) requires every protocol name examined to be
  recorded as a `.em` lookup edge so that declaring the `fn` later is not silently
  ignored. `em.dependency_lookup_kind` already exists and `dependency_matches`
  already handles it; nothing emits one yet. This matters for incremental
  correctness, not for a clean build.

`fixtures/link/protocol_cmp` covers both halves: two struct types in one module
carrying `point_cmp` and `tag_cmp` with opposite orderings, so a wrong dispatch
fails the run, plus the supplied `cmp` over signed, unsigned and boolean receivers.
`fixtures/check/protocol_missing`, `protocol_signature` and `protocol_no_fallback`
pin the three diagnostics exactly in both suites.

### 7.8 Function values

`fn(A, B) -> R` is a type (spec section 5), but the compiler only parsed it:
`check.e` had no handling and `lower.e` none at all. That blocked the `HeapBy`
half of `e.data.heap` and the `_by` variants across `e.data.sort`.

- `check.Kind.Function` with a `FunctionSignature` side table, because a parameter
  and return list does not fit the flat `Type` record. Structural equality, an
  8-byte layout, and resolution of `fn(...) -> R` in any type position.
- Naming a function in a value position, qualified or not, yields a pointer to it.
  Generic, intrinsic and `extern` functions are refused.
- `nir.FunctionAddress` (45) materializes the pointer as a rip-relative `lea`
  patched by the same relocation pass that patches a `call`, so no new relocation
  kind was needed. `nir.IndirectCall` (46) carries the callee as its first operand
  and shares all argument marshalling with the direct path, ending in `call reg`.
- `.em` serializes function types in both the canonical and indexed writers, and
  `FunctionAddress` canonicalizes to the referenced name rather than an interning
  index. `em.reference_used_by_module` and the string collector had to learn that
  taking a function's address references it exactly as a call does; without that a
  cross-module function value produced an invalid artifact.

`fixtures/link/function_values` covers a function passed as an argument and called
through the parameter, one held in a `var` and replaced, and one in a struct field
taken from another module. Both suites also emit the artifact set, link it, and
require the result to be byte-identical to the direct link.

Not covered: `extern fn(...) -> R` and the `@cc(CONV)` conventions of section 5,
and the GPU profile's ban on function pointers. A function value is currently
only callable from a local or parameter binding; calling one directly out of a
struct field (`s.cmp(a, b)`) is not wired, which is why the fixture binds it to a
local first.

Two hazards this increment ran into, both caught by the suites:

- `target` is reserved (spec section 2, the builtin comptime namespace) and was
  used as a local name in `check.e`, `lower.e` and as a parameter in
  `emit_x64.call_register`. `resolve-file` reports only `error:
  resolve.ReservedLocal` with no position, so finding which of 28 modules was at
  fault took a per-module sweep. Making that finite command report the same exact
  diagnostic `check-file` gives would be a cheap improvement.
- The instruction dispatch in `codegen_x64.function` is an eight-level hand-nested
  `if`/`else` chain, because the language has no `else if`. Adding a case there is
  easy to get wrong in a way that still compiles: closing one `else` a level early
  made `.Extract` fall through to `ret Unsupported`, which broke every
  multiple-return destructuring while leaving everything else working.

## 8. Working-tree boundaries

No compiler or test change is intentionally uncommitted now. Everything in
section 7 is committed.

The following changes predate that work and must be preserved and handled as a
separate documentation/design/site effort:

```text
D  DECISIONS.md
M  README.md
M  benchmarks/llm_edit/README.md
M  docs/general-purpose-verification.md
M  docs/module-apis.md
M  docs/modules.json
M  docs/modules.md
M  docs/roadmap.md
M  docs/schemas/neper-v1.schema.json
M  docs/spec.md
M  docs/tooling.md
M  docs/ui-framework.md
?? docs/decisions.md
?? docs/post-m2-llm-hardening.md
?? docs/stdlib-hardening.md
?? scripts/check_module_plan.py
?? scripts/render_module_apis.py
?? tests/test_module_plan.py
```

`DECISIONS.md` plus `docs/decisions.md` represents a case/path move in progress.
Do not restore or delete either side without reviewing the documentation set as a
whole.

The following are scratch, rendered, packaging, or deployment work products. They
are not part of the current compiler feature and should remain unstaged until their
ownership and retention policy are decided:

```text
.tmp-linux-runtime.bin
.tmp-linux-startup.bin
.tmp-runtime-ext.bin
.tmp-sites-packager/
docs/module-apis.pdf
package-site.sh
prepare-site-build.cjs
progress-site-*.tar.gz
site-package-stage-20260905/
```

There may be additional ignored build outputs under `build/` and `build-linux/`.
Do not clean broad directories destructively while this handoff is being resumed.

## 9. Remaining M2 libraries and blockers

The machine plan currently has ten planned M2 modules:

| Module | Immediate prerequisite or implementation gap |
| --- | --- |
| `e.data.heap` | `partial`: the non-`_by` surface is delivered. Section 7.8 unblocked the `HeapBy` half, which is what remains before it can advance to `source` |
| `algo.rand` | Exact API includes `f64`; scalar float lowering and ABI support are incomplete |
| `algo.uuid` | Depends on `algo.hash` and source-complete `e.str`; `e.str` is not source-complete |
| `e.fs` | Depends on complete `e.path`, `e.str`, memory, and filesystem `e.os` behavior |
| `e.proc` | Depends on cancellation, memory, process OS calls, and time semantics |
| `e.sync` | Depends on complete atomics plus OS wait/wake and time behavior |
| `e.channel` | Depends on `e.sync` and memory ownership/concurrency contracts |
| `fmt.json` | Depends on complete `e.io`, `e.mem`, `e.meta`, and `e.str` |
| `fmt.csv` | Same reflection/string/I/O prerequisites as `fmt.json` |
| `fmt.ini` | Same reflection/string/I/O prerequisites as `fmt.json` |

Do not publish a partial public surface and mark it `source`. The established rule
is that a module advances to `surface:"source"` only in the same revision that:

1. implements its complete frozen API;
2. adds behavioral tests on Windows and Linux;
3. extracts and checks the exact public declarations;
4. updates `docs/modules.json`.

## 10. Remaining compiler/toolchain work

### Highest-value next compiler increment

Continue `.em` work with generic modules and monomorphized instances. `109f760`
delivered the identity half of this: distinct instances now have distinct code and
distinct hashes, and `fixtures/link/generic_instances` covers it on both
platforms. The ownership half is still open. The current list/deque/ring sources
remain good probes because they require generic template and instantiation
behavior that the simple artifact fixtures do not cover. The target contract is:

- templates and required NIR are represented deterministically (done);
- concrete instances are emitted into the instantiating module with module-local
  linkage (done);
- dependency/body hashes invalidate exactly the consumers that need rebuilding;
- the own linker folds equivalent copies by content hash;
- clean and repeated emission is byte-identical on Windows and Linux.

Keep this separate from `e.data.heap`; heap's exact default-comparison contract
needs general `T.cmp` protocol resolution first.

### Subsequent compiler prerequisites

1. General protocol lookup at instantiation is partially delivered (section 7.7):
   declared protocol functions resolve, and `cmp` is supplied for integers, `bool`
   and `err`. Enums, floats, the recursive shapes, `hash`/`eq`/`format`, generic
   protocol functions and lookup edges remain.
2. Scalar floating-point parsing/checking/NIR/x64 ABI and operations needed by
   `algo.rand` and the M1 CPU language.
3. Complete `e.str`, `e.path`, `e.meta`, `e.atomic`, `e.thread`, `e.time`, and
   `e.io` surfaces with exact API fences.
4. Remaining OS surface: threads, wait/wake, sockets, polling, and dynamic loading.
5. Worker pool, sharded interning, parallel parse, and function-granular codegen.
6. Incremental compilation and the complete M2 determinism edit matrix.
7. Cross-module inlining with the 40-instruction cap and body-hash dependency edge.
8. Formatter, lossless finite tooling streams, index completeness, manifests,
   generated-source maps, test runner, FFI, debug info, SIMD, and remaining M1
   release gates.
9. Bootstrap freeze/deletion only after the specified self-host and recovery path
   is securely archived and reproducible.

### Documentation/tooling validation still pending

- Finish reviewing the coordinated documentation diff as one contract change.
- Run `scripts/check_module_plan.py` and `tests/test_module_plan.py` once their
  intended invocation and dependencies are confirmed.
- Regenerate/verify `docs/module-apis.pdf` only as a derived artifact; do not treat
  it as the normative source.
- Reconcile the progress site with the committed compiler state after each grouped
  implementation commit.
- Keep M2.5 requirements scheduled but do not silently add them to the preserved
  M2 completion baseline.

## 11. Known implementation constraints

- `check-em-edge` now accepts a dependent with several edges into one module and
  requires every edge that targets the given artifact to be current. It still
  rejects a dependent with no edge into that module at all.
- NIR historically used `.Invalid` as the multi-return marker. `88c20f3`
  introduced explicit internal types while retaining backend compatibility. Any
  new backend or artifact reader must recognize the explicit representation, not
  depend on invalid types.
- A function is identified in NIR, in relocations and in `.em` code records by
  module, name **and** instance discriminator. Anything that matches functions by
  module and name alone will bind calls to the wrong generic instance.
- The module named by a NIR function or reference is the module that **owns** the
  code, which for a generic instance is the instantiating module, not the module
  that declares the template. `em.checked_function_for_nir` therefore cannot look
  a template up by module and name.
- Bootstrap frame sizes are measured, not guessed (section 7.6). Anything that
  adds a new kind of stack temporary to `bootstrap/neper.c` must allocate it
  through `alloc_temp`, and anything that writes a new outgoing argument must go
  through `emit_argument_lane`; otherwise the measuring pass will not see it and
  the frame will be too small again. Both suites check the invariant.
- The compiled-module format is version 2. Artifacts written by an earlier
  compiler are rejected with `UnsupportedVersion`; delete stale `.em` files
  rather than trying to read them.
- Linker relocation names remain runtime symbols (`neper_os_*`); dependency records
  use source declaration names. Do not collapse those two namespaces.
- The `dependency_reference_name` table must stay aligned with
  `lower.intrinsic_symbol` until a shared representation replaces both tables.
- `neper_mem_alloc` is special: lowering treats it as a compiler-owned generic
  intrinsic, so the current checked-module table has no declaration that can own a
  normal signature edge.
- Windows and Linux are both required for every compiler/library completion claim.

## 12. Suggested continuation sequence

Steps 1 through 4 of the previous sequence are done: the `.em` feature is
committed, both suites are green at `82ea479`, and
`fixtures/link/generic_instances` is a committed regression case for one generic
source module. What remains:

1. Read this file and run `git status --short`.
2. Implement deterministic generic template/instance `.em` **ownership**. Today an
   instance is still owned by the module that declares its template, so a library
   artifact's contents depend on its consumers: emitting the
   `generic_instances` fixture puts all four `dep` instances in `dep.x64-*.em`
   even though only `main` instantiates them. The target contract is that a
   concrete instance is emitted into the instantiating module with module-local
   linkage, that the own linker folds equivalent copies by content hash, and that
   the consumer carries a body-hash edge on the template so a template edit
   invalidates exactly the modules that inlined it.

   The known shape of that change: `check.Function` needs an owner module
   alongside its declaring module; `find_function_instance` must key on owner as
   well as template and arguments, so each instantiating module gets its own
   copy; `instance_id` becomes a per-owner ordinal; the `Checker` needs an active
   owner while an instance body is re-checked, because a template body that
   instantiates another template (`list.from_slice` calling `list.init`) is
   walked in the template's own tree and would otherwise take the wrong owner;
   `lower.module` must lower the instances a module owns while parsing and
   tokenizing the template's module text; and `em.write_dependencies` must emit a
   `dependency_body_kind()` edge on the template instead of the signature edge it
   loses when the instance reference becomes module-local.
3. Add edge invalidation, linker folding, repeated-build, and cross-platform tests
   for that increment, and commit it independently.
4. Consider fixing the shadowing/name-resolution finding in section 7.4.
5. Choose the next prerequisite by dependency order—general protocols before
   `e.data.heap`, floats before `algo.rand`, and core string/path/meta/atomic work
   before the modules that depend on them.
6. Update the machine module plan and progress site only when an exact surface is
   actually delivered and verified.

Do not start M2.5 or M3 during this continuation. The immediate goal remains full,
evidence-backed M2 completion.
