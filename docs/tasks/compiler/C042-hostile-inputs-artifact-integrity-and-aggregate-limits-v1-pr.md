# C042 — Hostile inputs, artifact integrity and aggregate limits (v1 precursor for T2 H24)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.70 of 1 |
| queue position | 5 of 49 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H24 — hostile inputs, artifact integrity and aggregate limits** (track: T2.0 (Tooling foundations, open)):

**T2 tooling-v2 delivery: harden implemented readers/caches and CPU work scheduling.** Future
device/package readers inherit the frozen contract when those features arrive.

- Treat source, cache modules, source maps, protocol requests and metadata as
  potentially malformed. Validate versions, tags, lengths, offsets, integer
  arithmetic, section overlap, graph references and checksums before use. Bound
  decompression/decoding, recursion, allocations and diagnostic expansion.
- Distinguish trusted local optimization caches from imported/shared artifacts.
  CRC/fast hashes detect some corruption but do not authenticate untrusted content.
  Specify strong content integrity, compatibility checks and provenance requirements;
  untrusted cache metadata must not grant execution or generator permissions.
- Validate serialized typed IR and relocations before emission/reuse. Corrupt
  disposable caches can be quarantined/rebuilt; mandatory corrupt inputs produce
  explicit failures. Never fall back to unchecked execution of an invalid artifact.
- Enforce whole-request/build budgets across workers, instantiations and comptime
  evaluations. Limit caches/indexes/output as well as computation. Deterministic
  work exhaustion, cancellation and infrastructure failure have distinct statuses.
- Publish cache entries only after successful validation and complete writes.
  Concurrent writers, crashes and injected storage errors cannot create accepted
  partial records. Preserve the last known valid entry where applicable.

Acceptance: byte/mutation fuzzing of every implemented decoder; adversarial sizes
and cyclic references; hash collision/corruption injection; interrupted writes;
version mismatch; decompression bombs where compression exists; many individually
legal jobs exceeding the global budget; incremental cache fault injection.
Bounded inputs must not hang/crash the compiler or produce runnable invalid output.
Retain minimized reproducers and regression tests; clean/incremental semantic
equivalence is a required oracle, not the sole independent correctness oracle.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Every artifact read is checksum-validated once at load and layout-validated by each reader (D213, D320); `benchmarks/fuzz/fuzz.py` mutates every fixture source and artifact and found nothing in 33k runs, and expression nesting is bounded at 128 levels (D341); artifacts are published by one atomic replace and a damaged cache is rebuilt to the clean image, both suites (D343); an escaped resource limit is E-TYPE-9999 (D344); a corrupt artifact named on the command line is E-LINK-0001 and a damaged cache entry says `invalid-artifact` in the manifest (D368). `--fault-write N` makes one artifact write die between staging and replace, and both suites read the next build: the faulted module alone rebuilt, the image the clean build's (D435). `--instances N` is a whole-build budget over every worker's instantiations (D426). An artifact forged to import the module that imports it -- `corrupt.py cycle` -- made a warm build fail blaming the source; it is now distrusted and rebuilt as `invalid-artifact`, the image the clean build's, the linker over the forged set refusing without crashing, both suites in both modes (D472). The manifest records every artifact's checksum and the next warm build refuses one whose checksum is not the recorded one, cycle or not -- the cache's anchor beyond the file's own check, at no cost to the warm build (D473); `--comptime-steps N` is a whole-build budget over the interpreter's steps, the main checker's and every worker's summed, refused as E-COMPTIME-0002 with the count (D474)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] a keyed integrity a hostile cache cannot satisfy by rewriting the manifest too

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D213` — The artifact path at the compiler's own size (`docs/decisions.md:3898`)
- `D320` — The artifact path at scale: bytes are bytes, a module's own rows, indexes over every walk (`docs/decisions.md:6526`)
- `D341` — Bounded malformed input: the fuzzer, the nesting bound, and the link's hash scratch (`docs/decisions.md:7301`)
- `D343` — An artifact is published by one atomic replace, and a damaged cache is rebuilt (`docs/decisions.md:7368`)
- `D344` — A failure that reaches the top is a diagnostic, and the stream still ends (`docs/decisions.md:7393`)
- `D368` — A corrupt artifact is named: E-LINK-0001 on the command line, `invalid-artifact` in the manifest (`docs/decisions.md:8102`)
- `D426` — `--instances N`: a specialization budget (`docs/decisions.md:9438`)
- `D435` — A fault injected into the cache writes (`docs/decisions.md:9619`)
- `D472` — A cyclic artifact reference is a damaged artifact (`docs/decisions.md:10240`)
- `D473` — The manifest as the cache's anchor (`docs/decisions.md:10263`)
- `D474` — A whole-build budget over the interpreter's steps (`docs/decisions.md:10288`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `benchmarks/fuzz/fuzz.py`: `benchmarks/fuzz/fuzz.py`×1
- `invalid-artifact`: `src/main.e`×2‡, `src/tool.e`×1‡
- `fault-write`: `src/main.e`×6‡
- `comptime-steps`: `src/main.e`×4‡, `src/check.e`×1‡, `tests/conformance/tools/comptime_steps.e`×1, `tests/conformance/tools/comptime_steps.expected.jsonl`×1

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
