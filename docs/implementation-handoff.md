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
| `e.algo.hash` | `db50fcb` | FNV-1a 32/64, xxHash64 one-shot/streaming, CRC32 one-shot/streaming, Adler32 |
| `e.algo.bitset` | `dcb70dd` | Fixed-length bit sets, tail-bit invariant, algebra, scans, empty-set behavior |
| `e.data.ring` | `c839c80` | Generic fixed ring, wraparound, overwrite, iteration, zero capacity |
| `e.data.deque` | `7420f61` | Generic arena-grown deque, reserve/growth, wraparound, iteration |
| `e.data.list` | `2de9314` | Generic arena-grown list, insert/remove, views, copy, iteration |

Each committed module has exact source-surface checks in both self-host harnesses
and Windows/Linux behavioral coverage. The checker was also corrected so `.len`
is a pseudo-member only for arrays, slices, and strings; ordinary structs can have
a real field named `len`.

Current machine-plan status:

- M2 `surface:"source"`: `e.data.deque`, `e.data.ring`, `e.algo.hash`,
  `e.algo.bitset` (4 of 14 M2 modules).
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

Emitting all compiled modules for a real `e.algo.hash` program previously failed
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
half of `e.data.heap` and the `_by` variants across `e.algo.sort`.

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
and the GPU profile's ban on function pointers. Calling a function value out of a
struct field was wired separately in section 7.11.

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

### 7.9 e.data.heap completed

The `HeapBy` half of the frozen API is declared and `e.data.heap` is `source`. All
22 public declarations are present, in the order `docs/module-apis.md` lists them,
and both suites check that list against the file.

Function values (section 7.8) were necessary but not sufficient. Two further
checker gaps only appeared once `HeapBy` was written:

- Type substitution did not descend into a function type. `HeapBy`'s `cmp` field is
  `fn(*Ctx, T, T) -> i32`, so instantiating the aggregate has to rebuild that
  signature with the arguments bound. Both `substitute_type` and
  `substitute_aggregate_type` now do, through a shared `build_function_type`.
- A declaration and the aggregate it constructs number their comptime parameters
  separately, so `HeapBy[T, Ctx] { cmp: cmp }` inside `init_by[T, Ctx]` compared two
  signatures whose `.TypeParameter` entries had different indices and rejected
  them. `types_may_match_after_instantiation` now compares function signatures
  structurally, which is the same leniency it already gave `Named`, `Pointer`,
  `Slice` and `Array` while a template body is being checked.

The `_by` bodies originally bound `h.cmp` and `h.ctx` to locals before calling,
because a field was not directly callable. Section 7.11 wired that, and they now
call `h.cmp(h.ctx, ...)` where it stands.

`fixtures/link/data_heap` now covers both halves in one program: the supplied `cmp`
over integers, a user struct dispatching to its own declared `task_cmp`, and a
`HeapBy` whose comparison mutates borrowed context, in both orderings, through
`init_by`, `from_slice_by`, `push_by`, `peek_by`, `pop_by`, `clear_by`,
`heapify_in_place_by` and `iter_by`. The fixture asserts the context was actually
reached and written.

### 7.10 e.algo.sort

All seven declarations of the frozen API, in the order `docs/module-apis.md` lists
them, so the module is `source`. It is an M1 module, so this is the second M1
library after `e.data.list`.

It needed no compiler work: sections 7.7 through 7.9 had already delivered
everything it uses. That is the first module this session to compile on the first
attempt.

Algorithm choices, none of which the API document fixes:

- `in_place` and `in_place_by` are heapsort. Every module-scope declaration is
  exported, so a private recursive partition helper would widen the public surface;
  heapsort is iterative, in place, and O(n log n) in the worst case rather than
  quicksort's O(n squared). It is not stable, and nothing claims it is.
- `stable_in_place` and `stable_in_place_by` are bottom-up merge sort over one
  arena scratch buffer, taken and released around a `mem.mark`/`mem.reset` pair.
  Ties go to the left run, which is what makes them stable.
- `radix_u32_in_place` and `radix_u64_in_place` are LSD radix, one byte per pass,
  four and eight passes. Each pass is a counting sort, so they are stable too.

`fixtures/link/algo_sort` covers duplicates and negatives, empty and single-element
slices, already-sorted and exactly-reversed inputs, a user struct dispatching to its
declared `rec_cmp`, a context-mutating comparison in both orderings, and radix over
values with the high bit set that a signed comparison would order wrongly. Two
assertions are worth keeping:

- The stability checks pin the exact sequence numbers within each equal-key run. I
  confirmed separately that heapsort produces a different order on the same input,
  so these assertions distinguish a stable sort from an unstable one rather than
  passing for both.
- The fixture compares `mem.stats` before and after a further `stable_in_place` and
  `radix_u32_in_place`, so a scratch buffer that was allocated but never released
  fails the run.

### 7.11 Calling a function value from a field

`s.cmp(a, b)` now calls the function value in a field where it stands. Previously
only a local or parameter binding was callable, so `e.data.heap`'s `_by` bodies had
to bind `h.cmp` and `h.ctx` first; they no longer do.

`check_call`'s qualified-receiver branch tries the module-qualifier lookup first and
falls back to typing the receiver expression: if it is a function type, the call
becomes indirect with the field load as its callee. Ordering matters -- a module
qualifier keeps winning, so nothing about qualified calls changes. Lowering needed
no work, because `lower_call_arguments` already lowers the receiver expression for
an indirect call and a field load is an ordinary expression.

One thing this turned up. `o.cmp(a, b)` and `let f = o.cmp` followed by `f(a, b)`
lower to byte-identical code, relocations included, so the own linker folds them
into one body. `fixtures/link/function_values` covers both forms, and its second
one reverses its arguments deliberately: with identical bodies the fold makes the
artifact link smaller than the direct link, and the fixture's byte-identity
assertion stops holding. That assertion is only meaningful while no two functions
in the fixture fold together, which is worth remembering when adding to any fixture
that makes it.

### 7.12 Enum ordering, and the supplied `cmp` for enums

An enum orders by its backing integer, and only the backing integer says whether
that ordering is signed. Codegen decides comparison signedness from the operand
value's type, which for an enum is the named type -- it carries no signedness and
no route back to the aggregate, because a non-generic `.Named` leaves `has_element`
false. So every enum comparison used the signed condition codes. On a `u64` enum a
member above `2^63` reads as negative and orders below every other member:
`Big.Low < Big.Huge` was false. This was wrong in committed code, on both
platforms, and the reason section 7.7 left the enum `cmp` fallback out.

The resolution happens in lowering, which has the checker. `check.enum_backing_type`
maps a named type to its enum's backing integer; `lower.coerce_ordering_operand`
emits a `Cast` to that type ahead of each operand of `<`, `<=`, `>` and `>=`, and
ahead of the two comparisons inside `emit_supplied_cmp`. Codegen then reads an
ordinary integer type and picks the condition it already picked correctly for
integers. Its only change is to accept a `.Named` source for `Cast`, taking the
width and signedness from the target, which lowering has already resolved.

With ordering correct, `supplied_protocol` adds the enum shape to `cmp`, so
`T.cmp` works on an enum with no declared `fn <t>_cmp`. `fixtures/link/enum_ordering`
covers a `u64`, a `u8` and an `i32` enum through both the operators and `T.cmp`;
its `u64` assertions all fail under a signed comparison.

Negative enum members, which this turned up, are section 7.13; arrays, slices and
`str` are section 7.16. Rule 4's remaining `cmp` shapes are floats, vectors and
tagged unions; `hash`, `eq` and `format` are untouched.

### 7.13 Negative enum members

A negative enum member did not lower at all. `check.e` collected it correctly --
the magnitude and an `enum_negative` flag, range-checked against the backing type,
auto-incrementing up through zero, and serialized in `.em` -- but all three places
in `lower.e` that turn a member into a constant refused `enum_negative` outright
or would have emitted the bare magnitude. `Under` in `enum i32 { Under = 0i32 - 3i32 }`
was rejected with the generic "construct is not implemented in self-hosted lowering".

A member is stored as its backing integer's bits, so a negative one is its two's
complement at the backing width. `check.enum_member_bits` computes that as
`(mask - magnitude) + 1` rather than `2^width - magnitude`, which overflows a
`usize` at width 64. The member expression, `store_tag` and the tagged-union
switch case all go through it.

The register form follows from what was already there: an enum load has no
signedness (`signed_integer` is false for a `.Named` type), so it zero-extends the
backing width, and the constant is the truncated two's complement -- the two agree
bit for bit, which is what `==` and `switch` compare. Ordering is section 7.12's
cast to the backing type, which sign-extends both sides before the comparison.

`fixtures/link/enum_negative` covers `i8`, `i32` and `i64` backings at both
extremes, auto-increment walking -3 up through 0, `==`, ordering, `switch`, and
`T.cmp`.

Two things this ran into, neither of them about enums:

- The most negative value of a backing type cannot be written directly, because
  `128i8` is out of range for `i8` and there is no unary minus. `0i8 - 127i8 - 1i8`
  reaches it through constant folding, which is what the fixture uses.
- `let zero = ...` was rejected with a position-less `error: parse.InvalidSyntax`.
  Section 7.14 fixed that.

### 7.14 Positioned syntax diagnostics

No syntax error had a position. `parse.parse` returned a bare `InvalidSyntax`,
`graph.collect_imports` propagated it, and the four CLI commands that load a graph
let it reach the runtime, which printed `error: parse.InvalidSyntax` and nothing
else -- no file, no line, no token. Every other pass already reported properly;
parsing was the one that did not.

`parse.Tree` now carries `failure_token`, `failure_reserved_name` and
`has_failure`, recorded by `parse.record_failure`. The first declaration to fail
wins and is then frozen on the parser, so recovering past it cannot move the
position the reader has to look at; within a declaration the earliest record wins,
which is the token the parser stopped on. Three places record: the top-level item
failure in `parse_file`, and the two in-block statement recoveries, which count an
error without the enclosing declaration failing -- missing those was why the first
attempt still reported nothing for a dangling operator inside a function body.

`graph.Graph` carries the same three fields plus `failure_module`, set in
`collect_imports`, which is where every module is parsed first and so the only
place a syntax error is seen with its module still in hand. `main.load_graph`
wraps `graph.load` at all four call sites and prints
`path:line:column: error[E-SYNTAX-9999]: unexpected <token>`. The `parse` and
`parse-file` commands report the same way.

The reserved-binding case is the one reason worth naming, because a keyword reads
as an ordinary name and "unexpected `zero`" explains nothing. `parse_binding_node`
(both the single and the tuple form) and `parse_parameter_node` record
`failure_reserved_name` when `lex.is_keyword` says the token in a name position is
a keyword, and the report becomes
`` `zero` is a keyword and cannot name a local or parameter `` under E-NAME-0003 --
the same code and wording shape as the existing `reserved_local` case for `u8`,
which is a reserved identifier rather than a keyword and so already reached
`resolve.add_local`. `lex.is_keyword` re-derives the answer through `lex.keyword`
rather than keeping a second list, so it cannot drift from the keyword table.

Fixtures `scope/reserved_binding_let` and `scope/reserved_binding_parameter` pin
the two reserved cases; the `graph/invalid` and `parse` assertions in both runners
now pin the generic form, and the graph one also pins that the report names
`broken.e`, the imported module holding the error, rather than the root.

Two things worth knowing:

- `tree.failure_token = zero` does not check: assigning the zero literal to a
  struct-typed *field* is not supported, only to a declaration. The bootstrap
  accepts it, so this only appears when the self-hosted compiler checks its own
  source. Both sites use `var no_token: lex.Token = zero` and assign that.
- The first version named the `is_keyword` parameter `token`, which shadows
  `lex.token`. Section 5's own rule caught it, through the same diagnostic path
  this session added earlier.

### 7.15 `docs/llm-mcp-server.md`

`docs/docs_llm-mcp-server.md` was untracked, referenced by nothing, carried a
`docs_` prefix that reads as a download artifact, and declared itself a "normative
extension to `docs/spec.md` and `docs/tooling.md`" -- authority no other file in the
set grants it, and which contradicts `spec.md`'s own preamble, where the post-M2
design revision changes no current rule until versioned amendments land in M2.5.

It is renamed to `docs/llm-mcp-server.md`, tracked, and re-statused as a proposal.
The body is unchanged; the whole edit is the Status block. That block records the
three open points of contact with the adopted set, which is the substance of why it
could not stand as written:

- `neper patch` conflicts with R11/H29, which demotes byte spans to the lossless and
  trivia cases and requires a snapshot precondition the proposed payload lacks.
- `neper header` overlaps R05, the retrievable API catalogue, under another name.
- The section 5 targets are unadopted numbers; R03 owns token-cost measurement and
  R07 owns the evidence gate.

Sections 1-3, the MCP server itself, are the part with no counterpart elsewhere. It
is a client over `neper index --json`, `neper parse --json` and `neper check`, so it
needs an owning milestone rather than a place in the specification.

`post-m2-llm-hardening.md` now names it, which is the right host: the file is a
proposal for the M2.5 gate, and that document is the gate. `tooling.md`, the other
candidate, was uncommitted work in another session's hands (section 8), and this tree
is shared rather than branched, so editing it would have raced that session.

### 7.16 The supplied `cmp` for arrays, slices and `str`

Spec section 9 rule 4 says arrays, slices and vectors recurse in index order.
That is now supplied, for arrays, slices and `str`, with the shorter sequence
ordering first where the common prefix matches -- the rule does not spell out
unequal lengths, and lexicographic order is the only reading consistent with `eq`
being over contents.

`check.supplied_cmp_shape` replaces the flat list in `supplied_protocol` and
recurses through the element type, so `[]i64`, `[]u8`, `str`, `[3]i32`,
`[]Level` for an enum, `[2][3]i32` and `[2][]i64` all have one. A depth bound of 8
guards against a pathological alias chain; no honest type reaches it.

Lowering splits into four pieces where there was one inline emitter:

- `emit_scalar_cmp` is the old body, minus the slot allocation and the final load.
  The caller now owns the slot; every path stores, and the builder is left on a
  fresh block. The enum coercion from section 7.12 moved in here, so it applies to
  an element as well as a receiver.
- `emit_sequence_cmp` emits the loop. `sequence_parts` gives the data pointer and
  length -- an array is its own storage with a static length, a slice and a `str`
  are the {pointer, length} pair, which is also exactly how one sits inside an
  enclosing sequence, so nesting needs no special case. The loop runs while the
  index is below *both* lengths (two comparisons and a `BitAnd` on bools, which
  avoids a min branch), compares elements through `emit_cmp_into`, and carries the
  first non-zero result out. Falling off the end means the prefix matched, and the
  tail compares the two lengths through `emit_scalar_cmp` -- which for two arrays
  of one type is the equal case and stores zero.
- `element_operand` passes an element the way the rest of lowering does: an
  aggregate by address, everything else loaded.
- `emit_cmp_into` dispatches, and is what makes the recursion mutual.

`fixtures/link/sequence_cmp` covers `[]i64`, `[]u8` (where 200 against 3 pins the
unsigned element comparison), an enum element, empty and prefix slices, `[3]i32`,
`str`, and the two nested shapes.

An element with a *declared* `fn <t>_cmp` is section 7.17, tagged unions are
section 7.18, and the supplied `hash` is section 7.19. That leaves `cmp` for floats
and vectors, blocked on scalar floating point and on vectors existing at all, and
`eq` and `format` entirely.

### 7.17 An element that declares its own `cmp`

`[]Point` where `Point` declares `fn point_cmp` reported `ProtocolMissing`: the
element was `.Named`, which had no supplied shape, and the loop body only knew how
to emit an inline comparison. It now emits a call.

`check.element_cmp_function` resolves and validates the declaration, and
`supplied_cmp_shape` accepts an element that has one. Validation is stricter than
`check_protocol_call`'s, which checks only rule 3's first parameter: the
synthesized call is never re-checked anywhere, so the declaration has to be exactly
two parameters of the type and one `i32` back before it will be called. A receiver's
own `cmp` never reaches this path, because `check_protocol_call` resolves a declared
one before any fallback is considered.

`lower.emit_declared_cmp` is short, because rule 3 lands on the shape a direct call
already has. The receiver is by value, which for an aggregate is its address --
exactly what `element_operand` supplies, and exactly what an ordinary call passes,
since `captured` is false for everything but a deferred call. A single `i32` return
is a register return, so `call_return_layout`'s slot path is not involved. The
`nir.intern_function` reference is also what gives the artifact its dependency edge:
`em.write_dependencies` walks `builder.function_refs`, so a call synthesized during
lowering is indistinguishable from one the checker saw.

`fixtures/link/element_cmp` is two modules, so the call crosses a module boundary.
Its `tag_cmp` reverses deliberately -- larger id orders first -- so a comparison
that failed to reach the declaration would order the other way rather than merely
failing to compile. Both runners also emit the artifact set, assert the
`main -> shapes` edge with `check-em-edge`, link from artifacts and run the result.

One rough edge left, and it is a diagnostic rather than a behavior. A `<t>_cmp` that
exists but does not match the strict signature makes the element shape unsupplied,
so `[]Point` reports `ProtocolMissing` on the sequence rather than
`ProtocolSignature` on the element. `Point.cmp(p, q)` on its own still reports the
precise error, so the information is reachable, just not from the sequence.

That machinery is what section 7.18 builds the tagged union on.

### 7.18 Tagged-union `cmp`

Rule 4 orders a tagged union "in declaration order, including the tag before the
live payload". `check.tagged_union_comparable` accepts one whose every non-void arm
is comparable, through `comparable_component`, which is now the shared answer to
"can this thing be compared" for a sequence element and a payload arm alike: a
shape rule 4 supplies, or the component's own declared `cmp`.

`lower.emit_tagged_union_cmp` compares the two tags through `emit_scalar_cmp` and
branches out if they differ -- the slot already holds the answer. Where they match,
it walks the arms in declaration order emitting a `tag == constant` test per arm
with a payload, each falling through to the next, and the arm that matches compares
its payload through `emit_cmp_into`. Arms with a void payload get no test; they
fall to the default arm, which stores zero, which is also the right answer for
them. `layout.field` supplies both halves of the addressing -- `"tag"` gives offset
zero and the backing type, an arm's own name gives its payload offset and type --
so nothing here recomputes a layout. The arm constants come from
`check.enum_member_bits` (section 7.13), so a negative tag would encode correctly
even though nothing can currently declare one.

Block bookkeeping is the only awkward part. A test and its body are created in
pairs, but a body may contain nested blocks from the payload comparison, so the
next test's index is not predictable from the previous body's; the four fixed
arrays hold each arm's test, decision, body and exit, and everything is patched
after the merge block exists. Thirty-two arms is the cap and returns `Capacity`.

`component_at` replaces what `emit_sequence_cmp` was doing inline for its element:
`FieldAddress` plus a load for anything that is not an aggregate. Sequences index,
tagged unions offset, and both then want the same thing.

`fixtures/link/tagged_union_cmp` covers a four-arm union with a void arm, an `i64`,
a `str` and a `[]i64`: tag ordering across every pair, two void arms equal, payload
ordering within each arm, a payload that is itself a sequence, and `[]Node` -- a
sequence *of* tagged unions, which exercises the recursion in both directions. A
negative control confirms the payload assertions fail when flipped.

### 7.19 The supplied `hash`, and a new host intrinsic

Rule 4 fixes the supplied `hash` as **xxHash64 with seed 0** over a value's
canonical little-endian bytes. Unlike `cmp`, which is comparisons the compiler
already emits, this needs an implementation the compiler did not have. Three
options were live -- a host runtime symbol, emitting xxHash64 inline as NIR, or an
implicit dependency on `e.algo.hash` -- and the runtime symbol was chosen: it is the
pattern `neper_mem_*` and `neper_os_*` already follow, it needs no module-graph
machinery, and one implementation serves every shape.

`neper_hash_bytes(ptr, len) -> u64` is therefore in all three runtimes: C in
`bootstrap/runtime.c`, GNU-as Intel syntax in `runtime_elf_x64_ext.s`, MASM in
`runtime_pe_x64.asm`. Both assemblers take Intel syntax, so the instruction text is
one body differing only in directives, label prefixes and the ABI move that puts
the two arguments in `r8` and `r9`. The C form was written first and checked
against `e.algo.hash.xxhash64` over sixteen inputs covering every tail path (0, 1, 2,
3, 4, 5, 7, 8, 9, 15, 16, 17, 31, 32, 33 and 65 bytes); each assembly port was then
checked against the C by linking it into the same harness. All four agree, and the
empty and `"abc"` values match upstream xxHash64's published constants.

The C copy is not yet reachable: the bootstrap compiler does not implement protocol
lookup, so nothing it compiles can call the symbol. It is there because it is the
reference the two ports were validated against and because a runtime missing a
symbol the compiler may emit should be a link error rather than a surprise later.

On the compiler side `ProtocolBuiltin` gains `Hash`, `supplied_protocol` dispatches
on the protocol name rather than assuming `cmp`, the builtin's parameter count now
comes from `supplied_protocol_parameters`, and `call_return` types the call `u64`.
`check.supplied_hash_shape` admits integers, `bool`, `err`, pointers, enums, arrays
of those, and slices and `str` whose element is one of those. That set is exactly
the one whose canonical bytes are already contiguous in memory, which is why
`lower.emit_supplied_hash` is a single call: for those shapes the recursion rule 4
describes *is* the memory, so hashing the whole run in one pass gives the same
answer as walking it. A scalar has no address of its own and is spilled to a slot
to get one.

Not supplied, and the reason is the same one: a nested slice's bytes are a pointer
rather than its contents, and a tagged union's payload is padded. Both need the
streaming form of xxHash64 -- init, update per component, done -- rather than one
call, which is the next increment and would reuse `emit_cmp_into`'s dispatch shape.

Two things this broke, both pre-existing and neither about hashing:

- `em_link.assemble` required every relocation to resolve to a function in the
  artifacts. Host runtime symbols cannot, and none had ever reached it, because no
  fixture linked a compiled module that called one. The supplied `hash` is the
  first. Those are now left to `link_pe` and `link_elf`, which own the per-target
  symbol tables and reject a name neither knows -- the division the direct path
  already used. `fixtures/link/supplied_hash` links from artifacts to pin it.
- Both linker `self_test`s were golden-value tests over absolute file offsets, so
  growing the runtime by 564 bytes broke them. They now compute every offset that
  sits after the runtime from the layout, and check the values that move with it --
  the idata address, the import-address-table address, the first import thunk's
  patched displacement, the import directory's first name RVA -- as relations
  rather than literals. Two of the old literals were coincidences worth recording:
  the constant at offset 168 is 4096 because it is the section alignment, not
  because it equalled the text virtual size, and the bytes at 548 are a *patched*
  displacement, not static runtime content.

## 8. Working-tree boundaries

No compiler or test change is intentionally uncommitted now. Everything in
section 7 is committed.

The following changes predate that work and must be preserved and handled as a
separate documentation/design/site effort:

```text
 M benchmarks/llm_edit/README.md
 M docs/general-purpose-verification.md
 M docs/roadmap.md
 M docs/tooling.md
 M docs/ui-framework.md
?? scripts/render_module_apis.py
```

The `DECISIONS.md` to `docs/decisions.md` case/path move is finished: `DECISIONS.md`
is deleted, `docs/decisions.md` is tracked, and both sides are committed. The former
`README.md`, `docs/module-apis.md`, `docs/modules.json`, `docs/modules.md` and
`docs/spec.md` edits are committed too, as are `docs/post-m2-llm-hardening.md` and
`docs/stdlib-hardening.md`. Nothing in that move is still pending.

### Build output layout

Build outputs live under one ignored `build/` tree, split by target platform:

```text
build/windows/    MSVC output: neper.exe, neper-self.exe, runtime-embed/, tests/
build/linux/      cc output:   neper, neper-self, lib/, tests/
```

This replaced the earlier sibling `build/` and `build-linux/` directories on
2026-09-06. `.gitignore` now needs the single entry `/build/`. The paths are named
in `scripts/build-bootstrap.{ps1,sh}`, `scripts/build-selfhost.{ps1,sh}`,
`scripts/embed-pe-runtime.ps1`, `scripts/embed-elf-runtime-ext.ps1`, the three
`tests/*/run.ps1` and the three `tests/*/run.sh`, and in `README.md`. Both halves
are fully regenerable -- `scripts/build-selfhost.ps1` rebuilds the Windows chain
from `bootstrap/neper.c` and `src/` (it needs MSVC via `NEPER_VSDEVCMD` or
`vswhere`), `scripts/build-selfhost.sh` the Linux one -- so neither directory holds
an input that exists nowhere else, and either may be deleted whole.

### Scratch and packaging work products, removed 2026-09-06

The scratch, rendered and site-packaging files this section used to list are gone.
Each was confirmed untracked and either regenerable or already superseded before it
was deleted:

```text
.tmp-debug-launch.obj         .tmp-linux-runtime.bin    .tmp-linux-runtime.o
.tmp-linux-startup.bin        .tmp-linux-startup.o      .tmp-runtime-ext.bin
neper.obj                     vc140.pdb                 readme-pdf.patch
neper-progress-site.tar.gz    progress-site-*.tar.gz    site-package-stage-20260905/
package-site.sh               prepare-site-build.cjs    .tmp-sites-packager/
```

`readme-pdf.patch` had already been applied -- its text is in `README.md` and
`scripts/build-docs-pdf.{ps1,sh,py}` exist -- and it no longer applied cleanly.
`docs/module-apis.pdf` is likewise absent; `scripts/render_module_apis.py`
regenerates it from `docs/module-apis.md`. The six `dist/` tarballs and the staging
directory were builds of `progress-site` commits that are all still in that
repository's history.

`package-site.sh` and `prepare-site-build.cjs` -- the two-file packager that turned
`progress-site` into a deployable `dist/` tarball, checked for
`.openai/hosting.json` and folded in `drizzle/` -- were untracked everywhere and no
copy survives. Producing a site archive again means writing that step from
`progress-site`'s own `package.json`, `vite.config.ts` and `.openai/hosting.json`.

### What is deliberately still here

`progress-site/` is a self-contained git repository: ten commits, clean tree, no
remote and no upstream. It is the only copy of the progress site source, and the
source every deleted tarball was built from. Do not delete or clean it. It needs a
remote.

## 9. Remaining M2 libraries and blockers

The machine plan currently has ten planned M2 modules:

| Module | Immediate prerequisite or implementation gap |
| --- | --- |
| `e.data.heap` | delivered, `surface:"source"` (section 7.9) |
| `e.algo.sort` | delivered, `surface:"source"` (section 7.10). An M1 module, not one of the ten M2 rows |
| `e.algo.rand` | Exact API includes `f64`; scalar float lowering and ABI support are incomplete |
| `e.algo.uuid` | Depends on `e.algo.hash` and source-complete `e.str`; `e.str` is not source-complete |
| `e.fs` | Depends on complete `e.path`, `e.str`, memory, and filesystem `e.os` behavior |
| `e.proc` | Depends on cancellation, memory, process OS calls, and time semantics |
| `e.sync` | Depends on complete atomics plus OS wait/wake and time behavior |
| `e.channel` | Depends on `e.sync` and memory ownership/concurrency contracts |
| `e.fmt.json` | Depends on complete `e.io`, `e.mem`, `e.meta`, and `e.str` |
| `e.fmt.csv` | Same reflection/string/I/O prerequisites as `e.fmt.json` |
| `e.fmt.ini` | Same reflection/string/I/O prerequisites as `e.fmt.json` |

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
   `e.algo.rand` and the M1 CPU language.
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
- `scripts/check_module_plan.py` is confirmed and tracked: `python
  scripts/check_module_plan.py` validates `modules.json` against `modules.md` and
  `module-apis.md`, taking an optional `--root`, and it caught two real mid-edit
  mismatches during the namespace work. `tests/test_module_plan.py` is its regression
  suite and is tracked alongside it.
- `test_package_blocker_schema_matches_policy` reads
  `docs/schemas/neper-v1.schema.json` and asserts a `blocked_by` pattern that admits a
  dotted module name. The committed pattern was `^[a-z][a-z0-9-]*$`, which cannot match
  `e.db`, so the test was green only against the schema edit sitting uncommitted in the
  working tree; that one line is committed with it. That pattern, and the four others in the same
  schema governing tier lists, module names, `direct_dependencies` and module
  `blocked_by`, all still admitted `algo|text|crypto|fmt|gfx|ui` as roots after D87
  consolidated them away; all five are narrowed to `e`. The schema now rejects a
  pre-consolidation name such as `algo.hash` instead of silently accepting it, and all
  626 values those patterns govern in `modules.json` still validate.
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
   `e.data.heap`, floats before `e.algo.rand`, and core string/path/meta/atomic work
   before the modules that depend on them.
6. Update the machine module plan and progress site only when an exact surface is
   actually delivered and verified.

Do not start M2.5 or M3 during this continuation. The immediate goal remains full,
evidence-backed M2 completion.
