# C029 — Vec[T,N] / Mask[T,N] and SIMD lowering

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.97 of 1 |
| queue position | 1 of 55 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

From `docs/roadmap.md`, section **M1 — The full CPU language**:

> `Vec[T, N]`, `Mask[T, N]` and the `simd` module (spec §4, D40): the closed width table, register-class passing, and lowering at every `--cpu` level including the split below the vector's width

**Done when:** every item above is implemented in the self-hosted compiler, and
`lib/e` builds and its tests pass under `neper test`; all applicable conformance
fixtures validate byte-for-byte after the specified duration normalization; tooling
streams reconstruct source exactly and validate against the schema; formatter
idempotence holds; every M1 API fence matches extracted source declarations; and the
S0 generated-code benchmark has been rerun with no unexplained regression.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `Vec[T, N]` and `Mask[T, N]` are builtins seeded into e.simd with section 4's closed table, width-aligned layout and `meta.kind/element_type/array_len` answers; every `simd.*` intrinsic but `shuffle` is library source lowered lane by lane over scalar code (D148); section 4's operator table -- IEEE `+ - * /` on float lanes, only `+% -% *%`, the bitwise ones and a scalar shift on integer lanes, `& | ^ ~` on masks -- is checked and lowered lane by lane, plain `+` on integer lanes and every comparison refused (D158); `Vec[T, N]{ ... }` is N positional lanes and `v[i]` reads or writes one, bounds-checked (D159); `shuffle`'s `IDX: [N]u8` is a comptime array parameter, bound from a literal of literals and forwardable by name (D160). a `Mask[T, N]` is register-only (D750): a field, an array element, a slice element, a pointee -- `*Mask` or `&m` -- a module-scope `var`, `mem.alloc`'s element type and `mem.size_of`/`mem.align_of` are each refused under one diagnostic kind naming the position and pointing at `simd.bits(m)`, with a check fixture per position in both suites, but for the written `[]Mask`, which shares `mem.alloc`'s sentence, and the module-scope `var`, which the builtins' seeding order already refuses before the guard is reached. a sixteen-byte lane-wise binary operator lowers to one SSE2 instruction instead of a lane loop (D751): IEEE `+ - * /` on `f32`/`f64` lanes, `+% -%` on every integer width, `*%` on sixteen-bit lanes and `& | ^` on all of them, with section 11's canonical NaN produced lane by lane without a constant pool, checked bit for bit by the `link/simd_lanes` fixture in both suites. `~` on a sixteen-byte integer vector is packed too (D752), as the two instructions no unit has one for: `pcmpeqd` against itself for the all-ones operand and `pxor` against that, carried as `VectorBinary` with the one operand given as both, with a sixteen-lane fixture check whose lanes are all distinct. a sixteen-lane mask's `& | ^` are packed too (D753): its lanes are sixteen bytes of `0` and `1`, so the byte lanes' `pand`, `por` and `pxor` answer them bit for bit with nothing new in the back end, and the sixteen lanes belong to `Mask[i16, 16]` and `Mask[i32, 16]` as well as to a byte vector's mask, all checked in the `link/simd_lanes` fixture over two patterns that differ in every nibble. `~` on a sixteen-lane mask is packed too (D754), and is the one operator that cannot reuse the byte vector's form: a mask lane is a byte of `0` or `1`, so `pxor` against all ones leaves `0xfe` where `0` is wanted and the answer is `pcmpeqb` against zero -- all ones in exactly the lanes that were `0` -- subtracted from that zero, which is the `1` those lanes want. It rides on operation rank 11 with the one operand given as both, loads into `xmm1` so the subtraction is the table's own `psubb` into the register the store reads, and `pcmpeqb` is the only new opcode, with the fixture checking both patterns and that a flipped lane still reduces as a mask lane. an eight-lane mask is packed too (D755): a mask is a byte per lane, so eight of them are the register's low half, which every instruction in the table already operates on and `movlps` -- a quadword in both directions -- loads and stores without reading past the slot; the back end multiplies the immediate's lane code by its lane count for the width, and the closed table keeps a `Vec` from ever being eight bytes, so `Mask[i16, 8]`, `Mask[f32, 8]` and `Mask[u64, 8]` are packed while the thirty-two and sixty-four byte vectors they come from are not, checked over two alternating patterns in the `link/simd_lanes` fixture in both suites. a four-lane mask is packed too (D756): four lanes are four bytes, which `movd` -- the first of these moves to need a mandatory prefix -- carries in both directions, so the same four instructions answer `Mask[i32, 4]`, a sixteen-byte vector's mask, and `Mask[f64, 4]`, a thirty-two-byte vector's, checked over two patterns that agree in two lanes and differ in the other two in the `link/simd_lanes` fixture in both suites. a two-lane mask is packed too (D757), and is the one width the vector unit cannot carry to and from memory on this baseline -- `pinsrw` reads a word but SSE2's `pextrw` only writes one into a general register -- so both directions go through r11, the scratch no value is allocated to: a zero-extending word load and the scalar float path's own `movq` in, that `movq` and a word store out, with the packed operation between them unchanged, which makes `Mask[i64, 2]` and `Mask[f64, 2]` packed and leaves only the masks of more than sixteen lanes on the loop, checked over two patterns that agree in the high lane and differ in the low one in the `link/simd_lanes` fixture in both suites. the masks of more than sixteen lanes are packed too (D758), and want no second register: a packed operation reads no lane it is not given, so an operand wider than one is the same instruction once per sixteen-byte chunk over the chunk's own addresses, which lowering names with the `FieldAddress` its lane loop already uses and the back end never sees -- every instruction it is given is still sixteen bytes -- which packs `Mask[u8, 32]`, `Mask[i16, 32]` and `Mask[u8, 64]` and leaves every mask the closed table has packed, checked over patterns that differ in every chunk in the `link/simd_lanes` fixture in both suites. the thirty-two and sixty-four byte vectors are packed too (D759), which is the chunk loop's condition and nothing else: the wide widths are admitted for every lane type and not for a mask's byte lanes only, so a `Vec[f32, 8]` is two instructions and a `Vec[u8, 64]` four, each canonicalising its own NaN lanes and each loaded by the unaligned move a chunk at offset 16 needs, checked in the `link/simd_lanes` fixture over lanes written in every chunk in both suites. a lane-wise shift by a constant count is packed too (D760), and is the first packed form whose right operand is not a vector: the baseline carries the count inside the instruction -- `psllw`/`psrlw`/`psraw`, their thirty-two-bit three and `psllq`/`psrlq`, with the modrm register field saying which -- so lowering takes the form only when the count folded to a `ConstInteger` it can read and is below the lane's width, which leaves every other count on the lane loop and with it the check that traps on a count the width does not admit. The count rides above the immediate's three fields, where everything written before it is zero, and passes through the chunk loop unchanged, so a thirty-two-byte vector is two instructions with the one count. a shift by a count in a register is packed too (D761), which is the shape D760 left on the lane loop and the baseline does have an instruction for: the count rides in the low quadword of a second register instead of a byte of the encoding, flagged by a bit above the immediate's count field, and the third operand the constant form already named keeps it live for the allocator. Section 11's two halves run in order -- a `cmp` against the width guards a trap naming the count and the width in debug, an `and r10, width - 1` masks in every mode -- through `r10` and `r11`, the registers the allocator never hands out, so the check needs no spill and cannot reuse the scalar path's helper, which shifts through `rcx`. A count the width does not admit is no longer a constant either: it takes this form and traps. The signed sixty-four-bit right shift stays on the lane loop, as there is no `psraq`, and a wide vector reloads the count per chunk, since the back end sees one chunk at a time. Checked in both suites by the `link/simd_lanes` fixture, over all three widths in both directions and across a thirty-two-byte vector's two chunks, and by `link/trap_arithmetic`'s new `vshift` mode, which reads the vector trap's own line, column and message. `*%` on thirty-two-bit lanes is packed too (D762), out of the instruction the baseline does have: `pmuludq` multiplies the low half of each sixty-four-bit lane into the whole lane, and `*%` wants a lane's low thirty-two bits, which are the same bits whichever width the product was taken at -- so two of them, one on the operands as given and one on each shuffled by `0xb1`, cover all four lanes, `pshufd` by `0x08` gathers the low doubleword of each pair of products and `punpckldq` puts the four in order. Seven instructions, nothing new in the allocator, the same selection for `i32` and `u32` since a low half has no sign, and once per chunk for a wider vector, checked in the `link/simd_lanes` fixture over four distinct lanes that each need a high half dropped and eight lanes with one written in each chunk, in both suites. Sixty-four-bit lanes take the third `pmuludq` form (D763): the low halves' product plus both cross products shifted up thirty-two, ten instructions and nothing new in the allocator, checked in the same fixture over `i64` lanes whose product crosses 2^64 and `u64` lanes across two chunks, in debug and release on both hosts. Byte lanes take a `pmullw` form (D764): the bytes unpacked against themselves, since 257 is 1 modulo 256, multiplied as words, masked and packed back, fourteen instructions and nothing new in the allocator, checked over sixteen distinct `u8` lanes, sixteen `i8` lanes and two chunks of `u8`, in debug and release on both hosts; every integer width of `*%` is packed now, and `f16` keeps the lane loop by design, its arithmetic being F16C or AVX-512. `--cpu x64-v3` (D765) lowers every thirty-two-byte vector operation as one VEX.256 instruction over a ymm register, the same selection through the emitter's VEX prefix, the level in the build identity and the manifest, `info` listing the levels, the fixture run at the level in both modes on both hosts

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] a vector register class with an ABI -- `Vec` and `Mask` crossing a call in xmm registers, as section 5 says, where they cross by address today

Notes:

- The one remaining line is an ABI change: `Vec`/`Mask` in xmm registers across a call on both System V and win64 (spec §5). Start by reading how aggregates cross today (`src/lower.e` and `src/codegen_x64.e`, search `by address`) and the fixture `link/simd_lanes`.

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D148` — `Vec[T, N]` and `Mask[T, N]` are seeded aggregates, and `e.simd` is source over their lanes (`docs/decisions.md:2537`)
- `D158` — the lane-wise operators, lowered over the lanes (`docs/decisions.md:2826`)
- `D159` — `Vec[T, N]{ ... }` and `v[i]`: the two spellings, over the same lanes (`docs/decisions.md:2847`)
- `D160` — a comptime array parameter, and `shuffle` with it: `e.simd` at 28 of 28 (`docs/decisions.md:2862`)
- `D750` — A mask is refused at every position that stores a value (`docs/decisions.md:13899`)
- `D751` — One packed instruction per sixteen-byte lane-wise operator (`docs/decisions.md:13919`)
- `D752` — Packed `~` on a sixteen-byte integer vector (`docs/decisions.md:13943`)
- `D753` — Packed `& | ^` on a sixteen-lane mask (`docs/decisions.md:13960`)
- `D754` — Packed `~` on a sixteen-lane mask (`docs/decisions.md:13980`)
- `D755` — The packed forms reach an eight-lane mask (`docs/decisions.md:14005`)
- `D756` — The packed forms reach a four-lane mask (`docs/decisions.md:14036`)
- `D757` — The packed forms reach a two-lane mask (`docs/decisions.md:14068`)
- `D758` — The packed forms reach the masks of more than sixteen lanes (`docs/decisions.md:14098`)
- `D759` — The packed forms reach the thirty-two- and sixty-four-byte vectors (`docs/decisions.md:14127`)
- `D760` — The packed shifts, by a count the compiler knows (`docs/decisions.md:14155`)
- `D761` — The packed shift by a count in a register (`docs/decisions.md:14198`)
- `D762` — The packed multiply on thirty-two-bit lanes (`docs/decisions.md:14238`)
- `D763` — The packed multiply on sixty-four-bit lanes (`docs/decisions.md:14275`)
- `D764` — The packed multiply on byte lanes (`docs/decisions.md:14298`)
- `D765` — `--cpu x64-v3`: the packed forms over ymm (`docs/decisions.md:14321`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `shuffle`: `src/codegen_x64.e`×5‡, `benchmarks/metamorphic/metamorphic.py`×4, `lib/e/simd.e`×2, `src/emit_x64.e`×2†, `src/check.e`×1‡
- `mem.alloc`: `src/main.e`×243‡, `src/tool.e`×79‡, `src/em_link.e`×49†, `lib/e/fmt/json.e`×26†, `src/check.e`×24‡, `lib/e/os.windows.e`×23‡, `lib/e/algo/graph.e`×22, `lib/e/fmt/webp.e`×18†
- `mem.size_of`: `lib/e/bytes.e`×10, `lib/e/gpu/tensor.e`×9, `lib/e/algo/deflate.e`×5, `lib/e/fmt/zstd.e`×5†, `lib/e/math.e`×5†, `lib/e/fmt/gzip.e`×4, `lib/e/fmt/lzw.e`×4, `lib/e/fmt/zlib.e`×4
- `mem.align_of`: `src/check.e`×1‡
- `simd.bits`: `src/check.e`×1‡, `src/main.e`×1‡
- `pcmpeqd`: `src/codegen_x64.e`×1‡, `src/disasm_x64.e`×1†
- `pxor`: `src/codegen_x64.e`×3‡, `src/disasm_x64.e`×1†, `src/lower.e`×1‡
- `VectorBinary`: `src/lower.e`×3‡, `src/codegen_x64.e`×2‡, `src/em.e`×1‡, `src/nir.e`×1†
- `xmm1`: `src/runtime_pe_x64.asm`×46†, `src/runtime_elf_x64.s`×44†, `src/codegen_x64.e`×3‡
- `psubb`: `src/codegen_x64.e`×3‡, `src/disasm_x64.e`×1†
- `pcmpeqb`: `src/codegen_x64.e`×1‡, `src/disasm_x64.e`×1†
- `movlps`: `src/disasm_x64.e`×1†, `src/emit_x64.e`×1†
- `movd`: `src/runtime_pe_x64.asm`×67†, `src/runtime_elf_x64.s`×57†, `src/emit_x64.e`×3†, `src/disasm_x64.e`×1†
- `pinsrw`: `src/emit_x64.e`×1†
- `pextrw`: `src/emit_x64.e`×1†
- `movq`: `src/emit_x64.e`×3†, `src/disasm_x64.e`×1†
- `FieldAddress`: `src/lower.e`×33‡, `src/codegen_x64.e`×4‡, `src/nir.e`×3†, `src/em.e`×1‡
- `psllw`: `src/codegen_x64.e`×2‡, `src/emit_x64.e`×1†
- `psrlw`: `src/codegen_x64.e`×1‡, `src/emit_x64.e`×1†
- `psraw`: `src/codegen_x64.e`×1‡, `src/emit_x64.e`×1†
- `psllq`: `src/emit_x64.e`×1†

## Existing fixtures

- `tests/selfhost/fixtures/link/simd_lanes`
- `tests/selfhost/fixtures/link/simd_lanes/src/main.e`
- `tests/selfhost/fixtures/link/trap_arithmetic`

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- `python scripts/render_progress.py` must run clean after the queue edit.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
