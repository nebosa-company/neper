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
