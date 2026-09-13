# neper — locked design decisions

Decisions that are settled. Each one constrains everything downstream, so changing
one means revisiting the spec. Recorded with the reasoning so a future reader (human
or model) does not relitigate them. Rows D1–D26 are the original design; D27–D46
were added by the 2026-09-04 review and its three verification passes (2026-09-04);
D47–D50 by the design calls accepted on 2026-09-04 that closed §17's open items;
D51–D53 by the standard-library plan and sample program of 2026-09-04
(`docs/modules.md`, `examples/sample.e`); D54–D64 by the implementation-readiness
audit of 2026-09-04, with later rows superseding the narrower clauses they name;
and D65–D73 by the machine-interface and generated-code audit of 2026-09-04. Later
rows explicitly supersede narrower clauses in earlier rows; historical rationale is
retained but is not normative after supersession. A row that any pass or call changed
carries an `(amended 2026-09-04: ...)`
clause in its Why column — D9 was rewritten outright. Rows that predate D51 spelled
the standard library `core.<module>` and its directory `lib/core`; every one of them
has been rewritten in place to the `e.*` names and the `lib/e` path D51 introduced,
which renames no decision and moves no call site. Ids are sequential and are
never reused.

| # | Decision | Chosen | Why |
|---|----------|--------|-----|
| D1 | Codegen backend | Own direct machine-code emitter (x64, aarch64, x86-32) + SPIR-V/PTX | Compile speed is a headline goal; LLVM costs 10-100x. No external dependency, full control of the binary format. |
| D2 | GPU model | Explicit `@gpu` kernels, restricted GPU subset | A GPU has no unified stack, no recursion, no function pointers. A restricted profile is honest; auto-mapping produces errors far from their cause. |
| D3 | Memory | Stack + explicit arenas. No global allocator, no GC. | Deterministic, trivially fast, maps onto GPU scratch memory, and guarantees no function allocates in secret — which is what makes cross-module inlining cheap. (amended 2026-09-04: "cheap" was about the cost of a call, not about invalidation — an inlined body is recorded as a body-hash edge in `Deps` (§12, D36), so the inliner is recompiled when the callee changes.) (amended 2026-09-04: one exception to "no function allocates in secret" — `gpu.upload`/`gpu.write` take a driver-owned staging block outside every arena for the duration of the transfer (§10); it is named on the page and `gpu.OutOfMemory` is its failure.) |
| D4 | Bootstrap | Throwaway C99 compiler implementing only the `neper-0` subset (roadmap); the self-hosted compiler is written in `neper-0`; M2 gates on the bootstrap compiling it; everything beyond `neper-0` is implemented once in the self-hosted compiler | C99 builds anywhere with no toolchain install. The bootstrap is discarded, so its ergonomics matter less than its portability. (amended 2026-09-04: the bootstrap's scope was never sized — as "everything M1 lists" it was a second full compiler; `neper-0` is what `list.e`-shaped code needs, roughly 15k lines of C99 against some 35k for the full M1 language in C, and it halves what is written twice.) |
| D5 | Compile-time abstraction | Compile-time parameters in `[...]` (§9), monomorphised; one interpreter for four sites — `[...]` arguments, `const` initialisers, `when`, and a call to a comptime-only core function (`meta.fields`, `meta.members`, `meta.type_name`) standing in an ordinary body with every argument comptime-known, folded at the instantiation — the four being what "comptime context" names; with byte-addressed compiler-owned memory in the target's layout and endianness; runtime state (module `var`, atomics other than `atomic.init`, threads, `extern`/OS, `gpu.*`) is a compile error naming the call chain; a `const` result is pointer-free save a `[]const u8` into compiler-emitted read-only data — a string literal or a compiler-synthesised name; 10M steps, depth 1024 and 64 MiB of interpreter memory per evaluation | One mechanism covers generics, compile-time constants and specialisation. Required to write the self-hosted compiler's containers over arenas. (amended 2026-09-04: "touches no runtime state" defined neither runtime state nor the interpreter's memory — with untagged unions and arenas a value-tree interpreter is wrong, and the bootstrap and the self-hosted compiler must produce the same bytes, so the model is byte-addressed and target-laid-out; the budget is what stops a `const` from hanging the build.) (amended 2026-09-04: the step budget bounded time and not space, so a `const` that allocated without looping was unbounded; 64 MiB is the third limit.) (amended 2026-09-04: the runtime-state clause named every atomic operation while §8 makes `atomic.init` comptime-evaluable and legal in a `const`; `init` builds a value and touches no location, so it is carved out here and in §9's list.) (amended 2026-09-04: three evaluation sites left `meta.type_name[T]()` and `meta.fields[T]()` illegal in an ordinary body, which is where §9's own worked example calls them, and left "comptime context" undefined; a comptime-known call to a comptime-only function is the fourth site, and the four define the term.) (amended 2026-09-04: "a literal `[]const u8`" made `const NAME: str = meta.type_name[T]()` illegal, where §9 already lets a `const` hold any `[]const u8` the compiler emits into read-only data.) |
| D6 | Errors | Multi-return `(T, err)` + the `try` form — a keyword prefixing one call, not an operator (§6); error names are module-scoped and qualified cross-module (`os.NotFound`); the value is the 32-bit FNV-1a hash of the fully qualified name, and a name whose hash is `0` is a compile error at the declaration; each `.em` carries a value-to-name table, merged and collision-checked at link; `err` formats as its qualified name, and a value absent from the table as `err(0x<hex>)` | Zero cost, no allocation, no hidden control flow, and every propagation site is one greppable token. (amended 2026-09-04: "globally unique" was undefined — names are unique per module like every declaration, and a hash of the qualified name makes the value a comptime constant with no numbering pass, so adding an error in one module renumbers nothing and `-j N` output stays byte-identical; the per-module table plus a link-time collision check gives `err` a printable name with no reflection.) (amended 2026-09-04: the example was `io.NotFound`, an error `e.io` never declares (D43); it is `os.NotFound`.) (amended 2026-09-04: `try` was called an operator here and in the README where §6 says it is not; §7's hash-is-`0` error and the `err(0x...)` form for a value absent from the table — reachable only through `undef` or a `union` pun — had no row.) |
| D7 | Safety checks | On in debug, elided in release; every **arithmetic** check has a defined release result (wrap, truncate, saturate, masked count, unchecked enum) — never undefined behaviour; an elided **memory** check (bounds, null, tag, align, barrier) leaves the operation to the hardware, which is undefined behaviour as in C; division by zero and `MIN / -1` trap in every mode; `unreachable()` is never elided | Serves "easy to debug" without taxing release builds. Semantics are identical up to the point a check would fire. (amended 2026-09-04: §11 granted C-style "undefined" for release division, which contradicted "elided" — x64 raises `#DE` regardless, so "undefined" bought nothing but licence to miscompile; trapping in every mode costs one compare on the targets that do not trap for free, and keeps release behaviour target-independent.) (amended 2026-09-04: "never undefined behaviour" overclaimed — an out-of-range write with the bounds check off is undefined by any reading, and the `align` row's release result is the hardware's; the claim is narrowed to the arithmetic rows, where it is true and testable.) |
| D8 | Source extension | `.e` | Single-letter, collides with nothing live, keeps harness output short. Compiled modules are `<name>.<target>.em`. |
| D9 | Debug info | Three things, kept distinct. For external tools, **standard formats**: line tables + symbols + unwind always, and locals and types in a fixed twelve-tag DWARF/CodeView subset with `DW_OP_fbreg` locations, on the default path from `neper-0` (the bootstrap emits it too, so the self-hosted compiler is debugged with locals from its first build). For the runtime's own trap backtrace, **`.nepersym`** (D46), on every platform under either linker. Debug builds do not inline; `--g` adds the subset plus `inlined_subroutine` records to a release build. The **neper-format locals/types side table**, debug engine and `neper dap` are the M4 optimisation over that path, never a replacement for it | Rewritten 2026-09-04; the earlier rationale was wrong on two counts. It costed hand-written DWARF against an own format and never costed the debug engine the own format is worthless without — process control, breakpoint patching, stepping, stack walking, location rendering — which is the expensive part and cannot land before M4; the old sequencing left every developer with line tables and no locals through self-hosting and the whole GPU milestone. And it counted editor support as "one adapter" when VS Code and Zed already ship `lldb-dap` and `codelldb` over `lldb`, so the standard format costs zero adapters and an own format costs one plus an engine. A twelve-tag subset with one fixed abbreviation table and frame-relative locations is hundreds of lines, not the "thousands of lines of DIE trees" the old row feared — that cost lives in location lists and expression programs, which are not emitted — and it is read by `lldb`, `gdb`, WinDbg and Visual Studio from `neper-0`. The side table survives as the later optimisation because the `.em` already serialises the type table. Not inlining in debug builds is what makes every frame, breakpoint and step correspond to the page. (amended 2026-09-04: `.nepersym` was used by §11 and §13 with no row of its own and sat beside this one as if it were a fourth standard format; the three are now distinguished — standard formats for external tools, `.nepersym` for the runtime's backtrace (D46), and the side table as the M4 optimisation.) |
| D10 | Baseline ISA | `x64-v3` (AVX2/FMA/BMI) by default, `x64-v4` opt-in, `native` never the default; `aarch64-v8.2` the aarch64 default, `v8.0` and `v8.6` (native BF16) opt-in; `x86-v1` the x86-32 default and its only level | AVX-512 is absent from Alder Lake and later Intel consumer parts, and throttles some earlier Intel server parts. `v3` is near-universal on the last decade of hardware and carries the instructions that matter. Standard microarchitecture levels are adopted verbatim rather than inventing feature flags. (amended 2026-09-04: aarch64 had no default level; `v8.2` is what Apple Silicon and every recent ARM server have, and `v8.0` is 2011-era hardware; x86-32 has one level, so it is the default.) (amended 2026-09-04: §13's table listed `aarch64-v8.6` and this row did not.) |
| D11 | Naming | Compiler-enforced casing, the §3 table being canonical: `snake_case` functions and values (variables, parameters, fields) and modules; `PascalCase` types, enum members, errors and comptime parameters of kind `type` or `fn` (`T`, `Ctx`, `K`); `SCREAMING_SNAKE` constants and comptime parameters of a value kind (`N`, `FMT`, `IDX`, `FIELD`); `snake_case` the comptime binding an unrolled `for` introduces (§9), which is a local binding and not a parameter | Casing tells you a name's kind on sight, and a grep pattern never has to guess. Enforced by `neper fmt --check`, not left to a style guide, because naming drift is exactly what generated code produces. (amended 2026-09-04: the table had no row for comptime parameters, so `neper fmt --check` had no rule for them; a type-kind parameter names a type and takes a type's casing, a value-kind one is a compile-time constant and takes a constant's, and every use in the spec already conforms.) (amended 2026-09-04: the rule was stated three ways — here, in §3 and in §14 invariant 10 — with modules and enum members in only one of them; §3's table is canonical, and this row and invariant 10 name every row of it.) (amended 2026-09-04: the unrolled comptime `for` of D53 binds a comptime value that no row covered, and the `SCREAMING_SNAKE` rule would have claimed it; the rule covers comptime *parameters* only, and `f` in `for f in meta.fields[T]()` is `snake_case`.) |
| D12 | Compiler parallelism | Work-stealing pool, parse phase fully parallel, codegen parallel per function, per-thread arenas, deterministic output | Scaling is architectural, not an afterthought. No preprocessor or macros means every file parses with zero coordination; no global allocator means no allocator contention; work-stealing absorbs hybrid P-core/E-core speed differences that static partitioning cannot. |
| D13 | Linking | Own linker and direct executable emission as the default; the M2 easy case is a freestanding ELF and a PE with a fixed `kernel32` import table; general dynamic imports and the PDB writer (module, symbol and line streams, no type stream) at M4; `--linker=system` kept permanently for static archives and for a Windows build that wants locals in an external debugger (no type stream is scheduled, so only symbolication and line tables move to the own PDB at M4); until M4 it is also required for any Windows symbolication by external tools | Linking is the largest serial section of a build, so it caps the speedup no matter how many cores are available. Code and relocations are already in memory: skipping object files and the process spawn takes a full relink from 100ms–1s to realistically sub-10ms. Staged by difficulty — static pure-neper first, dynamic imports next, static archives never. (amended 2026-09-04: a pure-neper static executable does I/O only on Linux, so without a `kernel32` table the M2 own linker served nothing on Windows, one of the two M0 platforms, and "rebuilds in milliseconds" held on Linux only; `e.io`, `e.thread` and `e.time` on Windows are over dynamic imports by construction, and one fixed DLL is a few hundred bytes. The PDB was promised in §13 and absent from the obligations.) (amended 2026-09-04: "until the PDB writer lands" read as if locals would follow; they do not without a type stream, so the system-linker dependency for Windows locals is permanent and stated.) |
| D14 | Threads | OS threads only, no runtime or scheduler; builtin `Atomic[T]` with explicit orderings, `T` any integer type of §4 or a pointer on the CPU (32- and 64-bit integers in device code); one arena per thread; explicit context pointer instead of TLS; no compile-time race protection | The fast choice and the simple choice coincide. A scheduler adds latency; platform TLS costs a lookup and hides state; race checking would need an ownership system neper does not have (D3). Races on non-atomic locations are undefined behaviour, as in C. (amended 2026-09-04: `Atomic[T]`'s legal `T` was shown by example only; the CPU set is every integer width and pointers because every target has native atomics at each, and the device set is narrower for the same reason.) |
| D15 | Testing | Built in: `@test` attribute, one arena-taking signature, `neper test`, which takes the same optional `FILE.e` operand as `neper fmt` and `neper index` (§13) and then runs that file's module's `@test`s and nothing else. Compiler owns discovery, isolation and reporting only; `e.test` declares `error Failed` and the assertion helpers — `test.assert(cond: bool, msg: str) -> err` returns `Failed` and records `msg` in the test's JSON, never traps; `unreachable()` stays for impossible paths. Execution: a synthesised program root per module — a generated `main` that takes the module name, the start-at test and the control-handle number through `args`, runs the module's `@test`s serially in source order from that test and writes one JSON record per test to the control handle, reaching the module under test through a compiler-internal qualifier no source file can spell, exempt from §2's no-alias rule; one child process per module, modules in parallel under `-j N`, tests within a module serial in source order, a fresh arena per test, stdout/stderr captured per test, a 60-second default per-test timeout (`--timeout`), a crash or timeout recorded as outcome `crashed`/`timeout` with the trap record in that test's JSON object and the module process restarted from the next test; JSON fields `name`, `module`, `file`, `line`, `outcome`, `error`, `message`, `duration_ms`, `timeout_s`, `stdout`, `stderr`, `trap` | A library cannot discover tests — no macros, no reflection, no static initialisers — leaving only a hand-maintained registry whose failure mode is a test that silently never runs. Assertions, fakes and generators stay libraries because they need no discovery. Host-native only; cross-target testing needs an external runner. (amended 2026-09-04: a library assertion needs a primitive that survives release, since every other check is elided — `unreachable()` is that one builtin, and `test.Failed` gives the §13 example a declared error to return.) (amended 2026-09-04: every test in one process on the §15 pool meant the first trap killed the run and the JSON the §14 tooling consumes was never written, while module-scope `var` raced between parallel tests by construction; a process per module isolates a trap at the cost of one spawn per module, attributes the crash to the test that was running, and turns the shared global into an ordered, reproducible hazard instead of a race.) (amended 2026-09-04: the runner was specified over an `os.spawn` that inherited the standard streams and an `e.os` with no pipe or kill, so capture, the control stream and the timeout could not be written over the surface the spec named; `os.pipe`, a `Stdio` argument to `os.spawn` and `os.kill` (D32) are what it uses, and nothing outside `e.os`.) (amended 2026-09-04: the field list omitted the four identity fields §13's Report table requires.) (amended 2026-09-04: the module process had no entry point, so `neper test` synthesises a program root per module — the generated `main` above; and `test.assert` could not be written over `unreachable()`, which takes a `str` literal only and traps, so it is a signature of its own that returns `Failed` and records its message.) (amended 2026-09-04: the synthesised root had to `use` the module under test, and for a module named `main` that qualifier collided with the generated entry point, while §2 as written made a library's `fn main` a second program root; `main` is special only in the root module (D41), and generated code reaches the module under test through an internal name that source-level invariants do not govern.) (amended 2026-09-04: `neper test` took no `FILE.e` where `fmt` and `index` did, so no example's `@test` could ever run — a file outside every source root is a module only when a command names it (§2) — and it now takes that same operand with that same meaning.) |
| D16 | Attribute placement | Attributes sit on their own line at column 0, above the declaration | `@gpu fn saxpy(...)` would break invariant 2 — `grep "^fn saxpy"` would miss exactly the annotated functions. Keeping the keyword first on its own line preserves every §14 guarantee. |
| D17 | Tuples | None. `(A, B)` is a return calling convention, not a type — no storing, no passing, no `.0`. Two return classes — integer (integers, pointers, enums, `err`, `bool`) and vector (floats of every width, `Vec[T, N]`) — each with a per-target budget in values (x64 2+2, aarch64 2+2, x86-32 2+1), assigned to the class's registers in declaration order; when either budget is exhausted the whole set returns through a caller-provided slot; an aggregate — `struct`, `union`, `union enum`, `[N]T`, a slice, `str` — belongs to neither class and is never returned in registers, a set containing one going entirely through the slot | Positional access is unanchored for search and unreadable in generated code; a named struct costs one line and gives every field a name. No layout is visible to the program, so there are no equality or ordering rules to define, and there is exactly one way to spell a product type. `gpu.launch` takes trailing comptime-checked arguments instead of an argument tuple. (amended 2026-09-04: "returns stay in registers" was false for `(List[T], err)`; the convention is registers up to `N` per target and a caller slot beyond, and the semantic claims stand.) (amended 2026-09-04: three independent budgets gave scalar floats and `Vec` values the same physical registers, so a mixed set such as `(f32, Vec[f32, 4])` had no assignment; two classes with one register sequence each, filled in declaration order, give every set exactly one.) (amended 2026-09-04: an aggregate belonged to neither class, so `(List[T], err)` had no rule after all; aggregates take the slot, and only the two scalar classes use registers.) |
| D18 | Const qualifier | `*const T` and `[]const T`; string literals are `[]const u8`; `[]T` → `[]const T` and `*T` → `*const T` are the mutability-losing conversions in spec §6's list of implicit operations, which is the one canonical list; the constness of `&e`, `e[lo..hi]` and an assignment through `e` is that of the innermost pointer or slice step on the path to the place, and of the binding (`var` mutable; `let`, parameter, `const` immutable) only when there is no such step; read-only library slice parameters are `[]const T`; `[]const T` is shallow | Without it `let s = "abc"; s[0] = 'x'` compiles and segfaults — a runtime fault where a compile error belongs, in a language selling debuggability. Qualifies the pointee only, cannot be cast away, exists in two positions and nowhere else. (amended 2026-09-04: with no rule for `&x` and `x[lo..hi]` on a `let` place the guarantee was undelivered — `let p = &v; p.x = 1.0` compiled; the const forms close it, and `[]const T` library parameters let a literal or a `let` array fit without a cast.) (amended 2026-09-04: "the one implicit conversion" disagreed with §4's two and §6's two, and §10's `Buf[T]` mapping was a fourth nobody listed; §6 now holds the single list of four and every other section points at it.) (amended 2026-09-04: "on a `let`, a parameter or a `const` path" matched a pointer-typed parameter and its pointee's step with opposite results, so `list.e`'s `l.items[0..l.len]` had two types; the innermost step decides, and a parameter of pointer or slice type contributes its own type as that step.) (amended 2026-09-04: "two positions and nowhere else" is stated as the pointee of a pointer or slice type, which includes §10's address-space-qualified device forms `*const shared T` and `[]const shared T`.) |
| D19 | Argument packs | Trailing `...` parameter, comptime-only, monomorphised per shape; in v1 it appears only in the intrinsics `io.printf`, `str.format` and `gpu.launch` — not declarable as a pack in user or library code (the `...` on an `extern`, D32, is a C variadic under a separate rule), no pack API; `gpu.launch[K: fn]` takes its kernel as a comptime parameter of kind `fn`, never as a runtime argument | Formatting and kernel launch both need variadics; one token serves the three, with no `va_list`, no runtime variadics, no boxing. (amended 2026-09-04: the "one general mechanism" claim was wrong — with no length, indexing or type dispatch a pack is usable only by the compiler, so packs hide `gpu.launch`'s exception behind a token rather than removing it; recorded as three intrinsics, which is one paragraph and costs no interpreter feature.) (amended 2026-09-04: `launch` took `k: kernel` at runtime, a type defined nowhere, so the compile-time check of the pack it promised had no mechanism — the kernel is now a comptime `K: fn`, which is what `printf[FMT]` and `thread.spawn[Ctx]` already do.) |
| D20 | Equality | `==` on primitives, pointers and enums only; slices, structs, unions and arrays use explicit functions | `==` on a slice would compare pointer and length rather than contents — a silent wrong answer, which is the worst kind. |
| D21 | Time | `e.time` is UTC-only and allocation-free; `Timestamp`/`Instant`/`Duration`/`Date`/`Time` are distinct types; zones are an explicit minute offset; leap seconds ignored; every comparator and arithmetic function over a clock type is spelled `<t>_<op>` — `timestamp_cmp`, `instant_cmp`, `duration_cmp`, `timestamp_add`, `instant_add`, `duration_add`, `timestamp_diff`, `instant_diff`, `duration_sub`, `duration_neg`, `duration_scale` — so each type satisfies §9's protocols | IANA tzdata is megabytes plus file I/O plus a parser, none of which fits a freestanding core that allocates nothing. Distinct types make "measured elapsed time with the wall clock" a compile error rather than a production bug, and cost nothing given no implicit conversions. A real tz database is a separate library. (amended 2026-09-04: spelled `cmp`, `cmp_instant`, `cmp_duration`, no `e.time` type had a protocol `cmp` and none could be sorted; under D52's `<t>_<op>` the suffixes are the protocol convention rather than a workaround for having no overloading.) |
| D22 | Device memory | `gpu.Buf[T]` is a distinct host type whose `T` is a device type (plain data: no pointers, slices or `bool`; `err` is a `u32` and is one), mapped onto a kernel's `[]T`, `[]const T` or `[]Atomic[T]` parameter by `gpu.launch`; the SPIR-V floor is Vulkan 1.2 with `bufferDeviceAddress` and `scalarBlockLayout`, so a device slice is §4's `{ 64-bit address, len }` header under `PhysicalStorageBuffer64` with the CPU's sub-slicing and the `len` at the device's `usize` width; `usize` is 32 bits on `spv` and, with `isize`, is therefore not a device type — legal as a kernel local, never in a `Buf[T]` element or a kernel parameter; address spaces are part of the type — `[]T` device, `[]shared T` workgroup, no conversion — and private memory has no pointer or slice type in device code | A host pointer is meaningless on the device and the reverse. Making them different types means the compiler enforces the boundary instead of a naming convention. No unified address space in v1. (amended 2026-09-04: a `[]T` had no device representation at all — under logical addressing a pointer carries a storage class, cannot be re-based and cannot be stored, so `x[k..]` and one helper over a buffer and a `shared` array were inexpressible; the 1.2 floor makes the slice one type on both profiles at the cost of excluding Vulkan 1.1 devices, POD-only elements under scalar layout make an upload a memcpy, and a 32-bit `usize` keeps indexing off the optional `Int64`.) (amended 2026-09-04: a `usize` field in a buffer would have had two layouts, one per side, and "an upload is a memcpy" was false for it; excluding the two target-width integers from device types keeps the layout rule true, and `launch` writes each slice's `len` at the device's width.) (amended 2026-09-04: on `.Cpu` there is no driver, so `gpu.alloc` and the staging block had no memory source — a hidden allocation D3 forbids; the CPU backend takes every `Buf[T]` from the arena passed to `gpu.open`, exhaustion being that arena's `mem.Exhausted`, while the driver backends use device memory and that arena for the bookkeeping block alone.) (amended 2026-09-04: whether an `err` could exist in device code was unstated; it is an ordinary `u32`-backed value there — helpers return `(T, err)` and `try` between them, only a kernel entry point returns nothing — and as a `u32` in every layout it is a device type, so a kernel can report failure by writing one into a `Buf`.) (amended 2026-09-04: the previous clause also gave `.Cpu` a staging block, which §10 elsewhere called a plain memcpy; on `.Cpu` there is no staging — `upload` and `write` copy straight into the `Buf`'s storage, allocated once at `alloc`/`upload` — and staging exists on the driver backends only.) |
| D23 | GPU async model | `gpu.Queue` from `gpu.queue(dev)`, and every call that submits work — `alloc`, `upload`, `write`, `launch`, `download`, `sync`, `release` — takes a `*Queue`, while `open`, `close`, `has`, `queue`, `len` and `grid*` take none; a queue is an in-order stream used by one thread at a time, a `Device` is thread-safe because `open` takes one bookkeeping block from its arena and guards that block with its own lock — the one locked arena memory in `lib/e`; `launch` queues and returns; `upload`/`write` copy the source into driver-owned staging synchronously, then queue the transfer — the source is free on return, the cost is one memcpy; `download` synchronises that queue, then copies; `gpu.sync(q)` waits for that queue only; `release` is queued behind prior submissions, so `defer gpu.release` is safe by construction; queues are unordered with respect to each other and a buffer shared across them without a `sync` is a race | Overlap between host and device is the reason to have a GPU. `download` syncs implicitly because a stale read is a silent wrong answer, the failure mode this language works hardest to eliminate. (amended 2026-09-04: no `Queue` type existed, so `sync` and `download` could only drain the whole device and stall the independent streams the same paragraph promised; an asynchronous `upload` from a host slice with no lifetime rule corrupted the double-buffer pattern silently, and the synchronous staging copy costs one memcpy where a lifetime rule costs a check the compiler cannot make; `release` appeared in every example with no ordering.) (amended 2026-09-04: "usable from any thread" while allocating from an arena D14 declares not thread-safe was a race by construction; a single block taken at `open` and a lock inside the `Device` resolve it without making arenas thread-safe.) (amended 2026-09-04: "every host call takes a `*Queue`" was false for the six device-level calls, and §10's thread rule listed `alloc` among calls made on a `*Device`; `alloc` is a queue call and the concurrent set is `queue`, `has`, `close`.) |
| D24 | Device-callable inference | `@gpu` marks kernel entry points; a plain `fn` reached from a kernel is compiled for the device too, and must satisfy the GPU restrictions; the device copy is emitted into the kernel-owning module's `.em` with module-local linkage and recorded as a body-hash edge; a helper that uses any `gpu.*` builtin or names a `shared` type is device-only, and a helper over both address spaces is a generic over the slice type, monomorphised per space | Otherwise `@gpu` spreads down through every leaf helper. Errors are reported at the kernel with the call chain reaching the violation. (amended 2026-09-04: inference compiled another module's body into the kernel's module with no invalidation rule and no stated owner; D36 supplies the rule, and module-local emission means no ownership protocol between modules.) (amended 2026-09-04: address spaces are part of the slice type, so a helper reached with `[]shared T` is one more instance in the kernel-owning `.em`, placed by the same rule.) (amended 2026-09-04: the device-only rule named three builtins where D37 and §10 say any `gpu.*` builtin — `gpu.gid`, the barriers included; aligned.) |
| D25 | Narrow floats | `f16` (binary16) and `bf16` are primitive types; arithmetic is "compute in `f32`, round after every op"; native instructions used where the target has them | Storage bandwidth is the reason they exist and any GPU or AI-adjacent workload needs them. The compute-then-round rule is bit-identical to native half hardware for `+ - * / sqrt`, so results are deterministic across targets whether or not the CPU has FP16/BF16 instructions. |
| D26 | Apple GPUs | MoltenVK is the supported-but-second-tier path now; a native Metal backend is scheduled as M5; GPU capabilities (`f64`, `f16`, subgroups, 64-bit atomics) are checked per device at `gpu.launch` | Apple ships no Vulkan. A GPU backend is the most expensive kind of target — emitter plus runtime — and Apple is one vendor, so it follows the core targets rather than delaying them. Capability checks must be at launch because the compiler cannot know the device. |
| D27 | Literal and index typing | An unsuffixed literal is an untyped comptime value typed by its immediate context; with no context it is a compile error, never `i32`; type suffixes `42u64`, `1.5f32`; indices and `.len` are `usize`; `a..b` has its bounds' type; GPU ids are `u32`; comptime inference is unambiguous only when every non-literal argument whose parameter type mentions the parameter agrees on one type, and the literals are then typed by the parameter | With no implicit conversions, the type of every literal must be legible on its line, because under §11 it decides where arithmetic wraps. A default of `i32` would have `atomic.add(&c.hits, 1, ...)` and `max(3, 9)` disagree on what a bare literal is. Go's untyped constants and Zig's `comptime_int` show the rule costs nothing; the error-without-context is the price of never guessing on a model's behalf. (amended 2026-09-04: the row dropped "whose parameter type mentions the parameter", which let an unrelated argument appear to vote; aligned with §9.) |
| D28 | Local initialisers and zero values | Every local requires an initialiser; `= zero` is a visible memset, legal on an annotated `let` or `var`, and `= undef` is no store (`0xCD` fill in debug), legal on an annotated `var` only and banned inside `@gpu`; `try` returns the zero value in every non-`err` slot; the zero value is defined for every type, and an `enum` with no member at `0` has none | An uninitialised local is either a hidden memset or an unchecked read, against Goals 2 and 6 at once. Two spellings put the cost on the page, and a definite value beside a failed `try` means two conforming compilers produce the same binary instead of two different ones. (amended 2026-09-04: §5 said both spellings were `var`-only and then banned only `undef` on `let`; `let x: T = zero` is a definite constant and is legal.) |
| D29 | Tagged unions | `union enum u8 { A: X, B }` beside bare `union`; payload access is tag-checked in debug; `case .A as x` binds the payload; `switch` on an enum or tagged union is exhaustive unless `default` is present; the optional is `union enum u8 { Some: T, None }` with no keyword | A compiler is mostly variant types, and a wrong-member read on a bare union is a silent wrong answer with no check in §11. The tag-then-payload layout is byte-identical to the hand-rolled `struct { kind, u }`, so placing the tag hides no cost — the earlier "will not hide the cost" rationale was wrong. Exhaustive `switch` turns an added variant into a compile error at every stale switch. (amended 2026-09-04: the byte-identity holds on the CPU; in device code the payloads are laid out without overlap, since SPIR-V cannot alias typed members over one storage, and the program cannot observe which — so neither `union` form is a `Buf[T]` element type. Bare `union` is kept as the C-ABI escape hatch, not as the punning form: `mem.bitcast` puns without one (D49).) |
| D30 | By-value argument aliasing | The storage of a by-value argument is written by no one for the duration of the call; doing so is undefined behaviour | Mirrors D14. It makes hidden-reference passing a pure ABI choice: the compiler may pass the caller's storage by address with no copy and no alias analysis, which the `-O1` optimiser does not have. Without it either every 64-byte matrix is a memcpy per call or a write through another pointer changes a by-value parameter. |
| D31 | Conditional compilation and reserved names | `target` is a builtin comptime namespace (`target.arch: target.Arch`, `target.os: target.Os`, PascalCase members) needing no `use`; `when` is statement-level only; target-specific module-scope declarations live in per-target files `<name>.<arch\|os>.e`; a `use` qualifier cannot be shadowed by any declaration; `_` is reserved; `@cpu` is removed until runtime dispatch lands, then spelled `@cpu("x64-v4")` | `when` around a declaration would break §14's column-0 and order-independence invariants, while a per-target file is found by glob like every other module. Reserving the qualifier keeps `mem.alloc` one thing in every scope, which is the reason qualified references exist; a function-pointer field named `mem` would otherwise make a call site ambiguous. |
| D32 | Foreign functions | Column-0 `extern fn` with `@import(LIB, SYM)` and `@cc(c\|sysv\|win64\|stdcall)` attribute lines — `sysv` and `win64` compile errors on any target but x64 — they exist only to force a non-native convention there, `c` being the native convention everywhere — and the convention part of an `extern fn` pointer type, so two conventions are two distinct types, a pointer type naming its convention by a `@cc(CONV)` line above `type Cb = extern fn(...) -> R` and an `extern fn` type without one being `c`; a closed C-ABI mapping — primitives, pointers, `*void`, enums, by-value structs and unions cross; slices, `err`, multiple returns, tagged unions, vectors and arrays by value do not; `...` on an `extern` is a C variadic with no default promotions; no `err`/`try` on an `extern`; `@cc` on a plain `fn` makes it C-callable, a generic `@cc fn` instantiating one C-callable function per instance, under the same signature rule as an `extern`; a pointer to a `Vec[T, N]` or an `Atomic[T]` crosses as `T*` although the value does not; banned inside `@gpu` and at compile time; `e.os` is the sole OS surface of `lib/e`, written per target over raw syscalls (Linux, via the `os.syscall` and `os.thread_start` intrinsics), `kernel32` (Windows) and `libSystem` (macOS), and includes `os.pipe`, an `os.spawn` that takes the child's three standard streams, and `os.kill` | The language could not name an external symbol, a library or a calling convention, so `e.io`, the thread pool, the root arena, `--linker=system`'s process spawn and the Vulkan runtime could not be written in it; a fixed intrinsic set gets hello.e running and cannot scale to a driver's hundreds of entry points. The foreign name is a string so the neper-side name keeps D11; a separate keyword keeps §14's column-0 set exact. The mapping is closed so "does this type cross" is answered at the declaration, and `err` stays out because C has no such value — the `e.os` wrapper is where a platform code becomes one. Raw syscalls on Linux keep the freestanding executable D13 stages first; libSystem on macOS is the lesson Go learned in 1.12. (amended 2026-09-04: the pointer row and the `Vec`/`Atomic` rows of the ABI table disagreed, the Linux stack switch had no name a source file could call, `thread_create[Ctx]` on Windows needed a trampoline the text could not express, and `neper test` (D15) needed pipes and a kill the surface lacked.) (amended 2026-09-04: the three standard streams could not carry the test runner's control pipe, so `Stdio` also carries `inherit`, extra handles the child inherits, their numbers passed to it through `argv`.) (amended 2026-09-04: §9 said no generic could be taken as a value, which the per-`Ctx` trampoline needs; an explicitly bracketed instance `f[Ctx]` is a value — a pointer to that one instance — and the inferred form still is not. An inherited handle keeps its `raw` value in the child on both platforms, so that is the number `argv` carries; `os.syscall` and `os.thread_start` are declared in `os.linux.e` alone.) (amended 2026-09-04: what `@cc(sysv)`/`@cc(win64)` meant on a non-x64 target, and whether the convention was part of the pointer type, were unstated; a convention the target cannot honour is an error at the declaration, and a pointer type that dropped it could be called under the wrong one.) (amended 2026-09-04: `@cc` had no type-level syntax, so no pointer type could name its convention; it is an attribute line on the `type` declaration. The `kernel32` example carried `@cc(win64)`, an error on aarch64 — it is `@cc(c)`. And `os.syscall`/`os.thread_start` are intrinsics: they appear in no `.e` file, `os.linux.e` included, and are compiler-known on Linux alone.) |
| D33 | Trap protocol and checked operations | A failed check writes `file:line:col: trap[kind]: <values>` plus a symbolised backtrace to stderr and exits `134`; under `neper test` the same record lands in the test's JSON; `unreachable()` is the one always-on builtin (a keyword, no `use`); integer narrowing casts trap in debug and truncate in release, `T.trunc(x)` truncates by intent; a float-to-integer cast rounds toward zero and, out of range or NaN, traps in debug; in release an out-of-range value saturates and NaN yields `0`, on every target; a cast is not a typing context for an untyped literal; shifts by `>=` width trap / mask, the count being independent of the left operand — any unsigned integer type, a literal typed `u32`; out-of-range `enum` casts trap / unchecked; `/` `%` by zero and `MIN / -1` trap in every mode | "Illegal instruction" at a `ud2` is a debugger session where one line would do, and the line tables, symbols and unwind info are emitted in every build already, so the record and the backtrace are nearly free. The record has a compiler diagnostic's shape so §14 tooling parses one format. Every cast and shift must have a stated result in both modes or "behaves identically until a check fires" is unfalsifiable; the release results are the C results because the hardware gives them for free. `134` is `128 + SIGABRT`, what every crash pipeline already classifies as an abort. (amended 2026-09-04: float-to-integer had no rule at all, and the two obvious hardware results differ — x64 gives the integer-indefinite value, aarch64 saturates — so a target-independent release result had to be chosen; saturation is aarch64's for free and a few instructions on x64, and it is what `simd.convert` already promised lane-wise. The shift count's type was unstated and is load-bearing under "no implicit conversions".) (amended 2026-09-04: a literal count typed `u8` contradicted §3's rule that a literal takes the other operand's type when the left operand is signed; the count is independent of the left operand, must be unsigned, and a literal is `u32`.) (amended 2026-09-04: the row said NaN saturates where §4 and §11 give `0`; aligned to the spec.) |
| D34 | Program entry | `fn main(a: *mem.Arena, args: []str) -> err` in the root module, no variants; `ok` exits `0`; any other value writes `error: <qualified name>` to stderr and exits `1`; a trap exits `134`; the root arena is the one passed in, sized by a link option; `args` live in it | Mirrors `@test`: one signature, and a different one is a compile error rather than a convention. The root arena has to reach the program through some door, and a parameter is greppable where a global or a `mem.root()` call is not; the examples were carving stack buffers because no door existed. The failure line reuses the error table D6 already pays for, so no reflection primitive is needed and the roadmap's exclusion of runtime reflection stands. |
| D35 | Arena fills and builder precondition | Debug only: `mem.reset` fills `[m, off)` with `0xDD`, `mem.alloc` fills fresh memory with `0xCD`; `str.push` checks in every mode that the builder still owns the arena top and returns `str.NotOnTop`; a growable container's contract states that slices do not survive a `push` | The one lifetime hazard arenas create is a slice outliving `reset`, and a range memset needs no per-object bookkeeping, so D3 is untouched; two distinct bytes tell "freed" from "never written" in a debugger. The builder's in-place growth is a precondition the compiler cannot prove, and one compare turns a silent overwrite into an `err`. The `push`-abandons-buffer hazard cannot be poisoned — the old memory stays valid — so it is a documented contract, as in Zig's arena-backed lists. |
| D36 | Incremental rebuild invalidation | Per-declaration signature and body hashes; `Deps` holds `(module, symbol, hash)` edges — signature edges for references, body edges for anything inlined, instantiated, comptime-executed or device-compiled, and negative edges `(module, name, absent)` for every protocol name (§9) looked up and not found, every compiler-supplied fallback included; a module recompiles when any edge changes, a negative edge changing when the name is later declared; cross-module inlining capped at 40 NIR instructions per callee; monomorphised instances and device helpers are emitted into the instantiating or kernel-owning `.em` with module-local linkage and folded by content hash in the own linker; an incremental build's output must equal a clean build's, checked by the M2 harness | A per-module interface hash with "body edits never disturb dependents" shipped stale code the moment a body crossed a `.em` boundary — and four mechanisms make bodies cross: inlining, monomorphisation, the comptime interpreter and D24. Recording exactly which bodies were compiled in is the only rule that is both correct and cheap: a signature edge is what a call needs, a body edge is what an expansion needs, and the cap keeps the second kind to leaf helpers so ordinary edits stay local. Delphi's DCUs learned the same lesson with `inline` bodies. Module-local instances need no cross-module ownership, which keeps compilation parallel; folding by content hash is free given §15's determinism. (amended 2026-09-04: edges recorded only symbols that exist, so declaring a `fn sensor_hash` after an instantiation had fallen back to the compiler-supplied `hash` invalidated nothing and the fallback shipped for ever; a negative edge records the absence, and declaring the name changes it.) |
| D37 | Kernel geometry, shared memory and device synchronisation | `@gpu(X, Y, Z)` carries the workgroup size and bare `@gpu` is a compile error; `gpu.launch[K]` is a kernel's only caller on both profiles — a direct call to an `@gpu` function is a compile error; a helper using any `gpu.*` builtin or a `shared` type is device-only; `gpu.subgroup_ballot` adds `.Int64` to the inferred set; `gpu.grid1/2/3` count invocations and `launch` rounds up to workgroups, returning `gpu.TooLarge`/`gpu.Unsupported` when a device limit is exceeded; `shared` is a keyword and `shared var name: T` an uninitialised statement legal only directly in a kernel body; helpers receive it as `[]shared T`; `gpu.barrier()` is a Workgroup control barrier with AcquireRelease over workgroup memory and must be in uniform control flow, `gpu.memory_barrier(.Workgroup\|.Device)` orders device memory; device atomics are `gpu.atomic_*` with a scope, on `Buf[Atomic[T]]`, `[]Atomic[T]` and `shared Atomic[T]`; a minimal subgroup set (`size`, `sid`, reductions, `all`/`any`/`ballot`, `broadcast`/`shuffle`, `elect`); the capability set is inferred per kernel into its `.em` Interface entry and checked at launch, `caps(...)` in the attribute is a compile-time upper bound; a type-to-capability table; `Vec[T, N > 4]` splits into four-lane vectors on SPIR-V | SPIR-V needs `LocalSize` at compile time and PTX the block size at launch, and `lid`, `shared` and `barrier` mean nothing without it; an invocation count is what a caller holds (`x.len`), so the division belongs in `launch` and the guard stays in the kernel where it is visible. A statement keyword keeps §14.2's column-0 set exact and the module-scope `var` ban intact; no initialiser because no single invocation could run one. A barrier with no stated scope and memory semantics cannot be emitted, and scoped atomics are the device's model — hiding the scope would make `.Device` a silent default. `gpu.atomic_*` rather than a second `atomic.*` signature keeps one signature per name (§14). Inference keeps the capability set honest; the upper bound exists because a helper edit could otherwise add a desktop-only capability to a mobile kernel with no diagnostic until launch. (amended 2026-09-04: "on the CPU it is also an ordinary function" gave `gpu.gid`, a `shared var` and `gpu.barrier()` no meaning in a direct call — there is no grid — so the call is an error rather than a hidden behaviour; the ballot's `u64` silently needed `Int64` and now says so.) |
| D38 | CPU execution model for kernels | The CPU backend (`gpu.open(a, .Cpu, 0)`) runs a launch on the calling thread, one workgroup after another; a workgroup runs on one host thread by barrier loop-fission — the body cut at every barrier and subgroup builtin into regions, each looped over the invocations in `lid` order, one slot per invocation for a local that crosses a barrier, one `shared` storage per workgroup filled `0xCD` in debug; a breakpoint stops at one invocation's iteration with the workgroup's state visible; a debug check traps with kind `barrier` when invocations reach different barriers or return before one; subgroups are 32 consecutive invocations, the last of a workgroup partial when the size is not a multiple of 32, with inactive lanes reading `false` and contributing nothing; address-space qualifiers are erased | The CPU build is the only debugger and the only test vehicle for kernels, so it must have the device's semantics rather than a serial approximation in which a missing barrier or a shared-memory race disappears — CUDA dropped its emulation mode because it diverged from the device. One OS thread per invocation with a host barrier is the obvious alternative and is hundreds of context switches per barrier, unsteppable in practice; loop-fission (pocl, Intel's CPU OpenCL) reproduces the barrier's exact ordering on one thread with no runtime, and makes "step one work item" a plain loop iteration. The divergence check is the one thing the CPU can do that the device cannot, and it catches the bug class that hangs a GPU. (amended 2026-09-04: a workgroup size such as `@gpu(100)` left the last subgroup's size and ballot bits unspecified; the partial-subgroup rule mirrors the device.) |
| D39 | Floating point | No implicit contraction in any build mode on any target; `math.fma` is the only FMA; every SPIR-V result carries `NoContraction`, with correctly rounded division and square-root sequences; PTX uses the `.rn` forms and never `.approx`; `min`/`max` are IEEE `minimum`/`maximum`; denormals preserved by default, with `@gpu(..., ftz)` opting a kernel into flush-to-zero on device and CPU build alike; the approximate builtins — the `e.math` transcendentals, `math.rsqrt`, float subgroup reductions — are listed in §11 and are the only permitted divergence | Every GPU compiler fuses `a*b + c` by default and the default CPU level carries FMA, so without a rule the CPU build and the device disagreed in the last bit with no check firing — the silent wrong answer D23 names, inside the debugger itself. Exactness by default costs one rounding per operation, which is what the source said; a generator that wants the fused result writes `math.fma` and the reviewer sees it. Vulkan bounds division to 2.5 ULP, so bit-identity needs a software sequence there; it is a handful of instructions and the only way M3's criterion is testable. Flush-to-zero is a per-kernel opt-in because it is the one IEEE deviation with a real GPU cost, and it is applied to the CPU build too so the two still agree. |
| D40 | SIMD | The vector type is the builtin generic `Vec[T, N]` — `T` an integer or float primitive, width `N * mem.size_of[T]()` of 16, 32 or 64 bytes, a closed table of 36 pairs — with `Mask[T, N]` as its mask type and no `f32x8`-style aliases; a `simd` module of comptime-generic intrinsics: `splat`, `load`/`store` (unaligned, aligned with an `align` check, masked), `shuffle` with a comptime index array, `cmp_*` to masks, `select`, `any`/`all`/`bits` reading a mask, `reduce_add/min/max` in a fixed pairwise tree, `convert`, `gather`, `fma`, `pdep`/`pext`; integer lanes take only the wrapping operators; vectors are a register class passed in vector registers at any width, exempt from the hidden-reference rule, and returned in them up to the per-target budget (two on x64 and aarch64, one on x86-32), through the caller slot beyond it; `N > 4` splits into four-lane vectors on SPIR-V, and `Mask[T, N]` is a register-only type on both profiles — a local, a parameter, a return value (passed and returned as the `Vec[T, N]` it masks, in the vector class under §5's budget) or an intrinsic operand, never a field, an element, a module-scope `var`, a `Buf[T]` element or a pointee, `mem.size_of` on it a compile error, `= zero` on a local all lanes `false`, `simd.bits`/`simd.mask` converting to and from an integer bitmask for storage — and never a device type; in device code the slice parameter of the load/store/gather intrinsics is generic over the address space; `simd` ships in M1 | A vector type with `splat` and elementwise arithmetic and no load, store, mask, shuffle, compare, reduction or FMA could not deliver Goal 3, and an open-ended type list meant a generator could not know whether `i16x8` was legal. `Vec[T, N]` is the D5 form every other parameterised builtin uses, so a suffixed family with suffixed intrinsics (`splat_f32x8`) was the one naming exception in the language. Wrapping-only integer lanes tell the truth about hardware with no overflow flag, instead of letting `+` mean `+%` in one type; the fixed reduction tree and lane-wise `fma` keep vector code under D39's bit-identity rule; the register class is what every ABI does with vectors and what the hidden-reference rule would have got wrong. (amended 2026-09-04: §5's two-word vector budget sent a `Vec[u8, 64]` to the slot that §4 said it never entered; `Mask` had no SPIR-V form and the loads took only device-space slices, so no vector could be loaded from `shared` memory.) (amended 2026-09-04: "never entering the return slot" still contradicted §5's budget; §5 is right — vectors return in vector registers up to the per-target budget of two and through the caller slot beyond it, like any aggregate.) (amended 2026-09-04: "device type" is §10's term for what a `Buf[T]` element or kernel parameter may be, and `Mask` is not one; the budget is §5's per target, not a universal two; `any`/`all`/`bits` were defined in prose and missing from the intrinsic table.) (amended 2026-09-04: register-only was stated for device code alone, which left a `Mask` field or array on the CPU with a size that varied by level — a `k` register at `x64-v4`, a full vector below it — visible through `mem.size_of`; a type whose representation the program cannot see cannot be stored, so it is register-only everywhere, and the bitmask conversion is its storage form.) (amended 2026-09-04: a `Mask` parameter or return value had no convention — it was in neither §5 return class, has no size for the hidden-reference rule and cannot be a pointee for the slot; it travels as the same-width all-ones/all-zeros vector every level can produce, which is the `Vec[T, N]` convention.) |
| D41 | Source roots and module names | `lib/` and `src/` are the two source roots; a module's name is its path below the root with `/` as `.` (`lib/e/mem.e` → `e.mem`, `src/main.e` → `main`); a per-target suffix is not part of the name; a file declaring `fn main` is a program root when it is the file named to the command, and `main` is an ordinary function in every other module; `neper run <file.e>` takes one, and `neper build <file.e>` takes one or any other `.e` file, compiling a file without `main` to `.em` files and no executable; the named file is a module — named from its root when it lies under one, by its bare filename otherwise, so `examples/hello.e` is `hello` and runs from any directory; the project root is the nearest ancestor of the named file (of the working directory, for `fmt`/`test`/`index`) holding `lib/` or `src/`, else that directory itself; the toolchain's own `lib/` beside the binary is a third source root on every command, consulted for a module name the project's roots do not define, which is where `e.*` lives; `neper test` runs every module under the project's roots; a backtrace frame is `module.function` | §2's one example (`lib/e/mem.e` → `e.mem`) already dropped a segment by an unstated rule, the trap example mapped `src/lex.e` to `e.lex`, the root module had no name, and `neper build` took no file. Two fixed roots keep "path is module name" true and a glob sufficient; a configurable root would put the name in a config file, which §2 exists to avoid. (amended 2026-09-04: under the two-root rule the shipped examples were not modules, so M0's `neper run examples/hello.e` named a file the spec could not compile; a program root is named from its own directory, which makes `examples/hello.e` module `hello` without `examples/` being a package.) (amended 2026-09-04: the project root was defined only for a program root and only for naming, so `use e.mem` in `hello.e` had no directory to resolve from, `neper test` no scope, `lib/e` no way to be built, and `vec3.e`/`list.e` — no `main` — no command that compiled them; the toolchain's `lib/` as a third root with the project's roots taking precedence answers all four without a config file, and a non-root file given to `neper build` is a module like any other.) (amended 2026-09-04: "a file that declares `fn main` is a program root" made `main` special in every module, so a library could not declare one and a module named `main` could not be tested; `main` is special only in the root module, and the test root reaches the module under test through a compiler-internal name exempt from the no-alias rule, generated code not being subject to source-level invariants (D15).) |
| D42 | Operator, iteration and naming rules the text had left implicit | Integer `/` truncates toward zero and `%` takes the dividend's sign; `>>` is arithmetic on signed and logical on unsigned; unary `-` is an operator and `-MIN` an `overflow` check; `enum` members may carry explicit values, the unassigned ones counting on from the previous; `for v in s` binds a `let` copy and writes go through `s[i]`; a range with `b <= a` is empty; an unused binding or parameter is not an error; a bracket is a comptime argument list after a name resolved to a function or type and an index after a value, decided by the symbol table; a name before `.` resolves as a `use` qualifier, then a type, then a comptime type parameter or a comptime type value, then a value, and the builtin type names (`Vec`, `Mask`, `Atomic`, the primitives) are reserved; a newline is whitespace inside `(`, `[`, a literal's `{ }` and a type body's `{ }` only, never inside a block's; `defer` runs at the exit of its enclosing block — by `break`, `continue` or `ret` included — in reverse order, a loop body's once per iteration, and a trap or `os.exit` runs none; every returned value is bound or discarded with `_` (`let _ = f()`), so a call returning anything cannot stand as a statement; a local or parameter is declared once per function and shadows nothing — no earlier local, no module-scope name of its own module, no qualifier; a struct literal names every field exactly once, an array or `Vec` literal supplies exactly `N` elements, a `union` literal names one member; `%` is integer-only; `neper fmt` writes a payload-less `union enum` member as `.Name` wherever context types it | Each is a rule a generator needs on an ordinary line and a reader needs to check one — the sign of `%`, whether `v` aliases the element, whether `xs[i]` after a `const` named `xs` is an index — and each had either no statement or two. The C results for `/`, `%` and `>>` are what the hardware gives and what every reader expects; a copy in `for` keeps "what is on the page is what runs" (a hidden reference would make `v.x = 1.0` write the array); an unused binding as an error would reject `main`'s `args` in every example. The newline rule as first written made every statement in a block whitespace-separated, which no lexer could implement. (amended 2026-09-04: the rule as rewritten made every multi-line `type X = struct {` a syntax error, the spec's own declarations and both record examples included — a type body's brace is a third case beside a literal's and a block's. `defer`'s scope, the single-value discard, redeclaration, literal completeness and float `%` each had no statement; block-scoped `defer` is what "scope exit" already said and what `defer` inside a loop needs, an explicit `let _` keeps an ignored `err` on the page, no-shadowing keeps one name one meaning per function as §14 keeps it per module, a complete literal is the counterpart of no hidden memset, and `%` on floats is `fmod`, which nothing defined.) (amended 2026-09-04: the resolution order named three sets where §2 has four — a comptime type parameter or a comptime type value, whose protocol function is looked up at the instantiation (§9, D52), sits between a type and a value.) |
| D43 | Library surfaces fixed by the spec | `e.mem`: `error Exhausted`, `copy[T]` returning nothing, `eq[T]`, `cast[P]`, `bitcast[T]` (D49), `type Stats = struct { used: usize, capacity: usize }` with an allocation-free `stats(a: *const Arena) -> Stats` deriving both from `off` and `cap`, the `Arena` carrying no counters so that `alloc` stays a bump and a bounds compare, and the comptime intrinsics `size_of[T]()` and `align_of[T]()`, `alloc` aligned to `align_of[T]`; `e.str`: `type Builder`, `type Sink` (a `*void` context and a plain `fn(ctx: *void, bytes: []const u8) -> err`), `error NotOnTop`, `builder` (whose `cap` is an initial reservation, not a limit), `builder_to` (the same, carrying a flush sink: a push that would exhaust the arena drains through the sink and proceeds, so `mem.Exhausted` never leaves a push on a sink-backed builder), `done`, `concat`, `join`, `eq`, `error BadNumber` with the four parsers `parse_f32`, `parse_f64`, `parse_i64` and `parse_u64` that return it on a malformed or out-of-range input, and a push per integer type — `usize` and `isize` included — so an expansion contains no source-level conversion (the formatter's internal widening of narrow integers to the push width under `{x}`/`{b}` is not one), `{x}`/`{b}` printing a signed value's two's-complement bits at its width; `e.io`: `print(s: []const u8) -> err` and `printf[FMT]` — pushing into a sink-backed builder over a 4 KiB stack arena of its own, whose sink is `print`'s loop over `os.write`, so the flushing is the builder's and `printf` carries no retry — no error of its own; the formattable set is every type §9 rule 4 supplies a `format` for — the integers, the floats, `bool`, `str` and every other slice, `err`, pointers, arrays, `Vec`/`Mask`, and every `enum` and `union enum` whose own module declares none — plus any type whose module declares `fn <t>_format(v: T, b: *str.Builder) -> err` (§9), a verb on which expands to one call to that function; `e.atomic`: `type Ordering` and the intrinsics `init` (comptime-evaluable), `load`, `store`, `xchg`, `cas -> (bool, T)`, `add`, `sub`, `and`, `or`, `xor`, `min`, `max` (the last seven on integer `T` only), `fence`; `e.time`: the signature table of §16 and `error Invalid`; `e.math`: every function comptime-generic over the float type, `fma` an intrinsic; `e.gpu`: `len[T](b: Buf[T])` | The examples called a dozen functions the spec never declared, so their argument and return types could not be checked from the text, and `size_of` was used as a builtin that existed nowhere. Naming a size needs an intrinsic because nothing else in the language can compute layout; the narrow pushes leave no source-level conversion in a `printf` expansion — the formatter's internal widening of narrow integers to the push width is not one — so §6's list of four implicit operations stays true. (amended 2026-09-04: §7 and §13 still used `io.read` and `io.NotFound`, which the fixed `e.io` surface never had — the examples are over `e.os`; `e.atomic` was five calls by example with no `cas` result and no ordering type, and §10 named device operations "§8's" that §8 lacked; `push_usize`/`push_isize` were missing from a family that exists so no cast is needed; `str.Builder` was used as a type and never declared.) (amended 2026-09-04: "no widening remains in a `printf` expansion" contradicted §4's `{x}`/`{b}` rule, under which the formatter widens a narrow integer to `push_hex_u32`'s width internally; the claim is that no source-level conversion remains.) (amended 2026-09-04: `io.printf` was said to push into a 4 KiB stack builder with no arena, which the push family's `NotOnTop` contract cannot satisfy — every push is a claim on an arena top; it pushes into a builder over a 4 KiB stack arena of its own, carrying a sink whose `write` is `print`'s loop over `os.write`, so a push that would exhaust the arena drains the buffer through the sink and proceeds, a `str` argument longer than the whole buffer drains through the sink as it is pushed, and `printf` sends what `str.done` leaves through the sink once at the end — every verb still a push, no caller's arena involved, and no retry in `printf` itself.) (amended 2026-09-04: the fixed surfaces omitted `atomic.init` and `mem.bitcast`, both declared in §8.) (amended 2026-09-04: D52 made a user type formattable through its `format`, but `printf`'s flush-and-retry wrapped only `printf`'s own pushes, so a user `format` body's `try str.push` propagated `mem.Exhausted` out of `printf`; the flush moves into the builder as `str.builder_to`'s sink, `printf` becomes an ordinary sequence of pushes, and the formattable set gains every type with a `format`.) (amended 2026-09-04: three gaps in the fixed surfaces — `mem.stats`, which `docs/modules.md` lists in `e.mem` and §8 now declares; number parsing, which `e.cli`, `fmt.json` and `fmt.csv` all need and `examples/sample.e` already called, now `str.parse_*` over `str.BadNumber`; and a formattable set closed at six shapes while §9 rule 4 supplies a `format` for far more, now stated as rule 4's set plus the declared ones.) |
| D44 | Operator precedence | C's precedence and associativity with two changes: every bitwise operator (`&`, `^`, `\|`, and the shifts) binds tighter than every comparison, and comparisons do not chain; eleven levels, tightest first: postfix (`.`, `[]`, `[a..b]`, call, comptime bracket), prefix (`- ! ~ & *`), `* / % *%`, `+ - +% -%`, `<< >>`, `&`, `^`, `\|`, comparison (non-associative), `&&`, `\|\|`; assignment is a statement, not an expression; `try` prefixes one call; `neper fmt` neither adds nor removes parentheses | No table existed, so `a & b == c` had no parse and §3's "the other operand of a binary operator" named a tree that was never defined. C's order is what every reader and every emitter expects, and its one famous trap — comparison binding tighter than `&`, a historical accident — is the one thing worth fixing, as Go did; a non-chaining comparison turns `a < b < c`, which is never what a generator meant, into a compile error instead of a `bool` compared with a number. |
| D45 | GPU targets in a build | `--gpu spv,ptx\|none`, default `spv`; `--gpu none` is a host-only build and a kernel present under it is a compile error naming the kernel; a host build compiles every kernel-owning module — only its device-reachable functions and those of the modules they reach — once per listed GPU target into `<module>.<gpu-target>.em` and embeds those Code sections in the executable; `--target spv\|ptx` alone builds device modules for `neper dis` and no executable; the device half of a module includes only device-reachable functions (D24, D37), so `target.os` is `.None` there and host-only names, `use e.os` included, are simply absent | One binary embeds the GPU module (§10) but the only build option was a single `--target`, so nothing said how a host build produced or chose the `.spv.em`/`.ptx.em` it embedded, what `--target spv` meant on its own, which modules received device `.em` files, or how `use e.os` resolved for the device half of a kernel-owning module. `spv` by default is what every desktop GPU on the two M0 platforms speaks; `ptx` is opt-in because it needs a CUDA driver. Restricting device compilation to the device-reachable set is what D24 already does, and it is what makes a host-only import invisible on the device without a second module system. |
| D46 | `.nepersym` | The compiler emits its line and symbol tables as a non-loaded section `.nepersym` in every object and executable from M0, read by the runtime for the trap backtrace on every platform regardless of linker | §11 promises a symbolised backtrace in every build mode under either linker, and the standard formats cannot deliver that on Windows until the M4 PDB writer exists — nor should the runtime carry a DWARF or PDB reader. One compact section, written from data the compiler already holds and found through the executable's own section table, gives the backtrace one source everywhere. It is distinct from the standard-format debug information external tools read (D9) and from the neper-format locals/types side table that is the M4 optimisation. |
| D47 | Module graph | `use` cycles are forbidden: the module graph is a DAG, and a cycle — direct or through any number of modules — is a compile error naming every module in it (§2, §12, §15) | Interfaces are built from the interfaces of the modules a file uses (§15) and `Deps` edges follow `use` (§12); a cycle has no first interface to build and no finite recompilation set, and a language with one file per module and no forward declarations gains nothing from allowing one. Naming the whole cycle is what makes the error actionable in generated code. |
| D48 | Type aliases | `type X = T` over anything but a `struct`, `union`, `enum` or `union enum` body is an alias — the same type, interchangeable, no conversion in either direction; a distinct type is a single-field struct, which is what `e.time` and `e.os` do; `str` is exactly such an alias of `[]const u8` (§4) | The form existed with no rule for whether `X` and `T` were one type or two. An alias is the cheap reading: it costs no cast and no rule, and the distinct-type need is already served by the one-field struct, which every library type in this document uses — a second distinct-type mechanism would be the redundancy a small language cannot afford. |
| D49 | Bare `union` | Kept as the C-layout escape hatch: it exists for C ABI compatibility across `extern` (`INPUT`, `VkClearValue`, `sockaddr`) and deliberate punning, and `union enum` is the default for a variant type; `mem.bitcast[T](x)` reinterprets a value as a `T` of the same size, checked at compile time, legal on CPU and device, so a pun never needs a `union`; bare `union` is banned in device code; a `union enum` in device code has non-overlapping payloads; neither `union` form is a `Buf[T]` element type (§4, §8, §10) | The earlier rationale — punning, and not hiding a cost — was wrong on both counts: a compiler-placed tag has the identical layout, and punning is a bitcast, not a type. What only a bare `union` can do is match a C `union`'s layout at an `extern` boundary, which the Win32, Vulkan and socket APIs all require. SPIR-V's logical addressing cannot reinterpret a local, so the device gets the bitcast and not the `union`, and non-overlapping payloads are legal there because the program cannot see the layout — which is also why neither form may be a `Buf[T]` element, where the layout crosses the boundary as a memcpy. |
| D50 | Implementation constants | (1) root arena 64 MiB by default, `--arena SIZE` raises or lowers it (§8, §13); (2) no default parameters exist, so `thread.spawn[Ctx](f, ctx, stack: usize)` takes the stack size explicitly, `const thread.DEFAULT_STACK: usize = 1 MiB` is provided, and `os.thread_create` takes the same `stack` (§5, §8); (3) xxHash64 for signature hashes, body hashes and content-hash folding (§12, §13), FNV-1a 32-bit for error values alone (§7); (4) ULP bounds — the Vulkan specification's precision table on the device, every `e.math` transcendental within 2 ULP on the CPU, `math.rsqrt` within 2 ULP on both, per-function bounds recorded in `lib/e/math.e` when implemented (§11); (5) PTX levels `--cpu sm_50 \| sm_70 \| sm_80 \| sm_90`, default `sm_50`, as rows of the §13 table beside x64 and aarch64, `--cpu` given at most once per target family so a host build with `--gpu ptx` names both its host level and its `sm_*` level, a level whose family the build does not target being an error (§10, §13); (6) diagnostic codes numbered by spec section, `E<SS><NN>`, `E0403` being §4's third; the catalogue is written with the checker (§13); (7) `neper fmt`: four-space indentation, 100-column lines, a breaking bracketed list one element per line, comments never column-aligned, frozen at 1.0 (§3, §14); (8) `e.test` ships `assert(cond, msg)`, `eq[T](a, b, msg)` — `T` a type with an `eq` (§9), which includes every type `==` takes — `near(a, b, abs, rel, msg)` and `fail(msg)`, each `-> err`; golden-file comparison deferred (§13, §17); (9) `neper test` builds debug by default and accepts `--release`, running the same tests against release semantics (§13); (10) per-test arena 16 MiB by default, `--test-arena SIZE` with `--arena`'s `SIZE` syntax (§13); (11) `.em` files are written to `.neper/<mode>/<module>.<target>.em` under the project root, debug and release coexisting by directory (§12); (12) `e.data.sort`, `e.data.map` and the rest of `e.thread` — beyond `spawn`, `join`, `detach` and `DEFAULT_STACK` (§8) — are specified by their `lib/e` source and indexed by `neper index`, the spec authoritative only where it writes a signature; `e.math` arities `atan2(y, x)`, `pow(x, y)`, `fma(a, b, c)`, `min(a, b)`, `max(a, b)`, `copysign(x, y)`; `round` is ties-to-even — `RoundEven` on SPIR-V, the round-to-even instruction on CPUs — so device and host agree (§11, §13) | These were §17's twelve open items: each a number, a catalogue or a surface with no goal to decide it, listed so that an implementer knew it was choosing rather than reading. Each is now fixed by the smallest defensible value — the Windows default for a stack, a small arena a program raises, one 64-bit non-cryptographic hash for everything that is not an error value, published precision tables rather than measured ones, the standard PTX levels verbatim as the x64 levels are, section-numbered diagnostics so a code says where its rule lives — so that two implementations, and the bootstrap and the self-hosted compiler, agree without a second document. `round`'s tie rule is recorded because it is the one exact `e.math` function whose device and host instructions could otherwise silently disagree. (amended 2026-09-04: a single `--cpu` could not name both a host level and an embedded `ptx` module's `sm_*` level; one option per target family needs no second option, since every level names its family. Item 12 also omitted `thread.detach`, whose signature §8 fixes.) (amended 2026-09-04: item 8 fixed `test.eq`'s `T` as a type `==` takes while D52 lists `e.test` as a consumer of the `eq` protocol; `T` is a type with an `eq`, which is the wider set.) |
| D51 | Standard-library namespaces | `e.*` is the language-owned standard library (replacing `core.*`), `algo.*` is pure computation, `text.*` is Unicode/text processing, `crypto.*` is pure cryptography with caller-supplied entropy, `fmt.*` is interchange formats, `gfx.*` is graphics/rendering and `ui.*` is the declarative application framework; `x.<owner>.<package>.*` is separately versioned source; `lib/e/mem.e` is `e.mem`. D66 supersedes the former ecosystem-wide final-segment reservation; D79 adds `gfx.*` and `ui.*`. | Domain prefixes make ownership and purity visible without placing unrelated text and security surfaces into algorithm grab bags. Owner-qualified optional names avoid provenance collisions, while explicit import aliases handle local final-segment collisions. |
| D52 | Protocols | `T.f(...)` on a comptime type parameter or a comptime type value resolves, at instantiation, to `fn <t>_f` in the module declaring `T` — `Sensor.hash` is `fn sensor_hash`; conventional `hash`, `eq`, `cmp`, `format`, `next`; `for v in it` uses `next` | A generic container needs an operation on its element type, and neper has no interfaces, traits or closures by design. Name lookup at compile time gives it with no vtable, no tag and no dispatch — a direct monomorphised call — and `grep "^fn sensor_hash"` still finds the one that runs. Legal only where the module is genuinely unknowable, so §14 invariant 4 survives. The type's name is in the function's name because invariant 1 admits no overloading: a module declaring two types would otherwise need two `fn hash` lines. (amended 2026-09-04: the row admitted only a comptime type parameter as the receiver, where §9 rule 1, §2's resolution order, §14 invariant 4 and `docs/modules.md` all admit a comptime type value — `f.ty.format(x, b)`, which §9's own worked example relies on.) |
| D53 | Compile-time introspection | `e.meta`: `fields`, `members` and `type_name` are comptime-only, returning comptime values and callable only in a comptime context (D5); `get` and `set` are comptime-**parameterised**, only their `FIELD` argument comptime, each compiling to an ordinary field load or store and legal in any body; `Field` and `Member` are comptime-only types, never storage; a `for` over a comptime slice is unrolled | Every `fmt.*` module, `e.cli`, `e.log`, `e.bytes` and owner-qualified `x.<owner>.db.*` driver otherwise needs hand-written marshalling per type — the boilerplate generated code gets wrong most often. Compile-time only keeps runtime reflection a non-goal (§1): no type table in the binary, dead-code elimination intact, and the unrolled loop is gone by codegen. `fields` on a bare `union` is an error, since nothing says which member is live. (amended 2026-09-04: "all comptime-only" made §9's own `format_struct` illegal, because `meta.get` reads a field of a runtime `*const T` and the read has to happen at runtime; only `FIELD` is comptime there, and `Field`/`Member` are declared comptime-only types instead, since a `type`-valued field has no layout, no zero value and no place in a struct, a buffer or `extern`.) |
| D54 | Continuation barrier | An unclosed `(`, `[` or literal/type-body `{` may not cross a column-0 declaration keyword or attribute line; the error is reported at the opening bracket | Implicit continuation's standard failure is a dropped bracket swallowing the rest of the file and erroring far from the cause — exactly what generated code produces. §14 invariant 2 already guarantees nothing else starts at column 0, so the parser gets a barrier for free: one dropped bracket, one precise diagnostic. The property that makes `^fn` greps exact is what bounds the cascade. |
| D55 | `try` positions | Statement-level only: a whole statement, the entire initialiser of a `let`/`var`, or the entire right-hand side of an assignment. Not nested in an argument list, an operand, a literal, an index, a condition or after `ret`; not inside `defer`; not lexically in a comptime root expression. A helper dynamically executed by the interpreter may use `try`; an escaping error fails the root. | `try` is control flow, and neper keeps control flow at statement level. The lexical/dynamic distinction permits ordinary fallible helpers during evaluation without inventing a return target for a `const`. A deferred fallible call is `defer let _ = f()`. |
| D56 | Evaluation and type completeness | Subexpressions evaluate left to right; conditions are `bool`; non-void paths return; operator operand/result types, switch duplicates and break targets are fixed by spec §6; sized/runtime-storable types, recursive-type rejection, empty aggregates and exact layout are fixed by §4. | Two conforming implementations must not differ in side effects, accepted operands or layout. These rules close what the earlier operator and ABI decisions left implicit. |
| D57 | Representations and arena/resource state | `bitcast` cannot contain pointers or strip provenance; invalid representations are a debug `invalid` trap and release undefined behavior; an integer-to-enum cast naming no member traps in every mode, superseding D7's unchecked-enum clause; `mem.eq` is field/element value equality; arenas, builders and OS/GPU handles have the single-live-copy and consumption contracts in §§5, 8 and 10. | Raw byte equality reads padding, unrestricted bitcasts defeat `const`, and freely copied cursors/handles create overlapping allocation or double release. An invalid enum would invalidate exhaustive control flow, so it has no useful unchecked result. |
| D58 | Generic, protocol and reflection completion | Generic inference is structural and checking dependent on a comptime parameter occurs at instantiation; aliases preserve the canonical nominal declaration; protocol snake-case, wrong-signature errors, fallbacks and lookup edges are normative; `e.meta` includes type-kind, element, length and backing-type queries. | These rules make protocol lookup deterministic and support structural encoding/decoding without claiming tagged unions and opaque resources are generically decodable. |
| D59 | GPU host semantics | Driver launches are asynchronous and `.Cpu` launch is synchronous; device storage/execution/argument types are separate sets; host handles carry owner/generation validation with `WrongDevice`/`InvalidHandle`; buffer release and device close are fallible; workgroup/grid bounds, barriers, subgroup lanes and capability inference follow §10. | The previous single “device type” and unconditional asynchronous statement contradicted legal locals and the CPU backend, while copyable opaque handles needed an enforceable lifecycle. |
| D60 | Floating determinism | Narrow floats use widen-to-f32, operate, narrow semantics; arithmetic NaNs canonicalize; special values, FTZ widths and approximate-function domains are fixed by §§4 and 11. | Direct narrow rounding and f32 double rounding can differ, and NaN payload choices made the earlier bit-identical promise untestable. |
| D61 | Incremental and artifact integrity | Foreign const reads take value/body-hash edges; comptime cache keys include expression, arguments, target and semantic versions; xxHash64 is a candidate index followed by full identity comparison; `.em` and `.nepersym` have versioned bounded formats. | Hash collisions must affect performance only, and target- or value-dependent compiled constants must never survive stale incremental builds. |
| D62 | Toolchain and test isolation | Host targets are architecture-OS triples; `run` is host-only; under `--gpu none` only kernels in the reachable module graph are errors; linker inputs, index schema, diagnostic/exit ordering and startup failure are fixed by §13. Each test runs in its own child process with fresh globals, dedicated output pipes and nonce-authenticated framed control records. This supersedes D15's process-per-module execution details and narrows D45's “kernel present” wording. | Process-per-test removes post-crash global ambiguity and cross-pipe attribution races. Authenticated control records prevent user stderr or a guessed inherited handle from spoofing a trap. |
| D63 | Module and platform boundaries | `e.os` is the sole ordinary host-platform binding surface, with GPU-driver and owner-qualified `x.*` exceptions; standard modules needing new OS primitives remain blocked until those primitives are added. `x.*` is vendored source in v1; pure `algo.*` and `crypto.*` receive entropy explicitly; fallible iterators are explicit rather than language `for`; WebSocket and format transports are separate modules. D78 supersedes the former provisional `x.neper.*` package placement. | The catalogue previously scheduled modules that its own extern rule made impossible, classified externally backed security and OS-seeded randomness under the wrong namespaces, grouped unrelated security concerns, and used external package names with no owner provenance. |
| D64 | Debug type and symbol completeness | The fixed DWARF/CodeView subset includes const-qualified pointees and subroutine types for function pointers; Mach-O symbol tables are explicit; retained `.nepersym` contributions are merged, relocated and indexed rather than carried as independent opaque sections. This supersedes D9's “twelve-tag” count while preserving its intentionally small subset. | A pointer tag alone cannot describe a callback signature, and system linkers do not preserve or combine custom sections portably without retention and merge rules. |
| D65 | Public tooling protocol | `docs/tooling.md` version 1 fixes a JSONL envelope and discriminated records, original-byte and Unicode/UTF-16 spans, structured fixes, lossless `tokens`/`parse`, complete definition/reference `index`, deterministic test records, reproducible build manifests, `info` capability discovery, stdin operation and generated-source maps; `docs/schemas/neper-v1.schema.json` is its machine schema. Diagnostic codes come from `docs/diagnostics.md` as stable semantic `E-<CATEGORY>-<NNNN>` values. This supersedes D50 item 6 and D62's narrower index/diagnostic clauses. | A harness must never scrape human text, infer compiler capabilities, duplicate parsing or name resolution, depend on checkout paths, or guess how to apply a fix. Section-numbered codes and point-only locations were documentation conveniences rather than stable APIs. |
| D66 | Composable names and imports | `use path` binds the last segment by default and `use path as qualifier` supplies a module-local explicit alias; wildcard imports remain forbidden and every cross-module source reference remains qualified. A local cannot shadow an active outer, module, qualifier or builtin name, but a name may be reused in disjoint sibling scopes. This supersedes D15/D41's “no-alias” wording, D42's once-per-function rule and D51's ecosystem-wide reservation. | Last-segment uniqueness made unrelated packages coordinate globally, while function-wide uniqueness made independently generated blocks coordinate outside their lexical interface. Local aliases and lexical non-shadowing preserve one meaning at every source position without either global burden. |
| D67 | Formal syntax and bounded recovery | `docs/grammar.ebnf` revision 1 is the normative concrete grammar. The lexer always emits `NEWLINE`; the parser alone classifies it as soft in delimiter contexts. UTF-8, BOM, line-ending normalization, controls, tabs, longest match, literal lexing, raw strings and closed token/node registries are fixed. A continuation cannot cross a declaration, containing-block, `case`, `default` or EOF barrier. This extends D54. | Standalone tokenizers, syntax highlighters and lossless editors need parser-independent tokens, and a dropped delimiter inside one large function must not consume the rest of that function. Raw strings reduce generated embedded-data escaping without adding interpolation or hidden work. |
| D68 | Error-propagation spelling | The propagation form remains `try call()`, not `?call()`, under D55's three positions. | Both spellings are one lexical token and model-token cost is tokenizer-specific. The word is greppable, states control flow, and avoids spending punctuation on an unmeasured character-count optimization. |
| D69 | Machine-readable module plan | `docs/modules.json` version 1 is authoritative for module names, normalized surface/schedule status, milestones, layers and blockers; `docs/modules.md` carries rationale. Vendored packages carry the reproducibility-only `neper-package.json` manifest described there. | A prose table and ASCII layering diagram cannot be checked reliably, and “Spec, M1, Later” mixed independent dimensions. Structured plan data lets CI and generation harnesses reason about availability without making it a compiler package resolver. |
| D70 | Pre-implementation conformance and LLM measurement | Before compiler implementation, the specification ships the `tests/conformance/` corpus defined by tooling protocol §9 and an initial multi-tokenizer generated-code report. Grammar examples, primary diagnostics, formatting, token trees and tool records are byte-exact fixtures. | “LLM optimal” is not a property that character count can establish: tokenizers and repair behavior differ. A versioned corpus prevents two implementations from making different recovery or formatting choices, while the report makes syntax tradeoffs measurable. |
| D71 | Module decomposition and API ownership | `docs/modules.md`, `docs/module-apis.md` and `docs/modules.json` jointly define the toolchain library plan: the prose fixes namespace and dependency policy, the API catalogue enumerates the exact proposed declarations, and the JSON manifest is authoritative for names, layers, delivery state, direct edges and blockers. Broad historical buckets such as `e.data`, `algo.text`, `algo.crypt`, `e.http`, `e.ws` and `x.sec` are superseded by the decomposed owner-qualified names in that plan. | One concern per module improves retrieval, generation context and dependency auditing. Separating Unicode, cryptography, linear algebra, network protocols and optional vendor packages prevents unrelated APIs from sharing a qualifier, while an exact catalogue prevents implementation-time API invention. |
| D72 | Canonical implicit-operation count | Spec §6's table is the only authoritative list and contains five operations. This supersedes the historical counts embedded in D18 and D43 without changing either decision's substantive rule. | A generated checker needs one enumerable source of truth. Repeating a count across historical rationale created a contradiction when the compiler-generated iterator-place operation was added. |
| D73 | Compact lossless syntax interface | Tooling protocol v1 exposes 94 explicitly named token kinds and 54 explicitly named structural syntax-node kinds. Grammar helper productions are inlined rather than serialized. Original newline spellings, a leading BOM, trivia and invalid bytes remain reconstructible, while `info.language_profiles` relates language, grammar and stream versions in records rather than parallel arrays. | A grammar-shaped tree is correct but unnecessarily deep and expensive for model context; an AST without tokens is cheap but unsafe for source edits. A compact lossless tree gives harnesses stable structure and exact edit provenance without leaking parser implementation details or making them guess version relationships. |
| D74 | General-purpose RTL completion proposal | The module plan adds `algo.bitset`, `algo.complex`, `text.encoding`, `text.io`, `e.task`, `e.time.calendar` and toolchain-owned `e.tz`; expands `e.str`, `e.io`, `e.fs` and `e.sync`; replaces raw `os.last_error` with explicit `os.ErrorDetail`; and gives locale, URI and MIME exact initial toolchain-module surfaces. `e.tz` pins its built-in IANA data to the toolchain version while accepting explicit compatible data. These additions preserve caller-owned memory, bounded I/O, explicit locale/zone data, cooperative cancellation and portable `err` propagation. Runtime variants, exceptions, object/component streaming, COM and dynamic invocation remain outside the language-owned runtime. | Comparison with Delphi's RTL exposed missing everyday substrate rather than missing advanced algorithms: substring manipulation, encoding-aware line I/O, civil calendars and zones, secure temporary files, rich metadata, task pools, timed synchronization, locale formatting and URI/MIME processing. Making state and data versions explicit gains the useful coverage without importing Delphi's global locale, managed-object or exception model. |
| D75 | HTML is a format module | `fmt.html` parses UTF-8 slices or readers into a bounded, arena-owned, index-linked, read-only tree and serializes it. Its tokenizer and tree builder follow the WHATWG algorithm frozen by the toolchain release, including recovery, implied elements and HTML/SVG/MathML transitions. It does not reuse `fmt.xml`, open files, fetch resources, execute scripts, apply CSS or provide a mutable browser DOM. | Real HTML is not well-formed XML, and useful parsing requires deterministic recovery and tree construction. Owning it as `fmt.html` matches the existing format namespace without creating a pseudo-external `x.neper.*` standard library. Node indices keep relationships stable under arena allocation and explicit limits preserve the library's bounded-input rule. |
| D76 | Complete regular collection families | The plan adds semantic `e.data.stack` and `e.data.queue` facades, stable non-reusing node identifiers in `e.data.linked`, caller-storage `e.data.disjoint_set`, immutable CSR `e.data.graph`, and pure `algo.graph` traversal/component/shortest-path algorithms. Every existing collection exposes deterministic non-mutating iteration, ordered trees add upper-bound/range iteration, and heaps add comparator contexts and linear-time bulk construction. | Lists, hash/ordered maps and sets, deques, rings and heaps supplied the storage foundation but left ordinary names, traversal and graphs to every application. Thin stack/queue facades improve discovery; stable indices avoid pointer invalidation under arena growth; separating graph storage from algorithms keeps representation reusable and dependency direction acyclic. |
| D77 | Ordered delivery tiers | Every toolchain module appears exactly once in `modules.json`'s ordered `core`, `extended` or `experimental` tier. Core gates the first stable CPU release; extended modules become stable when independently delivered but do not gate it; experimental APIs have no compatibility promise. Dependency layers remain separate from delivery tiers. The lean core excludes ordered trees, application frameworks, advanced formats, specialized numerical/text/crypto domains and thin collection facades; `algo.bitset` moves into M2 core while `e.data.tree`, `e.debug`, `e.metrics`, `e.log` and `e.cli` cease to gate M2. | A large proposal catalogue is useful, but presenting all modules as one product commitment makes the language appear bloated and lets unrelated breadth delay stability. An explicit exhaustive order preserves future designs while making release scope and compatibility honest and mechanically checkable. |
| D78 | Priority RTL expansion and namespace ownership | The extended tier adds `e.data.slot_map`, fuller `e.data.iter`, `algo.decimal`, `algo.deflate`, `text.locale`, memory mapping and file watching, concurrent queue/map, typed asynchronous I/O, TLS, URI/MIME, gzip/zstd and zip/tar. Neper-owned APIs live under the toolchain domain namespaces; `x.neper.*` is forbidden and all such reservations are removed. `x.*` is reserved for optional packages named after their actual external owner. This supersedes D63's provisional `x.neper.*` placement and D74's package wording; D79 subsequently adds the `gfx.*` and `ui.*` domains. | The priority set closes major everyday gaps against .NET/Delphi without enlarging the first-stable core. A project cannot meaningfully be an external vendor to itself; ownership namespaces make discovery, support and reproducibility boundaries honest. |
| D79 | Declarative GPU UI proposal | Reserve toolchain-owned `gfx.*` and `ui.*` namespaces and add fifteen experimental modules for pure geometry/paint/images, shaping/layout, display lists, windows/input, immutable widgets, explicit state reconciliation, animation, accessibility, testing and application scheduling. Widgets are frame-arena values; persistent elements/state and GPU resources use bounded generation-checked stores. No new syntax, objects, closures, GC, reflection or hidden allocation is introduced. Delivery is blocked on reviewed `e.os` native-window/accessibility and `e.gpu` presentation designs and must pass GP-15 before promotion. | A Flutter-like value tree and GPU renderer fit Neper's explicit memory model better than a Swing-style object hierarchy. Experimental status permits workload-led API correction without expanding the first-stable commitment, while explicit blockers preserve the sole-platform-boundary rule. |
| D80 | Embedded application assets | Add experimental `e.asset` and `ui.asset`. Root `project.yaml` declarations become a sorted linker-generated immutable registry; logical name, source, media type, attributes, size and SHA-256 enter build identity and the canonical build manifest. `e.asset` performs allocation-free zero-copy lookup. `ui.asset` deterministically selects locale/theme/scale variants, exposes fonts without copying and owns a caller-bounded GPU texture cache driven by a caller-supplied decoder. Raw bytes are embedded unchanged; package-provided, compressed and external runtime assets are deferred. | Flutter-style applications need reproducible fonts, images and other resources without runtime path assumptions. Keeping codecs injectable avoids a hidden format dependency, immutable executable slices fit the existing data model, and explicit bounded caches preserve Neper's allocation and ownership rules. |
| D81 | Interoperability and verification expansion | Add extended `crypto.x509`, ASN.1/PEM, multipart/mail, quoted-printable, PNG/JPEG/WebP, bzip2/LZW/zlib, deterministic text and context-safe HTML templates, compiler-backed coverage/fuzzing, and generic `e.db` SQL contracts. Extend `e.bytes` with Base32 and Base85. Encodings/codecs remain bounded and streaming; image pixels are caller-owned; certificate roots and time are explicit. Concrete drivers are the owner-qualified packages `x.sqlite.sqlite`, `x.oracle.mysql` and `x.postgresql.libpq`. | Comparison with Go's standard library exposed operational gaps in TLS identity, common Internet messages, image interchange, SQL portability and verification tooling. Toolchain-owned protocol contracts improve interoperability without importing hidden allocation, ambient trust stores, driver registries or database implementations into the stable core. |
| D82 | Post-M2 LLM hardening gate | Complete M2 against its existing contract, then execute M2.5 before any M3 implementation. `post-m2-llm-hardening.md` owns H01–H29 evaluation, required outcomes, migration and evidence; `llm-hardening-recommendations.md` distils that review into the prioritized R01–R11 set and registers R08–R11 as H26–H29. All items start scheduled/unresolved; adopted language/API/protocol changes require versioned normative amendments and implemented verification. CPU/tooling obligations close in M2.5; explicitly future GPU runtime evidence remains pending against frozen contracts. | The hidden-semantic-context concern raised by Jose Crespo's 2026-08-22 article motivates checked ownership/lifetimes, explicit unsafe and concurrency contracts, value/alias and error-state review, compiler-derived context and real LLM evaluation. The follow-up review adds incremental queries, snapshots, bounded semantic editing/transport, artifact hardening and measured CPU/GPU performance contracts. This decision fixes sequencing and the mandatory gate; it does not yet supersede D3/D14 or adopt proposed keywords. Documentation alone cannot close implemented-delivery obligations. |

| D83 | Explicit multi-GPU discovery and selection | Extend planned `e.gpu` with bounded caller-owned `devices`, `DeviceInfo`/`DeviceKind`/`DeviceKey`, exact `open_id` and opening-time `info`. Backend-scoped UUIDs are revalidated selectors, not immutable serial numbers; missing/duplicate keys fail without substitution. Indices are temporary; memory reports capacity, not availability; every queue/buffer belongs to one logical open device. | Applications and harnesses must be able to choose among multiple GPUs without assuming ordinal stability, unique names or Vulkan/CUDA identity equivalence. Freeze contracts and versioned tooling under M2.5 H18/H21/H22; implement CPU/Vulkan in M3 and CUDA in M4. No implicit offload, automatic fallback, peer sharing, device migration or optimized CPU kernel backend is adopted. |

## D84 — standard-library composition and stable dependency closure

Adopt `stdlib-hardening.md` SL01–SL11 and the synchronized next-contract catalogue.
Keep ordinary parameters and the current shadowing rule; fix signature/import
collisions and validate declarations with the real resolver during M2.5. Add core
`e.cancel` and promote basic `text.utf8` to core through that cross-cutting gate.
Add extended `crypto.mac`, `crypto.kdf` and `e.test.support`; extend existing modules
for composable buffering, lossless JSON/Pointer/Patch, bounded globbing, fallible
iteration, safe directory-relative operations, supervised processes and HTTP/SSE
streaming. Installed capabilities remain separate from design metadata.

Promote the pure `gfx.geometry`/`gfx.paint`/`gfx.image` dependency closure to extended
and stabilize it with the already-extended PNG/JPEG/WebP codecs. GPU rendering and
UI remain experimental; stable public types cannot depend on experimental types.
This amends D77/D79's planned tiers, not implementation status. Version/migrate
delivered CPU contracts in M2.5 without moving M2's preserved baseline. Future
libraries retain their own implementation gates and independent runtime evidence.

## D85 — `e.data.sort` becomes `algo.sort`

Move the module from `e.data.sort` to `algo.sort`, in `modules.json`, `modules.md`,
`module-apis.md` and `lib/`. The seven declarations and their order are unchanged and
stay frozen; `layer`, `surface`, `milestone`, `schedule` and `direct_dependencies` are
unchanged. This is a namespace correction, not an API or delivery change.

`modules.md` defines `algo.*` as "pure algorithms over caller-owned data", which
describes the module exactly: all seven functions take a caller-owned slice and sort
or inspect it in place. `e.data.*` is one module per data structure, and this module
declares none — across all fourteen `e.data.*` and twelve `algo.*` catalogue entries
it is the only one declaring zero types, while sitting under a heading that reads
"Containers are one module per data structure". The catalogue already splits a domain
this way: `e.data.graph` owns `NodeId`, `Edge`, `Builder`, `Graph`, `Neighbors` and
`Nodes`, and `algo.graph` owns `bfs`, `dfs` and `topological` over a caller-owned
`graph.Graph`. Sort is structurally the second of those, with no container to pair it
with.

This supersedes D50 item 12's naming of `e.data.sort`, whose substance — that the
module is specified by its library source and indexed by `neper index`, the spec
authoritative only where it writes a signature — is unchanged and now reads
`algo.sort`.

## D86 — the `e.data.*` / `algo.*` boundary is genericity

Record the rule the catalogue already follows, in `modules.md` §1: `e.data.*` is
generic containers parameterised by their element type; `algo.*` is concrete domain
types and pure computation over caller-owned data. Where an `algo.*` type is generic
it is over a numeric parameter — `Complex[F]`, `Matrix[F]`, `Tensor[F]` — never over an
arbitrary `T`. Move `e.data.disjoint_set` to `algo.disjoint_set` under that rule; its
declarations, `layer`, `surface`, `milestone`, `schedule` and dependencies are
unchanged, and no `lib/` source exists. Keep `algo.bitset` where it is.

Storage ownership was the obvious candidate rule and is wrong: `e.data.ring` takes
`init(storage: []T)` and `disjoint_set` takes `init(parent: []u32, rank: []u8, ...)`,
so both borrow caller storage while only one is a container. Genericity separates them
and already held for 21 of the 26 catalogue entries — 12 of 14 `e.data.*` modules are
generic over an arbitrary element type, while 9 of 12 `algo.*` modules are concrete.
`disjoint_set` was the one genuine outlier: non-generic, concrete, a state array plus
union-find, which is textbook kin to `algo.bitset` rather than to `List[T]`.

`algo.bitset` stays because the rule puts it there, and the reason is recorded rather
than left silent because general convention shelves bitsets with containers
(`std::bitset`, `java.util.BitSet`) and the question will recur. A `BitSet` is a bit
vector over `[]u64` words holding bit indices; it can never hold an arbitrary `T`,
which makes it kin to `Uuid` and `Decimal`. The generic `Set` in `e.data.map` is the
contrast — a container over whatever key type the caller names. It is also already
`surface:"source"` at M2, so it is the expensive one to move and the one where being
wrong would cost most.

This supersedes D76's placement of caller-storage `disjoint_set` in `e.data`, and
sharpens D51's namespace definitions and D78's namespace-ownership clause without
changing what either assigns; D85 moved `sort` on the same rule, before the rule was
written down.

## D87 — every toolchain namespace consolidates under `e.*`

Move `algo.*`, `text.*`, `crypto.*`, `fmt.*`, `gfx.*` and `ui.*` to `e.algo.*`,
`e.text.*`, `e.crypto.*`, `e.fmt.*`, `e.gfx.*` and `e.ui.*`. `e.*` and
`x.<owner>.<package>.*` are unchanged, and all 128 catalogued modules are now `e.*`.
The rule becomes: `e.` is the standard library, `x.` is an external package, anything
else is the project's own. On disk `lib/algo/` becomes `lib/e/algo/`; no other module
has source yet.

It closes a silent shadowing hole, which is a demonstrated defect rather than a
tidiness argument. `graph.resolve_source` searches a project's `lib/` and `src/`
before the toolchain, and its `DuplicateModule` check only fires when a project holds
a module in both of its own directories -- never project against toolchain. A project
directory named `algo/` therefore overrode `algo.hash` with no diagnostic: a stub
`fn fnv1a64` returning `12345u64` compiled clean and ran instead of the library's.
The toolchain claimed six bare top-level names, and `algo`, `text`, `crypto`, `fmt`,
`gfx` and `ui` are among the most natural directory names a project invents. Only
`e/` and `x/` are hazardous now, and both read as reserved. The resolver is unchanged;
the fix is that the toolchain no longer claims names a project will reach for.

It also serves the language's purpose. A model writing neper had to have memorised six
arbitrary roots, and one that half-learned them invents a seventh -- `use net.http`
reads exactly as legitimate as `use fmt.json` did. A single generative rule
generalises where a memorised list gets extrapolated wrong, makes a hallucinated
import visible from the line alone rather than only against the catalogue, and matches
the single-root prior of `std::`, `java.*` and `System.*`.

The cost, stated rather than waved away: every `use` line for those six domains grows
by one path segment. It is bounded to import blocks -- the qualifier is the final
segment either way, so `hash.fnv1a64`, `paint.fill` and `tensor.matmul` are untouched.
R03 and R08 of `llm-hardening-recommendations.md` hold that token cost steers syntax
and that character count is not token count, so the delta is for `benchmarks/llm_edit/`
to measure rather than for this row to assert.

This supersedes D51's namespace list, which named `algo.*`, `text.*`, `crypto.*`,
`fmt.*`, `gfx.*` and `ui.*` as roots; their meanings are unchanged and now hang off
`e.`. D78's namespace-ownership rule is untouched: neper-owned APIs still live under
toolchain domain namespaces, `x.neper.*` is still forbidden, and `x.*` still requires a
real external owner. `modules.md` §1 additionally records that ownership is the root
while stability is the tier -- `e.` says the toolchain owns a module, not that it is
stable, since `e.*` now spans 33 core, 77 extended and 18 experimental modules.

Rows above this one name modules under the pre-consolidation roots and are left as
written, as D71's superseded `algo.text` and `algo.crypt` buckets show why: those names
never existed under an `e.` root, and rewriting them would falsify the record.

## D88 — the supplied `hash` folds components where bytes are not contiguous

Spec section 9 rule 4 says arrays, slices, vectors and tagged unions "recurse in
index or declaration order" for `hash`, without saying what recursing produces. Fix
it as two cases. Where a value is already one contiguous run of its canonical
little-endian bytes -- a scalar, an enum, an array of those, a slice or `str` over
those -- it is hashed in a single xxHash64 pass over that run, which is what the
implementation already did. Where it is not -- a nested slice, whose bytes are a
pointer rather than its contents, or a tagged union, whose payload is padded -- one
hash per component is folded in order, `acc = H(acc || h)` over the two as
little-endian words starting from zero, where `H` is the same one-shot pass.

The alternative reading, concatenating the components' bytes into one pass, needs a
buffer whose size is not known until the value is walked, so it needs allocation the
protocol has no arena for. The fold needs sixteen bytes of stack per level and no
second hash construction, so `neper_hash_bytes` remains the only hash symbol any
runtime provides.

Folding one hash per component rather than flattening bytes also separates values
that a flattening would collide. `[[1], [2, 3]]` and `[[1, 2], [3]]` are the same
flat bytes and hash differently, because each element is hashed as a unit before it
is folded. Nothing requires a nested shape's hash to relate to the flat shape's, and
the two are different types.

What this does not change: the contiguous case is byte-identical to before, so no
already-computed hash moves; `eq` and `hash` still agree, because both recurse over
the same components in the same order; and rule 4's leaf requirement, canonical
little-endian bytes under xxHash64 seed 0, is untouched.

D87's consolidation is unrelated except that the library this must agree with is now
`e.algo.hash`. This adds to rule 4's implementation rather than superseding a row.

## D89 — `e.mem` gains `view`, the one arena operation source cannot express

Add `fn view(a: *const Arena, start: usize, len: usize) -> []u8` to `e.mem`'s frozen
surface. It exposes arena storage the caller already owns as a slice; `start` and
`len` follow the ordinary bounds-trap rule rather than returning an error, matching
how the language treats slice bounds everywhere else.

It exists because `e.str`'s frozen `Builder` cannot be implemented without it.
`Builder` records `arena`, `start`, `len` and `reserved` -- an offset, not a slice --
so reaching its own bytes means turning `arena.base + start` into a writable `[]u8`.
The language offers no way: indexing a `*u8`, slicing a `*u8` and pointer arithmetic
all fail to type-check, and `e.mem` had no view. That blocked `Builder`, `builder`,
`builder_to`, `done` and all nineteen `push_*` functions, which is the half of
`e.str` that spec section 4's formatting depends on, and therefore rule 4's supplied
`format` as well.

Two alternatives were rejected. Widening the language with pointer arithmetic or
pointer slicing buys the same thing at far greater cost and hands every program a
primitive only an allocator needs. Re-freezing `Builder` to hold a `[]u8` instead of
an offset avoids the compiler change, but edits a frozen type that the delivery
discipline treats as a contract, and leaves the underlying gap for the next structure
that records an offset.

`view` is compiler-owned like `alloc`, `mark`, `reset` and `stats`, but unlike them
it has no runtime symbol: a base load, an add and a two-word store are emitted where
the call appears. It is the first arena intrinsic lowered inline rather than through
`neper_mem_*`, which keeps all three runtimes unchanged.

Nothing about arena ownership changes. `view` allocates nothing, moves no offset and
takes `*const Arena`; it is a way to name memory the caller already has, not a second
way to obtain it.

## D90 — one generated readiness document, updated by every session

Readiness is reported in `docs/progress.html` and nowhere else. It gives three
percentages — compiler, modules, tooling — each backed by a scored capability list in
which every row carries its evidence or its gap.

The page is generated by `scripts/render_progress.py`, never hand-edited. The compiler
and tooling scores come from rubric tables in that script; the module score is derived
from `docs/module-apis.md`, `docs/modules.json`, the committed `lib/e` sources and the
intrinsics seeded in `src/resolve.e`, so it cannot drift from the plan it summarises.
Scoring is `1` delivered, `0` not started, and a stated fraction when partial; items are
equally weighted inside a dimension, no dimension is weighted against another, and the
three numbers are never combined into one.

**Every session that lands a capability updates the page in the same commit.** A
readiness figure that moves only when someone remembers to move it is worse than no
figure at all, and the failure is silent: the number stays plausible while becoming
false. Generating the page keeps the cost of updating it to one edit and one command,
which is the only reason the obligation is realistic.

Two consequences are accepted. Compiler scope is the CPU language of M1 and M2, so M3's
GPU work and M5's Metal backend are excluded rather than counted as zero — a percentage
that silently included unstarted milestones would understate the CPU compiler without
saying so. And self-hosting is three rows out of fifty-one despite being the binary M2
exit gate, so the compiler number reads as capability coverage, not as distance to the
milestone; the page states this rather than reweighting to hide it.

This supersedes every ad-hoc progress artifact. There is no second copy to keep in step.

## D91 — `lines` marks its mode with the empty separator

`str.Split` is frozen at four fields — `source`, `separator`, `off`, `finished` — and
`lines` has to return one. But a line traversal is not a split on `"\n"`: it accepts
CRLF as well as LF, and it does not open a final empty field for the input's own
trailing terminator. `split_next` therefore has to tell the two apart, and the struct
has no field left to say so.

The empty separator is the state `split` cannot produce: it returns `InvalidSeparator`
for one. So `lines` sets `separator` to the empty string, and `split_next` reads that
as line mode. It costs one comparison per call and no field.

Two alternatives were rejected. Widening `Split` with a `mode` or `crlf` flag edits a
frozen type, which the delivery discipline treats as a contract. Overloading the
separator `"\n"` to mean line mode makes `split(s, "\n")` silently strip carriage
returns and swallow a trailing field, so an explicit separator would stop meaning what
it says.

The consequence accepted: the empty separator inside a `Split` is now spoken for, and
`it.separator` on a `lines` iterator reads as `""` rather than as a terminator. Section
14 makes the fields readable for diagnostics only, so no caller depends on the value.

## D92 — each `e.algo.rand` name is one published algorithm

`e.algo.rand`'s frozen surface names three generators and fixes their state layout,
but a name like `pcg64` covers a family. Pin each one to a single published variant:

- `Pcg64` is PCG `setseq_64_rxs_m_xs_64` -- 64 bits of state, 64 bits out, and an odd
  increment selecting one of 2**63 streams. `stream` holds that increment, which is
  why the constructor takes the selector and stores `(selector << 1) | 1`.
- `Xoshiro256` is xoshiro256**, the family's general-purpose member. `+` is documented
  as float-only and `++` differs only in the scrambler; `**` is the conservative pick
  where the output feeds anything.
- `Mt19937` is MT19937 seeded by the reference `init_genrand`, so a seed carries from
  any other implementation of it.
- Both `_f64` forms take the top 53 bits over 2**53. Every double in `[0, 1)` that
  yields is equally spaced and exactly representable, so nothing rounds.
- `xoshiro256`'s four words are the state, not a seed to expand. An all-zero state is
  the one the generator cannot leave, and the frozen signature returns no error, so
  it is replaced with a fixed non-zero state rather than accepted.

The reason to pin rather than leave it open is reproducibility across languages: a
seed written down in a paper, a test, or another runtime has to produce the same
stream here. That is also why the fixture compares against a separate implementation
of each reference rather than against statistical properties -- a near miss passes
every property test and fails every reproduction.

None of these is cryptographic, and the surface does not pretend otherwise: the state
is recoverable from the output by design.

## Consequences accepted

- **We own the optimiser.** v1 targets roughly `-O1` quality: inlining, constant
  folding, DCE, good register allocation. Explicit SIMD carries the vector
  performance rather than an auto-vectoriser. Beating LLVM on scalar codegen is a
  multi-year project; beating it on compile time is immediate and permanent.
- **x86-32 is in scope** and is a fourth emitter. It is sequenced last.
- **Self-hosting sets the language floor.** neper must be able to express a
  compiler — interned strings, growable arrays, hash maps — with no heap. This is
  a real constraint on minimalism and a useful forcing function.

## D93 — `printf`'s sink is generated, not declared

`str.builder_to` takes a `Sink`, whose `write` is `fn(*void, []const u8) -> err`.
`io.printf` has to supply one, and `e.io` declares no function of that shape:
`print` is `fn(s: []const u8) -> err`, a different arity, and section 12 exports every
module-scope declaration, so a helper would be a public symbol its frozen surface does
not name.

**The compiler generates the sink**, one per module that calls `printf`, as a single
call into `print`. This is available to `printf` and to nothing else for a reason
particular to it: `printf` is an intrinsic (section 14, and the pack exception D19),
so it has no source of its own in which a helper could be written and named. Where a
function does have source, the helper it needs is a declaration and belongs in the
surface — which is D94.

## D94 — `e.io`'s callbacks are declarations

`e.io`'s surface could not be implemented as it was frozen. Ten of its constructors —
`file_reader`, `file_writer`, `slice_reader`, `slice_writer`, `file_seeker`,
`limited_reader`, `counting_writer`, `tee_writer`, `buffered_source`, `buffered_sink`
— each have to supply a callback of their own, and the fence declared no function of
the callback shape. `reader`, `writer` and `writer_with_flush` take a caller-supplied
callback; they are not callbacks themselves.

There is no way to write one privately. Section 12 exports every module-scope
declaration, the language having no visibility mechanism, and section 2's list of
expression forms has no closure or function literal. So the callback a constructor
needs is a public symbol whether or not the plan names it, and the only question was
whether the plan would name it.

**The fence now names them.** This records what the language already makes true
rather than changing the design: the callbacks were always exported, and a surface
that omitted them was describing a module that could not exist. The alternative
readings were both worse. Allowing unlisted helpers would give up the property that
the plan knows every public symbol, which is the whole point of freezing a surface.
Making the ten constructors compiler intrinsics would work — it is what `printf`'s
own sink does, for the reason D93 gives — but it would put `e.io`'s implementation
inside the compiler, where it cannot be read as library source and cannot be changed
without a compiler release.

`printf` stays the exception rather than the precedent. Its sink is generated because
`printf` is itself an intrinsic and has no source in which to name a helper; every
constructor here has one.

`e.str` does not have this problem and needed no change: `builder_to` takes its `Sink`
from the caller.

## D95 — the bootstrap's archive is a tagged revision and its stage hashes

M2's exit item is "bootstrap compiler frozen, then deleted", and the handoff makes
deletion conditional on the self-host and recovery path being "securely archived and
reproducible". Neither document said what that archive is, so the precondition could
be asserted but never finished. It is now a step of its own, ahead of the deletion.

The archive is a git tag on the last revision whose `bootstrap/neper.c` compiles
`src/main.e`, the SHA256 of stage one, stage two and the stable stage recorded per
platform at that revision, and the commands that reproduce those hashes from a clean
checkout of the tag on a machine carrying no `neper` binary. Deletion then removes
the bootstrap from the working tree; the tag keeps it buildable.

The alternative is to commit a seed — a stage-one binary, or the compiler's generated
assembly — and it is worse on every count. A seed is two platform artifacts in the
tree that either grow with every compiler change or go stale against the source they
are supposed to build, and a reader has to trust their bytes rather than rebuild them.
Generated assembly adds back the external assembler that the own linker exists to
remove. A tag costs nothing to carry, and because the stages are already byte-for-byte
deterministic — `tests/selfhost/run.ps1` asserts stage two against the stable stage —
recorded hashes are a check that can fail rather than a note.

The hashes are per platform because stage one is not produced the same way on both:
on Windows the bootstrap emits MASM and shells out to `ml64` and `link`, on Linux to
the system toolchain. One number could not cover both, and the recovery path that
matters is the one for the platform in hand.

## D96 — `mem.address_of` reads an address out, and nothing reads one back

A pointer's address is available as a `usize` through one intrinsic,
`mem.address_of(p)`. There is no conversion in the other direction: no integer becomes
a pointer, and §8's bitcast rule is not relaxed to let one through.

The need is concrete. `os.syscall` (D32's route to a Linux `e.os`) takes six `usize`
arguments because that is what the kernel takes, and every filesystem call among the
seven `e.fs` is waiting for — `newfstatat`, `mkdirat`, `unlinkat`, `renameat`,
`readlinkat`, and `read` and `write` themselves — passes a path or a buffer as an
address. Without a way to name one, `os.syscall` could reach only the calls whose
arguments are all numbers, which is none of the ones that mattered. The alternative
considered was widening `mem.bitcast` to admit the pointer-to-`usize` direction. It was
rejected because the bitcast rule is stated over the types, not the direction: a rule
that reads "neither type holds a pointer" is checkable by looking at a type, and one
that reads "unless the pointer is on the left" is not, so every future use of
`punnable_type` would have to carry the exception.

Making it one-way is what keeps it cheap. The three things §8's rule exists to prevent
— inventing provenance, casting away `const`, manufacturing a callable address — are
all things done *with* a pointer, and none of them follows from a program learning where
one points. A `usize` cannot be dereferenced, and with no integer-to-pointer conversion
there is no expression that turns the number back into something the language will
follow. An address that leaves the program can only return through an interface whose
arguments are numbers — a system call — where the kernel, not the type system, is what
validates it. So the intrinsic emits no instruction: the address *is* the pointer, and
the `usize` is the same bits under a name with no way to be followed.

`address_of` takes a pointer and not a slice. A slice is a pointer and a length and has
no single address, so `&s[0]` is how the element whose address is wanted gets named —
which also makes the length the caller's business to pass, as every one of those calls
requires anyway.

## D97 — `e.os` is written per target, and `e.fs` is written once over it

D32 said `e.os` is the sole OS surface of `lib/e`, "written per target over raw syscalls
(Linux …), `kernel32` (Windows)". That is now what it is: `lib/e/os.linux.e` over the
`os.syscall` intrinsic, `lib/e/os.windows.e` over `extern fn` with `@import("kernel32.dll",
…)`, and `lib/e/os.e` for anything else — which is also the file the C bootstrap reads,
since it resolves `lib/e/<module>.e` and knows nothing about variants. `e.fs` is then one
portable file with no platform code in it at all.

The alternative was the route every existing `e.os` function takes: a seeded intrinsic
lowered to a symbol in `runtime_elf_x64_ext.s` and `runtime_pe_x64.asm`. Six primitives
over two platforms is ten to twelve hand-written stubs, each doing its own arena string
build and error translation, in the one part of the tree with no type checker over it —
and it would have made `os.syscall` (D32) and `mem.address_of` (D96) buy nothing, since
their whole purpose was to put the Linux half in neper. What replaced that is 180 lines of
checked source per platform.

The cost is that one module is one file, so the type block at the top of the three `os`
files is a copy rather than something shared. The language has no way to say otherwise and
D32 accepted that when it said "per target". The errors are not copied: `NotFound` and the
rest are seeded by the compiler into `e.os`, so declaring them in a variant would be a
second `NotFound`.

`os.NATIVE_SEPARATOR` is in the variants because `e.fs` needs to know which path
convention it is running under and nothing else can tell it. `e.path` is pure by
construction — it applies whatever `Style` it is handed and asks the host nothing — and no
comptime query names the target, so a portable `lib/e` module has no other source for it.
It is a helper beyond `e.os`'s fence, in the same category as the `c_string` and `widen`
that the variants also expose: §12 has no visibility, so a module's fence cannot have
private parts, which is the same reason `e.io` and `e.sync` are at `surface:"partial"`.
A comptime target query would remove the need for it and is the cleaner fix when the
general comptime interpreter is there.

`e.fs` stays at `surface:"partial"` for that reason and because half its fence is waiting
on primitives that do not exist: `metadata` needs times, permissions and a link count
where `os.FileInfo` carries a kind and a size, `read_link` and `symlink` need calls that
are one syscall on Linux and reparse-point work on Windows, and `canonical`,
`current_dir`, `set_current_dir`, `executable_path` and `temp_dir` still have no `e.os`
primitive at all.

## D98 — `os.FileInfo` carries what `e.fs.Metadata` promises

`os.FileInfo` was `{kind, size}`, and `e.fs.Metadata` promises times, permissions, a file
identity and a link count. So `e.fs.metadata` could not be written at all: the only two
fields it could have filled were the two `stat` already returns. `FileInfo` is now
`{kind, size, modified_ns, accessed_ns, created_ns, mode, file_id, link_count}`, and
`e.fs.metadata` is the mapping from that to `Metadata` and nothing else.

The fields are the ones both hosts can answer, in the form the host that *has* the notion
uses. `mode` is POSIX permission bits, because Linux stores exactly that; Windows has one
read-only flag, so it synthesises the bits and gives owner, group and other the same
answer rather than a narrower split that nothing on that host enforces. Turning nine bits
into nine booleans is `e.fs`'s job, not `e.os`'s — the portable presentation belongs where
the portable module is.

An unavailable timestamp is `-1` and never zero. Zero is a real Unix time, so a caller
comparing two of them could not tell "not recorded" from 1970. Linux has no creation time
in the structure `newfstatat` fills, so `created_ns` is `-1` there and a real value on
Windows; a caller that compares creation times has to allow for that, and the fence says
so.

Widening it changed how Windows answers. `GetFileAttributesExW` has no link count and no
file index at all, so `stat` and `lstat` are now `CreateFileW` with `FILE_READ_ATTRIBUTES`
plus `GetFileInformationByHandle`, which answers every field in one call. That is a better
primitive for a second reason: `CreateFileW` without `FILE_FLAG_OPEN_REPARSE_POINT`
follows the link, so `stat` genuinely describes the target and `lstat`, which passes the
flag, genuinely describes the link — where the previous pair had `stat` on a call whose
following behaviour is not clearly documented. It also removed `FindFirstFileW` and its
592-byte `WIN32_FIND_DATAW`, so the file has fewer types than before. `lstat` still asks
`GetFileInformationByHandleEx` for the reparse tag, because the handle information says
that a reparse point is there and not what it stands for, and an app-execution alias is
one without being a link.

The cost is a handle per lookup on Windows, where an attribute query needed none. It is
opened with `FILE_READ_ATTRIBUTES` and all three share bits, which is the least that can
be asked for, so a file another process holds open is still described.

`set_permissions` and `set_times` are still not implemented: they need `e.os` primitives
that write — `chmod`/`utimensat`, `SetFileTime` and the read-only attribute — and this
decision is about what can be read.

## D99 — `e.os` writes permissions as a mode and times as nanoseconds

`e.fs.set_permissions` and `e.fs.set_times` had no primitive under them: the `e.os` fence
described how to read a path and not how to change one. It gains two calls, spelled as the
inverses of what `stat` already reports — `set_mode(a, path, mode)` taking the same `mode`
as `FileInfo.mode`, and `set_times(a, path, accessed_ns, modified_ns)` taking the same
nanoseconds. Symmetry is the whole argument: a caller that read a value can write it back
without a conversion, and `e.fs` is again only the mapping between a mode and nine
booleans.

A negative nanosecond count leaves that stamp as it is, so one of the two can be set
alone. That is the same `-1` D98 gave "not recorded" on the way out, and both hosts have a
way to say it: `UTIME_OMIT` in a `timespec` on Linux, a null `FILETIME` pointer on
Windows. The Windows side is why `SetFileTime`'s three time parameters are declared
`usize` rather than `*FileTime` — a null is a meaningful argument there, and with no
integer-to-pointer conversion (D96) an address is what a `usize` parameter carries and
zero is the address that means nothing. `mem.address_of` supplies the non-null case.

**What a host cannot represent is not reported as a failure.** Windows has one read-only
attribute where POSIX has nine bits, so `set_mode` honours the owner-write bit and `stat`
reads the read and execute bits back as set whatever was asked for; a filesystem that
enforces no modes at all can succeed while changing nothing. The alternative was
`os.Unsupported` for any mode the host cannot store exactly, which is every mode on
Windows — it would make the call useless while telling a caller nothing it could act on.
The fence already promised the portable read-only/executable subset, and reading back with
`stat` or `metadata` is the only honest way to learn what took. `set_times` is the same
about precision: a filesystem that keeps whole seconds keeps the seconds.

Both fixtures check both directions of the write bit, because a call that changed nothing
would pass either direction on its own. They set whole-second stamps, since one of the two
filesystems this suite runs on drops the nanoseconds — precision it never promised, and
not what the assertion is about.

## D100 — `read_link` gives back the string, and `symlink` stores one

`e.os` gains `symlink(a, target_path, link)` beside the `read_link` its fence already
named. `read_link` returns the target **as it was stored** and resolves nothing: a
relative link gives back a relative string, because that string is what the link means and
resolving it is `canonical`'s job. A path that is not a link is `Unsupported` — EINVAL on
Linux, `ERROR_NOT_A_REPARSE_POINT` on Windows, one answer either way.

The two hosts disagree about what a link is, and the disagreement is handled at creation.
POSIX stores a string and asks nothing else; Windows records at creation whether the link
names a directory. So the Windows side looks the target up first — and looks it up **as
the link will see it**, resolving a relative target against the link's own directory
rather than the current one, which is the difference between a correctly typed link and
one that happens to work from where it was made. A target that is not there yet is taken
to be a file, since a link to something not yet created is still a link.

Making a link is privileged on Windows unless the host is in developer mode.
`CreateSymbolicLinkW` is passed `SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE`, and
`ERROR_PRIVILEGE_NOT_HELD` becomes `Denied` — a refusal by policy, not a failure of the
call. The fixtures skip on exactly that one error and on nothing else, so a machine
without developer mode still runs everything except the link assertions while any other
error, or a target that reads back wrong, still fails.

Reading the target is where the two hosts cost different amounts. Linux is one
`readlinkat`, sized from `lstat` — POSIX makes a symbolic link's `st_size` the length of
its target, which turns "how long is it" into one call instead of a doubling search, and
the doubling stays for the filesystems that report zero. Windows has no such call:
`GetFinalPathNameByHandleW` resolves the whole chain and would answer a different
question, so it is `DeviceIoControl` with `FSCTL_GET_REPARSE_POINT` and the reparse buffer
read field by field. Only `IO_REPARSE_TAG_SYMLINK` is read; a junction's path begins four
bytes earlier because it has no flags field, and every other tag is a reparse point that
is not a link at all, so both are `Unsupported`. The print name is preferred over the
substitute name because the substitute carries the object manager's device prefix, which
is stripped on the fallback path.

## D101 — the working directory is `e.os` state, and moving back is the caller's job

`e.fs.current_dir` and `set_current_dir` had no primitive under them; `e.os` gains the
pair under the same names, so `e.fs` is a pass-through and the two fences agree on what
the words mean. `current_dir` is absolute and in the host convention, which is what makes
its result something `set_current_dir` accepts — the round trip is the property worth
having, and the fixtures assert exactly it.

This is the first pair in `e.os` that reads and writes state belonging to the **whole
process** rather than to a path. Nothing here hides that: there is no scoped form, no
"run this with that directory", no saving and restoring around a call. A caller that
moves is the one that has to move back, because any wrapper that promised otherwise would
be lying in the presence of threads — the directory is one per process and `e.thread`
exists. Every other call in `e.fs` resolves its relative paths against whatever this is
set to, so moving it is a decision about the whole program, and it should look like one.

The two hosts differ in how they report a buffer that was too small, and both are handled
by the shape of the answer rather than by a guess. Linux `getcwd` returns `-ERANGE` and
nothing else, so the loop only grows; it also counts the terminating NUL, which a `str`
does not carry, so the result is one byte shorter than what the kernel reports — the
fixture catches getting that wrong, because a trailing NUL makes the directory's own name
stop matching. `GetCurrentDirectoryW` answers two questions with one number: what it
wrote when the buffer fitted, and what it needs — terminator included — when it did not.
Comparing against the capacity is what tells them apart.

What is still missing for the neighbours this unblocks: `canonical` needs a resolving
call (`realpath`, or `GetFinalPathNameByHandleW`), `executable_path` needs
`/proc/self/exe` or `GetModuleFileNameW`, and `temp_dir` and `home_dir` need `os.env`,
which is in the fence and not yet written.

## D102 — `executable_path` is what the host records, not what it ought to be

`e.os` gains `executable_path(a) -> (str, err)`, absolute, naming the running image. On
Linux it is `read_link` of `/proc/self/exe` and nothing else — the kernel already keeps
the image as a symbolic link, so the primitive that landed in D100 is the whole
implementation. On Windows it is `GetModuleFileNameW` with a null module handle.

**The two answers are not the same kind of path, and this does not pretend otherwise.**
Linux resolves the symbolic links in it, because that is what the kernel stores; Windows
gives the path the process was started from, links and all. Normalising the two would
mean resolving on Windows, which needs the resolving call `canonical` is still waiting
for, and would make this call quietly do more work than it says. The fence says which
host does what, and a caller comparing this against a path of its own should compare what
`canonical` makes of them rather than the strings.

The buffer protocols differ again and again the shape of the answer settles it.
`GetModuleFileNameW` signals a buffer that was too small by filling it exactly and
returning the capacity, so a result that fills the buffer is never treated as complete —
a truncated path is the failure mode this guards, and the fixture catches it by asking the
host to `stat` what came back. Linux needs no such loop, since `read_link` already sizes
itself from `lstat`.

The fixture cannot know the answer, so it asserts what has to hold whatever it is:
absolute, the same on two calls, and naming a file that exists and has bytes — which is
the running program itself. Both halves were pinned by breaking them: pointing Linux at
`/proc/self/cwd` fails on the kind, and dropping a byte from the Windows result fails on
the lookup.

## D103 — `os.env` reads the environment; `e.fs` knows which names to ask for

`e.fs.temp_dir` and `home_dir` are the environment and a check, so what they needed was
`os.env`, which the `e.os` fence already named and nothing had written. No fence change
this time.

**Linux reads `/proc/self/environ` rather than gaining a runtime primitive.** The
alternative was exposing `environ` from the stack the way `neper_os_args` already exposes
`argv`, which is assembly; this is `openat`, `read` and `close` through `os.syscall`, in
the same neper source as everything else in that file. It is a snapshot taken at exec, and
that is the whole truth here because nothing in this language changes an environment.
Every file under `/proc` reports a size of zero, so there is no asking how much to
allocate: a buffer that filled exactly may have been cut short, and only a short read
proves the whole of it arrived. Windows is one `GetEnvironmentVariableW`.

A name that is not set and a name set to nothing are different answers, which is why this
returns an `err` and not an empty `str`. Windows makes that distinction cost something —
both come back as a zero count, and only the error code afterwards separates
`ERROR_ENVVAR_NOT_FOUND` from no error at all.

The record scan is where the bug would have been: a name must match to its whole length
**and** end at the `=`, or `PAT` would be answered by `PATH` and the empty name by the
first record in the block. The fixture asks for `PATHH` and for `""` for that reason, and
dropping the `=` check fails it at exit 131.

`temp_dir` and `home_dir` ask different names per host — `TMP` then `TEMP` against
`TMPDIR` then `/tmp`, `USERPROFILE` against `HOME` — which is the second thing in `e.fs`
that has to know which host it is on, and it comes from `os.NATIVE_SEPARATOR` like the
first. Each candidate is kept only if it is really there and really a directory, which is
what makes a list of candidates worth having rather than a chain of first-set-wins.
Neither creates anything or checks that it can be written to: `temp_file` is what would
have to, and it is not written yet.

## D104 — `canonical` opens the path and asks what was opened

`e.os` gains `canonical`, absolute with every symbolic link, `.` and `..` resolved.
Neither host implements it by walking the path: both open it and then ask the host which
object the handle names, which is the same answer the host would have reached anyway and
is reached by the code that already does it correctly.

On Linux that is `openat` with `O_PATH` — which opens the name and nothing else, so no
permission to read is needed and a directory opens as readily as a file — followed by
`read_link` of `/proc/self/fd/<n>`. The alternative was writing `realpath` by hand:
component by component, following links, bounding the loop against a cycle, and getting
`..` right across a symbolic link, which is where hand-written versions go wrong. What
replaced all of that is a decimal formatter for the descriptor number, which is the only
formatting this file needs and the reason it does not reach for `e.str` — `e.os` may
depend on `e.mem` and nothing else.

On Windows it is `GetFinalPathNameByHandleW` over the same open `stat` uses, since
following links is that call's default. It answers in extended-length form, which is
correct and is not what anyone means by a path, so the device prefix is dropped — and a
UNC name gets its two leading separators written over the tail of that prefix, which is
exactly where they belong.

**It requires the path to exist**, and that follows from the method rather than being a
restriction chosen for it: there is no handle to ask about a name that leads nowhere. A
caller that wants to canonicalise a path it is about to create has to canonicalise the
parent.

The fixture cannot know the answer, so it asserts what must hold: absolute, not in the
extended-length form, one answer for two spellings of one place, and a file inside a
directory resolving to something longer that begins with it. The link case is the one that
makes resolution observable at all — naming the link and naming its target give one
answer — and both halves are pinned by breaking them: dropping the prefix strip fails at
exit 134, and resolving the input instead of the descriptor fails at 140.

## D105 — a temporary name is taken before it is handed out

`e.fs.temp_file` returns a path that already exists, and that is the whole design: a call
that returned a name for the caller to create would leave a window in which something else
could take it, and the fence's "never returns a predictable uncreated name" is that window
named.

Closing it needs a create that fails rather than opening a file that is there, and
`os.open` could not do it. `OpenFlags` has no exclusive form, and adding one is not the
small change it looks like: the struct is read at fixed offsets by the runtime assembly
that backs `os.open` on both hosts, and by the C bootstrap's copy of `lib/e/os.e`, so a
sixth field would be a change to hand-written assembly on two platforms. `e.os` gains
`create_new(a, path) -> (File, err)` instead — `O_CREAT|O_EXCL` on Linux, `CREATE_NEW`
with no share bits on Windows — which is one operation where a check and then an open
would have been two. The handle it returns is the same kind `os.open` returns, so
`os.read`, `os.write` and `os.close` take it unchanged.

`os.random` was in the fence and unwritten, and this is what needed it: `getrandom` on
Linux, `BCryptGenRandom` on Windows with a null algorithm handle and the system-preferred
flag, which is the form that needs no provider opened first. That makes `bcrypt.dll` the
second library `lib/e` imports from, which the import machinery already supported and
nothing had exercised outside a fixture. `getrandom` may return short or be interrupted
before it writes anything, so the loop is not decoration.

The name is twelve random bytes as twenty-four hex digits after the caller's prefix. The
retry loop exists because a collision is *possible*, not because it is expected — and it
retries on `Exists` alone, so a directory that is not there comes back at once rather than
after sixteen attempts at the same impossible name.

The fixtures pin both halves. Two draws differ and neither is the zeroed buffer a call
that wrote nothing would leave; creating the same name twice is `Exists` and leaves the
first call's bytes alone, which is what a `CREATE_ALWAYS` in place of `CREATE_NEW` fails
at.

## D106 — `replace` refuses two ways, and one host needs a second mechanism to do it

`e.os` gains `replace(a, src, dst, overwrite, durable)`: `rename` with the two questions a
caller actually has. `overwrite` decides whether a destination that is already there is
replaced or the call fails with `Exists`; `durable` decides whether the result is on the
disk before it returns, which is what a caller writing a file and swapping it into place is
after. Crossing a filesystem is `Unsupported` either way — neither host does it atomically,
and neither is asked to copy behind the caller's back, so `MOVEFILE_COPY_ALLOWED` is never
passed.

Replacing is what `rename` already does, so the interesting half is refusing to.
`RENAME_NOREPLACE` is the one call that decides and acts at once, and it is what Linux
uses — but a filesystem that does not know the flag rejects **the call** rather than the
destination. Measured: on tmpfs it works both ways, and on the 9p mount this is tested over
it returns `EEXIST` when the destination exists (the VFS layer answering) and `EINVAL` when
it does not. So the success path is the one that breaks, and it breaks on the filesystem
the suite runs on.

The fallback is what every Unix could always do: `linkat` fails if the name is taken, and
the old name goes afterwards. It is two operations rather than one, so a failure between
them leaves both names — but the destination still never appears half made, which is the
guarantee `replace` is for, and the fence already contemplates a partial effect being
reported. Windows needs none of this: `MoveFileExW` without `MOVEFILE_REPLACE_EXISTING`
already refuses, and `MOVEFILE_WRITE_THROUGH` is `durable`.

Durability on Linux is two `fsync`s, not one: on the file, so its bytes are on the disk,
and on the parent directory, so the name is. A name that survives a crash pointing at bytes
that did not is worse than losing both.

The fallback is pinned the way a fallback should be — by removing it and watching one
filesystem fail while the other does not. Without it `link/os_fs` still passes on tmpfs and
fails on 9p at exit 169, the case that renames onto a free name without overwriting. On
Windows, never setting `MOVEFILE_REPLACE_EXISTING` fails at 164.

## D107 — a directory-relative open is the host's walk, not a check before one

`e.os` gains `Dir`, `ResolvePolicy`, `dir_open`, `dir_close` and `open_at`, and `e.fs`
gains `Root`, `root`, `root_close` and `open_at` over them. The point of the family is that
a handle keeps naming the same directory even if the path that opened it is renamed
underneath, and that the resolve policy is enforced **while the host walks the path** —
not by a test made here first, which would be a statement about a path something else can
change before the open happens.

Linux is `openat2` and nothing else. `RESOLVE_BENEATH` refuses any step that would leave
the directory and `RESOLVE_NO_SYMLINKS` refuses any link at all, both inside the kernel's
own walk. Measured on both filesystems the suite touches, including the 9p mount, which
refuses a `Beneath` escape with `EXDEV` and a link under `NoSymlinks` with `ELOOP`. That
`EXDEV` is read at the call site rather than in `from_errno`: from `openat2` it means the
policy refused a step, where from `rename` the same number means a device boundary, and
collapsing the two would have made a refused escape indistinguishable from a filesystem
that cannot do the move.

Windows has no `openat` in `kernel32`, so every "open this name under that directory" it
offers is really a string join — which is exactly what the fence refuses to accept as a
safety claim. The implementation is `NtCreateFile` from `ntdll` with a `RootDirectory`
handle in its `OBJECT_ATTRIBUTES`, which is a true relative open, plus `OBJ_DONT_REPARSE`
for `NoSymlinks`: the object manager fails the whole path if any component is a reparse
point.

**`Beneath` is `Unsupported` on Windows**, and that is the honest answer rather than a
gap. Nothing in the object manager confines a walk to a subtree, and the fence is explicit
that a lexical prefix test or a canonicalise-then-open is not a substitute. Saying so
leaves a caller able to tell that the guarantee is absent; a fallback would not.

The shape check — absolute paths, `..` in any position, embedded NULs — happens before the
host is asked and answers `Denied`. It is not the security boundary; the resolve policy is.
It exists because those three are never a name *under* a directory, and because an embedded
NUL is the classic way a check and the thing checked come apart. On Linux the kernel would
catch two of the three anyway, which the fixtures show: removing the check there still fails
only on the empty name, while removing it on Windows fails on the absolute path, where a
leading separator with a root directory is a syntax error rather than a refusal.

Every guarantee is pinned by removing it. Without `RESOLVE_NO_SYMLINKS` or without
`OBJ_DONT_REPARSE`, `link/os_fs` opens a symlink it should have refused and fails at exit
192 on the respective host.

One trap worth recording: `openat2` rejects the whole call with `EINVAL` unless `how.mode`
is zero when nothing is being created. Setting a default mode once and leaving it made
every read-only open fail — and fail as `Unsupported`, which reads as "this host cannot do
it" rather than "you asked wrongly".

## D108 — `remove_at` and `rename_at` resolve the parent, then act on the name

The last three declarations in `e.fs`'s fence. `e.os` gains `remove_at` and `rename_at`,
and `e.fs` gains `remove_at` and `replace_at` over them, which closes the module.

Both hosts need the same two-step, for the same reason. The fence asks for two things that
sound compatible and are not: **traverse without following symlinks**, and **removing a
final symlink removes the link, not its target**. Neither host has one call that says both
— a flag that refuses links refuses the last component too, and a flag that opens the last
component as itself says nothing about the way there. So the parent is resolved first,
under the policy, and the final component is then acted on by name relative to that handle.
On Linux that is `openat2` with `RESOLVE_NO_SYMLINKS` and then `unlinkat`/`renameat`, which
never follow a final component anyway; on Windows it is `NtCreateFile` with
`OBJ_DONT_REPARSE` and then a second relative open carrying `FILE_OPEN_REPARSE_POINT`
without it.

The returned parent handle is the caller's to close only when it is not the one passed in,
which comparing the two raw values says. That is a small thing to get wrong quietly, so it
is one helper rather than a rule each call remembers.

Windows uses `NtSetInformationFile` rather than `SetFileInformationByHandle`. The Win32
wrapper rejects the form of `FILE_RENAME_INFORMATION` that names a root directory — it
answers with an unmapped error while accepting the same structure's disposition sibling —
and a rename that has to spell its destination as a full path is exactly the string join
this family exists to avoid. Using the native setter for both classes also leaves one error
vocabulary instead of two, since `NtCreateFile` was already there.

A durable rename on Windows asks for `FILE_WRITE_DATA` as well: `FlushFileBuffers` refuses
a handle that cannot write, and the handle a rename needs is otherwise opened for `DELETE`
alone. On Linux durability is an `fsync` of the destination directory, because it is the
name that has to survive — the bytes were the caller's to have flushed already.

The guarantee is pinned by removing it: with the parent walk following links, both hosts
remove a file named through a symbolic link that should have been refused, and `link/os_fs`
fails at exit 224 on each.

That leaves `e.fs` at 44 of its 45 declarations. The one not written is
`last_error_detail`, and it is not an oversight: the `e.os` fence says every failing call
"records the native code and portable classification in **thread-local runtime state**",
while spec section 15 says in as many words that "thread state travels in an explicit
context pointer, not thread-local storage", and rejects `__thread` and
`__declspec(thread)` by name. The two cannot both hold. A module-scope `var` is not a way
out — `e.thread` exists, so that is a race by construction rather than an approximation.

The e.fs fence already marks the call "a legacy M2 bridge pending H07, not the revised
checked API's error-detail transport", so the contradiction is known there too. Resolving
it is a decision about which of the two documents gives way, and belongs to whoever makes
that call rather than to the module that would consume the answer.

## D109 — the platform error detail is a named exception to §15, and stays unwritten

D108's closing paragraph overstated this, and this row corrects it. It said the `e.os`
error-detail contract and spec §15 "cannot both hold" and that someone had to choose which
document gives way. Two things are wrong with that. The conflict is not between the fence
and the spec — it is inside the spec, since §5's `os` table and its "Error detail state is
per OS thread" paragraph mandate exactly the ambient per-thread state §15 rejects by name.
And it is already reconciled: `docs/modules.md` lists "existing legacy platform-detail
state" among the explicit exceptions to ambient state, beside compiler-owned test-report
state, and says of them that they are "explicit exceptions, not invisible guarantees".

So §15 stands unamended and needs no adjudication. It states the rule; this one path is a
named, bounded exception to it, with a designated replacement — H07, which
`docs/post-m2-llm-hardening.md` charters to "replace the temporal requirement to call
`os.last_error_detail` before another failed operation with explicitly returned or
caller-supplied detail", and to "design rich detail as ordinary typed data, not ambient
exception state".

**The decision here is that the exception is not exercised.** `os.last_error_detail`,
`os.error_message` and `e.fs.last_error_detail` stay declared in their fences and stay
unimplemented. Three reasons, in order of weight:

Correct means all of it. The contract is that *every* failing `e.os` call records its
native code before returning. A version that records it in some paths and not others is
worse than none, because a caller cannot tell a stale detail from a fresh one — and the
temporal rule ("must be called before the next failing operation on that thread") gives it
no way to check. That is roughly forty call sites across both `e.os` variants, all of which
H07 then unwinds.

It needs a mechanism the language does not have. Thread-local storage has no spelling in
neper by choice, so this would be runtime state with no source-level form, added to two
runtimes, for a surface with no callers yet. A module-scope `var` is not an approximation of
it but a race, since `e.thread` exists.

And building it is migration debt by construction. The temporal contract is the specific
thing H07 exists to delete; writing it now would mean writing something whose replacement
is already chartered, and whose only consumers would be code that then has to change.

What a caller has instead is the `err` value — the portable classification the nine-error
table already gives, which is what §11's unified error type is for. What is lost is the raw
platform code, and that costs diagnostic precision rather than correctness. Where it bites
is `Failed` as a catch-all: the answer there is to widen the mapping in the two variants
when a particular code turns out to matter, which is a local change with a local test,
rather than to open an ambient channel for it.

The fence entries stay rather than being deleted. `e.fs` is therefore complete at 44 of its
45 declarations, and the readiness number keeps counting the surface that is planned:
removing the three entries would make both modules look finished while a promised call is
absent, which is the opposite of what that number is for.

## D110 — sockets are the transport only, and a narrow foreign return has to be widened

`e.os` gains the socket transport: `Socket`, the four descriptive enums, `SocketAddress`,
and `socket_open`, `socket_close`, `socket_set_nonblocking`, `socket_bind`, `socket_listen`,
`socket_accept`, `socket_connect`, `socket_send`, `socket_receive`, `socket_send_to`,
`socket_receive_from`, `socket_shutdown` and `socket_handle`. Linux is raw syscalls, Windows
is `ws2_32`.

`socket_resolve` is **not** in this increment. On Windows it is `getaddrinfo` and would be an
afternoon; on Linux, with no libc, a name lookup is a DNS client written in neper — a UDP
protocol implementation with its own parsing, retries and `/etc/hosts` fallback. That is a
piece of work in its own right rather than the tail of this one, and shipping it on one host
only would make the surface asymmetric in a way none of the rest of `e.os` is.

The address is encoded by byte index rather than as a typed struct. `sockaddr_in` and
`sockaddr_in6` agree on their first four bytes and diverge after, so one buffer holds either
with the length saying which — but the reason for bytes is that the port and the address are
big-endian on the wire while the family is in the host's own order. A struct holding both
orders would hide exactly the distinction that has to be got right, and `AF_INET6` differing
between the two hosts (10 and 23) is the one place these files disagree about the wire
rather than about the call.

Winsock has to be started before anything else touches it and there is nowhere to remember
that it has been — D109 is why this file keeps no ambient state for a flag. `WSAStartup` is
reference counted, so it is called once per `socket_open`, which is correct and cheap.

**A narrow signed return from a foreign call was being read unwidened, and this is the
finding worth keeping.** Both System V and Win64 leave the bits above the declared width
undefined for a value returned in a register, so a C function returning `int` defines only
`eax`. The code generator moved all of `rax`, which is right for neper's own calls — they
leave the value widened — and wrong for every `extern`. A `-1` then reads as `0xFFFFFFFF`,
which is not less than zero, so **every error check on a foreign call that reports failure
by a negative number passed silently**. It surfaced as a non-blocking `recvfrom` reporting
success with a byte count of -1, and it had been latent in every `extern fn` returning `i32`
since imports landed.

The fix is to widen a narrow integer call result with the same `normalize_integer` the
`Cast` opcode uses. It is applied to every call rather than only to foreign ones: neper's
own already arrive widened, so it is a no-op for them, and that is cheaper to reason about
than a rule that has to detect which kind of callee it is looking at.

`link/extern_import` now pins it with `atoi`, which is in `libc` on one host and `msvcrt` on
the other. Equality alone would not have caught it -- `0xFFFFFFFF` equals nothing and is
greater than zero -- so the fixture checks the value and its sign, and reverting the code
generator's widening fails it.

## D111 — a poller carries a pointer, and one host does not have one to carry

`e.os` gains the readiness poller: `poller_open`, `register`, `modify`, `unregister`, `wait`,
`wake` and `close`, over `epoll` on Linux. `Poller` changes from `struct { raw: usize }` to
`struct { state: *void }`, which is the same shape `e.fs.Walk` already uses.

That change is forced rather than chosen. A poller retains a set, and no host offers a single
handle that *is* a set together with the tokens attached to it — Linux comes closest, and
even there the poller needs two descriptors, its `epoll` and the one `poller_wake` writes to.
`poller_open` takes an arena, which is where that state belongs; but D96 leaves no way back
from a `usize` to a pointer, so a `raw: usize` cannot address it. A pointer field is the only
thing that reaches arena state, and `Walk` is the precedent.

The kernel's `struct epoll_event` is **packed** on x86-64: the 64-bit datum follows the
32-bit mask with no padding, so an entry is twelve bytes and not sixteen. It is declared here
as a mask and two 32-bit halves for exactly that reason — a `u64` field would be eight-byte
aligned and every entry after the first would be read from the wrong offset. The fixture
makes two sockets readable at once so that this is a test rather than a comment; declaring
the padding back in fails it.

`poller_wake` is an `eventfd` registered in the set under a reserved token, which is the
largest `usize`. A wake is one eight-byte write and one read drains however many arrived, so
a burst costs one wakeup rather than one each, and the descriptor is never reported to a
caller because it is not the caller's. The reserved token is the one value a caller may not
use, which is worth naming rather than leaving to be discovered.

**Windows reports `Unsupported`, and the reason is specific.** `WSAPoll` gives readiness but
retains nothing — the arena now solves that half — except that `poller_wake` then needs
something that becomes readable from another thread, and the only such thing there is a bound
socket whose port must be discovered. **There is no `getsockname` in the `e.os` fence**, so a
library cannot learn the port it was given and would have to pick one by searching, which is
not something a library may do to a machine. A completion port retains registrations and even
carries the token as its completion key, but it reports finished operations rather than ready
handles, so `readable` and `writable` would have nothing to mean.

Either route is design work rather than translation, so this says `Unsupported` — an answer a
caller can act on, where a half-poller is not. Adding `getsockname` to the fence is the
smaller of the two openings and would unblock the `WSAPoll` route; it is also missing for an
ordinary server that binds to port zero, which is the more common reason to want it.

## D112 — `socket_local_address` reports the port the host chose

`e.os` gains `socket_local_address(s) -> (SocketAddress, err)`: `getsockname` under the
`socket_*` name the rest of the family uses, since D11 keeps the neper-side name independent
of the foreign one.

It closes a hole that was visible from two directions. Binding to port zero asks the host to
choose a port, and without this call there was no way to learn which — so a server could not
tell a peer where to reach it, and neither could a test. D111 found the other direction: a
Windows poller needs a wake socket, the only wake a `WSAPoll` set can have is something that
becomes readable, and a library that cannot learn the port it was given would have to pick
one by searching. That is not something a library may do to a machine, so the absence of this
call is what made `poller_open` report `Unsupported` there. It no longer does so for that
reason.

The evidence that it was a hole rather than a nicety is what it deleted. `link/os_socket` and
`link/os_poller` both carried a loop that tried a fixed range of ports until one bound,
because nothing could report a chosen one — a test that races whatever else the machine is
running, in a suite that is supposed to be deterministic. Both now bind to port zero and ask,
and the range constants and the search are gone. The helper asserts a reported port is never
zero, which is also the check that the report is real: returning a zeroed address instead
fails both fixtures at exit 11 on both hosts.

Only the local address is added, not `getpeername`. `socket_accept` already hands back the
peer, which is where a server wants it, and nothing yet needs the peer of an already-connected
socket. Adding it later is one call in the same shape.

## D113 — the Windows poller keeps the set that `WSAPoll` will not

D111 reported the poller `Unsupported` on Windows and named two blockers. D112 removed one of
them, and this row is the other half: the poller is now written for both hosts.

`WSAPoll` gives readiness and retains nothing, so the set is kept in the arena that
`poller_open` was already given — which is what `Poller { state: *void }` exists for — and
passed in whole on every wait. `poller_wake` is one datagram from the wake socket to its own
address, which is why it needs no second descriptor and no pair; binding it to port zero and
asking `socket_local_address` is what D112 made possible. The alternative, a completion port,
retains the set and even carries the token as its completion key, but reports finished
operations rather than ready handles, so `readable` and `writable` would have had nothing to
mean.

`register` answers a duplicate handle with `Exists` and a full table with `OutOfMemory`,
which are the answers the other host's kernel gives to the same two mistakes — the point
being that the two implementations agree on the errors and not only on the successes.

**Only sockets can be polled here**, and the fence now says so. `WSAPoll` reports `POLLNVAL`
for anything else, which arrives as a failed event rather than as a lie: a handle this host
cannot poll is answered, not ignored.

Two structure layouts, opposite problems, and I got one of them wrong first. Linux's
`epoll_event` is **packed**: twelve bytes, so its padding has to be kept out by hand, and
declaring it back fails the fixture at exit 24. Windows's `WSAPOLLFD` is ordinary: the
socket's eight-byte alignment rounds the structure up to sixteen with nothing said, which is
the stride the call indexes by. I had written an explicit tail field there with a comment
claiming the array would otherwise land short. Removing it changed nothing — measured — so
the field is gone and the comment says what is actually true. A redundant field justified by
a wrong reason is worse than neither.

The wake is load-bearing on both hosts and pinned the same way: made a no-op, the fixture
waits out its four seconds and fails at exit 55, because a dead wake still returns zero
events and only the clock tells the two apart.

## D114 — a file mapping arrives as a pointer, and only one host can say so directly

`e.os` gains `map_file`, `mapping_bytes`, `mapping_bytes_mut`, `mapping_flush` and
`mapping_close`. `Mapping` already carried `address: *u8` and `len`, which is what made the
interesting problem visible: **a mapping has to arrive as a pointer, and D96 leaves no way
from an address to one.**

Windows says it directly. `MapViewOfFile` is declared as returning `*u8`, and a foreign
declaration is where a pointer comes into existence — the same boundary `os.reserve` uses.

Linux cannot: `mmap` is a syscall and `os.syscall` answers with an `isize`. Rather than add a
runtime stub in assembly — which is what every other pointer-returning primitive here is —
the pointer comes from `os.reserve`, which already returns a real one over a `PROT_NONE`
region, and `MAP_FIXED` then replaces that reservation with the file at the same address. The
pointer already held *is* the mapping afterwards. No assembly, and the reservation being ours
is what makes discarding it safe.

That is not a cosmetic choice, and the fixture shows it: dropping `MAP_FIXED` makes the
mapping land somewhere else while the pointer still addresses the `PROT_NONE` reservation, so
the process takes SIGSEGV and exits 139 rather than answering wrongly. `MAP_PRIVATE` in place
of `MAP_SHARED` fails at exit 34, where the write never reaches the file.

`mem.view` is how a pointer and a length become a slice, and it is the only such operation —
its own comment in the compiler says as much. So `mapping_bytes` builds a `mem.Arena` over the
mapping and views it: not to allocate out of, but because naming a region is what an `Arena`
is. That is the mechanism the language offers and there is no second one.

`Mapping.raw` carries whether the mapping may be written. Linux needs no handle to keep a
mapping alive, and Windows closes its mapping object as soon as the view exists — the view
holds its own reference — so the field is free for the one thing that must be remembered:
`mapping_bytes_mut` refuses a read-only mapping rather than handing back a slice whose first
write would fault. A refusal is an error a caller can act on; a fault is not. Removing the
check fails the fixture at exit 15.

## D115 — a watch begins when it opens, on both hosts

`e.os` gains `watch_open`, `watch_read` and `watch_close`. `Watch` changes from
`struct { raw: usize }` to `struct { state: *void }`, for the reason `Poller` did in D111:
each host reports a change by a **name relative to what is being watched**, so the watch has
to remember the path in order to give `WatchEvent` one, and `watch_read` is not passed it.

**The contract this row is really about is when watching starts.** Linux queues from the
moment `inotify_add_watch` returns. Windows records only from the moment
`ReadDirectoryChangesW` is called — so the synchronous form loses any change made between
opening a watch and first reading it, which is exactly what a caller writes: open, act, read.
Matching Linux means arming the read at open, which means the overlapped form. With no event
in the `OVERLAPPED` the file handle itself is what completion signals, so
`GetOverlappedResult` is the only extra call needed; no event object and no separate wait,
because there is never more than one read outstanding. `watch_read` waits for the outstanding
read and arms the next one **before** returning, so the gap is never open.

That is the whole reason the Windows half is not three lines, and it is pinned: with the
arming removed, the file created before the first read is not reported and the fixture fails
at exit 22.

`recursive` asks for `Unsupported` on **both**, and this is a deliberate refusal rather than
a missing half. Windows would take it as a parameter; Linux needs a watch per directory, a
table mapping each descriptor back to its path, and a new watch whenever a directory appears.
Honouring it on the host where it is free would make a program that works there fail on the
other — the asymmetry trap, discovered late rather than at the first call. Both refuse until
the Linux side is written.

A rename arrives as a removal and an addition rather than as `Renamed`. Both hosts report the
two halves separately — `IN_MOVED_FROM`/`IN_MOVED_TO` with a cookie, and
`RENAMED_OLD_NAME`/`RENAMED_NEW_NAME` — and pairing them means matching across a batch
boundary and holding the unmatched half somewhere. Reporting what each half actually is costs
a caller nothing it cannot reconstruct, where guessing would.

The fixture uses **one watch per action**. A single change is not one event everywhere:
creating a file is an addition on both and a modification as well on at least one, so a watch
that had seen two actions leaves a read holding whichever came first. A fresh watch has an
empty queue, which is what makes one read exact — and it is why the first version of this
fixture failed at exit 32 on Windows for a reason that had nothing to do with the watch. The
path is checked for being longer than the bare name as well as ending with it, since a name
with nothing prepended ends the same way; dropping the base fails Linux at exit 21.

A watch also needs a filesystem that reports changes, and finding out costs more than it
should: on a 9p mount `inotify_add_watch` **succeeds and returns a descriptor**, and then no
event ever arrives. So the failure is not an error a caller can see — the watch opens, and the
read never returns. Measured on the mount this repository lives on, which is why the Linux
runner puts the fixture on a local filesystem and why the fence now says a caller pointed at
arbitrary paths should not assume a watch will fire. It cost a hung suite run to find, which is
the most expensive way this session found anything.

## D116 — a broken pipe is the end of a stream, not a failure

`e.os` gains `pipe`, `kill`, `release` and `page_size`: four small primitives, both hosts.
`pipe` and `kill` are the two D15 named for the `neper test` runner, which is why they are worth
having before the larger families.

**The finding is in `os.read`, not in the new calls.** On Linux a read of a pipe whose write end
has closed returns zero bytes. On Windows `ReadFile` fails with `ERROR_BROKEN_PIPE`, and the
runtime turned that into an error — so a caller reading a pipe to its end could not be written
once. That is now mapped to zero bytes and no error in `neper_os_read`, which is what every
other runtime does and what the zero-byte convention already meant everywhere else. It was found
by the fixture failing at exit 37, and fixed in the assembly rather than in the fixture, because
a pipe whose end cannot be detected portably is a half-delivered pipe.

`page_size` is asked for on Windows through `SYSTEM_INFO` and answered as a constant on Linux.
That is not laziness on the Linux side: every syscall number in that file already pins it to
x86-64, where the base page is four kilobytes, and there is no way to ask without reading the
startup stack, which a library does not have. The Windows side reads offset four of the
structure, and reading the wrong field fails the fixture at exit 11 — the power-of-two check is
what makes a plausible-looking wrong answer visible.

`release` is the one place the two hosts disagree about what a call means. Linux `munmap` takes a
length; Windows `MEM_RELEASE` takes the whole reservation and insists the size be zero. The
length a caller passes is therefore used on one host and dropped on the other, which is worth
knowing before relying on a partial release.

And a mistake worth recording twice, since recording it once did not stop me: **Linux `munmap` of
an already-unmapped range succeeds.** The fixture first checked that releasing twice fails, which
passes on Windows and not on Linux — the same trap that had already been found and written down
during `os.syscall`. What it checks now is that the range can no longer be committed, which is
true on both.

`os.stdin` is in the fence and is **not** seeded, so it cannot be named from source at all —
found while giving the child its streams. `stdout` and `stderr` are there; `stdin` was simply
never added.

## D117 — a lock timeout is polled, because neither host has one

`e.os` gains `file_lock` and `file_unlock`. `FileLock` needs nothing but the handle, since both
hosts unlock through the same one they locked — so the fence's single `raw` is enough, unlike
`Poller` and `Watch`.

`timeout_ns` follows `wait_u32`'s convention: negative waits, zero attempts once. Neither host
offers a lock call that takes a deadline, so a **positive** timeout is a loop of non-blocking
attempts ten milliseconds apart. That is a real compromise and it is marked as one in both
files; a host call that took a deadline would replace the loop entirely.

The three outcomes are three different answers rather than one. Acquiring is `ok`; a zero
timeout that found the lock held is `WouldBlock`, because one attempt was all that was asked
for; a positive timeout that ran out is `Timeout`. Collapsing the last two would lose the
distinction between "not right now" and "not within the time I gave you", which is the only
thing a caller can act on differently.

The two hosts differ in strength and the fence already allows it. Linux `flock` is advisory —
nothing stops a reader that never asked — while Windows locks are mandatory and the system
refuses the read itself. The fence's "cooperative unless the platform explicitly guarantees
more" is worded for exactly this, and Linux is why.

The fixture makes the contention real instead of describing it: a lock belongs to the open file
description, not to the process, so two separate opens of one path contend and one process is
enough to make a lock block. Exclusion is pinned by removing it — with the exclusive flag never
set, the second claim succeeds and the fixture fails at exit 21 on both hosts — and the polled
wait is timed against the clock, so a timeout that returned at once fails rather than passing
for the right reason by accident.

## D118 — a process group is created with the child, not around it

`proc_group_spawn` needed its own spawn rather than a wrapper around `os.spawn`. A group that is
assigned after a spawn returns is a race with the child itself: between the two calls the child
can already have started children of its own, and those are outside the containment the caller
asked for. Both hosts have a way to close that window and neither of them is a second call on a
running process, so the group and the child are created together — which also delivers the
fence's `spawn_with_options`, since a spawn that takes options was the missing half of both.

Linux sets the group twice. The child calls `setpgid(0, 0)` between the fork and the exec, and
the parent calls `setpgid(child, child)` as soon as the fork returns. Whichever runs first wins
and the other is harmless, and the point of doing both is that the group exists before either
call returns: the child cannot reach `execve` without being in it, and the parent cannot return a
`ProcGroup` that is not yet real. A `pgid` is not a handle, so `proc_group_close` is a no-op and
`proc_group_terminate` is `kill` with a negated group — which is all `killpg` ever was.

Windows creates a Job object first and starts the child `CREATE_SUSPENDED`, assigns it, and only
then resumes the thread. The suspension is the same window closed from the other side: the child
has not executed an instruction when it joins the job. An assignment that fails terminates the
child rather than resuming it, because a caller that asked for containment should not be handed a
loose process. `TerminateJobObject` ends everything in the job at once, and `force` has nothing to
choose between there — this host has no signal to ask politely with.

Everything the Linux child needs is prepared before the fork, because it may not allocate. The
argument and environment vectors, the program path and the target directory are all built in the
parent's arena, and after the fork the child does nothing but `setpgid`, `chdir`, three `dup2`s
and `execve` — each one syscall, none of them touching the allocator or the runtime. `execve`
only returns when it failed and there is nobody to tell, so the child exits 127, which is the
shell's number for the same thing.

`inherit_env` means overlay, and the fence says so: the parent's environment with the caller's
entries laid over it, an entry replacing an inherited record of the same name rather than joining
it. Neither host appends to an environment, so the overlay is built by hand — Linux from
`/proc/self/environ`, which `env` now shares a reader with, and Windows from
`GetEnvironmentStringsW`, walked as UTF-16 with the names folded to lower case, because
environment names are not case-sensitive there and a block holding both `Path` and `PATH` answers
with whichever the host reaches first rather than the caller's. Inheriting with nothing added
stays a null pointer on Windows and the parent's own block on Linux: that is what the request
already means, and copying it would only be a way to get it wrong.

Two ceilings are deliberate. `Stdio.inherit` is not honoured as an exact set — Linux passes every
descriptor without close-on-exec and Windows every inheritable handle, so the named list is a
minimum, and the fence now says as much. And the pipe ends `os.pipe` returns are not inheritable
on Windows, so a child cannot yet be given one as a stream; that is `pipe`'s decision to revisit
when `e.proc` needs it, not this one's.

The fixture spawns its own image with a marker argument, since that is the only program it can be
sure exists, and each mode answers by its exit code: the overlay case checks both the addition
and that the parent's `PATH` survived, the replacement case checks that `PATH` is the caller's,
the bare case checks that nothing else came through, and the `cwd` case asks the child where it
is. Both halves are pinned by removing them. With the override filter disabled the child reads
the inherited `PATH` and the run fails at 83 on both hosts; with both `setpgid` calls removed on
Linux the terminate finds no group and fails at 32. What is not checked is containment of a
grandchild, which cannot be observed from outside without an identity the parent has no way to
learn.

## D119 — `stdin` is source, and the three standard streams no longer come from one place

`stdout` and `stderr` are seeded intrinsics backed by runtime assembly, written before `e.os`
was source at all. `stdin` was in the fence and had never been supplied, and the cheapest way to
supply it now is a function in each variant: descriptor zero on Linux, `GetStdHandle` on Windows.
The alternative was two more assembly stubs and a third seed, for three lines of behaviour.

So the three streams are asymmetric in provenance and identical in effect. That is worth naming
because it looks like an oversight from either side: a reader of `src/resolve.e` sees two of the
three seeded, and a reader of a variant sees one of the three written. Neither is wrong, and the
seeded pair is not worth moving — a seeded name cannot also be declared in a variant, so moving
them means editing the runtime, the seeds, `lower.e`'s name mapping and both link paths to change
nothing observable.

`link/os_process` compares the three against each other rather than against a constant, since
what the fence promises is three distinct streams and what a wrong constant does is answer with
the neighbouring one. Both fixtures that spawn a child now name `os.stdin()` where they used to
carry a comment saying they could not.

## D120 — one host has a resolver, the other gets a DNS client

`socket_resolve` is the one call in the fence where the two hosts are not the same amount of work.
Windows hands the name to `GetAddrInfoW` and that is the whole of it: a literal, the hosts file,
the cache, DNS and whatever else that host is configured to consult, all behind one call. Linux
has nothing to hand it to. D32 says raw syscalls and no libc, and there is no syscall that
resolves a name, so the resolver is written here: a literal, `/etc/hosts`, then plain UDP DNS to
the servers in `/etc/resolv.conf`.

The DNS half is deliberately a stub resolver and not more. It asks with recursion desired, so the
tree is walked on the far side of the socket; it does not follow a `CNAME`, because a resolver
asked to recurse puts the target's addresses in the same message; and it does not check whose name
each record sits under, which that same resolver has already decided. Three ceilings are marked in
the source: 512-byte messages with no EDNS0 and no retry over TCP, so a truncated answer is used
for whatever it did carry; at most eight addresses and three servers, which is what a caller about
to connect to one of them uses; and no search-suffix list, so the question asked is the question
given.

Two things are not optional and are done. The identifier is random rather than fixed, and an
answer carrying a different one is discarded — a predictable identifier is an invitation. And the
socket is `connect`ed to the server rather than sent to, so the host itself drops anything
arriving from any other address; that is the cheap half of not believing a stranger and the
identifier is the other.

Answers are classified the way a caller can act on. `NXDOMAIN` is `NotFound` and stops the search,
because a resolver that says a name does not exist has answered the question and asking the next
one is asking it twice. A name that exists with no address of the family asked for is also
`NotFound` — there is nothing there to connect to either way. A deadline that ran out is `Timeout`
rather than `WouldBlock`, since nothing about it says to try again immediately. Nothing configured
in `/etc/resolv.conf` is `NotFound` and not a failure to reach anyone: there is nobody to reach.

A literal is answered without reading a file or asking anyone, and a literal of the *other* family
is `NotFound` without asking either — sending `127.0.0.1` to a resolver as an IPv6 name can only
be told no, slowly. The IPv6 parser takes the compressed form, the full form and an embedded
dotted quad (`::ffff:127.0.0.1`), and refuses a zone suffix: naming an interface means asking the
host for its index, which is a syscall family this file does not otherwise touch. Windows accepts
one, so the fence now says so rather than leaving it to be discovered.

The fixture needs no network, which is not a claim to make without checking. Under `unshare -rn`
the whole of it still passes, and with the hosts path removed it fails at 40 — so `localhost` on
Linux is answered by `/etc/hosts` and not by a nameserver that happened to be reachable. That pair
is a manual check rather than part of the suite, because user namespaces are not available
everywhere and a suite that needs them fails for the wrong reason. The DNS path itself cannot be in
the suite at all: it is verified by a scratch program against a real name, whose answer matched the
host resolver's, and the committed fixture only requires that a name reserved never to exist fails
— which offline is a timeout and online is a name that is not there, both correct.

## D121 — the calendar is a shift, not a table, and its range is what an i64 reaches

`e.time`'s five calendar conversions and its two ISO-8601 halves are the last of that fence, and
they are pure arithmetic: no host is asked anything, so both targets run the same code and there is
nothing to keep symmetric.

The conversions are Hinnant's civil-date algorithms, which shift the year so that it begins in
March. That moves the leap day to the end of the year, which makes the month lengths one linear
expression instead of a table and makes the inverse the same shape as the forward direction. The
alternative — a table of month lengths and a special case for February — is more code and has more
places to be wrong.

Every division that splits a timestamp into days floors rather than truncates, and that is the one
thing here most likely to be got wrong quietly. A timestamp before 1970 is negative, and truncating
toward zero puts the second before midnight in the following day: `1969-12-31T23:59:59Z` becomes
the first of January. The fixture pins it — with the floor replaced by the plain operator the run
fails at 22, and with the century rule dropped from the leap test it fails at 34.

The representable range is a consequence, not a policy. An i64 of nanoseconds reaches 106751 days
either side of the epoch, so the calendar spans 1677 to 2262 and `from_civil` refuses anything
outside it rather than wrapping. The bound is set one day inside that, at 106750, because a whole
day of nanoseconds added to the last day passes what an i64 holds — one refused day at each extreme
is better than an addition that overflows.

Three things are refused rather than repaired. The thirty-first of February is `Invalid`, not the
first of March: the fence's clamping rule is about adding months and years, where the day has to
land somewhere, not about being handed a date that is not one. A leap second is `Invalid`, because
a count of nanoseconds since the epoch has no gap to put one in and folding it into the following
second would answer a question nobody asked. And a civil time with no zone is `Invalid` on parse —
a `Timestamp` is an instant, and a local time without an offset does not name one.

`format_iso8601` is fixed width, always UTC and always nine fractional digits, so
`1970-01-01T00:00:00.000000000Z` is thirty bytes for every representable timestamp and a caller can
size a buffer without asking. Every year in range is four digits, which is what makes that true. A
buffer too small gets an empty string rather than a truncated timestamp that would read like a real
one. `parse_iso8601` takes that shape and the shorter spellings of the same instant — the fraction
absent or one to nine digits, the zone `Z` or `+HH:MM` — and marks as a ceiling what it does not
take: ordinal dates, week dates, a comma for the decimal point, and the basic format with no
separators are all ISO 8601 and none of them are here.

`e.time` stays at `surface: "partial"` even though the whole fence is now written, because the
calendar needs helpers of its own and spec 12 has no visibility — a module held to its fence exactly
could not have them. That is the same reason `e.io` and `e.sync` sit there, and the file's own
header used to say the five conversions were missing; it now says why the surface reads as it does.

## D122 — a glob is two nested matchers, and the outer one is the reason `**` exists

`e.path`'s `glob` and `glob_match` complete that fence. They are pure matching: a pattern that
matches says two strings correspond, never that anything exists, which is what the fence means by
"matching proves no filesystem containment".

The structure follows from one line of the fence: `*` and `?` match within a component and a whole
`**` component matches zero or more components. So there are two matchers, one nested in the other
— the outer one walks components and the inner one walks bytes — and `*` cannot cross a separator
because the inner matcher is never given one. Any implementation that matches the whole path as a
single string has to special-case separators everywhere instead.

Both matchers backtrack the same way, with two cursors rather than recursion: on a mismatch the last
star gives up one more unit and the scan resumes just after it. That needs no stack, which matters
because `glob_match` takes no arena and must allocate nothing. It is also what the step limit is
for — this shape is quadratic on patterns like `*a*a*a*a*b` against a long run of `a`, and the fence
says work-limit exhaustion is `TooLarge` and never a quiet `false`.

A zero limit means no limit, for both `max_steps` and `max_pattern_bytes`. The alternative reading —
that a zeroed `GlobOptions` permits no work at all — would make the default value refuse every
pattern, and a caller who wants a budget can say so.

Three consequences of the fence that are worth writing down because they surprise:

A `/` cannot appear inside a bracket class. The pattern is cut into components before any class is
read, so `a[/]b` is the two components `a[` and `]b`, and the first has an unterminated class — the
pattern is refused at compile time rather than never matching. That is stronger than the fence
requires and it is the only self-consistent reading of "pattern separators are `/`".

`**` only means "zero or more components" as an entire component. Inside one, as in `a**b`, it is
just a run of stars and stays inside that component, because that is what "a whole `**` component"
says.

Empty components and `.` are skipped in both the pattern and the path, so `a//b`, `a/b/` and `./a/b`
all match `a/b`. This is not normalization creeping in — `.` and `./x` name the same relative path,
and a matcher that disagreed would be answering a different question than the caller asked. `..` is
the opposite case and is `Invalid` on both sides, since asking about a parent is asking about
containment.

Case folding is asked for and never assumed, including inside a class: a range holds a byte if it
holds it as written or, when folding, if the other case of it falls inside. Folding the bounds
instead would quietly turn `[A-z]` into something else while leaving `[0-9]` alone, which is a worse
kind of wrong than not folding at all.

The pattern is copied into the arena rather than referenced, so a `Glob` does not depend on the
caller keeping their string alive. `glob_next` is a second component walker beside the existing
`next_component`, which the older functions use: this one reports whether it found anything instead
of answering with an empty string, and it skips what a glob skips. Changing the old one would have
changed `normalize` and `relative` for no reason.

`link/path_glob` spends most of itself on the boundary between the wildcards, since that is where
the fence is specific and where implementations differ. Making `**` consume a component instead of
matching zero fails the run at 40. The step limit is pinned in the fixture itself rather than by
removal: the same pattern is `TooLarge` with a budget of eight steps and answers correctly with
none, so the limit is what stopped it and not the pattern.

## D123 — `e.mem`'s last four split in half, and the layering decides where each one lives

`copy`, `eq`, `size_of` and `align_of` complete `e.mem`, and they are two different kinds of thing.
`copy` and `eq` are ordinary generic code — the first of that module written in source rather than
supplied by the compiler — while `size_of` and `align_of` cannot be written at all, because only the
compiler knows a layout.

`copy` takes the shorter of its two slices. The fence gives it no return value, so there is no way
to report a length mismatch; the alternative to copying what fits is trapping on a question the
caller has no way to ask about. `eq` requires an element type that `==` accepts, which is every
scalar, pointer and enum and no struct — `eq[SomeStruct]` is `InvalidOperator` reported inside
`lib/e/mem.e`. That is the right constraint rather than a gap: comparing structs as bytes would
compare their padding and call two equal values different. The wart is where the diagnostic points,
which is the library and not the call.

The other two needed less compiler work than expected, because `e.meta`'s scalar reflection already
established the shape: a type goes in, a constant comes out, and nothing survives to run time. So
they join `MetaQuery` instead of getting a path of their own, and `emit_reflection` already knew how
to lower a constant. No new `CallInfo` field either — `meta_subject` exists and is guarded by a
different flag, which matters while the bootstrap's declaration table sits at its limit.

What forced the one real design choice is the layering. `layout` is built on `check`, so the checker
cannot ask what a type's size is; it carries the *type* and lowering emits the number. `bitcast`
already compares its widths there for exactly this reason, so this is the established direction and
not a workaround.

That layering has a consequence worth writing down because it is invisible until tried:
**`mem.size_of[T]()` cannot stand in an array length.** `[mem.size_of[u32]()]u8` is
`Unsupported`, because an array length is evaluated while checking and the size is only reachable
while lowering. The value is a genuine compile-time constant in the code that comes out — no call is
emitted — but it is not one the checker can use. Making it usable there means moving layout under
check, which is a much larger change than this increment, and supporting it for scalars only would
be worse than not supporting it: a rule that holds for `u32` and not for a struct is harder to learn
than a rule that never holds. I asserted the opposite in the fixture, both suites failed on it, and
the assertion is now the comment that records why.

`link/mem_slices` pins the layouts that would expose a wrong rule rather than the ones anyone would
guess right: `{u32, u32}` is 8 bytes aligned 4, and `{u8, u64}` is 16 aligned 8 — seven bytes of
padding and then a tail round-up. It also checks what must hold for any type whatever the rules are:
a non-zero power-of-two alignment, a size no smaller than it, and a size that is a whole number of
it.

## D124 — a type-valued answer belongs in `comptime_type`, which is not the type grammar

`meta.element_type` and `meta.backing_type` return a type rather than a number or a name, and the
question that decides where they live is where such an answer can be written. Spec section 9 says a
comptime expression of type `type` stands wherever a type is written, so the implementation is a
`CallExpr` case in `comptime_type` — the one function that evaluates a type expression — and nothing
in `check_call` at all. There is no value for a call like this to produce, so the only place it can
be asked for is a place expecting a type.

That makes both of them one step each with no aggregate built: `element_type` reads the element a
slice or array type already carries, and `backing_type` reads the `backing_type` an `Aggregate`
already holds, which is populated for a union enum as well as an enum because a union enum is an
enum with payloads hung off it. Vectors are named by section 9 and skipped, since this compiler has
no kind for one; `str` is skipped because section 9's list is array, slice and vector and a string is
its own kind here.

An earlier note on the readiness page said these two were blocked because "the type grammar admits
no call". That was half right and worth correcting rather than repeating. The type grammar is not
what evaluates a comptime argument: `mem.size_of[meta.element_type[[]u8]()]()` reaches
`comptime_type` directly and works, as does nesting one question in the other, and as does
instantiating a generic of the caller's own with the answer — which is how a caller reaches a value
of the element type without having a name for it. What the type grammar does block is the direct
spelling, `var x: meta.element_type[T]() = zero`, which is a syntax error: that grammar accepts a
dotted name (`FIELD.ty`, which is why `meta.get`'s return type works) and not a call. Fixing it
means accepting the lossless `Name[...]()` node in a type position and letting name resolution
classify it, which section 14's first invariant requires anyway — the parser may not consult the
symbol table. That is a parser change and it is not in this increment.

`Field` and `Member` are deliberately still not declared, and the reason is worth stating so it is
not mistaken for an oversight. Declaring the names is trivial and would move the readiness count by
two, but a name that resolves to a type nobody can use is worth less than an honest gap.
`ComptimeKind.Field` and `.Member` already exist, and a `Field` value is created in exactly one
place: the binding of an unrolled `for` over `meta.fields[T]()`. For a user declaration to take
`[FIELD: Field]` as section 9 promises, six sites need work — the seeds; the comptime-parameter
declaration, which today maps an annotation to `.Type`, `.Str` or `.Integer` and rejects everything
else; the generic-argument loop, which handles only those same kinds and would have to accept a
comptime binding as an argument; `comptime_type`'s `FieldExpr` case, which resolves `FIELD.ty` for a
binding but not for a parameter; the member reader behind `FIELD.name`, `.offset` and `.size`; and
lowering's offset path. That is a feature, not the tail of this one.

`link/meta_types` is written to fail if the answer were merely a number that happened to be right:
it nests the two questions, asks `kind` of each answer, and hands each to a generic that returns a
value of that type. A signed backing carries a negative value through that generic, which a size
comparison alone would not have shown.

## D125 — a comptime value crosses a call, and one funnel carries it

`Field` and `Member` complete `e.meta`. D124 said declaring the names without the rest would be
worth less than an honest gap, and this is the rest: a user declaration takes `[FIELD: meta.Field]`,
reads its members, and hands it on, which is what spec section 9 means by "available to user
declarations under the same rule as the `e.meta` intrinsics".

The leverage is that everything reading a comptime value already goes through one function.
`find_comptime_binding` resolved a name against the stack an unrolled `for` pushes to; it now falls
back to a `Field` or `Member` parameter of the enclosing instantiation, and with that one change
`FIELD.ty` as a type, `FIELD.name` and `.offset` as expressions, `meta.get` and `meta.set`, and
lowering's constant for the offset all work on a parameter without knowing there is a second way to
bind one. Only those two kinds fall through: a `T` must not be found there, or `T.anything` would
read as a member of a comptime value rather than as the type it is.

There is no `Type` for either of them anywhere in the checker, and that is how comptime-only is
enforced rather than something checked separately. A parameter annotated `meta.Field` is recognised
by the name it resolves to and turned into a `ComptimeKind`; nothing else can name it, so there is
nothing for a struct field, a local or a pointee to be declared as — exactly what section 9 says.
The seeded names exist so that `meta.Field` written anywhere else is a type error rather than an
unknown name.

Four more sites followed, and each was found by a probe that failed rather than by reading:

A `Field` argument at a call is always a name, because a `Field` has no spelling of its own — it
comes from `meta.fields`. So `specialize_call` resolves the argument as a comptime value and copies
it wholesale; `bind_inferred_argument` could not be reused, since it carries a type and a value and
would lose the owning aggregate.

A generic body is checked once at its declaration, before anything is bound to its parameters, and
section 9 puts every check that depends on a comptime parameter at the instantiation. So an unbound
`Field` parameter answers with a placeholder: what a member of it *is* can be said there, what it
holds cannot. This is safe for a reason worth stating — a declaration's body is never lowered, only
every instantiation of it is, so a placeholder cannot become wrong code. `meta.get`'s ownership
check is deferred the same way: at declaration time neither the field nor the type it belongs to
exists yet, and every instantiation still passes through that check with the argument set.

`FIELD.ty` in a parameter or return type is that placeholder, so `substitute_type` maps it to the
type the bound field has. A `Member` is not accepted there: its members are a name and a value, so
there is nothing for one to stand for.

The subtlest was inference. A `FIELD.ty` parameter is a `TypeParameter` whose index belongs to a
comptime `Field`, and argument inference happily bound it as a type — rebinding `FIELD` to whatever
the argument happened to be and losing the field it named. Nothing is inferable there: the field was
named at the call and its type follows from it. Removing that one guard fails `link/meta_field_param`
at 88, which is how it is pinned.

The fixture is about the handover rather than the reflection, since `link/meta_reflect` already
walks a struct inside one function. Here the value crosses a call, so the callee is instantiated per
field with a return type that depends on which one it got; one case relays its own parameter to a
third function, which is what says a parameter and a loop's binding are the same kind of thing; and
a write through a call is read back in place, so an offset that were not the field's own would land
somewhere else and show up as a wrong value rather than a type error.

Left where it is: a generic *aggregate* taking a comptime `Field` — `type Holder[FIELD: Field]` with
a field of type `FIELD.ty` — which section 9 permits and `substitute_aggregate_type` does not do.
Nothing needs it, and it fails as an error rather than silently.

## D126 — the type grammar gets brackets and a trailing call, and the resolver does the classifying

D124 recorded that `var x: meta.element_type[T]() = zero` was a syntax error and that fixing it meant
accepting the node and letting name resolution sort it out. This is that change, and looking at it
turned up a second gap in the same function that had nothing to do with `e.meta`.

`parse_named_type_node` parsed its bracket arguments with the expression parser, so a composite type
could not stand there: `list.List[[]u8]` in a type position failed with "unexpected `]`", while the
same thing in an expression worked. The expression grammar decides type-or-value per argument with
`bracket_argument_is_type`, and the type grammar had no reason not to. One call swapped, and both
spellings agree. That was a bug rather than a missing feature, and it is fixed where every caller
goes through rather than where it was noticed.

The trailing `()` is the feature. The parser accepts it after a bracket and keeps the tokens without
deciding anything, because section 14's first invariant says it may not consult the symbol table --
`Name[...]` is a comptime argument list after a function or a type and an index after a value, and
only the symbol table knows which. So the node stays a `NamedType` carrying the parens, and two later
stages read them: name resolution looks the member up as a value rather than a type when they are
present, and the checker routes such a node to the same answer a call in an expression reaches. The
two spellings share `derived_from_subject` so they cannot drift.

Requiring the bracket before the parens is deliberate. `Name()` where a type is written is not a
shape section 9 gives any meaning to, and accepting it would have this function swallowing tokens
that belong to whatever follows.

What this buys is the spelling the spec names first: `var element: meta.element_type[[4]u32]() = zero`,
including nested and including a signed enum's backing carrying a negative value. Before it, the
answer was reachable only by handing it to a generic of the caller's own -- which works and is what
`link/meta_types` used, but is not what section 9 says a comptime expression of type `type` does.

Both halves are pinned by the fixture rather than by argument: before the change its annotation lines
failed with "unexpected `(`" and its `list.List[[]u8]` line with "unexpected `]`", and both are in it
now.

What actually broke was neither, and it is worth recording because the mistake is easy to repeat.
Deciding whether a named type carries a trailing call by looking for a `(` anywhere in its tokens
finds the parentheses of an ordinary argument: `Sized[(N << 1u8) | 1usize]` is an instantiation and
has one, so every such type was routed to the comptime-call path and failed.
`check/constant_operators_valid` caught it. Both the checker and the resolver now test the last two
tokens and nothing else, which is exactly what the parser accepts, and that shape is in
`link/meta_types` beside the feature that caused it. The risk I had expected instead -- that
existing instantiations would now hand the checker a type node where they used to hand a name
expression -- was not one: `bracket_argument_is_type` answers false for a bare name, so nothing
about those changed.

## D127 — a comptime `Field` parameterises a type, by the same two edits a function needed

D125 left one thing out: `type Holder[FIELD: Field]` with a field of type `FIELD.ty`, which section 9
permits and `substitute_aggregate_type` did not do. It is now done, and the interesting part is how
little it took — the aggregate path needed exactly the two changes the function path had already had,
in the two places that mirror each other.

`collect_generic_arguments` binds an aggregate's comptime arguments the way `specialize_call` binds a
function's, and both handled only a type, a `str` and an integer. A comptime value is a name that
already holds one, so both now resolve it through `find_comptime_binding` and copy the argument
whole. `substitute_aggregate_type` maps a `TypeParameter` to its bound argument the way
`substitute_type` does, and both now accept a `Field` there, because the type the bound field has is
what the declaration's placeholder stood for.

Nothing else was needed. `FIELD.ty` as a *field's* type already resolved: it goes through
`type_from_node`, `comptime_binding_type_path` and then `find_comptime_binding`, which D125 had
already taught to answer for a parameter. That is the second time that one funnel has paid for
itself.

What the fixture asserts is not that the struct works but that each instantiation is its own: the
size of `Boxed[f]` equals `f.size` and its alignment equals `mem.align_of[f.ty]()`, for every field
of a struct whose fields are an i64, an i32 and a u8. If substitution had collapsed them to one type,
or to the placeholder, those would not hold — a value read and written through the struct would still
look right. Removing the one line that accepts a `Field` in `substitute_aggregate_type` fails the
fixture at 109 with `MissingContext`.

That closes the last gap `e.meta` had. What remains in the reflection row is not a gap in section 9's
surface: `Field` and `Member` cannot be inferred, only written, and nothing asks for them to be.

## D128 — the loader group, and why Linux was never blocked

`dlopen`, `dlsym` and `dlclose` complete `e.os`. Every earlier note in this repository, and my own
reasoning about it, said the Linux half was blocked: there is no syscall that loads a shared object,
so `e.os` would have to name libc, which contradicts D32's raw-syscall rule and gives up the
freestanding ELF that D13 stages first. Two measurements retire that argument.

`@import("libc.so.6", ...)` already works on Linux and always has — `link/extern_import` binds six
libc symbols through `DT_NEEDED` and a `GLOB_DAT` slot, and passes in the suite. There was never any
missing linker work. And an `@import` that is **never called** adds neither `PT_INTERP` nor
`DT_NEEDED`: an executable declaring one and not using it comes out freestanding, which was checked
with `readelf` rather than assumed. So the three externs in `os.linux.e` cost nothing for every
program that does not open a library, and a program that does open one needs a loader by definition.
D32's purpose is that a neper binary need not depend on libc, and that is intact; what it cannot
mean is that a call with no syscall behind it must go unimplemented.

`dlopen` and `dlclose` are ordinary source in both variants — `LoadLibraryW`/`FreeLibrary` on
Windows, which spec section 8's own table already assigns to kernel32, and `dlopen`/`dlclose` from
libc on Linux. The name is passed through unchanged, which is what "as in `@import`" says: that
takes `kernel32` and `libc.so.6` alike and adds nothing to either.

`dlsym[F]` is the one that needed the compiler, and less of it than expected. Section 8 bans
manufacturing a callable address and D96 bans integer-to-pointer, so a library cannot turn the
address a lookup returns into something callable — but nothing about *finding* the address needs the
compiler. So each variant supplies an ordinary `dl_lookup(a, l, sym) -> (usize, err)`, and the
checker points `dlsym[F]` at it and overrides the type of the first result. The call, its arguments
and its lowering are all ordinary; the retype is the whole of the intrinsic. `F` must be a function
type, which is section 8's "must be an `extern fn` type", and is the only thing an address may
become.

Doing that found a real code-generation bug that had nothing to do with the loader.
`register_return_type` in `lower.e` decides whether a result comes back in a register or through a
memory slot, and it listed `.Pointer` but not `.Function`. With the first result retyped to a
function, the **caller** computed a return slot while `dl_lookup`, compiled from its own
`(usize, err)` signature, returned in registers. Two sides disagreeing about that read each other's
rubbish — and it looked like success, because the first call's slot was freshly zeroed and an `err`
of zero is `ok`. Only a second call in the same function, reading a dirty slot, showed it, and the
error it produced matched none of the nine `e.os` errors. A function type is an address and belongs
in a register exactly as a pointer does; one line fixes it, and it fixes it for any function that
returns a function pointer, not only this one.

That is the third time this session that a wrong answer arrived as a plausible one — after the
unwidened narrow `extern` return and `munmap` succeeding on an unmapped range. The pattern is worth
the name: check the second call, not the first, whenever a result travels through memory the caller
allocated.

## D129 — `error_message` needs no ambient state, so it is written; `last_error_detail` still does

D109 decided that the platform error-detail exception "is not exercised" and left three
declarations unwritten. This row exercises the part of it that never needed the exception, and
sharpens why the rest still does.

`error_message(a, detail)` takes the code in its argument. It reads no thread state, has no temporal
contract, and is exact whatever failed last — the caller says which code to render. Every reason
D109 gave applies to the *ambient* half and none of them to this one, so the same decision that
withheld it withholds nothing here. `ErrorKind` and `ErrorDetail` follow, since a caller cannot
spell the argument without them.

Both hosts answer from the system rather than from a table, because a table is the one thing that
could not keep in step: the wording is per host, per version and per locale. Windows is
`FormatMessageW` with inserts ignored — a system message may name arguments a caller has none of, and
asking for them without supplying any is how that call fails. Linux is `strerror`, reached the way
the loader is (D128) and costing the same nothing until called. Both strip the trailing period and
newline the system appends: that belongs to a display, not to a message.

`last_error_detail` stays unwritten, and the reason is more specific than D109's "thread-local
storage has no spelling". The two hosts are not in the same position at all:

Windows already keeps this state, per thread, maintained by the operating system. `GetLastError` *is*
the store, so that half needs nothing built and no exception to §15 — the ambient state is the
host's, not neper's.

Linux has no such state. A raw syscall returns `-errno` in its result and sets nothing; `from_errno`
sees the code and drops it, which is the whole of what would have to change. Capturing it needs
somewhere per-thread to put it, and every route to that — thread-local storage, or a table keyed by
`gettid` — needs **module-scope mutable static storage**. Spec section 5 permits one ("`var` at
module scope is mutable static storage"), and the compiler does not implement it: there is no such
declaration anywhere in `src` or `lib/e`, and neither the checker nor lowering has a case for it.
That is a language feature standing between here and the contract, which is a more useful thing to
know than that TLS is unspelled.

So the choice is not between writing it and withholding it, but between writing it on one host and
withholding it on both. This session has twice refused the first — `recursive` watches and
`Stdio.inherit` are `Unsupported` and documented rather than honoured on Windows alone — for the
reason that applies here too: a call that answers on one host and cannot on the other is worse than
one that is honestly absent, because only the absent one is visible to a caller.

`e.os` is therefore 130 of its 131 declarations, and the one missing is missing for a reason with a
named unblocker: module-scope `var` in the compiler, after which the Linux capture is a change to
`from_errno` alone.

## D130 — only what `main` reaches is emitted, and D128 was wrong about what that cost

D128 said an `@import` that is never called adds neither `PT_INTERP` nor `DT_NEEDED`, so naming libc
in `os.linux.e` for the loader would cost nothing until a program opened a library. That was measured
on a *program* declaring an unused extern of its own, and generalised to a *module* whose functions
are all lowered whether or not anything calls them. The generalisation was false. Every Linux binary
that used `e.os` came out dynamically linked against libc — `link/time_calendar`, which has nothing
to do with the loader, among them. The claim in D128 and on the readiness page was wrong from the day
it was written, and this row is the correction.

The fix is the one the mistake pointed at: a function nothing reaches is not emitted. The compiler
lowered every function of every module it touched, so an image carried all of `e.os`, all of `e.mem`
and whatever else it named. Now `main` is the root, the walk follows the two opcodes that name a
function — a call and taking its address, which is the edge set `e.os.thread_create` needs since it
hands an entry point over as a value — and what is not reached is dropped.

The measurements: a Linux binary that only uses `e.os` goes from 221,392 bytes to 8,200, and is
freestanding again — one segment, no interpreter, no `DT_NEEDED`. A binary that actually calls
`os.dlopen` is still dynamic, which it must be. The compiler's own stage-2 image goes from 4,170,240
to 3,930,624 bytes; 5.7% is a modest share because a compiler calls most of what it contains, and the
weight it was carrying was `lib/e` surface it never touches.

Where this had to happen is the whole design, and the first attempt got it wrong. Filtering functions
*while lowering* changes the order they are emitted in as well as the set, and an image linked from
`.em` artifacts must come out byte for byte identical to one compiled from source — an invariant the
suite checks and which is the reason to trust an artifact at all. The artifact path's order is fixed
by the file list, so a source path that reorders can never agree with it. So both paths now do the
same thing: lower or assemble everything in the canonical order, then drop the same functions from
that sequence. Only the set changes, never the order.

That means the rule is written twice, once over NIR and once over artifact metadata, and the two have
to agree. They agree because they use the same edge definition, which `e.em` had already fixed for
its own use: a relocation records a `Call` or a `FunctionAddress` and nothing else names a function.
`link/function_values` compares the two images by hash, so a divergence is a failed run rather than a
subtle difference in something shipped.

What is deliberately not done is dead *module-scope* data and dead generic instances. An instance
exists because the checker made one, which happens when a call is checked rather than when it is
reached, so a module's instances are still over-approximated; nothing measured says that is worth a
second walk yet.

## D131 — a dead function's references die with it, and D130 claimed otherwise before they did

D130 said a Linux binary that opens no library is freestanding again. When it was written that was
true of the code that had been measured and not of the code that was committed, and this row is the
correction.

The first implementation of dead-function elimination filtered while lowering, so a function nobody
called was never lowered and never made a reference. That version is what the 221,392-to-8,200 and
`needed=0` measurements came from. It could not stay: filtering during lowering changes the order
functions are emitted in, and an image linked from `.em` artifacts has to match one compiled from
source byte for byte. So it was redesigned to lower everything and prune afterwards — and the suites
were re-run, but the freestanding property was not re-measured. Pruning after lowering removes the
functions and leaves their references in `function_refs`, which is the list the imports are
enumerated from, so `DT_NEEDED: libc.so.6` came back. A program whose only `e.os` call was `os.exit`
depended on libc, exactly as before, while the row and the readiness page said it did not.

The fix is to prune the reference list too, and it is what makes the property hold rather than be
asserted: a reference no surviving function names is dropped, and the instructions that index one are
renumbered. Measured after the fix rather than before it — a program using `e.os` without the loader
has one `DT_NEEDED` fewer than it has segments to put it in, which is to say none.

Renumbering has an order to it, and getting that wrong is silent. Writing each reference's new index
into the slot it is leaving and compacting in the same pass destroys that mapping as soon as a later
survivor moves onto the slot, so a reference whose slot was reused resolves to a different function.
`link/io_streams` failed and nothing else did, because `e.io`'s adapters are callbacks and taking an
address is the same edge as a call — a wrong callback is a wrong answer where a wrong call would have
been a crash. The indices are now assigned first, every instruction renumbered while the original
slots still hold their own mapping, and only then is the array compacted.

The lesson is narrower than "test more". Three mistakes in this area were caught by fixtures --
`check/constant_operators_valid` on a token scan, `link/function_values` on the artifact divergence,
`link/io_streams` here. The one that shipped wrong was the one property no fixture covers, which was
re-derived by hand and then not re-derived after the design changed under it. A measurement is
evidence about the code that was measured, and a redesign expires it.

## D132 — the error detail is a slot per thread, and says nothing rather than something wrong

`last_error_detail` completes `e.os` at 131 of 131. D109 decided the exception would not be
exercised, for three reasons; two of them have since expired and the third is answered rather than
denied.

It needed a mechanism the language did not have. It does now: module-scope `var` is mutable static
storage, which spec section 5 always allowed and the compiler did not implement until D129 named it
as the blocker and it was built. D129 also observed that Windows needs no storage at all, since
`GetLastError` is per-thread state the host already keeps — but it is stored on both hosts anyway,
because a native code here may be a Win32 error, a socket error or an `NTSTATUS` and only the
classifier that produced one knows which it was.

Correct meant all of it, and all of it is one place per host. Every failing call in each variant
classifies through a single function — `from_errno` on Linux, `from_last_error` on Windows — so the
code is recorded there rather than at forty call sites. That was the objection's weight and it turned
out to be the cheapest part.

What remains is the per-thread guarantee, and this is where the answer is a design rather than a
dismissal. `e.os` may depend on `e.mem` and nothing else, so there are no atomics to claim a slot
with. The table is a slot per thread keyed by the thread's own identifier, and two threads whose
identifiers land on the same slot overwrite each other. A read therefore requires the identifier to
match exactly and answers `Other` with no code when it does not. That is the whole of the guarantee:
**a detail may be absent, and is never another thread's.** An absent detail costs a caller a
diagnostic; a detail belonging to another thread would cost it the truth, and the second is the one
worth refusing. Sixty-four slots, no eviction, marked as a ceiling in both files.

D109's third reason stands unchanged and is not overridden here: H07 is chartered to delete the
temporal contract, and this is written to be deleted — one recording site, one table, one reader.
What it buys until then is the raw platform code behind a `Failed`, which is the precision D109 said
was being given up.

`link/os_dl` asks about a failing syscall rather than a failing `dlopen`, because that is the path
both hosts record on: `dlopen` answers `NotFound` from its own handle check on one of them and never
reaches the classifier, so a detail read after it would belong to whatever failed before. A zero code
fails the fixture, which is what a recording that never happened would produce.

## D133 — the root arena is reserved, and committed a chunk at a time as it is used

Every process a neper compiler produces begins by taking its whole root arena, and on Windows it
took it with `MEM_COMMIT`. Committing charges the commit limit — RAM plus pagefile — whether or not
a page is ever touched, so a program that allocated a few kilobytes was charged the whole arena
before `main` ran, and the arena size is baked into the binary rather than passed at run time. A
suite run is a hundred-odd such processes; each one asked for half a gigabyte it did not use, and
the machine answered by growing the pagefile until the system drive was full. Reserving instead is
what the arena wanted all along: the address space is claimed up front, exactly as before, and the
pages behind it arrive as they are allocated.

Linux needed nothing. An anonymous `mmap` there is already backed only by the pages that are
touched, which is why this was invisible until it was measured on the other host — the same source,
the same arena, and one of the two paying for it.

The growth belongs in the allocator, because that is the one place an arena's offset moves. The two
hosts of that allocator arrived at it differently. `bootstrap/runtime.c` is ordinary C with statics,
so the startup stub names the region it reserved through `neper_mem_root` and the allocator keeps a
watermark. The embedded runtime has nowhere to keep one: it is emitted as bare text with no
writable section and a relocation table that reaches imports and its own labels and nothing else.
So it derives the watermark instead — what is committed is whatever the *old* offset reached,
rounded up to a chunk, which is known from the arena it was handed. No state, and nothing to keep
in step. A reset moves the offset back and the next growth re-commits pages that are already
committed, which Windows allows and answers without work.

The root arena is told apart by its capacity, which the runtime fixes and no other arena has. An
arena over a caller's buffer therefore never reaches the growth, which matters because committing
memory that was never reserved fails, and a spurious failure here would surface as `mem.Exhausted`
on an allocation that had room.

Measured on Windows, peak commit charge: a fixture compile falls from the flat 512 MB every process
paid to 28 MB for the smallest and 96 MB for the largest, and the compiler compiling itself peaks at
388 MB — which agrees with the 384m-fails/400m-succeeds cliff measured independently on Linux, and
is the first time that number has been visible from outside the process at all.

What this replaces is D-less: `--arena` was lowered from 1g to 512m one commit earlier to buy the
same relief by giving up headroom. That trade is no longer necessary — the cap now costs only what
is used, so it can be set by the largest program worth compiling rather than by what the commit
limit will bear.

## D134 — a JSON number is the lexeme it arrived as, and reflection could not carry the codec

`e.fmt.json` turns on one decision, and everything else in the module follows from it: a
`Number` is the validated text that was written, not a value parsed out of it. JSON's grammar
admits numbers no binary float can hold -- an integer past 2^53, an exponent spelling that
meant something to whoever chose it, a negative zero -- and a parser that rounds on the way in
has discarded them before the caller is asked whether that was acceptable. So `parse` borrows
the lexeme from the source, every conversion out of it is a named call that can fail, and the
writers revalidate a `Number` before writing it, because `Number` is a public struct over a
public `str` and a caller can build one by hand.

The conversions are exact rather than convenient. `number_i64` takes `1.5e1` as `15` and
refuses `1.5`, which means the lexeme is decomposed into digits and a power of ten and the
trailing zeros are folded into the exponent before anything is accumulated -- otherwise
`1e22e-10` overflows on the way to a value that fits comfortably. `number_f64` is `e.str`'s
correctly-rounded `parse_f64` and nothing more; the one thing it adds is refusing a result that
came back non-finite, since a JSON number that overflows the format is not a number this can
answer with.

The depth limit reads zero as a default rather than as no limit, which is the opposite of what
`e.path`'s globs decided. The two are not inconsistent: there a zero limit costs the caller
nothing, here it costs them the stack, and a `zero` Options is exactly what a caller writes
without thinking about it.

### What the first consumer of `e.meta` found

This module was chosen to be the first thing outside the fence to use reflection, and the
answer is that reflection does not reach far enough to carry a codec. Six intrinsics take a
type; three of them accept a generic parameter and three do not:

```
meta.type_name[T]  works        meta.kind[T]          check.InvalidType
mem.size_of[T]     works        meta.array_len[T]     check.InvalidType
meta.fields[T]     works        meta.element_type[T]  check.UnknownCallable
```

All six work when the type is written out. `encode[T]` and `decode[T]` dispatch on `kind` and
recurse through `element_type`, so they cannot be written at all until a bound type parameter
is as good as a written one. `meta.kind[T]()` additionally cannot be bound with `let` even for
a concrete type -- it stands only where it is used. D126 said a type-valued answer stands
where a type is written; what is missing is the other half, that a type *parameter* stands
where a type is written.

`reader`/`reader_next_err` and `patch` are unwritten for want of time rather than for want of
a compiler, so the module is `partial` and the fence is 23 of 28.

### Two defects the module found on its way through

A module-scope `const` of type `str` does not type check, with a catch-all diagnostic and no
location. Section 5 says `const` is compile-time evaluated and has no storage, and restricts it
no further; `str` is `[]const u8`, and the checker has no comptime value for a slice even
though a string literal in an expression is placed without difficulty. The writers here use
arithmetic and a local literal instead.

`io.memory_writer` returns a `Writer` it never fills in -- the field is declared, zeroed, and
returned, so the first write jumps through a null pointer. Nothing had called it before. It may
not be fixable as declared: the context would have to point at state the function returns by
value, which is why every other constructor in `e.io` takes a `*State` instead. The fixture
wires its own sink from the pieces the fence does expose.
## D135 — a bounded CSV reader, and the file that ended in a different word than the slice

`e.fmt.csv` is a streaming reader over `io.Reader`, and its two limits are the whole of its
memory model. `field_limit` and `row_limit` are given once, at construction, and buy a byte
buffer and a field table that every record is then parsed into; a `Row` borrows both and is
valid until the next call. Nothing is allocated per record, which is what lets a file larger
than the arena go through an arena that never moves. The alternative -- a row allocated fresh
each time -- would make the reader's cost the size of the file rather than the size of a row,
and an arena has no way to give the earlier rows back.

Zero means the default for both, following `e.fmt.json`'s depth limit and for the same reason:
a caller who has not thought about the bound is asking for a reasonable one, not for none.

The format is read tolerantly and written strictly. Both line endings are accepted whatever the
dialect says, and the dialect decides only what is written. A quote inside an unquoted field is
data, because there is nothing else it can be. A bare CR is data, because this format has no
other reading for a CR that no LF follows. Two things are refused rather than guessed at: a
quoted field the source ends in the middle of, whose terminator was going to say where the
field ends, and a quoted field that closes and then carries on, where whoever wrote it meant
something a reader would have to invent. `header` in the dialect means the first record is
consumed at construction and never handed over -- a caller who wants the header asks for a
dialect that does not claim one.

A `zero` Dialect is refused where it is given rather than where it would first go wrong: its
delimiter and its quote are both zero, and there is no default dialect worth inventing when
`csv()` is one call away.

`encode_rows[T]` and `decode_rows[T]` are blocked exactly as `e.fmt.json`'s codec is (D134):
they dispatch on `meta.kind[T]`, which rejects a bound type parameter. The fence is 10 of 12
and the module is `partial`.

### The defect the first streaming reader found

`io.read` past the end of a slice answered `End`; past the end of a file it answered
`NoProgress`. The same contract, two answers, decided by which source a caller happened to
hold -- so a loop written against `Reader` worked on one and failed on the other, and
`io.read_all` over a file had been wrong since it was written. The host is not at fault: a read
that takes nothing from a non-empty request is how `read(2)` and `ReadFile` both report an end,
on a file, a pipe and a socket alike. `file_read` is the one place that knows the zero came
from a file, so the translation belongs there rather than in a guard per caller. `link/io_streams`
now asks a real file the question it already asked a slice.
## D136 — a reflection question inside a generic is deferred, not answered

A generic function's body is checked twice: `check_function` checks the template once with
`active_arguments = false`, before any instance exists, and `check_instance` checks it again per
instance with the argument bound. In the first pass `comptime_type` resolves `T` to a
`.TypeParameter`, and every `e.meta` question that has to produce a constant then had nothing to
produce: `meta.kind[T]()` and `meta.array_len[T]()` returned `InvalidType`, and
`meta.element_type[T]()` returned it from `derived_from_subject`.

`mem.size_of[T]()` never had the problem, and the reason is the whole of the fix. Its answer is
not known at check time either -- `layout` is built on `check` -- so it records the subject and
lets lowering compute the number. The three that failed were answering in the pass that cannot
answer. So they now do what it does: in the template pass a question whose subject is still a
type parameter keeps its **result type**, so the body around it goes on checking, and its
**value** is filled in when the instance is checked. `derived_from_subject` returns the parameter
as its own answer for the same reason.

The guard is the subject's kind, not a flag. A `.TypeParameter` reaches these two places only in
the template pass -- in an instance `active_argument` has already substituted the bound type --
so the deferral cannot fire where an answer was available.

### What it does and does not reach

Deferral composes through a chain: `meta.element_type[T]()` is accepted as the comptime argument
of another generic, and `link/meta_generic` carries one two deep, so what arrives is the element
of the element. Every answer in that fixture is the instance's own, and they differ across
instantiations -- a placeholder that survived the template pass would make them agree.

Two things it does not reach, both of which are the same missing feature rather than this one:

- A **value** whose type is a deferred parameter cannot be operated on in the template pass.
  `var first: meta.element_type[T]() = zero` is accepted; `u64(first)` after it is not, because
  the conversion is checked against a type that is not known yet.
- A **self-recursive** generic over a type does not terminate. `encode[T]` recursing into
  `encode[meta.element_type[T]()]` is guarded by `if meta.kind[T]() == .Array`, and that branch
  is only removed if the comptime interpreter folds it -- which it does for integers and nothing
  else. An acyclic chain of the same shape is fine; a cycle needs the fold.

So `e.fmt.json`'s `encode[T]`/`decode[T]` and `e.fmt.csv`'s `encode_rows[T]`/`decode_rows[T]`
(D134, D135) are no longer blocked on reflection reaching a type parameter. What they are blocked
on now is a comptime `if` over a non-integer constant, which is the "general comptime interpreter"
row and a separate piece of work.
## D137 — INI has no standard, so every rule here is a choice; two of them shape the rest

`e.fmt.ini` lands at 12 of 14. The format it implements is one this decision defines, because
there is no document to defer to: the fence names sections, `key=value`, `;`/`#` line comments,
quoted values and backslash escapes, and everything past that had to be settled.

**A comment starts a line and nothing else.** `;` and `#` are ordinary bytes anywhere after the
first byte of a trimmed line -- inside an unquoted value and after a closing quote alike. The
alternative, a trailing comment, means a value silently loses everything past a `;` that someone
meant as data, and no spelling of that value reads back the same under both rules. The fence says
line comments; this is what line comments are when the word is taken literally.

**`case_sensitive: false` folds the name as it is stored, rather than loosening a comparison made
later.** `get` takes no options and a `Document` carries none, so identity has to be a property of
what was stored: after folding, two names differing only in case are the same bytes, duplicate
detection is plain equality, and `get` needs no rule of its own. What a caller gives up is the
spelling, which `write` then emits folded -- honestly, since they asked for the distinction not to
matter. A value is not a name and is never touched.

Around those: an entry before any header belongs to the empty section, which is where `write` puts
one back. An unknown escape is `Invalid` rather than a byte passed through, because `\n` in a path
that means a newline on one reader and two characters on the next is worse than a refusal. A value
is quoted on the way out only when leaving it bare would not read back as itself -- an edge space,
an ending, a quote, a leading `;`/`#`/`[`, or nothing at all -- so the source's own quoting does not
survive, only its value. `TooLarge` belongs to the streaming reader, which holds a line and a table
of what it has seen; `parse` holds the source already and needs neither bound.

`encode[T]` and `decode[T]` are blocked, and by now the blocker has a name. D136 let a reflection
question stand inside a generic, which was necessary and is not sufficient: in an unrolled `for`
over `meta.fields[T]()`, **both arms of `if meta.kind[f.ty]() == .Int` are checked in every
iteration**, so the arm that cannot type for this field's type still has to. A codec over a struct
whose fields differ in kind therefore cannot be written until the comptime interpreter folds a
branch on a non-integer constant. That is the same missing piece `e.fmt.json`'s `encode`/`decode`
(D134) and `e.fmt.csv`'s `encode_rows`/`decode_rows` (D135) wait on -- one gap, three modules,
six declarations.
## D138 — a branch a `meta` question settles has one arm, and the other is not code

An `if` whose condition is decided before the program runs is folded: the arm that is not taken
is neither checked nor emitted. Only one shape of condition qualifies -- a comparison with a
`meta.kind` or `meta.array_len` question on one side and a constant on the other -- and that
narrowness is the point. Nothing an ordinary program writes can be folded by accident, so no arm
a reader expects to be checked stops being checked.

This is what the codecs were waiting on, and the reason is the same in both places they were
stuck. An unrolled `for` over `meta.fields[T]()` gives a body per field, and the bodies differ
only in what `f.ty` is; but until now every arm of an `if` inside that body had to type check for
every field, so `usize(slot)` in the integer arm had to be valid for the iteration whose field is
a `str`. A codec is exactly a walk whose arms are per kind, so a codec could not be written. The
same fold gives a recursive generic its base case: `depth[T]` recursing into
`depth[meta.element_type[T]()]` used to instantiate forever, because the guard arm that would
have stopped it was still live at the point where the element is no longer an array.

Both passes ask the question, and neither remembers the answer. `check_condition_statement` and
`lower_if` call `comptime_condition` on the same tree with the same comptime bindings in place;
asking twice is what keeps them from drifting, where a decision recorded by one and read by the
other would have to survive `check_instance` re-parsing the module into a fresh tree.

A folded condition is still an expression and still checks like one. `meta.array_len[T]()` where
`T` is not an array is an error whatever arm it guards -- only the arm not chosen is excused, not
the question. And a question whose subject is still a type parameter never settles: a template
body folds nothing (D136), which is why `MetaInfo` had to carry whether its value was an answer
or a placeholder.

The row this moves is "general comptime interpreter", from 0.25 to 0.4. What is still missing is
an `if` over an arbitrary compile-time expression, which wants an interpreter this compiler does
not have. What is no longer missing is the six declarations of D134, D135 and D137 --
`e.fmt.json`, `e.fmt.csv` and `e.fmt.ini` can each be given the codec their fence declares.
## D139 — `f.ty(x)` is a conversion, and with it the three codecs are written

A call whose callee is a comptime-bound field type is a conversion, the same one a written
`u8(x)` is. The checker recognised a conversion only when the callee was a `NameExpr` naming a
scalar type; a `FieldExpr` went looking for a function and answered `UnknownCallable`. Now, when
the receiver is a binding's `.ty` and that type is an integer or a float, the call is a cast.
`comptime_binding_base` says yes only to an actual comptime binding, so an ordinary
`module.function(x)` is untouched.

It is a small rule with one purpose: **every parser answers in one width and every field has its
own.** A walk over `meta.fields[T]()` reads text, and `str.parse_i64` gives an `i64` whatever the
field is; without a conversion whose target is the field's own type, the value has nowhere to go.
D138 made the arms of such a walk possible and this makes them useful.

### The three codecs

`e.fmt.ini` is complete at 14 of 14, `e.fmt.csv` at 12 of 12, `e.fmt.json` at 25 of 28 --
`reader`/`reader_next_err` and `patch` remain, unwritten rather than blocked. All three share a
shape, because all three are the same problem:

- A struct is the flat thing the format already has: an object for JSON, a row for CSV, the
  empty section for INI. Nesting is a struct inside a struct, which is the recursion none of
  them can do, so a field that is not a number, a bool or a `str` is `Invalid` rather than
  quietly skipped.
- A member, column or key the source does not carry **leaves its field as it was**. A partial
  document is the normal case, and a decoder that insisted on every name would make adding a
  field to a program break every file already written for it.
- An integer is read through `parse_i64` or `parse_u64` according to whether its text begins
  with a minus, so a `u64` past the signed maximum and a negative are both exact. JSON's fence
  requires this in so many words -- a typed integer never takes a floating-point detour -- and
  the other two follow it because the reason is the same.
- **Signedness is not a question reflection answers, and the value is**, so writing asks the
  value: `if slot < 0` picks `push_i64` over `push_u64`, and for an unsigned field the test is
  simply never true.
- Rendering is `e.str` over `mem.arena_from` on a stack buffer. `encode` is given no arena and
  needs none -- nothing it builds outlives the field it was built for -- and no module grows
  number formatting of its own.

CSV matches columns by **position**, not by name, because that is what a delimited file is. A
header is written when the dialect claims one and never read back for meaning: `reader` has
already consumed it by the time a row arrives.

### What the fixtures found

`decode_rows` kept a `str` field borrowing the reader's row buffer, which the next row overwrites
-- the reader's documented contract, and the decoder was the first caller to outlive a row. A
`str` field is now copied into the arena; everything else a field holds is a value and travels by
itself. The fixture caught it because it compares the field's contents and not just the row
count, which is the difference between a test and a tally.
## D140 — `e.fmt.json` complete: the stream, and the patch that copies before it changes anything

28 of 28. Two pieces were left, and each turned on one decision.

### The streaming reader

`parse` and `reader` read the same grammar; what differs is that a stream has no source to borrow
from. `parse_string` can hand back a span of the document when a string carries no escape, and a
reader cannot -- the bytes are gone from the stream once read. So every string and every number
lexeme is decoded into **one buffer the reader owns**, and an event is good until the next call
and no further. That is the fence's rule, and it is also why nothing here allocates per event: the
document may be larger than memory, and a reader that kept a piece of every event would not be.

A caller sees the shape rather than the value: `BeginObject`, a `Key`, whatever that key's value
turns out to be, `EndObject`. The depth limit and the duplicate-key rule belong here too -- a
stream is where an unbounded document is most likely to arrive from -- so a level's keys are
remembered while its object is open and the whole run is dropped when it closes.

### Patch

`patch` copies `root` once, wholly, strings and number lexemes included, and every operation
afterwards rebuilds only the spine down to what it changes. Sharing the untouched branches is
sound because nothing in the new tree is ever written through again, and copying first is what
makes the result arena-owned and `root` unreachable from it. A failure resets the arena to the
mark it took on entry, so a patch that does not apply leaves nothing behind.

**`test` compares numbers as mathematics, not as `f64`.** This is the module's founding decision
arriving where it matters most: a `Number` is the lexeme, so `1.0`, `1` and `1e0` are one number
written three ways and must compare equal, while `9007199254740993` and `9007199254740992` are two
numbers that `f64` cannot tell apart and must not. Each lexeme is reduced to a sign, a run of
significant digits and a power of ten, and the three are compared. Zero is zero however it is
spelled, `-0` included, even though the module keeps those apart as lexemes.

An object compares by membership rather than by order, because order is not what an object means
to a test -- though `parse` and `write` preserve it, because order is what a *document* means.

The explicit failures are the ones the fence names: a missing target, an array index past the end,
`-` anywhere but an `add`, a pointer that does not begin with `/`, an operation the standard does
not define, one missing the member it needs, more operations than allowed, duplicate keys anywhere
in the input, and a `move` whose `from` is a prefix of its `path` -- which would build a tree that
contains itself.

With this the M2 format set is finished: `e.fmt.json` at 28 of 28, `e.fmt.csv` at 12 of 12,
`e.fmt.ini` at 14 of 14 (D134, D135, D137, D139).
## D141 — `e.proc` reads both pipes at once, and the spawn path that never marked a handle inheritable

`e.proc` lands at 12 of 14. `run` and `RunOptions` wait on `e.cancel`, which the plan defers to
M2.5: a `Control` is what bounds the running work, and there is no writing `run` without one.
`Outcome` and `RunResult` are written, because they are what `run` will answer with and nothing
in them waits on anything.

### The one thing this module adds

Everything else is `e.os` in the shape a caller wants -- a program and its arguments rather than
an argv, three streams rather than a `Stdio`, and the child's ends of `spawn_piped`'s pipes closed
on the side that is not the caller's. What `e.os` does not have is the second reader. A child that
writes to both of its streams fills one pipe while the parent is blocked on the other, and then
neither moves. `output` drains stderr on a thread and stdout on the caller's, which is the only
way two pipes are read at once without a poller that both hosts have for pipes -- Windows does
not. The thread reads into a buffer that already exists and calls nothing that allocates, which
is what lets two readers share one arena that neither touches.

A limit is exact: a stream of exactly `limit` bytes is allowed, one more is `TooLarge`, and the
child is ended at that byte rather than read to exhaustion. A program producing more than it was
allowed is not one to wait on, and one that never stops would otherwise never let `output` return.
Whatever happened, the child is reaped before `output` returns -- a process left behind is worse
than any error.

A program that does not exist answers differently on the two hosts and `e.os` chose not to hide
it: Windows refuses at `CreateProcess`, so it is the spawn's error; Linux forks first and the
`execve` fails in the child, which exits 127 -- there is nothing else to report it to. What both
promise is that it is never a success with a status of zero, and that is what the fixture pins.

### The defect the first user of `spawn_with_options` found

A pipe handed to `os.spawn_with_options` on Windows arrived in the child as nothing, and the
child's first write to it failed. The `spawn` intrinsic, written in assembly, has always called
`SetHandleInformation` on each standard handle before `CreateProcess`; the source path written
later did not, and `pipe` makes its ends non-inheritable on purpose so that a pipe never leaks into
an unrelated child. Every earlier fixture went through the intrinsic, so nothing had noticed.
`start_process` now marks the three streams and everything `Stdio.inherit` names, which is what
the fence said it did, and `link/os_process` hands a pipe through that path and reads the word
the child says into it. Without the fix that check fails at 54; the probe that found it took
three wrong turns first, because a debug edit that does not compile leaves the old binary to
answer.
## D142 — `e.thread` and `e.test` complete, and the float `eq` rule 4 always listed

Two five-declaration modules, both at `surface:"source"` -- the first modules since `e.str` to
declare exactly their fence and nothing more.

**`e.thread`** is `e.os`'s three intrinsics with one convenience, a stack that may be left to
the module, and one name: `Thread` is `os.Thread` by alias, so a handle from either module is
the other's, and `link/thread_spawn` joins one spawned here over there and the other way round.
Zero means `DEFAULT_STACK` rather than a thread with nowhere to run, which is the reading of
zero every other bound in `lib/e` has. The generic `spawn[Ctx]` wraps `os.thread_create[Ctx]`
without ceremony, which D136's deferral is what allows: the intrinsic's own checking sees a type
parameter in the template pass and lets it stand.

**`e.test`** answers `ok` or `Failed` and nothing else. The fence says discovery, isolation and
reporting belong to `neper test`, and its dependency list enforces it -- `e.math`, `e.meta` and
`e.str` produce no output, so nothing here can print. The message is what `neper test` will
show once the trap protocol carries it (spec 11); until then it is accepted and the error is the
whole report. `eq[T]` is `T.eq`, the protocol, not `==`, the operator: section 6 keeps `==` to
the scalars and rule 4 supplies `eq` for the rest, and a struct has no fallback at all -- it
says what equal means, or it cannot be compared, which the fixture shows by declaring one.

### The gap the fixture found

Rule 4 has always listed the floats among the types the compiler supplies `eq` for, with a rule
of its own: "container float equality treats all NaNs equal and both zeros equal". The compiler
supplied nothing, and `test.eq[f64]` was the first call to ask. It is now `a == b || (a != a &&
b != b)` -- `==` already makes the two zeros one, and the pair of self-comparisons is what only
a NaN fails. The row was scored complete and was not; it is complete now, and `link/test_assert`
pins the three cases the rule names.

`near` is where IEEE's answer shows instead: a NaN is near nothing, itself included, because
the comparisons say so on their own and no rule overrides them there.
## D143 — `e.data.map` is open addressing over three parallel arrays, and a binding may wait for its protocol

`e.data.map` lands at 20 of 20, `partial` only because the table behind `state: *void` has to be
a type and the fence does not name one -- the same reason `e.io` named `BufferState` in its
fence and this one could not.

**Open addressing with linear probing, over three parallel arrays.** Keys, values and one mark
byte per slot, so a probe reads marks first and touches a key only where a mark says one is
there. Capacity is a power of two; the load stays under three quarters counting the slots a
removal left behind as well as the live ones, because a table whose dead slots went uncounted
would probe longer and longer while its `len` stayed small. A removal leaves a dead mark rather
than an empty one -- a probe that stopped at the hole would never reach whatever was placed
past it while the hole was full -- and an insertion reuses the first dead slot it passed, so the
hole nearest a key's home is the one filled and no later probe gets longer for it. Rehashing
copies only the live entries, which is how a table that has churned gets its probe lengths back.

Growth takes a fresh table from the arena and abandons the old one, since an arena gives
nothing back; `reserve` up front is what avoids leaving a trail, and a reclaiming allocator is
the upgrade. A key that is already there keeps its slot under `put`, so iteration order does
not change under updates. `Set[K]` is `Map[K, bool]` with the value left out of the surface,
exactly as the fence has it.

Three `ponytail:` comments in `e.fmt.csv`, `e.fmt.ini` and `e.fmt.json` name this module as
the upgrade for their linear duplicate-key scans. It exists now; those scans are unchanged,
because each is bounded and none has been measured to matter.

### The compiler gap

`let digest: u64 = K.hash(key)` failed to check inside a generic, while `ret K.hash(key)` and
`d = K.hash(key)` both passed. The call-initialiser branch of `check_binding` reads the
callee's result count, and a protocol call whose receiver is still a type parameter has no
callee yet -- the count was zero, so the binding was a `TypeMismatch` before the deferral in
`check_expr` was ever consulted. A binding initialised by a pending protocol call now follows
its declared type, the way an expression of it already did. The map's probe is the first code
to bind a hash rather than return or assign it.
## D144 — `e.bytes` needs the foundation layer, and one generic `load` needs `size_of` to fold

`e.bytes` lands at 35 of 35, `partial` for its alphabet and digit helpers. The plan listed it
with no dependencies, and that could not be written: `load[T]` reinterprets bytes as a `T`, which
takes the size of `T` and whether it is a float, and those are `mem.size_of` and `meta.kind`.
Both are layer 0; `e.bytes` is layer 1; the layer rule allows exactly this. The plan now says
`["e.mem", "e.meta"]`, which is the first revision to a module's dependencies since the plan was
frozen, and is recorded here as such.

### One `load` for every width

The bytes are gathered into a `u64` in the order the endianness names, and the `u64` becomes a
`T` by conversion for an integer and by a bit-for-bit pun for a float. The pun is the difficulty:
`bitcast[T]` from a `u32` is right for `f32` and wrong for `f64`, so the generic body holds both
and the arm for the other width has to be *gone*, not merely not taken -- a bitcast of the wrong
width is refused at check time. D138 folded a branch on `meta.kind`; this folds one on
`mem.size_of` when the subject is a scalar, whose size the checker knows without layout. An
aggregate's size is still lowering's to compute, and a branch on it does not fold.

Three more sites were answering in the template pass rather than deferring, each found by the
first generic to need it and each fixed the way D136 prescribes:

- `T(bits)`, a conversion to a bare type parameter, was `UnknownCallable`. It is a conversion the
  same way `u8(x)` is and `f.ty(x)` became in D139, to whatever `T` is bound to; in the template
  pass it stands as a conversion to a type not yet known.
- `u64(v)` where `v` is of a type parameter's type was a `TypeMismatch`, because the checker asked
  whether the operand was numeric before the instance could say. It asks the instance now.
- `mem.bitcast[T](x)` was refused for a type parameter target, because `punnable_type` had no
  answer for one. The widths are compared in lowering, which only ever sees an instance, so a
  type parameter is punnable until the instance says otherwise.

### The encodings

Base64 and base32 are RFC 4648's, both alphabets each, padded or not, and a decoder accepts
either since padding is stripped before anything is measured. Base85 is ASCII85 without its
frame and Z85; both go through one digit pair, which is what keeps them one codec with two
spellings. Z85 is defined only on whole groups and says so rather than padding. ASCII85's `z` is
accepted on the way in and never written on the way out, and it cost the fixture's one failure:
a length rule that measured the input in fives before it knew the `z`s were not groups.

`link/bytes_codec` checks each encoder against the vectors its RFC prints before round-tripping
it, because an encoder and a decoder that agree with each other and with nothing else would pass
the round trip alone; then every byte value goes through each.
## D145 — `e.data.iter` is `I.next` through a type parameter, and the argument block is claimed before it is filled

`e.data.iter` lands at 46 of 46 and `surface:"source"`: forty-six declarations, no helpers,
every adapter lazy and allocating nothing, every fold taking its source by pointer. An adapter
holds its source by value and does its work in `_next`, so a `Filter` over a `Map` over a list's
`Iter` is one value that pulls through all three. The `try_` family is the same over `next_err`,
and a source or callback that fails ends the adapter: the error once, where it happened, and no
item and `ok` on every pull after. `try_collect` past its limit answers `mem.Exhausted`, the one
error the fence's dependencies reach that says what happened.

Writing it took three compiler changes. The first two are the iterator protocol reaching a type
parameter at all; the third is a bug in generic instantiation that nothing had written the shape
of before.

**`I.next(&it)` through a type parameter.** Rule 3 requires a protocol's first parameter to be
the receiver by value, and `next` never is: an iterator advances, so its receiver is a pointer to
one. The `for` statement had always known this and `check_protocol_call` had not. And a generic
type's `_next` is generic with it -- `iter_next[T]` for `Iter[T]` -- which the protocol call
refused as unsupported. The receiver instance already holds the arguments it was made with, and
they bind the function's parameters in order, which is the one convention every `<t>_next` in
`lib/e` follows; so `Iter[i64].next` is `iter_next[i64]`, instantiated from the receiver.

**A pending protocol in a tuple binding.** `let (value, more) = I.next(it)` in a template body
has no result count to check against, since the protocol has no callee until the instance binds
it. Each name is bound to a type not yet known and the count is checked when it is -- D143's rule,
which had covered only the single binding.

**The argument block.** `collect_generic_arguments` claimed its first slot and then appended one
argument at a time as it read them. Reading an argument may instantiate a nested generic --
`Pair[Wrap[i64], u8]` -- whose own arguments go through the same function and were appended
first, into the slots the outer call was about to fill. The outer then read `[i64, Wrap[i64]]`
where `[Wrap[i64], u8]` was written, and `Filter[Map[Iter[i64], i64, i64], i64]` as an
annotation named a type with `I = i64`. It was never noticed because no fixture had written a
nested instance in a type argument -- every generic container so far held a type parameter
there, never a concrete instance. The block is now claimed whole before any argument is read.
The function-call path had always done this; only the aggregate path had not.

The bug was found by making `type_equal` structural for instances first, which did not fix it
and thereby proved the two types were not equal by argument -- and then by a temporary
diagnostic that named which argument differed and how. The structural equality stays: an
instance is its template and its arguments, not its index, whichever path made it.
## D146 — `e.math`'s exact set: `sqrt` is the instruction, the rest is bits, and what is not written is said

`e.math` lands at 11 of 24. Section 11 splits the fence in two -- an exact set, whose answer is
one value on every target, and an approximate set, within a stated bound -- and what lands is
the exact set less `fma`, plus `rsqrt`.

**`sqrt` is the one intrinsic.** A correctly rounded square root is the hardware's to give and
no software's to approximate, so `math.sqrt[F](x)` is a NIR opcode of its own, `Sqrt`, selected
as `sqrtss`/`sqrtsd` -- SSE2, so it is on every x64 this compiler targets. Everything else exact
is bits and comparisons: `abs` and `copysign` mask the sign, `min` and `max` are IEEE 754-2019
`minimum` and `maximum` with a NaN winning and `-0` below `+0`, and the four rounders fold the
value through an `i64` where one fits and answer the value itself where one does not, since a
float past 2^52 has no fraction left to round. `round` is ties to even, as SPIR-V's `RoundEven`
and every CPU's round-to-nearest are, and the tie is tested exactly because `x - trunc(x)` is
exact below the threshold. The sign of a zero result is the input's, which `i64(-0.5)` would
have lost. `rsqrt` is `1 / sqrt(x)`: two correctly rounded operations, within 1 ULP, inside the
2 ULP section 11 allows, and that bound is recorded in `lib/e/math.e` as the section asks.

The plan listed the module with no dependencies; the sign masks are `mem.bitcast`, which is
layer 0 as this module is, and the plan now says `["e.mem"]` (D144's precedent).

### What is not written, and why it is not sketched

`fma` is one rounding on every target. The baseline this compiler emits for is SSE2, which has
no fused instruction, and a software fused multiply-add is exact arithmetic on the significands
that must be verified against known answers. It waits either for a CPU level with `vfmadd` or
for that verification, and a version that rounds twice would be worse than none: a caller who
reaches for `fma` is reaching for the one rounding.

The thirteen transcendentals are within 2 ULP over the whole domain. For `sin`, `cos` and `tan`
that means an exact reduction of arguments past 2^60; for `pow` it means the special-value
table section 11 fixes, entry by entry. That is a libm, and section 11 asks for its per-function
bounds to be recorded in the source when it is implemented -- which is the right shape for
it: written once, with its bounds, not approximated now and tightened later.
## D147 — `e.math` complete: `fma` in integer arithmetic, the transcendentals from fdlibm, and every bound measured

`e.math` lands at 24 of 24. D146 said what was not written and why it was not sketched; this is
that work done, and the reasons held.

**`fma` is computed the way the instruction computes it.** The product of the two significands
is exact -- 106 bits -- the addend is aligned to it, the sum is taken exactly, and the result is
rounded once. A 256-bit accumulator holds the pair; an operand so far below the other that it
cannot reach the rounding position is folded into the lowest bit instead, the jam bit, which is
all a rounding needs to know about it and which carries the direction through a subtraction.
Every special value is settled before the arithmetic. `link/math_exact` checks sixty vectors
against the exact rational `a * b + c` rounded once, which Python's `Fraction` computes with no
float in the way -- including the twelve where `a * b + c` in two roundings disagrees.

**The transcendentals are fdlibm's algorithms** as FreeBSD's msun carries them, over `f64`, with
`f32` going through `f64` and rounding once more. Every constant is the published decimal stored
as its bits. The one piece not ported is the large-argument reduction for `sin`, `cos` and
`tan`: Payne-Hanek written here over 1280 bits of 2/pi, on the observation that for `m * 2^e`
the only bits of 2/pi that can reach the result are the 256 around bit `e`, so `m` times that
window modulo 2^256 holds the quotient's low two bits and 253 bits of the fraction -- more than
the 61 bits the worst double cancels.

**Every bound is measured, not derived.** Section 11 asks for per-function bounds to be
recorded in the source; they are, and the four `link/math_*` fixtures are what keeps them true:
880 inputs chosen to reach every reduction path and every special value, each compared against
mpmath at 200 bits rounded once. Every function is within 1 ULP of the correctly rounded result
at every point, `log2` and `log10` at 0, so within 1.5 ULP of the true value, inside the 2 the
section allows. Where mpmath has no answer -- the signed zeros and infinite quadrants of
`atan2`, the signs and zeros of `pow` -- the IEEE answer is written in.

### What the measurement caught

Seven defects, none of them in an algorithm: a `2^-1000` constant that was `1e-300`; the
half-log-2 reduction threshold as `0x3FC62E42` where fdlibm has `0x3FD62E42`, which reduced
inputs in `[0.17, 0.35]` by a whole log of two; `atan2`'s `x == 1` shortcut testing `|x|`, so
`x = -1` took it; the fraction mask of the reduction masking bit 51 of a limb where bit 61 was
meant; and four fold thresholds mis-converted from hex by hand, one of them "corrected" from a
right value to a wrong one. Every one showed as a distance of hundreds or thousands of ULP at
some input and nowhere else, which is the argument for the fixtures being what they are.

Two limits met on the way: a fixture of 880 checks in one function crossed a per-module
lowering capacity around 450, so there are four fixtures rather than one; and the scratch
directory holding the generators was wiped mid-session, so the vectors live in the fixtures and
their provenance in their headers. A generator in `scripts/` would be the tidier arrangement.
## D148 — `Vec[T, N]` and `Mask[T, N]` are seeded aggregates, and `e.simd` is source over their lanes

`e.simd` lands at 27 of 28, and the two vector types exist. The shape is the smallest one
that is correct, and it is chosen so that the register-class work later changes nothing
written in the library.

**The types are builtins the way `Atomic[T]` is (D-series precedent in `check.e`):** seeded
into `e.simd` when that module is in the graph, each a generic struct of one field --
`lanes: [N]T` for `Vec`, `lanes: [N]bool` for `Mask` -- with `T: type` and `N: usize` as
its comptime parameters. That gives section 4's width for free, `= zero` for free, and the
alignment-equals-width rule is one line in `layout.e`. The closed `(T, N)` table is
checked where the type is written, in both spellings (a type node, and a comptime argument
slot), with its own diagnostic. `meta.kind` answers `.Vec` for both, and `element_type`
and `array_len` answer the lane type and count, which is what the surface's dependent
names `T`, `N` and `M` are: `fn splat[V: type](x: meta.element_type[V]()) -> V`.

**Two pieces of the checker were needed for that spelling to be writable, and both are
general, not vector-specific.** First, `meta.element_type[V]()` in a parameter or return
position of a generic is a placeholder of its own -- the same `TypeParameter` with a mark --
that `substitute_type` answers once `V` is bound; before, the template's placeholder was
`V` itself, so the instance's parameter became the vector rather than its lane. Second,
`meta.array_len[X]()` written where a length is -- in `Mask[meta.element_type[V](),
meta.array_len[V]()]` -- is a constant-expression kind (`ArrayLen`) holding `X`, evaluated
after substitution in the aggregate, function and module evaluators. With those,
`Mask[T, N]` for a `V` is spelled entirely in the library, and `meta.element_type[W]()(x)`
is accepted as the conversion `simd.convert` needs.

**Every operation is a scalar loop over `lanes`.** Section 4 says every width compiles on
every target and a width the hardware lacks is split; N lanes of one is the degenerate
split, and the instruction count is the only thing the register class will change. The
pairwise reduction tree is in place (`2i >= i`); `reduce_min`/`max` are `e.math`'s IEEE
minimum/maximum on float lanes; integer `reduce_add` is `+%`; `convert` is the scalar
conversion per lane; `fma` is `math.fma` per lane; `pdep`/`pext` are the bit loops
section 4 prescribes for targets without the instruction.

### What is not in this increment

`shuffle`: its `IDX: [N]u8` is a comptime array parameter, a kind the generic machinery
does not have. The lane-wise operators `+ - * /`, the mask operators, the `Vec[T, N]{ }`
literal and `v[i]`: all the checker's, none the module's, and each a bounded increment
over the same one-field representation. The mask register-only rule: a `Mask` is a struct
here, so `&m` and a `Mask` field compile where section 4 says they must not. The `align`
check of the aligned loads. And the readiness row stays a fraction until the register
class exists.

### What the fixture caught

`math.fma`, sixty vectors old, was wrong whenever the exact result had fewer significant
bits than the format and was still normal: the kept bits were shifted up into place and
the exponent field was computed as though they had not been. `(1 + 2^-23)^2 - (1 + 2^-22)`
is `2^-46`, and came out `2^-23`. D147's random rationals never cancelled that deeply;
`link/math_exact` now carries the case in both widths.
## D149 — an ELF segment starts where the headers end, not on the next page

A static Linux image put its code at file offset 4096 and its data on the page after the code,
so an empty program was 7,780 bytes of which 3,982 were zeros, and hello world 13,120 with 6,138.
The loader never asked for that: a `PT_LOAD` needs its file offset and its address to agree
modulo the page, nothing more. The code now follows the program headers directly, at offset 120
or 176, and its address is still the base plus the offset, so every relocation on the path stays
a file offset. The data area follows the code in the file, rounded up to the strictest
alignment any global asks for, and is mapped one page beyond its offset so it lands on a page of
its own -- the two mappings share a file page and that is allowed; what is not allowed is one
mapping that is both writable and executable, and there is none.

Measured after: empty program 3,804 bytes, hello world 7,048, `module_var` 8,136 (was on two
pages); every link fixture unchanged in behaviour and stage 3 still equal to stage 2. What is
left of an empty program is 120 bytes of headers, 235 of startup and 3,438 of runtime, which is
appended whole whether the program reaches `spawn` and `thread_create` or not -- the next floor,
and a larger job than this one, since the runtime is opaque bytes behind a symbol-offset table.

The Windows image was not padded to speak of -- 345 bytes in 7,168 -- and the dynamic Linux
path (an `@import`) keeps its page-aligned layout, since a program that loads libc is not
counting bytes.
## D150 — the runtime is a prefix, cut after the last function the program reaches

D149 left an empty Linux program at 3,804 bytes, 3,438 of them runtime appended whole; the
Windows one was 7,168 with 5,370 of runtime. Both runtimes are opaque machine code behind a
symbol-offset table, so the dead-function pass stopped at their edge: a program that wrote one
line carried `spawn`, `wait`, three thread calls, the futex pair and xxHash64.

The cheap cut is an ordering. Each runtime's source is now arranged so that a function calls
only what precedes it -- the shared helper first, then the functions from the ones nearly every
program needs to the ones few do, each helper directly before its first caller -- and the
generator records where each function ends. The linker takes the furthest end among the
runtime symbols its relocations name and appends that many bytes. No relocation table, no
per-function chunks; one number. On Windows the floor is the entry and the two procedures it
calls, which every program runs before `main`; the base Linux runtime, which has no source
left to reorder, is still appended whole at 1,441 bytes. The import patch table of the PE
runtime skips the sites that were cut.

The PE import table follows the same rule. The runtime module lists its KERNEL32 imports in
the order the runtime first reaches them, so the imports a prefix of the runtime needs are a
prefix of that list, and the linker declares only as many as the kept bytes reach -- four for
the floor, seven for hello world, twenty-five for a program that reaches everything. The
kept length rides in the NIR builder, which is what every layout helper already receives.

Measured: empty program 3,804 to 1,807 bytes on Linux and 7,168 to 2,048 on Windows; hello
world 7,048 to 5,048 and 10,752 to 6,144. What a program that reaches `os.wait` carries is
`spawn` as well, since the two are neighbours at the tail; that is the ceiling of a prefix,
and a per-function table is the upgrade if a measurement ever asks for it.

Two things found on the way. `link/module_var` was written with D-row 849fa5b and never
wired into either runner, and on Windows it did not link: the PE writer bounded a global's
index against the function references before asking whether the relocation was a global at
all, so a program with more globals than calls was refused. The check moved inside the
branch it belongs to, and the fixture runs on both hosts now. And the base Linux runtime,
1,441 bytes with no source left, is now the largest single thing in an empty program on
either host -- the next floor, and one that needs the source rewritten before it can move.
## D151 — the Linux runtime is one source file again, recovered from its bytes

D150 left 1,441 bytes of Linux runtime that could not be cut because it had no source: the
arena allocator, the errno map and the file calls had been embedded in `link_elf.e` as hex
since the first ELF link (06987db) and reordered never. They were disassembled, given labels
and written down as `runtime_elf_x64.s` alongside what used to be the extension; the result
reassembles to the same 1,441 bytes exactly, which is the proof the recovery is faithful. The
extension's private copy of the allocator, a shorter twin of the base one, is gone -- both
callers use the one that also checks for a null base.

So there is one runtime source and one generated module, `runtime_elf_x64.e`, ordered as
D150 prescribes, and the linker cuts it after the last function reached on both the static
and the dynamic path. A program that reaches nothing gets no runtime at all: an empty program
is 120 bytes of headers, 235 of startup and its `ret` -- 366 bytes. Hello world is 3,984, of
which the runtime is `np_error` through `neper_os_write`, 377 bytes.

The linker's self-test used to know the runtime followed the code by checking the first byte
after it; that byte is now whatever comes next, and the check is gone with the assumption.

Windows is unchanged at 2,048 and 6,144. Its floor is the entry's 941 bytes -- command-line
parsing and the arena -- and the four imports those need; the Linux startup does the same
work in 235 bytes because a process there begins with `argc` and `argv` on the stack, where a
Windows one begins with a call to `GetCommandLineW` and a UTF-16 string to split and convert.
## D152 — the Windows floor stays where it is: a smaller one is a Meterpreter stager to Defender

The Windows entry parses the command line before `main` runs, for the `args` a `main` may
declare, and that parser with its two callees is 941 of the 2,048 bytes an empty program
carries. Moving it out was straightforward and was done: the parser became a procedure the
entry calls only when a byte the linker writes says `main` declares `args`, `neper_os_args`
called the same procedure for everyone else, and the NIR parameter count travelled through
the `.em` code record (format version 3) so a link from artifacts knew the same. An empty
program came out at 1,536 bytes with two imports, `VirtualAlloc` and `ExitProcess`.

Windows Defender quarantined it on first run as `Trojan:Win64/Meterpreter.AMTB`. That is
the shape of a stager -- a few hundred bytes that allocate memory and hand control to it --
and a heuristic cannot tell `fn main() -> err { ret ok }` from one. The same program
declaring `args`, 2,560 bytes with the parser and four imports, ran untouched; so did every
image of the previous layout, which always carried the parser.

So the change is reverted whole, format version included, and this row is what remains of
it. The Windows floor is 2,048 bytes and the parser is part of it on purpose: a compiler
whose smallest program is quarantined has not made a smaller program. Linux has no such
reader and keeps its 366 bytes.
## D153 — `main`'s `args` are checked on both link paths, and the sizes as they stand

`link/main_args` passes two arguments, one with a space, to a `main` that declares `args`,
linked once from source and once from `.em` artifacts through `link-em`, on both hosts. No
fixture had linked a `main` with parameters from artifacts before; the path worked, and the
fixture is what says so from now on.

Two things it found. `link-em` takes the root artifact first and nothing says so: `find_main`
looks for `main` in module 0, which is whichever artifact was named first, and any other
order fails with `InvalidExecutable` and no message. Every runner already named the root
first, so the contract was kept by habit; it is written down here, and the fixture's comment,
until the linker learns to say it. And an artifact carries no module-scope `var`, so a program
that reaches `e.os` -- whose per-target variants hold three -- does not link from `.em` files
at all; the fixture stays on `e.mem` for that reason, and the gap is the next thing the
artifact format owes.

The sizes at this row, freestanding on Linux and importing KERNEL32 alone on Windows:

| program | Linux | Windows |
|---|---|---|
| `fn main() -> err { ret ok }` | 366 | 2,048 |
| `fn main(a: *mem.Arena) -> err { ret ok }` | 395 | 2,048 |
| `fn main(a: *mem.Arena, args: []str) -> err { ret ok }` | 409 | 2,048 |
| `io.print("Hello, world!
")` | 3,984 | 6,144 |

Linux is what D149 to D151 left: headers, startup and the code, plus 377 bytes of runtime
for the one that writes. Windows is its 512-byte file alignment over a 941-byte entry that
parses the command line for everyone (D152 is why it stays), and hello world's `.idata`
carries `e.io`'s buffer as well as seven imports.
## D154 — the `.em` format carries a module's `var`s, so a program that reaches one links from artifacts

D153 found that a compiled-module artifact recorded no module-scope `var`, so a program
reaching one -- anything using `e.os`, whose per-target variants hold three -- could be built
from source but not linked from `.em` files. The artifact format is **version 3**: a seventh
section lists each `var` the module declares (name, size, alignment, whether an initial value
was written and its bits), a code relocation carries a kind saying whether it names a function
or a `var`, and the canonical NIR writes a `GlobalAddress` by module and name rather than by
its program-wide index. `em_link` fills the builder's globals from those sections in artifact
order -- the same order the module index already uses -- and resolves a global relocation
against them, so `link_pe` and `link_elf` lay a `var` out exactly as they do on the source
path. `link/global_artifact` links a module of five `var`s from its artifact and checks the
image is byte-identical to the one compiled from source, on both hosts.

`e.os` now links from artifacts too, which is what the row was for; it is verified by hand at
99 seconds. That time is not the `var`s: the reach walk in `em_link` re-derives every
artifact's function list from the bytes on every pass and re-validates each artifact -- a
CRC over the whole file -- inside the nested loops, so a module with hundreds of functions
costs O(passes * functions^2 * size). No artifact-link fixture had pulled a module that big
before, so the cost was there and unmeasured. Caching each artifact's function table once is
the fix; the fixture stays on an import-free module so the suite does not pay the 99 seconds
to prove the `var`s, and the perf is the artifact linker's own next row.
## D155 — the artifact linker reads each module once, not per function and not per error

D154 made a program that reaches a module-scope `var` link from `.em` files, and noted the link
took 99 seconds for one that pulls `e.os`. None of that was the `var`s. Three places re-derived
an artifact from its bytes inside a loop, and every `em.artifact_*` reader runs `validate` first
-- a CRC over the whole file -- so a per-item loop was a per-item CRC.

- The reach walk resolved every call edge of every function on every fixpoint pass, and each
  callee lookup re-parsed a whole module and, through `target_module`, re-validated every
  artifact. It now builds a function table once (one forward pass per artifact, via
  `em.read_code_functions`), caches each artifact's interface module index once, resolves a
  callee to a table position by a scan of its own module's slice, and reaches from `main` by a
  breadth-first walk that visits each function once -- so a module the program never enters is
  never scanned.
- The copy loop content-hashed every function including the ones reachability had already
  dropped; it now hashes only what it keeps.
- `merge_artifact_error_tables` compared error values in an O(errors^2) loop whose every step
  called `em.artifact_error_count`/`artifact_error_at`, each re-validating the artifact and
  re-walking its interface. `e.os` declares many errors, so this was most of the 99 seconds. It
  now reads each table once through `em.read_error_table` and compares in memory.

Two readers also validated a function's name by walking the string table to it, O(index) per
function; the name is checked where it is read, so that walk is gone. Measured, `module_var`
linked from artifacts: 99s to 4s; `os_process`, which pulls `e.os`, `e.proc`, `e.mem` and
`e.atomic`: 81s to 14s. The suite now links `module_var` from artifacts and checks the image is
byte-identical to the source build, so the `e.os`-from-artifacts path D154 could only verify by
hand is a standing test.

What remains is linear scans with no CRC in them -- `resolve_calls` and the module-slice lookup
-- which the source path pays too and which no measurement yet calls for indexing.
## D156 — the artifact linker keeps every reachable function, so D130 holds universally

D155 left one fixture, `link/os_process`, whose artifact-linked image was 792 bytes smaller than
its source build and not byte-identical to it -- the one violation of D130 ("an image linked from
`.em` artifacts is byte-for-byte the image compiled from source"). A controlled bisection settled
it: every feature in isolation (`page_size`, `file_handle`, a `wait_u32` on an atomic, `spawn`,
`pipe`, `spawn_with_options`, the `args`-reading child logic) linked identically both ways; the
divergence needed a program with two functions that compile to the same bytes. The minimal
reproduction is two functions with identical bodies, both reached: source keeps both, the artifact
image had one.

The cause was the artifact linker alone folding functions by content hash -- D36's "the same
concrete instance arrives from several artifacts, share one copy." The whole-program path
(`link_elf`/`link_pe` straight off codegen) folds nothing: it emits every reachable function, a
duplicate instance once per module. So the fold made an artifact image smaller than the source
build whenever two kept functions shared a content hash -- a duplicate cross-module instance, or
two distinct functions that happen to compile alike. Every determinism fixture passed only because
none of them had such a duplicate; `os_process`, reaching `e.os`, `e.atomic` and `e.mem` at once,
did.

D36's fold and D130's identity are in tension, and only the artifact path had the fold, so the
fold was the anomaly: the canonical output is the source build, which shares nothing. The fold is
removed. Both paths now emit every reachable function, a duplicate instance once per module, the
same bytes on both. Measured with it gone: `os_process` 59,024 on both, and `element_cmp`,
`function_values`, `supplied_hash`, `folded_hash`, `generic` and `generic_folding` all
byte-identical source-to-artifact on both hosts. `generic_folding` now asserts that identity where
it only checked the link succeeded before, so the gap that hid this cannot reopen unnoticed.

The cost is that a program with a duplicate cross-module instance carries it once per module in
both builds rather than once overall -- the size the source build always had. Sharing one copy is
still worth doing; it just has to be done on both paths to keep D130, which is a symmetric
optimisation for another day, not a divergence in the linker that has it.
## D157 — the same fold on both link paths: the size win back, D130 kept

D156 removed the artifact linker's content-hash fold because the whole-program path had none, so
sharing one copy of a duplicate function made an artifact image smaller than the source build. That
kept D130 but gave up a real optimisation: a duplicate generic instance, or two functions that
compile alike, was carried once per module in every image.

Now both paths fold, by the same key and in the same order, so they stay byte-identical while
sharing the copy. The artifact linker folds as it did (D36), keyed by the `content_hash` each `.em`
carries. The whole-program path folds in its codegen loop: a function is emitted, its hash is
formed by `em.write_code_hash_input` -- the exact bytes the `.em` hash is taken over, code plus
each relocation's target by name -- and if an earlier function in the same order already has that
hash, the just-emitted bytes and their relocations are rewound and the function points at the
first copy. The order is the one both paths already share (the canonical lowering order the
artifacts also use), so first-occurrence-wins picks the same copy on both. Folding is only for an
executable; an `.em` or `.o` still carries every function, so the fold happens once at the link
that consumes it.

Measured, source and artifact byte-identical on both hosts, and smaller than D156 where a
duplicate existed: `os_process` 59,024 to 58,232, `supplied_hash` 39,620 to 39,114; `element_cmp`,
`function_values`, `folded_hash` and `generic`, which have no duplicate, unchanged. The self-hosted
compiler still reproduces itself byte-for-byte (stage 2 equals stage 3), now with the fold applied
to its own build. `generic_folding` continues to assert the shared-instance image is identical
source-to-artifact -- now with both paths sharing rather than both keeping every copy.
## D158 — the lane-wise operators, lowered over the lanes

Section 4's operator table for vectors is in: on float lanes `+ - * /`, IEEE and one
rounding each; on integer lanes only `+% -% *%`, `& | ^ ~` and `<< >>` by one scalar
count; on a mask `& | ^ ~`. Plain `+ - *` on an integer vector, `/` and `%` anywhere on
one, and every comparison are compile errors, as the section says -- the `simd.cmp_*`
intrinsics are the comparisons.

The checker's part is one table (`vector_operator_legal`) consulted from the three
places a binary or unary operator is typed, with the same deferral a still-generic
vector gets everywhere else: inside a template `V * V` is `V`, and the instance decides.
Lowering's part is D148's representation put to use: both operands are addresses, the
result is a fresh slot of the vector's width, and each lane is one scalar instruction
between a load and a store at the lane's offset -- `lower_vector_binary`, and
`lower_vector_not` for `~`, which on a mask is each lane's `!`. A shift loads its count
once and applies it to every lane.

ponytail: N scalar instructions per operator. The vector register class, when it comes,
selects one instruction for the same NIR shape; nothing in the checker or the library
moves for it. `link/simd_lanes` carries the table on every lane kind, the refusals are
probed by hand, and a generic `a * x + y` over `V` goes through both passes.
## D159 — `Vec[T, N]{ ... }` and `v[i]`: the two spellings, over the same lanes

Section 4's last two spellings on a vector are in: the literal, which is exactly `N`
unnamed items of the lane type in lane order, and `v[i]`, which reads or writes one lane
with an array's bounds check. Both are the one-field representation of D148 read the
obvious way. A vector's address is its lanes' address, so `v[i]` is the array index path
with the length being `N` rather than the array's own; the literal is the array literal's
positional path with the lane as the element. `Mask[T, N]{ true, false, ... }` comes for
free and is not refused. The count mismatch is the array literal's diagnostic; an
out-of-range lane is the array's trap. Inside a generic, `Vec[T, N]{ ... }` and `v[i]`
defer as every other question about `V` does, and the instance settles them.

What remains for vectors is the register class -- one instruction per operator rather
than `N` -- the mask register-only rule, and `shuffle`, which waits on a comptime array
parameter kind.
## D160 — a comptime array parameter, and `shuffle` with it: `e.simd` at 28 of 28

`shuffle[V, IDX: [N]u8]` was the one declaration `e.simd` lacked, because section 9's
comptime array had no parameter kind. It has one now, made the way the comptime `str`
was: the argument is an array literal whose items are integer literals, and what is
bound is its spelling and the array type it wrote. Nothing decodes the spelling until a
body reads the name, where the array is materialised as a slot of constant stores --
`IDX[i]` is then an ordinary indexed read. Two literals that spell the same array
differently are two instances, which costs a duplicate function and nothing else.

The declared length may name an earlier argument -- the library writes
`IDX: [meta.array_len[V]()]u8`, D148's `ArrayLen` constant -- and by the time `IDX` is
bound `V` is, so the count is checked against the substituted length: exactly `N`
items. A comptime array forwards by name through another generic, so a permutation can
be passed down as a whole.

`shuffle` itself is a lane loop: source lane `IDX[i]` from `a`, or from `b` when it is
at or past `N`; an index past `2N` is the array's bounds trap. With it every surface
name of `e.simd` is written. The module stays `partial` because the lane helpers
(`lane_add`, `lane_min`, `lane_max`) are public declarations the fence does not list --
the D121 rule, not a gap in the surface.
## D161 — `e.data.stack`, `e.data.queue` and `e.algo.disjoint_set`; `union` cannot be a function

Three small modules at `surface:"source"`, each exactly its fence. The two adapters are
what D76 asked for: a `Stack[T]` is a `list.List[T]` whose end is the top, a `Queue[T]` is
a `deque.Deque[T]` entered at the back and left at the front, and each iterator walks its
storage without moving it -- LIFO from the top, FIFO from the front. `e.algo.disjoint_set`
is union-find on the caller's two slices, path compression in `find` and union by rank in
the join, `TooLarge` when `count` does not fit a `u32` and `TooSmall` when a slice does not
fit `count`.

**The fence spelled the join `union`, and `union` is a keyword** (section 6's `union` and
`union enum`); a declaration may carry it but no caller can spell `s.union(...)`, so the
surface as written was uncallable. It is `join` now, in `docs/module-apis.md` and in the
source, with the note beside it. The one-line rule for the rest of the plan: a fence name
that is a keyword is a defect in the fence, corrected when the module is written and
recorded here.

`link/data_adapters` carries all three. Two idioms it re-taught: a two-value call is bound
before it is returned (`ret f()` does not forward a pair), and a `main` that ends in
`os.exit` still needs its `ret ok`.
## D162 — `e.algo.stat` and `e.data.slot_map`

`e.algo.stat` is Welford's running mean and second moment, Chan's merge of two
accumulators, and the bivariate form of the same for a least-squares line and Pearson's
`r`; the square roots are `e.math`'s, so the plan's empty dependency list gains `e.math`.
Every question that needs data it does not have -- a variance of nothing, a sample
variance of one, a slope with no spread in `x` -- says `false` rather than dividing.

`e.data.slot_map` is the generational handle map the fence describes, over a `State[T]`
behind the `*void` the way `e.channel` keeps its state: values, generations, a live bit
and a free chain, all caller-funded at `init` and never grown. A removal moves the slot's
generation on and chains it back; at the last generation it retires instead, so no key
is ever issued twice. `clear` moves every live slot on and rebuilds the chain over what
has not retired. The state type and two helpers are public declarations beyond the fence,
so the module is `partial` (D121's rule). `link/stat_slots` drives the generation to its
last value by hand through the state to see a slot retire.
## D163 — `e.data.linked`, and the two generic-substitution defects it exposed

`e.data.linked` is D76's stable-identifier list: nodes in one `list.List[Node[T]]`,
addressed by index, a removed slot never reused, so a `NodeId` is valid exactly while its
node is live and `InvalidNode` ever after; `clear` invalidates every identifier issued
and keeps the storage. It is `partial` for one helper beyond the fence (`allocate`).

Writing it was the first time a generic struct held an instance of another module's
generic over its own parameter (`nodes: list.List[Node[T]]`) and a generic function
instantiated the same shape over *its* parameter. Two checker defects came out:

1. **An instance built over a still-generic instance counted as concrete.** The
   concreteness test looked for a bare parameter among the arguments; `Node[T]` is not
   one, so `list.List[Node[T]]` was instantiated -- and cached -- as if concrete, with
   fields substituted over a parameter that was not bound. `type_still_generic` now
   walks into instances, pointers, slices and arrays, and only a type mentioning no
   parameter makes an instance concrete.
2. **Both substituters read their argument block after recursing into it.** D145 made
   `collect_generic_arguments` claim its slots before reading any argument; the two
   substitution paths (`substitute_type`, `substitute_aggregate_type`) had the same
   shape and the same defect, so substituting `List[Node[T]]` wrote `Node[i32]`'s
   argument where `List`'s was read, and the field came out as `List[i32]`. Both claim
   the block first now. The symptom was an `E-TYPE-0002` on a plain field assignment
   in the instance pass, and finding it took a probe that names which of the equality's
   checks failed -- worth keeping in mind, since the checker has no way to say.

One bootstrap limit, too: `MAX_TRAP_SITES` was 4096 and the compiler's own source sat
within a handful of it; past the table the bootstrap emitted `np_trap_site_-1` and the
assembler refused the program with an undefined symbol. It is 16384 now and the
bootstrap says when it is reached.
## D164 — `e.data.graph` and `e.algo.graph`

`e.data.graph` is the immutable CSR of D76: a builder that only collects edges, and
`finish` counting each node's edges into offsets and placing them in insertion order, so
node `n`'s edges are one contiguous slice. A node named by an edge past the builder's
count grows the count; an undirected edge reserves its two slots before adding either.
Exactly its fence, so `source`.

`e.algo.graph` is the traversal and path set over it, each deterministic from node order
and adjacency order: BFS with the visit order as its own queue; preorder DFS on an
explicit stack of edge cursors, so the order is the recursive one; Kahn's topological
order with a min-heap of the ready nodes, `Cycle` and nothing else when a node is left
over; weak components by flooding over the graph and its transpose; strong components by
Kosaraju over the same transpose, renumbered by smallest node afterwards; Dijkstra over
`heap.HeapBy` with a `(distance, node)` entry ordered by both, refusing a negative, NaN or
infinite weight before it is added. The transpose builder and three small declarations
are beyond the fence, so `partial`.
## D165 — `e.data.tree` as a treap, and two more compiler gaps closed on the way

`e.data.tree` is an ordered map whose shape is a function of its keys: a treap with each
node's priority the stirred hash of its key, so the same keys give the same tree on every
run, with parent pointers so that an iterator is one node pointer and steps to the
in-order successor with no reference to the map -- which is what the fence's
`Iter { state: *const void }` allows. Nodes are individual arena allocations, reused
through a free list after removal. `init` cannot fail by its signature, so a map whose
state could not be allocated is the empty map every later `put` refuses with
`mem.Exhausted`. `partial`: the node, state and rotation helpers are beyond the fence.

Two things the compiler could not do before this module:

1. **A generic struct that points to itself** (`left: *Node[K, V]` inside `Node[K, V]`)
   instantiated without end: `instantiate_aggregate` substituted the fields before it
   registered the instance, so the pointee's own instantiation never found it in the
   cache. The instance is registered first now and its fields filled in place.
2. **`nil` did not lower.** The checker accepted it for any pointer or slice; lowering had
   no case for the keyword. It is the zero pointer and the empty slice, exactly what
   `zero` is for those types, and it lowers as `zero` does.

One gap stays open, worked around: comparing two `*const` pointers to a generic instance
inside that instance's own generic (`right_of_up != child`) fails to lower, while the
same comparison outside generics and over mutable pointers is fine. The iterator casts
its `*const void` to the node's mutable pointer type and reads only.
## D166 — `e.algo.complex`, `e.algo.linalg.matrix` and `e.algo.linalg.tensor`; assignability in lowering

Three `partial` modules over `e.math` and `e.mem`. `complex` is the textbook formulas
with the two classic guards -- a scaled modulus and Smith's division -- and the
principal branch through `math.atan2`'s sign rules; C99 Annex G's table of infinite and
NaN operands is not reproduced, and the header says so. `matrix` is row-major strided
views over caller storage, so a transpose is a view and costs nothing, with Gaussian
elimination under partial pivoting for the determinant and Gauss-Jordan on `[A | I]` for
the inverse, both on arena scratch. `tensor` is N-dimensional strided views walked by an
odometer over the index, `reshape` reusing storage when the view is row-major and
copying otherwise.

One lowering defect: an assignment's value was required to be *equal* to its place's
type, where the checker had admitted *assignability* -- a `[]T` into a `[]const T`
field, a `*T` into a `*const T` local -- so `c.data = m.data` failed to lower with an
"invalid type" while `let d: []const T = m.data; c.data = d` did. Both assignment paths
use `type_assignable` now. (The `*const` comparison gap D165 worked around is the same
family, not yet fixed.)
## D167 — `e.text.encoding` and `e.algo.bignum`

`e.text.encoding` is the four transformation formats beside UTF-8, streamed: a decoder
keeps the bytes of an unfinished scalar between calls and an encoder remembers its BOM,
so a stream can be cut anywhere; `Reject` and `Replace` are the two answers to an
invalid sequence. Two simplifications, both in the header: an overlong form or a
surrogate is judged once its sequence is complete, so it is one U+FFFD rather than
Unicode's two or three; and a BOM is looked for only in the first call's bytes.

`e.algo.bignum` is sign-and-magnitude in base 2^32 over arena limbs, every result a
fresh allocation. Multiplication is schoolbook and division is binary long division,
a bit at a time -- quadratic times 32, which is what a first version should be, with
Knuth's algorithm D as the upgrade when a profile asks. The formatter allocates
nothing, because a `str.Builder` holds the top of its arena and a scratch taken from
the same arena would land on top of it: the scratch is on the stack, which caps a
formatted value at 1024 limbs (about 9864 decimal digits) and says `Invalid` past
that. A rational is kept in lowest terms with a positive denominator.
## D168 — `e.fmt.uri` and `e.algo.decimal`

`e.fmt.uri` is RFC 3986: a parse that borrows every part from its source and checks
each percent for its two hex digits; section 5.2's reference resolution with 5.2.4's
dot-segment removal, checked against the section 5.4 examples; the normalisations that
keep the meaning -- lower-case scheme and host, upper-case hex, unreserved characters
unescaped, the authority rebuilt from its parts; and per-component percent-encoding.
`+` is never a space, as the fence says.

`e.algo.decimal` is a signed 128-bit coefficient and a scale, sign-magnitude inside over
two limbs, two's-complement `(low, high)` at the surface. `add`, `sub` and `mul` are
exact or `Overflow`; `div` computes one guard digit past the requested scale and folds
the division remainder into a sticky digit, then `quantize` rounds once under the mode,
so a tie is seen as a tie only when nothing below it is nonzero. `Inexact` is declared
by the surface and never returned: every operation that could be inexact carries a
rounding mode, and the header says so rather than inventing a case for it.
## D169 — `e.time.calendar` and `e.fmt.quoted_printable`

`e.time.calendar` is proleptic Gregorian arithmetic with one currency, the day count
`e.time` already keeps: weekdays and ISO 8601 weeks (the Thursday of a date's week
decides its week-year), month and year arithmetic clamping the day to the month landed
in, and `Components` both ways with the derived fields checked on the way back. The
pattern verbs of `format` and `parse` are a comptime `str` -- the `Str` parameter kind
`e.fmt`'s `format` introduced -- read at run time here; a pattern is small and the run is short, so folding it
into the instance buys nothing yet.

`e.fmt.quoted_printable` is RFC 2045 6.7 over `e.io` streams and caller storage, the
state at the front of the storage and the rest a buffer. Decoding is strict: upper-case
hex, CRLF only, nothing above 126. Encoding breaks with `=CRLF` when the next piece
would not leave room for the `=` of a break, and escapes a trailing space or tab before
every break and at the end, since a receiver may strip white space at a line end.
## D170 — `e.fmt.mime` and `e.fmt.tar`

`e.fmt.mime` is RFC 2045's media type with its token-or-quoted parameters, formatted
back with quoting only where a value needs it, a small extension table of what a
toolchain serves, and RFC 5322 header blocks read from a stream into the arena so the
names and values borrow from one buffer; names compare case-folded and the obsolete
folding is `Invalid`, both as the fence says.

`e.fmt.tar` reads POSIX ustar with the PAX `path`, `linkpath` and `size` records applied
to the entry that follows; an entry's content is a limited `io.Reader` over the archive,
and `next` drains whatever was not read plus the block padding. The fixture's archives
are what Python's `tarfile` writes, trimmed to the two end blocks and carried as string
literals -- an array literal of ten thousand bytes is ten thousand stores in one
function, and that is past the register allocator's table. `generate.py` beside the
fixture regenerates them.
## D171 — `e.metrics` and `e.fmt.lzw`

`e.metrics` is three atomics: a counter and a gauge as one relaxed instruction each, and
a histogram whose buckets are cumulative in its snapshot and whose `f64` sum is kept as
bits in an `Atomic[u64]` and added under a compare-and-swap loop. Bounds must be finite
and strictly increasing; the bucket above the last bound is implicit. The plan's
dependency list gains `e.math` for `abs`.

`e.fmt.lzw` is the variable-width LZW of GIF and TIFF with the bit order and literal
width explicit, over caller storage sized by `storage_required`: the writer's dictionary
a hash of (prefix, byte) probed linearly, the reader's a prefix chain unwound into a
stack, both cleared when the 12-bit table fills. The tables are byte-packed because
`mem.cast` is pointer-only and the storage is `[]u8`. TIFF's early-change variant is not
applied; the header says so. The encoder's bytes are checked against an independent
Python encoder on five streams, by length and FNV-1a -- a round trip alone would prove
only that the two halves agree with each other.
## D172 — `e.fs.mmap`, `e.fs.watch` and `e.fmt.msgpack`

`e.fs.mmap` opens the file, maps it through `e.os`, and closes the file: the mapping
keeps what it needs. Its one `bytes` returns `[]u8` for a read-only mapping too, built
the way `e.os` builds its own view, since the surface has one accessor and a write to a
read-only page is the host's fault to report. `e.fs.watch` is `e.os`'s watch with the
actions renamed into this module. Both are the thinnest layer the fence allows.

`e.fmt.msgpack` is the whole format both ways: every integer written in its smallest
form, every family read into an arena `Value` tree under `max_depth`, and the typed codec
in `e.fmt.json`'s shape -- a struct as a map of its fields, one arm per field kind. The
fixture matches every family's bytes to the specification, not to a round trip.

One trap for the record: `io.memory_writer` returns a `Writer` it never fills in (its
fence has no callback to name), and writing through it is a null call. `e.fmt.json`'s
fixture wires `io.memory_write` by hand; the fixtures here use slice writers.
## D173 — the crypto set: `hash`, `mac`, `kdf`, `random` and `aead`

Five modules, each checked against published vectors rather than against itself:
SHA-256, SHA-512, SHA3-256, SHA3-512, SHA-1 and MD5 against `hashlib` on four inputs
with the streaming forms fed across every block edge; HMAC against RFC 4231 cases 2
and 6; HKDF against RFC 5869 cases 1 and 3 plus the length refusal; ChaCha20 against
RFC 8439's block and keystream, with the counter refusing to wrap; AES-GCM at both key
sizes against NIST's GCM test cases 4 and 16; ChaCha20-Poly1305 against RFC 8439 2.8.2.

Two things the vectors caught. Five of the eighty SHA-512 round constants typed by hand
were wrong -- D147's lesson again, and the tables are now generated from the primes'
cube roots by a script. And the AEAD's Poly1305 pads `aad` and the ciphertext to a
multiple of sixteen with zeros inside the block stream, which is not what a bare
Poly1305 message's partial-block rule does; a first draft used the message rule and the
tag was wrong while the ciphertext was right.

What is written plainly: AES is byte-oriented over its S-box and not constant-time
against cache timing, GHASH is the bit-by-bit multiply, and the headers say so; a
bitsliced AES and a table GHASH are the upgrade. `hash` and `random` are `partial` for
their helpers; `mac` and `kdf` are exactly their fences.

## D174 — `e.crypto.kx` and `e.crypto.sign`: X25519 and Ed25519

Both curves over 2^255 - 19 share one field representation: ten signed 64-bit limbs
alternating 26 and 25 bits, the reference implementation's layout, so a limb product
and the ten-term sums of a multiply stay inside a word. The field core is written
once in `kx.e` and duplicated into `sign.e`, because a fence exposes only its
declarations and the plan has no private module to share helpers through; a shared
`e.crypto.field` would be a plan change, not an implementation choice.

X25519 is RFC 7748's ladder with the swap by an arithmetic mask, checked against the
section 6.1 exchange and the first section 5.2 vector; the all-zero result of a
small-order peer is `InvalidKey`. Ed25519 is RFC 8032 in extended coordinates with the
unified addition formula used for doubling too, checked against section 7.1 tests 1
to 3 byte for byte. Scalars mod L are eight 32-bit limbs; the 512-bit hash outputs and
the products are reduced one bit at a time (512 shift-compare-subtract steps), which
is a few microseconds and far shorter than the reference's 21-bit-limb reduction.
Verification refuses a non-canonical `y` (at or above p), a non-canonical `S` (at or
above L), and a public key of small order (eight times it is the identity) -- the
fixture drives each refusal plus a flipped bit and a changed message.

What is written plainly: scalar multiplication is double-and-add and its timing
depends on the scalar; the hand-typed `L` limb that was off by one was caught by the
signature vector, the fourth time a constant typed by hand has been wrong in this
project, so the constants now come from a Python line kept beside the fixture.

## D175 — `e.fmt.pem`, `e.fmt.asn1` and `e.fmt.bson`

Three small codecs, each the shape its fence fixed. PEM (RFC 7468) takes the first
block and returns the unconsumed suffix; RFC 1421 `Name: value` lines before an empty
line are carried as `mime.Header`s and not interpreted; text before the first BEGIN
is skipped as the RFC allows, a body byte outside base64 or a mismatched END label
is `Invalid`, and the decoded size is checked against the byte limit before the
buffer is taken. ASN.1 is DER only: the reader walks one level of TLVs, `children`
descends one constructed value against the depth limit, and the typed codec maps a
flat struct to a SEQUENCE of its fields in order -- INTEGER, BOOLEAN and OCTET STRING
(a UTF8String or PrintableString is accepted on the way in). Every non-minimal length,
tag number, integer or boolean is `NonCanonical`; a length past the data is `Invalid`;
a length over eight bytes is `TooLarge`. BSON parses from a slice into the value tree
and writes back over `e.io`; the nine element tags in the fence are carried and any
other tag is `Invalid`, so JavaScript, regex and the deprecated tags never enter the
model. Its typed codec follows msgpack's: integers go out as int64 and doubles as
double, both integer widths are accepted on the way in.

What is written plainly: array keys are not checked against their positions on the
way in, a `str` field is encoded as OCTET STRING rather than UTF8String, and none of
the three streams -- each takes the whole source as a slice, which is what a
certificate, a key file or a document from a socket frame is in practice.

## D176 — `e.algo.deflate` with `e.fmt.zlib`, `e.fmt.gzip` and `e.fmt.protobuf`

DEFLATE is written as the fence asked: caller storage, no allocation, and resumable
at any byte of input or output. The decoder is a stage machine in the shape of zlib's
`puff`: a 64-bit accumulator refilled from the input, every symbol decoded against it
and committed only when all of its bits -- code, extra bits, distance code, distance
extra, at most 48 -- are present, so a call that runs dry leaves the state where the
next call resumes. Output history is a ring of `window_limit` bytes; a distance past
what was produced or past the ring is `Invalid`. Stored, fixed and dynamic blocks are
all decoded, checked against zlib's own dynamic stream of a 3758-byte text whole and
in seven-byte input, thirteen-byte output steps.

The encoder collects a 32 KiB block, compresses it into a staging area and drains
that across calls. `Fast` writes stored blocks; `Balanced` and `Best` write
fixed-Huffman blocks over an LZ77 hash chain 16 and 256 candidates deep within the
block. Its output was decompressed by Python's zlib during development (70000 bytes
across three blocks to 21399), and the fixture decodes it back through the module.
What is not written: a dynamic-tree writer, lazy matching and matches across a block
boundary -- the ratio ceiling, not a correctness one.

The accumulator reads up to seven bytes past a finished stream; `leftover` hands them
back so a framing reader gets its trailer. It is beyond the fence, called by `zlib`
and `gzip`, the way any private helper is reachable (spec 12 has no visibility).
Those two are pull readers and push writers over 4 KiB buffers; zlib checks the
header pair and the Adler-32, gzip skips FEXTRA, FNAME, FCOMMENT and FHCRC and checks
the CRC-32 and ISIZE; both tell the decoder when the source has ended and let it
drain its accumulator first, which the first draft did not and refused a valid
stream. Protobuf is the wire-format primitive set with the ten-byte negative varint,
zigzag and the field-number ranges enforced.

## D177 — `e.fmt.zip`, `e.test.support` and `e.cli`

ZIP is read from its tail: the end-of-central-directory record is found under the
comment, the ZIP64 locator and record take over when a count is saturated, and the
central directory is read once into the arena and checked against every `Limits`
field before an entry is exposed. An entry is read through a seek to its local
header, stored bytes straight from the source and DEFLATE through `e.algo.deflate`,
with the CRC-32 and size compared at the end; the reader's storage must be 8-aligned
because it is cast to the state, and `extract` takes it from the arena as `u64`s and
views the bytes. That is the general rule now written down: `mem.alloc[u8]` aligns to
one, so storage a module casts is allocated as `u64` and viewed. Encryption and any
method but 0 and 8 are `Unsupported`; an absolute name, a `..` segment, a backslash or
a bad signature is `Invalid`. The fixture's ZIP64 archive is hand-built, since Python
only writes the extension when a size needs it, and Python reads it back.

`e.test.support` is what its fence says: a clock moved only by `advance`, a reader that
plays chunks and failures, a writer capped per call into a capture, a schedule that
admits participants in order and fails once exhausted. `e.cli` parses a `Command`
tree -- long, short, inline and repeated options, `--`, a subcommand by its first bare
word, the rest positionals, required options read from their `env` variable before
`Missing` -- validates the spec, renders wrapped help and reads a struct's fields as
options through `meta`. Values are collected eight per option in a scratch table
during the parse; more is `InvalidArgument`, a limit that a real command line does not
reach and the fixture does not test.

## D178 — `e.text.template`, `e.fmt.multipart` and `e.db`

The template engine is `{{name}}`, `{{#if name}} ... {{else}} ... {{/if}}` and
`{{#repeat name}} ... {{/repeat}}` with `{{@index}}` inside, parsed once into a flat
node table whose block nodes point at their `else` and close; the source size, the
node count and the nesting depth are each bounded by `Options`. Truthiness is the
value's own -- a non-zero number, a non-empty text, a true bool -- and a repeat count
is an integer binding, negative being `MissingValue` like an absent name. Numbers are
formatted through a `str.Builder` over a stack arena, since `execute` has no arena
and the builder needs one. `validate[T]` checks every name against the struct's
fields and `execute_typed[T]` binds them by kind. No escaping happens here, as the
fence says.

Multipart keeps an 8 KiB window on the source. The body reader yields everything
before a `CRLF--boundary` and, absent one, everything but the longest tail that could
begin one, so a delimiter split across two reads is still found; the first boundary
is searched for past any preamble and later ones are where the previous body ended,
a distinction the first draft missed. Headers go through `mime.parse_headers` into
an arena carved from the storage. The writer returns the sink itself for a body.

`e.db` is exactly its fence: dispatch through the driver table with `Closed` for a
handle whose context is `nil`. The one decision beyond the fence is that a handle a
driver returns carries only its context and this module fills in the table from the
handle it came from -- the fixture's driver crashed on a nil table before that was
so, and a driver that had to copy the pointer into every `Rows` would get it wrong.

## D179 — `e.fmt.xml` and `e.tz`

The XML reader takes the whole source into the arena and walks it as events; an
empty element is a Start with `empty` set and then its End, so a consumer's depth
count needs no special case. The five named entities and numeric references are
decoded into the arena only when a text holds an ampersand, otherwise the source is
borrowed; the declaration is skipped, a DOCTYPE is `Unsupported`, and whitespace
outside the root is dropped while everything inside it is a Text event. Namespaces
are names with a colon in them, which is what the fence promised and no more.

`e.tz` reads TZif as RFC 8536 lays it out -- the 64-bit block when there is one --
and evaluates the POSIX footer rule for every instant after the last transition,
because the tzdata release is slim: Europe/Sofia's last stored transition is 1996
and every summer since is the rule's. The rule grammar is the `Mm.w.d/time` form, the
only one in the release, with the southern hemisphere's wrapped season and a
half-hour daylight offset both handled; `Jn` and `n` rules are `InvalidData` until a
release uses one. The builtin database is a pack of thirteen zones chosen for their
rule shapes and pinned to tzdata 2025c, generated by the script beside the fixture
from the same package the fixture's expectations come from; `load` takes any pack in
that shape. `resolve` tries the offsets a day either side of the local time and, for
a gap, binary-searches the transition to the second, answering the instant before
and the instant at it.

The first draft advanced past the data block twice and never saw the footer, which
made every instant after 1996 standard time; the very first check caught it.

## D180 — `e.concurrent.queue` and `e.concurrent.map`

The queue is a ring of `T` under one `sync.Mutex` with a condition for each side;
the timed forms compute a deadline once and re-wait on what remains, so a spurious
wake does not restart the clock. `close` broadcasts to both sides and what is
buffered is still popped before `Closed`, as the fence says. The map is sharded by the
high half of `K.hash` with the low half choosing the slot, each shard its own
open-addressed table under its own lock, and `Full` is the shard's fullness against
its share of the capacity -- an uneven hash can fill one shard before the map holds
`capacity` keys, which is the price of never taking two locks at once and is written
in the header. `len` sums the shards in turn and is the point-in-time figure the
fence promised. Both were driven by real threads in the fixture: a producer through
a queue of four, two fillers into sixteen shards under a reader.

## D181 — `e.fmt.bzip2` and `e.text.io`

bzip2 decompression is bounded the way the fence asks: the storage holds the state,
a 4 KiB input buffer and four bytes per byte of the largest block it will accept, and
a stream whose header names a bigger block is `TooLarge` before a byte is decoded.
A block is decoded whole into the `tt` array -- Huffman groups over the MTF/RLE2
symbols, the origin pointer, the cumulative counts threaded into links -- but the
inverse Burrows-Wheeler walk and the first-stage run-length decode happen as `read`
asks, one byte at a time out of the links, so a block never needs an output buffer
and the output limit is enforced as bytes leave. The block CRC is bzip2's MSB-first
CRC-32 computed per byte; the combined CRC is rotated and mixed per block and checked
at the end-of-stream marker. Python's bz2 output for a 264 KB text with long runs
is the reference, read back in 7000-byte pulls across three blocks. Compression is
not written, as the fence says.

`e.text.io` reads lines out of a decoded buffer twice the raw capacity, since UTF-16
grows by up to half when it becomes UTF-8, and hands out the text before a bad byte
before reporting it -- a first draft lost the good line in front of the error.
`Newline.Native` resolves to LF on every host, written plainly in the header: a
portable module cannot learn its host, the gap D97-D132 record, and a per-target
variant of the file is the upgrade.

## D182 — `e.debug` and `e.log`

`e.debug` is its fence and nothing behind it: `backtrace` answers no frames and
`symbolize` an address with empty names and line zero, which is exactly the shape
the fence assigns to missing symbol data. There is no frame walk because the
compiler has no intrinsic to read the frame chain and no symbol table in the
executable; writing a guess would be worse than writing nothing. When those land,
both functions fill in and no caller changes -- `e.log` already threads the frames.

`e.log` stamps each record from the wall clock and hands it to every sink in turn,
stopping at the first failure. Both sinks render through a `str.Builder` over a
4 KiB stack arena, so a sink allocates nothing and a record longer than that is cut
rather than grown; the console sink writes to an `os.File` directly and the JSON
lines sink to an `io.Writer`. An `err` field prints as `ok` or `error`: an error has
no name at run time until the trap protocol carries one (spec 11), and inventing a
number for it would be read as meaning something.

## D183 — `e.fmt.yaml` and `e.crypto.x509`

The YAML subset is parsed from logical lines -- indent and content with the comment
stripped once, quotes respected -- by recursive descent on indentation, with a
sequence item that begins a mapping or a nested sequence re-read as that node two
columns in. Plain scalars resolve by the core schema; the writer quotes a string
that would resolve to anything else, or that starts or ends with something YAML
gives meaning to, and writes block style throughout. Folding follows the spec: the
break before the first empty line becomes the newline, which the first draft doubled.
Anchors, aliases, tags, directives and a second document are `Unsupported`, as the
fence says; a mapping or sequence holds at most 256 entries per level and a flow
collection 64, limits a configuration file does not reach and the header states.

X.509 is read through `e.fmt.asn1` with the algorithm set pinned to Ed25519 -- any
other signature or key algorithm is `InvalidCertificate` -- and the chain built by
name from a leaf through the intermediates to a root, each link's signature checked
over its TBSCertificate bytes, each window against the caller's `now`, each
intermediate's CA bit, the leaf's DNS name with a leftmost wildcard, and its extended
key usage when it carries one. A name renders as `CN=x, O=y` in written order. The
plan listed `e.text.unicode` among its dependencies; DNS labels are ASCII and the
comparison folds ASCII case through `e.str`, so it is not needed and not listed.
The chain in the fixture is built by Python's cryptography package, which verifies
it itself before this module is asked to.

## D184 — `e.text.unicode`

The property tables are generated from Python's `unicodedata` -- Unicode 15.0.0,
which `version` reports -- by the script beside the fixture, which also writes the
fixture's expectations from the same source: the general category as 4007 runs of
(start, category), the canonical combining class as 581 runs, simple lower and upper
mappings and full case folding as sorted pairs with a small side table for the 104
scalars that fold to two or three. All of it is byte strings in the module read
little-endian, 42 KB in all, searched by binary search; the source is large and the
compiler took it without complaint. White_Space is the property's own 25 scalars,
written in the code. What is a reduction and says so: `is_alphabetic` is the letter
categories and Nl rather than the Alphabetic derived property, and graphemes are
extended clusters by a reduced rule set -- CR LF, marks, ZWJ and variation selectors,
regional indicators in pairs, Hangul jamo -- with the Grapheme_Cluster_Break table
and UAX #29 in full as the upgrade. The plan listed `e.text.utf8` as a dependency;
the module reads UTF-8 with its own twenty lines and does not need it.

## D185 — `e.fmt.zstd`

The reader decodes RFC 8878 frames a block at a time into a history buffer of the
window plus one block: raw and RLE blocks, and compressed blocks with their Huffman
literals (weights direct or FSE-coded, one or four streams) and FSE-coded sequences in
every mode -- predefined, RLE, compressed, repeat -- with the three repeat offsets and
the zero-literal-length shift. Backward bit streams count the zero bytes they feed
past their start, so "ended exactly" and "read too far" are both plain checks. The
XXH64 of the content is compared at the frame's end. Storage holds the input block,
the literals, the tables and the history, and a frame asking for a window past the
storage is `Unsupported`, as is a dictionary or a skippable frame.

Two things libzstd's own decoder settled where my reading of the RFC had gone wrong.
The match-length default distribution has seven "less than one" symbols, not
seventeen -- a table built from the misremembered list decoded the first sample
block to the wrong length, and the truth was recovered by feeding libzstd every
state of a hand-built block and reading what it produced. And the interleaved
weight stream ends when a state update reads past the stream's start, with one more
symbol from the other state; ending it when the bits are exactly consumed drops the
last weight, which shifted every literal by one symbol. Both are now written in the
code as what libzstd does.

The writer emits frames of raw blocks with a checksum at every level -- valid
Zstandard that libzstd read back during development -- and the header says the
level is accepted and ignored; the entropy coders on the writing side are the upgrade.

## D186 — `e.fmt.html`, the common path of the WHATWG algorithm

The tokenizer follows the specification's data, tag, attribute, comment, DOCTYPE,
RCDATA and RAWTEXT states, and decodes named references from the full HTML5 table
(2231 entries generated from Python's `html.entities` by the script beside the
fixture, longest match, the legacy names without a semicolon left alone in an
attribute before `=` or a letter, as the specification says) and numeric ones with
the replacement character for what is not a scalar. The tree builder carries the
rules that shape ordinary documents -- implied `html`, `head` and `body`, head-only
elements before the body, void elements, `p` closed by a block, `li`, `dt`/`dd`,
`option`, cells, rows and headings closing their open sibling, an end tag closing
back to its element or ignored, `svg` and `math` opening their namespaces where
self-closing tags close -- and recovers malformed input rather than refusing it.
Nodes live in one arena table with parent, child and sibling links; adjacent text
merges into one node; the serializer escapes text and attribute values and leaves
raw-text elements as they are.

What is not written, and the header says so: the adoption agency for mis-nested
formatting elements, foster parenting of text inside a table, the `template`
element and the in-table insertion modes beyond cell and row closing; and the
html5lib tree-construction fixtures have not been run. The fence names the whole
algorithm with those fixtures recorded in a build manifest; this module is the path
real documents take and marks its surface `partial` for the rest. The plan's
`e.text.utf8` dependency is not needed: UTF-8 is validated in twenty lines here.

## D187 — `e.async` and `e.fmt.mail`

`e.async` is the fence over `e.os`'s poller: the loop is the host's registration set
and each call is the matching `os.poller_*` call with the token and interest carried
across, `Unsupported` where the host has no poller and `Invalid` after `close`. Its
fixture is `link/os_poller`'s shape with the module in front of it: two loopback
datagram sockets, the empty poll, both readable, the interest changed, the wake.

Mail parses addresses in every form RFC 5322 puts in a header and splits a list on
the commas outside quotes, brackets and comments; dates take numeric zones and the
obsolete names; `read_message` unfolds continuation lines -- mime refuses a line that
starts with a space, rightly, so the fold is undone first -- and hands the body back
as a reader over what was buffered past the block and then the source. Encoded words
decode B and Q in UTF-8, US-ASCII and ISO-8859-1, with the whitespace between two of
them dropped; a word in another charset or of another shape is left as written. The
plan's dependencies on multipart, quoted-printable and encoding are not used: a body
is the caller's to route through them, as the fence itself says.

## D188 — `e.fmt.html.template`, escaping by context

The HTML template reuses the core engine's parse and node table and decides, once
at parse time, the context of every interpolation by running the literal text
before it through a small HTML state machine: element text, an attribute value in
either quote, a URI attribute, a `style` attribute or element, a `script` element.
Execution walks the same nodes with the core engine's lookup, truthiness and count,
and writes each value through the escaper its context names -- entities in text and
attributes, percent-encoding with the scheme checked for a URI (`javascript:` and
any scheme but http, https and mailto become `#unsafe`), CSS hex escapes, a
JavaScript string literal with hex escapes for everything that could form a tag or
a quote. An interpolation in a tag or attribute name, in an unquoted value, in an
event handler attribute or in a comment is `UnsafeContext` at parse, since no
escaping makes those safe; a template that ends inside a tag is refused the same
way. There is no raw insertion, as the fence says.

The contexts ride behind the inner template's state pointer: this module's state
begins with the core engine's `nodes` field and adds the context table, so the
same pointer serves both `template.validate` and this module's `execute`. A first
draft kept them in a module-level table and found that a module-scope `var` is not
lowered yet; the prefix layout needs no global and is the better shape anyway.

## D189 — `str.format` recurses into slices and arrays

The formatter expansion, which lowered one `e.str` push per verb and refused a
slice or an array, now writes a sequence as `[` elements `]` with `, ` between,
each element through the same function -- so a slice of `str` prints its texts and
an array of arrays nests -- in the loop shape `emit_sequence_cmp` already used: a
counter on the stack, a condition block, a body with a separator branch, an exit
block. `sequence_parts` and `element_operand` were there for `cmp`; the verb rides
down to the elements, so `{:x}` on a slice of integers would be hex -- the checker
still refuses that at the call, as it did before, and lifting it is a checker
change for another day. Enums and a type's own `format` are what rule 4 still
leaves to the expansion.

## D190 — `str.format` prints an enum by its variant name

The expansion compares the value against each variant's backing bits in
declaration order and pushes the matching name a byte at a time, one block per
variant and one exit they all reach; a value no variant declares pushes nothing,
which is the honest answer for an enum that was never given a name for it. Explicit
and negative backing values go through `enum_member_bits` the way a `switch` arm
does, and a slice of enums reaches this through D189's sequence path. The hex and
binary verbs still take the integer -- an enum under `{:x}` is refused by the
checker as it was. A struct with a `format` of its own is what rule 4 still leaves.

## D191 — `str.format` calls a type's own `format`

A `Named` argument whose module declares `fn <t>_format(v: T, b: *str.Builder) -> err`
is formattable, as section 4 says, and the expansion writes it as one call to that
function with the builder it is already pushing into, the `err` guarded like a
push's -- the shape `emit_declared_cmp` gave `cmp`. The checker matches the
declaration exactly, receiver by value, a pointer second, one `err` back, because
nothing re-checks the call the expansion synthesizes; the lookup is the same
`protocol_function` walk the other rule 4 protocols use. A struct without one is
still refused at the call, which is what the negative fixture pins now. With this,
rule 4's `format` reaches every shape the section lists but pointers and
`union enum` payloads.

## D192 — An `extern` declaration is checked against the C ABI table

Section 5 closes the set of types that cross a foreign call: integers, `bool`,
`f32`/`f64`, enums, function pointers, pointers to `void` or to a crossing type,
and non-generic structs and unions whose every field crosses (a fixed array field
of a crossing element included). Slices, `str`, `err`, arrays by value, generic
templates, `Vec`/`Mask`/`Atomic` by value and tagged unions do not. The checker
now walks that table (`type_crosses`) over every parameter and the return of each
`extern fn` at declaration time and refuses the declaration with `ExternType`,
naming the function and the type -- by its shape (`a slice`, `an array by value`)
when the type has no name. Intrinsics are exempt, as they are not calls at all.
Before this, `extern fn puts(text: []const u8)` compiled and passed a two-word
slice where C expects one pointer; the fixtures `check/extern_slice_parameter`
and `check/extern_slice_return` pin the two sides. Variadics remain the open row.

## D193 — A trailing `...` on an `extern fn` is a C variadic

Section 5 allows one runtime-variadic form: a trailing `...` on an `extern`, each
extra argument crossing as its own type and with no default promotion. The checker
now records the `...` on the declaration (`Function.variadic`; anywhere but an
`extern` it stays refused), lets a call carry any number of arguments past the
declared parameters, types each of those with no context, and refuses one that is
untyped, does not cross the table, is an `f32`, or is an integer narrower than 32
bits -- the promotions C would apply silently are the caller's to write as `i32(x)`
or `f64(x)`. Lowering passes the extra arguments as ordinary operands. The back end
has no per-call flag, so every imported call is made the way a variadic one has to
be: on Win64 a float argument is also copied into the integer register of its slot,
and on System V `al` carries the count of xmm registers used. A fixed-arity callee
ignores both, so the cost is one move per float and one `mov eax` per foreign call.
`link/extern_variadic` prints `%d %lld %.2f %s %d` through `snprintf` with eight
arguments, so the stack overflow area and the float are both exercised on each
convention; `check/variadic_narrow_argument` pins an `i16` refused.

## D194 — A failed check follows section 11's trap protocol

A bounds check that failed executed `ud2`: an illegal-instruction crash, a
platform-specific exit status and no word about where or why. Both embedded runtimes
now carry `neper_trap`, which writes one record to stderr -- `file:line:col:
trap[kind]: <values>`, the shape of a compiler diagnostic -- and exits 134, as the
section says. The record's text is laid out inline in the code beside the check, the
way a string constant is, with a NUL where each of the two operands goes, and the
generated code jumps over it; the runtime prints the segments and the operands in
decimal between them. Nothing about a trap is in NIR: the checks are selected in the
back end, so that is where the record is built, and the function's source path
travels on `nir.Function` for it. The rows that fire this way are `bounds` -- an
index against its length, a slice's start against its end and its end against the
length -- and the points the compiler itself takes as unreachable (a `switch` with
no default falling through, the exit of a `while true`). `link/trap_bounds` pins the
record and the exit code for the index and the slice on both platforms. The
backtrace, the test root's framed control record, the arithmetic rows and the
release-mode elision are still open.

## D195 — `unreachable()` is the one always-on builtin

Section 11 names one builtin every build mode keeps: `unreachable()`, with an optional
`str` literal, a trap of kind `unreachable` whose values are that literal, after which
control is dead. The checker recognises the call by its keyword receiver, accepts at
most one argument and only a string literal (the message is laid out beside the site,
so it has to be text the back end can place), types the call as void and counts the
statement as returning, so a function whose last statement is `unreachable("why")`
needs no `ret` after it. Lowering emits the NIR `.Trap` that D194 left unused, its
immediate the message's string constant plus one -- zero for the bare form -- and the
`.em` body hash names the message by its text rather than that program-wide index, as
it does for a string constant. The back end prints `unreachable() reached` for the
bare form. `link/trap_unreachable` pins both forms on both platforms, and
`check/unreachable_argument` pins a value argument refused.

## D196 — The `divide` and `shift` rows trap with a record

Section 11's `divide` rows trap in every build mode, and until now they did: x64
raises `#DE` for a zero divisor and for the minimum divided by -1, which is a crash
with a platform status and no record. The back end now tests the divisor before the
instruction and, for a signed division, the pair the quotient cannot represent, and
reaches `neper_trap` with `<dividend> / <divisor> divides by zero` or `... overflows`
(`%` for a remainder). The `shift` row, whose count the instruction was silently
masking to `width - 1`, traps on a count at or past the width with `shift by <count>
on a width of <width>`; the release-mode masking the section describes waits on
build modes, which nothing selects yet. A signed operand prints signed: the record's
separator byte says how the runtime renders the operand that follows, 0 unsigned and
1 signed, which is the only change to the runtime. `link/trap_arithmetic` pins the
four records on both platforms and that the same operators in range are untouched.
The row found two library sites that leaned on the masking: every rotate in
`e.crypto.hash`, `e.crypto.random`, `e.fmt.zstd` and the compiler's `artifact_hash`
shifted by the full width for a rotation of 0, and zstd's Huffman rank table shifted
by -1 for its top rank; both now avoid the count the section forbids.

## D197 — `Kind(x)` is a cast, and the `enum` row traps

Section 4 names an integer-to-enum cast, `Kind(x)`, from an integer of the backing
width alone, and section 11 says a value naming no member traps in every build mode.
Neither existed: `Color(x)` was an unknown callable. The checker now recognises a
same-module enum's name in call position as a cast, accepts only an integer of the
backing width (`check/enum_cast_width` pins a `u32` into an `enum u8` refused, as
the section says to go through `u8` first), and lowering casts the integer to the
unsigned type of its width -- an enum lives in a register as its backing bits
zero-extended, which is what a load and a member constant both give -- then tests
it against every member, one `Equal` and a branch per member, and reaches a `.Trap`
of kind `enum` where none matched. That `.Trap` carries its kind as the name of an
`Other` type and the integer as its operand, so the record reads `no member of Level
has value -6` with the source integer printed in its own signedness; the message is
built by lowering and interned raw, which the back end tells from a literal by the
absence of a quote. `link/trap_enum` pins an `enum u8` and an `enum i8` on both
platforms and that a cast naming a member, a negative one included, is untouched.
A qualified enum name, `lex.Kind(x)`, is not yet a cast.

## D198 — Integer casts are checked, and `T.trunc(x)` is the meant truncation

Section 4 says a cast between integer types is checked -- the value must be
representable in the target, `u32(x)` with a negative `x` and `u8(n)` with `n = 300`
alike -- and that a truncation that is meant is spelled `T.trunc(x)`; section 11 makes
the failure the `narrow` row. Both were missing: every cast cut to the width and the
spelling did not parse. The back end now keeps the source of a cast that narrows the
width or changes the sign, normalises as before, and traps unless widening the result
again gives the source back -- at a 64-bit target, where normalising is a no-op, the
test is the sign that would change. The record prints the source in its own
signedness and the type it did not fit: `-298 does not fit usize`. `u8.trunc(x)`, and
`T.trunc(x)` for a type parameter bound to an integer, is a cast whose NIR immediate
is 1, which the back end never checks; it takes only an integer argument
(`check/trunc_float_argument`). The row found ten library sites that meant the bits:
`e.bytes`' `load`/`store` of a signed `T`, the two's complement negations in
`e.algo.bignum` and `e.algo.decimal`, `e.fmt.msgpack`'s signed integer and ext-kind
bytes, and `os.windows`' `to_filetime`, all now `trunc`; `e.bytes`' base codecs mask
before cutting to a byte; `e.math`'s `pow` masks the high word it extracts; and the
`scalar` fixture, which asserted the C result, now narrows a value that fits. A record
inside a generic instance named the caller's file with the template's line: the
function's path is now the template's. `link/trap_narrow` pins five refusals and the
meant forms on both platforms. Float-to-integer narrowing is still unchecked.

## D199 — `main`'s failure line is written from a synthesized error table

Section 13 says a `main` that returns anything but `ok` writes `error: <qualified
name>` to stderr from the merged error table and exits 1; the C bootstrap did so and
the self-hosted compiler exited 1 in silence. The table now reaches the binary as
code: when the root module's `main` returns an `err` from any `ret` that is not the
literal `ok`, lowering branches on the value and, on the failing path, calls
`neper_report_failure`, a function synthesized once the module is lowered -- one
`Equal` and a branch per error symbol the resolver holds, program-wide, each arm
writing `<module>.<name>`, and `err(?)` for a value none of them has, which only
`undef` can produce. It writes through the runtime's own `neper_os_stderr` and
`neper_os_write`, which every image carries, so nothing depends on `e.os` being in
the graph, and a `main` that only ever returns the literal `ok` carries none of it.
The function has no declaration, so the `.em` hashes it by its NIR alone and the
signature table reserves the one parameter type it needs. `link/failure_line` pins the
module's own error and one of `e.os`'s on both platforms, and that `ok` writes nothing.
`neper test` and the trap protocol's use of the table are still open.

## D200 — The `tag` row, and the float side of `narrow`

`n.Lit` reads or writes a tagged union's payload, and section 4 says it is one compare
against the tag in a debug build, with a mismatch a `tag` trap (section 11). Both
paths through lowering that reach a field of a tagged union -- the address taken for
a write and the load for a read, through a pointer or not -- now load the tag at
offset 0, compare it with the member's, and reach a `.Trap` of kind `tag` whose
message names the union and member and whose operand is the tag found: `Node.Pair
read while the tag is 1`. Reading `n.tag` itself is not a payload and is untouched.
Section 4's float-to-integer cast is the other `narrow` case: a value outside the
target's range, or NaN, traps -- the release-mode saturation waits on build modes.
The back end compares the double or single in `xmm0` against the two bounds as bit
patterns before `cvttsd2si`: strictly below the power of two past the range above,
and above the bound below -- `-2^(width-1) - 1` exact for a double into a narrower
target, `-2^63` inclusive at 64 bits or from a single, `-1` for an unsigned target --
with NaN refused by the unordered compare. `link/trap_tag` pins a read and a write
under the wrong tag and four float refusals on both platforms, and that the live
payload and casts at both edges of their ranges pass. `T.trunc(f)` is not a float
conversion (D198), so the checked cast is the only one from a float.

## D201 — The `null` row: a dereference of `nil` traps

Section 4 says every dereference is null-checked in a debug build, and section 11
makes the failure the `null` row. Lowering now compares the pointer with zero on
every path that reads or writes through a pointer value -- `*p` as an operand and as
an assignment target, and `p.field` through the auto-dereference, read or written --
and reaches a `.Trap` of kind `null` whose message names the pointer's type: `nil
dereferenced as *Point`. A value that is already the address of a stack object or of
an aggregate passed by address never comes through those paths and is never nil, so
the check is only where a pointer the program holds is followed. The compiler's own
image grows by a seventh; no build mode elides the check yet. `link/trap_null` pins
the four refusals on both platforms and that live pointers pass.

## D202 — The `overflow` row: `+ - *` and unary `-` trap when the result does not fit

Section 11's `overflow` row traps in a debug build and wraps in release; with no
build modes yet, it traps, and `+% -% *%` remain the spelling for a wrap that is
meant. Below 64 bits the operands sit sign- or zero-extended in their registers, so
the 64-bit result of the instruction is exact and overflow is the normalised result
differing from it -- one move and one compare. At 64 bits the flags say: `OF` after a
signed operation, `CF` after an unsigned one. An unsigned 64-bit `*` is the case
`imul` cannot flag, so it goes through `mul`, whose nonzero high half is the overflow,
under the fixed-register discipline division already uses. Unary `-` on a signed type
is checked the same way; on an unsigned type it is not. The record names the type and
the operator -- `usize - overflows` -- and not the operands, which the instruction
has consumed by the time the flags are read. The row found five library sites that
meant the wrap: the borrow in `e.algo.decimal`'s negation, `e.algo.deflate`'s
multiplicative hash, `e.algo.uuid`'s shift countdown, and the carry idioms of
`e.math`'s wide add, subtract and multiply, and the negated process group `os.linux`
hands to `kill`, all now `+% -% *%`. The compiler's own image grows by four percent. `link/trap_overflow` pins eight refusals across the
widths, both signednesses and the four operators on both platforms, and that the same
arithmetic in range, and `+%` past the edge, pass.

## D203 — `@nocheck { ... }` leaves the debug-only rows out of a block

Section 11 gives `@nocheck` for the rare hot loop: it disables the debug-only rows
inside the block and cannot disable the rows that trap in release. The statement
parsed and was refused by lowering; it now lowers its block with the builder marked,
and every NIR instruction emitted while the mark is up carries it. The back end
leaves out `bounds`, `overflow`, `narrow` (integer and float) and `shift` for a marked
instruction, and lowering leaves out `null` and `tag`; `divide`, `enum` and
`unreachable` are not consulted. An unsigned 64-bit `*` still goes through `mul`
inside the block, only its high half is not looked at. The mark is semantics -- the
same source with and without it is two programs -- so the `.em` body hash carries it
in the instruction's reserved half-word. `link/nocheck` pins a block running an
overflowing sum, a narrowing cast, an over-wide shift and a payload read under the
wrong tag to exit 0, a division by zero inside a block still trapping, and the same
sum outside a block trapping, on both platforms.

## D204 — `emit-executable --release` is the release build

Section 11 divides its rows by build mode: the debug-only ones are removed in
release and the arithmetic rows take their defined release result -- wrap, truncate,
mask, saturate -- while `divide`, `enum` and `unreachable` trap in every mode.
`emit-executable` now takes a trailing `--release`, which lowers the whole program
under the same mark `@nocheck` puts on a block (D203), so the debug-only rows are left
out everywhere and `+ - *` wrap, a narrowing cast truncates and a shift count is
masked, which is what the instructions do once the checks are gone. The one release
result the hardware does not give is a float outside its integer target, which
`cvttsd2si` answers with the indefinite integer: an unchecked float-to-integer cast
now compares against the same two bounds the check used and lands on the maximum,
the minimum or zero for NaN, on both platforms. A release build of the compiler is a
quarter smaller than the debug build and emits byte-identical code from it, which is
section 11's promise that the modes agree until a check fires. `link/release_build`
is built in both modes by the runners: the debug build traps on its first `+`, the
release build passes every release result and is smaller. The debug fills are still
absent from both modes.

## D205 — `emit-em-all --incremental` applies the edge rule

Section 12 recompiles a module when its source hash changes or a recorded edge no
longer matches the current hash of its target, and nothing else. `emit-em-all` now
takes a trailing `--incremental`: the program is compiled as before, every fresh
artifact is held in memory, and then each module's artifact already in the directory
is judged -- kept when the Debug section's source hash is unchanged and every edge in
its Deps still matches the declaration it names in the target's fresh artifact, by the
same `dependency_matches` that `check-em-edge` uses, replaced otherwise -- with every
decision taken before any file is touched, since a target may come earlier in module
order than its dependent. `kept <module>` or `rebuilt <module>` is printed per module.
`link/incremental` is driven by the runners through a scratch copy: unchanged sources
keep everything, a body edit behind a signature edge rebuilds only `dep` and links
byte-identical to a clean build of the edited tree (section 12's "incremental equals
clean"), and a signature edit rebuilds `main` as well. The saving the section
describes -- not compiling the kept modules at all -- is not here: checking a module
against its dependencies' Interfaces alone, without their sources, is not a path the
checker has, so this is the rule and the writes, not yet the time.

## D206 — A trap ends with its backtrace, from a symbol table after the code

Section 11's trap protocol writes the record and then a symbolised backtrace. Every
function keeps a frame pointer, so the walk is `[rbp+8]` and `[rbp]` from the
trapping function's frame and the return address into it, until an address no
function claims -- the runtime's own entry -- or thirty-two frames. The names come
from a symbol table the driver appends to the machine code once it is final and
before either linker sees it: a count, then per placed function its start relative
to the table, its length and its `module.function` name, then the names. Each trap
site loads the table's address into `r10` through a reference to `neper_symbols`,
which the driver resolves against the table it just wrote, so neither linker learns
a new relocation kind and the artifact path -- whose functions carry the module name
from their artifact's Interface -- links byte for byte the same as the source path,
which the suite already pins. A folded duplicate is listed once, under the survivor's
name. The compiler's own image grows by three percent for the table, and relocations
are now sized by the instruction count, two per trap site having overrun the old
constant. `link/trap_backtrace` pins a bounds trap two calls deep printing
`helper.pick`, `main.deeper` and `main.main` in that order on both platforms. The
file and line of each frame, which need a line table, are still open.

## D207 — Cross-module inlining through an oracle lowered ahead of the program

Section 12 caps cross-module inlining at callees of forty NIR instructions and makes
every inlined callee a body edge. Inlining at a call site needs the callee's NIR, and
the two link paths lower modules in different orders, so the callee is not reliably
there when the call is; a pass after lowering would need a second copy of the whole
program's tables, which the default arena has no room for. So the small functions are
lowered first: every non-generic function of every module whose declaration is a
hundred tokens or fewer goes into the oracle, a builder of its own a tenth the size
of the program's, in module order on both paths, and the ones that came out at the
cap or under, without a hidden return slot and with at most one non-aggregate result
are entered. The program's own lowering then copies a body in at each call to an
entered function: `Parameter` becomes the argument, `Return` a branch to the
continuation block -- through a stack slot when the callee returns from more than one
place -- and function, string and global references are re-interned; the callee's
own body is not inlined into further, so a copy is one level deep. Each instruction
now carries the path of the file it came from, which a trap record inside an inlined
body names. The oracle's lowering is a second lowering of those functions, and the
instances it creates are the ones the program's lowering would create at the same
calls. Every inlined callee of another module is recorded on the builder: the artifact
writes a body edge for it with the hash its own artifact's Interface carries, the
pruner keeps the callee's definition in an artifact for that hash while an executable
still drops it, and a module reached only by inlining is still lowered. The
compiler's image grows by a fifth in debug; the machine buffer's multiplier drops
from 96 to 56 bytes per instruction, twice what the checks brought it to, so the
oracle fits the default arena. `link/incremental` now pins both edge kinds: a body
edit behind a signature edge keeps the dependent and one behind a body edge rebuilds
it, and `link/trap_backtrace`'s inlined frame is gone from its walk. The cap is
applied within a module as well, where the section has none.

## D208 — The bootstrap's archive is recorded

D95 named the archive -- a tag, the stage hashes per platform, the commands that
reproduce them -- and left it to be made. `docs/bootstrap-archive.md` now records,
at revision `448256c`, the SHA-256 of stage one (the bootstrap built by MSVC 14.51 and
GCC 13.3, toolchain-specific and said so), stage two (the compiler built by the
bootstrap's driver), stage three (the compiler built by itself, the stable stage)
and stage four (identical to three) on Windows and Linux, with the commands that
reproduce them from a clean checkout; the tag `bootstrap-archive-1` marks the
revision that carries the file, which differs from the measured one only by that
file and the readiness page. Stages two and three depend on the sources alone, which
is what a recovery must reproduce; stage one is whatever the C compiler at hand
makes of `bootstrap/neper.c`, and needs only to build stage two. Deleting the
bootstrap, the M2 exit item after this one, is still open: both suites build their
compiler from it on every run.
