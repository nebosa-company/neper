# L040 — Cascade, matcher, and accessibility-name kernels

| field | value |
|---|---|
| category | library / Algorithms |
| score | 0.80 of 1 |
| queue position | 55 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Vaper css/container_query.dart (Kleene and/or/not plus scope proximity), style_resolver id/class/tag rule-index buckets with origin/importance/specificity/order/proximity sort, selector_matcher right-to-left combinator walk (adapted off the package:html DOM), a11y role map with aria-labelledby over aria-label over native over content. Port logic kernels into e.algo.logic and e.ui.accessibility. PART ONE (D2343): lib/e/fmt/css/container.e, e.fmt.css.container -- container_query.dart; fixture text_css_container, 400 trees. PART TWO (D2343): lib/e/fmt/css/match.e, e.fmt.css.match -- selector_matcher.dart over an e.fmt.html document; fixture text_css_match, 560 cases. PART THREE (D2343): lib/e/fmt/html/accessible.e, e.fmt.html.accessible -- accessibility_builder.dart over an e.fmt.html document; fixture html_accessible, 220 documents. NOT DONE: the style_resolver kernels with no public surface to compare against (rule-index buckets, @scope proximity, declaration precedence incl. hints and layers, containersMatch over a container stack).

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

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
