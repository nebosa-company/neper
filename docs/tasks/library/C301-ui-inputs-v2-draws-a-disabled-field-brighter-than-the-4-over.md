# C301 — ui_inputs_v2 draws a disabled field brighter than the 4% overlay it pins

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

> Open, and pre-existing: ui_inputs_v2 is the fixture after gpu_present in the suite, so no run had reached it. It exits 16 at its fourth field, the disabled one, which pins the pixel at the box's left inset to `over(page, style.color(&tokens, .OnSurface), 0.04)` -- page plus four percent of the on-surface ink, where `over` is a plain linear blend and `close_to` allows three of 255. Read out of a temporary probe at that pixel the frame is 248, 249, 255 where the expectation's red is 239, so the drawn tint is brighter and bluer than the four percent overlay by about nine of 255 on red, well outside the tolerance; the neighbouring fields pass, so it is the disabled state specifically. Not from this session's work: rebuilding the fixture against lib/e/gfx/cssvalue.e from before the viewport-unit, transform and colour changes answers exit 16 the same way. Where to look is the disabled tint the widget style lays over the field -- whether it composites `on-surface` at four percent, at the wrong alpha, or under the field's own background rather than over it -- and the blue channel reaching 255 suggests the field's background is not what the fixture assumes. Acceptance: ui_inputs_v2 exits 0. Narrowed further: the module does compute what the fixture pins. For a filled field, control.field sets `var fill = style.color(t.tokens, .SurfaceContainerHighest)`, then `if !options.enabled { fill = with_alpha(ink, 0.04) }` where `ink` is `.OnSurface` -- the same page-plus-four-percent formula the fixture recomputes with `over`. So the expectation and the style agree, and the difference is between that brush and the pixel: either the field under test is not taking the filled branch (the outlined branch deliberately paints no fill for this profile, 'a disabled outlined field has no fill, as Flutter's'), in which case the pixel would be the page itself rather than the page brightened by nine, or the solid brush's alpha is being composited differently from `over`'s linear blend. Reading the page's own red alongside the pixel settles it: the probe printed the expectation's red as 239 and the frame as 248, so the drawn pixel is brighter than the page by nine and cannot be the unfilled page either. Next: dump what `style.color(&tokens, .Background)` and `with_alpha(.OnSurface, 0.04)` are as bytes, and check whether the field is built with `filled`.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `on-surface`: `lib/e/ui/control.e`×130‡, `lib/e/ui/collection.e`×56‡, `lib/e/ui/overlay.e`×48‡, `lib/e/ui/navigation.e`×46‡, `scripts/material/gallery.html`×28, `scripts/render_reference.mjs`×10, `lib/e/ui/looks_z84_edge.e`×2, `lib/e/ui/looks_q79.e`×1
- `.OnSurface`: `lib/e/ui/control.e`×155‡, `lib/e/ui/navigation.e`×80‡, `lib/e/ui/collection.e`×78‡, `lib/e/ui/overlay.e`×63‡, `lib/e/ui/style.e`×24†, `lib/e/ui/flow.e`×4†, `lib/e/ui/looks_y63.e`×4, `lib/e/ui/sheet.e`×4†

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
