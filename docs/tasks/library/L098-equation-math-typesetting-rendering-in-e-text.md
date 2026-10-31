# L098 — Equation (math typesetting) rendering in e.text

| field | value |
|---|---|
| category | library / Algorithms |
| score | 0.98 of 1 |
| queue position | 46 of 106 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Planning only (D1824). Office-equation parity missing: math-zone layout (fractions, scripts, roots, matrices, operators) over e.text.layout shaping into caller-owned glyph runs for scene/SVG adapters. Display layout first; interactive equation editing stays app-side. Fixtures for nesting, baseline alignment and refusal paths. Follow-on (D1891): LaTeX-math and MathML input formats ride the same layout. PART (D2842): e.text.math typesets a LaTeX-math subset (atom spacing, four styles, fractions, radicals with index, scripts, display limits, \leftight growth, matrices and cases) to a paint-ordered list of glyph and rule items, agreeing with fontTools metrics and TeXbook formulas to 0.01 (about 50 checks). NOT DONE: drawing and any pixel check, MathML, italic math letters, MATH-table constants, extensible-glyph assembly, cramped styles, align. PART (D3101): OpenType MATH constants, cramped styles, MathVariants/GlyphAssembly, italic alphanumerics, align/aligned/gather, typeset_mathml (bit-identical to LaTeX for 12 documents), to_layout; text_math agrees with a Python model over a generated MATH font to 0.02 and the scene pixel check is within 3/255 mean. Missing: \mathbf/\mathcal, accents and braces, MathKernInfo, horizontal variants, real MathML accents. PART (D3702): math alphabets, accents, over/under braces, horizontal variants, MathKernInfo, top-accent attachment, MathML accents; text_math 37 layout cases and 18 MathML pairs vs a Python model. Missing: \substack, equation numbers, ig sizes, composite-base kerning. PART (D4505): \substack, ig sizes, 	ag equation numbers and numbered align/gather, composite-base kerning; text_math 54 model cases, 18 MathML pairs. Missing: MathML input for the new constructs.

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
