# Compiler optimizations: survey and applicability to Neper

Survey of what the fastest-executing compilers do (LLVM, GCC, ICX, Go, Rust, Cranelift,
HotSpot, V8, LuaJIT, ISPC) against Neper's backend as read on 2026-11-03 from
`src/regalloc.e`, `src/nir.e`, `src/codegen_x64.e`, `src/lower.e` and
`docs/gp-performance.md`. It is a survey, not an audit: "unknown" means the code was not
read for it. Open work is the queue items C242-C253 in `work-queue.json`; this file holds
the reasoning and is not a second list.

Neper's identity is compile speed on par with C (178 ms against 164 ms on the GP
workloads), so every pass must be near-linear. Measure with cachegrind instruction
counts and `benchmarks/gp`.

## Already in place

- Oracle inlining with a flat 40-NIR-instruction cap (D207, re-measured D1521).
- `promote_locals` (mem2reg), dominator-based `elide_null_checks`, `hoist_frame_addresses`.
- Whole-program dead-function elimination, unreachable pruning, comptime branch folds.
- Linear-scan allocation over whole live ranges, call-aware register preference (D1607),
  live-only call saves (D226).
- Packed vector ops through xmm0-xmm3 scratch; no vector register class (D786, D1524).

## Measured gaps (docs/gp-performance.md)

- GP-09 SIMD Base16: 1576 ms against C 50 ms, from scalar interleave and pair assembly.
- GP-10 CPU backend 1911 ms: the deliberately serial debug backend (D38), not codegen.
- Struct copy codegen was 16% of all instructions (D930-D933).

## Catalogue

Value: H, M, L. N is Neper's state.

### Mid-end scalar

| Optimization | N | Value |
|---|---|---|
| SSA, mem2reg | partial | done |
| SROA | no | H |
| SCCP, constant propagation | partial | M |
| Instruction combining, algebraic simplify | unknown | H |
| GVN, CSE, local value numbering | no | H |
| Dead store elimination, store-to-load forwarding | no | M |
| Copy and memcpy elision, return-value optimization | no | H |
| Bounds-check elimination, range analysis | null checks only | H |
| Overflow-check elimination | no | M |
| Jump threading | no | M |
| Interprocedural SCCP, argument specialisation | no | M |
| Alias analysis from language guarantees (noalias) | no | H if guaranteed |
| Tail merging, sinking; GVN-PRE; ICF; dead argument elimination | no | L |

### Loops

| Optimization | N | Value |
|---|---|---|
| LICM | no | H |
| Induction-variable strength reduction | no | H |
| Counted-loop detection, range-check hoisting | no | H |
| Loop rotation | no | M |
| Unrolling | meta `for` only | M |
| Idiom recognition (memcpy, memset, popcount) | no | M |
| Unswitching, fusion, interchange, tiling, polyhedral, software pipelining | no | L, skip |

### Vectors and floating point

| Optimization | N | Value |
|---|---|---|
| Float/vector register class | no; floats live in GPRs as bits | H |
| Shuffle, interleave, pack selection | scalar lane loops | H |
| Auto-vectorisation, SLP | no | M, after the register class |
| FMA contraction | no | M |
| ISA multiversioning | no | M |

### Inlining and interprocedural

| Optimization | N | Value |
|---|---|---|
| Cost-model inlining | flat cap | M |
| Tail calls | no | M |
| LTO | whole-program already | done |
| Hot/cold splitting, function reordering | no | L |

### Instruction selection and scheduling

| Optimization | N | Value |
|---|---|---|
| Addressing-mode folding | partial | check |
| lea, multiply by constant as shift/add | unknown | M |
| Division and modulo by constant (magic multiply) | unknown | H |
| Compare-branch fusion, test, cmov, setcc | unknown | H |
| Rotate, bswap, popcnt, lzcnt, BMI | unknown | M |
| Peephole | unknown | M |
| Rule DSL for lowering (ISLE, Go rules) | no | M structural |
| List scheduling | no | L on x86, M on a64 |

### Register allocation

| Optimization | N | Value |
|---|---|---|
| Interval splitting (second-chance linear scan) | no | H |
| Copy coalescing, hints | partial | H |
| Spill weights by loop depth | unknown | H |
| Rematerialisation | no | M |
| Shrink-wrapping | no | L |

### Layout and control flow

| Optimization | N | Value |
|---|---|---|
| Likely/unlikely hints on trap paths | possibly | H |
| Block placement, loop alignment | no | M |
| Branch folding, empty-block elimination | unknown | M |
| Switch lowering (tables, bit tests) | unknown | M |
| PGO, BOLT | no | skip until a profile source exists |

### Not applicable

Escape analysis (arenas by design), devirtualisation (no virtual dispatch), GC barrier
elision, JIT tiering, superoptimisers, struct field reordering (layout is language
visible).

## Compilers worth borrowing from

- Cranelift: egraph mid-end (GVN, rewrites, LICM in one pass), ISLE rules, regalloc2.
- Go: about fifteen cheap SSA passes, a rule-driven rewrite, the `prove` pass.
- HotSpot C1, V8: linear scan with interval splitting, range-check elimination.
- LuaJIT: loop-invariant hoisting, store-to-load forwarding.
- Zig self-hosted backend, TCC, QBE, Cuik: minimal pipelines.

## Order

1. C242 float/vector register class, C243 vector shuffle ops, C244 SROA and copy
   elision, C245 value numbering and simplify.
2. C246 LICM and strength reduction, C247 bounds-check elimination, C248 trap hints and
   layout.
3. C249 allocator splitting, after C242 because both change the allocator's data.
4. C250 inliner cost model, C251 tail calls, switch and branch folding.
5. C252 first decides whether the spec guarantees non-aliasing; if it does, it unlocks
   safe LICM, forwarding and vectorisation without a general alias analysis.

## Which targets each item reaches

Checked 2026-11-03 against `src/`: one shared NIR (`nir.e`, `lower.e`), and
`regalloc.e` is used only by `codegen_x64.e` and `codegen_a64.e`. Nothing here is
implemented yet; this is where each item would land.

| Reach | Items |
|---|---|
| Every target through NIR, OS independent | C244, C245, C246, C247, C250, C252 |
| Shared allocator logic, per-architecture emission | C249, C248 (fallthrough and alignment differ) |
| Per architecture and calling convention | C242 (xmm against v0-v31; System V, Win64, AAPCS64), C243 (`punpck`/`pshufb` against `zip`/`tbl`), C251 (stack arguments, jump-table relocations per object format) |

C245's division by a constant is NIR-level, but its multiply sequence needs `umulh` and
`smulh` lowering on a64.

Targets that get nothing from the register-allocator items: SPIR-V, GLSL and MSL, WASM
(own code paths, not `regalloc.e`), and the serial CPU `gpu` backend (D38), so GP-10's CPU
time is not addressed. The NIR passes may help them; whether the WASM path reaches each
one was not checked and must be confirmed per item. Planned targets (z/OS, C229) would
take the NIR items and need their own backend work for the rest. Each of C242-C252 should
pass fixtures on x64 and a64, and on Windows and Linux at minimum.

## Sequencing against the Android and iOS targets

Android code generation exists (`aarch64-android` and `x64-android`, D5896-D5911,
`docs/android-cross-compilation.md`); open is C224, the Bionic executable and APK. iOS is
C225 and needs an Apple developer identity this repository does not have (see C191), so
it cannot be verified here. Both mobile targets are arm64 and depend on the a64 back end,
which is smaller than x64 (108 KB against 236 KB of source) and borrows x64's
`FunctionContext`.

Mobile support is mostly packaging and runtime work and does not depend on these
optimizations, so the order is:

1. The NIR-level items (C244, C245, C246, C247, C250) now: they help x64 and a64
   together and are verifiable on the existing Windows and Linux hosts.
2. C224 Android in parallel: it touches ELF output and `build-apk.ps1`, almost none of the
   optimization files.
3. The a64 halves of C242, C243 and C249 once a64 code can be run on every change, which
   is C253. Writing NEON register-class code that cannot be run is the risk.
4. C225 iOS last.

## Running a64 code

- QEMU user mode locally. `scripts/a64-differential.sh` runs prebuilt x64 and aarch64
  pairs, x64 natively and aarch64 under `qemu-aarch64`, and requires stdout, stderr and
  exit status to agree. It needs qemu-user, `libc6:arm64` and `aarch64-linux-gnu-gcc`.
  `tests/selfhost/run.sh` also runs a64 builds under QEMU when it and a cross compiler are
  present. Pairs are built by `scripts/a64-differential.ps1` on Windows, so the shell half
  cannot run alone on Linux.
- Five fixtures differ for reasons that are not the back end's: `when_target`, `os_fs`,
  `fs_basics` (QEMU 8.2 has no `openat2`), `os_gaps` (no `PR_SET_SECCOMP`) and
  `debug_dump` (gcore dumps the emulator).
- Native Apple Silicon in CI: `macos-a64` and `macos-corpus` run arm64 Neper binaries on
  `macos-14`. This covers macOS only.
- Not in CI: no Linux job runs a64 (`linux-suite.yml` is x86 and installs no QEMU), and
  `ios-sim` drives a Wasm UI in a simulator, not a64 machine code. C253 closes this gap.
- Not covered by either route: Android behaviour (Bionic, loader, APK), which needs an
  emulator or a device.
- The differential script was read, not run, for this survey.

## Constraints on every item

Near-linear passes, no whole-program fixed point. The C bootstrap is more permissive than
neper-self (MAX_LOCALS, arena, token limits). The self-host check stage2 == stage3 and the
emit sweeps catch miscompiles. Each item needs a fixture that fails if the optimization
miscompiles and a cachegrind or `benchmarks/gp` number showing it helps.
