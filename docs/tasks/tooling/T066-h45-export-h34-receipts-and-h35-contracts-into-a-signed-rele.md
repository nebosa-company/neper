# T066 — H45: export H34 receipts and H35 contracts into a signed release-provenance envelope

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.00 of 1 |
| queue position | 152 of 223 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H45 — release provenance bridge** (track: M6-provenance (Release provenance bridge, planned)):

**Later delivery, scheduled with M6 package/release work: export Neper evidence into
standards-based source and build provenance.** This does not block M3 because the
post-M2 tracks have no complete package publication boundary.

- Export the unchanged H34 receipt, H35 contract, H37 environment identity,
  dependency lock and produced artifact digests into a versioned provenance envelope
  compatible with the selected release ecosystem. The export may reference, but may
  not reinterpret or strengthen, native evidence.
- Signing, builder/source identity, key isolation, trust policy, revocation and
  distribution are explicit platform responsibilities. Unsigned local provenance is
  useful traceability, not authenticated proof; self-reported model confidence or
  authorship is never substituted for an attested identity.
- Verification is monotonic: deleting or ignoring an extension cannot change deny to
  allow, and missing/untrusted provenance produces unknown or rejection under the
  consumer's policy.

Acceptance: validate against the selected external schema and independent verifier;
cover altered source, dependency, builder, artifact, receipt and signature; reproduce
the native evidence link; and reject any export that claims a stronger property than
its inputs establish.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened 2026-11-03 from docs/post-m2-llm-hardening.md:1586 by the single-list audit; not previously a queue row. Acceptance: A command exports receipt, change contract, environment identity, lock and artifact digests into the selected external provenance schema; an independent verifier accepts it and rejects altered source, dependency, builder, artifact, receipt or signature. Unsigned output is labelled local traceability and an export claiming more than its inputs is refused. Size L. Checked open: grep H45/provenance in work-done = 0; M6-01..06 milestone files do not mention it; hardening-tracks.json M6-provenance status planned; no SLSA/in-toto reference in repo docs.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

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
