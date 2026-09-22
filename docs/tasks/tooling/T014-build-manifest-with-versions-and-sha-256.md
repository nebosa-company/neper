# T014 — Build manifest with versions and SHA-256

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.95 of 1 |
| queue position | 43 of 48 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

From `docs/roadmap.md`, section **M1 — The full CPU language**:

> Every build writes the canonical v1 build manifest with language/grammar versions, normalized source identities, SHA-256 inputs/dependencies/libraries/artifacts and effective options. Generated-source maps use exact tooling spans and hashes; stale or malformed maps fail with `E-TOOL-0001` and never change compilation semantics

**Done when:** every item above is implemented in the self-hosted compiler, and
`lib/e` builds and its tests pass under `neper test`; all applicable conformance
fixtures validate byte-for-byte after the specified duration normalization; tooling
streams reconstruct source exactly and validate against the schema; formatter
idempotence holds; every M1 API fence matches extracted source declarations; and the
S0 generated-code benchmark has been rerun with no unexplained regression.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `build-manifest-file PATH ROOT ARCH OS --json` (D238): the canonical `neper-build-manifest` object -- schema, version, tool and language versions, grammar revision, target, mode, root module, and one `inputs` entry per source module carrying its source identifier and the real SHA-256 of its bytes (ported into artifact_hash.e over the byte-per-slot representation, checked against the RFC 6234 `abc` vector and python hashlib); tests/conformance/tools/manifest.e pins it per host. A build writes the same object to `.neper/<mode>/build-manifest.json` under the project root with `mode` from `--release` and `artifacts` carrying the executable as named, `kind` executable, the target and the SHA-256 of the bytes written (D254), making the directory when it is missing (D287). Every input carries section 2's real identity (D265): `project-src` or `project-lib` with its path under that root, `toolchain-lib` for a module under the toolchain's lib, and the operand by its basename otherwise; and every module but the root is a `dependencies` entry with `interface_sha256` -- the source with every function body left out, so an edit inside a body moves only `body_sha256` -- and `body_sha256`, the whole file; tests/conformance/tools/manifest_project pins a two-module project per host. The artifact's path is project-relative as section 7 says (D293): the executable as named, made absolute under the current directory, then spelled from the project root with `/` separators, or kept absolute when it lies outside the project; both suites read the corpus build's artifact by that spelling. The `unsafe` inventory and `options.checks` (D355). Every declared asset as an `assets` entry with its project-relative path, media type, attributes, size and SHA-256 (D792)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] libraries

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D238` — `build-manifest --json` and a SHA-256 in the compiler (`docs/decisions.md:4320`)
- `D254` — A build writes its manifest, into a directory the project makes once (`docs/decisions.md:4802`)
- `D265` — A manifest's inputs have their real roots, and its dependencies an interface hash (`docs/decisions.md:5072`)
- `D287` — `os.mkdir` joins the fixed surface, as a bootstrap intrinsic only (`docs/decisions.md:5635`)
- `D293` — An artifact's manifest path is project-relative (`docs/decisions.md:5762`)
- `D355` — A release build is a checked build, and every unsafe boundary is listed (`docs/decisions.md:7776`)
- `D792` — The build manifest lists every declared asset (`docs/decisions.md:15070`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `neper-build-manifest`: `src/tool.e`×3‡, `src/main.e`×1‡, `tests/conformance/tools/manifest.e`×1, `tests/conformance/tools/manifest.x64-linux.expected.jsonl`×1, `tests/conformance/tools/manifest.x64-windows.expected.jsonl`×1, `tests/conformance/tools/manifest_map.x64-linux.expected.jsonl`×1, `tests/conformance/tools/manifest_map.x64-windows.expected.jsonl`×1, `tests/conformance/tools/manifest_project.x64-linux.expected.jsonl`×1
- `project-src`: `tests/conformance/tools/plan_rename_type.x64-linux.expected.jsonl`×13, `tests/conformance/tools/plan_rename_type.x64-windows.expected.jsonl`×13, `tests/conformance/tools/nested_instance.x64-linux.expected.jsonl`×9, `tests/conformance/tools/nested_instance.x64-windows.expected.jsonl`×9, `tests/conformance/tools/uses_type.expected.jsonl`×9, `src/main.e`×8‡, `tests/conformance/tools/plan_rename_error.x64-linux.expected.jsonl`×6, `tests/conformance/tools/plan_rename_error.x64-windows.expected.jsonl`×6
- `project-lib`: `src/main.e`×2‡, `src/tool.e`×2‡, `tests/conformance/reject/safety_pushed_twice.expected.jsonl`×2, `tests/conformance/reject/safety_codec_decode_resource.expected.jsonl`×1, `tests/conformance/reject/safety_codec_encode_resource.expected.jsonl`×1, `tests/conformance/reject/safety_copy_toolchain.e`×1, `tests/conformance/reject/safety_copy_toolchain.expected.jsonl`×1, `tests/conformance/tools/arena_layout.expected.jsonl`×1
- `toolchain-lib`: `src/main.e`×2‡, `src/tool.e`×2‡, `tests/conformance/tools/explain.expected.jsonl`×2, `tests/conformance/reject/safety_copy_toolchain.e`×1, `tests/conformance/tools/manifest_unsafe.x64-linux.expected.jsonl`×1, `tests/conformance/tools/manifest_unsafe.x64-windows.expected.jsonl`×1
- `interface_sha256`: `src/tool.e`×8‡, `src/main.e`×4‡, `src/artifact_hash.e`×3, `src/em.e`×3‡, `src/graph.e`×2†, `tests/conformance/tools/manifest_map.x64-linux.expected.jsonl`×1, `tests/conformance/tools/manifest_map.x64-windows.expected.jsonl`×1, `tests/conformance/tools/manifest_project.x64-linux.expected.jsonl`×1
- `body_sha256`: `src/tool.e`×3‡, `src/artifact_hash.e`×1, `src/main.e`×1‡, `tests/conformance/tools/manifest_map.x64-linux.expected.jsonl`×1, `tests/conformance/tools/manifest_map.x64-windows.expected.jsonl`×1, `tests/conformance/tools/manifest_project.x64-linux.expected.jsonl`×1, `tests/conformance/tools/manifest_project.x64-windows.expected.jsonl`×1, `tests/conformance/tools/manifest_unsafe.x64-linux.expected.jsonl`×1
- `options.checks`: `src/main.e`×2‡

## Existing fixtures

- `tests/conformance/tools/manifest.e`
- `tests/conformance/tools/manifest_project`

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
