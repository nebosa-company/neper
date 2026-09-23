# Popover

A popover is a titled floating panel tied to one control, with a close button and a beak pointing at its anchor, for details or a short task about that control (a build's status, a person's card, a quick edit) without leaving the page.

## Anatomy
1. Anchor: the control it explains; it shows its focus or selected state while the popover is open.
2. Beak: a 12 square rotated 45°, the container's colour, centred on the anchor along the near edge, 16 in from any corner.
3. Container: `surface-container-high`, `radius-md`, `elevation-3`, 16 padding.
4. Header: the title in `title-medium`, and a Close icon button at the end.
5. Body: `body-medium` text in `on-surface-variant`, key-value pairs, or a few controls.
6. Actions (optional): up to two buttons at the end, the main one tonal, the other text.

## Variants and when to use
| Variant | Use for |
|---|---|
| Details | Read-mostly information about the anchor: a build's result, a commit, a person. May carry one or two actions. |
| Short task | A tiny form about the anchor: rename a tag, set a due date. The tonal action commits; Close cancels. |
| On compact | The same content as a sheet at half height (Sheet), with the drag handle and title; no beak. |

Use Flyout when no title or close button is needed and changes apply live; Tooltip or rich Tooltip for read-only help that should not take focus; Dialog when the task is not about one control or must block the page; Menu for commands.

## Specs
| Part | Value |
|---|---|
| Width | 320 default; 240 min, 400 max |
| Padding | `space-4` 16 sides and top, `space-3` 12 bottom |
| Gap between blocks | `space-3` 12 |
| Radius | `radius-md` 12 |
| Container | `surface-container-high`, `elevation-3` |
| Beak | 12 by 12, rotated 45°, `radius` 2, `surface-container-high`; 6 of it outside the edge |
| Offset | beak tip 4 from the anchor (10 from container edge to anchor) |
| Title | `title-medium` in `on-surface`, up to two lines |
| Close | icon button 40 (32 on pointer hosts), `close` icon in `on-surface-variant`, end of the header |
| Body text | `body-medium` in `on-surface-variant` |
| Key-value rows | key `body-medium` `on-surface-variant`, value `body-medium` `on-surface`, `space-4` column gap, `space-1` row gap |
| Actions | end-aligned, `space-2` apart; the main action tonal, the other text |

## States
- Open: focus on the Close button for a details popover, or on the first field for a short task.
- Anchor: keeps its selected state (and focus ring when keyboard-opened) while open.
- Busy: after the main action, it shows its loading state; the popover closes on success and shows an inline error on failure.
- Buttons and fields inside take their own states.

## Behaviour
- Opening: a press on the anchor, or Enter / Space on it. Hover never opens a popover (use a rich tooltip for hover).
- Keyboard: Tab cycles inside (focus is trapped); Escape closes; Enter in a short task presses the main action.
- Dismissal: the Close button, Escape, a press outside or pressing the anchor again. An outside press is consumed. A short task with unsaved input stays open on an outside press and closes only through Close or Escape.
- Focus returns to the anchor on close.
- Placement: below the anchor, then above, then end, then start, whichever fits first; the beak moves along the edge to stay on the anchor. 8 inside the window. It follows the anchor on scroll and closes when the anchor leaves the view.
- Motion: in over `duration-medium-1` with `ease-emphasized-decelerate`, scaling from 90% with the beak as origin; out over `duration-short-3` with `ease-emphasized-accelerate`. Reduced motion: fade only.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | As specified, pointer density (32 close button); may take Acrylic. WinUI TeachingTip conventions for the beak. |
| macOS | The `NSPopover` idiom: a beak, transient behaviour (closes on outside click); a popover can be torn off into a panel only if the app supports it. |
| Linux | GNOME: a `GtkPopover` with its arrow; KDE: the same panel. Pointer density. |
| Android | No popovers on compact: present as a modal bottom sheet; on medium and up, as specified at touch density. |
| iOS | iPhone: adapts to a sheet at the medium detent with a Close button; iPad: native popover with its arrow, dismissed by a tap outside. |
| Web | `role="dialog"` with `aria-labelledby` the title and `aria-modal="false"`; the Popover API (`popover="auto"`) plus anchor positioning where supported. |

## Accessibility
- Role Dialog, labelled by the title (`labelled_by`) and described by the body text; the title is a Heading level 2.
- The anchor reports HasPopup Dialog and Expanded, and controls the popover.
- The Close button is an icon button named "Close", not a glyph.
- Screen readers announce the title and the description on open.
- Focus is trapped while open and returns to the anchor on close.
- Contrast: title and values 4.5:1 on `surface-container-high`; the beak is decorative.
- Targets: 48 on touch (the close button pads to it), 32 on pointer hosts.
- Reduced motion: fade only.

## Content
- Title: what the anchor is, with its state: "Build 4128 failed", "Ada Park". Sentence case, no period.
- Body: one or two sentences with the specifics, then key-value rows for facts. Keys are nouns ("Branch", "Started by").
- Actions: verbs about the anchor: "View log", "Rerun". Never "OK"; Close is the dismissal.

## e.ui today
`overlay.popover` places a column of a title row (the title and a Plain button labelled `x`) and the caller's `content` on a bordered `surface` box (`radius-sm`, `elevation-2`) against `anchor`, as a modal Dialog named `title`. To reach this design:
- Replace the `x` Plain button with an icon button showing the `close` icon and named "Close"; today a screen reader says "x".
- Set `labelled_by` to the title heading (`key + 1`) and drop the heading to level 2.
- Repaint as `surface-container-high`, `radius-md` 12, `elevation-3`, no border, 16 padding, `title-medium` title; draw the beak and keep it on the anchor.
- Add optional actions (tonal plus text) and a busy state; keep a dirty short task open on an outside press.
- Choose the side that fits (below, above, end, start) and present as a sheet on compact touch windows.
