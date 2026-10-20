# Handover: Neper browser control (CSS layout conformance) — 2026-10-20

For another account/session continuing the work. Goal in force: **keep implementing the browser until it is fully implemented and passes the reputable suites** (WPT CSS/HTML/layout reftests, test262). Nothing here is "done"; this is a checkpoint.

## 1. Where things stand

Engine: pure-E browser stack under `lib/e/` (`fmt/css/{layout,style,paint,...}.e`, `web/`, `js/`, `net/`), shell + e.ui control in `lib/e/web/shell.e` and `examples/browser/main.e`. Live pages render (Hacker News was rendered with `build/windows/render-csp.exe`, needs `--arena 6g`).

WPT reftest scores (runner `tests/browser/wpt/run.e`; `--show` lists FAIL lines):

| Suite | Start of this session | Latest measured |
|---|---|---|
| css/CSS2 | 5118 / 5829 | 5121 |
| css/css-flexbox | 581 / 908 | 610 |
| css/css-grid | 611 / 1545 | 633 |
| css/css-writing-modes | 406 / 995 | 549 |

Latest committed layout commits (newest first): `e44a149b9` bidi for atomic inlines + grid-lanes baseline carve-out; `3c514e324` vertical text central baseline + grid baseline from first item; `4ca799583` inline-level orthogonal boxes; `a224d4c76` flex/grid orthogonal items; `885eb8305` grid abspos rtl/last-baseline + `last baseline` parsing; `43275a6a2` relative offsets on floats + self-start/self-end; `8d5f1b14a` vertical-align top/bottom subtree; flexbox commits `8f13d72dc`, `44b57da4c`, `b82ab4ab3`, `a15ccdf61`.

## 2. Last change (committed)

The RTL abspos static-position change is committed: `scan_line` extends the line end past an `Abs` piece, `emit_line` places inline-level abspos boxes after the content before them (right of it in an rtl line), and `layout_abs` ends the box at that point for inline-level boxes in an rtl container of the same writing-mode frame (css_layout case 104). Final sweeps: writing-modes 549, CSS2 5121 (after restricting the branch to inline-level boxes), flexbox 610, css-grid 633 (five grid-lanes/subgrid tests newly failing, unexamined, likely coincidental passes before; one gained).

`git status` also shows modified `lib/e/js/intl*` and `lib/e/js/temporal*` files: those belong to another agent working in the same tree. **Do not stage them.** Stage only your own paths (`git add <path>`), never `git add -A` (repo rule in AGENTS.md).

## 3. The loop that works

1. Pick a failing cluster from a `--show` result (count by name prefix: `grep ^FAIL file | sed -E 's/-?[0-9]+[a-z]?\.(x?html?|xht)$//' | sort | uniq -c | sort -rn`).
2. Render one test and its reference side by side:
   ```bash
   mkdir -p /d/Temp/t/o && build/windows/run-wpt<N>.exe --only css/<suite>/<test> --out D:/Temp/t/o D:/wptdata/wpt/MANIFEST.txt
   ```
   Failing pairs write `<path>.test.png` / `.ref.png` (passing pairs write nothing). The **reference is rendered by our engine too**, so a reference can itself be wrong; read the reference HTML before trusting it. Compare with PIL/numpy (bounding boxes of colours) rather than eyeballing.
3. Fix in `lib/e/fmt/css/layout.e` (or style.e/paint.e). Add a **regression case** to `tests/selfhost/fixtures/link/css_layout/src/main.e` (next free case is 105; each check has its own `os.exit` code). The Ahem-like test measure is 1em per char, ascent 0.8em, descent 0.2em, default font 16px.
4. Run the fixture: `timeout 590 scripts/check-fixture.sh css_layout` (first run rebuilds the compiler, a few minutes). Other fixtures that exercise CSS: `css_style`, `css_paint`.
5. Build a fresh WPT runner and measure: `WPT_EXE=$PWD/build/windows/run-wptNN.exe tests/browser/wpt/run.sh --show --only css/css-flexbox/ D:/wptdata/wpt/MANIFEST.txt > file.txt`. Use a **new exe name each build** (run-wpt55 was the last). `--only` is a substring filter over manifest paths. The runner uses the manifest's directory as the base, so a scratch manifest must live in `D:/wptdata/wpt/` (a scratch test dir `zz/` + `ZZMANIFEST.txt` worked; delete afterwards).
6. Diff failure lists against the previous run: `diff <(grep ^FAIL old) <(grep ^FAIL new) | grep '^>'` (new failures). Zero new failures in CSS2, css-flexbox, css-grid, css-writing-modes before committing. CSS2 takes ~45–90 min, run it in the background and wait on a done-marker file (`until [ -f done ]; do sleep 20; done`), do not chain sleeps.
7. Commit only your paths.

## 4. Traps learned

- **Heavy sweeps are slow and concurrent runs slow each other**; one `run-wpt` uses ~1 core and ~1 GB. A CSS2 sweep that "stops growing" is usually one slow test; check CPU before killing.
- Shell is Git Bash on Windows: pass Windows-style `D:/...` to the .exe tools, `/d/...` to bash tools. `render-csp.exe` writes its PNG unreliably; use the WPT runner's `--out` instead.
- Compiler "arena exhausted / out of memory" is transient: retry. Render tool needs `--arena 6g`.
- E language: checked arithmetic, `mem.alloc` returns slices, reserved names (`target`, `ref`), no `continue` that skips an increment safely, borrow-view errors. Struct field order changes recompile everything.
- Changes that look unrelated can flip tests that passed **by coincidence** (test and reference wrong the same way), especially in `grid-lanes/subgrid` (subgrid is unimplemented). Judge net effect and look at what newly fails before reverting.
- Orthogonal flows: `layout_orthogonal` lays a box out in its own transposed frame (`l.vmode`, `transpose_style`, `remap_children`). Flex/grid items reach it via `flex_place_item` (forced sizes through `l.orth_fb`). Inline-level orthogonal boxes go through `layout_atomic`. Text in vertical (non-sideways) modes sits on the **central baseline** (`text_ascent`).
- Static positions of inline abspos boxes: set during `scan_line`, corrected in `emit_line`, consumed in `layout_abs` (`bb.aux`: 0 unplaced block-level, 2 placed by a line, 3 content-edge in a block container).

## 5. Remaining failure clusters (largest first, from the latest sweeps)

- **css-grid:** `grid-lanes` ≈ 617 failing (alignment 123, intrinsic-auto-repeat 82, intrinsic-sizing 55, track-sizing 49, baseline 40); `subgrid` ≈ 68 (not implemented); `abspos` ≈ 60 (orthogonal-positioned-grid-items, last-baseline, vertWM static positions); `alignment` ≈ 70; `grid-items`/`grid-model` ≈ 65.
- **css-flexbox:** ≈ 298 failing: baseline/align-self (`flexbox-align-self-baseline-*`, `flexbox-baseline-*`), `aspect-ratio` img cases, intrinsic sizing (`col-wrap-*`, `flex-minimum-width-*`), writing-mode items, `balance/*` (≈ 28, feature unimplemented), table-as-item, definite-size cases. `flexbox-align-self-horiz-002` still differs in the baseline row text widths.
- **css-writing-modes:** `sizing-orthog-*` (htb-in-vrl/vlr 26, prct 32), `available-size` 13, bidi families (`bidi-plaintext/override/normal/isolate/embed/unset` ≈ 60, plaintext/isolates across inline boxes), `block-flow-direction-slr` 12, `line-box-direction-slr` 9, `wm-propagation-body` 9, `text-indent-vrl/vlr`, `clip-rect-*`, `border-conflict-element-*`, tables (`table-cell-align`, `table-column-order`), floats in vertical modes.
- **CSS2:** ≈ 708 failing, spread thin (abspos overflow clipping, first-line pseudo, fixed table layout percent cols, bidi across inline boxes).
- **Other tracks** (from the standing goal): test262 (`class-elements` crash, `Array/map`, RegExp property-escape speed ≈ 6 s/test), GitHub-scripts crash, WebAssembly body-type validation, HTTP/2, CSP, browser shell polish (shortcuts, history search, downloads, favicons). These were implemented to a first working version earlier in the session; see their fixtures (`wasm_exec`, `net_h2client`, `web_csp`, `web_page_csp`, `web_shell`, `js_generator_shutdown`) before extending.

## 6. Rules of the repo and the user

- A fix is "done" only with a regression test that fails if the behaviour breaks (here: a `css_layout` case, or a JS test under `tests/browser/js/own`). Name tests for the behaviour.
- Minimal comments; only non-derivable why/constraints.
- Commit directly on `main`, only touched paths, with the Co-Authored-By trailer. Fetch before pushing; other agents commit to the same repo concurrently.
- End substantive replies with a one-sentence **Summary:** and **Next step:** (user's global CLAUDE.md).
