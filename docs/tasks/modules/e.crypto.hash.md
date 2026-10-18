# e.crypto.hash — 2 of 92 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/crypto/hash.e` |
| plan row | layer 2, surface `partial`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/crypto/hash.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Extended pure algorithms, text and cryptography:** `e.algo.stat`, `e.algo.complex`, `e.algo.decimal`, `e.algo.bignum`, `e.algo.deflate`, `e.algo.linalg.matrix`, `e.algo.linalg.tensor`, `e.text.unicode`, `e.text.encoding`, `e.text.normalize`, `e.text.collate`, `e.text.regex`, `e.text.locale`, `e.crypto.hash`, `e.crypto.mac`, `e.crypto.kdf`, `e.crypto.aead`, `e.crypto.sign`, `e.crypto.kx`, `e.crypto.random` and `e.crypto.x509`. Preserve caller-owned allocation, caller-supplied entropy and the declared dependency edges. Cryptographic delivery requires published standard vectors, malformed-input cases and verification of every API that explicitly promises constant-time behavior.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 2 may depend on layers [0, 1, 2].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Sha256 = struct { h: [8]u32, block: [64]u8, block_len: u8, total: u64 }
type Sha512 = struct { h: [8]u64, block: [128]u8, block_len: u8, total_hi: u64, total_lo: u64 }
type Sha3_256 = struct { lanes: [25]u64, block: [136]u8, block_len: u8 }
type Sha3_512 = struct { lanes: [25]u64, block: [72]u8, block_len: u8 }
type Blake2b = struct { h: [8]u64, t_lo: u64, t_hi: u64, block: [128]u8, block_len: usize, out_len: usize }
type Blake3 = struct { key: [8]u32, cv: [8]u32, chunk_counter: u64, block: [64]u8, block_len: usize, blocks_compressed: usize, flags: u32, stack: [432]u32, stack_len: usize }
type Blake3Output = struct { cv: [8]u32, block: [16]u32, counter: u64, block_len: u32, flags: u32 }
type Shake = struct { lanes: [25]u64, block: [168]u8, block_len: usize, rate: usize, offset: usize, squeezing: bool }

fn rotr32(x: u32, n: u32) -> u32
fn rotr64(x: u64, n: u32) -> u64
fn rotl64(x: u64, n: u32) -> u64
fn rotl32(x: u32, n: u32) -> u32
fn load_be32(block: []const u8, at: usize) -> u32
fn load_be64(block: []const u8, at: usize) -> u64
fn store_be32(out: []u8, at: usize, value: u32)
fn store_be64(out: []u8, at: usize, value: u64)
fn sha256_k(index: usize) -> u32
fn sha256_init() -> Sha256
fn sha256_compress(s: *Sha256, block: []const u8)
fn sha256_update(h: *Sha256, data: []const u8)
fn sha256_done(h: *Sha256) -> [32]u8
fn sha256(data: []const u8) -> [32]u8
fn sha512_k(index: usize) -> u64
fn sha512_init() -> Sha512
fn sha512_compress(s: *Sha512, block: []const u8)
fn sha512_update(h: *Sha512, data: []const u8)
fn sha512_done(h: *Sha512) -> [64]u8
fn sha512(data: []const u8) -> [64]u8
fn sha384_init() -> Sha512
fn sha384_update(h: *Sha512, data: []const u8)
fn sha384_done(h: *Sha512) -> [48]u8
fn sha384(data: []const u8) -> [48]u8
fn keccak_round_constant(round: usize) -> u64
fn keccak_rho(index: usize) -> u32
fn keccak_f(lanes: []u64)
fn keccak_absorb(lanes: []u64, block: []const u8)
fn keccak_squeeze(lanes: []const u64, out: []u8)
fn sha3_256_init() -> Sha3_256
fn sha3_256_update(h: *Sha3_256, data: []const u8)
fn sha3_256_done(h: *Sha3_256) -> [32]u8
fn sha3_256(data: []const u8) -> [32]u8
fn sha3_512_init() -> Sha3_512
fn sha3_512_update(h: *Sha3_512, data: []const u8)
fn sha3_512_done(h: *Sha3_512) -> [64]u8
fn sha3_512(data: []const u8) -> [64]u8
fn legacy_padded_len(length: usize) -> usize
fn legacy_sha1(data: []const u8) -> [20]u8
fn md5_k(index: usize) -> u32
fn md5_shift(index: usize) -> u32
fn legacy_md5(data: []const u8) -> [16]u8
fn equal_constant_time(a: []const u8, b: []const u8) -> bool
fn blake2b_sigma(round: usize, i: usize) -> usize
fn load_le64(bytes: []const u8, at: usize) -> u64
fn blake2b_g(v: []u64, a: usize, b: usize, c: usize, d: usize, x: u64, y: u64)
fn blake2b_compress(s: *Blake2b, last: bool)
fn blake2b_init(out_len: usize, key: []const u8) -> Blake2b
fn blake2b_update(s: *Blake2b, bytes: []const u8)
fn blake2b_done(s: *Blake2b) -> [64]u8
fn blake2b(data: []const u8) -> [64]u8
fn blake2b_keyed(key: []const u8, data: []const u8) -> [64]u8
fn blake3_iv(index: usize) -> u32
fn blake3_word(bytes: []const u8, at: usize) -> u32
fn blake3_words(bytes: []const u8) -> [16]u32
fn blake3_g(state: []u32, a: usize, b: usize, c: usize, d: usize, mx: u32, my: u32)
fn blake3_round(state: []u32, m: []const u32)
fn blake3_compress(cv: [8]u32, block: [16]u32, counter: u64, block_len: u32, flags: u32) -> [16]u32
fn blake3_output_cv(o: Blake3Output) -> [8]u32
fn blake3_output_root(o: Blake3Output, out: []u8)
fn blake3_start_flag(h: *Blake3) -> u32
fn blake3_chunk_output(h: *Blake3) -> Blake3Output
fn blake3_parent(left: [8]u32, right: [8]u32, key: [8]u32, flags: u32) -> Blake3Output
fn blake3_stack_get(h: *Blake3, index: usize) -> [8]u32
fn blake3_stack_push(h: *Blake3, cv: [8]u32)
fn blake3_add_chunk_cv(h: *Blake3, cv_in: [8]u32, total_chunks: u64)
fn blake3_init_with(key: [8]u32, flags: u32) -> Blake3
fn blake3_init() -> Blake3
fn blake3_key_words(key: [32]u8) -> [8]u32
fn blake3_keyed_init(key: [32]u8) -> Blake3
fn blake3_derive_key_init(context: []const u8) -> Blake3
fn blake3_clear_block(h: *Blake3)
fn blake3_update(h: *Blake3, data: []const u8)
fn blake3_done(h: *Blake3, out: []u8)
fn blake3(data: []const u8) -> [32]u8
fn blake3_xof(data: []const u8, out: []u8)
fn blake3_keyed(key: [32]u8, data: []const u8) -> [32]u8
fn blake3_derive_key(context: []const u8, key_material: []const u8, out: []u8)
fn shake128_init() -> Shake
fn shake256_init() -> Shake
fn shake_absorb(s: *Shake, data: []const u8)
fn shake_squeeze(s: *Shake, out: []u8)
fn shake128(data: []const u8, out: []u8)
fn shake256(data: []const u8, out: []u8)
```

## Missing declarations

- [ ] `sha256_k`
- [ ] `sha256_compress`

## Contracts that name this module

Read each line in context; they carry obligations (cancellation, bounded buffers, no hidden allocation, standard vectors) that the fence alone does not spell out.

- `docs/stdlib-hardening.md:333` accept, reusing `e.crypto.hash`'s existing legacy SHA-1 primitive plus `e.bytes` Base64.

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/crypto/aead.e`†
- `lib/e/crypto/cipher.e`
- `lib/e/crypto/classic.e`
- `lib/e/crypto/cms.e`
- `lib/e/crypto/hash.e`†
- `lib/e/crypto/jks.e`
- `lib/e/crypto/kdf.e`†
- `lib/e/crypto/kx.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/crypto/hash.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/crypto_hash/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 2.

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
