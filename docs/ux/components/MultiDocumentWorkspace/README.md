# MultiDocumentWorkspace

A multi-document workspace is the editor area of a document app: one or more editor groups, each a DocumentTabs strip over the current document's view, with the standard shortcuts to open, switch, split, close and restore documents, and an empty state when nothing is open.

## Anatomy
1. Editor group: DocumentTabs over a view; the active group (the one with keyboard focus or the last one focused) has the `primary` line on its current tab.
2. Location bar (optional): a 24-tall breadcrumb row under the tabs (folder, file, symbol).
3. View: the current document's content, `surface`, filling the rest.
4. Group sash: 1px `outline-variant` between groups (see DockLayout).
5. Group actions: a `more-horiz` button at the strip's end (Split right, Split down, Close group, Close all).
6. Empty state: centred, "No open files", three key shortcuts and a tonal Open recent button.
7. Compact only: an app bar with the document's title and a count button that opens the document switcher.

## Variants and when to use
| Variant | Use for |
|---|---|
| Single group | The default: one strip, one view. |
| Split groups | Side-by-side or stacked comparison and reference: up to 4 groups in a grid. |
| Compact | Phones: one document at a time, the count button and a document grid (see WindowSwitcher). |
| One window per document | macOS and simple apps that prefer the system's window tabs: no workspace; each document is a window. |

Just the tab strip without groups or shortcuts is DocumentTabs. Tool panels around the workspace belong to DockLayout. A single content view with fixed sections is Tabs.

## Specs
| Part | Pointer | Touch (tablet) |
|---|---|---|
| Tab strip | DocumentTabs pointer, 40 | DocumentTabs touch, 56 |
| Location bar | 24 tall, crumbs 24 with 4 sides, 12/16 text, `on-surface-variant`, current `on-surface` 600 | hidden |
| View | `surface`, padding by content | same |
| Group sash | 1 `outline-variant`, 8 grab area, 4 `primary` on hover | 1, 24 grab area |
| Group minimum | 240 wide, 120 tall | 320 x 240 |
| Empty state | `title-medium` heading, `body-medium` `on-surface-variant` rows 240 wide with `nu-kbd` keys, gap `space-2`; `space-3` between blocks; Open recent tonal `sm` | default button size |
| Count button (compact) | | 32 outlined, `radius-sm`, `label-medium` number, 48 target |

## States
- One active group at a time; its current tab shows the line, the others show their current tab without it.
- Dirty documents: the tab dot; closing the window with dirty documents lists them in one dialog ("Save changes to 2 files?").
- Empty group: a group whose last tab closed collapses and its sash disappears; the last group shows the empty state.
- Restoring: on launch, groups, tabs, scroll positions and cursors come back; a document that no longer exists opens as a tab with an inline error in its view ("lower.e was deleted or moved") and Close / Locate actions.
- Read-only and preview tabs as in DocumentTabs.

## Behaviour
- Open: Ctrl+O, Ctrl+P (go to file, the CommandPalette's file mode), drag files into a group (the drop preview shows which group or split), or double-click the strip's empty space for a new document.
- Switch: Ctrl+Tab / Ctrl+Shift+Tab in most-recently-used order with the WindowSwitcher's document list; Ctrl+PageDown / PageUp in strip order, wrapping; Alt+1..9 picks a tab by position; Ctrl+1..4 focuses a group.
- Split: Ctrl+\ splits right with the current document; dragging a tab to a group's edge splits there.
- Close: Ctrl+W closes the current document (asking to save when dirty); Ctrl+Shift+T reopens the last closed; Ctrl+K W closes all in the group.
- Focus: pressing a view makes its group active; the view gets focus after any switch so typing continues.
- Motion: switching documents is instant (no cross-fade: it hides typing latency); a new split opens over `duration-medium-1` with `ease-emphasized-decelerate`. Reduced motion: instant.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Ctrl-based shortcuts as above; the strip can live in a custom title bar; closing the window with dirty files uses one Save dialog listing them. |
| macOS | ⌘ replaces Ctrl (⌘W, ⌘⇧T, ⌘1..9 for tabs, ⌃Tab to switch); apps that fit one-document-per-window use native window tabs instead of this workspace; unsaved documents restore silently (Resume) rather than asking at quit. |
| Linux | Ctrl-based shortcuts; GNOME apps follow `AdwTabView` behaviours (drag a tab out to a new window). |
| Android | Tablet: touch strip, split groups at `window-expanded`. Phone: compact variant; the system back gesture returns from a document to the list. |
| iOS | iPad: touch strip, up to two groups (Split View is the system's job); iPhone: compact variant with a document browser as the root. |
| Web | Do not take Ctrl+W, Ctrl+Tab, Ctrl+T or Ctrl+N from the browser: use Alt+W, Ctrl+Alt+PageUp/PageDown, and the app's own menu; warn on page unload when documents are dirty. |

## Accessibility
- The workspace is the Main landmark; each group is a Group named "Left editor group" / "Right editor group" containing its TabList and TabPanel.
- Switching documents announces the new document's name and position ("nir.e, 2 of 3, right group").
- Every shortcut is also a menu command and a palette command; none is the only way.
- The empty state's shortcuts are text, not images; the heading is a Heading level 2.
- Contrast: as DocumentTabs; the location bar's 12 px `on-surface-variant` is 4.5:1 or better on `surface`.
- Reduced motion: no split animation.

## Content
- Empty state: a plain statement ("No open files") and three actions that get the user started, each with its shortcut.
- Save prompts name the files: "Save changes to lower.e?" / "Save changes to 2 files?" with Save, Don't save, Cancel.
- Group names by position ("Left editor group"), not numbers.

## e.ui today
`navigation.multi_document_workspace` stacks `document_tabs` over the current document's `view`, with Ctrl+W closing and Ctrl+PageDown / Ctrl+PageUp picking the next and previous tab, stopping at the ends. To reach this design:
- Add editor groups (a list of groups, each with documents and a current index, and an active group) with split, focus and move shortcuts; today there is one strip.
- Wrap Ctrl+PageDown / PageUp at the ends, and add most-recently-used Ctrl+Tab with the WindowSwitcher, Alt+1..9 and Ctrl+Shift+T.
- Pass the active-group flag to `document_tabs` so the current tab's `primary` line marks the focused group.
- Add the empty state, the optional location bar and the compact variant with the count button.
- Make it the Main landmark with per-group names, and add restore-on-launch hooks (the caller keeps the model; the workspace reports scroll and cursor state).
- Map shortcuts per host (⌘ on macOS, browser-safe keys on the Web).
