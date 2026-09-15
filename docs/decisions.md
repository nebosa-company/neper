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

## D209 — The line table: every frame of a backtrace has its file and line

Section 13 promises a line-and-symbol section in every build mode, and section 11's
backtrace names the file and line of every frame. The back end now records a line
row wherever the line or the file changes as it selects a function -- the offset in
the machine code, the line, and the instruction's own file, which an inlined body
brought with it (D207) -- and the symbol table after the code (D206) carries, per
function, its rows and the distinct paths they share. Both runtimes look a frame's
return address up in its function's rows, the greatest offset at or below the
address less one, and print ` (path:line)` after the name. Artifacts carry each code
function's rows in a Lines section, the file as a string index, and the artifact
linker re-bases them to the assembled code, so an executable linked from artifacts
keeps the table byte for byte the same as one built from source; the fold rewinds
the rows with the code it drops. The section is new, so the `.em` format version is
4, as section 12 says a change to the serialization is. `link/trap_backtrace` pins `helper.pick
(...helper.e:1)` and `main.main (...main.e:17)` on both platforms. The compiler's
image grows by a tenth for its rows. A named `.nepersym` section, DWARF and CodeView
are still open.

## D210 — The `align` row is checked at the aligned intrinsics' call sites

Section 11's `align` row belongs to `simd.load_aligned` and `store_aligned`, which
are ordinary generics in `e.simd` that call `load` and `store`: the library has no
way to name a check kind, and a builtin for one would be a language addition the
section does not make. So lowering places the check where a call to either is
lowered, with the slice, the offset and the vector type in hand: the element address
is the slice's data plus the offset times the element size, wrapping, and its low
bits against the vector's width have to be zero, or a `.Trap` of kind `align` fires
with the address as its value -- `address not a multiple of 16: 20970884`. The row is
debug-only, so `@nocheck` and `--release` leave it out, and the record's site is the
call. `mem.address_of` now bitcasts its pointer to `usize` rather than passing the
value through under the old type, which is what let a fixture compute the skew to
an aligned lane in the first place: arithmetic on the old value would not select.
`link/simd_lanes` loaded eight float lanes at an offset of four, sixteen bytes into a
stack array, which was never aligned to thirty-two; it starts its lanes at the first
sixty-four-byte boundary inside a larger array now and loads at eight.

## D211 — Debug builds do not inline; `emit-em-all` takes `--release`

Section 13's rule for debug builds is that the inliner is off in every module and
across every `.em` boundary, so every frame in a backtrace is a real call and a
breakpoint on a function is hit whenever it runs. D207 inlined in both modes, and
`link/trap_backtrace` had lost its `deeper` frame to it. Now the oracle is built and
consulted only for a release build: `emit-executable --release`, and `emit-em-all
--release`, which is new -- the flags after the five positional arguments are read in
any order, so `--release --incremental` is the incremental release build. A release
artifact says so in its header's mode byte, which was always written and is now read
(`em.artifact_mode`); the edge rule keeps an artifact only when its mode agrees as
well as its source hash, so switching modes over a directory rebuilds everything
rather than linking debug code into a release program. `link/incremental` runs its
whole sequence in release, since the body edge it pins exists only where inlining
does, and `link/trap_backtrace` names `main.deeper` again. A debug build of the
compiler no longer pays for the oracle at all.

## D212 — Nested inlining through a second oracle, and every function has a frame

A copy under D207 was one level deep: the oracle's bodies were lowered without an
oracle, so a callee inlined into a callee was called from the copy. Now the oracle
is built twice. The first pass is as before; the second is lowered against the
first, so its bodies hold one level of copies, and what the program copies from it
is two levels deep -- `leaf.add` inside `mid.twice` inside `main`. Each pass records,
per copying function, the callees it copied, and a copy carries the refs of the body
it copies along to its caller, so the artifact of the module two copies up has a
body edge to the leaf and an edit to the leaf's body rebuilds it; the edge stays one
per module and callee, the writer folding what the per-function records repeat. A
copied instruction keeps the path it was stamped with, so a trap inside the inner
copy names the leaf's file. Two more things the fixture found. The backtrace looked a
return address up as it stood, and a trap that ends a function returns to the
function's end, which no half-open range holds, so `unreachable()` as the last
statement had no backtrace at all; the walk now looks up the byte before, the call
itself, and the line rows are searched from the call's offset -- the frame's line was
the function's last row before, which `link/trap_backtrace` had pinned as line 18
where the call is on 16. And a function with no stack slots had no frame, so when it
called it was no frame in the chain and its caller was skipped: every function has
one now, a push, a move and a leave, which also puts the stack where the ABI wants
it at the calls such a function makes.

## D213 — The artifact path at the compiler's own size

`emit-em-all` over the compiler's 31 modules took 4 m 49 s, and `--incremental` over
the result 6 m 45 s, against 8 s for the executable, so the artifact path existed
for fixtures alone. A sampled profile put nearly all of it in `artifact_hash.xor`, a
sixty-four-iteration bit loop from before `^` existed, under the CRC that every
artifact reader ran over the whole artifact on every call -- three hundred loop
iterations a byte, and the edge walk called a reader per edge over five-megabyte
artifacts while widening the target artifact per edge as well. Now `xor` is `^`;
`validate` keeps the checksum but is called once, where an artifact is loaded and
where one is written, and the readers check the layout alone; the edge walk widens a
target once per dependent module; the string table under the writer has a hash
index; and the artifact and scratch buffers grew to eight and four mebibytes, since
`main.em` alone is 2.7 MB. The compiler's artifacts are byte-identical to before,
`emit-em-all` takes 23 s, the incremental decision 5 s, and `link-em` links the
compiler in 6 s -- the linked compiler passes its self-test, though it is not yet
byte-equal to the source-linked one, which the fixtures are: a function order
difference to find under the determinism row.

## D214 — The edge rule is settled before lowering, and a kept module is not compiled

D205's `--incremental` compiled every module and skipped only the writes, because the
edge rule compared old edges against fresh artifacts, and a fresh artifact needed the
module lowered and selected. Two changes make the decision independent of lowering.
A declaration's body hash is over its tokens whenever it has a source range -- what
generic templates already used -- rather than over its NIR, so it is the same whether
or not the function was lowered; NIR remains the hash of a function with no source of
its own. And the Interface a module's artifact would carry is written from the checker
alone, as an artifact of its Strings and Interface sections, which the same
`dependency_matches` reads. So after checking, every module's fresh Interface is
written, each old artifact on disk is loaded once and its edges walked against them,
and the modules that pass are marked kept before anything is lowered; the rest are
lowered, selected and written, the kept ones not at all. For that to be sound the
artifacts had to stop depending on what else was in the build: `emit-em-all` now
lowers every module of the graph in graph order and an artifact holds the whole
module, where before both `.em` paths pruned to what `main` reached -- the linker
that consumes the artifacts prunes, as `emit-executable` still does, and a program
linked from whole artifacts is byte-identical to one compiled from source. Over the
compiler's 31 modules a build with nothing changed takes 10 s against 34 s for a full
one, a body edit in `decimal` rebuilds `decimal` alone in 13 s, and the linked result
of either is byte-equal to a clean build. D213's finding that the compiler's own link
was not byte-equal to the source build was the artifacts' order on the command line:
`link-em` lays functions out in the order the artifacts are given, and the graph's
order reproduces the source build exactly.

## D215 — Registered diagnostic codes for the graph, the scanner and the command line

docs/diagnostics.md registers thirty codes and the compiler emitted seven of them,
with a missing module surfacing as `error: project.ModuleNotFound` from `main`'s own
failure line and a byte the scanner refused as `unexpected` under E-SYNTAX-9999. Now
the graph records the importing module and the name when a `use` resolves to nothing,
to two roots, or closes a cycle, and the driver reports E-MODULE-0001 or 0002 at that
module; an `Invalid` token is a lexical error under E-LEX-0001, 0002 or 0003 by the
byte it starts at -- past 127, a control character or tab, or a quote, digit or `r`
prefix the scanner could not finish -- since the scanner stops at the first byte it
cannot take; an empty or unknown command line is E-CLI-9999 on stderr with exit 1
rather than the usage on stdout with exit 0; and the checker's kinds for a
reflection shape are E-COMPTIME-9999 and the atomic ones E-MEM-9999, the registry's
own categories for sections 9 and 8 -- a constant cycle stays E-TYPE-9999, since the
bootstrap says so and tests/neper0 holds the two compilers to the same words, and a
`use` that resolves to more than one variant is E-MODULE-9999. Eighteen of the thirty are emitted;
the rest name subjects -- the formatter, tests, the GPU profile, the tooling
protocol -- that do not exist yet to diagnose.

## D216 — `when` over the target namespace

Section 6's conditional compilation parsed and went no further: the checker and
lowering had no case for a `WhenStmt`, and `target` resolved to nothing. Now a
`when` condition is a question about the target -- `target.arch` or `target.os`
compared with a member of `target.Arch` or `target.Os` with `==` or `!=`, on either
side, under `!`, `&&`, `||` and parentheses -- which the checker settles from the
graph's target; the resolver does not descend into the condition, since `target` is
no declaration; both blocks type check, as the section says, so a dead configuration
cannot rot; and lowering asks the same question and emits the taken block alone, as
the settled `if` of D138 does. A condition of any other shape is refused under
E-COMPTIME-9999, naming the shape that is allowed. `target.arch` and `target.os` as
values outside a `when` condition -- section 2's namespace in full -- would want an
enum value the checker can type, and every use so far is a `when`, so they wait.

## D217 — The debug fills

Section 11's two fills existed in neither mode. Now the runtime has a second entry
point for each: `neper_mem_alloc_fill` allocates and then writes 0xCD over every
byte it hands out, and `neper_mem_reset_fill` writes 0xDD over what a reset gives
back before it moves the offset; a debug build's lowering names those, a release
build's the plain ones, and since the fills are not checks `@nocheck` does not touch
them -- which is why the builder carries a `release` flag beside `nocheck`, which a
`@nocheck` block sets for its own extent. The fill entry points sit after the plain
ones in the runtime source, so a release image that reaches only the plain ones is
cut before them, and both call the plain one under a local name: on ELF a call to a
global symbol is a relocation the embedding does not apply, and the first attempt
called the next instruction. link/debug_fills reads a fresh allocation, a reset's
memory and the allocation that reuses it in both builds.

## D218 — A `const` initialiser may call a function

Section 9's interpreter evaluates four sites, and this compiler folded integer
constant expressions and settled a `meta` question in an `if`; a call in a `const`
initialiser was `InvalidConstant`. Now it is a `Call` constant expression, and the
checker evaluates it by walking the callee's syntax tree: integer and bool values in
locals, `let`/`var`, assignment and the compound forms, `if`/`else`, `while`,
`break`/`continue`, `ret`, the arithmetic, bitwise, shift, comparison and logical
operators with the same typing the folder uses, `!`, `-`, `~`, parentheses, a checked
cast, module-scope constants, and calls to other such functions in the same module
or a qualified one -- under the section's ten-million-step budget, and a call depth of
sixty-four, since a frame is host stack. Anything else, and every reach into runtime
state, is refused under E-COMPTIME-9999 naming the constant and what it reached. The
callee's module is parsed and tokenized once into storage of its own and kept,
because the graph's node storage holds the tree of the module being checked and a
call chain may cross modules and return; the callee's tokens stand in for the
caller's while its body runs. A constant that calls is evaluated once the program's
signatures are collected, rather than with the other constants before them, so one
used in a type or another module-scope declaration is refused with a reason. What
the interpreter does not have is memory: arrays, structs, slices and the arena the
section describes; nor does it run `[...]` arguments or `when` conditions, and a
`const` is still an integer.

## D219 — A call in an array length or a `[...]` argument

The length evaluator that array types and comptime arguments go through had one
call it accepted, `meta.array_len`. Any other call now goes to D218's interpreter
the way one in a `const` does: the expression is copied into the constant table for
the evaluation and the table's count restored after, since nothing keeps the index
and an instance-heavy program evaluates the same length many times.
`count_primes(20usize)` is a `[...]` argument and `count_primes(30usize)` an array
length in link/comptime_call; the argument's type has to be the parameter's, as any
comptime argument's does.

## D220 — A `when` condition through the interpreter

Section 9 names every `when` condition as one of the interpreter's four sites, and
D216 took the target questions alone. A condition of any other shape now goes to
D218's interpreter over the module's own tree with no locals in scope, and has to
come back a bool: `when LEVEL > 2i64 && enabled(LEVEL)` is settled by the constant
and the call. One it cannot evaluate -- a local, which is runtime state -- is
refused under E-COMPTIME-9999 saying what it reached, in place of D216's report of
the shape allowed.

## D221 — Array locals and `for` over a range in the interpreter

D218's frame held scalars. It now holds cells as well: `var t: [N]u8 = zero` binds
an array local whose element type is an integer or bool and whose length the
length evaluator settles, over a run of zeroed cells in the frame; `t[i]` reads and
writes a cell with the bounds check section 11 would apply at run time, `t.len` is
the length, the compound assignments work on a cell, and the cells go with their
scope as the locals do. `for i in a..b` binds the counter and steps it. `zero` turned
out to be a token of the binding statement rather than a node, which a scalar
binding of `zero` now also takes. An array does not cross a call: it is the frame's,
and a slice of it would be the interpreter memory the section describes. A sieve in
link/comptime_call counts the primes below sixty-four at compile time and at run
time and finds them equal.

## D222 — Bool constants, and a calling constant put off rather than refused

A `const` was an integer. It may be a bool now: `true` and `false`, a comparison of
two constants, `&&`, `||` and `!`, and a call the interpreter runs -- the folder
evaluates the comparison and the logical pair as bools, and lowering emits the bit.
And D218's rule that a constant which calls waits for the signatures reached only
the constant whose initialiser was the call; one that reached a call through another
constant was evaluated early and refused. The early pass now evaluates every
constant and treats reaching a call before the signatures as putting the constant
off -- back to unevaluated, no report -- and the pass after the signatures settles
what is left. A type that asks for such a constant before the signatures is refused
at the length that asked, under E-COMPTIME-9999, saying why. link/comptime_call
carries three bool constants; check/comptime_call_in_type pins the refusal.

## D223 — `target.arch` and `target.os` as values

D216 knew the target namespace inside a `when` condition alone. Section 2 makes it
a namespace usable anywhere, with `target.arch` a `target.Arch` and `target.os` a
`target.Os`. The two enums are seeded into the root module under the names
`target.Arch` and `target.Os`, which no source can spell as an identifier and which
print as the section writes them; `target.arch` and `target.os` type as values of
them in the checker and lower to the current target's member as a constant, the
qualified type names resolve to them, and the resolver treats `target` as no
declaration in both positions. So a member literal compares against them, a
`switch` over `target.os` is exhaustive over the four members, and the value is
held and passed like any enum. The two are the language's, not declarations of
the root module, so no artifact Interface carries them. link/when_target does all
of that on both platforms.

## D224 — The kept modules' bodies are not checked, and the checksum is table-driven

D214 decided the kept modules before lowering, after the whole program was checked.
The checker now runs in two halves -- the declarations, which are all the edge rule
needs, and the bodies -- and the incremental build settles the rule between them, so
a kept module's bodies are not checked: they were when its artifact was written, and
the instances of its templates that other modules use are checked as instances
regardless. The checksum over every artifact loaded was a bit loop, eight steps a
byte; it is a table now, built per call. A build of the compiler with nothing
changed takes 4 s against the 10 s of D214, and what remains is reading and widening
every artifact to decide, and the declarations of every module.

## D225 — `emit-executable --arena SIZE`

Section 5 sizes the root arena by `--arena`, and the bootstrap's `build` took it,
which is how the bootstrap-built compiler has a gibibyte; a self-hosted executable
had the runtime's 512 MiB and no way to ask for more, and a release build of the
compiler needs more -- two oracles and a machine buffer of eight bytes a byte. Now
`emit-executable` takes `--arena` with k, m or g, from a mebibyte up, in any order
with `--release`. The PE runtime keeps the size as a word, `neper_arena_size`,
right after the entry, which the entry, the arena's capacity and the growth check
all read; the linker patches it by symbol as it does a procedure, and the runtime's
floor is one procedure longer. The ELF startup stub carries the size as four
immediates the linker patches at their offsets, and refuses a size a signed 32-bit
immediate cannot hold. A self-hosted compiler built with `--arena 1g` compiles the
compiler in release in 27 s; link/arena_size pins an arena of eight mebibytes
refusing twelve on both platforms.

## D226 — A call saves the live registers alone

Every call site stored the five allocated registers to their preserve slots before
the call and reloaded all five after, whatever they held. The allocator's live
ranges say which of them hold a value defined before the call and used after it,
and only those are saved and restored now -- one pass over the function's values
per call, a bit per register. A value the call itself defines, and one whose last
use is an argument of it, need nothing. The other sites that preserve registers --
a trap record, a fixed-register divide or multiply, an atomic -- are as they were.
The compiler's own image is seven per cent smaller; its speed could not be measured
on a loaded machine, and the suites, which compile the compiler with itself twice
and compare, pass on both platforms.

## D227 — `tokens --json` and `parse --json`, and the first of the conformance corpus

docs/tooling.md's machine protocol had nothing behind it. `src/tool.e` now writes
the version 1 stream for the two syntactic commands: the header line, one `token`
record per token -- the registry kind, the lexeme, the span with both column forms,
and the leading trivia as `space`, `comment` and `bom` items with their own spans --
a `diagnostic` before each `INVALID` token, whose lexeme is the base64 object since
its bytes are not UTF-8, and for `parse` one `syntax` record whose root lists the
top-level nodes with kind, span, token range and ordered `{node}`/`{token}` children,
then the `result` with the exit status. The lexer already knew everything the
records need -- the trivia scanner, the UTF-16 columns, the maximal subparts of
invalid input -- so the module is serialisation, with each record built in one
buffer and written whole. Every record validates against the schema, the trivia
and lexemes concatenate back to every byte of the compiler's own sources, and
tests/conformance holds the first fixtures with byte-exact expected streams --
every token kind but `INVALID` in one file, a hostile one with a BOM, CRLF, a tab,
unterminated literals and invalid UTF-8 inside a comment, and a parse that stops --
which both suites compare. The corpus is marked binary in .gitattributes, since its
bytes are the point. Stdin, recovery past the first syntax error and the other
commands are not there.

## D228 — `check-file --json`, through one diagnostic emitter

Every diagnostic printer in the driver wrote its own `path:line:col: error[CODE]:
message` line to stderr. They now compose the message into a capture and hand
path, token, code and message to one emitter, which writes that line or, under
`--json`, docs/tooling.md's `diagnostic` record with the span from the token and the
source as an operand named by the file's basename; the sink the text goes to
carries the mode, and every printer takes it, so a command decides once. `check-file
... --json` emits the header, the records of every error the front end reports --
lexical, syntax, module, resolution, checking -- an unreadable operand as a
location-free E-CLI-9999 with exit 2, and the result, with stderr empty. Every
record validates against the schema, and tests/conformance gains accept/ and
reject/ with five streams both suites compare byte for byte; the target named on
the command line does not appear in them, so one expectation serves both
platforms. Notes and fixes, project roots and the project-level `check` are not
here.

## D229 — `info --json` is the capability query, pinned per host

`neper-self info --json` emits the section 1 header, one `info` record and a
successful result: the tool version, one language profile (`0.1`, grammar revision
1, stream version 1, not experimental), the commands whose streams exist (`check`,
`info`, `parse`, `tokens`), the host target, the two build targets, and the CPU
levels the emitter honours -- `x64-v1` alone, since nothing above SSE2 is selected
and SIMD lowers as lane loops -- every collection sorted by bytes as the section
requires; `features` is empty until a feature exists to name. The host is probed
from the standard-handle value (a Linux fd is 2, a Windows HANDLE never is) until the
runtime has a host intrinsic. Because the host differs, tests/conformance/tools/
holds one expected stream per host, `info.x64-linux` and `info.x64-windows`, and
each suite compares its own byte for byte. `--language-version` and the other CPU
levels of the spec's table are not here.

## D230 — `emit-executable --json` is the build stream

With `--json` as a trailing flag, `emit-executable` writes the section 1 header
with command `build` to stdout, every diagnostic of the build as a `diagnostic`
record -- the lowering, code-selection and error-table printers, which still wrote
bare lines, now go through the one emitter of D228 so no stream ever carries one --
and a result last: on success `data.executable` is the output path exactly as it
was given, on any failure the diagnostic count with exit 1, and an operand that is
not a module is `E-CLI-9999` with exit 2, as `check-file` has it. The conformance
corpus pins both a program that builds and one that is rejected, run from the suite's
build directory so the executable's name is the same on both hosts. The build
manifest, the `--target`/`-o` spellings and a project root as operand are not here.
The corpus's empty program found a startup bug: both hosts exit with `eax != 0`
after `main` returns, so a void `main` exited with whatever its body left in eax --
0 from one shell, 1 from another. The entry's empty return now zeroes eax.

## D231 — `run --json` builds then launches, capturing the whole output

`run` takes `emit-executable`'s build path and, once the executable is written,
launches it with its stdout and stderr redirected to two files beside it, waits, and
reads them back whole into one `run` record -- `process_exit_code`, `stdout`,
`stderr` and a null `trap` -- before the result. Captured bytes follow section 2: a
JSON string when valid UTF-8, `{encoding:base64,data:...}` otherwise, which
tests/conformance/tools/run.e exercises by writing a non-UTF-8 byte to stderr and
exiting 3. A bare output name is launched as `./name`, not searched on PATH. The
fixed os surface creates files 0666 and has no chmod, so on Linux the child goes
through `sh -c 'chmod +x -- "$0" && exec "$0"'`; drop that when emit-executable can
write an executable bit. Streaming, the structured trap payload of a crash, `-- ARGS`
and a project root are not here.

## D232 -- `index --json` names the module and its declarations

`index-file` builds the graph and runs the resolver, then emits a `symbol` record
for the operand module and, in source order, each of its module-scope declarations,
which the resolver already holds: `fn`, `extern`, `type`, `const`, `module_var` and
`error`, mapped one-to-one onto section 5's closed `kind`. Each carries its id (the
module is id 0, so every declaration's `container_id` is 0), qualified name, the full
declaration span and the name's selection span, empty attributes and null
signature/documentation; the stream ends with the symbol count and zero references.
The resolver carries neither locals, parameters, fields, enum/union members and
intrinsics, nor any reference with its role and concrete target, so those are the
gap. The golden names no target, so one expected stream serves both hosts.

## D233 -- `dis --json` lists each function's bytes

`dis-file` runs the same codegen pipeline as `emit-executable` and, after call
resolution, emits one `disassembly` record per emitted function: its
`module.function` symbol, the target triple, and `text` -- the function's machine
bytes as space-separated lowercase hex, a faithful listing of what code selection
produced. The stream ends with the function count. Only functions the program
reaches are emitted, since dead-function elimination has already run. The bytes and
target depend on the ABI, so the corpus holds one expected stream per host, generated
by cross-targeting from one build. Mnemonic (AT&T or Intel) disassembly rather than a
hex byte listing is the gap.

## D234 -- `fmt --json` emits the canonical layout

`fmt-file` tokenizes the source and re-emits it in canonical layout: four-space
indent by brace depth, one space around binary and assignment operators and after
comma and colon, no space inside delimiters or around `.` and `..` or before a call
or index list, slice and array element types and prefix operators glued to their
neighbour, comments preserved (a trailing comment one space past the code, a
standalone comment at the line's indent), runs of blank lines collapsed to one with
none surviving at a block edge, and a single final newline. It is a reindent-and-
respace pass over the token and trivia stream, which is enough because neper is
one-statement-per-line; prefix versus binary `-`/`*`/`&` is told apart by whether the
previous token ends a value. tests/conformance/tools/fmt.e is already in canonical
form, so the golden -- one `formatted` record -- also pins idempotence, and names no
target so one stream serves both hosts. Gaps: wrapping a list past 100 columns,
joining an empty block to `{}` or `}`..`else`, sorting `use` and attributes,
minimizing raw-string delimiters, and the `--check` and stdin spellings.

## D235 -- The allocator's pool is ten registers, five of them callee-saved

The allocator had five registers, rax, rcx, rdx, r8 and r9, all of which a call
clobbers, so a value live across a call was saved and reloaded at every call and a
function with more than five values live at once spilled the rest. The pool is ten
now: rbx, r12, r13, r14 and r15 follow the first five, and the first free index wins,
so a function that fits in five is as it was. The callee-saved five cost one store
at the entry and one load before each return, in slots of their own between the
preserve area and the call area -- the call area has to stay at the bottom of the
frame -- and only for the registers the function's values actually reached; the live
mask that D226 saves around a call considers the first five alone, since a callee
keeps the others, and a fixed-register sequence reads a value in one of them where it
is rather than from the preserve area. The emitter had refused rsp, rbp, r12 and r13
as a base with no displacement, which the mod 00 row cannot spell; the first pair is
a SIB byte naming itself, the second a zero eight-bit displacement. The runtime's
routines were checked for the five: only `neper_trap` writes them, and it does not
return. Measured on `e.fmt.json` over the standard files, best of four interleaved
against the previous compiler: one to nine per cent faster, and a byte-counting
loop fifteen; the compiler's image is three per cent larger for the saves. The
larger cost stays where it was: a `var` is a stack object, every use of it a load or
a store through its address, so a loop counter is a chain through memory. That is
the next change, and it is the register allocator's rather than a pass of its own.
## D236 -- A scalar local is a value, and a loop's temporaries are its own

Lowering makes every `var` a stack object, read and written through its address at
every use, so a loop counter was a chain through memory -- a store, then the next
iteration's load waiting on it -- and a byte loop cost thirteen cycles a byte. The
allocator promotes them now, before it builds its ranges: a `Stack` of a scalar kind
whose address reaches nothing but `Load`, `Store` and `Zero` of that slot, all at
one width, is one value numbered as the local -- the `Stack` becomes a zero value,
each `Store` a `Bitcast` that defines the number again, a `Zero` the zero value, and
each `Load` a `Bitcast` that copies it. A value defined more than once is what the
ranges allow since: one range from the first definition to the last use, which is
what a variable in a register has always been. A use of what a load read, in the
load's own block and before the next definition, reads the local itself, and a load
whose uses were all redirected is a bitcast nothing reads, which selection leaves
out; a use in another block keeps the copy, since a store may lie on a path to it.
The order matters: the accesses are rewritten first, while the address still tells a
store to the local from a store through a pointer the local holds -- redirecting the
loads first made the two the same and a release build of `link/trap_null` wrote
through the wrong one. Two more things the pass exposed. The back-edge rule extended
every value defined inside a loop and used inside it to the loop's end, so a loop's
temporaries all shared one live range and the tenth of them spilled the rest; a value
is live across the edge only when it was defined before the loop's head. And every
fixed-register sequence -- an index address, a slice, a copy, a shift, a divide, an
atomic -- saved and restored all five caller-saved registers around itself; each now
saves only the ones it clobbers that hold a value live across it (a slice adds the
ones its operands sit in, which it reads back from the preserve area), and an index
address without its check clobbers nothing. The copy's clobbers were rax and r9, not
rcx: the emitter copies with a byte loop, not `rep movs`. Measured on `e.fmt.json`
over the standard files, best of three interleaved against D235: gsoc-2018 twice as
fast, citm_catalog 1.45, twitter 1.36, the number-heavy files 1.1 to 1.25; the
byte-counting loop 2.4 times.

## D237 -- Fused compare-and-branch, fall-through, and short immediates

Three peepholes the promoted locals of D236 made worth having. A comparison whose one
use is the `BranchIf` immediately after it no longer materialises a bool: the `cmp`
sets the flags, the branch is a single conditional jump on the condition the compare
computed, and neither a `set` of a register nor a `test` of it is emitted. Selection
recognises it from the ranges -- the comparison's value defined at the compare and
last used one instruction later, by a branch that reads it -- and carries the
condition to the branch on the context. A branch, conditional or not, to the block
that is next in code order is dropped, since the fall-through reaches it anyway. And
`mov` of an integer constant under 2^32 is the five-byte `mov r32, imm32`, which
zero-extends to the full register, rather than the ten-byte `mov r64, imm64`; a wider
value still takes the long form. Measured on `e.fmt.json` over the standard files,
best of three interleaved against D235: gsoc-2018 2.3 times, citm_catalog and canada
1.6 to 1.8, twitter 1.6, the number-heavy files about 1.5; a byte-counting loop 3.3
times. The `dis --json` conformance corpus, which pins emitted bytes per host, is
regenerated for both. The codegen self-test's branch case had never given its own
function its own live ranges -- it shared the previous function's -- which the
fusion check exposed; it does now, and the branch pin asserts the fused shape (a
`cmp`, a signed conditional jump, a trailing `ret`) rather than an exact length.

## D238 -- `build-manifest --json` and a SHA-256 in the compiler

`build-manifest-file PATH ROOT ARCH OS --json` loads the graph and emits the canonical
`neper-build-manifest` object of section 7: schema and version, the tool, language and
grammar versions, the target triple, the mode, the root module, and one `inputs` entry
per source module with its source identifier and the SHA-256 of its bytes. SHA-256 is
ported into artifact_hash.e alongside xxhash/CRC, over the same one-byte-per-`usize`
representation, all arithmetic on `usize` masked to 32 bits so the bootstrap needs no
`u32` type or wrapping operator; its digest of the fixture matches python's hashlib and
the RFC 6234 `abc` vector. The `target` field makes the manifest host-specific, so the
corpus holds one expected object per host over a no-import fixture. Gaps: the dependency
interface/body split, libraries, assets, the built artifact's own hash, non-empty
options, and writing the manifest to `.neper/<mode>/build-manifest.json` on every build
rather than only through this query.

## D239 -- `@reorder`, an opt-in that packs a struct by alignment (planned, low priority)

The struct default is unchanged and stays as §4 fixes it: fields are laid out in
declaration order with natural alignment, which is C's layout. That default is
load-bearing and must not be flipped -- FFI is annotation-free precisely because a
neper struct already *is* its C counterpart (§4, "§4's struct layout is C's"), the
bootstrap runtime writes multi-field results at fixed offsets matching declaration
order (`neper_os_clock` puts the value at 0 and the err at 8, `bootstrap/runtime.c`),
and host/device structs share a defined layout for `@gpu` (SPIR-V scalarBlockLayout).
An opt-out that reordered by default would turn every one of those into a silent ABI
break whenever the author forgot the annotation.

So the safe polarity is opt-in. `@reorder` is a new declaration attribute, legal only
on a `type ... = struct` or `type ... = union`, that lets the compiler sort the fields
to minimise padding. The sort key is **alignment**, descending, not size -- the two
differ for nested aggregates, `f80`/`long double`-shaped types and vectors -- with
declaration order breaking ties, so the chosen layout is a single deterministic
function of the type. Determinism is required, not incidental: neper promises
reproducible builds and a frozen `.em`/ABI, so the reordering is specified and stable,
never the "unspecified, may change between versions" freedom Rust's default layout
takes.

Boundaries are a compile error, not a footgun. `@reorder` is illegal on any struct
that crosses an FFI boundary -- used in an `extern`/`@import`/`@cc` signature -- or is
shared with a `@gpu` kernel or device buffer; the checker rejects it at the crossing
site, the same way §4 already makes `@packed`/`@align(N)` require an explicitly
matching C declaration to cross. `@reorder` is mutually exclusive with `@packed`
(packed already gives every field alignment one, so there is no padding to remove) and
composes with `@align(N)` (reorder first, then raise the aggregate alignment and tail
padding). Reflection still iterates fields in declaration order but reports each
field's true reordered offset, so `e.meta` continues to expose the actual layout.

Not started; this sits at the end of the backlog. When built: a `@reorder` attribute
node on the aggregate, an alignment-sort in the layout pass that assigns offsets, the
boundary-crossing rejection in the checker, and a fixture proving `size_of` shrinks
for a reordered internal struct while an FFI/`@gpu` use is refused.

## D240 -- `test --json` runs each @test in its own process

`test-file PATH ROOT ARCH OS WORKDIR --json` discovers the operand's `@test` functions
-- an `@test` attribute node followed by a top-level `fn` -- in source order, generates a
runner that is the operand verbatim plus a `main` dispatching to the test named by its
argv index, and compiles that runner by spawning the compiler again (`args[0]`), so no
lowering pipeline is duplicated. Each test then runs in its **own process**, because a
neper trap aborts: a process that exits 0 is `passed`, one whose stderr begins `error: `
(the runtime's print for a returned err) is `failed`, and anything else -- a trap -- is
`crashed`. The stream is section 7's: the header, one buffered `test` record per function
in source order, a `test_summary`, and a result that exits 1 if any test is not passed.
The target never appears in the stream, so one golden serves both hosts; the runner and
its per-test output land in WORKDIR, out of the source tree. `duration_ms` is 0 and no
test times out yet -- real timing, the `timeout_s` outcome, the structured `trap` payload
(stderr still carries a crash's raw text), an operand that defines its own `main`, and
project-wide discovery are the gaps.

## D241 -- `e.time.cron`, a cron-expression parser and next-fire clock (planned)

A small module over `e.time` that parses a cron expression into a `Schedule` and
answers "when does this next fire". It is a parser plus a clock, not a scheduler --
running the job is the caller's concern; the module only turns an expression and a
`time.Timestamp` into the next matching `time.Timestamp`. Planned, unimplemented;
this section is the contract.

### Two flavours, detected by field count

Whitespace-split the expression:

- one token beginning with `@` -- a named shortcut (below);
- five fields -- `minute hour day-of-month month day-of-week`, with seconds fixed
  to `{0}` (classic Vixie cron);
- six fields -- `second minute hour day-of-month month day-of-week` (the seconds
  flavour, as Quartz/node-cron write it, seconds first);
- any other count -- `E-CRON` parse error.

So the seconds flavour is just a six-field expression; no mode flag, the count
decides. Ranges are: second/minute 0-59, hour 0-23, day-of-month 1-31, month 1-12
(or `JAN`-`DEC`), day-of-week 0-6 (or `SUN`-`SAT`), with both `0` and `7` meaning
Sunday.

### Per-field grammar

Each field is `*`, or a comma list of items; an item is `N`, `N-M` (range), `*/S`
or `N-M/S` (step), or `N/S` (Vixie shorthand for `N-max/S`). Month and day-of-week
accept case-insensitive three-letter names, including in ranges (`MON-FRI`); names
resolve to numbers before the range expands. Each field lowers to a bitset:
`seconds`/`minutes` as `u64`, `hours`/`doms` as `u32`, `months` as `u16`, `dows`
as `u8`, plus a `dom_restricted`/`dow_restricted` flag recording whether that field
was anything other than `*`.

Named shortcuts expand to five-field forms: `@yearly`/`@annually` = `0 0 1 1 *`,
`@monthly` = `0 0 1 * *`, `@weekly` = `0 0 * * 0`, `@daily`/`@midnight` =
`0 0 * * *`, `@hourly` = `0 * * * *`. `@reboot` is rejected -- it has no wall-clock
meaning, so a scheduler must handle it out of band.

### The day-of-month / day-of-week OR rule

The one semantic trap, kept faithful to Vixie: when **both** day fields are
restricted the instant matches if the day-of-month **or** the day-of-week matches;
when only one is restricted that field alone gates the day; when neither is (both
`*`) any day passes. `0 0 13 * 5` therefore fires every 13th and every Friday, not
only Friday the 13th. Day-of-week is derived from `time.days_from_civil` as
`floor_mod(days + 4, 7)` (epoch day 0, 1970-01-01, is a Thursday, and Sunday is 0).

### Surface

    type Schedule = struct { ... bitsets and the two restricted flags, plus the
                             offset_minutes the schedule is read in ... }

    fn parse(a: *mem.Arena, expr: str, offset_minutes: i32) -> (Schedule, err)
    fn matches(s: Schedule, t: time.Timestamp) -> bool
    fn next(s: Schedule, after: time.Timestamp) -> (time.Timestamp, err)

`parse` carries a fixed UTC offset because a cron expression names a wall clock;
`matches` decomposes `t` with `time.to_date_at`/`time.to_time_at` at that offset and
tests the six bitsets under the day rule; `next` returns the first match strictly
after `after`. `next` steps field-coarsely -- it advances to the next candidate
month, then day, then hour/minute/second, skipping whole non-matching ranges rather
than scanning per second, so a yearly schedule costs a handful of steps, not 31
million. Termination is guaranteed by a five-year horizon: an unsatisfiable
expression (`0 0 30 2 *`, Feb 30) returns `E-CRON` rather than looping.

### Out of scope for a first cut

DST and timezone-rule transitions beyond the fixed `offset_minutes` (a schedule that
must survive a DST jump is a gap, not a guarantee); `@reboot`; the Quartz `L` / `W` /
`#` / `?` extensions and its seventh year field. It builds on nothing new -- `e.time`
already supplies civil-time conversion and the epoch weekday -- so it is blocked only
on being wanted, and sits at the end of the module backlog.

## D242 -- A test carries its real wall time

Each `test` record and the `test_summary` now report a real `duration_ms` instead of 0:
the driver reads `os.clock(.Monotonic)` around each child run and around the whole loop,
in nanoseconds, and divides to milliseconds. Timing makes the stream non-deterministic,
so the conformance golden keeps `duration_ms` at 0 and both suites normalise the field
to 0 before the byte-exact compare -- the standard way to golden test-runner output. The
`timeout_s` outcome (killing a test that runs too long) still needs a timer against a
blocking `os.wait` and is not here; `duration_ms` is the wall time actually observed.

## D243 -- `e.grep`, a dependency-free code scanner (planned)

Registered as a planned experimental module against my own earlier advice: for
interactive use `rg`/`tgrep` are faster and already indexed, and the compiler's
own `index-file`/`parse`/`graph` JSON commands already answer structured
"where is this symbol" questions that plain text search cannot. `e.grep` earns
its place only in the one spot those do not cover -- a self-hosted neper tool
that must scan a tree for a literal or simple pattern with no external binary on
the path, e.g. an LLM-facing code-scan built entirely in neper.

Surface (see module-apis.md): a `Match` of path/line/column/text, an `Index`, and
`build_index`, `search`, `search_index`. `search` walks the tree under `root`
(via `e.fs`/`e.path`) and returns matches; `search_index` answers from a prebuilt
trigram `Index` the way tgrep does, trading build time for query speed on repeat
scans. First cut is literal and simple character-class patterns; full regex waits
on `e.text.regex`, and .gitignore semantics, mmap and ranked output are out of
scope. It sits in the experimental tier at the end of the backlog, blocked only
on being wanted.

## D244 -- `fmt --check` reports E-FORMAT-0001

`fmt-file PATH --check --json` formats the source and compares it to the original: when
they match it emits the header and a passing result and exits 0, and when they differ it
emits an `E-FORMAT-0001` diagnostic -- "source is not in canonical layout" -- whose span
is the first byte that differs, with its one-based line and column from a scan of the
original, then a failing result and exit 1. This is tooling §6's `--check` and the first
emission of the registered `E-FORMAT-0001` code. The corpus pins a non-canonical fixture
(the diagnostic and exit 1) and runs the check over the canonical `fmt.e` (exit 0); both
are target-independent. Writing the formatted source to stdout with `-` and the `fmt`
row's other gaps are unchanged.

## D245 -- `else if` lowers as the nested `if` it is

The grammar has always had the chained form -- `if_stmt = if expression block (else (if
expression block | block))?` -- and the parser and checker accepted it, but lowering only
took a `Block` as an else branch and refused an `IfStmt` there with "construct is not
implemented in self-hosted lowering". `lower_if` now accepts an `IfStmt` as the else
branch and lowers it by recursing into itself, so a chain is the nested `if` it already
was to the checker: no extra block or merge of its own, and `break`/`continue`/`ret`
inside any arm behave as they do in a plain nested `if`. link/else_if pins chains that
return from every arm, fall through to a shared merge inside a loop with `break` and
`continue`, and an open-ended chain with no final `else`.

Two findings from the generation benchmark that prompted this. `else if` is not a token
saving -- the nested form and the chain tokenize identically -- but it removes a real
trap: a model writing the natural `} else if` got a baffling lowering error. And the
failure that looked like `printf` breaking under `else if` was not the compiler at all:
`build/lib/e/` holds a stale partial copy of the library (`io.e`, `os.e`, no `str.e`), and
project-root discovery walking up from an operand under `build/` selects it, so `e.str`
never enters the graph. Compile nothing from under `build/`; the benchmark's tasks live
under `benchmarks/` for that reason.

## D246 -- A test that outruns its deadline is ended from inside

`test-file PATH ROOT ARCH OS WORKDIR [TIMEOUT_MS] --json` reports the fourth outcome,
`timeout`. The driver cannot enforce it: the fixed `e.os` surface gives it neither a
kill nor a wait with a deadline, so a hung child would block `os.wait` forever. The
deadline is therefore enforced from inside the child. The generated runner carries a
watchdog thread that blocks on `os.wait_u32(&guard.done, 0u32, TIMEOUT_NS)` -- the
futex wait is the one primitive in the surface that takes a deadline -- and, when that
returns `os.Timeout` rather than a wake, calls `os.exit(124)`. Main signals the futex
the moment the test returns, so the watchdog only fires on a test that is still
running. The driver maps exit 124 to `timeout`, ahead of the crash case, and reports
the deadline in `timeout_s`; the default is a minute and `TIMEOUT_MS` overrides it.

Two shapes were forced by the compiler. The runner imports `e.os` and `e.atomic` under
unique aliases (`nptest_os`, `nptest_atomic`), because a second plain `use e.os` beside
the operand's own is `graph.DuplicateQualifier` while a distinct qualifier for the same
module is legal -- so the watchdog needs no knowledge of what the operand imports. And
the dispatch chain moved into its own function, leaving `main` a single `ret`: an early
return plus an N-way chain plus the watchdog put `main` past what lowering would take.

The Linux half needed a runtime fix. `os.exit` lowered to syscall 60, `exit`, which
ends only the calling thread; the watchdog therefore killed itself and left the hung
test running, which is how a suite run first hung rather than reporting a timeout. It
is now `exit_group` (231), so section 8's exit ends the program from any thread, as
`ExitProcess` already did on Windows. A thread that merely finishes still leaves by
syscall 60 in the clone trampoline, which is a different site. The instruction is the
same length, so no runtime offset moved.

A note on where the runner may live, which cost real time to find. A project's `lib/`
shadows the toolchain's `e.*` by design (§2), and `build/lib/e/os.e` is a stale copy
from an older bootstrap that predates `type Thread`. A runner written under `build/`
therefore binds `e.os` to a surface with no `Thread`, and the call type checks -- the
interception fabricates the named type without asking whether the module declares it --
and only fails in lowering as "cannot lower `main`". WORKDIR must be a directory whose
project root is the real one; the suites pass their own `build/<host>/tests/selfhost`,
which carries the current copy. That the checker fabricates a type it never verifies is
a defect of its own, and is left recorded here rather than fixed in this change.

## D247 -- A grouped return value may carry an operator

`ret (x * 7 + 13 + i) % 1009` did not parse. After `ret`, a `(` was always taken to open
the multi-return tuple `ret (a, b)`: the statement parsed one expression, wrapped it in a
`GroupExpr`, and then demanded a newline, so any binary operator after the closing paren
was `unexpected %`. The same expression parsed fine in a `let` or an `if`, and a group on
the right of an operator -- `x * (y + 2)` -- was fine too, which made the rule hard to
guess. The grammar has always allowed it: `primary = ... | '(' expression ')'`, so a group
is a primary and a legal left operand.

`parse_return_statement` now decides which form it is looking at before committing. A copy
of the scanner walks ahead from the `(` to its matching `)`, counting `(`/`[`/`{` depth; a
comma at depth one means the tuple, anything else means an ordinary expression, which is
then parsed by `parse_expression_node` like any other -- the primary rule handles the group
and any operators that follow. The scanner is a value, so the lookahead disturbs nothing.
A comma inside a nested call sits at depth two and correctly does not read as a tuple.

Found by the scale benchmark (benchmarks/llm_scale), where it is exactly the shape a model
writes. The workaround cost a line per function; removing it took 79,200 tokens, 10.3%,
off that benchmark's 100k-line Neper program. link/ret_group pins both forms together: the
tuple returns, a grouped operand carrying `%` and `*`, a nested call's comma, a negated
group, and a doubly-parenthesised one.

## D248 -- Audio arrives as a vocabulary, two decoders and a mixer

`e.audio` is the vocabulary and nothing else: `SampleFormat`, a `Format` of rate,
channels and sample type, and `Frames`, an interleaved buffer whose `count` is frames
rather than samples. It is layer 2 and depends only on `e.mem`, exactly as `e.gfx.image`
does for the image codecs -- a decoder must not drag a device in behind it, and this is
the shape the repository already uses for that.

The vocabulary is registered before the codecs on purpose. The existing `e.fmt` codecs
each answer in a width of their own, and that is the mistake to avoid here: if `wav` and
`mp3` each invented an output type the mixer would face two incompatible APIs. Both
decoders therefore expose the same four calls -- `open`, `format`, `decode_into`, `seek`
-- and `decode_into` fills a caller's buffer and returns the frames written, so a decode
streams. Whole-file decoding is not offered: five minutes of stereo 44.1k is about 50 MB
of PCM, and `e.fmt.csv` already established that the buffer limits are the memory model.

`e.fmt.wav` is small -- RIFF chunks and PCM -- and also encodes, which makes it the way
to write a mix out and the cheapest end-to-end proof of the contract. `e.fmt.mp3` is
large: frame headers, side info, scalefactors, Huffman, requantisation, stereo modes,
alias reduction, IMDCT and the polyphase synthesis filterbank. Its patents expired in
2017, so nothing licenses it away. Both are unblocked -- `e.bytes` gives the bit reader
and `e.math` the transforms, and both are complete.

`e.audio.mixer` is layer 2 and portable: voices over a shared `Frames`, Q16 gain,
accumulation in `i32` with clipping, and a resampler. Integer gain rather than float is
deliberate, so a mix is bit-identical on every target and can be pinned by a fixture.

Ogg and Vorbis are not registered. They are the largest of the three by a wide margin --
an Ogg container plus codebooks, floor, residue, MDCT and overlap-add -- and nothing here
needs them.

What this does not give is playback. A speaker needs a platform device -- WASAPI on
Windows, ALSA on Linux -- which is a layer 6 module of its own in the shape of
`e.ui.window`, blocked on a `native-audio-api` capability that is not scheduled. It is
left unregistered rather than registered and stalled; `e.audio.mixer` writing into a
buffer is testable today, and a player is that buffer plus the device when it exists.

## D249 -- A game engine core is ten pure modules, and three things it must not add

`e.game.*` holds a headless engine core: `ecs`, `loop`, `sprite`, `tilemap`,
`collide2d`, `vision`, `ai`, `dialog`, `particle`, `netsync`. Every one is layer 2,
pure-domain, so the whole core is simulation with no platform beneath it. Two supporting
modules sit outside the group because they are not about games: `e.math.fixed` at layer
0, and `e.net.snapshot`, which is the serialization half of replication and is useful to
anything that replicates state.

Three subsystems were asked for and deliberately add nothing. **UI is already built**:
`e.ui.widget`, `e.ui.layout` and `e.ui.input` are a widget tree, a layout solve and
hit-testing, which is exactly what a HUD is; an `e.game.hud` would fork the layout engine
for no reason. **Combat rules are game design, not library** -- stats tables, damage
formulas and status effects belong to the game, and what is reusable about them is
already `e.game.ai` and the timers in `e.game.loop`. **Pathfinding is already
`e.algo.graph`**, so `e.game.ai` adapts a grid onto it rather than carrying a second
Dijkstra.

The reuse is the point. `e.data.slot_map` gives entity handles, `e.algo.bitset` the fog
masks, `e.data.ring` the input history, `e.algo.rand` the deterministic stream. Nothing
in the core depends on a module that does not yet exist -- checked when they were
registered -- so the whole engine core is implementable today, with `e.math.fixed` the
only new foundation it waits on.

`e.math.fixed` is the keystone, and it is at layer 0 with no dependencies on purpose.
Rollback netcode, lockstep and replay all require that two machines computing the same
tick get the same bits, and `e.math` is floating point. So the core is integer
throughout: positions in Q16.16, gains and angles in fixed point, and `e.game.vision`
casts shadows by comparing integer slopes rather than float ones, because a disagreement
about who can see whom desynchronises a lockstep session as surely as a disagreement
about position.

`e.game.loop` takes the elapsed time as a parameter instead of depending on `e.time`.
That keeps it pure, and it is what lets a scripted clock replay a session exactly --
which is how any of this gets tested without a machine to render on.

Interest management -- replicating only what a player can see, which is both a bandwidth
saving and the standard measure against maphacks -- is the natural meeting of
`e.game.vision` and `e.game.netsync`. They are deliberately not coupled: the game wires
one to the other, so neither module forces the other on anyone.

## D250 -- The corpus is validated against the v1 schema, by both suites

`docs/schemas/neper-v1.schema.json` has described the machine protocols since section 1
was written, and nothing checked anything against it: the schema and the emitters could
drift apart indefinitely and the only symptom would be a consumer failing somewhere
else. `scripts/validate_stream.py` closes that, and both suites run it.

It validates the committed goldens, not a freshly captured stream, because the suites
already compare every emitted stream to its golden byte for byte. The goldens therefore
*are* what the commands emit, and validating them validates the emitters -- without
ordering the schema check after every command, and without a second capture path that
could itself drift. Today that is 895 records across 23 `.jsonl` files, plus
`docs/modules.json` as a whole document: three of the schema's five top-level shapes
(`streamRecord`, `buildManifest`, `modulePlan`). `sourceMap` and `packageManifest` are
described and unproduced, so they are validated the day something emits them.

Two details earn their lines. A validator that accepted everything would pass all 895
records and prove nothing, so before the corpus the script validates one record that
must fail -- a header whose `command` is not in the registry -- and exits non-zero if
the schema takes it. And the suites so far have needed nothing but the toolchain; rather
than make `jsonschema` a hard prerequisite of running them, an absent package prints a
skip and exits zero. The check runs wherever the package is installed, which is both
development hosts, and a fresh machine still gets a green suite.


## D252 -- What classical 2D and 2.5D still needed: a camera, a grid, input and placed sound

D249 covered simulation. Four gaps remained before the core could carry an ordinary 2D or
2.5D game, and they are registered here.

`e.game.camera` is the viewport -- follow with a deadzone, clamp to world bounds, shake,
zoom, parallax, and world-to-screen both ways. Culling and the depth sort live here too
rather than in a module of their own, because deciding *what is on screen and in what
order* is one question with one answer: an ordered draw list. Producing that order is
engine logic; drawing from it is not, and stays outside.

`e.game.grid` is the 2.5D enabler, and the reason is unglamorous: isometric is a
coordinate transform plus a depth order. One vocabulary -- square, iso diamond, and hex
in both orientations -- answers conversion, neighbours, distance, line, ring and area for
all of them, and `depth` folds elevation in so a tile stack sorts correctly. Tilemaps,
vision and pathfinding all want the same answers, so it sits below them rather than
inside any one.

`e.game.input` is the pure half of input. `e.ui.input` is the device at layer 6; this is
the action map above it -- rebinding, axes, and the buffering an action game is unplayable
without: a press a few ticks early still lands, and an ordered run of presses inside a
window is a combo. It is separate from `e.game.netsync`, which rings inputs for rollback;
that is history, this is interpretation.

`e.audio.spatial` turns a source at a point into a gain and a pan on a mixer voice, with a
cue layer over variants so a footstep is not the same sample twice. Integer pan and
attenuation, so a positioned mix stays as reproducible as an unpositioned one.

Two things were folded in rather than given modules. `e.game.tilemap` gains an
`elevation` layer and `height_at`, because isometric height is a field, not a subsystem.
Easing goes into `e.game.loop`: it is a handful of Q16 curves, and `e.ui.animation` is
layer 6 and bound to the widget tree, so the game core cannot reach it anyway.

One was deliberately refused. `e.game.physics2d` -- an impulse solver with circles,
polygons, joints, slopes and one-way platforms -- is genuinely large, and
`e.game.collide2d` already carries swept AABB, raycast and a broadphase, which is what a
platformer or a top-down ARPG actually uses. It gets registered when a game needs to stack
rigid bodies, not before. `e.fmt.tiled` is likewise left out: importing TMX is a thin
adapter over `e.fmt.xml` and `e.fmt.json`, not a codec.

## D251 -- A symbol carries its signature, its attributes and its `///` documentation

`index --json` named every module-scope declaration (D232) and left three of section
7's fields empty: `signature` was null, `attributes` was `[]`, `documentation` was null.
All three are answerable from the token stream the command already scans, so they are
filled from it, and the resolver -- which carries none of them -- is not widened.

The signature is the declaration's header: the source from its first token to the token
before the first `{` outside any bracket. A function's is everything up to its body; a
`const`, a `var`, an `error` or an `extern fn`, having no body, is its own signature; a
struct's stops at `struct`. That is the text a reader needs to use the declaration and
none of how it is written.

Attributes are spec section 12's: adjacent to the declaration, so the walk back from the
opening keyword crosses newlines, then either `@name` or `@name(...)`, and stops at the
first token that is neither. The names come out in source order.

Documentation is spec section 3's, as written there: the run of `///` lines immediately
above, one optional space after the slashes removed, joined with LF; a blank line or an
ordinary `//` ends the run. Two facts of the lexer shaped the code. A comment is the
leading trivia of the `Newline` token that ends its line, not of the token that follows,
so the run is read off consecutive `Newline` tokens walking back from the attributes.
And `Token.leading_comment` does not mean "this trivia holds a comment": it records
whether the trivia *began* inside one, the continuation flag the trivia scanner needs.
The first draft tested it and found no documentation anywhere. Whether a line is a
`///` line is decided by its first three non-blank bytes, and nothing else.

The run attaches through the attributes -- documentation above `@test` documents the
test -- because attributes are part of the declaration, and a reader writes the doc
above the whole thing. tests/conformance/tools/index.e pins a two-line doc, a documented
`@test`, and a run that a blank line detaches.

## D253 -- A trap's record is read back as the `trap` payload, under `run` and `test`

Section 11's trap protocol writes `file:line:col: trap[kind]: values` to stderr, then
one `  at module.function (file:line)` line per frame. `run --json` and `test --json`
captured those bytes and left section 7's `trap` field null. It is now the structured
payload the schema describes, read back out of the captured stderr by one parser both
commands share.

`kind` is the bracketed word. `span` is byte-precise and zero-width at the site, when
the site's file is the operand: the record carries the lexer's line and column, which
count code points, so the byte and the UTF-16 column are found by walking the operand's
text the driver already holds. `values` is the record's text after the kind, as one
entry. The spec says the values are the operands the check saw, and they are in that
text -- but which words are operands is decided per kind by the check that wrote them,
and a parser guessing at digit runs would read the `8` of `u8` in a cast trap as one.
One lossless entry is honest; splitting it per kind is the gap. `backtrace` has one
frame per `  at` line: the qualified function, the operand source where the frame's
file is the operand, and the line.

Two facts of the child shaped the mapping. The child spells the operand's file exactly
as the compiler was given it -- an absolute path prints absolute -- so the payload keys
on that spelling, not on a basename, and the `run` conformance fixture is spelled
relative to the test build directory, whose depth is the same on both hosts, so its
golden carries no host path. And under `test` the child is not the operand but the
generated runner: the operand's text two `use` lines down, spelled by WORKDIR (D240).
A trap in it is therefore mapped back -- lines shifted by two, the runner's module name
replaced by the operand's in each frame's function -- when the frame lies inside the
operand's own line count. A frame in the runner's scaffolding (`nptest_dispatch`,
`main`) keeps its printed name with no source: that is where it is. The suites
normalise the WORKDIR spelling out of the captured stderr the way they already
normalise `duration_ms`.

Two smaller fields follow from the same read. A crash with no record is the spec's
`exit` kind, its one value the status. And a test's `error` is `"ok"` when it passed
and the qualified name after `error: ` when it failed, the runner's module name mapped
to the operand's the same way -- `test.Mismatch`, not `nptest-runner.Mismatch`.

A frame in a module other than the operand has no source, because the printed path
does not say which root it lies under and the driver has no primitive to find out; its
qualified function names the module, which is enough to look it up.

## D254 -- A build writes its manifest, into a directory the project makes once

Section 7 says every build writes `.neper/<mode>/build-manifest.json`. `build-manifest`
(D238) could print the object; no build wrote it, and the object had no artifact in it.
Now `emit-executable` -- and `run`, which is a build first -- writes it under the
project root after the executable is saved: `mode` is `release` under `--release` and
`debug` otherwise, and `artifacts` carries the executable as it was named, kind
`executable`, the target, and the SHA-256 of the bytes just written. The `build-manifest`
command emits the same object through the same writer, with no artifact, because it runs
no build.

The directory is the project's to make. The fixed os surface (spec section 12, the
bootstrap's `os.e`) has `open`, `readdir`, `spawn` and no `mkdir`, and the compiler must
stay inside that surface to be built by the bootstrap. Three ways around were tried and
put down. Adding `os.mkdir` to the surface is the right fix -- one line in the bootstrap's
intrinsic table, a C body per host, a lowering entry, and a body in each runtime prefix
-- and a change of that shape has cost a session before (D149-D151); it is recorded as
the gap, not folded into this. Creating it through the host's shell worked in neither
form: `cmd /c mkdir` runs Git's `mkdir.exe` rather than the internal command once the
argument is quoted, which the runtime's spawn always does, and a child with no standard
handles at all is refused by `CreateProcess`. And writing the manifest somewhere that
does exist -- beside the executable -- would put it where no consumer looks. So the
build writes the manifest when `.neper/<mode>/` exists and writes nothing when it does
not: an absent directory is `NotFound` from `open`, and that one error is taken as "not
asked for". A consumer that wants the manifest creates the directory once, the way a
repository has a `.git`. Both suites make it, then check the manifest a build wrote
validates against the schema and carries the SHA-256 of the executable on disk.

`.neper/` is ignored by git, since every build under the repository -- its fixtures'
project roots included -- would otherwise leave one behind.

The artifact hash found a second thing. `sha256_hex` (D238) took one byte per `usize`
slot and copied the whole message into a padded scratch of the same shape, so hashing a
5.5 MB compiler cost 88 MB of arena; the bootstrap-built compiler has that, the
self-hosted one does not, and the stable-stage build exited 1 with nothing on stderr --
the first time the manifest was written for anything bigger than a fixture. It now takes
bytes and walks them a 64-byte block at a time through one block buffer, the message
never copied; the `abc` vector, the corpus goldens and `sha256sum` agree.

## D255 -- The format corpus, and a space inside a brace pair

tooling.md section 9 names six corpus roots; five existed. `tests/conformance/format/`
is the sixth: a deliberately non-canonical source beside what `fmt` makes of it, byte
for byte, and the canonical side must itself pass `fmt --check`, so one pair pins both
the transformation and its idempotence. The row that claimed every root was present was
wrong, and is corrected.

Writing the first pair found a rule `fmt` did not have. Its delimiter rule was "no space
inside delimiters", which is right for `(` and `[` and produced `struct {a: i32, b: i32}`,
`if x {ret ok}` and `Pair {a: 1i32}` for braces -- layouts nothing in this repository
writes. A brace pair on one line now has one space inside each side and an empty `{}`
none; `(` and `[` still hug their contents. The existing canonical fixture had no inline
braces, which is how the gap stayed hidden: a corpus whose inputs are already canonical
pins idempotence and nothing else. The format root's inputs are mangled on purpose.

`fmt-file PATH` without `--json` prints the canonical text itself, so the corpus check is
a byte compare and a person can diff or pipe it.

## D256 -- A `@test` that is not a test is E-TEST-9999, before anything is compiled

Discovery (D240) took every top-level `fn` under a `@test` attribute and ignored the
attribute on anything else. A test with another signature -- no arena, a second
parameter, a return that is not `err` -- was then found out by the generated runner
failing to compile, reported as the location-free "the tests could not be compiled"
(E-CLI-9999), which names neither the test nor the rule it broke. And `@test` on a
`const` was silently nothing.

Both are now E-TEST-9999 (diagnostics.md, "invalid test declaration"), the one code
the registry has for them, at the declaration: the function's name token for a
signature that is not spec section 13's one signature, the declaration's first token
for a `@test` that marks something other than a function. The stream is the header, the
diagnostic and a result exiting 2, the shape a runner that fails to compile already
had; nothing is generated, compiled or run. The signature check is a token walk --
`(` name `:` `*` [module `.`] `Arena` `)` `->` `err` `{` -- so the arena's module may be
aliased or omitted, and anything else is refused. The first offender is reported;
tests/conformance/tools/test_reject.e pins a test without its arena.

## D257 -- What `fmt` refuses is diagnostics, in every form

`fmt` on a source with an invalid token printed `error: tool.InvalidSource` and exited
1: a bare line naming an internal error value, no location, no code, and not in the
stream at all under `--json`. Now the refusal is the diagnostics themselves. Each
invalid token is a record under its lexical code, the shape and the code `tokens --json`
already emits for it (D227), and the stream ends in a result that exits 1 with no
`formatted` record; the plain form prints the same as `path:line:col: error[CODE]:
invalid token` lines on stderr and exits 1; `--check` refuses the same way, since a
source that does not lex is not canonical and is not "not canonical at byte N" either.

Section 6 also has one contract a layout pass cannot honour by rewriting: a comment
between attributes and their declaration is illegal, because attributes must be
adjacent and a comment is never moved across a declaration. The formatter cannot both
keep the comment where it is and keep the attribute adjacent, so it refuses, as
E-FORMAT-9999 -- the registry's "other formatter input or contract violation" -- at the
comment. That is the first use of the code. The check is a line-shape one: a line whose
first token is `@`, then a line holding only a comment, before any other token.

tests/conformance/tools/fmt_reject.e carries both and pins two diagnostics in one
stream. The other formatter contracts section 6 states and the layout pass does not yet
implement -- one statement per line, one blank line between top-level declarations,
100-column wrapping, sorted `use` and attributes -- are not refusals; they are the
formatter's own gap, named in the readiness row, and D255's inline brace spacing sits
on the "one statement per line" question until that is decided.

## D258 -- A declaration's parameters, fields and members are symbols under it

`index --json` named module-scope declarations only (D232, D251), because it read the
resolver's symbol table and the resolver carries nothing below that level. What lies
below is in the parse tree, which the command did not build. It builds it now, once,
and under each function or type emits what the tree declares inside it: `parameter`,
`field` and `member` symbols -- the union enum's and the enum's members alike -- with
the declaration's id as `container_id`, the qualified name `module.Decl.name`, and each
carrying its own signature (`a: i32`, `Red`) and its own `///` documentation, since spec
section 3 attaches documentation to fields and members too.

Two facts of the tree shaped the walk. A nested declaration node starts at its name
token, so a symbol's name and selection span are the node's first token and nothing
has to be searched for. And the parser appends a child before its parent, so tree
order is not source order: the nodes inside one declaration are picked by token range
and put out in token order, or a struct's fields would follow the next declaration.

The result's symbol count includes them. tests/conformance/tools/index.e now pins a
documented field, two enum members and three parameters under their owners.

## D259 -- `info` names every command the stream reaches

The `info` record is section 1's capability query -- "harnesses never scrape
`--help`" -- and its `commands` list had stopped at the four of D229: `check`, `info`,
`parse`, `tokens`. Six commands have joined the stream since (D230-D240) and a harness
asking the tool what it can do was told it could not build, run, index, disassemble,
format or test. The list is now the ten of section 1's header enum, sorted by UTF-8
bytes as the section requires. `cpu_levels` stays at `x64-v1`, which is the one level
code selection actually targets, and `features` stays empty until there is one.

## D260 -- An unreadable operand is the envelope, on every `--json` command

Section 1: a command emits its final `result` record last, including on source or
option failure, and stderr is empty unless JSON output itself cannot be initialised.
`check`, `build`, `run` and `index` honoured that for an operand that cannot be read
(D228-D232); `tokens`, `parse`, `fmt` in both its forms, `dis` and `test` printed
`error: os.NotFound` to stderr and exited 1 -- an internal error value, no stream, and
a harness that had been promised JSON Lines got none. All six now answer the way
`check` does: the header, one location-free E-CLI-9999, and the result exiting 2 with
the command's own zero counts. One writer produces it from the command name and the
`data` object, so the shape cannot drift between commands. The plain `fmt-file PATH`
prints the human line and exits 2, since it never promised a stream.

Both suites pin the six streams byte for byte, building the expected text from the
shape rather than from six more golden files that would differ only in one name and
one object. `build-manifest` is left as it was: it emits a document, not a stream, and
a stream header naming it `build` would be a lie -- what its failure should look like
is a question for the manifest's own row.

## D261 -- A program built twice is the same bytes, and its manifest says so

Both suites have long checked the compiler's own fixed point: the compiler the
self-hosted compiler builds, building itself, is the same bytes. Nothing checked the
same for a program. Now each suite builds the conformance corpus's `build.e` a second
time and compares the two executables byte for byte, and compares the second build's
manifest against the first's artifact hash. The second half is the point of the
increment: D254 wrote the SHA-256 of every executable into `.neper/<mode>/build-manifest.json`,
so two builds -- on one machine, or one recorded and one repeated -- can be compared by
their manifests alone, with neither executable in hand. The check that the hash agrees
with the bytes on disk (D254) and the check that it agrees across two builds (this) are
what make the manifest that witness.

No source changed; the suites are the deliverable. A Windows and a Linux build of the
same program differ by design -- different runtime prefix, different image format --
so reproducibility is claimed per host, and the row says so.

## D262 -- `check-project` checks every module under a project, one stream

`check-file` checks one operand. A project is a tree under `src/`, and checking it
meant a caller walking the tree and reading one stream per file. `check-project DIR
TOOLCHAIN_ROOT ARCH OS WORKDIR --json` does the walk and emits one stream.

The shape is a driver, not a refactor of the checker. `check-file`'s pipeline lives
inline in `main`, which sits at the bootstrap's local cap, so extracting it would have
been a large edit for the sake of a loop; the driver instead runs `check-file --json`
on each module in its own process -- the compiler spawning itself, as `test` already
does (D240) -- and merges the children's records: the header once, every diagnostic,
one result with the diagnostic and module counts. A process per module costs
milliseconds and gives isolation for free.

Two things had to be settled for the merged stream to be right. A diagnostic's
identity was the operand's basename (D228), which cannot tell `a/main.e` from
`b/main.e`; `check-file` now takes `--path VIRTUAL` after `--json`, the spelling
`tokens` and `parse` already had (D227), and uses it as the operand's identity in every
span while a diagnostic in any other module keeps that module's basename. The driver
passes each module's path relative to `src`, with `/`. And the tree is walked in byte
order of entry name, not the order `readdir` returns, so the stream is the same on
every filesystem and the golden holds on both hosts. A diagnostic a child raises for
an imported module rather than the one it was asked to check is dropped from that
child's stream -- it is reported when that module is the one checked, and would
otherwise appear twice under two names; with D224 the case is rare, since an imported
module's body is not checked.

tests/conformance/tools/check_project pins three modules, one of them in a
subdirectory, two with an error. `WORKDIR` is where the children's output is captured,
the same need `test` has and for the same reason: the fixed os surface spawns onto
files, not pipes.

## D263 -- `test-project` runs every module under a project, and a runner is built as part of it

`test-file` ran one module's tests. `test-project DIR TOOLCHAIN_ROOT ARCH OS WORKDIR
[TIMEOUT_MS] --json` runs every module under `DIR/src`, the way `check-project` checks
them (D262): the tree walked in byte order, `test-file --json --path REL` spawned per
module, the children's `test` records and diagnostics forwarded, their summaries added
into one `test_summary`, one result with the test and module counts. A module with no
`@test` is counted and skipped -- its stream is the header, an empty summary and the
result, with nothing generated, compiled or run -- which is also why a module that
defines `main` and has no tests, the usual shape of `main.e`, no longer collides with
the runner's `main`.

Two things the single-file command had never needed. First, identity: `test-file`
takes `--path REL`, and the record's `file` is that path and its `module` the dotted
name section 2 gives it -- `nested/deep.e` is `nested.deep` -- so two `t.e` in
different directories are two modules, not one. Second, and the real finding: the
runner is the operand's text copied into WORKDIR, and a test that `use`s a sibling
module could not build there, because module resolution finds the project from the
operand's own path and WORKDIR is not in it. The lazy fix -- writing the runner into
the project's tree -- would leave generated files in a user's `src`. Instead
`emit-executable` takes `--project DIR`, naming the project root outright in place of
discovering it, and the runner is compiled with the operand's own root; a file outside
the tree is built as part of the project. `test-file` discovers that root itself, so
`test-project` passes nothing extra.

tests/conformance/tools/test_project pins three modules: `main.e` with no tests,
`helper.e` with a passing and a failing test, and `nested/deep.e` whose test uses
`helper`. What remains is a module that both defines `main` and carries tests, which
the runner's own `main` still collides with.

## D264 -- Source maps: the test runner writes one, and the compiler reads it back

Tooling section 8 has described generated source maps since it was written, and
nothing produced or consumed one. This repository has exactly one generator -- `test`
writes a runner that is the operand's text two `use` lines down (D240) -- and the
consequence showed every time a test failed to compile: "the tests could not be
compiled", location-free, with the real diagnostic pointing into a file the user never
wrote. Both halves of section 8 now exist, and that failure is reported at the test's
own line.

The generator half. Beside `nptest-runner.e` the driver writes `nptest-runner.e.map.json`:
`neper-source-map`, version 1, the runner's identity and SHA-256, and one mapping from
the operand's text at its place in the runner to the operand as a whole, `name` null.
One mapping is the truth of this generator -- the operand is copied verbatim, so every
byte of it maps by one constant offset and two lines -- and the document validates
against the schema, which both suites check.

The consumer half. `emit-executable`, `run`, `dis` and `check-file` look for
`<operand>.map.json` beside the operand once the graph is loaded. Absent, nothing
changes. Present, its `generated_sha256` must be the operand's bytes and its `schema`
the source map's, or it is E-TOOL-0001 -- stale or malformed, the code's two meanings
-- and the command fails with no artifact written; that is the first use of the code.
With a matching map, every diagnostic whose span lies inside a mapping is reported at
the original span as primary, the source identity the map names, and the generated
span goes into `related` as "in the generated source". The arithmetic is the mapping's
two offsets: bytes shift by the difference of the two `byte_start`s, lines by the
difference of the two `line`s, columns are kept -- right for a mapping that begins at a
line start, which this generator's does and which is recorded as the assumption. The
map is read by a key scan over the one document shape the generator writes, not a JSON
reader: `e.fmt.json` would cost bootstrap declarations the compiler has no room for, and
the schema is ours. Eight mappings per map is the cap.

`test` compiles its runner under `--json` now and forwards the compiler's records --
mapped -- before its own E-CLI-9999, so the stream says both what was wrong and that
nothing ran. tests/conformance/tools/test_compile_error.e pins that stream, and
tests/conformance/tools/stale_map.e with a map whose hash is zeros pins the refusal.
Section 8 also says the compiler still analyses the generated file under a stale map
and fails only at the end; this one fails at once, which is the gap the row names.

## D265 -- A manifest's inputs have their real roots, and its dependencies an interface hash

D238's manifest named every module as an `operand` by basename and left `dependencies`
empty. Two corrections.

An input's source identity is now section 2's: a module under the project's `src` is
`project-src` with its path under that root, under `lib` it is `project-lib`, a module
under the toolchain's `lib` is `toolchain-lib` -- `e/atomic.e` -- and only a file
outside every root is the operand by its basename. The graph already knew both roots;
the identity is `project.relative_under` asked three times, separators written as `/`.

Every module but the root is a dependency, with two hashes. `body_sha256` is the file.
`interface_sha256` is the file with every function body left out -- the balanced braces
after a top-level `fn` header, the `{` and `}` kept -- hashed. That is the property the
split exists for: an edit inside a body moves `body_sha256` and nothing else, so a
consumer holding the previous manifest can tell "recompile the dependents" from
"relink them" without a checker. The cut is a token walk, not a parse: a header ends at
its first `{` outside brackets or at a newline that does not continue one, so an
`extern fn` without a body and a function-typed field are passed over.
tests/conformance/tools/manifest_project pins a two-module project per host, and the
interface hash was checked against the same cut done by hand.

The first draft of the cut scanned each module into a token array and the self-hosted
compiler's stable stage failed to build, the D254 symptom again: a token is a hundred
bytes per source byte, times thirty modules. The cut now streams tokens off the scanner
one at a time and keeps none, and each module's scratch is released with an arena mark
once its hashes are written -- a large graph costs one module's worth of arena at a
time. The compiler's own manifest lists 32 inputs and 31 dependencies, and its stable
stage is the same bytes as its second.
## D266 -- `e.math.fixed`, and angles measured in turns

The first of D249's game-engine modules, and the one the rest wait on. Q16.16 in `i32`,
every operation integer: two machines running the same tick agree bit for bit, which is
what lockstep, rollback and replay need and what `e.math` cannot promise, being floating
point. Products take a 64-bit intermediate and narrow back, so an overflow traps under
section 11 rather than wrapping quietly.

**Angles are turns, not radians.** One whole turn is `ONE`, a quarter is `QUARTER`. That
choice pays three times: reducing an angle is masking off the whole turns rather than a
division by a transcendental constant, `sin` is therefore defined for every `i32` with no
range-reduction error, and the quarter turns land exactly, so `sin(QUARTER)` is `ONE` and
not one off it. `atan2` answers in the same unit, so an angle round-trips.

Nothing here is a lookup table. `sin` is the parabola `8t - 16t|t|` over turns with one
refinement pass weighted 0.225, worst error 0.0011 of a turn; `atan2` divides the steeper
axis by the shallower so the ratio never leaves `[0, 1]`, applies the usual minimax bend
to `z/8`, and folds the quadrant back on, worst error 0.00026 of a turn -- a tenth of a
degree. Both are exact at the quarter turns. A 257-entry table would read better and
measure better, and is not used because large literals have bitten this library before;
the first `atan2` written here was the cruder rational form, at 4 degrees of error, and
was replaced once measured rather than once trusted.

`sqrt` is bit-by-bit integer square root over `i64` -- no division, no float, no
iteration count that could differ. `length` squares into Q32 and takes one root, so
3-4-5 comes back as exactly 5.

The module is `partial`, not `source`: `atan_unit` is a helper the declared surface does
not name, and section 12 has no visibility, so it sits beyond the fence in the same way
`e.io` and `e.sync` do. `isqrt64` is declared rather than hidden, being useful on its
own. `Overflow` was declared when the module was registered and is not implemented,
because nothing returns it -- `mul` and `from_int` trap instead -- so it was removed from
the surface rather than left as a promise.

link/math_fixed pins thirty-seven checks whose expected values were computed
independently rather than read back from this implementation, including a round trip that
recovers an angle through `sin`, `cos` and `atan2` across the whole circle.

## D267 -- `run` passes what follows `--` to the program

`run --json` launched the program with no arguments; a program that reads its command
line could not be exercised through the stream. Everything after a `--` at the end of
the command is now the program's, as given -- `-- first "second word" 3` reaches
`main`'s `args` as three strings, the space kept -- on both hosts: on Windows the
runtime's spawn quotes each argument into the command line, and on Linux, where the
fixed os surface's lack of chmod sends the launch through `sh -c`, the shell passes
`"$@"` on after `exec "$0"`. The compiler's own flag scan stops at `--`, so nothing the
program is given is read as `--release` or `--arena`.

The same probe found that a relative OUTPUT with a directory in it -- `build/out.exe`
-- could not be launched on Windows at all: CreateProcess reads a relative path
spelled with `/` as no path, and the suite had only ever launched bare names. The
launch now spells the path the host's way. tests/conformance/tools/run_args.e echoes
its arguments and exits with their count.

Found on the way: a build hashed every module for its manifest before asking whether
`.neper/<mode>/` exists, so a project that never made the directory paid for a manifest
it never got. The open comes first now, and an absent directory costs nothing.
## D268 -- The fixed step and the entity store, and a fixture check that is not the suite

`e.game.loop` and `e.game.ecs`, the first two of D249's engine modules, taken as one batch
because the ceremony around a module -- a decision, a runner block, a regenerated
readiness page -- costs more than either module does.

**`e.game.loop`.** The clock is handed the elapsed time rather than reading one. That is
the whole point: a simulation driven by a scripted clock replays exactly, which is what
makes a deterministic engine testable with no machine to render on, and what rollback
needs. `advance` returns the whole steps owed and caps them, and on hitting the cap it
drops the backlog rather than carrying it, because a machine that cannot keep up would
otherwise owe more every frame than the frame before. A repeating timer carries its
overshoot into the next period, so a period that is not a whole number of steps does not
drift. Easing lives here rather than in a module of its own: these are a handful of Q16
curves, and `e.ui.animation` is layer 6 and bound to the widget tree, so the game core
cannot reach it. `ease_elastic` damps with a cube rather than the usual power of two,
which would want an exponential; it is table-free, lands exactly on both ends, and rings
the same way.

**`e.game.ecs`.** An `Entity` is a slot and the generation that slot held when it was
handed out, so a handle kept across a despawn is detectably stale rather than quietly
addressing whoever moved in afterwards. A generation is odd while its slot is live and
even once it is free, which makes `alive` a comparison and needs no second table.
Components live in parallel columns, a bit per slot saying whether this slot has one, and
`get` hands back the store's own bytes so a write through it sticks. Every buffer is the
caller's: the store allocates nothing, so its capacity is what `init` was given and a full
store is an error rather than a surprise. `query` walks slots in order, so it answers the
same sequence on every machine.

Both surfaces were corrected against what was actually written rather than left as
registered. `e.game.ecs` needed a `free_count` the registered `Store` did not name, and
three errors beyond the two registered; it is `partial`, since its bit helpers sit beyond
the declared fence and section 12 has no visibility. `e.game.loop` names everything it
defines, so it is `source`.

**`scripts/check-fixture.sh`** is the other half of this decision. The suite makes 415
compiler invocations across 175 fixtures and builds the compiler two or three times for
the fixed point. That is the right price when a change can reach the compiler -- anything
under `src/`, `bootstrap/` or `scripts/`, or an edit to a lib module something imports --
and the wrong price for a change that only adds a module and its own fixture, where
nothing else in the suite can see it. The script builds the compiler only when a source
is newer and then runs one fixture: 1.1 seconds warm against five to fifteen minutes, or
50 seconds cold including the compiler. The rule is targeted checks during development,
the full suite once per batch at merge -- which is where this batch's two green suites
came from. It does not cover the runner block a new fixture adds, so the merge gate stays.

Measured rather than assumed, twice over: the Linux suite wedged fifteen minutes on the
self-host build with no output while free memory sat at 2.5 GB, and the same build took
48 seconds once memory freed. A stall under contention is indistinguishable from a hang,
which is its own argument for not paying the full price on every module.

link/game_core pins 55 checks across both modules, and a deliberately broken check was
confirmed to fail before the fixture was trusted. That check also turned up something
worth recording: `fn main() -> i64` compiles, though section 13 says `main` has one
signature and any other is a compile error, and whatever it returns the process exits 1.
Every link fixture numbers its checks that way, so a runner that reports `failed check
$LASTEXITCODE` always reports 1. The numbering still marks the failing line in the source;
it is not a status. Left as it stands rather than changed under 175 fixtures here.

## D269 -- `dis` lists mnemonics, from a decoder over what the emitter produces

`dis --json` listed each function's bytes as hex (D233): faithful, and unreadable. The
listing is now one line per instruction -- the function-relative offset, the mnemonic
and operands in Intel order, the bytes after a `;` -- from `src/disasm_x64.e`, a
linear-sweep decoder over the encodings `emit_x64.e` produces: the REX, 66, F2/F3 and
lock prefixes; the one-byte map's moves, arithmetic, shifts, groups 1/3/5, pushes,
pops, immediates, calls and jumps; the two-byte map's conditionals (jcc, setcc,
cmovcc), movzx/movsx, imul, bt, xadd, cmpxchg, fences, syscall, ud2, and the scalar SSE
forms with movd/movq; ModRM with SIB, disp8/disp32 and rip-relative memory; signed
immediates; jump targets as offsets. A byte the table does not know is a `db` line,
never a failure.

Two things a decoder for this emitter has to know. Code selection lays section 11's
trap record inline after an unconditional forward `jmp` -- the path, the kind, the
operand text with 0/1 separator bytes -- and a sweep reads it as code; the bytes a
`jmp` skips are listed as one `text` line when every one is printable, NUL, a
separator or a newline, and decoded as the else-branch they otherwise are. And a `66`
before `0F` is SSE's mandatory prefix, not an operand-size override: the first draft
printed `movq r10w, xmm0`, which is what turned up when the listing was checked against
GNU objdump. That check -- 3,546 instructions across three fixtures, every function up
to its first inline text -- found no other semantic difference, and eight fixtures
(42,000 instructions) list with no unknown byte. The per-host goldens of
tests/conformance/tools/dis.e are regenerated; the bytes in them are the same.
## D270 -- One coordinate vocabulary for four shapes, and a tilemap that is bits beside tiles

`e.game.grid` and `e.game.tilemap`, batched because a grid without a map to index is
half an idea, and because the ceremony costs more than either module.

**Isometric is a coordinate transform plus a depth order.** That is the whole of what
2.5D means here, and it is why there is one `Coord` -- axial `q`, `r` -- and one set of
operations answering for square, isometric diamond and hex in both orientations. A game
changes its look by changing the `Shape` it passes, not its map, its pathfinding or its
AI. `depth` returns the painter's key: the row, or the diagonal for a diamond, times 256
with elevation in the low byte, so a raised tile sits in front of the flat ground it
shares a row with while a nearer row still beats a further one at any elevation.

The shapes are kept internally consistent rather than conventionally so. Square and
diamond have four neighbours and Manhattan distance, so their rings are diamonds; hex has
six and hex distance, so its rings are hexes. A ring is always *the cells at exactly
`radius` under the distance that shape uses* -- mixing Manhattan distance with a square
ring is the usual bug, and it makes `distance` and `ring` disagree about what a radius is.

`from_world` floors rather than truncates, and `floor_div` exists to make it so. Integer
division rounds toward zero, which folds the tile left of the origin onto the tile right
of it: every map is then wrong along two edges, and only there, which is the kind of bug
that survives a demo. Hex needs more than a floor -- fractional axial coordinates are
rounded in cube space, where the three components must sum to zero, so the component that
moved furthest is recomputed from the other two. Without that a line drawn across a hex
grid leaves the lattice.

**The tilemap keeps what is drawn apart from what is simulated.** Tiles are layers;
solidity, opacity and elevation are bitsets and a byte array beside them. Collision asks
`is_solid`, vision asks `is_opaque`, the depth order asks `height_at`, and none of them
needs to know how many layers a map has or which of them is scenery. A wall and a window
then differ by one bit rather than by a tile id every system has to agree about, and
`derive` fills the bits from a table of blocking ids because a map is authored as tiles
and derived into bits, not the other way round.

Off the map reads as solid and as opaque. A mover walking off the edge is stopped by the
same test that stops it at a wall, and sight does not run out past the border, so neither
caller carries a bounds check of its own. Layers that disagree about their size are
refused by `init` rather than trusted, since a ragged map makes every index ambiguous.

Both are `partial`: each keeps helpers the declared surface does not name -- `floor_div`,
`cube_round`, `abs32`, the bit accessors -- and section 12 has no visibility. Both
surfaces were corrected to what was written: `tilemap` gained `Size`, the three setters,
`derive` and the size accessors, and `grid` gained `coord`, `equal` and `hexed`.

link/game_grid pins 63 checks against values computed independently, and **three
deliberately broken checks were confirmed to fail before the fixture was trusted** --
including the floor-versus-truncate one, which passes under either rule everywhere except
the negative edge it was written for.

## D271 -- References in the index, resolved by the rule that forbids shadowing

`index --json` had symbols and no references, and the result said `"references":0`.
Now every use of one of the module's own module-scope names, and every name reached
through a `use` qualifier, is a `reference` record: `import` for each `use`, `type` in a
type position -- or for a type's name standing in a path, `Colour.Red` -- `call` before
a `(`, `instantiate` before a `[`, `write` before an assignment operator, `address`
after `&`, and `read` otherwise. A bare name is resolved by matching it against the
module-scope symbols the same stream just emitted, and that match is the resolution:
spec section 5 forbids a local or parameter from reusing a module-scope name of its
own module (the resolver's `ModuleShadow`), so a bare name that matches a declaration
can be nothing else. A name through a qualifier is spelled as written and named
`path.name` with a null id, since other modules are not symbols of this stream. A name
that matches nothing -- a local, a parameter, a builtin type, a generic parameter -- is
not a reference to a symbol and is not emitted.

The classification is the tokens around the name, which is what the parser itself used
to build the node: the tree says where a name expression or a named type is, the
neighbouring tokens say what it does. No checker state is consulted, so the index costs
a parse and nothing more; compiler-origin references -- protocol resolutions, the
iterator's `_next`, formatting calls -- are the gap, and they are the checker's to
report. Records go out after the symbols, sorted by span start among themselves;
section 5's single order over both kinds is the other gap. tests/conformance/tools/index.e
pins eleven references across every role but `protocol`.
## D272 -- Contact times and shadows, both answered in integers

`e.game.collide2d` and `e.game.vision`, batched because both read the solid and opaque
bits of a tilemap and neither is much use without the other: a mover that cannot see and
a watcher that walks through walls are the same bug from two directions.

**A sweep answers *when*, not *whether*.** Every test here reduces by the Minkowski trick
-- grow the target by the mover's half extents and a box against a box becomes a ray
against a box -- and returns a time along the motion in Q16 with the face that was struck.
A caller then advances to the moment of contact instead of stepping and testing, which is
what stops a fast mover tunnelling through a wall rather than making the steps smaller and
hoping. A mover that already overlaps reports time zero; `overlaps` is the question for
that case. `ray_tiles` walks tile boundaries by advancing whichever axis reaches its next
edge first, so no tile on the line is skipped and none is visited twice.

**Shadowcasting compares slopes without dividing them.** A slope is a pair of integers and
`slope_greater` cross-multiplies, so visibility is identical on every machine -- which
lockstep requires, since disagreeing about who can see whom desynchronises a session as
surely as disagreeing about position. The subtlety that makes it work is a sign
normalisation: every octant scans with a negative row, so the denominators are negative,
and cross-multiplication only orders correctly when both are positive. Without normalising
first the comparisons invert and the scan reveals nothing at all -- which is exactly what
the reference implementation did on its first run, before any of this was written in
Neper.

Fog is two bitsets and no third table: `visible` is recomputed each tick, `explored` is
sticky, and a cell in neither is unseen. `line_of_sight` lives beside them because the AI
and the fog must answer the same question the same way -- an enemy that can see you and a
tile you can see cannot disagree.

Both are `partial`; each keeps helpers the declared surface does not name. `cast_cone` was
registered in D249 and is **removed from the surface rather than left as a promise**, the
way `Overflow` was in D266: it is not implemented, and a declared function that does not
exist is worse than an absent one.

link/game_sight pins 65 checks with three negative controls. The visibility expectations
-- including that exactly 37 cells are lit -- come from an independent shadowcaster rather
than from this implementation, so the two agreeing means something. One check failed on
first run and the implementation was right: a ray 32 units east from the middle of a tile
reaches only the next open tile, not the border I had asserted it would strike. The
arithmetic was checked before the fixture was changed, and the short ray was kept as a
deliberate no-hit case, which makes it a better fixture than the one intended.

## D273 -- One blank line between declarations, `{}`, and `else` beside `}`

Three of section 6's layout rules the formatter did not have, all settled in the
line pass that already collapsed blank runs. Exactly one blank line separates
top-level declarations: a column-0 line that opens one -- `fn`, `type`, `const`,
`var`, `error`, `extern`, `use`, an attribute, or a comment that leads into one --
gets a blank before it, unless what precedes is what leads into it: an attribute, a
`///` or `//` line, or a `use` before another `use`, so a documented and attributed
function stays one unit and the import block stays contiguous. An empty block is
`{}`: a line that is only `}` joins the `{` above it. And `else` follows `}` on the
same line: a line beginning `else` joins the `}` above it with one space.

Two things were checked before the goldens moved. The existing canonical fixture
(tools/fmt.e) was still canonical under the new rules, so `--check` on it is unchanged;
and the format corpus's canonical side still compiles and runs, so a rule that joined
lines had not fused two statements. The repository's own style groups constants
without blank lines in places; the contract says one blank line, and the formatter
follows the contract.

## D274 -- The leading `use` block sorts by module path, then alias

Section 6: contiguous comment-free `use` declarations at the start of a file sort by
module path then alias. The formatter now sorts that run -- the consecutive `use`
lines after any leading comment lines, ended by a blank line or anything else -- in
byte order of the whole line, which is path-then-alias order because the space
before `as` sorts before a `.`: `use e.mem`, `use e.mem as m`, `use e.os`. It is a
pass over the finished text, after the line pass, since the run has to be seen whole.
The format fixture's two imports are written out of order and come out sorted, and
its canonical side still compiles and runs.

## D275 -- Every recovered failure is a diagnostic, and a barrier crossing is E-SYNTAX-0012

The parser already recovered: a statement or declaration that failed became an
`ErrorNode` and the parse went on (D-early), so a tree with three broken statements had
three `ErrorNode`s. But it kept one failure -- the first, frozen so the human line
never moved -- and `parse --json` reported that one. The tree now keeps every failure
recovery went past, in order, and `parse --json` emits one diagnostic per failure at
its own token; the first is still the primary the compile pipeline reports. The list
takes a failure once even though a declaration's failure is recorded by the statement
and again by the file that contains it.

Spec section 3's barrier rule was detected and not named. A `(`, `[` or a literal's
`{` still open when a column-0 declaration keyword arrives is a compile error reported
at the *opener*, naming the keyword that ended it -- one precise diagnostic instead of a
cascade -- and the parser stopped there under the generic E-SYNTAX-9999 at the token it
happened to be on. Now the token that opened each soft delimiter is remembered as it
opens, the crossing records the innermost one at the moment it is seen (the depth is
gone by the time the failure is unwound to the file), and the diagnostic is
E-SYNTAX-0012 with the spec's own wording -- `` `(` opened here is still unclosed at
`fn` on line 6 `` -- in the parse stream, the check stream and the human line alike.
That is the code's first use. tests/conformance/parse pins two_errors and barrier, and
reject/barrier pins the check stream.

## D276 -- Spec section 2's spellings, as a front door onto the positional forms

The self-hosted compiler answered only to positional forms -- `emit-executable PATH
TOOLCHAIN_ROOT ARCH OS OUTPUT --json` -- while the spec writes `neper build <file.e>`
and `neper run <file.e>`, and section 2 says where the missing operands come from: the
toolchain's `lib/` is beside the binary, so the toolchain root is the binary's own
directory; the target is the host unless asked otherwise; a program root may be run
from any directory. Those spellings now exist: `build FILE [-o OUT] [--target ARCH-OS]
[--release] [--json] [--project DIR]`, `run FILE [--target ..] [-- ARGS]`, `check FILE
[--json] [--path REL]`, `fmt FILE [--check] [--json]`, `index FILE`, `dis FILE`,
`build-manifest FILE`. Each is rewritten into its positional form and dispatched
again through `main` -- the rewrite is a table, not a second implementation, and the
positional forms stay the ones the suites drive and the goldens pin. `build` names its
output after the operand's stem, `.exe` on Windows, and `run` is always the stream.

Two details. The positional `run` and the short `run` share a word; they are told
apart by the positional form's architecture sitting fourth. And `main` sits at the
bootstrap's local cap, so the rewrite and the second dispatch live in one helper whose
`NotShortForm` result means the arguments were already positional. The suites copy the
stage-one compiler beside the toolchain `lib/` and compare the short `build`'s stream
to the positional golden. A short `test` is not offered: its WORKDIR has no short
answer until the fixed os surface can make a directory.

## D277 -- Lists break at 100 columns, one element per line, and join when they fit

Section 6's one line-breaking rule: a bracketed list that exceeds 100 columns breaks
after its opening delimiter, one element per line with a trailing comma, and closes on
its owning indentation; otherwise it is one line with no trailing comma. The layout
pass now works over the token array with a plan: every soft opener is matched to its
closer up front, and at the opener the list's one-line width is measured with the
pass's own spacing, from the column the opener sits on. Fits: the newlines inside are
soft and dropped, a trailing comma before the closer dropped. Does not fit: a newline
after the opener, elements four columns in from the opener's line, `,` ending each,
the closer back on that line's indent. Nested lists measure from their own column.

What may break is what the grammar lets carry a trailing comma: a `(` after a callee,
`ret` or `fn`, and a type body's `{` after `struct`, `union` or an enum's element type.
A grouping `(` and every `[` only join -- the first draft broke `(a && b)` in `main.e`
and produced a `,` no parser takes, which is how the rule was found -- and a list with
a comment inside is left as written, since a comment is never moved. Aggregate-literal
bodies are not lists yet: at the token level `Pair {` and `if p {` look the same.

The check that settled it: every source file of the compiler and the library formats
without failure and idempotently, and a compiler built from its own formatted sources
answers the format and index goldens byte for byte. That sweep also found D273's line
pass writing past a buffer sized before it learned to insert blank lines, which the
old compiler tripped on `check.e` as a bounds trap; the buffer has room for one
insertion per line now.

## D278 -- A `call` in the listing is named

`dis` listed `call -0x38` and `call 0x52`: the first a resolved displacement into
another function of the image, the second a zero the image fills at link time. Both
now carry the name after their bytes. A resolved displacement is followed back to the
function whose start it lands on -- `-> dis.add` -- and an unresolved one is named from
the relocation that will fill it, the rel32 sitting one byte after the opcode --
`-> neper_os_exit`. The decoder stays generic; the naming is a pass over its lines in
the command that has the function table and the relocations to hand.
## D279 -- A conversation is data, and a particle pool forgets in order

`e.game.dialog` and `e.game.particle`, batched because each is self-contained and neither
needed a new foundation.

**A dialogue tree is two flat arrays.** Nodes, and the choices they own as a run inside one
shared choice array -- no pointers, no allocation, so a tree is data a game can author,
ship as a constant and hand straight to `start`. The mutable half is the `State`: where
the conversation is, which flags are set, what the counters hold, all in the caller's
buffers.

Each choice carries its own guard, so **whether an option is offered is part of the data**
rather than a branch in the game. A guard reads flags and counters and nothing else, which
makes evaluation total: no expression language, nothing that can fail to parse, and no
condition the checker cannot see through. The cost is that arithmetic past "add to a
counter" belongs to the game, which is the right trade for a stdlib module -- `e.game.ai`
will want the same guards, and a shared evaluator that can fail would push that failure
into both.

`choose` takes the index into the shared choice array, the value `available` returned, not
a position within that answer -- so a caller that filters the offered list again still
names the same choice. A guarded choice is refused even when named directly, and `advance`
refuses a node that still offers something, because advancing past a live decision would
silently skip it.

**The particle pool keeps its live set contiguous.** An expired particle is replaced by the
last live one and the count drops, so `step` walks a prefix without testing a flag per
slot. Survivors are therefore not in emission order, which costs nothing, because
particles are drawn as a set. A full pool drops the new particle rather than growing or
evicting: effects are the first thing to sacrifice under load, and a dropped spark is not
a bug where an allocation in the middle of a hit reaction would be.

Randomness is `e.algo.rand`'s PCG64, threaded in by the caller rather than held inside, so
a replay that seeds it the same way produces the same sparks in the same places. The
registered dependency on `e.data.slot_map` was dropped -- a pool with a contiguous live
prefix does not need generational handles, and carrying the dependency would have implied
the particles were addressable, which they are not.

Both are `partial`. `Emitter` gained a `facing`, since a spread without a direction to
spread around is only ever a full circle.

link/game_story pins 64 checks with four negative controls. The particle expectations came
from a model of the step loop, and the emitter is given a zero spread and a fixed lifetime
so those checks draw nothing from the generator and are exact; the spread emitter is
checked as a property -- inside its arc, inside its lifetime range -- which holds whatever
the generator returns.

## D280 -- The index is one span order over symbols and references

Section 5: records sort by source identifier, span start, record kind, then qualified
name. D271 put the references after the symbols, sorted among themselves; the stream
is now one order. The references are collected first, then every symbol's id is
settled before any record is written -- the id sequence is deterministic, one per
declaration plus one per parameter, field or member under it, so a pass that only
counts the nested declarations reproduces it -- and each reference goes out before
the first symbol whose span starts after it, nested symbols included, so a type named
in a signature comes between the parameters it sits between. The result's counts are
unchanged, and the fixture's thirty records are monotone in span start. A reference
to a declaration that comes later in the file names an id that has not been written
yet; that is what the spec's stable ids are for.

## D281 -- The runner renames the operand's `main`, and the map carries the seam

An operand that defined `main` and carried tests could not be tested: the runner is
the operand's text plus a `main` of its own, and two `main`s do not compile. Discovery
now also notes the operand's top-level `fn main`, and the runner writes it as
`nptest_operand_main` -- one identifier replaced as the text is copied, nothing else
touched. The runner's source map (D264) then has two mappings instead of one: the
operand's bytes up to the renamed name, and the bytes after it shifted by the fifteen
bytes the longer name adds, so a compile error in a test declared after `main` still
lands on the operand's own line and column. The second mapping begins mid-line, which
is the one place the map's "columns are kept" assumption is not true: a diagnostic on
the `main` line itself, after the name, would be off by fifteen columns. Two fixtures
pin both halves: tests/conformance/tools/test_main runs two tests around a `main`, and
test_main_error mistypes a test after it.
## D282 -- Frames and transitions, and the order a frame is drawn in

`e.game.sprite` and `e.game.camera`, batched because both answer questions the draw loop
asks and neither draws: one says which frame, the other says where and in what order.

**A clip ends by naming what follows.** `then` is the clip to run next, so an attack that
returns to idle is data rather than a branch in the game, and a state machine over
animations is a table. Looping is separate from that and deliberately so: a loop never
finishes, a finished clip stays finished until something plays another, and the two answer
`finished` differently. A clip with nothing after it holds its last frame rather than
wrapping or blanking -- a hurt frame that silently restarts reads as a stutter, and one
that blanks reads as a missing sprite.

`play` always resets the cursor, so replaying the clip already running restarts it. The
other convention -- continue if already in this state -- cannot be recovered by a caller
that wanted a restart, while this one can: test `p.clip` first. A clip whose `hold` is
zero is treated as one tick per frame, so a table with a forgotten hold animates fast
rather than standing still forever, which is the failure that looks like a hang.

**The camera answers what is on screen and in what order, together.** Culling that changed
the order would break the painter's algorithm the order exists to serve, so `cull` and
`order` live in one module and `cull` preserves input order. `order` is an insertion sort
because it is *stable*: two items tying on layer and key keep the order they were given,
so a draw list does not flicker between frames that produce ties -- and because it is
nearly free on an almost-sorted list, which a draw list is from one frame to the next.
Layer outranks the key, so a background never sorts in front of a foreground however deep
it lies.

Following uses a deadzone and moves only far enough to put the target back on its edge;
a camera that centred every frame would swing on every step a character takes. Clamping
centres a world narrower than the view, because no position satisfies both edges. Shake is
integer and draws from the caller's generator, so a replay shakes the same way -- a camera
that wandered by a float would put every rollback frame a pixel off the one it is compared
against.

`sort_key` was registered in D252 and is **removed rather than shipped**: it reduced to
returning its own argument, since `Item.layer` already outranks the key in `after`. An
identity function in a public surface is a promise that something happens.

link/game_view pins 67 checks with four negative controls, one of them the stable-sort tie
-- the case a sort that is merely correct would get wrong without ever failing a count.
The shake is checked as a bound rather than a value, since it draws from the generator.

## D283 -- `--language-version` selects the advertised profile, or refuses before reading

Section 1: `--language-version MAJOR.MINOR` selects one advertised version and defaults
to the newest non-experimental one; an unsupported value is E-CLI-9999 before source is
read. There is one advertised profile, 0.1, so the flag on any command -- short or
positional -- is taken off the arguments when it names 0.1 and the command proceeds
unchanged; any other value is refused before a file is opened, as the human line or,
under `--json`, as a stream whose header names the command the flag was given to and
whose result exits 2. The flag is handled where the short spellings are (D276), ahead
of every dispatch, which is what "before source is read" needs. The refusal is pinned
by tests/conformance/tools/info_version.

## D284 -- A second fixture per corpus root, and what writing them found

Section 9's corpus had one fixture under `accept/` and one under `format/`. Each root
now has at least two: accept/aggregate checks structs, an enum, a generic function and
a `switch`, and format/types writes type bodies, an enum, a generic signature and a
`switch` badly and pins what `fmt` makes of them. The second found two things the
formatter got wrong, which is what a fixture written to be unlike the first is for. A
`.` glued to whatever preceded it, so `case .Red` came out `case.Red` -- a `.` glues to
a value on its left and to what is on its right, and a member literal after a keyword
keeps its space. And `case` labels were indented as statements of the switch's block;
they sit at the `switch`'s own indent, the statements under them one level in, which
is how every switch in the repository is written. Every compiler and library source
still formats idempotently, and a compiler built from its own formatted source agrees
with the new golden.

## D285 -- An aggregate literal's body is a list

D277 left aggregate literals alone because `Pair {` and `if p {` look the same at the
token level. They are told apart the way the parser tells them apart: a `{` after a
PascalCase name is a literal's, unless a control header -- `if`, `while`, `for`,
`switch`, `when`, `else` -- or a signature's `-> Type` is open on the line, in which
case it is a block's. The first draft forgot the signature and rewrote `-> Sink {` as
a one-line literal body, which a compiler built from the formatted sources refused to
parse; that check is why the rule was found before the golden moved. With it, a
literal joins when it fits and breaks one field per line when it does not, exactly as
a type body does, and every compiler and library source still formats idempotently.

## D286 -- Attribute lines sort by name

Section 6: attribute lines stay adjacent to their declaration and sort by attribute
name. A run of consecutive `@` lines at one indent is now sorted in byte order of the
whole line, which is name order first, by a pass over the finished text like the
`use` block's (D274). Duplicates stay a compile error, not the formatter's business.
The format fixture pins `@packed` and `@align(8)` written the other way round.

## D287 -- `os.mkdir` joins the fixed surface, as a bootstrap intrinsic only

D254 left `.neper/<mode>/` as the project's to make because the fixed os surface --
what the C bootstrap seeds, since it ignores per-host variants -- had no `mkdir`, and
named the fix as an intrinsic through every layer. Half of that was wrong: the
self-hosted compiler already has `os.mkdir`, as source in `os.windows.e` and
`os.linux.e`, and a seeded intrinsic of the same name would be `DuplicateName` in every
program on either host and would lose `last_error_detail` for the call. So `mkdir` is
added to the bootstrap alone: one line in its intrinsic table and a C body per host,
`CreateDirectoryW` and `mkdir(2)` mapped through `np_error` like the rest. The
compiler's source calls `os.mkdir` and gets the C body from the bootstrap and the
per-host source from itself; nothing in resolve, lower or the runtime prefixes changes.

A build now makes `.neper/` and `.neper/<mode>/` when the manifest's open answers
`NotFound`, each level once with `Exists` accepted, then opens again. Both suites
remove `.neper/debug/` before the corpus build and require the build to have made
it; `tests/neper0/os-intrinsics.e` asks the bootstrap's `mkdir` for `Exists` on a
directory that is there.
## D288 -- A* in integers, a tree that names its action, and forgiving input

`e.game.ai` and `e.game.input`, the last pair before `netsync`.

**`e.algo.graph` is deliberately not used.** Its shortest-path answers carry `f64`
distances, and a float comparison landing differently on two machines sends two agents
down two different paths -- which desynchronises a lockstep session exactly the way a
float position would. So `path_grid` is A* with integer costs written against the tilemap
directly, over a binary heap keyed on `u32`. The duplication is the price of the
determinism the rest of this core rests on, and the registered dependency was removed
rather than kept as a fiction. The heuristic is Manhattan, admissible for four-way
movement at unit cost and therefore optimal; a diagonal grid would need a different one,
which is why the choice is written down rather than assumed.

**A behaviour tree names its action rather than performing it.** Conditions are answered
by the caller before the tick as a flat `[]const bool`, and an `Action` node reports its
id through an out-parameter while `run` returns `Running`. That keeps the tree pure data
-- a constant table a game can author -- and needs no function pointers. The cost is that
the caller evaluates every condition whether the tree reaches it or not, which is the
right trade while conditions are cheap predicates over game state; it is also the same
shape `e.game.dialog` took for its guards, deliberately, so the two read alike.

**Input buffers, because an action game is unplayable otherwise.** A player who presses
attack three frames before the animation allows it did not mean "do nothing", and a game
answering only `pressed` tells them they did. `buffered` remembers a press for a window of
ticks and `consume` takes it so it fires once -- a caller that asks and acts without
consuming will act again next tick, which is the usual double-attack bug, so the two are
separate calls rather than one. A held key the device re-reports each tick does not
refill the buffer, since `apply` ignores a code that repeats its current state. Opposite
axis keys cancel rather than the later one winning, which is what a player pressing both
actually expects.

Both are `partial`. `path_grid` takes caller-owned `Scratch` rather than an arena, like
every other module here; a push that cannot grow the heap drops the candidate rather than
failing, so a caller who undersized its scratch gets a possibly-suboptimal path instead of
none.

link/game_mind pins 74 checks with four negative controls. The path expectations came from
an independent A* over the same map -- eleven tiles around a gapped wall -- and the fixture
additionally proves every step is one tile from the last and lands on open ground, so a
path that were merely the right length would still fail.

## D289 -- `-` reads stdin on `tokens`, `parse` and `fmt`

Section 4 says `-` reads UTF-8 source from stdin with `--path` as its identity, and
section 6 that `fmt -` writes only the formatted source. What blocked it was the same
gap as D287's: the bootstrap's fixed surface had `stdout` and `stderr` but no `stdin`,
while both per-host `e.os` sources already had it. So `os.stdin` is added to the
bootstrap alone -- a table line and a body per host, `GetStdHandle(STD_INPUT_HANDLE)`
and descriptor 0 -- and the bootstrap's Windows read now takes `ERROR_BROKEN_PIPE` as
the end of the stream, as the PE runtime prefix always did.

`source.load_stdin` reads the handle to its end without closing it. `tokens` and
`parse` take `-` and then require `--path`, usage otherwise, exactly as section 4
says. `fmt-file` takes `-` on all three forms and an optional trailing `--path
VIRTUAL.e` -- the short `fmt` spelling carries it through -- with the identity the
`--path` spelling, else the operand's basename, which for `-` is `-` itself: the plain
form writes source and names nothing. Both suites pipe a fixture in under its
basename and require the file's own golden, and pin `tokens -` without `--path` as
usage. `index -` stays out: it loads a module graph from a path.

## D290 -- `--absolute-paths` adds `absolute_path` beside the operand's identity

Section 2: machine output carries no absolute path unless `--absolute-paths` is
passed, and then a separate `absolute_path` field is added and never replaces the
source identifier. `tokens`, `parse`, `check` and `index` take the flag; every source
object that names the operand gains the field, a source object naming any other
module -- a generated runner's, a dependency's -- does not, and the schema already
allowed it. The spelling is the operand as given when it is already absolute -- a
leading `/` or `\`, or a drive letter -- and otherwise the current directory, the
host's separator and the operand as given; `.` and `..` segments are kept, since the
field is a spelling and not an identity. For `-` there is no directory to spell and no
field is written.

`os.current_dir` is what it needed, and it followed D287 and D289 onto the bootstrap's
fixed surface: a table line and a C body per host, `GetCurrentDirectoryW` and
`getcwd`, the self-hosted side having the per-host source already. `main` sits at
the bootstrap's local cap, so `check-file`'s flags moved out of it into `check_flags`,
which reads `--json`, `--path` and `--absolute-paths` in any order after the four
positionals; the count-shaped matching it replaces accepted the same forms. Both
suites take the field out of a `check` stream over an absolute operand and a `tokens`
stream over a relative one and require the golden, having first required the field
with the expected spelling.

## D291 -- A Linux build writes its executable executable

D231 launched a Linux program through `sh -c 'chmod +x -- "$0" && exec "$0" "$@"'`
because the fixed surface opened files 0666 and had no way to change that; D240's
test runner went the same way with the test index as `$1`. `os.set_mode` now follows
D287, D289 and D290 onto the bootstrap's surface -- `chmod(2)`, and on Windows the one
bit a mode has there, read-only when no write bit is set, as the per-host source
already does -- and `emit-executable` and the artifact link set 0755 on a file they
wrote for a Linux target, on either host. `run` and the test runner launch the file
itself; nothing about their streams changes, since the shell only ever `exec`ed. The
Linux suite requires the corpus build's executable to be one before running it.

## D292 -- `neper test FILE` works under `.neper/debug/test/`

D276 left `test` out of the short spellings because its positional form takes a
WORKDIR and nothing in `neper test FILE` names one. With D287 the answer is the
project's: the short form is `test FILE [--json] [--project DIR]`, always the stream,
its WORKDIR `.neper/debug/test/` under `--project DIR` or else the project the operand
is in -- the directory `project.discover` finds, the operand's own when it is in none
-- and each level is made when missing, `Exists` accepted. Everything else is the
positional `test-file`: the runner, its map, the child's captured streams, all live
in that directory, and the stream is the same bytes once the runner's path is
normalised. Both suites run the short spelling from a copy of the compiler beside
`lib/` and require the positional form's golden.

## D293 -- An artifact's manifest path is project-relative

Section 7 says artifacts carry project-relative paths; D254 wrote the executable as it
was named, which is relative to wherever the build ran. Now the name is made absolute
under the current directory unless it already is -- `os.current_dir` (D290) is what
this waited on -- and so is the project root, `.` and a trailing `/.` meaning the
directory itself; when the one lies under the other, either separator standing for the
other, the rest is the path with `/` separators. An artifact outside the project keeps
its absolute spelling: not project-relative, but a spelling that finds it, which is
more than the bare name was. `.` and `..` segments are kept, as in D290. Both suites
read the corpus build's artifact from the manifest by its project-relative spelling.

## D294 -- `neper check` and `neper test` with no operand are the project

Spec section 13: without a `FILE.e`, `check` and `test` operate on everything under
the project's roots. The short form now takes that shape: `check` or `test` with no
operand, or with a `--` flag first, is the project the current directory is in --
`project.discover` from a name beside it -- or `--project DIR`, run as
`check-project` or `test-project` with WORKDIR `.neper/debug/check/` or
`.neper/debug/test/` under that project, made when missing (D292's helper, given the
leaf). Both suites run each from inside a corpus project and require the project
form's golden.

Doing so found the suites' short-form binary standing beside the bootstrap's three-
file `lib/e` copy under `build/<host>/`, where a project outside the repo has no
toolchain `e.atomic` for its test runner; the earlier short-form steps passed only
because their operands lay in the repo, whose own `lib/` served. The suites now give
that binary a real toolchain layout, `build/<host>/short/` with the whole `lib/`
copied beside it.

## D295 -- `fmt FILE` formats in place; `fmt` alone formats the project

Section 6 says `fmt --check` writes nothing, which is only worth saying of a command
that otherwise writes; and section 13 says `fmt` with no operand covers every `.e`
under the project's roots. D234 and D255 had the short `fmt FILE` print the canonical
text, which is `-`'s job. Now `fmt FILE` writes the canonical text back into the file
when it differs and nothing otherwise -- `fmt-file PATH --write` positionally -- with
a refusal still the human lines on stderr and exit 1; `fmt -` prints as before, and
`--json` and `--check` on a file are unchanged. `fmt` with no operand, or `--check`
first, is `fmt-project DIR --write|--check`: every `.e` under the project's `src/`
and `lib/` in byte order (D262's walk), formatted in place, or under `--check` each
non-canonical file named as an E-FORMAT-0001 line on stderr with exit 1. A `--json`
stream over a project waits for a merged shape like `check-project`'s. Both suites
format a one-file project and a copied file to the corpus's canonical text.

## D296 -- Quantised deltas, and guessing ahead of the server

`e.net.snapshot` and `e.game.netsync`, the last pair, and the two that only make sense
together: a predictor with nothing to compare against cannot detect that it guessed wrong.

**Quantising is what makes replication affordable, and integers are what make it agree.**
A field is an offset into a state array, a range and a width on the wire; a position that
matters to a tenth of a unit over a thousand-unit map is ten bits, not thirty-two. Both
sides round to nearest with the same integer arithmetic, so a decoded value is the same
value on both machines -- with floats it would be the same value *almost* always, which
in a rollback scheme is the same as never.

**A delta is one presence bit per field, then the fields that moved.** A still world costs
a bit per still field rather than a field per still field, which is the entire economics of
state replication. The comparison is on the *quantised code* rather than the raw value: a
change too small to survive quantisation is not a change, and sending it would spend a
field to convey nothing. A field the sender omitted keeps the baseline's value, which is
what makes the delta lossless against that baseline rather than merely small.

**Prediction repeats the last input.** A player holding a direction keeps holding it, so
repeating is right far more often than zero would be, and the guess is stamped with the
tick asked for rather than the tick it came from. Reconciliation compares the
authoritative state against what this peer simulated byte for byte -- a comparison that is
only meaningful because the whole engine core is integer. A frame older than the one
already confirmed is `Late`: the network reordered it, and acting on it would undo a
correction already applied. `recoverable` answers whether the replay window still fits in
the input ring, because a replay whose inputs have been lapped cannot be exact and the
caller should know rather than silently resimulate from nothing.

`encode` adopts the state it just sent as the peer's new baseline. That is deliberate and
it is also the risk: the sender assumes the frame arrives, so a transport that can drop has
to re-acknowledge, which is what `Peer.acked` carries. Registered dependencies on
`e.data.ring` and `e.bytes` were dropped -- the ring is indexed by tick modulo its length,
which needs no ring type, and the bit packing is here rather than borrowed.

One language finding worth recording: **`u32(-37)` traps.** Conversions are range-checked,
which is the right default, but it means reinterpreting a negative value's bits has to go
through `i64` and an explicit mask. The first `store` written here trapped on the signed
field, and the fixture caught it.

link/game_net pins 66 checks with five negative controls, including the exact wire widths
-- 28 bits for a full snapshot of three fields, 3 for an unchanged delta, 13 for one
changed -- so a delta that silently degraded to a full write would fail rather than pass
quietly.

## D297 -- A reject fixture for every code the compiler raises

docs/diagnostics.md registers thirty codes; the corpus pinned sixteen. Ten more now
have a `reject/` fixture whose `check-file --json` stream is the golden: a `use` of no
module (E-MODULE-0001), a two-module import cycle (E-MODULE-0002) and a module with
two source variants for the target -- `.x64.e` beside `.linux.e` and `.windows.e`,
so the ambiguity holds on either host (E-MODULE-9999), the last two as projects
under `reject/<name>/src/` since one file cannot make them; a function named like a
`use` qualifier (E-NAME-0002); `target` as a local (E-NAME-0003); `try` in a function
that returns no `err` (E-ERROR-9999); `atomic.load` with `.Release` (E-MEM-9999); an
inferable generic parameter that nothing fixes (E-TYPE-0001); a `ret` of one value
where two are declared (E-TYPE-0003); and an `i32` as an `if` condition, the
catch-all E-TYPE-9999. What stays unpinned is E-LINK-9999, an error-hash collision
no small fixture produces, and E-GPU, E-SAFETY and E-TOOL-9999, whose subjects do not
yet diagnose. Both suites check every fixture.

## D298 -- `neper index` with no operand indexes the project

Spec section 13: `index` with no `FILE.e` covers every `.e` under the project's roots.
`index-project DIR ROOT ARCH OS WORKDIR --json` is the shape `check-project` and
`test-project` have: every `.e` under DIR/src and DIR/lib in byte order, each indexed
by `index-file --json --path REL` in its own process -- `index-file` now takes the
`--path` identity the other file commands take -- and the symbol, reference and
diagnostic records forwarded under one header, the result carrying the symbol,
reference and module totals, exit 1 when any module failed. Section 5 says a symbol's
`id` is its record number among the stream's symbols, so each child's `id`,
`container_id` and numeric `target_id` are moved up by the symbols forwarded before
it; `null` stays `null`. The short `index` with no operand, or a `--` flag first, is
that over the project the current directory is in, working under
`.neper/debug/index/`. tests/conformance/tools/index_project pins a two-module
project; both suites compare the positional and the short form to it. `--all`, the
toolchain's `lib/`, is not yet taken.

## D299 -- `e.text.utf8`: the question asked once

`str` is bytes and nothing about the type says they are well-formed. Two modules have
answered that themselves -- `e.text.unicode` and `e.fmt.html` each carry a private
twenty-line reader (D184, D186) -- and `e.text.regex` and `e.text.normalize` are
registered to depend on this one. The module is delivered at `surface: source`, the fence
exactly as `module-apis.md` has carried it, and the `post-m2-library-hardening` gate it
was blocked by is cleared: "basic `e.text.utf8`" was the gate's own wording for this.

**`decode` is strict and never guesses.** Every malformed shape Unicode names answers
`Invalid` at its first byte: a lead of 0xC0/0xC1 or 0xF5 and above, a missing or wrong
continuation, an overlong three- or four-byte form, a surrogate, a scalar past U+10FFFF.
An offset past the end is `Invalid` as well, not a trap. `encode` refuses a surrogate or
a value past the last plane for the same reason: nothing should be able to write bytes
that no decoder accepts.

**`TooSmall` is measured against the width this scalar needs, not four.** A two-byte
buffer takes `é` and refuses `€`, so a caller sizing for what it writes is not made to
over-allocate.

**One replacement per byte.** `iterator_next` turns a malformed byte into U+FFFD and
advances one, so a corrupt run degrades to replacement characters rather than swallowing
the text after it, and the iteration always reaches the end. That is the policy
`e.text.unicode.read_utf8` already has; the W3C "maximal subpart" rule, which would make
a truncated `E2 82` one replacement rather than two, was not adopted, because two modules
that read the same string differently is worse than either rule. `iterator_next_err` is
the strict form: it stops on the fault and leaves the offset on it, so a caller can say
where.

**`byte_offset(s, count)` is `s.len`.** An index equal to the scalar count answers one
past the last byte, so `s[byte_offset(a)..byte_offset(b)]` slices up to and including the
end; one more than the count is `Invalid`.

link/text_utf8 pins 65 checks with real exit codes, including every width boundary in
both directions (U+007F/0080, U+07FF/0800, U+FFFF/10000, U+10FFFF) and five negative
controls that each landed on their own check number.

## D300 -- Analysis still runs under a stale source map

Section 8: a stale or malformed map produces E-TOOL-0001 and the compiler still
analyzes the generated file for its own errors, but the command fails and writes no
artifact. D264 stopped at the diagnostic. Now `load_source_map` reports E-TOOL-0001
and marks the sink instead of exiting; `check` and `build` (and `run`, which is a
build first, and `dis`) go on unmapped, so the operand's own diagnostics follow at
their generated spans, and at the point an artifact or a clean result would be
written they end with the result record and exit 1 instead. The existing stale_map
golden is unchanged, its operand being clean; tests/conformance/tools/stale_map_error
pins a rejected operand under a stale map: E-TOOL-0001, then E-TYPE-0002, two
diagnostics, exit 1, no artifact on either host.
## D301 -- `e.text.normalize`: four forms, one window

Two strings that look the same can differ in bytes -- `é` is one scalar or two -- and a
comparison, a hash or a sort that does not normalize first answers by accident. The module
delivers the four forms of UAX #15 at `surface: partial` (the fence, plus the tables and the
Hangul constants), generated from Python's `unicodedata` at the same 15.0.0 that
`e.text.unicode` reports, by the script beside the fixture that also writes the fixture's
expectations. 81 KB of tables: 5857 single-level decompositions over a 8663-scalar pool,
941 composition pairs, and 72 starters that can be the second of a pair. The module
source is 293 KB with one 169 KB literal; both compilers took it.

**Decomposition is single-level and recursed, as UnicodeData carries it.** Storing the full
expansion would have been simpler to read and three times the pool; the recursion is ten
lines. **Composition exclusions are folded into the table**, not checked at run time: a pair
is listed only if NFC actually recomposes it, so the exclusions, the singletons and the
non-starter decompositions are simply absent, and `compose` needs no second lookup.
**Hangul is arithmetic in both directions** and never touches a table.

**`is_normalized` has no arena, so it normalizes in a stack window, segment by segment.**
A segment is cut before a starter that neither decomposes under the requested form nor can
be the second of a composition -- nothing normalization does can cross such a scalar,
because it cannot be reordered past, decomposed, or absorbed. That last condition is why
the starter-second table exists: Hangul V and T jamo and 24 Indic vowel signs are
starters that compose with what precedes them, and cutting before one would report an
un-composed pair as normalized. The fixture pins Bengali E + AA and LV + T for exactly
that. Most segments are one scalar and a few marks; a segment that decomposes past the
512-scalar window answers `Invalid`, marked as the ceiling it is.

`normalize` allocates by the worst case rather than measuring first: 4 scalars per input
scalar for the canonical forms, 18 for the compatibility ones (U+FDFA), then 4 bytes per
scalar out. Two allocations, no second pass.

link/text_normalize pins 66 checks with real exit codes -- composition reaching past a
lower-class mark and blocked by an equal one, the 18-scalar mapping, a starter whose
decomposition is two non-starters (U+0F73), idempotence -- and seven negative controls,
each landing on its own number. Three of those controls first came back passing: the
`sed` patterns carrying `\x` escapes never matched, so the check was never broken. The
controls were redone through a Python substitution. A control that cannot fail is not a
control, and this one nearly went unnoticed.

## D302 -- One NIR tier for every program, and a capacity that says so

The NIR pools were allocated in two tiers: 32768 instructions for any program under 257
functions, sixteen times that above. The gate was not a flag, so an application could
not opt out, and the small tier was overrun twice in practice -- the `e.math` fixture at
880 checks had to be split into families (D147), and `e.text.regex` was being planned as
two fixtures for the same reason. When it filled, the diagnostic read `cannot lower
`main`: lowering failed: NIR capacity exhausted`: it named the function being lowered
when the pool ran out, which is the program's last function and never its cause, and in
one reproduction here it pointed at `lib/e/str.e:564` -- a string helper blamed for the
size of the program calling it.

**Every program gets the compiler's own tier.** The root arena is reserved and committed
as it is touched (D133) and `mem.alloc` is a bump, so a pool a small program fills a
tenth of costs a tenth of its pages; the gate saved address space, not memory. The
reservation is about 85 MB against the compiler's 1 GiB arena, which already held this
tier and two oracles to build itself. The tier stays fixed -- growable pools are the
production answer and wait for a program past half a million instructions to exist.

**The capacity diagnostic names the pool, its size and the program.** `NIR instruction
capacity (524288) exhausted while lowering `f`: the program so far is N functions, B
blocks and I instructions; the pools are sized once per program, and a program this
large has to be split.` The pool is found at the report site by asking the builder which
count reached its length, so `nir.e` carries no new plumbing. The limit is recorded in
the diagnostic registry as an implementation limit; it stays under `E-TYPE-9999` because
a new code is a specification change.

**The ceiling behind the ceiling.** With lowering no longer the first to fail, a
3000-check `main` was refused by code selection: `codegen_x64` had a flat 8192-entry
block table per function, and `regalloc`'s ranges and allocations and the branch
fixups were flat too, while their siblings (`relocations`, `line_entries`) were already
sized from the lowered program's counts. All four are now sized the same way; a
3000-check function compiles and runs. The next one is not in this decision: at 15000
checks the parser reports `E-SYNTAX-9999: unexpected end of line` at line 8741, which is
the program-wide pool of 65536 syntax nodes in `init_cli_graph` filling and `parse.e`
answering `InvalidSyntax` for it -- a capacity indistinguishable from a typo, and the
benchmark's 14,700-line ceiling by another route. That is its own decision.

Verified by shrinking the instruction pool to 4096 and reading the message, by the
3000-check program against the previous compiler (refused) and this one (runs), and by
both suites, which build the compiler with itself under the same arena.

## D303 -- Measure the compiler, then index its names

The target is a compiler that takes millions of lines, and the first honest number was
6,000 lines a second: the compiler builds its own 42k lines in 7.4 s. Nothing had ever
measured where that goes, so the first change is the instrument: `emit-executable
--time` prints a line per phase on stderr -- load and parse, resolve, check declarations,
check bodies, inline oracles, lower, prune, codegen setup, regalloc and codegen, link --
with milliseconds since the previous one. The phase subcommands (`nir-file` and the
rest) could not serve, because each prints its whole result and the printing dominates.
The state rides on the report sink like `--json` does, because `main` is at the
bootstrap's 256-local limit and a new local there fails with an unrelated type error
at an unrelated line.

**The profile, at 40k lines in 80 modules, was not what a compiler's profile usually
is.** Parsing ran at 340k lines a second and code generation took 38 ms of 3.1 s.
Two-thirds of the time was in resolve and check declarations -- the phases that look at
names, not code -- and the exponent from 10k to 40k was near one. Not a hot spot: a
slow constant, about a million instructions per declaration.

**Every name lookup was a walk over every declaration in the program.** `resolve.find`
scanned all symbols for a (module, space, name), and `add` called it, so building the
symbol table was N^2; the checker's `find_function`, `find_aggregate`, `find_alias`,
`find_constant` and `find_global` each scanned their whole table by (module, name), and
every reference in every body paid one. `src/lookup.e` is the hash index those walks
become: open addressing over (module, table, name), FNV-1a with the wrapping operators
`em.e` already hashes with. It is named `lookup` because a `use` qualifier is reserved against every local of the importing module (spec section 5), and `index` is a local 42 times in the checker. It fills lazily -- a finder indexes its table's tail before
probing, so the tables' seven append sites are untouched, first match still wins on a
duplicate, and a caller that never attaches an index keeps the scan. The entries array
is reserved at four rows per pool row but the live table starts at 64 and moves to the
region after itself at double the size when half full, zeroing only that region, so a
small program commits a few pages: the same reserve-and-commit discipline as D133.

At 40k lines: resolve 831 -> 332 ms, check bodies 351 -> 194, lower 646 -> 377, the
build 3.1 -> 2.1 s, the answer unchanged. Check declarations went 1075 -> 979, and that
is the finding that decides the next step: every collector -- aliases twice, constants,
aggregates, signatures, then bodies and lowering -- re-parses and re-tokenizes every
module from its text, because the graph's node pool holds one module's tree at a time
and each pass rebuilds it. A module is parsed six to eight times per build. (It also
corrects D302's account: the 65,536-node pool is per module, not per program.) The fix
is not to cache the trees, which would make the front end hold every tree of a
million-line program at once; it is to run every phase on one module at a time in
dependency order, which is D304 and the shape the target asked for.

The benchmark generator is under `benchmarks/scale/`: a DAG of modules of log-normal
size, each function a loop with a branch and a cross-module call, and `main` folding
every module's root through a checksum that the generator evaluates independently. It is
generated and says so; what it has that a single file does not is the shape -- thousands
of files of unequal size and calls that cross them. 40k lines in 80 modules peaks at
83 MB of working set.

## D304 -- The front end runs one module at a time, in dependency order

D303 found that every collector -- aliases twice, constants, aggregates, signatures,
then bodies and lowering -- re-parsed and re-tokenized every module from its text,
because the graph's node pool holds one tree and each pass rebuilt it: six to eight
parses per module per build, and most of the check-declarations phase. The cure is not
to keep every tree (a million-line program would hold a million lines of trees) but to
ask for each module once per sweep, which needs an order in which a module's imports
are already known when it is looked at.

**`graph.order` is `visit`'s post-order.** The cycle check already walks the import
graph depth-first; recording each module as it finishes gives every module after the
ones it imports, with the root last. **Every parse into the pool goes through
`graph.parse_module`, which remembers what the pool holds**, and the two tokenizers
remember their module the same way; so the twelve parse sites and eleven tokenize sites
are unchanged in shape, a request for the module already in the pool costs nothing, and
a request for another one is always correct because it is always what the pool holds.
Nothing else parses into the pool.

**Two sweeps, not one.** The checker's `begin_declarations` seeds the intrinsics and
resets the tables; `declarations_module` runs the eight declaration steps on one
module -- aliases with placeholders, constants and globals, aggregates registered then
collected, aliases retyped in place now that their aggregates exist, field types
resolved and cycles checked over the rows this module added, signatures -- and
`finish_declarations` evaluates the constants that reach a call once every signature is
in. Then `bodies_module` for every module and `finish_bodies` for the instances they
made. Bodies could not join the first sweep: every generic path tests `function_index <
signature_function_count` to tell a template from an instance, so every template has to
precede every instance, and bodies are what make instances. The resolver got the same
`begin` and `module` halves. The whole-program passes stay for the incremental artifact
build, which decides its `keep` mask between declarations and bodies, and for every
other caller.

**Globals are laid out in graph order whatever order they were collected in.** The one
table whose order reached the image was the module-scope `var`s: `declare_globals` walked
`c.globals` in collection order, the artifact linker lays them out by artifact, which is
graph order, and link/module_var compares the two executables byte for byte. So
`declare_globals` walks modules in graph order and records each global's NIR index on the
checker's record for `global_address` to read. All nine artifact-linked fixtures are
byte-equal again.

At 40k lines in 80 modules: check declarations 979 -> 163 ms, resolve 332 -> 176; the
build 2.1 -> 1.1 s, 3.1 s before D303. The compiler building itself: 7.4 -> 5.0 s, and
the fixed point holds. A module is now parsed three times per build -- once per sweep,
once for lowering -- and the third is D306's.

Two things the bootstrap taught along the way. `use X` reserves `X` against every local
of the importing module, which is why D303's index module is `lookup`. And `main` is at
exactly 256 locals, the bootstrap's limit, now reported as such; the sweeps are helpers
so that `main` gains none, and the one flag it needed is spelled inline at its three uses.

## D305 -- Code generation stops walking every value per instruction

With the front end per module (D304), the compiler building itself spent 2.8 of its
5.0 seconds in register allocation and code selection -- and the 40k-line benchmark
spent 36 ms there. The difference is function size: `main` has ten thousand values, and
three loops were quadratic or worse in it. Every change here makes the same decisions
as before, value for value: the benchmark executable and the compiler itself come out
byte-identical from the old allocator and the new.

**The allocator was cubic.** For each value, for each of ten registers, it walked every
earlier value to ask whether one still in that register was live, and on a spill walked
them all again for the live one ending last. Both answers depend only on the largest
(last, value) among the values a register holds, so each register keeps them in a
max-heap and answers from its top; the spill pops it. 2758 -> 1793 ms, and the heaps
are taken from the arena for the length of the call and given back -- `mem.mark` and
`mem.reset`, the first use of either in the compiler.

**The live mask was recomputed per call.** Every call and every fixed-register sequence
asked which registers held a value live across it by walking every value. Now the mask
at every instruction of the function is built once, as one difference array per register
and a prefix sum -- the values plus the instructions, not their product -- and read.
Every instruction also scanned every block to find the one starting there; blocks begin
in instruction order, so a cursor does it. 1142 -> 780 ms of selection.

**Folding hashed every relocation in the program per function.** Identical-code folding
copies a function's bytes and relocations for hashing, and both the count and the copy
walked all relocations. They ascend with the code, so a lower-bound search finds a
function's run: 237 -> 70 ms, and the artifact writer's `write_code` gets the same run.

The compiler building itself: 5.0 -> 3.4 s, with every phase now under a second; the
fixed point holds. `--time` gained sub-timers for allocation, selection and folding.
The bootstrap's program-wide `use` table was at its limit of 128 and `regalloc.e`'s
`use e.mem` was the 129th; `UseDecl` is a few words, so it is 256 now. The self-hosted
resolver also refused what the bootstrap accepted -- a `mem.` call in a module without
`use e.mem` -- which is the right order for the two to be strict in.

## D306 -- Two million lines: pools sized from the program, and the constants underneath

The target set in this stream was a compiler that takes millions of lines, measured on a
generated program of two million lines in two thousand files. This decision is what it
took to get there from D305, in the order the profile found it, and the measurement.

**Pools are sized from the program, not the arena.** The first attempt scaled every pool
by the arena's gibibytes, on the reasoning that a reserved page costs nothing until
touched. On Windows that is false one level down: the runtime commits up to the
*allocation* offset (D133's chunked growth), so a pool sized for millions of lines was
charged in full by every build, and a 64 GiB compiler spent its first seconds committing
40 GB. Linux is touch-native and would not have shown it. So the loader now measures
the program -- `graph.total_bytes` and `largest_bytes`, since every module's text is read
before anything else is done with it -- and every pool after loading is `base + bytes /
per`: symbols a sixteenth of the source, instructions a fifth, tokens and trees the
largest module. The tree pool grows to the largest module as the loader meets it,
doubling and leaving the smaller one behind. Commit is proportional to the program on
both hosts; the 2M-line build peaks at 2.9 GB. A debug-built compiler fills every
allocation with 0xCD (§11) and so touches every pool it allocates -- 8.4 GB for the
same build -- which is what `--release` is for; the numbers below are a release compiler.

**The constants, in the order the profile surfaced them.** `--time` and a Linux `perf`
run mapped through the image's own symbol table (`benchmarks/scale/symmap.py` is the
mapper) found each:
- `intern_function` and `intern_string` scanned their tables per call site and literal;
  both have `lookup` indexes now. `prune_references` compacts the references, which had
  left the index pointing past the table and every codegen-time intern on the scan.
- `resolve_calls` matched every relocation's target by scanning every function by name;
  `function_for_reference` did the same per call instruction in the prune. Each
  reference is matched once by one pass over the functions (`resolve_reference_targets`).
- The symbol table decided "placed" by scanning earlier functions, found a function's
  end by scanning all of them, and found its line rows by scanning all rows -- three
  quadratics per function. Placed functions and rows ascend with the code, so a running
  maximum and two cursors do it.
- `lower_function_index` zeroed a 256-entry `DeferState` -- 230 KB, a `CallInfo` and a
  token per entry -- for every function, byte by byte. One per module sweep now.
- `sha_k` rebuilt the sixty-four round constants on the stack per round; built once per
  block. The manifest hashes every source file of every build.
- `layout.aggregate_index` scanned the aggregates by name; it uses the checker's index.
- The lexer probed up to twenty-eight two- and three-byte operators per punctuation
  token through a bounds-checked call each, and compared every identifier against all
  thirty-four keywords; three bytes read once and a first-letter dispatch.
- **Aggregate copies and fills were byte loops** -- five instructions per byte -- and
  every token returned by value, every node or instruction read from a table, every
  `= zero` paid it. Eight bytes per iteration with the byte loop as the tail; the bytes
  were checked against GNU `as`. This was the single largest constant in the compiler.
- `nir.Instruction` was 180 bytes because it carried a whole 120-byte `lex.Token`;
  nothing downstream reads more than its start, end, line and column, so it carries a
  32-byte `Site` and rebuilds a token for the few callers that want one. This is what
  puts the compiler's own build back under the 512 MiB default arena the suite's
  own-stage test emits it with -- at 484 MB, which is the next thing to widen: the
  machine-code buffer and the image buffer hold one byte per `usize`.
- Three ceilings the 2M program hit: `lowered_modules` at 128, the symbol table's paths
  at 512 per program, and the image buffer sized from the code *before* the symbol
  table was appended to it with a mebibyte of slack. Sized from the program, 8192, and
  after the table, respectively. A fourth stays: a Linux image's arena is a 32-bit
  immediate in its startup stub, so `--arena` tops out under 2 GiB there.

**Measurements**, one host, release compiler, best of three unless noted:

| program | lines | modules | compile | peak | image | run |
|---|---|---|---|---|---|---|
| compiler itself (debug compiler) | 42k | 34 | 7.4 s -> 3.4 s | -- | 5.9 MB | -- |
| scale, 40k | 40k | 80 | 3.1 s -> 1.1 s | 83 MB | 0.5 MB | -- |
| scale, 200k | 184k | 200 | 26 s -> 4.9 s | 1.4 GB | 1.3 MB | -- |
| scale, 2M | 1.84M | 2000 | 36-58 s | 2.9 GB | 12.7 MB | 3.3 s |

Every output checks against the generator's independently evaluated answer. Two million
lines is 32k to 46k lines a second, against 6k at the start of the stream. Every change
here is output-preserving for the programs that fit before -- the 40k image and the
compiler's own image are byte-identical from D305's compiler and this one when the
operand is spelled the same way, which cost an hour to learn -- except the copy loops,
which change every image and hold the fixed point and the artifact fixtures.

What the profile says now is that the remaining time is lexing and parsing (a third),
then checking and lowering at a few microseconds per node. The next order of magnitude
is not another scan; it is the per-module architecture (parse once, not three times;
NIR and machine code per module, discarded) and then the lexer's inner loop.

## D307 -- The code buffer holds bytes

`emit_x64.Buffer` held one byte per `usize`. The machine code, the image and every
object file were written through it, so a build's two largest allocations were eight
times the size of what they held: 4.4 GB of code buffer at the first 2M-line attempt
(D306), and 55 MB of image buffer in the compiler's own build, which is what stood
between it and the 512 MiB default arena.

The buffer is `[]u8` now. `byte` narrows on the way in, `pack` is a copy, the two
patchers write narrowed octets, and the readers that fed bytes back into another
buffer -- the two linkers, the two object writers, the artifact writer's code copy,
the artifact linker -- widen on the way out. The disassembler still reads a byte per
word and is the one place a range is widened before use, since it serves `dis` alone.
The self-tests that pinned bytes compare against `u8` literals now.

Output is byte-identical to D306's for the 40k program and for the compiler itself.
The compiler's own build peaks at 424 MB instead of 484 -- after the instruction pool
went from a sixth of the source to a quarter, because the 2M program's 8.3 million
instructions were three percent over a sixth and D302's diagnostic said so, by name and
by count. The 2M-line build peaks at 2.1 GB instead of 2.9 and takes 44 s.

## D308 -- `--stats`: what a build was, measured after it

`emit-executable --stats` and `run --stats` print a table after the image is written:
the program (files, lines split into code, comment and blank, module sizes at the
minimum, median and maximum, functions and instances, imports, types, constants, vars,
errors, parse nodes, externs, and each attribute counted -- `@test`, `@gpu`, `@import`,
`@nocheck`), the build (mode, compiler version, host, target, hot and cold modules --
those with a function in the lowered program and those loaded and never reached --
threads, image size), the wall time and every phase's time, and with `run` the
program's own time and exit code. `--stats-full` adds every pool's capacity beside how
much of it was used, which is the table D306 sized by hand.

**Nothing that costs anything runs during the build.** Counting lines, parsing every
module once more for its nodes and attributes, and sorting the module sizes happen in a
pass after the file is written, so the phase times are the build's own; what the
driver records as it goes is a clock read per phase, a store per pool allocation and
the run's status. The table goes to stderr, where `--time` goes, so `run --json`'s
stream on stdout stays a stream. Numbers are grouped in thousands with an apostrophe.

Two rows read `n/a`: the compiler's own peak working set and the program's. There is
no `e.os` intrinsic for a process's peak memory, and adding one is D291's procedure --
the bootstrap's seed, both C runtimes, both assembly runtimes and the checker's seed --
which is its own decision. `benchmarks/scale/peak.sh` measures it from outside
meanwhile.

## D309 -- `run --release` means it, and the oracles are sized like the builder

Producing D308's table for the two million lines in both modes found three things.

**`run --release` was silently ignored.** The release gate knew `emit-executable` and
`emit-em-all`; the usage line listed the flag for `run` too, and `run` took it and built
in debug. The table's `compile mode` row read DEBUG under a command that said release,
which is what caught it. `run` is in the gate.

**The inlining oracles' pools were not sized with the rest.** Their signature table was
a flat 4096, and past it every function failed as invalid control flow -- exactly what
the comment on `init_cli_nir` had warned of for the main builder in D-era terms -- and
their instruction pool was a quarter of the main one. An oracle lowers every candidate
function before it knows which are short enough to inline (D207), so it needs the main
builder's sizes, and has them.

**The finding those fixes exposed.** A release build lowers the program three times:
once per oracle, over everything, then for real. On the 2M-line program that is 61 of
101 seconds and 3.3 GB of the 5.4 GB peak, for an image 28% smaller and a run 2%
faster. An oracle only needs bodies of forty instructions or fewer; lowering eight
million instructions to find the short ones is the next thing to remove. Until then a
release build costs twice a debug build, which is the wrong way round.

D308's `hot modules` and `cold modules` rows are `reached modules` and `unreached
modules`: they count modules with a function in the lowered program against those
loaded and never called, and "hot" and "cold" are builds, not modules. There is no hot
build on this path: `emit-executable` and `run` compile everything from source every
time; the artifact path's edge rule is where incremental lives, and a checker that
reads an imported module's interface from its artifact is the step that would make a
one-module edit cost one module.

The 2M-line program, release-built compiler, warm file cache, both modes:

| | DEBUG | RELEASE |
|---|---|---|
| wall | 47.1 s | 101.4 s |
| of which inline oracles | -- | 60.8 s |
| compiler peak (external) | 2.1 GB | 5.4 GB |
| image | 12.7 MB | 9.1 MB |
| run | 3.19 s | 3.14 s |
