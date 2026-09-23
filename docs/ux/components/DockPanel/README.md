# DockPanel

A dock panel is a tool window (an explorer, a problems list, a terminal, an inspector) with a titled header and its own actions, that lives in a slot of a DockLayout, shares that slot with other panels as tabs, collapses, and can be torn off to float.

## Anatomy
1. Container: `surface-container-low`, square when docked; `surface-container`, `radius-md`, `elevation-3` when floating.
2. Header: 32 tall; the panel's name in `label-medium`, or the tabs of the panels sharing the slot.
3. Focus indicator: a 2px `primary` line along the header's top edge while focus is inside the panel.
4. Header actions: up to three 32 icon buttons (panel-specific, then Maximise and Close, or More).
5. Disclosure chevron (stacked panels only): `chevron-down` open, `chevron-right` collapsed.
6. Body: the caller's content, clipped, scrolling on its own.
7. Floating only: a drag handle (`drag-handle`) in a 40 header and a Dock button (`dock-left`) that returns it to its last slot.

## Variants and when to use
| Variant | Use for |
|---|---|
| Single | One tool in a slot: Explorer on the left, Inspector on the right. |
| Tab group | Several tools sharing a slot, only one visible: Problems, Output, Terminal at the bottom. |
| Stacked | Several tools visible at once in one side slot, each collapsible: Outline, Timeline, Breakpoints. |
| Floating | A panel the user tore off the dock; stays above the main window, remembers its size and position. |

Content that is not a tool (a summary, an entity) is a Card. A pane of a two-part master-detail view is NavigationSplit. A transient panel that covers content and dismisses is a Sheet (side sheet).

## Specs
| Part | Docked | Floating |
|---|---|---|
| Header height | `control-sm` 32 | `control-md` 40 |
| Header padding | `space-3` 12 start, `space-1` 4 end | same |
| Title | `label-medium` 12/16 600, `on-surface-variant`; focused `on-surface` | `on-surface` |
| Focus line | 2 `primary`, inside the top edge | none (the window's focus shows it) |
| Header actions | icon buttons `control-sm` 32, 18 icons, gap 0 | same |
| Panel tab | `label-medium`, 12 sides, 32 tall; current `on-surface` with a 2 x (label width) `primary` line at the bottom | same |
| Count badge on a tab | `nu-badge` on `secondary-container` / `on-secondary-container` | same |
| Container | `surface-container-low`, square, no border (sashes separate panels) | `surface-container`, `radius-md`, `elevation-3` |
| Body | padding 0 (content decides); rows 24 tall in tool lists | same |
| Minimum size | 160 wide, header + 64 tall | 240 x 160 |
| Empty state | `body-small` `on-surface-variant`, 12 sides, 8 top, with the action that fills it | same |

## States
- Unfocused, focused (primary line and `on-surface` title), collapsed (header only), maximised (fills the dock's centre area, the Maximise icon flips to `chevron-down` "Restore panel"), floating, hidden (closed; reopened from the View menu or its activity-strip icon).
- Header actions: hover, focus ring, pressed, disabled.
- Tab group: current tab, hover, focus (inset ring), dragged (see DockLayout).
- Busy: a 2px indeterminate linear progress under the header while the panel loads.
- Empty: a sentence saying why and how to fill it.

## Behaviour
- Pressing anywhere in a panel focuses it; the focus line moves with keyboard focus too. F6 and Shift+F6 cycle focus between the editor and visible panels; Escape in a panel returns focus to the editor.
- Header: double-click maximises and restores; drag the header (or a tab) to move the panel to another slot or tear it off (see DockLayout for drop targets). Collapsible headers toggle on press, Enter or Space; Left collapses, Right expands.
- Tabs in the header: Left/Right move, Enter selects, Delete closes the panel; the current tab's panel is remembered per slot.
- Close hides the panel; it keeps its state and returns to the same slot when reopened. It never deletes content.
- Floating panels stay above their main window, not above other apps; they hide when the app is inactive on macOS.
- Motion: collapse and expand over `duration-short-4` with `ease-standard` (height); a torn-off panel follows the pointer at once; docking snaps with `ease-emphasized-decelerate` over `duration-medium-1`. Reduced motion: no height animation.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Docked pointer density; floating panels are owned tool windows (they minimise with the main window); F6 cycles panes. |
| macOS | Docked pointer density; floating panels are utility panels (`NSPanel`) that hide on deactivation; headers follow the sidebar/inspector look (no drag handle, title in the panel's own title bar when floating). |
| Linux | Docked pointer density; floating panels are transient windows of the main window; Wayland may not allow them to position themselves (let the compositor place them). |
| Android | No docking. At `window-expanded`, a panel becomes a side sheet or a supporting pane; on compact, a bottom sheet. |
| iOS | No docking. iPad: an inspector column (supporting pane) with the same header; iPhone: a sheet. |
| Web | Docked; floating panels stay inside the page (no new browser windows); drag uses pointer events, not HTML drag and drop. |

## Accessibility
- Role Region (a landmark) named by the panel's title; a tab group is a TabList whose tabs control TabPanels.
- Collapsible headers are Buttons with Expanded; Maximise and Close are Buttons named "Maximise panel" / "Restore panel" and "Close Problems panel".
- Focus entering a panel announces its name; F6 is documented in the Help menu and the CommandPalette ("Focus next panel").
- Count badges are part of the tab's name ("Problems, 3 items").
- Contrast: `on-surface-variant` 12 px titles on `surface-container-low` are 4.5:1 or better; the focus line is not the only focus cue (the title darkens too).
- Targets: 32 header buttons on pointer hosts; this component is pointer-only.
- Reduced motion: no collapse animation.

## Content
- Titles are nouns for the tool: "Explorer", "Problems", "Terminal", "Breakpoints". Sentence case, no "Panel" suffix, no ALL CAPS.
- Empty states say what is missing and how to add it: "No breakpoints. Click in the gutter to add one."
- Action names include the panel: "Close Problems panel", "Filter problems".

## e.ui today
`navigation.dock_panel` puts a `surface-variant` title bar (Label-role title, Plain "x" button) over the caller's `content` on a `surface` sheet with a `border-regular` border and `space-md` padding. To reach this design:
- Name the close button "Close <title> panel" and draw the `close` icon: today it is a literal "x" and a screen reader says "x button".
- Remove the `space-md` panel padding that insets the header from the edge; use no border (sashes separate panels) and `surface-container-low`.
- Fix the header at 32 with `label-medium` and add header actions, Maximise, and the focused state (a `focused: bool` input or focus-within tracking) with the `primary` line.
- Add the tab-group, stacked-collapsible and floating variants, and an empty-state slot.
- Make the panel a Region landmark and wire F6 focus cycling in DockLayout.
