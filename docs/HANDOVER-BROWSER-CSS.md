# Handover: browser engine CSS conformance (grid, flexbox, writing-modes)

Goal in force: "complete the CSS" (DOM/CSS/HTML/JS conformance of the Neper browser engine, measured by WPT reftests). It is not met. This file is the state at 2026-11-18. The per-round log is `docs/HANDOVER-BROWSER.md` (Rounds 315, 375-392 cover this stretch); this file is how to continue.

## Scores (WPT reftests, Windows runner)

| Suite | Pass | Total | Note |
|---|---|---|---|
| css-grid | 1038 | 1545 | was 1031 at the start of this stretch |
| css-flexbox | 650 | 908 | was 636; 258 failing |
| css-writing-modes | 650 | 995 | 638 committed; 650 with the uncommitted `sideways-lr` change |
| css-sizing | 335 | 457 | not re-measured |

Every commit below is local on master; nothing from this stretch is pushed (origin/master has the earlier css commits, 916705ec2). Local master has diverged from origin/master (same CSS content, different hashes): `git log origin/master..HEAD` and read the divergence before pushing the shared tree, and never push peers' local commits.

## Uncommitted: `sideways-lr` frame (lib/e/fmt/css/layout.e)

Built as `build/windows/run-wpt-r215.exe`. Writing-modes 638 -> 650, no writing-modes regression (fixes `wm-propagation-body-035/039/043/051`, `sideways-lr-main-axis`, `block-flow-direction-slr-066`, `table-progression-slr-001`, `vertical-alignment-slr-029/031/033/035/041`). NOT yet checked against css-flexbox (650) and css-grid (1038): `layout.e` is shared, so run both and diff the FAIL lists before committing. The change:

- `flow_frame(s, code)`: returns frame code 3 for `writing-mode: sideways-lr`, else the layout frame.
- `remap_rect(from == 3, to == 0)`: `vertical-lr` mapping with the inline axis reversed (`y = sw - x - w`). Used only when descendants are mapped out (`remap_children` in the two orthogonal paths). Layout still runs in frame 2 (`tr2`), so asymmetric top/bottom edges of a `sideways-lr` box are mapped as in `vertical-lr`: known approximation.
- The root of a `sideways-lr` document is laid out with `fi = ch` (viewport height), because its lines start at the bottom edge.
- Not done: text painting is still the clockwise rotation in `paint.e` (around line 968); counter-clockwise glyph rotation for `sideways-lr` may be what remains in the other slr tests.

If flexbox or grid regress, revert with `git checkout -- lib/e/fmt/css/layout.e` (only this change is in the diff) and note it as a Round.

## Committed in this stretch (local)

- 8b2347b20: `grid_split` splits a name group glued to a size (`[a]30px`, `30px[a]`); a subgrid's own names go in line order (`push_name_by_line`). css-grid 1035 -> 1037.
- e5bfd893d: `span <name>` ends at the n-th line of that name (`resolve_axis`); abspos children take span edges (`grid_abs_area`); a subgrid whose direction opposes its parent numbers the parent's names from the far end (`subgrid_names` flip, columns only). css-grid -> 1038.
- 6f6906b03: flex `justify-content` `start`/`end` follow the writing mode, `left`/`right` the page (not flex-start/end). css-flexbox 636 -> 643.
- 82961bb51: a horizontal-tb column flex container in rtl starts its lines on the right (`wrap_rev` flips); restricting to horizontal-tb avoided regressing the vertical baseline tests. css-flexbox -> 650.
- Docs only: 9d876da66 (Round 385), 543dcdb18 (388), 0e490fb11 (389), e485c1315 (392).

## Negative results (reverted; do not retry blindly)

- Synthetic subgrid-edge items in `subgrid_contributions` (Round 385): the 80px border is counted but no test changes; `column-subgrid-extra-margin-001` also depends on glyph width. Lanes equalization in `grid_widths` is spec-correct.
- Reversing a flipped subgrid's track sizes and swapping its edges (Round 389): `writing-directions-002` regressed and `t012` did not move. A flipped subgrid's names flip but its sizes must not, without also mirroring the edge padding.

## Open work, with the best lead for each

css-grid (507 failing):
- `subgrid/line-names-012` (`t012`, 15 cases): names resolve; the pixel diff is confined to the second parent track. The inner subgrid inherits `grid-column: 2 / span 2` from a shared stylesheet; in an rtl subgrid that is the physically left track. Look at how `layout_grid_inner` places a clamped `2 / span 2` child on an rtl subgrid's tracks.
- baseline `-002`, `-008`.
- Lanes subgrid (about 116 tests), grid-lanes track-sizing (51), alignment (50), abspos (42), intrinsic-sizing (33). Triage is in Round 381.

css-flexbox (258 failing, long tail; biggest groups first): `flexbox-writing-mode` 9, `balance/*` about 20, `aspect-ratio-intrinsic-size` 6, `flexbox-safe-overflow-position-001..005` (needs `parse_align` in `style.e` to keep the `safe` keyword, which it drops today, then honour it in every `Center`/`End` comparison), `flexbox-min-width-auto`, `flexbox-definite-sizes`, `baseline-*`. `flexbox_flex-0-*` (13) fail on the harness font (min-content of "three" is 80px, 64px in the reference): not a layout bug. `-left-002`/`-right-002` still differ.

css-writing-modes (345 failing after the uncommitted change): `table-cell-align` 6, `block-plaintext` 5, `bidi-override` 5, `bidi-isolate-override` 5, `ch-units-vrl` 4, `available-size` 4, `table-progression-vrl/vlr/slr` about 8, `vertical-alignment-*` and the remaining slr tests.

css-sizing: re-measure first (335 of 457 was an older sweep).

## How to measure (hard-won)

- Build the runner: `build/windows/neper-self.exe emit-executable tests/browser/wpt/run.e . x64 windows build/windows/run-wpt-rNNN.exe --arena 2g` from the repo root. A `fatal: out of memory: the system refused to commit` is transient memory pressure: retry.
- Run a suite: `build/windows/run-wpt-rNNN.exe --show --only css/css-grid/ /d/wptdata/wpt/MANIFEST.txt 2>&1 | grep -E "^FAIL|^wpt" | sort > tmp/rNNN-grid.txt`. Without `--show` the runner prints only the summary line. Always run from the repo root. A grid sweep takes about 10 to 15 minutes: run it in the background; the file stays empty until it finishes.
- `--only SUBSTR` filters the manifest. Do NOT build a sub-manifest by `grep`ing MANIFEST.txt lines into a new file: the paths then resolve wrongly and every pair reports as blank ("1545 pass, 1545 blank pairs", a false green).
- Compare to the last list: `diff <(grep ^FAIL old.txt) <(grep ^FAIL new.txt)`. Baselines kept in `tmp/` (uncommitted scratch): `r204-grid.txt` (1035), `r207-grid.txt` (1037), `r210-grid.txt` (1038), `r214-flex.txt` (650), `r214-wm.txt` (638), `r215-wm.txt` (650).
- One test with images: `--only NAME.html --out DIR MANIFEST` writes `*.test.png` and `*.ref.png` for failing pairs (DIR must exist). For a pixel diff use the neper-pyenv Python (`D:\tools\neper-pyenv\Scripts\python.exe`, PIL available).
- Corpus: `D:/wptdata/wpt/css/...` and `D:/wptdata/wpt/MANIFEST.txt`.
- Method that worked: split a failing test into per-case probes, find which cases fail, view the PNG pair, fix the rule, sweep the whole suite, keep only a clean net gain, write a Round (negative results included) in `docs/HANDOVER-BROWSER.md`.
- Test-font caveat: the harness has placeholder glyph widths. Tests whose result depends on text width or min-content of words are not fixable in layout.

## Environment traps

- Shared working tree: peers keep uncommitted edits. Commit only your paths (`git commit -m ... -- path path`), never `git add -A`/`.`. `lib/e/fmt/css/layout.e` was clean of peers' edits throughout this stretch, but recheck `git diff --stat` before staging.
- Bootstrap rules for `.e` in this area: no `-=`, no `if` expressions (statement `if`/`else` only), `io.printf` needs `use e.io`, a slice of a `[]const` is immutable (copy into an allocated array), locals named `target` are reserved.
- Windows full suite (`run.ps1`), needed before pushing: recipe in memory `neper-suite-green-recipe` (worktree outside D:\repos\neper, seed copy of neper-self, run under `pwsh`, Git Bash and neper-pyenv first on PATH, 35-60 minutes). It passed on the css-publish worktree before 916705ec2.
- Edit with the Edit tool or `build/windows/patch.exe`, not Python patch scripts (repo rule).

## Suggested order

1. Run flexbox and grid sweeps against the uncommitted `sideways-lr` build (`run-wpt-r215.exe`) and diff against `r214-flex.txt` / `r210-grid.txt`. Commit with a Round 393 entry if clean.
2. Check slr text painting (counter-clockwise) against the remaining slr failures.
3. `safe` overflow alignment (5 flexbox tests, then grid/lanes alignment).
4. `t012` rtl-subgrid child placement.
5. Re-measure css-sizing, then pick clusters as above.
