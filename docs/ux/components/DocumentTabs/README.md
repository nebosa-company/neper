# DocumentTabs

Document tabs are the strip of open documents above an editor group: one tab per document, the current one joined to the editor below, each closable, reorderable and marked when it has unsaved changes.

## Anatomy
1. Strip: full-bleed, 40 tall (pointer), `surface-container`.
2. Tab: 36 tall with `radius-sm` top corners; file-type icon (18), title, close slot.
3. Current tab: filled with the editor's `surface`, so it reads as the top of the document; in the active group a 2px `primary` line runs along its top edge.
4. Close slot: a 24 round close button (`close` at 16); holds an 8px unsaved dot instead when the document is dirty and the tab is not hovered.
5. Pinned tab: icon only, at the start, no close button.
6. Preview tab (optional): a tab opened by single-click browsing, title in italics, replaced by the next preview.
7. End controls: Show all open files (`chevron-down`), and on touch New document (`add`).
8. Drop indicator: a 2 x 28 `primary` line between tabs while one is dragged.

## Variants and when to use
| Variant | Use for |
|---|---|
| Pointer strip (40) | Editors and document apps on desktop hosts: code, text, spreadsheets, design files. |
| Touch strip (56) | Tablets and touch Web at `window-medium` and up: 48 tabs, close always visible. |
| Compact | Phones: no strip. The app bar shows the current document's title and a count button ("3") that opens a grid of open documents (see WindowSwitcher's document form). |

Fixed places in an app (Home, Builds, Settings) are a DestinationBar or Tabs, not document tabs: they cannot be closed. Switching among many open documents by keyboard is the WindowSwitcher; the whole editor area with groups and shortcuts is MultiDocumentWorkspace.

## Specs
| Part | Pointer | Touch |
|---|---|---|
| Strip height, padding | `control-md` 40, `space-1` 4 sides; tabs bottom-aligned | 56, 4 sides |
| Tab height | 36 | `control-lg` 48 |
| Tab width | min 96, max 220, shrink to fit then scroll | min 120, max 240 |
| Tab padding and gap | `space-3` 12 start, `space-1` 4 end, `space-2` 8 inner gap; 2 between tabs | 16 start, 4 end |
| Tab shape | `radius-sm` top corners, square bottom | same |
| Title | 13/20 (`body-medium` at 13), one line, ellipsis | `body-medium` 14/20 |
| Icon | 18, `on-surface-variant`; current `on-surface` | 24 |
| Close button | `control-xs` 24 round, 16 icon | `control-md` 40 round, 24 icon |
| Unsaved dot | 8, the title colour | same |
| Rest tab | transparent, `on-surface-variant` | same |
| Current tab | `surface` fill, `on-surface` title | same |
| Active group line | 2 `primary`, top edge of the current tab | same |
| Hover | `state-hover` layer | pressed only |
| Dragged | `surface-container-highest`, `elevation-2`, lifted 2 | same |
| Drop line | 2 x 28 `primary`, `radius-full` | same |

## States
- Rest, hover (close appears), focus (ring inset 3px; the tab is edge-to-edge in the strip), pressed, current, current in the active group.
- Unsaved: the dot replaces the close button until hover or focus, then the close button shows; closing asks to save.
- Preview: italic title; becomes a normal tab on edit, double-click or pin.
- Pinned: icon only, first; unpinning restores the full tab after the pinned ones.
- Dragged: lifted, following the pointer horizontally; the others slide apart to open the gap.
- Overflowed: tabs shrink to the minimum, then the strip scrolls horizontally with the current tab kept in view; Show all open files lists every tab.
- Read-only document: a 16 `visibility` icon after the title with the word in its tooltip ("Read only").

## Behaviour
- Press a tab to make it current; middle-click closes it; double-click on the strip's empty space opens a new document.
- Close: the close button, Ctrl+W (⌘W), or middle-click. Closing the current tab selects the tab that was current before it (most-recently-used), not simply the neighbour. Closing a dirty tab asks "Save changes to lower.e?" (Save, Don't save, Cancel).
- Keyboard: the strip is one Tab stop; Left/Right move focus between tabs, Home/End to the ends, Enter or Space selects, Delete closes the focused tab. Ctrl+Tab and Ctrl+Shift+Tab switch in most-recently-used order (with the WindowSwitcher); Ctrl+PageDown and Ctrl+PageUp switch in strip order, wrapping. Ctrl+Shift+PageDown and PageUp move the tab.
- Drag to reorder after 4 px of movement; drag out of the strip into another group or out of the window to split or tear off (see DockLayout). Pinned tabs reorder only among pinned tabs.
- Context menu on a tab: Close, Close others, Close to the right, Close saved, Pin, Copy path, Reveal in file explorer, Split right.
- Scrolling the wheel over the strip scrolls it horizontally.
- Motion: tabs slide apart for a drop over `duration-short-4` with `ease-standard`; a new tab expands from zero width with `ease-emphasized-decelerate` over `duration-short-4`; a closed one collapses with `ease-emphasized-accelerate` over `duration-short-3`. Reduced motion: no width animation, instant reflow.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer strip; tabs can merge into the title bar in a custom-chrome window (the strip becomes the caption area, drag its empty space to move the window, leave 46 for each caption button). Ctrl+W, Ctrl+Tab. |
| macOS | Pointer strip; ⌘W closes, ⌃Tab and ⇧⌘] / ⇧⌘[ switch; native window tabs (the system tab bar under the title bar) may replace the strip for one-document-per-window apps. |
| Linux | Pointer strip; GNOME apps use the `AdwTabBar` look (tabs spread evenly, close on hover); follow it in GNOME. |
| Android | Touch strip on tablets; compact form on phones. |
| iOS | Touch strip on iPad (the document tab bar, like Safari's); compact form on iPhone. |
| Web | Pointer or touch by input; do not take Ctrl+W or Ctrl+Tab from the browser: use Alt+W and Ctrl+Alt+PageDown/PageUp, or the app's own shortcuts. `role="tablist"` with roving tabindex. |

## Accessibility
- Role TabList named for the group ("Open files", "Open files, right group"); each tab is a Tab with Selected, a position ("2 of 5") and a name that includes its state: "lower.e, unsaved changes", "neper.json, pinned".
- The close button is a Button named "Close lower.e"; it is reachable by Delete on the tab rather than as a separate Tab stop.
- The current tab controls the editor below (`controls`), which is a TabPanel.
- Status is never colour alone: unsaved is a dot plus the name suffix; the active group is a line plus the group's name.
- Contrast: `on-surface-variant` titles on `surface-container` and `on-surface` on `surface` are 4.5:1 or better.
- Targets: 36 x 96 tabs and 24 close buttons on pointer (the close stays within the tab's 36 row); 48 tabs and 40 close buttons on touch.
- Reduced motion: no slide or width animation.

## Content
- Tab titles are the document's name exactly ("lower.e", "Q3 roadmap"); when two open documents share a name, add the shortest distinguishing parent in `on-surface-variant` after it ("main.e  src", "main.e  tests").
- No "Untitled" numbering beyond "Untitled 1", "Untitled 2"; rename on first save.
- No ALL CAPS, no trailing asterisk for unsaved: use the dot.

## e.ui today
`navigation.document_tabs` draws one square tab per `Document` on a `surface-variant` strip, the current one `primary` mixed 50% toward selection with an `on-primary` title, a dirty title prefixed "* ", and a Plain "x" close button on tabs that are not pinned. To reach this design:
- Draw the current tab as the editor's `surface` with `on-surface` text and the 2px `primary` top line only in the active group (add an `active: bool` input), not a `primary` fill; this also fixes the low-contrast Plain "x" on the current tab.
- Replace the "x" text with the `close` icon button named "Close <title>", and the "* " prefix (the comment promised a dot) with the unsaved dot plus "unsaved changes" in the name.
- Give every tab the same 36 height: today a close button makes a tab 40 and a pinned tab stays 32.
- Round the top corners (`radius-sm`), draw hover, focus (inset ring) and dragged states, and the drop line; `DocumentMove` already carries the move.
- Add preview tabs, pinned icon-only rendering, overflow scrolling with Show all open files, and the tab context menu; lift the 64-document cap to a scrolling strip.
- Add Home, End and Delete to the existing Left/Right handling, and most-recently-used order for Ctrl+Tab.
