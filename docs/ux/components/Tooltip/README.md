# Tooltip

A tooltip is a short, non-interactive label that appears beside a control on hover, focus or long press to name it or explain it in a few words; the rich variant adds a subhead and one action for a sentence or two of guidance.

## Anatomy
1. Container: plain is `inverse-surface`, `radius-xs`; rich is `surface-container`, `radius-md`, `elevation-2`.
2. Text: plain in `body-small`, one or two lines; rich in `body-medium`, up to four lines.
3. Shortcut (plain, optional): the command's key chord after the text, `space-2` from it.
4. Subhead (rich, optional): `title-small` in `on-surface`.
5. Action (rich, optional): one or two text buttons at the start of the row below the text.
6. Anchor: the control it describes. There is no arrow; the 4px gap and placement tie it to the anchor.

## Variants and when to use
| Variant | Container | Content | Use for |
|---|---|---|---|
| Plain | `inverse-surface`, `radius-xs` | 1-2 lines of `body-small`, optional shortcut | Naming an icon button, a truncated label, a toolbar command and its shortcut. |
| Rich | `surface-container`, `radius-md`, `elevation-2` | Subhead, up to four lines, up to two text-button actions | Explaining a setting or a feature on pointer hosts ("Incremental builds"). |

A tooltip never holds the only copy of information the user needs and never holds a form control. For anything interactive or longer use Popover; for a status that the user must see use a Snackbar or Banner; for help that stays on screen use supporting text in the field.

## Specs
| Part | Plain | Rich |
|---|---|---|
| Min height | 24 | 48 |
| Padding | 4 top and bottom, `space-2` 8 sides | `space-3` 12 top, `space-4` 16 sides, `space-2` 8 bottom |
| Max width | 200 | 312 |
| Radius | `radius-xs` 4 | `radius-md` 12 |
| Container | `inverse-surface` | `surface-container`, `elevation-2` |
| Text | `body-small` in `inverse-on-surface` | `body-medium` in `on-surface-variant` |
| Subhead | none | `title-small` in `on-surface`, `space-1` above the text |
| Shortcut | `body-small` in `inverse-on-surface`, `space-2` after the text | none |
| Actions | none | text buttons (`primary`), 40 tall, `space-2` apart, `space-2` below the text, aligned with the text's start |
| Offset | 4 from the anchor | 4 from the anchor |

Placement: plain goes above the anchor by default (below for anchors in a top bar or window title area), centred on it; rich goes below-end. Both flip to the opposite side when there is no room and are kept 8 inside the window edge.

## States
- Hidden: the default. Nothing is in the tree but the anchor's description.
- Showing: plain after 500 ms of hover, at once on keyboard focus, after a 500 ms long press on touch. Moving from one anchor to the next inside 1500 ms of the last tooltip shows the next one at once (the toolbar sweep).
- Persistent (rich only): stays while the pointer is over the anchor or the tooltip, and while focus is inside it.
- The anchor keeps its own states; the tooltip adds none to it. A disabled anchor still shows its tooltip on hover, which is how it explains why it is disabled.

## Behaviour
- Pointer: show after the 500 ms hover delay; hide 100 ms after the pointer leaves (plain) or 300 ms after it leaves both anchor and tooltip (rich). A press on the anchor hides a plain tooltip.
- Keyboard: focusing the anchor shows it; Escape hides it without moving focus; blur hides it. A rich tooltip's actions are reached with Tab from the anchor and are in the tab order only while it shows.
- Touch: long press shows the plain tooltip and hides it 1500 ms after release. Rich tooltips do not open on touch; the anchor opens a Popover instead.
- Scrolling or resizing the window hides every tooltip.
- Motion: in over `duration-short-4` with `ease-emphasized-decelerate`, fading and scaling from 80% at the anchor side; out over `duration-short-2` with `ease-emphasized-accelerate`. Reduced motion: fade only.
- Never more than one tooltip on screen.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Plain tooltip as specified; toolbar commands show their accelerator ("Open terminal Ctrl+`"). Follow the system hover time where it is exposed (`SPI_GETMOUSEHOVERTIME`). |
| macOS | Help-tag timing: 1000 ms first delay, then immediate within the sweep window. Shortcuts use glyphs (⌘⇧B). Menu bar items never get tooltips. |
| Linux | Plain tooltip as specified; GTK and KDE both use 500 ms. Shortcut in the desktop's spelling (Ctrl+Shift+B). |
| Android | Plain tooltip on long press only, 1500 ms after release; above the anchor, never over the finger. No rich tooltips. |
| iOS | No tooltip on iPhone: the icon button's accessibility label and a context menu cover it. On iPad with a pointer, show the plain tooltip on hover after 1000 ms. |
| Web | Our own element with `role="tooltip"` and `aria-describedby`, never the `title` attribute. On coarse pointers follow Android. Honour `prefers-reduced-motion`. |

## Accessibility
- Role Tooltip. The anchor is described by it (`described_by`), or named by it when the anchor is an icon button with no other label; the tooltip text and the anchor's name must not repeat each other.
- It never takes focus, except a rich tooltip's actions, which are reached by Tab from the anchor and announced as a group labelled by the subhead.
- Screen readers read the description with the anchor; the tooltip does not announce itself when it appears.
- Plain text on `inverse-surface` and rich text on `surface-container` hold 4.5:1 in every theme (7:1 in high contrast).
- The tooltip itself is not a target; presses pass through a plain tooltip to what is under it.
- WCAG 1.4.13: hoverable (the pointer can move onto it without it closing), dismissible (Escape), persistent (it stays until the user moves away).
- Reduced motion: fade only, no scale.

## Content
- Plain: a noun phrase or a verb phrase, sentence case, no trailing period, 1 to 5 words: "Rebuild project", "Open terminal". Add the shortcut, not the word "Shortcut".
- Do not restate a visible label; a tooltip on a button that says "Save" is noise.
- Rich: a subhead of 1 to 4 words, then one or two full sentences with periods. Actions start with a verb: "Learn more", "Open build settings".
- Never put error messages, status or anything the user must act on in a tooltip.

## e.ui today
`overlay.tooltip` places `text` below `anchor` on a `surface-variant` box with a border, `radius-sm`, `elevation-1`, never wrapped; `overlay.tooltip_wanted` is true while the anchor is hovered, focused or pressed. To reach this design:
- Repaint plain as `inverse-surface` / `inverse-on-surface`, `radius-xs`, no border and no shadow, `body-small`, 200 max width with wrapping to two lines.
- Place above by default with a 4px offset and flip to below; today it is always below.
- Add the delay and the sweep window to `tooltip_wanted` (show after 500 ms hover, at once on focus, on long press for touch; hide on Escape and on scroll). Today it shows on the first frame of hover and on press, which flashes it on every click.
- Set the anchor's `described_by` to the tooltip inside the function instead of leaving it to the caller.
- Add an optional shortcut string, and a `overlay.rich_tooltip` with subhead, body and up to two actions that stays while hovered.
