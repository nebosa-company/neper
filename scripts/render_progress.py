# -*- coding: utf-8 -*-
"""Render docs/progress.html from the roadmap rubric and the module plan.

Usage:  python scripts/render_progress.py     (from the repository root)

The three readiness numbers are computed, never typed: the compiler and
tooling scores come from the tables below, the module score is read out of
docs/module-apis.md, docs/modules.json, committed lib/e sources and the
intrinsics seeded in src/resolve.e.
"""
import json, re, subprocess, datetime
# Readiness rubric, rendered into docs/progress.html by this script.
# Each item scores 1 (delivered), 0 (not started), or a fraction (partial).
# Update these tables when a capability lands, then re-run this script.
compiler = {
 "Front end and language": [
  ("Lexer over the closed token registry", 1, "src/lex.e"),
  ("Parser and syntax tree", 1, "src/parse.e; a grouped return value may carry a binary operator (D247) -- after `ret` the tuple `ret (a, b)` and an ordinary `(expr)` are told apart by a scanner-copy lookahead for a comma at depth one, pinned by link/ret_group"),
  ("Module graph and import resolution", 1, "src/graph.e"),
  ("Order-independent name resolution", 1, "src/resolve.e"),
  ("Integer arithmetic, bitwise, shifts, division", 1, "link/bitwise, link/shifts, link/division"),
  ("if / while, break / continue, block scopes", 1, "link/control; `else if` chains lower as the nested if they are (D245), pinned by link/else_if"),
  ("when over target.arch / target.os", 1, "Section 6's conditional compilation (D216): `when` takes a condition over `target.arch` and `target.os` compared with their members, under `!`, `&&`, `||` and parentheses, settled at compile time; both blocks type check and the taken one is emitted; any other condition is a bool the interpreter evaluates (D220), and one it cannot is refused under E-COMPTIME-9999 (link/when_target on both platforms, check/when_condition). `target.arch` and `target.os` are values of `target.Arch` and `target.Os` anywhere (D223): compared, switched over exhaustively, held and passed"),
  ("for over ranges, arrays and slices", 1, "tests/neper0"),
  ("Fixed arrays, zero / undef, .len", 1, "link/storage"),
  ("Slicing and mutability propagation", 1, "link/storage"),
  ("Structs: layout, literals, field places", 1, "link/aggregate"),
  ("Pointers, & / *, *const, auto-deref", 1, "link/aggregate"),
  ("Aggregate copies and ABI pass / return", 1, "link/advanced"),
  ("Enums, bare unions, union enum", 1, "link/variants"),
  ("switch, exhaustive and non-fallthrough", 1, "fixtures/variants"),
  ("defer, both forms", 1, "tests/neper0"),
  ("err / try / ok and named errors", 1, "link/error_collision"),
  ("Multi-return and destructuring", 1, "link/scalar"),
  ("const and integer comptime folding", 1, "link/generic_folding"),
  ("Generic functions [T: type], [N: usize]", 1, "link/generic_instances"),
  ("Generic aggregate types", 1, "link/generic_same_name; check/generic_instance_field and link/generic_instance_alias pin one used as a field type, named directly and through an alias; link/data_iter pins a nested instance as a type argument -- `Filter[Map[Iter[i64], i64, i64], i64]` -- which read its inner argument as the outer's until the argument block was claimed before it was filled (D145)"),
  ("Protocol resolution, spec 9 rules 3 and 5", 1, "check/protocol_*"),
  ("Iterator protocol <t>_next", 1, "tests/neper0; link/data_iter calls it through a type parameter as `I.next(&it)`, on a generic iterator whose `_next` is instantiated from the receiver's own arguments (D145)"),
  ("Supplied cmp (rule 4)", 1, "link/sequence_cmp, tagged_union_cmp"),
  ("Supplied hash (rule 4)", 1, "link/supplied_hash, folded_hash"),
  ("Supplied eq (rule 4)", 1, "link/supplied_eq; link/test_assert pins the floats, which rule 4 always listed and the compiler had not supplied: every NaN equals every other and the two zeros are one (D142)"),
  ("Supplied format (rule 4)", 1, "link/str_format, link/io_printf expand scalars, str, bool and err; slices and arrays recurse an element at a time as `[a, b]`, nesting included (D189); an enum prints its variant name (D190); a type's own `<t>_format` is called with the builder, inside a sequence too (D191); check/format_compound_argument pins the struct without one"),
  ("Scalar floating point f32 / f64", 1, "link/float_scalar; f16 / bf16 still unlowered. link/math_exact pins `math.sqrt` as the one float intrinsic -- `sqrtss`/`sqrtsd` behind a NIR opcode of its own, correctly rounded and checked by its bits (D146). `fma` is exact by integer arithmetic on the significands, and the thirteen transcendentals are fdlibm's over f64 with a Payne-Hanek reduction of its own, each measured within 1 ULP against mpmath at 200 bits in the four link/math_* fixtures (D147)"),
  ("Vec[T,N] / Mask[T,N] and SIMD lowering", 0.7, "`Vec[T, N]` and `Mask[T, N]` are builtins seeded into e.simd with section 4's closed table, width-aligned layout and `meta.kind/element_type/array_len` answers; every `simd.*` intrinsic but `shuffle` is library source lowered lane by lane over scalar code (D148); section 4's operator table -- IEEE `+ - * /` on float lanes, only `+% -% *%`, the bitwise ones and a scalar shift on integer lanes, `& | ^ ~` on masks -- is checked and lowered lane by lane, plain `+` on integer lanes and every comparison refused (D158); `Vec[T, N]{ ... }` is N positional lanes and `v[i]` reads or writes one, bounds-checked (D159); `shuffle`'s `IDX: [N]u8` is a comptime array parameter, bound from a literal of literals and forwardable by name (D160). Not yet: the mask register-only rule and a vector register class with SSE/AVX selection"),
  ("Atomic[T] and memory orderings", 1, "link/atomic_ops runs all thirteen across every width and both signs; link/atomic_threads proves the lock prefix under contention; check/atomic_* pin the ordering rules. e.sync and e.channel are unblocked"),
  ("extern with @import / @cc and the C ABI", 1, "link/extern_import binds and calls foreign symbols on both platforms: a PE import directory with one descriptor per library, and a dynamic ELF with PT_INTERP, DT_NEEDED and GLOB_DAT slots. It also pins a narrow signed return being widened, which the convention leaves undefined above the declared width -- an unwidened -1 read as 0xFFFFFFFF made every `< 0` check on a foreign call pass. Section 5's closed table of which types cross is enforced at every extern declaration (D192): check/extern_slice_parameter and check/extern_slice_return pin a slice and a tagged union refused. A trailing `...` is a C variadic (D193): link/extern_variadic prints through snprintf with an f64 past the fixed parameters on both conventions, and check/variadic_narrow_argument pins that an i16 there is refused rather than promoted"),
  ("Checked optimized builds and unsafe boundaries (M2.5 H03)", 0.76, "A release build keeps `bounds`, `null`, `tag` and `align` (D355, `m25-h03-checked-release.md`); `@nocheck` is the explicit unchecked operation in every mode and `--unchecked` the whole-image one; the manifest lists every `@unsafe` function and `@nocheck` block and the check policy; a fixture traps in release on all three memory rows; the first bounds proof (`while i < x.len`, D356) its guard form (`if i < x.len`, D377), its conjunct form (the leftmost `i < x.len` of an `&&`, D378) its early-exit form (`if i >= x.len { ret }` proving the rest of the block, D380) the width proof (a `u8` widened, a literal mask or offset into an array of known length, D384) the slack form (`while at + K <= x.len` proving `x[at + j]`, D385) and its early-exit form (`if at + K > x.len { ret }`, D387; 476 checks elided in the compiler's own build) with their eliminated and retained fixtures and a `--stats` count, which also found and closed the inlined bodies' lost checks. Not yet: proofs through a second local or a field base (the compiler's commonest guard), `invalid` in release, definite initialization of fields, the load/store audit; cold wall +16-29% and image +40% against budgets of +10%/+5%"),
  ("Reproducible performance gate (M2.5 H25)", 0.6, "Registered workloads, budgets and rendered reports (D338, `m2-baseline.md`); `benchmarks/baseline/gate.py` judges a measurement cell by cell against the budgets and exits 1 on a breach (D366) -- twelve named on the D351 measurement, twenty on the D382 one and the causes found in the phase split (D383: two scans fixed, D355's retained checks named as what stands; D386: a profile of the compiler building itself found a quadratic slot walk, cold -14%; D387: the warm build's byte sinks copy whole through the intrinsic memcpy, cold 619 ms). Not yet: the gate in the suites, Linux measurements after the baseline, the H25 report"),
  ("Unsafe boundaries enumerable (M2.5 H27)", 0.8, "The build manifest's `unsafe` array lists every `@unsafe` function and `@nocheck` block (`provenance: declared`) and every `extern fn`, `mem.cast`, `mem.bitcast` and bare `union` site (`provenance: trusted`) with module, function and line, read off the modules' bytes so warm builds list them too, and `options.checks` says the policy (D355, D371); the corpus fixture `manifest_unsafe` holds all six kinds. Not yet: raw dereference sites (the checker's, not the bytes'), the index marking them, `--unchecked` images as one boundary in the context records, artifact-only modules"),
  ("Diagnosis, recovery and transactional repair (M2.5 H09)", 0.45, "Every two-site E-SAFETY diagnostic carries its other site -- acquisition, move, deferred call, borrow, pointer, reset, mutation, thread start -- as a `related` span with a message saying which (D364), pinned by the reject corpus; stable codes throughout; the parser's nesting bound and error nodes are D341's; a forgotten cleanup carries its `defer <closer>(x)` and an untested acquisition its `if e != ok { ret e }` as `fixes` entries (D381, D382), and a rename is a plan with preconditions (D376). Not yet: fixes for the type and name codes, cascades grouped under a primary cause, expected/actual as fields, instantiation chains, lossless recovery beyond D341"),
  ("Declaration-level incremental semantic work (M2.5 H14)", 0.35, "Module-level reuse with structured reasons (D363): the build manifest's `incremental` array says per module whether it was kept or rebuilt and why -- stable, edges-hold, edge-changed, source-changed, mode-changed, no-artifact -- asserted by both suites on a warm build and a body edit; a comment-only edit to the compiler rebuilds one module and keeps the rest by their edges. Not yet: reuse inside a rebuilt module, the counts of declarations rechecked and functions emitted, trivia separated from semantic identity, the fallback and comptime fixtures"),
  ("Semantic search and safe change planning (M2.5 H17)", 0.45, "`uses-file --json --symbol module.name` (D362): every use the checker resolved -- calls of the function and its instances, dispatches that chose it, instantiations, its name as a value -- with the enclosing function and span, the roots that keep it alive, the count of calls through values that no name can trace, and a completeness flag; the contract says what a safe-delete claim and a rename plan may conclude. A rename is a plan with file-hash preconditions and a re-check postcondition, applied by nothing but the harness (D376). Not yet: field and address relations, ownership and borrow uses, signature-change plans, moves and error renames, the shadowing and alias fixtures"),
  ("GPU contracts frozen before M3 (M2.5 H13)", 0.4, "Design only (`m25-gpu-contracts.md` section 1, D367): the CPU/device mapping of H01-H09 -- `*Device` and `Buf[T]` as resources, the device as a region, the H03 policy on the device as fault records reported by `sync`/`download` as `gpu.Fault`, address spaces per profile, specialisation provenance, E-GPU codes, context facts -- with named M3 fixtures. Runtime evidence pending: nothing executes; the H01 closer extension is undelivered"),
  ("Explicit CPU/GPU dependency composition (M2.5 H21)", 0.35, "Design only (`m25-gpu-contracts.md` section 2, D367): tokens naming past submissions (no cycle expressible), state tables for tokens and buffers, conservative whole-buffer use tracking with cross-queue release waits, the failure table with no cancellation in v1, the D83 discovery contract frozen, the H18 requested/selected record, nine named M3 fixtures. Runtime evidence pending"),
  ("End-to-end GPU cost and artifact lifecycle (M2.5 H22)", 0.3, "Design only (`m25-gpu-contracts.md` section 3, D367): the timeline record with two clocks never subtracted and instrumentation apart, the cache-key matrix with safety and numerical policy in the key, the bounded staging pool that waits rather than grows, cold/warm defined, and the list of what M3 implements. Runtime evidence pending; batching, graphs, the pinned path and an optimised CPU backend are separate deliveries"),
  ("Executable numerical and capability contracts (M2.5 H23)", 0.35, "Design only (`m25-gpu-contracts.md` section 4, D367): spec section 10's bit-identity claim corrected to subgroup-independent kernels or a matching width, section 11's denormal rule corrected to a required inferred `.DenormPreserve` with the execution mode emitted, the per-operation matrix with oracles, the launch-precondition table, nine named fixtures. Runtime evidence pending: the CPU cases execute in M3's first week"),
  ("Hostile inputs, artifact integrity and aggregate limits (M2.5 H24)", 0.5, "Every artifact read is checksum-validated once at load and layout-validated by each reader (D213, D320); `benchmarks/fuzz/fuzz.py` mutates every fixture source and artifact and found nothing in 33k runs, and expression nesting is bounded at 128 levels (D341); artifacts are published by one atomic replace and a damaged cache is rebuilt to the clean image, both suites (D343); an escaped resource limit is E-TYPE-9999 (D344); a corrupt artifact named on the command line is E-LINK-0001 and a damaged cache entry says `invalid-artifact` in the manifest (D368). Not yet: content integrity for imported artifacts beyond the CRC, whole-build budgets across workers and instantiations, fault injection into the cache writes, cyclic artifact references as a fuzz target"),
  ("Immutable snapshots and correct cache identity (M2.5 H15)", 0.3, "Artifacts carry format version, target triple, build mode, source hash and interface/body hashes, and a mismatch is a miss (D205-D214); published by one atomic replace (D343); `--unchecked` is its own mode byte, so a warm build over the other policy's artifacts rebuilds every module as `mode-changed` and is the clean image, both suites both ways (D369). Not yet: `--inline-cap` and CPU features in the identity, the compiler's own hash in the artifact, in-memory overlays, snapshot identifiers on query results, the transaction boundary, collision verification beyond xxHash64"),
  ("Compilation policy and generated-code performance (M2.5 H20)", 0.45, "Three policies, each a build identity and named in the manifest: debug, release with the memory checks retained, release `--unchecked` (D355, D369); the forty-instruction cap re-evaluated on the 500k-line workload and retained, `--inline-cap N` and `--explain` giving every inlining decision its reason (D346); the bounds proof and the `--stats` rows for elided checks and by-value copies (D356); measured budgets and the gate (D338, D366). Not yet: explanation records in the JSON stream, copies/allocations/register-pressure measurements, lazy `.em` section access, serialized alias facts, the cap against the GP workloads, any vectorizer (reported unavailable)"),
  ("Bounded, versioned harness transport (M2.5 H18)", 0.3, "One versioned JSONL stream with a header, a closed record set and `result.data` as the extension map, validated against `docs/schemas/neper-v1.schema.json` by the suites (D227-D300); two-site diagnostics carry `related` (D364); `run --json` is bounded -- `--capture N` bytes per stream in the record, whole counts and `captured_complete` in the result, the files beside the executable holding the rest (D370). Not yet: streamed capture chunks, typed diagnostic facts, cursors bound to snapshots, sequence IDs and progress records, a versioned `fix` with expected-source preconditions, cancellation, measured serialized bytes"),
  ("Compiler responsiveness and correctness (M2.5 H10)", 0.45, "Phases separated so a check links and generates nothing (D314, D320); artifacts keyed by source, mode and interface hashes and published atomically (D205-D214, D343, D369); mutation fuzzing and a nesting bound (D341); deterministic failure codes for every exhausted limit (D344); images byte-equal across worker counts and perturbed schedules (D331); stage-2 == stage-3 and clean == incremental in both suites; one-shot query latency measured -- 25 ms for a small check, 269 ms for the whole compiler -- and no daemon adopted on it (D372). Not yet: IR verifiers, differential execution against an independent oracle, metamorphic tests, test impact queries, cancellation beyond killing the process"),
  ("Bounded tooling lifetimes and responsiveness (M2.5 H16)", 0.25, "One process per query over one snapshot, reclaimed at exit -- measured and kept (D372); `--stats` accounts arena high-water, peak resident set, per-phase time and worker bytes (D311, D338); limits are named codes, not crashes (D344); the baseline's memory budgets and the gate (D366). Not yet: a batch mode, pinned snapshots and eviction, cancellation checkpoints, a backpressure scheduler (the worker default is eight, measured at four on the largest workload), retained-memory reports after warmup"),
  ("Generated-source provenance and editability (M2.5 H19)", 0.35, "A `<file>.e.map.json` beside a generated file maps diagnostics back to the original span with the generated one related; a stale or malformed map is E-TOOL-0001 with no artifact (D264, D300); version 2 names the generator and hashes its input, so a changed input is stale too, and a mapping's `edit` says whether the generated span may be edited or the original is the target (D373); no fix is ever offered on an original span; the compiler runs no generator. Not yet: one input to many declarations, nested maps, provenance through specialisation and inlining, maps in a cache identity, hand-edit detection"),
  ("Compiled LLM cards (M2.5 H28)", 0.6, "`docs/llm-neper-card.md` is the render of `scripts/render_card.py`: the grammar's own productions, its keyword set, the diagnostic registry's families and the stream versions, around the prose of `llm-neper-card.src.md`, stamped with the grammar revision and a content hash, and both suites refuse a card that is not the render (D374). Not yet: per-symbol API records, planned/present/verified marking, compiled examples, one card per language version"),
  ("Learnability and executable API documentation (M2.5 H11)", 0.2, "The index carries every symbol's signature, spans, attributes and documentation (D232), `context-file` its resource and unsafe facts (D361), and the language card is generated and stamped (D374). Not yet: per-symbol API records with ownership, invalidation, allocation and thread facts; planned/present/verified marking; examples that compile under the suite; near-miss negative examples; the stdlib-hardening migrations of SL01-SL11 as a gate"),
  ("Tokenizer grounding (M2.5 H26)", 0.5, "`benchmarks/tokens/profile.py` writes a grammar-versioned vocabulary table per public tokenizer (cl100k_base, o200k_base): the model-token cost of every grammar terminal and the frequent composite forms, and `--measure` reproduces the corpus numbers from it -- 1.27 model tokens per lexical token on the conformance corpus, keywords one token each, fixed-width type names two, a typed literal three (D375). Not yet: families without a public tokenizer, the profile in the build manifest, the table in the card"),
  ("Structured edits (M2.5 H29)", 0.35, "`plan-rename-file --json --symbol m.f --to g` emits a plan -- `precondition` (file hashes), `edit` (`rename-symbol`, site, span, replacement), `postcondition` -- and applies nothing; `scripts/apply_plan.py` applies all or none against the hashes; both suites round-trip it (D376); `m25-h29-structured-edits.md` fixes the shape of `change-signature`, `add-parameter-and-migrate` and `replace-expression`. Not yet: those three, a snapshot identity in the stream"),
  ("Bounded semantic context for harnesses (M2.5 H08)", 0.35, "`context-file --json --symbol module.name [--budget N] [--cursor N]` (D361): a subject record bound to the source SHA-256, target and check policy, then facts with provenance -- signature, `own` parameters, the rules that held or the unsafe boundary, every resolved call, dispatch, instantiation and discard with its span -- under a record budget with omission counts, a completeness flag and a deterministic cursor; pinned per host. Not yet: other symbol kinds, borrow origins and invalidations as facts, effects and errors, dependency hashes, a byte budget, partial sources"),
  ("Error detail and partial failure (M2.5 H07)", 0.4, "A failing cleanup records its detail only over a read slot, so the acquisition's detail survives the close on an error path (D360, both hosts, pinned by a fixture that exits 12 against the old library); the fixed surface's outputs on failure, consumption and retry are specified; a dropped `err` is a `discard` record in `explain-file`. Not yet: caller-supplied detail on the checked path, wrappers beyond `e.os`, concurrent errors, per-step allocation failure"),
  ("Protocols, generics and compile-time context (M2.5 H06)", 0.3, "`explain-file --json` (D359) emits every protocol dispatch -- declared, supplied or none -- and every generic instantiation with its arguments and requesting site, from the checker's own decisions; pinned by the corpus. Not yet: failed candidates with reasons, dependent requirements, explicit strategy selection, comptime budgets and exhaustion, layout and phase in the output, per-instance cost"),
  ("By-value ABI and alias semantics (M2.5 H05)", 0.8, "A by-value aggregate is a snapshot (D358): copied to the call's own storage unless nothing can write it during the call -- a local whose address the function never takes goes by address; pointer, slice, string and global places and address-taken locals are copied; the copy is shallow; `--stats` counts both. The fixture holds `f(x, &x)`, a written slice element, a field through an address-taken struct and a fresh result in both modes. Not yet: a proof through the callee's signature, external ABI wrappers, the compatibility identity"),
  ("Scoped concurrency and shared-state contracts (M2.5 H04)", 0.55, "The design (`m25-h04-concurrency.md`, D365): the join obligation is H01's; a thread over this frame's storage cannot be detached, handed on, returned or stored past it (D357, E-SAFETY-0015); what a thread was given is lent to it until the join, read or written by nobody but through an address (D365, E-SAFETY-0016); a lock held as a value is a `sync.Guard` resource, released on every exit by H01's rule (D379); the compiler's crews and every fixture pass. Not yet: the protected data as a view of the guard, RwLock guards, aliases through slices, pointer locals and globals, partial spawn failure over arrays, a perturbation fixture"),
  ("Regions, borrows and container views (M2.5 H02)", 0.4, "The lexical subset (D354, `m25-h02-regions.md`): a mark is followed, values allocated after it dangle at the reset, views of a container dangle at its mutation, both refused at the use (E-SAFETY-0013/0014) with the join and loop rules of H01; no false positive across the compiler, library and fixtures. Not yet: borrow summaries across modules, escapes through structs, callbacks and threads, aliases through pointer locals, non-lexical liveness, build-then-freeze containers, generation-tagged handles"),
  ("Resource ownership and cleanup (M2.5 H01)", 0.9, "The seeded handles are affine and obligated, `own` parameters transfer, every exit audits, `defer` reserves, an untested acquisition is unchecked, arms join and loops keep outer resources (D345); declared `resource(cleanup)` types, containment followed field by field, views, and a declared resource's fields its module's (D348); a borrow given to no one, copies by pun, pointer cast or element refused, and `os.dup` the one duplication (D349); every other `e.os` handle a `resource(closer)` with its fields the module's (D350); a kept pointer pins its resource until the block ends, and `mem.Arena` is affine (D351); the cost measured and cut, the closure record written (D352, `m25-h01-ownership.md` section 15); the containers' inserts by `own` and `(T, bool)` results narrowed by their flag (D353): twelve E-SAFETY codes pinned by conformance fixtures, both suites on every fixture and library, the compiler's and library's own leaks found and fixed. Not yet: a container that can hold obligated resources (H02), reflection and the format codecs over resource fields, arrays as wholes, the seeded handles' opacity, the `@unsafe` inventory; check bodies +11% debug against a +10% budget"),
  ("Comptime str parameters and varargs", 0.95, "link/comptime_str, link/str_format, link/io_printf; two of the three pack intrinsics expand, `gpu.launch` does not"),
  ("e.meta reflection", 1, "link/meta_scalar answers kind, array_len and type_name; link/meta_reflect walks fields and members through comptime Field and Member values, an unrolled for and get/set at the named offset; link/meta_types answers element_type and backing_type, whose result is a type usable as a comptime argument, nested in the other question, or instantiating a generic. link/meta_field_param hands a comptime Field across a call, so the callee is instantiated per field with a return type that depends on which one it got. A type-valued answer stands where a type is written, including a local's annotation: the type grammar takes a trailing call and name resolution classifies it (D126). A comptime `Field` parameterises a function or a type, and link/meta_field_param pins each instantiation's layout to the field it was built around (D127). link/meta_generic asks the same questions from inside a generic function, where the subject is a type parameter: the template body is checked once with nothing bound, so the question stands there and the instance settles it, which is the deferral `mem.size_of` always had (D136); a `let` initialised by such a protocol call follows its declared type the same way (D143). A call whose callee is a binding's `.ty` is a conversion, the same one a written `u8(x)` is, which is how a walk over `meta.fields` puts a parsed value into the field it belongs to -- every parser answers in one width and every field has its own (D139). A bare type parameter is a conversion the same way, `T(bits)`, and its operand may itself be of a type parameter's type; a `bitcast` to `T` stands in the template pass and is checked per instance (D144)"),
  ("Merged error table", 0.75, "src/error_table.e builds it and push_err expands against it; `main`'s failure line reads it in the binary (D199): a root `main` returning anything but `ok` reaches a synthesized `neper_report_failure`, one compare per declared error of the program, which writes `error: <qualified name>` to stderr through the runtime's own write before the exit with code 1 -- link/failure_line pins the module's own error and one of `e.os`'s on both platforms. Not yet: the trap protocol's use of it and `neper test`"),
  ("Root arena sized by --arena", 1, "`emit-executable --arena SIZE` (D225): the size, with k/m/g, is patched into the image -- a word in the PE runtime the entry reads, the four immediates of the ELF startup stub -- so a self-hosted compiler built with `--arena 1g` compiles the compiler in release, which the default 512 MiB does not hold. link/arena_size pins eight mebibytes refusing twelve on both platforms"),
  ("Debug fills 0xCD / 0xDD", 1, "Section 11's two fills (D217): a debug build calls `neper_mem_alloc_fill` and `neper_mem_reset_fill`, which fill what an allocation hands out with 0xCD and what a reset gives back with 0xDD; a release build calls the plain entry points and `@nocheck` changes nothing, since the fills are not checks. link/debug_fills pins both fills in debug and their absence in release, on both platforms"),
  ("Spec 11 debug check table and trap protocol", 0.99, "A check that fires follows the trap protocol (D194): the runtime's `neper_trap` writes `file:line:col: trap[kind]: <values>` to stderr and exits 134 on both platforms, and link/trap_bounds pins the record for an index and a slice past the end. Rows delivered: `bounds` (index and slice), the compiler's own `unreachable` points, the `unreachable()` builtin with its literal as the values, which the checker counts as diverging (D195, link/trap_unreachable, check/unreachable_argument), the rows that trap in every mode -- `divide` by zero and the minimum by -1, both reported before x64 could raise `#DE` for them, and `shift` by a count past the width -- with a signed operand printed signed (D196, link/trap_arithmetic), `enum`: section 4's `Kind(x)` cast exists now and traps on a value naming no member (D197, link/trap_enum, check/enum_cast_width), `narrow` for an integer source: a cast whose value does not fit by width or by sign traps, and section 4's meant truncation `T.trunc(x)` exists and never does (D198, link/trap_narrow, check/trunc_float_argument), `narrow` for a float source -- NaN and a value past the target's range -- `tag`: a payload read or written under another member's tag (D200, link/trap_tag), `null`: every dereference of a pointer value -- `*p` and `p.field` -- read or written, refused for nil (D201, link/trap_null), and `overflow`: `+ - *` and unary `-` on every width, an unsigned 64-bit `*` through `mul`'s high half (D202, link/trap_overflow); `@nocheck { }` leaves the debug-only rows out of a block and the release rows in (D203, link/nocheck); `emit-executable --release` is the release build: every debug-only row left out, `+ - *` wrapping, casts truncating, shifts masked and a float outside its target saturating, NaN to 0 (D204, link/release_build, a fifth smaller). A trap ends with its backtrace: one `  at module.function` line per frame, walked over the rbp chain and named from a symbol table the driver appends after the code, which the artifact path reproduces byte for byte (D206, link/trap_backtrace), each frame with the file and line its call is at, from the line table (D209, D212), and `align`: `simd.load_aligned`/`store_aligned` at an address that is not a multiple of the vector's width, checked at the call site in debug and left out in release (D210, link/trap_align). Not yet: the test root's control handle"),
  ("General comptime interpreter", 0.8, "A `const` initialiser may call a function (D218): the interpreter walks the callee's syntax tree with integer and bool values -- locals, assignment and the compound forms, `if`, `while`, `break`, `ret`, every operator, checked casts, constants, and calls to other such functions in any module -- under the section's ten-million-step budget, and a call that reaches anything else, or runtime state, is refused under E-COMPTIME-9999 naming the constant and what it reached (link/comptime_call, check/comptime_call_runtime, check/comptime_call_budget). A call stands in an array length and a `[...]` argument the same way (D219), and a `when` condition that is not a question about the target is a bool it evaluates (D220); an array local of integers or bools -- `zero`, indexed reads and writes, `.len` -- and `for` over a range run in the frame (D221, a sieve in link/comptime_call). A `const` may be a bool -- `true`, a comparison, `&&`, `||`, `!`, or a call -- and a constant that reaches a call through another is put off until the signatures exist rather than refused (D222); one a type asks for before them is refused with the reason (check/comptime_call_in_type). Not yet: structs, slices and the arena as interpreter memory, an array across a call, and meta-only calls in a body. Before it: integer const folding, and a branch settled by one `meta` question. link/comptime_branch walks `meta.fields` with arms that do not type check for each other's field types, and recurses on `meta.element_type` with the guard arm as its base case -- neither could be written before, and both are what a codec over a struct is (D138). `mem.size_of[T]()` on a scalar folds the same way (D144), which is what lets one generic `load` in e.bytes hold a bitcast for each float width with the wrong one gone. The condition still has to be a `meta` or size question compared against a constant: an `if` over an arbitrary comptime expression wants the interpreter this does not have"),
  ("@reorder opt-in struct packing", 0, "Design only (D239), end of backlog: the struct default stays declaration-order C layout, and `@reorder` on an internal `struct`/`union` lets the compiler sort fields by descending alignment to cut padding, deterministically for reproducible builds; illegal on a type that crosses an FFI/`@gpu` boundary and mutually exclusive with `@packed`. Not started"),
 ],
 "Back end": [
  ("NIR, typed SSA-lite", 1, "src/nir.e"),
  ("Linear-scan register allocator", 1, "src/regalloc.e; a call saves and restores only the registers whose values are live across it, from the allocator's ranges (D226): the compiler's own image is seven per cent smaller. The pool is ten registers (D235): five the calls clobber and five the callee keeps, saved once at entry and restored at the returns, so a value in one of the second five costs nothing at a call. A scalar `var` whose address is used for nothing but loading and storing it is a value with one range and one register, defined again at every store (D236), a loop's own temporaries no longer share one live range with everything the loop touches, and a fixed-register sequence saves only the registers it clobbers that hold a live value. Measured on `e.fmt.json` over the standard files, best of three interleaved against D235: eleven to ninety-nine per cent faster; a byte-counting loop 2.4 times. A comparison whose only use is the branch after it sets the flags and the branch jumps on them, with no materialised bool, and a branch to the next block in code order is dropped (D237); an integer constned under 2^32 is a five-byte load. Measured on `e.fmt.json` over the standard files, best of three interleaved against D235: forty-eight to a hundred and twenty-eight per cent faster, a byte loop 3.3 times. Not in a register still: an aggregate's fields, and a load whose use lies in another block"),
  ("x64 emitter, System V and Win64", 1, "src/codegen_x64.e"),
  ("ELF object writer", 1, "src/object_elf.e"),
  ("COFF object writer", 1, "src/object_coff.e"),
  ("Own ELF linker", 1, "src/link_elf.e"),
  ("Own PE linker with kernel32 imports", 1, "src/link_pe.e"),
  ("Host runtime intrinsics, both platforms", 1, "runtime_pe_x64.asm, runtime_elf_x64.s"),
  ("os.syscall and mem.address_of: the raw kernel path", 1, "link/os_syscall carries a path and a stat buffer through getcwd and newfstatat; link/mem_address pins the address itself and D96 keeps it one-way. It is what lib/e/os.linux.e is written over -- six filesystem primitives in neper rather than asm. Linux only by design; the name does not resolve on Windows"),
  ("`.em` module format with Deps edges", 1, "src/em.e, fixtures/em"),
  ("Dead-function elimination", 1, "only what `main` reaches is emitted, following calls and taken addresses. Both link paths drop the same functions from the same sequence, so an image linked from `.em` artifacts stays byte-identical to one compiled from source -- which link/function_values compares by hash. A minimal e.os binary went from 221 KB to 8 KB and is freestanding again; the compiler's own stage 2 from 4,170,240 to 3,930,624 bytes (D130). Both runtimes are ordered so a function calls only what precedes it and are cut after the last one the program reaches, and the ELF code segment starts where the headers end: and the PE import table declares only what the kept runtime reaches: an empty program is 366 bytes on Linux and 2,048 on Windows, hello world 3,984 and 6,144 (D149, D150, D151)"),
  ("Cross-module inlining, 40 NIR cap", 0.95, "The inlining oracle (D207): every short non-generic function of every module is lowered ahead of the program into a builder of its own, and a call to one that came out at forty NIR instructions or under, with at most one register result, is replaced by a copy of its body -- parameters become the arguments, returns become branches to the continuation, references are re-interned -- in module order on both link paths, so an executable linked from artifacts is still byte-identical. Only a release build inlines (D211): a debug build keeps every call a frame, as section 13's debug-info rule says, and `emit-em-all --release` is where the artifacts' body edges come from. The artifact records a body edge to every inlined callee of another module, and `--incremental` acts on it: link/incremental pins, in release, a body edit behind a signature edge keeping the dependent and one behind a body edge rebuilding it. The oracle is built twice, the second against the first, so a copy is two levels deep and carries the body edges of the body it copies (D212, link/inline_nested: a leaf's body edit rebuilds the module two copies up). `--inline-cap N` and `--explain` (D348): the cap re-evaluated at 0/20/40/80/160 on the compiler compiling 500k lines (forty retained: seven per cent faster than none, twenty as fast at five per cent less image, more buys nothing) and every oracle decision explained on request. Not yet: the cap is applied within a module too, where the section has none, and a third level"),
  ("Incremental rebuild on the edge rule", 0.95, "`emit-em-all --incremental` (D205) lets section 12's edge rule decide per module: the artifact on disk stays when its source hash and build mode are unchanged (`--release` builds release artifacts, D211) and every recorded edge still matches the declaration it names in the target's fresh Interface, and is replaced otherwise; `kept`/`rebuilt` is printed per module. The decision is taken after checking and before lowering (D214): every hash an Interface carries comes from the checker -- a body hash is over the declaration's tokens -- so the fresh Interfaces are written from it alone, and a kept module is not lowered, selected or written at all. That is the saving: over the compiler's 31 modules a build with nothing changed takes 10 s against 34 s, and one with a body edit in `decimal` rebuilds `decimal` alone in 13 s, linking byte-equal to a clean build. An artifact holds the whole module now, not the functions this program reaches; the linker prunes. link/incremental pins unchanged sources kept, a body edit behind a signature edge rebuilding only its module with the linked result byte-equal to a clean build, and a signature edit rebuilding the dependent, on both platforms. The artifact path became usable at this size in D213: a CRC per read and a bit-loop `xor` under it had cost minutes. The checker settles the declarations first and the edge rule decides on them, so a kept module's bodies are not checked either, and the load-time checksum is table-driven (D224): a build with nothing changed is 4 s. What is left is the load itself -- every artifact read and widened to decide -- and the declarations of every module. `emit-executable --incremental` and `run --incremental` are the hot build (D319): the keep set settled after the declarations, the kept modules' bodies and code skipped, each fresh module's artifact written as it is selected, and the image linked from every module's artifact, byte for byte the cold build's; the compiler with nothing changed settles in 0.6 s and links in 1.0 s. At scale the artifact path walks a module's own rows and resolves through indexes, bytes are bytes and the NIR section is not written (D320): warm, nothing changed, the compiler builds in 1.1 s, a 500k-line program in 3.1 s and a 2M-line one in 12.6 s, each the cold build's image byte for byte. An unchanged module is not parsed unless something that changed imports it (D322, artifacts carry their imports, format 6): warm builds 0.86 s / 1.5 s / 6.1 s, and a leaf edit costs the warm build plus the module; with the manifest's digests carried on the artifact (D323, format 7) a release-built compiler builds itself warm in 0.24 s, 500k lines in 0.97 s, 2M in 4.0 s; with the artifacts read and validated on worker threads and the link reading through the bounds it holds (D324): 0.19 s / 0.36 s / 1.6 s"),
  ("os.thread_create / join / detach", 1, "link/os_thread runs and joins a real thread on both platforms: CreateThread on Windows, clone(2) over a self-allocated stack with a futex join on Linux. detach leaks its mapping, wanting a reaper"),
  ("Work-stealing pool, parallel parse and codegen", 0.75, "the front end runs in waves of eight workers (D321); the modules are lowered, selected and written as artifacts on eight workers with checkers that share the declarations (D325); and the same workers check the bodies and build both inlining oracles first, each with a checker forked from the program's and importing the types of a body copied from another worker's oracle (D326). A two-million-line program builds cold in 7.6 s debug and 7.4 s release where it took 29 and 26, its body sweep 0.6 s where it took 1.9 (1.3 s where it took 5.7 in release), the settle nothing on a cold build and the lowering not re-checking what the sweep checked (D327), and the bootstrap runs a thread inline. The names are validated on the workers too (D328), the artifact writer copies bytes with one runtime call (D329), and the allocator, the digest and the lexer lost their last quadratic and per-byte costs (D330): a million-line program builds cold in 3.0 s on Windows and 3.4 s on Linux, warm in half a second; the link's per-artifact passes run on the workers too, with SHA-256 and CRC-32C in hardware where the CPU has them (D336): a million-line program builds warm in a quarter of a second, the compiler in 65 ms; what remains sequential is collecting the declarations, reachability and layout; the work is assigned statically, not stolen"),
  ("Determinism harness", 0.9, "compiler fixed point on both platforms, artifact-linked equals source-linked for every artifact fixture, and incremental equals clean for link/incremental (D205); the compiler's own 31 artifacts, listed in graph order, link byte-equal to the source build, and so does the set with one module rebuilt incrementally (D213, D214) -- `link-em` lays functions out in the order the artifacts are given, so the order is an input. `-j N` caps every phase's workers and `--perturb` turns the crew's schedule around (D331): both suites require the compiler built under `-j 1` and under `-j 3 --perturb` to be the stable stage byte for byte, and the inlined release fixture under `-j 1 --perturb` the default build; the hot build under either is the cold image. A relocated build is the same image (D337): the sources spelled from the project root in the line table, so the operand's spelling and the project's place change nothing, pinned by both suites. Not yet: the device-reached edit case that waits on M3"),
  ("DWARF, CodeView and .nepersym debug info", 0.35, "The symbol and line table (D206, D209): after the code, per function its start, length and `module.function` name, and its line rows -- a code offset, a line and a file wherever the line changes, inlined bodies naming their own file -- which the trap protocol reads for its backtrace; artifacts carry the rows in a Lines section and the artifact path reproduces the table byte for byte. Not yet: DWARF or CodeView for a foreign debugger, a named `.nepersym` section rather than the bytes after the code, and variables"),
 ],
 "Self-hosting": [
  ("Self-hosted compiler emits its own source", 1, "run.ps1:623, run.sh:760"),
  ("Stage 2 == stage 3, byte-identical, both platforms", 1, "SHA-256 compare / cmp"),
  ("Bootstrap recovery path archived", 1, "docs/bootstrap-archive.md (D208): the SHA-256 of stages one to four on both platforms at the archived revision, stage three the stable one, and the commands that reproduce them from a clean checkout of the tag `bootstrap-archive-1` with no neper binary present"),
  ("Bootstrap frozen and deleted", 0, "bootstrap/neper.c still builds stage 0"),
 ],
}
tooling = [
 ("JSONL v1 stream envelope and version header", 0.93, "The header, diagnostic, token, syntax and result records of section 1 (D227, D228), each a line, the result last with the exit status; emitted by `tokens`, `parse`, `check-file`, `info` (D229), `emit-executable` (D230), `run` (D231), `index` (D232), `dis` (D233), `fmt` (D234) and `test` (D240) -- every section 1 command now streams. An operand that cannot be read answers with the envelope on every one of them (D260): the header, one location-free E-CLI-9999, the result exiting 2 with the command's own zero counts, pinned in both suites for tokens, parse, fmt, fmt --check, dis and test; `check`, `build`, `run` and `index` had it since D228-D232. `-` reads the operand from stdin under the `--path` identity section 4 requires with it, on `tokens`, `parse` and `fmt` (D289: `os.stdin` joined the bootstrap's fixed surface the way `os.mkdir` did); both suites pipe a fixture in and compare against its own golden. `--absolute-paths` on `tokens`, `parse`, `check` and `index` adds `absolute_path` beside the operand's identity and changes nothing else (D290: an absolute operand as given, a relative one under the current directory, which `os.current_dir` joined the bootstrap's fixed surface for); both suites take the field out of a check and a tokens stream and require the golden. Not yet: `-` on `index`, `.` and `..` segments collapsed in `absolute_path`, and a result record on a JSON output that cannot be initialised"),
 ("build", 0.85, "`emit-executable PATH ROOT ARCH OS OUTPUT [--release] [--arena SIZE] --json` (D230): the section 1 header with command `build`, every front-end, lowering, code-selection and error-table diagnostic as a record, and the result naming the executable as it was given; tests/conformance/tools pins a program that builds and one that is rejected. Every successful build writes `.neper/<mode>/build-manifest.json` under the project root, making the directory when it is missing (D254, D287: `os.mkdir` joined the fixed surface as a bootstrap intrinsic, the self-hosted side already having it from the per-host `e.os` source), its one artifact the executable as named with the SHA-256 of the bytes written; both suites remove the directory, validate the manifest the build makes against the schema and compare the hash to the file on disk. `--project DIR` names the project root outright instead of discovering it from the operand (D263), so a file outside the tree -- a generated test runner -- is built as part of it. Spec section 2's spelling works (D276): `neper build FILE [-o OUT] [--target ARCH-OS] [--release] [--json]`, with the toolchain root the binary's own directory, the target the host unless said, and the output the operand's stem (`.exe` on Windows); `run`, `check`, `fmt`, `index`, `dis` and `build-manifest` have the same front door; both suites compare the short `build` stream to the positional form's golden. `neper test FILE [--project DIR]` is the short `test` (D292): always the stream, its WORKDIR `.neper/debug/test/` under the project the operand is in, made when missing; both suites compare it to the positional form's golden. `neper check` and `neper test` with no operand are the project the current directory is in (D294). Not yet: a project root as `build`'s operand, and warnings"),
 ("check", 0.85, "`check-file PATH ROOT ARCH OS --json` (D228): the header, a `diagnostic` record for every error the front end reports -- lexical, syntax, module, resolution and checking, each with its registered code, message and span -- an unreadable operand as a location-free E-CLI-9999 with exit 2, the `result` with the exit status, and nothing on stderr; every diagnostic printer goes through one emitter that writes the human line or the record. tests/conformance/accept and reject pin five streams byte for byte on both platforms. `check-project DIR ROOT ARCH OS WORKDIR --json` checks every module under DIR/src (D262): the tree walked in byte order so the stream is the same on every filesystem, each module checked in its own `check-file --json --path REL` process so its identity is its path under src -- `nested/deep.e`, not a basename -- and the children's records merged into one stream with one header and one result carrying the diagnostic and module counts; tests/conformance/tools/check_project pins three modules, two with an error. `neper check FILE` is the short spelling (D276) and `neper check` with no operand checks the project the current directory is in as `check-project`, working under its `.neper/debug/check/` (D294), as does `neper test` as `test-project`; both suites run each from inside a corpus project and require the project form's golden. Not yet: notes, fixes, a `project-src` root in the identity, and a module outside src"),
 ("run", 0.85, "`run PATH ROOT ARCH OS OUTPUT [--release] [--arena SIZE] --json` (D231): a build, then the program is launched with its stdout and stderr to files beside the executable and read back whole into one `run` record with the process exit code, captured bytes base64 when they are not UTF-8 (section 2); tests/conformance/tools/run.e exits 3 and writes a non-UTF-8 stderr byte. A trap's record is read back out of stderr as the structured `trap` payload (D253): its kind, a byte-precise zero-width span at the site when the file is the operand, the record's values text as one entry, and one backtrace frame per `  at` line with its qualified function, the operand source where the frame lies in it, and its line; tests/conformance/tools/run_trap.e pins a bounds trap two frames deep, spelled relative to the test build dir so the golden carries no host path. `-- ARGS...` after the flags reaches the program as its arguments on both hosts, spaces kept (D267, tests/conformance/tools/run_args.e echoes three and exits with their count); a relative OUTPUT with directories launches on Windows too, spelled the host's way. A Linux build writes its executable mode 0755 and `run` and `test` launch it directly, no `sh -c` and `chmod` in front (D291: `os.set_mode` joined the bootstrap's fixed surface, the per-host `e.os` source having it); the Linux suite requires the corpus build's executable to be one. Not yet: streaming, a project root, and a source for frames in other modules"),
 ("test and @test discovery", 0.97, "`test-file PATH ROOT ARCH OS WORKDIR --json` (D240): the @test functions of the operand -- an `@test` attribute on a top-level `fn` -- are discovered in source order, a runner carrying them is compiled by spawning the compiler again, and each test runs in its own process so a trap is a crash rather than aborting the harness; the section 7 stream buffers one `test` record per function in source order, a `test_summary`, and the result, exiting 1 if any test is not `passed`. A returned err is `failed`, a trap `crashed`, classified from exit status and stderr; each test and the run carry a real `duration_ms` from the monotonic clock (D242), normalised out of the golden. a test that outruns the deadline is ended by a watchdog thread inside the runner -- the fixed os surface gives the driver no kill and no timed wait, so the child self-terminates on the futex wait's deadline and exits 124 -- and is reported `timeout` with the deadline in `timeout_s` (D246, `WORKDIR [TIMEOUT_MS]`). A crashed test carries the same structured `trap` payload as `run` (D253), mapped from the generated runner back onto the operand -- the runner is the operand's text two `use` lines down, so its span, frame functions and lines come out as the operand's, and a frame in the runner's own scaffolding keeps its printed name with no source; a crash with no record is the `exit` kind carrying the status. `error` is `ok` for a passed test and the qualified name after `error: ` for a failed one, with the runner's module name replaced by the operand's; the fixture's third test indexes past a five-element array. A `@test` that is not a test is refused before anything is compiled, as E-TEST-9999 at the declaration (D256). `test-project DIR ROOT ARCH OS WORKDIR [TIMEOUT_MS] --json` runs every module under DIR/src (D263): the tree in byte order, each module through `test-file --json --path REL` in its own process so its `file` is its path under src and its `module` the dotted name (`nested.deep`), the runner built as part of the project via `emit-executable --project DIR` so a test's `use` of a sibling module resolves, a module with no tests counted and skipped without a compile, and the children's records merged under one header, one summed `test_summary` and one result with the test and module counts; tests/conformance/tools/test_project pins three modules, one test-less, one failing test and one nested test that uses a sibling. A test that does not compile is reported at its own span through the runner's source map, the compiler's records forwarded before the E-CLI-9999 (D264). An operand that both defines `main` and carries tests works (D281): the runner renames the operand's `main` to `nptest_operand_main` and its source map carries the seam as a second mapping, so a diagnostic past it still lands on the operand (tests/conformance/tools/test_main, test_main_error). Not yet: `message` from `test.assert`, and a call to the operand's own `main` from its tests"),
 ("fmt canonical layout", 0.98, "`fmt-file PATH --json` (D234): one `formatted` record whose text is the canonical layout -- four-space indent by brace depth, one space around binary and assignment operators and after comma and colon, no space inside delimiters or around `.`/`..` or before a call or index list, slice and array element types and prefix operators glued, comments preserved with a trailing comment one space out, blank runs collapsed to one with none at a block edge, a single final newline; tests/conformance/tools/fmt.e is already canonical, so the golden pins idempotence too; `--check` reports E-FORMAT-0001 at the first non-canonical byte and exits 1 (D244). One space inside a brace pair on a line -- `{ ret ok }`, `struct { a: i32 }`, `Pair { a: 1i32 }` -- and none in `{}` (D255), pinned by tests/conformance/format/layout.e, a deliberately mangled source whose canonical side is the golden; `fmt-file PATH` without `--json` prints the canonical text itself. What `fmt` refuses is diagnostics in every form (D257): each invalid token under its lexical code and a comment between an attribute and its declaration as E-FORMAT-9999, the stream ending in a result that exits 1 with no `formatted` record, the plain form printing the human lines to stderr. Three more of section 6's rules (D273): exactly one blank line separates top-level declarations -- an attribute, a `///` or `//` line, or a `use` before another `use` leads into the next one rather than separating it -- an empty block is `{}`, and `else` follows `}` on the same line; the format fixture pins all three. The contiguous comment-free `use` block at the start of a file sorts by module path then alias (D274), pinned by the fixture. A bracketed list -- a call's or signature's `(...)`, a type body's `{...}` -- that would exceed 100 columns from where it opens breaks after the opener, one element per line four columns in with a trailing comma, the closer back on the opener's indent; one that fits is joined onto one line with no trailing comma; a grouping `(` or any `[` only ever joins, since a trailing comma inside is not syntax, and a list with a comment inside is left as written (D277). A member literal after a keyword keeps its space (`case .Red`, not `case.Red`) and a `case` or `default` label sits at its `switch`'s indent, the statements under it one level in (D284). Every source of the compiler and the library formats idempotently, and a compiler built from its own formatted source agrees with the goldens. An aggregate literal's body is a list too (D285): a `{` after a PascalCase name outside an `if`/`while`/`for`/`switch`/`when`/`else` header or a signature's `-> Type` is the parser's own literal rule, so `Pair { a: 1, b: 2 }` joins and a wide one breaks one field per line. A run of attribute lines sorts by attribute name (D286). `fmt -` reads stdin and writes only the canonical source to stdout, `--json` the `formatted` record under the `--path` identity (D289). `fmt FILE` formats the file in place, writing nothing when it is canonical, and `fmt` with no operand formats every `.e` under the project's src/ and lib/ in byte order, `--check` naming each non-canonical file as an E-FORMAT-0001 line and exiting 1 (D295); both suites format a one-file project and a copied file to the corpus's canonical text. Not yet: one statement per line, raw-string delimiter minimization, and a `--json` stream over a project"),
 ("tokens, lossless over 94 tokens", 0.95, "`tokens [--json] [--path VIRTUAL.e] FILE` (D227): the section 1 header, a `token` record per token with its registry kind, lexeme, span and leading trivia, a `diagnostic` before each `INVALID` token whose lexeme is the base64 object, and the `result`; every record validates against docs/schemas/neper-v1.schema.json, the trivia and lexemes concatenate back to every byte of the compiler's own sources, and tests/conformance/tokens pins every_kind (93 of the 94 kinds) and hostile (BOM, CRLF, a tab, unterminated literals, invalid UTF-8 inside a comment) byte for byte; `-` reads stdin under `--path` (D289)"),
 ("parse, lossless over 54 syntax nodes", 0.97, "`parse [--json] [--path VIRTUAL.e] FILE` (D227): the token records, one `syntax` record whose root lists the top-level nodes with kind, span, token range and ordered `{node}`/`{token}` children, a `diagnostic` where the parser stopped, and the `result`; schema-valid, and tests/conformance/parse pins every_kind and recovery byte for byte. Recovery past the first error was already in the tree -- an `ErrorNode` per failed statement or declaration, the parse going on -- and now every failure is a diagnostic at its own token, not only the first (D275, parse/two_errors pins three); a soft delimiter still open at a column-0 declaration keyword is E-SYNTAX-0012 at the opener, naming the keyword that ended it, in the parse stream, the check stream and the human line (parse/barrier, reject/barrier); `-` reads stdin under `--path` (D289)"),
 ("index, symbols and references", 0.88, "`index-file PATH ROOT ARCH OS --json` (D232): a `symbol` record for the operand module and each of its module-scope declarations -- fn, extern, type, const, module_var, error -- with the closed `kind`, qualified name, full and selection spans and container id, ending in the result with the symbol count; tests/conformance/tools/index.e pins all seven kinds. Each symbol carries its `signature` (the header up to the body brace, so a const or extern is its own), its `attributes` (the `@name` run section 12 requires adjacent) and its `documentation` -- spec section 3's `///` run, one optional space stripped, joined with LF, ended by a blank line or an ordinary `//`, and attaching through the attributes (D251); the fixture pins a two-line doc, a documented `@test`, and a run broken by a blank line. Under a function or type the parse tree supplies its parameters, fields and enum/union members as `parameter`, `field` and `member` symbols with the declaration as `container_id`, qualified `module.Decl.name`, their own signature and `///` documentation, in token order (D258); the fixture pins a documented field, two enum members and three parameters. Every use of one of the module's own names, and every name reached through a `use` qualifier, is a `reference` record (D271): `import` for each `use`, `type` in a type position or a type's name in a path, `call` before `(`, `instantiate` before `[`, `write` before an assignment, `address` after `&`, `read` otherwise; a bare name resolves to the operand's symbol by id -- spec section 5 lets no local shadow a module-scope name, so the match is the resolution -- and a qualified one names `path.name` with a null id; records sorted by span start after the symbols, the result counting both; the fixture pins eleven across every role but `protocol`. Symbols and references go out in section 5's one span order (D280): the references are collected first, every symbol's id is known before any record is written, and each reference is emitted before the first symbol -- nested ones included -- whose span starts after it; the fixture's thirty records are monotone in span start. `index-project DIR ROOT ARCH OS WORKDIR --json` indexes every module under a project's src and lib in byte order, each in its own `index-file --json --path REL` process so its identity is its path from the root, the symbol, reference and diagnostic records under one header and a result with the totals; `neper index` with no operand is that over the project the current directory is in (D298, tests/conformance/tools/index_project). Not yet: `--all` for the toolchain's lib, locals and parameters as symbols and their references, comptime parameters, intrinsics, and compiler-origin `protocol` and iterator references"),
 ("dis", 0.85, "`dis-file PATH ROOT ARCH OS --json` (D233): the codegen pipeline, then one `disassembly` record per emitted function with its module.function symbol, the target triple and its listing, ending in the result with the function count; tests/conformance/tools/dis.e pins it per host. The listing is a mnemonic disassembly (D269, src/disasm_x64.e): one line per instruction -- the function-relative offset, the Intel-order mnemonic and operands (64/32/16/8-bit and xmm registers, `[base + index*scale + disp]` and rip-relative memory, signed immediates, jump targets as offsets), then the bytes after `;` -- from a linear sweep over the encodings emit_x64 produces, with section 11's inline trap text listed as one `text` line rather than decoded; 3,546 instructions across three fixtures were cross-checked against GNU objdump with no semantic difference, and eight fixtures list with no unknown byte. A `call` is named after its bytes (D278): `-> module.function` when its resolved displacement lands on a function's start, and the runtime or imported symbol from the relocation that will fill it otherwise (`-> neper_os_exit`). Not yet: AT&T syntax, following jumps rather than sweeping, and every encoding the emitter does not yet produce"),
 ("info", 0.95, "`info --json` (D229): the header, one `info` record -- tool version, the one language profile, the commands the stream reaches (`check`, `info`, `parse`, `tokens`), the host target, both build targets, the one CPU level the emitter honours -- every collection sorted by bytes, and a result; tests/conformance/tools pins it per host. `commands` names every section 1 command the stream reaches -- build, check, dis, fmt, index, info, parse, run, test, tokens -- sorted by UTF-8 bytes (D259); it had stopped at the four of D229. `--language-version MAJOR.MINOR` on any command selects the one advertised profile, 0.1, and is taken off the arguments; another version is E-CLI-9999 before any source is read, as a stream whose header names the command (D283, tests/conformance/tools/info_version). Not yet: a `features` list beyond empty, the other CPU levels of the spec's table"),
 ("v1 schema validation of emitted records", 0.9, "`python scripts/validate_stream.py` validates every committed golden against docs/schemas/neper-v1.schema.json, and both suites run it (D250): the 23 `.jsonl` streams under tests/conformance -- one record per line, 895 of them -- and docs/modules.json as a whole document, so the three shapes anything currently emits are covered (`streamRecord`, `buildManifest`, `modulePlan`). The goldens are what the commands emit byte for byte, so validating them validates the emitters. A self-check rejects a header carrying an unregistered command before the corpus runs, so a validator that accepted everything could not pass; a machine without the `jsonschema` package prints a skip rather than failing the suite. The runner's source map (D264) is validated by both suites as a fourth shape; `packageManifest` is in the schema with nothing producing it yet"),
 ("Stable diagnostic codes from diagnostics.md", 0.85, "39 of 46 registered codes are emitted (D215; the E-SAFETY codes under D345, D348, D349, D351, D354, D357 and D365; E-TEST-9999 under D256, E-FORMAT-9999 under D257, E-TOOL-0001 under D264, E-SYNTAX-0012 under D275), and every one reaches the JSON stream as a `diagnostic` record with its span (D228): E-CLI-9999 for the usage line, E-LEX-0001/0002/0003/9999 for the token the scanner refused by the byte it starts at, E-MODULE-0001 for a `use` naming no module or one defined by both roots and E-MODULE-0002 for one closing a cycle, each at the module that wrote it, E-COMPTIME-9999 for a reflection shape and E-MEM-9999 for an atomic's element or ordering, beside the E-NAME, E-TYPE, E-ERROR and E-LINK codes already there; check/module_missing, module_cycle, lex_literal, lex_tab, lex_utf8 pin them. E-FORMAT-0001 for a source that is not in canonical layout, via `fmt --check` (D244). `test` reports E-TEST-9999 at a `@test` that is not a test -- not a function, or one with a signature other than `fn name(a: *mem.Arena) -> err` -- and exits 2 with nothing compiled (D256, tests/conformance/tools/test_reject.e). `fmt` refuses a comment between an attribute and its declaration as E-FORMAT-9999 at the comment, and an invalid token under its lexical code, as records in the stream rather than a bare `error:` line (D257, tests/conformance/tools/fmt_reject.e). A stale or malformed source map beside the operand is E-TOOL-0001 (D264, tests/conformance/tools/stale_map.e). A soft delimiter still open at a column-0 declaration is E-SYNTAX-0012 at the opener (D275, tests/conformance/reject/barrier.e). Every code the compiler raises is pinned by a conformance fixture (D297). Not yet: E-GPU, E-SAFETY and E-TOOL-9999, whose subjects do not yet diagnose, and E-LINK-9999 pinned."),
 ("Build manifest with versions and SHA-256", 0.9, "`build-manifest-file PATH ROOT ARCH OS --json` (D238): the canonical `neper-build-manifest` object -- schema, version, tool and language versions, grammar revision, target, mode, root module, and one `inputs` entry per source module carrying its source identifier and the real SHA-256 of its bytes (ported into artifact_hash.e over the byte-per-slot representation, checked against the RFC 6234 `abc` vector and python hashlib); tests/conformance/tools/manifest.e pins it per host. A build writes the same object to `.neper/<mode>/build-manifest.json` under the project root with `mode` from `--release` and `artifacts` carrying the executable as named, `kind` executable, the target and the SHA-256 of the bytes written (D254), making the directory when it is missing (D287). Every input carries section 2's real identity (D265): `project-src` or `project-lib` with its path under that root, `toolchain-lib` for a module under the toolchain's lib, and the operand by its basename otherwise; and every module but the root is a `dependencies` entry with `interface_sha256` -- the source with every function body left out, so an edit inside a body moves only `body_sha256` -- and `body_sha256`, the whole file; tests/conformance/tools/manifest_project pins a two-module project per host. The artifact's path is project-relative as section 7 says (D293): the executable as named, made absolute under the current directory, then spelled from the project root with `/` separators, or kept absolute when it lies outside the project; both suites read the corpus build's artifact by that spelling. The `unsafe` inventory and `options.checks` (D355). Not yet: libraries and assets"),
 ("Generated source maps", 0.72, "Section 8, both halves (D264). The generator: `test` writes `nptest-runner.e.map.json` beside the runner it generates -- `neper-source-map`, the runner's SHA-256, one mapping from the operand's text at its place in the runner to the operand -- validated against the schema by both suites. The consumer: `emit-executable`, `run`, `dis` and `check-file` read `<operand>.map.json` when one lies beside the operand; a diagnostic inside a mapped range is reported at the original span as primary with the generated span related, so a test that does not compile is reported at the test's own line (tests/conformance/tools/test_compile_error.e); a map whose hash is not the operand's, or that is not a source map, is E-TOOL-0001 and the command fails with no artifact written (tests/conformance/tools/stale_map.e). The runner's map has two mappings when the operand's `main` was renamed (D281), the second beginning mid-line. A stale or malformed map is E-TOOL-0001 up front and the analysis still runs unmapped, so the operand's own diagnostics follow it; `check` and `build` then fail with no artifact, as section 8 says (D300, tests/conformance/tools/stale_map_error). Not yet: a `project-src` identity, columns across a mapping that does not start at a line (the rename's own line), more than eight mappings, and a reader beyond the key scan this one document shape needs"),
 ("Conformance corpus accept/reject/format/tokens/parse/tools", 0.9, "All six corpus roots of tooling.md section 9 exist with byte-exact expected output the suites compare on both platforms: tokens/ and parse/ (D227), accept/ and reject/ (D228), tools/ -- one `info` stream per host (D229), a build and a rejected build (D230), a program run (D231) and a trapping one (D253), a symbol index (D232, D251), a disassembly per host (D233), a canonical format and a `--check` rejection (D234, D244), a build manifest per host (D238), a test run and a timed-out one (D240, D246) -- and format/ (D255): a non-canonical source beside what `fmt` makes of it, the canonical side also passing `--check`. Every `.jsonl` golden validates against the v1 schema (D250). Every root has at least two fixtures (D284: accept/aggregate -- structs, an enum, a generic and a switch -- and format/types, whose first draft found `fmt` writing `case.Red` and mis-indenting `case` labels). Every registered code the compiler can raise today has a reject fixture pinning its stream (D297): ten more -- E-MODULE-0001/0002/9999 (the last two as two-module projects under reject/), E-NAME-0002/0003, E-ERROR-9999, E-MEM-9999, E-TYPE-0001/0003/9999 -- beside the six already pinned, leaving E-LINK-9999 (an error-hash collision no small fixture produces) and the codes whose subjects do not yet diagnose (E-GPU, E-SAFETY, E-TOOL-9999). reject/nesting pins section 3's 128-level nesting bound (D341), which a mutation-and-depth fuzzer (benchmarks/fuzz) guards beside the artifact readers. Not yet: the generated-code benchmark report section 9 asks for"),
 ("Module-plan validation in CI", 1, "check_module_plan.py 128 modules; check_module_surfaces.py 9 sources"),
 ("Build statistics (`--stats`)", 1, "`emit-executable --stats` and `run --stats` (D308): the program by files, lines, functions, types and attributes; the build by mode, host, target, reached and unreached modules, image size, wall time and every phase; the run by its time, exit code and peak working set (D311); `--stats-full` adds every pool's capacity beside its use. The link's drop count (D334): reached and unreached functions and the code bytes dropped, from the linker's own reachability walk at no cost to the build"),
 ("`--stats` as a stream record", 0, "Design only (D335): with `--json`, `--stats` emits one flat `stats` record on stdout before the result -- one snake_case key per table row, scalars only, phases as `phase_<name>_ms`, pools under `--stats-full` -- rendered by the same row helpers as the stderr table; also fixes `build --json --stats` printing nothing. Schema entry and a conformance fixture per host. Not started"),
 ("Image digest reused on a warm build", 0, "Design only (D332): the executable's SHA-256 is the one hash a warm build still runs, sixty milliseconds of the compiler's 189; the image is compared with the file on disk before it is written and, equal, the write is skipped and the digest taken from the previous manifest. Not started"),
 ("Compiler hashes from the library", 0, "Design only (D333): `src/artifact_hash.e` duplicates xxHash64, FNV-1a and SHA-256 from `e.algo.hash` and `e.crypto.hash` for bootstrap limits that no longer hold; the compiler calls the library's, `e.algo.hash` gains a table-driven `crc32c`, the tuned SHA-256 moves into the library, and only the hex wrapper, the error-value fold and the interface cut stay. Pinned by the artifacts, the manifest goldens and the stage-2/stage-3 fixed point. Not started"),
 ("Reproducible-build check", 0.75, "Both suites check the compiler's fixed point -- stage 2 and stage 3 byte for byte -- and, since D261, that a program built twice is the same executable and that the second build's manifest carries the first's artifact SHA-256, so two builds can be compared by their manifests without the executables (D254 wrote the hash). Not yet: a `neper` command that compares two manifests, cross-host comparison (a Windows and a Linux build differ by design), and the dependency and library hashes the manifest does not yet carry"),
 ("Generated-code benchmark corpus", 0.5, "benchmarks/llm_edit"),
 ("Self-host regression suite, both platforms", 1, "285 fixtures, run.ps1 + run.sh"),
 ("Bootstrap and self-host build scripts, both platforms", 1, "scripts/build-*"),
]


# Stamp the last commit that touched what this page measures, not HEAD. Stamping
# HEAD would make the page differ from itself the moment it is committed, so every
# later run would show a spurious diff. Taking that commit's own date as well keeps
# the output a pure function of its inputs.
INPUTS = ['src', 'lib', 'docs/module-apis.md', 'docs/modules.json']
stamp = subprocess.run(['git', 'log', '-1', '--format=%h %cs', '--'] + INPUTS,
                       capture_output=True, text=True).stdout.split()
rev, when = (stamp + ['unknown', str(datetime.date.today())])[:2]

# ---- module numbers, recomputed here so the page cannot drift from the plan ----
txt = open('docs/module-apis.md', encoding='utf-8').read()
blocks = dict(re.findall(r'^### `([^`]+)`\n(.*?)(?=^### |\Z)', txt, re.S | re.M))


def decl_names(body):
    out = []
    for f in re.findall(r'```neper\n(.*?)```', body, re.S):
        for line in f.splitlines():
            m = re.match(r'(fn|type|error|const)\s+([A-Za-z_][A-Za-z0-9_]*)', line.strip())
            if m:
                out.append(m.group(2))
    return out


tracked = set(subprocess.run(['git', 'ls-files', 'lib/e'],
                             capture_output=True, text=True).stdout.split())
# `lib/e/os.linux.e` is `e.os`, not a module called `e.os.linux`: a per-target variant
# is one of the files a module may be written in (spec 2), so the trailing arch or os
# is not part of the name and the variants union into one surface.
VARIANTS = {'linux', 'windows', 'macos', 'none', 'x64', 'x86', 'aarch64', 'spv', 'ptx'}
impl = {}
for p in tracked:
    if not p.endswith('.e'):
        continue
    parts = p[len('lib/e/'):-2].replace('/', '.').split('.')
    if len(parts) > 1 and parts[-1] in VARIANTS:
        parts.pop()
    mod = 'e.' + '.'.join(parts)
    impl.setdefault(mod, set()).update(
        m.group(2) for m in
        (re.match(r'(fn|type|error|const)\s+([A-Za-z_][A-Za-z0-9_]*)', l)
         for l in open(p, encoding='utf-8')) if m)

seeded = {}
for mod, nm in re.findall(r'seed\(r,\s*g,\s*"([^"]+)",\s*"([^"]+)"',
                          open('src/resolve.e', encoding='utf-8').read()):
    seeded.setdefault(mod, set()).add(nm)

plan = json.load(open('docs/modules.json'))['modules']
surf = {}
for m in plan:
    surf[m['surface']] = surf.get(m['surface'], 0) + 1
# `docs/modules.json` is the plan and this table is the plan's, so every module in it gets a
# row whether or not a line of it exists. A page that listed only what is written cannot be
# read as a roadmap: what is missing is the part a reader is asking about.
planned = {m['name']: m for m in plan}
tier_of = {}
for tier in json.load(open('docs/modules.json'))['tiers']:
    for name in tier['modules']:
        tier_of[name] = tier['id']

mod_rows, dtot, dgot = [], 0, 0
for mod in sorted(blocks):
    d = decl_names(blocks[mod])
    have = impl.get(mod, set()) | seeded.get(mod, set())
    h = sum(1 for n in d if n in have)
    dtot += len(d)
    dgot += h
    entry = planned.get(mod, {})
    mod_rows.append((mod, h, len(d), entry.get('surface', 'planned'),
                     entry.get('milestone'), entry.get('schedule', 'later'),
                     tier_of.get(mod, ''), entry.get('blocked_by', [])))
# Written first and most complete first; then what is scheduled, by milestone; then what is not
# scheduled at all. Read top to bottom that is the order the plan intends to be worked in, which
# is the only ordering a roadmap can justify.
mod_rows.sort(key=lambda r: (-r[1] / r[2], r[4] is None, r[4] or '', r[0]))

c_sum = sum(s for g in compiler.values() for _, s, _ in g)
c_n = sum(len(g) for g in compiler.values())
t_sum = sum(s for _, s, _ in tooling)
t_n = len(tooling)
C, M, T = 100 * c_sum / c_n, 100 * dgot / dtot, 100 * t_sum / t_n

SRC = 'source'
PART = 'partial'


def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def mark(v):
    if v == 1:
        return '<span class="s s3" aria-hidden="true"></span>', '1'
    if v == 0:
        return '<span class="s s0" aria-hidden="true"></span>', '0'
    return '<span class="s s2" aria-hidden="true"></span>', ('%g' % v)


def table(items):
    rows = []
    for name, v, note in items:
        dot, num = mark(v)
        rows.append('<tr><td class="mk">' + dot + '</td><td class="nm">' + esc(name)
                    + '</td><td class="sc">' + num + '</td><td class="nt">'
                    + esc(note) + '</td></tr>')
    return ('<table><thead><tr><th class="mk"><span class="vh">State</span></th>'
            '<th>Capability</th><th class="sc">Score</th><th>Evidence or gap</th>'
            '</tr></thead><tbody>' + ''.join(rows) + '</tbody></table>')


def meter(label, pct, sub):
    return ('<div class="tile"><div class="lab">' + label + '</div>'
            '<div class="val">' + ('%.0f' % pct) + '<span class="pc">%</span></div>'
            '<div class="track" role="img" aria-label="' + label + ': '
            + ('%.0f' % pct) + ' percent complete"><i style="width:'
            + ('%.1f' % pct) + '%"></i></div>'
            '<div class="sub">' + sub + '</div></div>')


groups = ''
for g, items in compiler.items():
    s = sum(x for _, x, _ in items)
    groups += ('<h3>' + esc(g) + ' <em>' + ('%.2f of %d' % (s, len(items)))
               + '</em></h3>' + table(items))

mod_body = ''
for m, h, d, surface, milestone, schedule, tier, blocked in mod_rows:
    # Both of these are intrinsics plus source now, and saying only "intrinsics" understates
    # how much of them is written down: e.os is mostly its two per-target files, and e.mem gained
    # `copy` and `eq`.
    if m == 'e.mem':
        where = 'compiler intrinsics, lib/e/mem.e'
    elif m == 'e.os':
        where = 'compiler intrinsics, lib/e/os.linux.e, lib/e/os.windows.e'
    elif h:
        where = 'lib/' + m.replace('.', '/') + '.e'
    elif blocked:
        where = 'blocked: ' + ', '.join(blocked)
    elif schedule == 'scheduled':
        where = 'scheduled, not started'
    else:
        where = 'after the scheduled set'
    when = milestone if milestone else '&mdash;'
    mod_body += ('<tr><td class="nm"><code>' + esc(m) + '</code></td><td class="sc">'
                 + ('%d / %d' % (h, d)) + '</td><td class="sc">'
                 + ('%.0f%%' % (100 * h / d)) + '</td><td class="sc">' + when
                 + '</td><td class="sc">' + esc(tier) + '</td><td class="nt">'
                 + esc(surface) + ' &middot; ' + esc(where) + '</td></tr>')
mod_table = ('<table><thead><tr><th>Module</th><th class="sc">Declarations</th>'
             '<th class="sc">Share</th><th class="sc">Milestone</th><th class="sc">Tier</th>'
             '<th>Surface and where it comes from</th></tr></thead><tbody>'
             + mod_body + '</tbody></table>')

mod_pct = 100 * (surf.get(SRC, 0) + 0.5 * surf.get(PART, 0)) / len(plan)

# The prose below the table names three modules by their counts. Typing those in is
# how the page goes stale one increment after it is written, so they come from the
# same rows the table does.
counts = {row[0]: (row[1], row[2]) for row in mod_rows}
written_modules = sum(1 for row in mod_rows if row[1])


def count_of(module):
    h, d = counts[module]
    return '%d of %d' % (h, d)

html = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>neper Readiness</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Spectral:ital,wght@0,400;0,600;1,400&amp;family=IBM+Plex+Mono:wght@400;500&amp;family=IBM+Plex+Sans:wght@400;500;600&amp;display=swap">
<style>
:root {
  --ink:#101418; --ink-2:#42505f; --ink-3:#78838f;
  --rule:#e4e8ee; --rule-2:#eef1f5; --paper:#ffffff; --panel:#f7f8fa;
  --ramp-3:#1a4fa0; --ramp-2:#7297d2; --ramp-1:#c9d8ee; --ramp-0:#dfe4ea;
  --serif:"Spectral",Georgia,"Times New Roman",serif;
  --sans:"IBM Plex Sans","Segoe UI",system-ui,-apple-system,Helvetica,Arial,sans-serif;
  --mono:"IBM Plex Mono",ui-monospace,"Cascadia Mono",Consolas,monospace;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --ink:#e7ecf3; --ink-2:#a7b3c1; --ink-3:#7d8894;
    --rule:#232c37; --rule-2:#1a222c; --paper:#0f1319; --panel:#151b23;
    --ramp-3:#8fb0e6; --ramp-2:#4a6da8; --ramp-1:#2a3a52; --ramp-0:#262f3a;
  }
}
:root[data-theme="dark"] {
  --ink:#e7ecf3; --ink-2:#a7b3c1; --ink-3:#7d8894;
  --rule:#232c37; --rule-2:#1a222c; --paper:#0f1319; --panel:#151b23;
  --ramp-3:#8fb0e6; --ramp-2:#4a6da8; --ramp-1:#2a3a52; --ramp-0:#262f3a;
}
* { box-sizing:border-box; }
body {
  margin:0; background:var(--paper); color:var(--ink);
  font:400 16px/1.6 var(--sans); -webkit-font-smoothing:antialiased;
}
.wrap { max-width:60rem; margin:0 auto; padding:3.5rem 1.5rem 5rem; }
header { border-bottom:1px solid var(--rule); padding-bottom:1.75rem; margin-bottom:2.5rem; }
.eyebrow {
  font:500 .75rem/1 var(--mono); letter-spacing:.14em; text-transform:uppercase;
  color:var(--ink-3); margin:0 0 .9rem;
}
h1 {
  font:600 2.5rem/1.15 var(--serif); margin:0 0 .6rem; letter-spacing:-.01em;
  text-wrap:balance; color:var(--ink);
}
.stand { font-size:1.0625rem; color:var(--ink-2); max-width:46rem; margin:0; }
.stand em { font-family:var(--serif); }
.kpi { display:grid; grid-template-columns:repeat(auto-fit,minmax(13rem,1fr)); gap:1.75rem; margin:0 0 2rem; }
.tile { display:flex; flex-direction:column; gap:.55rem; }
.lab { font:500 .8125rem/1 var(--sans); letter-spacing:.02em; color:var(--ink-2); }
.val { font:600 3rem/1 var(--sans); letter-spacing:-.03em; color:var(--ink); }
.pc { font-size:1.375rem; font-weight:500; color:var(--ink-3); margin-left:.08em; }
.track { height:8px; border-radius:4px; background:var(--ramp-1); overflow:hidden; }
.track i { display:block; height:100%; border-radius:4px; background:var(--ramp-3); }
.sub { font:400 .8125rem/1.45 var(--mono); color:var(--ink-3); }
section { margin:0 0 3.25rem; }
h2 {
  font:600 1.5rem/1.25 var(--serif); margin:0 0 .75rem; letter-spacing:-.005em;
  padding-top:1.5rem; border-top:2px solid var(--ink); display:flex;
  justify-content:space-between; align-items:baseline; gap:1rem; flex-wrap:wrap;
}
h2 span { font:500 .875rem/1 var(--mono); color:var(--ink-3); letter-spacing:0; }
h3 {
  font:600 .8125rem/1 var(--sans); letter-spacing:.08em; text-transform:uppercase;
  color:var(--ink-2); margin:2rem 0 .75rem; display:flex;
  justify-content:space-between; align-items:baseline; gap:1rem;
}
h3 em { font:400 .8125rem/1 var(--mono); letter-spacing:0; text-transform:none; color:var(--ink-3); }
p { max-width:46rem; color:var(--ink-2); }
.tw { overflow-x:auto; }
table { border-collapse:collapse; width:100%; font-size:.875rem; min-width:34rem; }
th {
  text-align:left; font:500 .6875rem/1 var(--mono); letter-spacing:.1em;
  text-transform:uppercase; color:var(--ink-3); padding:0 .75rem .5rem 0;
  border-bottom:1px solid var(--rule);
}
td { padding:.45rem .75rem .45rem 0; border-bottom:1px solid var(--rule-2); vertical-align:baseline; }
tbody tr:last-child td { border-bottom:0; }
.nm { color:var(--ink); width:46%; }
/* Six columns rather than four, so the name gives most of its width back. */
.mods table { min-width:46rem; }
.mods .nm { width:22%; }
.mods .nt { width:34%; }
.nt { color:var(--ink-3); font:400 .8125rem/1.45 var(--mono); }
.sc { font-variant-numeric:tabular-nums; font-family:var(--mono); color:var(--ink-2);
      text-align:right; white-space:nowrap; width:1%; padding-right:1.25rem; }
th.sc { text-align:right; }
.mk { width:1.25rem; padding-right:.6rem; }
.s { display:inline-block; width:9px; height:9px; border-radius:2px; }
.s3 { background:var(--ramp-3); }
.s2 { background:var(--ramp-2); }
.s0 { background:var(--ramp-0); }
.vh { position:absolute; width:1px; height:1px; overflow:hidden; clip:rect(0 0 0 0); }
code { font:400 .875em/1 var(--mono); color:var(--ink); }
.note {
  background:var(--panel); border-left:2px solid var(--ramp-2);
  padding:1.15rem 1.35rem; margin:2rem 0 0; font-size:.9375rem;
}
.note p { margin:0 0 .65rem; }
.note p:last-child { margin:0; }
.note h4 { font:600 .8125rem/1 var(--sans); letter-spacing:.08em; text-transform:uppercase;
           color:var(--ink-2); margin:0 0 .7rem; }
.legend { display:flex; gap:1.5rem; flex-wrap:wrap; font:400 .8125rem/1 var(--mono);
          color:var(--ink-3); margin:0 0 2rem; padding-bottom:.25rem; }
.legend span { display:inline-flex; align-items:center; gap:.45rem; }
footer { border-top:1px solid var(--rule); margin-top:3rem; padding-top:1.25rem;
         font:400 .8125rem/1.6 var(--mono); color:var(--ink-3); }
</style>
</head>
<body>
<div class="wrap">

<header>
  <p class="eyebrow">neper &middot; milestone M2</p>
  <h1>Readiness</h1>
  <p class="stand">Three numbers for three deliverables, each scored against the
  capability list the <em>roadmap</em> and <em>module plan</em> already state. Every row
  below carries its evidence or its gap, so the totals are checkable rather than
  asserted.</p>
</header>

<div class="kpi">
__KPI__
</div>

<p class="legend">
  <span><i class="s s3"></i> delivered &mdash; score 1</span>
  <span><i class="s s2"></i> partial &mdash; score 0.25 to 0.5</span>
  <span><i class="s s0"></i> not started &mdash; score 0</span>
</p>

<section>
  <h2>Compiler <span>__CSUM__ / __CN__ &middot; __CPCT__%</span></h2>
  <p>The furthest along of the three, for a narrow reason: the front end is nearly
  complete while whole back-end subsystems have not been started. It compiles its own
  source on both platforms, and stage&nbsp;2 and stage&nbsp;3 come out byte-identical
  &mdash; the strongest single result on this page.</p>
__GROUPS__
</section>

<section>
  <h2>Modules <span>__DGOT__ / __DTOT__ &middot; __MPCT__%</span></h2>
  <p>Scored by <strong>declaration</strong> rather than by module.
  <code>docs/module-apis.md</code> freezes __DTOT__ declarations across __NMOD__
  modules, and __DGOT__ of them exist in committed source or as compiler intrinsics.
  Counting whole modules gives a similar figure &mdash; __NSRC__ at
  <code>surface:"source"</code> and __NPART__ at <code>"partial"</code> out of __NPLAN__,
  or __MODPCT__%.</p>
  <p>The two framings agree because the delivered modules are finished: every container
  and algorithm module with a count below implements its frozen surface in full. What is
  missing is breadth, not polish. The design layer is a separate story &mdash; all
  __NMOD__ modules have a frozen, mechanically extractable API, which is what makes the
  denominator meaningful.</p>
  <p>The table is the whole plan, not the part that exists: every one of the __NPLAN__
  modules in <code>docs/modules.json</code> has a row, __NWRITTEN__ of them with something
  written. The rest carry what is known about them instead &mdash; the milestone they are
  scheduled for, the tier that says what stability they will promise, and what they are
  waiting on. <strong>core</strong> is the required-first set, <strong>extended</strong> is
  stable but independently delivered, and <strong>experimental</strong> promises no
  compatibility. A module with no milestone is not scheduled yet, which is a statement
  about order and not about doubt.</p>
  <div class="tw mods">__MODTABLE__</div>
  <div class="note">
    <h4>What the two large partials mean</h4>
    <p><code>e.os</code> at __COS__ and <code>e.io</code> at __CIO__ are not stalled
    work. <code>e.os</code> is the subset the compiler needs to build itself, plus
    everything written since as neper source rather than supplied as intrinsics: the
    filesystem calls <code>e.fs</code> needs, sockets, a poller, file mappings, directory
    watches, file locks, process groups, name resolution and the loader. Those are per target,
    over <code>os.syscall</code> on Linux and <code>kernel32</code> through
    <code>@import</code> on Windows, which is what D32 said all along (D97) &mdash; and on Linux
    the resolver is a DNS client written in neper, because that host has nothing to ask (D120).
    The loader is the one place <code>os.linux.e</code> names a library instead of a syscall.
    That did cost something at first &mdash; every binary using <code>e.os</code> came out linked
    against libc, because the compiler emitted every function of every module it touched &mdash;
    which is what dead-function elimination fixed: only what <code>main</code> reaches is emitted,
    so a binary that opens no library is freestanding again and a minimal one went from 221&nbsp;KB
    to 8&nbsp;KB (D130 corrects D128). Nothing in that fence is unwritten:
    <code>last_error_detail</code> was the last, and it waited on a module-scope <code>var</code>
    in the compiler, which is now built. It is a slot per thread keyed by the thread's own
    identifier, with no atomics available inside <code>e.os</code>'s dependency budget &mdash; so a
    detail may be absent and is never another thread's (D132).
    <code>e.io</code> is the subset the compiler needs.
    <code>e.io</code> no longer waits on <code>printf</code>: that expands, over a
    4&nbsp;KiB buffer of its own drained through a generated sink.</p>
    <p><code>e.str</code> is complete at __CSTR__ and is the first module at
    <code>surface:&nbsp;"source"</code> to have needed the compiler for any of it.
    <code>format</code> expands, and so does <code>push_err</code> &mdash; the one
    declaration a library could not write, because what it prints is the qualified
    name and the merged error table is a property of the whole program, where a
    module sees one module at a time. What the expansion still cannot reach is a
    slice, an array or a named type's own <code>format</code>, each of which needs it
    to recurse into an argument.</p>
    <p>What <code>e.io</code>'s remaining declarations wait on is not a compiler
    feature but a decision. Ten of its constructors have to supply a callback of
    their own, and the shape they need &mdash;
    <code>fn(*void, []u8) -&gt; (usize, err)</code> &mdash; is not one the frozen
    surface declares. The language has no visibility mechanism (spec&nbsp;&sect;12), so
    a helper cannot be added quietly: it would be a public symbol the plan does not
    know about. <code>printf</code>'s own sink hit exactly this and was answered by
    generating the function in the compiler, which is one of the three ways the rest
    could go; widening the surface and making the constructors intrinsics are the
    others.</p>
  </div>
</section>

<section>
  <h2>Tooling <span>__TSUM__ / __TN__ &middot; __TPCT__%</span></h2>
  <p>The lowest of the three, and the least surprising. None of the ten specified
  commands emits the JSONL v1 contract yet, and <code>tests/conformance/</code> does not
  exist. What does exist is substantial but internal: a 285-fixture self-host suite on
  both platforms, module-plan validation in CI, and a reproducible-build check. The
  schema, the diagnostic registry and the command surface are designed and frozen;
  nothing emits against them.</p>
  <div class="tw">__TTABLE__</div>
</section>

<div class="note">
  <h4>Method</h4>
  <p>Each capability scores 1 when delivered, 0 when not started, and a fraction
  between when partial, with the reason stated in its own row. Items are weighted
  equally inside a dimension; no dimension is weighted against another, and the three
  numbers are never combined into one. Compiler scope is the CPU language of M1 and M2
  &mdash; GPU (M3) and Metal (M5) are separate milestones, excluded rather than counted
  as zero.</p>
  <p>Module readiness counts declarations present in committed source or seeded as
  compiler intrinsics. Uncommitted work in the tree is deliberately not counted.</p>
  <p>One judgement is worth naming. Self-hosting is four rows out of __CN__ here, but it
  is the binary M2 exit gate. Read the compiler number as capability coverage, not as
  distance to the milestone.</p>
</div>

<div class="note">
  <h4>Keeping this current</h4>
  <p>This page is generated, never hand-edited. <strong>Every session that lands a
  capability updates it</strong>: move the affected rows in the tables at the top of
  <code>scripts/render_progress.py</code>, run <code>python
  scripts/render_progress.py</code> from the repository root, and commit the regenerated
  page with the change that earned it. The module numbers need no editing at all &mdash;
  they are read from <code>docs/module-apis.md</code>, <code>docs/modules.json</code>,
  the committed <code>lib/e</code> sources and the intrinsics seeded in
  <code>src/resolve.e</code>.</p>
  <p>A readiness figure that moves only when someone remembers to move it is worse than
  no figure. This is the single readiness document for the project; there is no second
  copy to keep in step.</p>
</div>

<footer>
  Generated by <code>scripts/render_progress.py</code> from <code>docs/roadmap.md</code>,
  <code>docs/module-apis.md</code>, <code>docs/modules.json</code> and the compiler
  sources, as they stood at <code>__REV__</code> (__DATE__).
</footer>

</div>
</body>
</html>
"""

kpi = '\n'.join([
    meter('Compiler', C, '%.2f of %d capabilities' % (c_sum, c_n)),
    meter('Modules', M, '%d of %d declarations' % (dgot, dtot)),
    meter('Tooling', T, '%.2f of %d capabilities' % (t_sum, t_n)),
])

for key, val in [
    ('__KPI__', kpi),
    ('__GROUPS__', groups),
    ('__MODTABLE__', mod_table),
    ('__TTABLE__', table(tooling)),
    ('__CSUM__', '%.2f' % c_sum), ('__CN__', str(c_n)), ('__CPCT__', '%.0f' % C),
    ('__TSUM__', '%.2f' % t_sum), ('__TN__', str(t_n)), ('__TPCT__', '%.0f' % T),
    ('__DGOT__', str(dgot)), ('__DTOT__', str(dtot)), ('__MPCT__', '%.0f' % M),
    ('__NMOD__', str(len(blocks))), ('__NPLAN__', str(len(plan))),
    ('__NWRITTEN__', str(written_modules)),
    ('__NSRC__', str(surf.get(SRC, 0))), ('__NPART__', str(surf.get(PART, 0))),
    ('__MODPCT__', '%.0f' % mod_pct),
    ('__COS__', count_of('e.os')), ('__CIO__', count_of('e.io')),
    ('__CSTR__', count_of('e.str')),
    ('__DATE__', when), ('__REV__', rev),
]:
    html = html.replace(key, val)

open('docs/progress.html', 'w', encoding='utf-8', newline='\n').write(html)
print('wrote docs/progress.html')
print('compiler %.1f  modules %.1f  tooling %.1f' % (C, M, T))
