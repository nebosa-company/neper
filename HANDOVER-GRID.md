# HANDOVER-GRID.md — the data grid parity stream (G012)

Updated every turn. Last update: 2026-10-14, after D5013 (sideways scroll fix); earlier D5009 (axis for data bars + fallback fonts; local D4070); axis seen on the grid (AX3), Japanese (NE2) and Chinese (NE4) cards verified, Cyrillic verified (KO1, Segoe UI covers it); Korean (3 cards) only via Malgun registration, not looked at; right-to-left bar drawn right-anchored but faint at the default gradient (KO2).

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
2. Print Preview window built (D5014, `print_panel`: no toolbar icons, margins not editable, no zoom/paging); Print, Page Setup, Designer not built. (CSV/Text/XML/HTML/Excel/PDF export done, D5008; the Excel export fails above ~2000 rows with long card texts: `book.encode` error not chased.)
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

## Status of the tree

Committed locally; pushed through D4068 / D5007, D4069 / D5008 being pushed. Peers' dirty files in the
main tree (`lib/e/ui/control.e`, untracked `docs/tasks/...`) are not mine; leave them.
