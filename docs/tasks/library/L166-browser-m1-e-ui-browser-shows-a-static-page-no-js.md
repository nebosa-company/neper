# L166 — Browser M1: e.ui.browser shows a static page (no JS)

| field | value |
|---|---|
| category | library / Library |
| score | 0.20 of 1 |
| queue position | 97 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Plan docs/browser-progress.html, decisions D5114 to D5122. Acceptance: (1) tracker phase P0 (0.1 to 0.8): oracle frozen, html5lib, WPT reftest, pixel-probe and render-tool harnesses, Ahem asset, baselines; (2) P1 parse and style core: 1.1 to 1.14, html5lib at least Dart's 1549 of 1791; (3) P2 2.1 to 2.3 block and inline layout over e.text; (4) P3 3.1 to 3.6 and 3.11 display list, scene tiling, backgrounds, borders, text, images; (5) P4 4.1 and 4.2 loader and HTTP/1.1; (6) 7.0 lib/e/ui/html_view.e shows a static document over e.fmt.dom, e.fmt.css.style, e.fmt.css.layout and e.fmt.css.paint (D5123: reusable parts are library modules, not e.web); 7.1 lib/e/ui/browser.e builds on it, loads an HTTP(S) page, scrolls, follows links; Hacker News within the pixel tolerance of the Dart golden. PART (2026-10-16): 0.6a html5lib runner done (tests/browser/html5lib/run.sh) 1.1 to 1.3 done (D5124) 1.7 done (D5125, e.fmt.dom with fixture fmt_dom) 1.13a to 1.13f done (D5126, D5127: sheet loader with all at-rules but nesting, user agent sheet; fixtures css_sheet, css_ua) and 1.13a to 1.13d done (D5126, e.fmt.css.style and e.fmt.css.expand with fixture css_style: expansion before ranking, typed computed values, inheritance, var()): e.fmt.html is the WHATWG tokenizer and tree builder, 1791 of 1791 html5lib cases against Dart's 1549 (it was 572), floor enforced by run.sh; the WPT reftest runner, pixel-probe and render tool wait for the layout and paint layers; 0.1 done (D5114 to D5123); 0.3 Dart oracle frozen: vaper tag dart-oracle-final at 8e0c4e9, a record/replay capture tool, six sites (Hacker News, example.com, Wikipedia Comparison_of_web_browsers with 12317 nodes, MDN, craigslist, abv.bg) captured with PNG, node and display-list goldens, each replay byte-identical twice, in tests/browser/oracle with a README; the jQuery page set and the licence decision before committing the stores remain. PART: landed pieces that M1 reuses, not yet checked against the oracle: e.fmt.html, e.fmt.css.syntax/selector/match/cascade/container, e.gfx.cssvalue (L038, L040), e.fmt.woff and woff2 (D2346), e.net.policy and ssrf (D2351).

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] everything except 0.1, most of 0.3, 0.6a, 1.1 to 1.3, 1.7 and 1.13a to 1.13d

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
