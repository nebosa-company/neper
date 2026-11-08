# C295 — x_cloud_rest reports an observed azure vnet as unmanaged where the expectation says managed

| field | value |
|---|---|
| category | library / Library |
| score | 0.00 of 1 |
| queue position | 1 of 225 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Open, and pre-existing: it is the fixture after text_css_cascade in the suite, so no run had reached it. x_cloud_rest answers exit 17 from its seventeenth vector chunk, on an `observed` call whose def is an azure.vnet. The comparison that fails is the resource record: the library answers `{"attributes":{},"managed":false,"name":"petcow-x","realId":null,"type":"azure.vnet"}` where the expectation has `"managed":true`, everything else agreeing -- name, type, empty attributes and a null realId. So the observation path's `managed` decision is the whole difference: rest.observed sets `ob.managed` from the resource's markers, and for this input it concludes the resource is not managed. Nothing in the selector, cssvalue, cascade, window or ssh work touches x.oracle.cloud, so this is not a regression from them. Acceptance: x_cloud_rest exits 0, and an observed azure.vnet whose expectation is managed reports managed.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `ob.managed`: `scripts/rest_fixture_template.e`×1

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
