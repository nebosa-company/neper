# Handover: the ten looks (state at 2026-11-03, master at the commit that adds this file)

For whoever continues the looks programme. It follows `26-10-20-HANDOVER-UI-LIB-L-and-F.md` (read that
for the architecture of `lib/e/ui/`, the token system and the Windows reference captures). This file
covers what changed since: how rows are now judged, how work and audits are run, what is still open.

## 1. What exists

One Neper widget set (`lib/e/ui/`, language Neper, `.e`) drawn in ten looks: Neper, NeperDark, Windows,
WindowsDark, Linux, LinuxDark, Cupertino, CupertinoDark, Material, MaterialDark. 120 controls have a
sheet app under `examples/looks/` that writes PNGs to `docs/ui/looks/<look>/<control>*.png` (1x and
1.5x). `docs/ui/looks-progress.html` (generated, about 10 MB) is the single progress page.

Status lives in `docs/ui/looks/status.json` plus overlays in `docs/ui/looks/status.d/*.json`, applied in
**sorted filename order, later wins**. The page is `python scripts/render_looks.py` (see section 4).

Ladder: planned 0, started 20, review 60, ready 100, matched 100. The headline percentage per look is
the mean over the 30 Delphi-equivalent controls only; the other 90 "platform idiom" rows are on the page
but are not in it.

## 2. Latest audited numbers (audit 47, Light / Dark, 30 base controls)

| Look | Completion |
|---|---|
| Neper | 100 / 100 |
| Linux | 100 / 100 |
| Windows | 99 / 99 |
| macOS / iOS (Cupertino) | 100 / 100 |
| Android (Material) | 100 / 100 |

Start of the audited series (audit 35): Windows 85 / 77, Neper 91 / 91, macOS 65 / 71, Android 79 / 80.

**Read 100 correctly.** It does not mean "matched a real reference" everywhere (section 3). Many `ready`
rows rest on measured numbers against cited public specs and contrast probes, not on a capture.
`matched` is the stronger word and is used only where a reference was measured.

## 3. How a row is judged (decisions made along the way)

- No real macOS, iOS or Android screenshots will ever exist. References: **Neper = Flutter Material 3,
  seed #1b3a6b** (`docs/ui/looks/ref/flutter/neper`); **Android = Flutter M3 baseline #6750A4**
  (`ref/flutter/material`; palette difference recorded); **macOS/iOS = Flutter Cupertino, shapes only**
  (`ref/flutter/cupertino`, Roboto stands in for SF so text pixels are excluded). Windows has the v3
  captures (`ref/windows-1to1`, `ref/windows-native`); Linux has libadwaita captures. Flutter harness:
  `scripts/flutter_refs/` (Flutter 3.44.2 offline, project outside the repo); outputs and `manifest.csv`
  are committed. The black outline on hovered buttons in the Flutter refs is a harness artifact: never match it.
- Where Flutter deviates from the M3 spec on purpose, the spec wins for the Android look and the
  deviation is recorded (small top app bar 64 dp, scrim 32 %, handle 40 % opacity).
- **Relaxed rule (maintainer, from round 79, for goal "complete all looks")**: a row with no reference may
  be `ready` when every cell is drawn correctly and legible (viewed at 1x and 1.5x, light and dark),
  measured against cited public numbers (WinUI/Win32, M3 tokens, Apple HIG), contrast >= 4.5:1 text and
  >= 3:1 controls, no clipping, no Material-looking shape where an iOS or macOS idiom exists. `matched`
  still needs a measured reference. The rule was applied by the workers and then checked by audits that
  downgraded rows that failed it (every audit from 39 to 47 except 42 downgraded between one and five rows).
- Dark Windows rows are a maintainer-accepted derivation of the light capture (v3 has no dark mode); they
  must still meet the contrast numbers.
- Neper uses true circular-arc corners (`widget.set_arc_corners`, Neper looks only).

## 4. How to work (mechanics that bit)

- One git worktree per worker: `git -C D:/repos/neper_master worktree add -b <name> D:/Temp/lanes/<name> master`,
  `git config core.longpaths true`, copy `D:/repos/neper/build/windows/neper-self.exe` into the worktree
  `build/windows/`. `D:/repos/neper` is on another session's branch: never stash, reset, checkout or commit there.
  `D:/repos/neper_master` has been used by other sessions too (it was on `av1-decoder` for part of this
  work): do not check out or commit there. Land work by merging in a throwaway worktree
  (`merge84`..`merge88` were that), then `git branch -f master <branch>` after `git merge-base --is-ancestor master <branch>`
  (works only because `master` is not checked out anywhere). Nothing was pushed.
- Compile one app: `build/windows/neper-self.exe emit-executable examples/looks/X.e <root> x64 windows <out>.exe --arena 4g`
  (use `--arena 8g` when it reports arena errors). Render one app at a time, in the foreground; never run
  `scripts/render_looks_all.sh` in one call. Python: `export PATH=/d/tools/python312:$PATH`.
- **Overlay paths exceed 260 characters** (names carry 240 to 255 characters so they sort after every
  other overlay). `render_looks.py` resolves substs and fails with FileNotFoundError; use
  `python scripts/render_looks_long.py` (added with this handover) instead. When naming a new overlay it must
  sort after the newest one; check with `ls docs/ui/looks/status.d | sort | tail`. The 255-character limit
  is nearly exhausted: the newest overlays are `~audit47.json` style names for that reason (`~` sorts after `z`).
  Consider consolidating old overlays into `status.json` to end this.
- New drawing code goes in per-round files (`lib/e/ui/looks_<letter><round>.e`) with minimal hooks in the
  shared files (`control.e`, `navigation.e`, `overlay.e`, `collection.e`, `looks.e`, `widget.e`). Every change in a
  shared file must be proved byte-identical for the other looks by re-rendering at least 20 sheets.
  Hooks seen: `looks.aim` (harness pointer position per cell: it persists across the looks of one run, reset it
  for the other looks), `widget.soft_shadows` (Android rig only), `pad_neper`, `focus_inset` (Cupertino).
- A recurring harness bug: cells that share keys make the runtime resolve a pointer to the first element
  carrying a key, so hover or press never shows in the wrong cell. Another: a pointer aimed at the cell centre
  lands 30 px from a small control. Fix the aim or give each cell its own keys.
- Stale pictures: some committed PNGs differ from a fresh render on unchanged code (Windows Dark
  `data_grid_main`, `native_dark4`, `dock_panel`, Material `date_input`, Cupertino `tree_table`,
  `swipe_actions`, Neper `side_sheet`/`popover`/`flyout` came up in turn). Restore the committed bytes unless
  you can explain the change, and never commit an unexplained re-render.
- Commit messages: plain prose, no em dashes (repo rule), with the Co-Authored-By trailer.
- The `Stop` hook and the `/goal` check-ins ran throughout; briefs were kept in `D:/Temp/claude/briefs/`, which
  was emptied, so the rules above are the only copy.

## 5. How the audits ran (and should keep running)

Each round: 2 to 3 workers (one per look group) on their own branches, then a merge branch, then an independent
audit with its own scratch comparers that does not trust the workers' claims: it re-renders about 15 sheets per lane
plus at least 40 other-look sheets (byte-identical check), prints the effective status of every touched row,
views the raised rows at both scales, and downgrades what fails via a later overlay. Sections "Audit 29" to
"Audit 47" at the top of `docs/ui/looks/audit.md` record each one. Workers' reports were repeatedly optimistic
(missing 1.5x views, unmeasured rows, stale pictures, wrong contrast figures): treat unaudited claims as claims.
Per-look evidence notes: `flutter-compare*.md`, `windows-complete-x.md`, `cupertino-complete-y.md`,
`material-complete-z.md`, `windows-gaps-o.md`, `windows-fixes-r.md`, `windows-fixes-t.md`.

## 6. What is still open (none of it is in the headline)

- **Cupertino `table`** was downgraded in audit 47: in `surf_table` the sort arrow is drawn on top of the "Qty"
  caption in the 56 px column (1x and 1.5x, light and dark). Widen the column or move the arrow, re-render, re-raise.
- **Windows `dialog` (review, Light and Dark):** 12 dialog bodies are composed (the sheets needed 14; which two are
  missing is not recorded here: check `windows-complete-x.md`, round 88) and 32 of 119 cells pass the strict compare; states with no capture (caption pressed, resize, disabled), the message-box bitmaps and the task dialog are
  not drawn. Deviations from the captures: the Deck Legality memo uses Tahoma 13 (capture is Verdana 11), the About
  skull is posterised to six levels, Deck Properties shows another file name. Dark: the Missing Set Cards edition
  names are 2.3 to 2.9:1. The older bodies (Search, Sort, Missing Set Cards, Options) were not re-fitted.
- Windows other open rows: Light `data_grid_main` is excluded as a different composition (the 1:1 set shows the current
  v3 main window); the Shortcuts icon residue is 4 px at 111 levels on one channel.
- **Cupertino idiom rows:** about 22 viewed and left at review for Material or web idioms or a visible defect
  (autocomplete, banner, breadcrumbs, carousel, color_picker, dial, dock_panel, font_picker, grid_view, image,
  key_caps, list, navigation_rail, navigation_split, pagination, range_slider, scroll_area, shortcut_recorder,
  terminal_view, wizard, reorderable_list, pull_to_refresh); never viewed: notification_list, page_view, schedule,
  flow_editor, stepper, sheet. Cupertino `date_edit` is `ready` with a stated limit: the iOS compact capsule and the
  macOS stepper field are not drawn. Glyph shapes (ribbon) are drawn from memory, not an Apple capture.
- **Material idiom rows:** terminal_view (focus cell never puts focus in the terminal), icon and image (library
  glyphs, not Material Symbols), schedule, flow_editor, sheet (states equal rest in the library), android_text_modes
  (a rendering mode); markdown_view two-word link hover is a recorded gap; `hint` was last held by a shadow-edge
  difference against Material Web. Material `table` is `matched` with two recorded deviations (16 dp margin against
  24, Type column left aligned).
- **Limits of the evidence:** the contrast figures are nominal ink pairs at the pixel; not every Cupertino row was
  viewed at 1.5x; Material 1.5x pictures were not opened in audit 47; the Linux and Neper looks were not the subject of
  any audit after round 77, so a fresh independent look at them is worthwhile before calling the programme done.
- Housekeeping: nothing is pushed anywhere; `docs/ui/looks-progress.html` is large and conflicts on every merge
  (take either side, regenerate); the overlay-name length problem above; temporary worktrees under
  `D:/Temp/lanes/` and the branches `looks62-*` to `looks88-*`, `audit*`, `merge84`..`merge88` can be removed.
  A Claude Design artifact with the derived macOS, Android and Windows 11 sheets exists
  (https://claude.ai/artifact/RDcCzMvf45BazMab7ophNe, private, metrics only).
