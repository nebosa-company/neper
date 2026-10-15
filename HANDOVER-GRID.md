# HANDOVER-GRID.md — the data grid parity stream (G012)

Updated every turn. Last update: 2026-10-14, after D5033 (colour editor steppers); earlier D5013 (axis for data bars + fallback fonts; local D4070); axis seen on the grid (AX3), Japanese (NE2) and Chinese (NE4) cards verified, Cyrillic verified (KO1, Segoe UI covers it); Korean (3 cards) only via Malgun registration, not looked at; right-to-left bar drawn right-anchored but faint at the default gradient (KO2).

## The goal (standing /goal, re-injected by a Stop hook every turn)

Iterate over all grid features of `e.ui.datagrid`, studying the Delphi source and the DevExpress grid, until
behaviour and look are pixel-identical to MTG Studio v3: colours, layout, backgrounds, runtime behaviour, every
menu and context popup. Screenshots of everything achieved go to the user with `SendUserFile` and into
`docs/grid-parity/`. Keyboard and mouse are driven by script (never by hand).

## Rules the user set

- Shared neper tree: commit explicit paths only (`git add -A` never). Never stage peers' `lib/e/ui/control.e`,
  `tests/selfhost/run.ps1`, `run.sh`, `docs/work-evidence.md`.
- Edit with the Edit tool or `build/windows/patch.exe` (check it really applied — a spec silently skipped one
  hunk once). No Python/heredoc patch scripts carrying old/new strings.
- Each decision is appended as `## D<n> - title` to `docs/decisions.md`; then `python scripts/render_digest.py`
  and `python scripts/render_progress.py`. Read `docs/digest/*.tsv` before `decisions.md`.
- Local D numbers (D40xx) differ from origin's (D50xx): port with `D:\Temp\claude\gt\push_g24.py <LOCALD> <files...>`
  (fresh worktree of origin/master, copies the files, renumbers the decision, renders, leaves it uncommitted;
  then `git add` explicit paths, commit, `git push origin HEAD:master`). GitHub account: `gh auth switch -u
  nebosa-company` for neper, `oboobortot` for the MTG repo (`D:\repos\mtg.studio.src`, branch `main`), then back.
- Commit trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- While Claude drives mouse/keyboard a warning-emoji overlay must show (`docs/grid-parity/mouse-warning.ps1`;
  `drive.ps1` does it) and be hidden afterwards.
- Skip the Legality menu (out of scope). Ignore Gleemax (CMC 1000000) in data bar ranges (done).
- End answers with `**Summary:**` and `**Next step:**` lines.

## Where things are

| What | Where |
|---|---|
| The grid | `lib/e/ui/datagrid.e` (~7.7k lines), `lib/e/ui/collection.e`, `lib/e/ui/gridrules.e`, `gridlook` |
| Fixtures (must pass) | `tests/selfhost/fixtures/link/ui_datagrid`, `ui_gridrules` (+ two more grid ones); run `bash scripts/check-fixture.sh ui_datagrid` |
| Sample app | `D:\repos\mtg.studio.src\v5\cardgrid\main.e` (build `powershell -File build.ps1`; delete `cardgrid.layout` before runs) |
| Trial script | `D:\Temp\claude\gt\trial.sh NAME` builds the sample, opens Rules > New Rule > Format..., writes `states\NAME.png` |
| v3 reference | `D:\repos\mtg.studio.src\version-3\bin\mtgstudio.exe`; Delphi source in `version-3\src\mtgstudio\ui\vcl` |
| Drive/capture | `docs/grid-parity/drive.ps1` (move/click/down/drag/up/kd/ku/key/wheel/shot), `capture.ps1` |
| Ledger | `docs/grid-parity/inventory.md`, screenshots `docs/grid-parity/*.png`, decisions D2467..D5006 |

Kill `mtgstudio.exe` before sample screenshots (it sits on top and the shot shows it).

## Done (pushed)

Filter row with v3 operator list and pictures; View menu (lines, header, indicator, auto width); application
menu; navigator pictures and footer band; check box cell; Enter-key action; Percent/Percentile bounds; formula
rule (one comparison); no-data messages; gradient data bars (Gleemax ignored); hover-thickening scroll thumbs;
horizontal scrolling with the navigator thumb; background picture (GRID_BACK, `set_backdrop`);
**Data Bar Rule Style Settings window** from Format... (`fmt_panel`, Fill mode and Border style live).

## Open (in priority order)

1. **Data Bar dialog rows that are drawn but inert** (Bar direction is LIVE since D5007: Context / Right To Left):
   negative bar colour and "apply same fill", axis colour (the Axis mode row is live since D5009), positive
   colour edit (the `...` button), the Preview strip. Bar drawing is at `lib/e/ui/datagrid.e` near
   `bar_length` (~line 6205); rule fields live in `gridrules.e` (`bar_solid`, `bar_border`); wizard state in
   `Grid` (`wiz_bar_style` bit0 solid, bit1 border, `fmt_open`). Add Rule fields + `apply` in `on_wiz_ok`.
2. Print Preview window built (D5014, `print_panel`: no toolbar icons, margins not editable, no zoom/paging); Print, Page Setup, Designer not built. (CSV/Text/XML/HTML/Excel/PDF export done, D5008; Excel export of 30000 rows works with a 96 MB scratch, D5020.)
3. (DONE D5013) columns keep widths while scrolling sideways, vertical bar fixed.
4. (DONE D5010/D5011) hovered scroll widths measured from v3.
5. Remaining DevExpress popup-size comparison; empty-grid message centring/size vs v3.
6. Never seen clearly: solid and bordered bar styles live (bar is a few px at CMC width) — use a wider column.
7. NEW finding (PR2 shot of v3): the selected collection row shows in-place editors: Qty and Used get a spin editor with left/right arrows, Buy at / Sell at get a '...' button; not built in ours.
8. Card Rules View entry: application-level, probably out of scope like Legality (confirm with the user).

## Traps (each cost real time)

- `build_parts` in datagrid.e: **do not add locals there** — it silently corrupts the rule wizard's styles
  (traps in `paint.validate`/`style.amount`, `style.e:32 unreachable`). Add helper functions
  (`shown_in_pane`, `wiz_panel` wrapping `wiz_panel_base`).
- No local named `target`; locals cannot shadow module functions; literal escapes only `\n \t \r \\ \" \' \0 \xHH`;
  module-scope `const` of f32/str gives a locationless E-TYPE-9999; a tuple call cannot be returned directly;
  too large struct additions to the sample `Model` give E-TYPE-9999; a failing window loop prints its error name.
- Exit statuses are mod 256 (650 shows as 138).
- Window scale is 1.5 px per layout unit; the sample layout shifts with the persisted layout, so delete it.
- The push worktree has no `cc`, so fixtures cannot be run there; run them in the main tree first.

- ALWAYS `taskkill //IM cardgrid.exe //F` before rebuilding the sample: a running exe makes the build fail with
  `os.Denied`, the old binary keeps running and its crash looks like a library fault.
- An overlay nested inside the wizard's overlay (even `modal: true`) gets no taps; keep the style window a stacked
  layer in `wiz_panel`. Helper functions that take `style.Style` by value and return nodes were suspected but not
  the cause; the percent left margin trick (`bar.margin.left`) gives the right-to-left bar with no extra nodes.
- `patch.exe` reports "patched" even when a hunk did not apply: grep for the result.

- Non-English cards need the extra system fonts the sample registers (Segoe UI, Yu Gothic, Malgun, YaHei, SimSun, MingLiU, Segoe UI Symbol):
  `layout` falls back across `Theme.fonts` by cmap; register every font with `scene.register_font`.

- Collection grid: Show Columns... in its menu opens the tabbed Customization window (CM2, D5018).

- `f32(x)` of a **u8** struct field (e.g. `f32(grid.fmt_pick)`) in a function that builds styles made the whole
  window trap in `style.amount` as soon as it opened, even in a branch not taken (D5032). Compare chains instead.
- Filter-operator popup sized from v3 (D5031); colour editor is a 24-colour palette (D5032): custom RGB, report
  Designer, typed spin boxes for Page Setup / Preview margins, Korean row and a negative-value bar seen on
  the grid are what remains.

## Where it stopped (2026-10-14, by the user's request: tokens)

Last landed: D5033 (custom RGB steppers in the colour editor, `98dd7a24`). Tree clean for my files.
Not started in the tree (only read): typed margin boxes. The plan, so the next session can do it:
- `pv_tenths: [6]u8` is "extra tenths over the base" (bases 5,5,5,5,2,2). Make it absolute hundredths
  (`[6]u16`, a `pv_ready` flag to init 50,50,50,50,20,20), change `margin_text(a, name, hund, two)`, the
  three step sites (`on_setup_tap` kind 5/6, `on_print_tap`, `print_margins`) and in `margins_content` use
  `control.spin_box_sized` (see the wizard's value field in `wiz_panel_base`) with a `{grid, slot}` ctx.
- Then Header/Footer cells and Fit To counts as text fields; Print Preview margin boxes the same way.
- Colour editor: typed R,G,B (or a hue square) instead of the R+/G+/B+ steppers.
- Report Designer: not built (menu entry is greyed). Korean row and a negative-value data bar not seen on
  the grid (no data; fixture guards only).
Before editing datagrid.e: `taskkill //IM cardgrid.exe`, avoid `f32(u8field)` and extra locals in
`build_parts`/`fmt_panel`; build with `build/windows/neper-self.exe emit-executable .../main.e ...`.

## Update 2026-10-14 (later)
D4095 (local `1b6a3e4d`): Margins tab uses typed spin boxes (`MarginSpin`, `set_margin`, `pv_hund`); fixture
ui_datagrid passes, sample builds, NOT seen on screen yet and NOT pushed (push_g24.py ran, D4095 -> D5034,
worktree left uncommitted). Remaining: Header/Footer + Fit To text fields, Print Preview margin boxes.

## Update 2026-10-14 (end of session)
Pushed: D5034-D5036 (typed margins, header/footer cells, Fit To, Print Preview margin boxes), `0cf9e924`.
Local, not pushed: D4098 (`008217d1`) the Data Bar style window in v3's layout (radios, chips, "..." buttons).
STALE in the Open list above: item 1 (the colour, negative, axis rows are live since D5032+), item 7 (the
collection row editors are done: ED1 in inventory). Still open: Print / Report Designer, Print Preview
paging and page drawing following margins, Page Setup multi-line cells and Font/Background buttons, typed
RGB or hue square, group frames and a real chevron glyph in the style window, popup-size comparison.
TRAP (D4098): a function with three Styles plus many Nodes corrupts the widget tree; keep style-window
helpers small, <= 8 argument words, pack flags/colour in one u64, pass no Node by value; bisect with
early `ret`s and `D:\Temp\claude\run.sh NAME` (build with neper-self directly: build.ps1 hides errors).

## Status of the tree

Committed locally; pushed through D4068 / D5007, D4069 / D5008 being pushed. Peers' dirty files in the
main tree (`lib/e/ui/control.e`, untracked `docs/tasks/...`) are not mine; leave them.

## Update 2026-10-15 (where the stream stands)
Pushed to origin: D5033-D5040 (margins, header/footer cells, Fit To, preview margins/paging, Data Bar window layout, colour RGB).
LOCAL, NOT PUSHED (22 neper commits, D4102-D4123; port with `D:\Temp\claude\gt\push_g24.py` in one commit, files:
`lib/e/ui/datagrid.e`, `lib/e/ui/collection.e`, the new `docs/grid-parity/*.png`): empty-grid message and count
(ND1/ND2), filter panel with clear/suspend/Customize (FP1-3), View/collection/column popup sizes (D4104-D4106),
Customization window tabs for the pool (D4107), print preview header/footer/date/margins (D4110-D4112),
three-row Page Setup cells, hue strip (D4115), View menu pictures and bold headings (D4116/D4117, sample side),
the report Designer = v3's Format Report window with five tabs (D4118-D4120, D4122), Cards/Charts tabs out of
scope by the user (D4121), drive.ps1 foreground guard (D4113/D4114/D4123).
The sample's `D:\repos\mtg.studio.src\v5\cardgrid\main.e` has uncommitted edits too (set_band_tabs, View menu
pictures, the Designer entry): commit them on `main` with `gh auth switch -u oboobortot`, then back to nebosa-company.
Still open: Title/Footnote Properties dialogs (v3's not recorded: v3 would not come to the front for the guarded
script, a browser kept taking focus), the Styles tab's controls edit nothing, other Designer checks only remembered,
Alt+P not wired in the sample, [Time Printed]/[User Name] predefined functions, Print Preview rows per page do not
follow the margins.
Traps found this session: a style-window helper building three Styles plus many Nodes corrupts the widget tree
(keep helpers small, pass flags packed in one u64); a spin box inside the colour popup layer ends the window loop;
scripts must use `run2.sh`-style builds with neper-self directly (build.ps1 hides errors); `drive.ps1` now refuses
to click unless the target is in front (checked before every step).
