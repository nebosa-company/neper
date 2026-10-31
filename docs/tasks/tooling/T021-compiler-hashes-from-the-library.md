# T021 — Compiler hashes from the library

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.95 of 1 |
| queue position | 25 of 106 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

The compiler's own hashing (CRC-32C for artifact checksums, SHA-256 for manifest digests) comes from `lib/e` (`e.algo.hash`, `e.crypto.hash`) instead of private copies in `src/`, so one implementation is tested once and the compiler is a client of its own library. Blocked in part by the C bootstrap, which must still compile every module the compiler imports.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> xxHash64 and FNV-1a land (D747): `src/artifact_hash.e` calls `e.algo.hash` for both, and the tuned inline-load one-shot D388 wrote for the artifact path moved into the library rather than the library's byte-buffered one surviving -- D333's rule that the faster moves. `round` (the `program_snapshot` fold, D407) and `fnv1a32_step` (the module-dot-name fold, D6) stay in the compiler with `rotate_left` and `xor` under them; `read_u32`, `read_u64`, `merge_round` and three primes went with the body. Pinned by a seventy-seven byte vector in `artifact_hash.self_test` -- two whole blocks, then an eight, a four and a one -- and by the suite's artifacts, manifest goldens and stage-2/stage-3 fixed point. `e.algo.hash` is `surface:"source"`, so the move added no declaration. CRC-32C is the library's (D1701): `e.algo.hash.crc32c*` with slicing-by-8 past 256 bytes, the compiler keeping only the CRC32 instruction and the zeroed field, artifacts unchanged. What remains is a decision, not a blocker: the compiler's `os.sha256_blocks` intrinsic (D332) against the library's portable block function, to be measured on T023's corpus. PART (D4301): artifact_hash.sha256_hex_into calls e.crypto.hash.sha256 (about 90 lines left the compiler); the library tops up a partial block and feeds whole blocks to os.sha256_blocks at 1.0-1.25 GB/s; build manifest byte-identical, stage 2 equals stage 3, crypto_hash split check passes on Windows and Linux. Missing: the suite's stage-one (bootstrap) build verification.

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] SHA-256
- [ ] which is blocked -- the C bootstrap builds stage one on every suite run and refuses `lib/e/crypto/hash.e` with nineteen E-TYPE-0002s where a `u64` shifts by a `u32`, so that half waits on the bootstrap's deletion (D208)
- [ ] which is the finding D333 asked for UPDATE (D2329): the blocker is gone -- lib/e/crypto/hash.e now builds under the C bootstrap (u64 shifts by u64, no `-=`, Keccak slices through a local pointer copy)
- [ ] the six crypto fixtures still pass

Notes:

- Blocked in part: the C bootstrap refuses `lib/e/crypto/hash.e` (nineteen E-TYPE-0002s, a `u64` shifted by a `u32`). Either fix the bootstrap's shift typing (`bootstrap/neper.c`) or rewrite those shifts in the library so both compilers accept them; then move SHA-256. CRC-32C first needs the table-driven `crc32c` in `e.algo.hash` (D333).

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D208` — The bootstrap's archive is recorded (`docs/decisions.md:3805`)
- `D332` — The image's digest reused when the image is the one on disk (planned) (`docs/decisions.md:6989`)
- `D333` — The compiler's hashes from `e.algo.hash` and `e.crypto.hash` (planned) (`docs/decisions.md:7023`)
- `D388` — The hash reads its words inline, and a reader's guard is its proof (`docs/decisions.md:8625`)
- `D407` — A context answer names the program it was computed against (`docs/decisions.md:9071`)
- `D747` — xxHash64 and FNV-1a from `e.algo.hash` (`docs/decisions.md:13839`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `e.algo.hash`: `scripts/algos/decisions-pending.md`×5†, `src/artifact_hash.e`×4, `scripts/algos/batch43.json`×3, `lib/e/algo/sketch.e`×2†, `scripts/algos/batch35.json`×2, `lib/e/algo/consistent_hash.e`×1, `lib/e/algo/formula/misc.e`×1†, `lib/e/algo/uuid.e`×1
- `program_snapshot`: `src/tool.e`×10‡
- `fnv1a32_step`: `src/artifact_hash.e`×4, `src/em.e`×3‡
- `rotate_left`: `lib/e/data/tree.e`×3, `src/artifact_hash.e`×2, `lib/e/bytes.e`×1
- `read_u32`: `src/em.e`×134‡, `lib/e/text/unicode.e`×6‡, `src/binary.e`×4, `lib/e/audio.e`×3, `lib/e/text/bidi.e`×3†, `lib/e/time/sync.e`×3, `src/main.e`×3‡, `src/em_link.e`×1†
- `read_u64`: `src/em.e`×17‡, `lib/e/fmt/mvt.e`×8, `lib/e/fmt/protobuf.e`×8, `lib/e/net/grpcstub.e`×6, `src/binary.e`×3, `lib/e/time/sync.e`×2, `lib/e/fmt/protodesc.e`×1
- `artifact_hash.self_test`: `src/main.e`×1‡
- `os.sha256_blocks`: `lib/e/crypto/hash.e`×2†, `src/check.e`×1‡, `src/runtime_elf_a64.s`×1†, `src/runtime_elf_x64.s`×1†, `src/runtime_macos_a64.s`×1, `src/runtime_macos_x64.s`×1†, `src/runtime_pe_x64.asm`×1†

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- Every emitted record must validate: `python scripts/validate_stream.py`.
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
