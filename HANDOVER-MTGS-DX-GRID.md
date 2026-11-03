# HANDOVER-MTGS-DX-GRID.md - MTG Studio v3 / DevExpress grid parity (G012)

Written 2026-11-04. Supersedes the stale parts of `HANDOVER-GRID.md` (its "Open" list and status sections predate
D4102-D4160); its Traps section is still valid.

## Goal

Make `lib/e/ui/datagrid.e` and the windows around it pixel-identical in look and behaviour to MTG Studio v3 (Delphi
+ DevExpress TcxGrid): colours, sizes, popups, dialogs, read-only columns. Every achievement is screenshotted
(`SendUserFile` to the user, and saved in `docs/grid-parity/`). Mouse and keyboard are driven by script, never by hand.

## User rules

- Commit explicit paths only (shared tree; never `git add -A`). Peers' dirty files are not mine.
- Edit with the Edit tool or `build/windows/patch.exe`; grep afterwards, it reports "patched" even when a hunk missed.
- Each decision is `## D<n> - title` in `docs/decisions.md`, then `python scripts/render_digest.py` and
  `python scripts/render_progress.py`.
- Skip the Legality menu and the Designer's Cards and Charts tabs (not used in MTG Studio).
- Use the standard controls, sized like v3's (Button 75x23, edit 21 high); no oversized hand-built look.
- The user approves before any push. Local D numbers (D41xx) differ from origin's (D50xx).
- Warning-emoji overlay while Claude drives the mouse (`drive.ps1` does it).
- Trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. End answers with Summary / Next step lines.

## Where things are

| What | Where |
|---|---|
| The grid and every window | `lib/e/ui/datagrid.e` (~11.9k lines), also `collection.e`, `gridrules.e`, `control.e` |
| Fixture | `bash scripts/check-fixture.sh ui_datagrid` (also `ui_gridrules`) |
| Sample app | `D:\repos\mtg.studio.src\v5\cardgrid\main.e`; build `build/windows/neper-self.exe emit-executable main.e D:/repos/neper x64 windows cardgrid.exe --arena 512m` from that folder (`build.ps1` hides errors); `taskkill //IM cardgrid.exe //F` first; delete `cardgrid.layout` before runs |
| v3 reference | exe `D:\repos\mtg.studio.src\version-3\bin\mtgstudio.exe`; Delphi forms `version-3\src\mtgstudio\ui\vcl\*.dfm`; DevExpress style sheets in `main.vcl.data.dfm` |
| Driving/capture | `docs/grid-parity/drive.ps1 -Proc cardgrid -Script "click x y;key 118;wait ms;shot name"` (x,y relative to the window; shots land in `D:\Temp\claude\gt\states\`). `D:\Temp\claude\run2.sh` builds, runs, drives |
| Audit | `docs/grid-parity/tcxgrid-audit.md` (all 19 TcxGrid controls, read-only flags), `tcxgrid-plan.md` (build order), `v3-menu-tree.md`; generators `scripts/audit_tcxgrid.py`, `scripts/audit_v3_menus.py` |
| Captures | `docs/grid-parity/tcxgrid/NN-name-v3.png` (v3) and `-v5.png` (ours) |
| Ledger | `docs/grid-parity/inventory.md`, screenshots in `docs/grid-parity/*.png` |

The sample's View menu opens Messages (Ctrl+M), Statistics (F7) and Options. In the screenshots the View button is at
about (618, 353) and Statistics in its popup at (130, 897) with the 1300 px window.

## Done

Earlier (see `HANDOVER-GRID.md`, pushed): filter row, view menu, navigator, data bars, scrolling, export, Data Bar
style window, print preview, Page Setup, report Designer, colour editor (D4102-D4157).

This stream, pushed as D5097-D5099 (`f6e10169d` on origin/master):
- D4158: TcxGrid audit of all 19 grids; v3 control helpers `v3_button`, `v3_edit`, `v3_idle` (75x23 / 21 high),
  Designer dialogs moved onto them.
- D4159: read-only table helper `st_table`; windows Messages, Options > Shortcuts, Statistics (Editions, Advanced).
- D4160: Statistics Probability, Mana Slots, Start Hand; tab widths and banners from the v3 capture.

## Not pushed

- Sample `main.e` (v5/cardgrid): View menu entries Messages/Statistics/Options, window width 1300. Commit on `main`
  with `gh auth switch -u oboobortot`, then `gh auth switch -u nebosa-company` (a 403 on the neper push means the
  wrong account is active).
- Local neper master has about 700 commits ahead of origin (peers' lanes). Do not push the shared tree; port with
  `D:\Temp\claude\gt\push_g24.py <LOCALD> <files...>` (fresh worktree on origin/master, copies the files, renumbers the
  decision, renders; then `git add` explicit paths, commit, `git push origin HEAD:master`). For several decisions
  run it for the first and append the other blocks by hand, renumbered.

## Open

1. Statistics: Colors, Rarity, Card Type (charts), Mana Analyser, Mana Product, Power Analyser tabs still say "not
   built yet". Tab pictures, rotated bar captions, the Importance icon are not drawn. Controls on Probability, Mana
   Slots and Start Hand are drawn but inert; data is v3's capture sample, not computed from the deck. Panel is 891 wide
   (v3's 990 times 0.9, horizontal only).
2. Unbuilt TcxGrids: Prices panel, Abilities, Filter (blocks/formats/editions), Import preview (12 views), Price
   dialog, Select Edition. Abilities, Price dialog and Import preview were not captured from v3 yet.
3. Dialogs still on the old oversized hand-built controls: Data Bar `fmt_*`, Page Setup `setup_box`, Sort
   `sort_button`, margin/RGB spin boxes, check boxes, radios, group boxes. Move them onto shared v3 helpers
   (`st_radio`, `st_group`, `st_spin`, `st_button` in the Statistics section are small candidates to promote).
4. Messages, Options and Shortcuts were not re-checked after the 1300 px window and the shared-table changes.
5. Older: Title/Footnote Properties dialogs, Designer Styles tab edits nothing, Print Preview rows per page ignore
   margins, Alt+P not wired in the sample.

## Traps

- Sample window: width above 1300 fails (`widget.TooLarge` on the first menu click at 1440+; raising
  `max_elements` or the frame arena gives `scene.OutOfMemory` or "host cannot open a window"). Keep 1300x900.
- Window units are about 1.45 px per layout unit; the screenshots are 1:1 px. v3 captures were converted with 1.42.
- Never name a local `table` or `target` (E-NAME-0003); a function returning `style.Style` by value, and module-scope
  `f32`/`str` consts, give a locationless E-TYPE-9999; array literal length must equal the declared length; a helper
  with three Styles plus many Nodes corrupts the widget tree (keep helpers small); do not add locals to `build_parts`;
  `f32(u8field)` in a style-building function traps.
- A stack of N absolutely placed children needs the array allocated for all of them (index out of bounds otherwise).
- `drive.ps1` refuses to click unless the app is in front; after a refusal re-run. Modal windows close with their X or
  `closewin.ps1`. Never full-screen capture (it picked up unrelated user content); use window or region shots.
- Kill `mtgstudio.exe` before sample screenshots; kill `cardgrid.exe` before rebuilding (`os.Denied` otherwise).
- Fixtures cannot run in the push worktree (no `cc`); run them in the main tree first.
