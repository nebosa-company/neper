# C048 — Generated-source provenance and editability (v1 precursor for T2 H19)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.86 of 1 |
| queue position | 10 of 53 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H19 — generated-source provenance and editability** (track: T2.1 (Understand and check, open)):

**T2 tooling-v2 delivery: source-map/tooling contracts and supported generated-input fixtures.**
Do not require the future package runner or a new general generator framework.

- Distinguish the physical compiled span, displayed origin, generator identity,
  input/artifact hashes and permitted edit target. Provenance mappings may be
  many-to-one or noninvertible; an origin location is not automatically a fix span.
- Mark generated output as directly editable, regeneration-owned or unknown.
  Regeneration-owned changes target the generator/input through a validated plan;
  do not automatically execute arbitrary generator commands from metadata.
- Propagate provenance through specialization, inlining, cleanup generation and
  CPU/device lowering. Preserve chains with bounded expansion and explicit omissions.
- Include maps/origins in tooling cache identities. Changing only a source map must
  refresh diagnostics and references without unnecessarily invalidating executable
  code. Stale or unavailable maps fall back to honest physical locations.
- Specify regeneration determinism, stale-output detection and conflict handling.
  Directly modified outputs must not be overwritten silently during a repair.

Acceptance: one input producing several declarations; combined inputs; nested maps;
map-only change; missing generator; hand-edited generated output; mapped diagnostic
with no inverse edit; stale generator hash. Verify fixes never modify an approximate
origin as though it were an exact editable span. Metadata text remains untrusted
data, not harness instructions or authority to run tools.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> A `<file>.e.map.json` beside a generated file maps diagnostics back to the original span with the generated one related; a stale or malformed map is E-TOOL-0001 with no artifact (D264, D300); version 2 names the generator and hashes its input, so a changed input is stale too, and a mapping's `edit` says whether the generated span may be edited or the original is the target (D373); no fix is ever offered on an original span; the compiler runs no generator. a generated file whose hash is not the map's while the generator's input is unchanged is a hand edit, `E-TOOL-0002`, told from a stale map, pinned by the corpus (D418); a generator's combined inputs (`generator.inputs`) are each checked and the first changed one named, and one input's line that became two declarations maps each to the one original span, pinned by the corpus (D464); a nested map -- the original itself generated under a map of its own -- is followed one level to the root original with the intermediate related, and a stale nested map is stated rather than followed, pinned by the corpus (D465); a failure inside an instance's body relates the site that first requested that instance, named with its arguments, in whichever module asked, pinned by the corpus (D466); the operand's map is an input of the build manifest with its hash, so a map-only change is visible there and nowhere in the code's identity, pinned per host (D467). The chain is bounded at eight nested levels (D499, D564), each level's mappings in its own eight slots and every intermediate related root-nearest first; `nested_deep` pins four levels past the former three-level ceiling. Provenance through inlining in a trap's backtrace (D519): a frame whose line lies in another module -- a body inlined there in release -- names that module's function holding the line as `inlined_from`, found from the checker's source ranges, where the runtime's frame could only name the function whose code holds the site; both suites pin it over `run_trap_module` in release, and the operand's own frames are under the project's identity. `dis-file --json --release` lists the release image, and each record's `inlined` names the runs of the function's code that are copies of another function's body, from the line table as backtrace frames are named (D542); a copied instruction also retains its bounded origin chain, so a run copied through another body carries `through` from the innermost intermediate outward while direct copies stay unchanged (D565)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] provenance through inlining in diagnostics

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D264` — Source maps: the test runner writes one, and the compiler reads it back (`docs/decisions.md:5033`)
- `D300` — Analysis still runs under a stale source map (`docs/decisions.md:5922`)
- `D373` — A version 2 source map names its generator, and a mapping says what may be edited (`docs/decisions.md:8249`)
- `D418` — A hand edit of a generated file, told from a stale map (`docs/decisions.md:9289`)
- `D464` — A generator's combined inputs (`docs/decisions.md:10082`)
- `D465` — A nested source map, followed one level (`docs/decisions.md:10101`)
- `D466` — The instance's request site on a template-body failure (`docs/decisions.md:10124`)
- `D467` — The source map in the build manifest (`docs/decisions.md:10149`)
- `D499` — The chain of maps, three levels (`docs/decisions.md:10679`)
- `D519` — A frame inlined from another module names its origin (`docs/decisions.md:10962`)
- `D542` — The inlined runs in the disassembly (`docs/decisions.md:11279`)
- `D564` — Source-map chains pass three nested generators (`docs/decisions.md:11637`)
- `D565` — Disassembly retains nested inline provenance (`docs/decisions.md:11655`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `E-TOOL-0002`: `src/main.e`×1‡, `tests/conformance/tools/hand_edited.e`×1, `tests/conformance/tools/hand_edited.expected.jsonl`×1
- `generator.inputs`: `src/main.e`×1‡
- `nested_deep`: `tests/conformance/tools/nested_deep.e`×1, `tests/conformance/tools/nested_deep.e.map.json`×1, `tests/conformance/tools/nested_deep.expected.jsonl`×1, `tests/conformance/tools/nested_deep.mid1`×1, `tests/conformance/tools/nested_deep.mid1.map.json`×1, `tests/conformance/tools/nested_deep.mid2`×1, `tests/conformance/tools/nested_deep.mid2.map.json`×1, `tests/conformance/tools/nested_deep.mid3`×1
- `inlined_from`: `src/tool.e`×2‡
- `inlined`: `src/em.e`×34‡, `src/main.e`×28‡, `src/lower.e`×27‡, `src/nir.e`×17†, `src/tool.e`×14‡, `tests/conformance/tools/dis.x64-linux.expected.jsonl`×2, `tests/conformance/tools/dis.x64-windows.expected.jsonl`×2, `src/check.e`×1‡

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
