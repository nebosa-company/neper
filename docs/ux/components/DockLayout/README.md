# DockLayout

A dock layout arranges an IDE-style window: a central document area surrounded by left, right and bottom slots of DockPanels, separated by draggable sashes, with panels the user can move, stack, collapse, maximise and restore, and a layout that persists.

## Anatomy
1. Activity strip (optional): a 40-wide `surface-container` column of toggle icon buttons, one per side-slot panel.
2. Side slots: left and right, each holding one or more DockPanels (single, tab group or stacked).
3. Centre: the document area (usually a MultiDocumentWorkspace).
4. Bottom slot: under the centre (or across the full width, a per-app choice), usually a tab group.
5. Sashes: 1px `outline-variant` lines between slots with an 8px grab area; 4px `primary` on hover and drag.
6. While moving a panel: the ghost (the panel's title chip under the pointer), the dock guide (a compass of targets over the slot under the pointer) and the drop preview (a `primary-container` area showing where the panel will land).

## Variants and when to use
| Variant | Use for |
|---|---|
| Three sides and centre | IDEs and design tools: Explorer left, Inspector right, Problems/Terminal bottom. |
| Two sides | Simpler tools: navigator left, inspector right, no bottom. |
| Bottom only | Consoles and data tools: the main view with an output pane. |
| Locked | Kiosk or embedded tools where panels must not move: sashes still resize, no dragging or tearing. |

Two panes of a list and its detail are NavigationSplit. A single resizable pair of panes is a SplitView. Floating tool windows over any layout are DockPanel's floating variant.

## Specs
| Part | Value |
|---|---|
| Activity strip | `control-md` 40 wide, `surface-container`, icon buttons `control-sm` 32, gap `space-1` 4; the open panel's button is tonal (`secondary-container`) |
| Side slot width | default 240 (left), 280 (right); min 160; max 50% of the window |
| Bottom slot height | default 200; min header + 64; max 70% of the window height |
| Centre minimum | 320 x 160; sashes stop there |
| Sash | `divider` 1, `outline-variant`; grab area 8 (4 each side), cursor col-resize / row-resize |
| Sash hover and drag | 4 `primary`, after `duration-medium-4` hover delay (instantly on press) |
| Sash focus | ring round the sash, 3 `focus-ring` |
| Ghost | `surface-container-high`, `radius-sm`, `elevation-4`, 32 tall, `label-medium`, 92% opacity |
| Dock guide | `surface-container-high`, `radius-md`, `elevation-2`, 3 x 3 grid of 32 targets, gap 4, padding 4; targets `surface-container-highest` / `on-surface-variant`; the one under the pointer `primary` / `on-primary` |
| Drop preview | `primary-container` at 72% with a 2 `primary` inner outline, `radius-xs`, 4 inset from the slot |
| Slot backgrounds | panels `surface-container-low`; centre `surface` |

## States
- Rest: sashes as hairlines.
- Sash hover / drag / focus as above; while dragging, the cursor keeps its resize shape across the window and content does not reflow until the drag moves 1 px (live resize thereafter).
- Panel moving: ghost, guide, preview; drop targets are the four sides and the centre (as a tab) of the slot under the pointer, plus the window's four outer edges.
- Collapsed side: the slot shrinks to its activity-strip button; the sash hides.
- Maximised: one panel or the centre fills the window; others hide until Restore (double-click the header or Ctrl+M).
- Reset: View > Reset layout restores the app's default.

## Behaviour
- Resizing: drag a sash; double-click a sash to reset that slot to its default. Keyboard: sashes are focusable in the F6 cycle; Left/Right (Up/Down for horizontal sashes) move by 8, Shift by 32 (the old card's `space-md` step is kept as the fine step), Home/End to min/max, Enter toggles collapse.
- Collapsing: dragging a side below its minimum snaps it collapsed; dragging from the collapsed edge or pressing its strip button reopens it at its last size.
- Moving: drag a panel's header or tab after 4 px. The guide appears over the slot under the pointer; releasing on a guide target or anywhere in its preview area docks there; releasing outside any target floats the panel (tear-off). Escape cancels and returns the panel.
- Keyboard moving: "Move panel" in the panel's header menu enters a mode where arrow keys pick a target and Enter docks.
- Persistence: slot sizes, panel positions, collapsed and floating state save per workspace and restore on launch; a window too small for the saved sizes scales them down proportionally, keeping the centre's minimum.
- Motion: guide and preview fade in over `duration-short-3` with `ease-standard` and the preview slides between targets over `duration-short-4`; docking snaps with `ease-emphasized-decelerate` over `duration-medium-1`; collapse animates the slot width over `duration-short-4`. Reduced motion: no slides, instant preview moves.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Full docking with tear-off into owned tool windows; the guide matches Visual Studio's compass convention; F6 cycles; Aero snap is not affected (the window itself still snaps). |
| macOS | Docking without a guide compass is the Xcode convention: show the drop preview only; torn-off panels are utility panels; side slots toggle with ⌘0 (left) and ⌥⌘0 (right). |
| Linux | Full docking; on Wayland torn-off panels may not position themselves (let the compositor place them near the pointer). |
| Android | Not used. At `window-expanded` a fixed list-detail-supporting pane layout (NavigationSplit plus a side sheet); on compact, sheets. |
| iOS | Not used. iPad: sidebar, content, inspector columns with fixed positions; iPhone: sheets. |
| Web | Full docking within the page; tear-off floats inside the page; persistence in the app's storage, not per browser tab. |

## Accessibility
- The layout is a Group; each slot's panels are Region landmarks named by title; the centre is the Main landmark.
- Sashes are Separators with a value (the slot size as a percentage of its range), orientation, and Increment / Decrement; named by the slot: "Resize left panel".
- F6 / Shift+F6 cycle focus through centre, panels and sashes in visual order; the order is announced by each Region's name.
- Moving a panel by keyboard is always available ("Move panel", then arrow keys and Enter), so drag is never the only way; announce each target as it is picked ("Dock to the right of the editor").
- Contrast: sash hairlines are decorative (the tonal step between `surface-container-low` panels and the `surface` centre separates slots); the 4px `primary` hover line is 3:1 or better against both.
- Reduced motion: no slides.

## Content
- Menu commands: "Reset layout", "Move panel", "Maximise panel", "Restore panel", "Show left side", "Hide bottom panel". Sentence case.
- Announcements name the panel and the target: "Terminal docked below the editor".

## e.ui today
`navigation.dock_layout` builds left, centre-over-bottom and right with `control.resizable_pane` handles 4 px thick filled with `border`, reporting a whole `DockSizes` to `change`; sides keep at least 32 and arrow keys move by `space-md`. To reach this design:
- Draw sashes as 1px `outline-variant` lines with an 8px grab area and the 4px `primary` hover/drag state, instead of 4px `border` bars.
- Remove the dead code: `moves[2]` is built and never used, so `dock_move_fire`'s bottom branch is unreachable; route the bottom sash through the same move handler and stop passing the height in `DockMove.width` (`dock_bottom_fire`).
- Raise minimums to 160 for sides and 320 x 160 for the centre, add collapse-on-drag, double-click reset and Home/End.
- Add panel moving: the ghost, dock guide, drop preview, tear-off to floating and keyboard moving; the model needs panel-to-slot assignment, not four fixed nodes.
- Add the activity strip, maximise/restore, persistence of sizes and positions, and Separator semantics with values and names per sash ("Resize left panel" rather than "Left panel").
