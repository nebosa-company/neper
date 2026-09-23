# Flyout

A flyout is a small, light-dismiss panel of controls opened from a button (filters, a quick setting, view options); it takes focus, applies changes as they are made, and closes on Escape or a press anywhere outside.

## Anatomy
1. Anchor: the button, chip or icon button that opened it; it shows its selected state while the flyout is open.
2. Container: `surface-container`, `radius-md`, `elevation-2`, 16 padding (12 on pointer hosts). No title bar, no close button, no scrim.
3. Section labels (optional): `label-medium` in `on-surface-variant`.
4. Content: a few controls: checkboxes, switches, a slider, a segmented button.
5. Footer (optional): one quiet action at the end ("Reset"), never Apply or OK.
6. Dismiss layer: an invisible full-window layer that turns an outside press into a close.

## Variants and when to use
| Variant | Use for |
|---|---|
| Filter flyout | Narrowing a list from a toolbar: status checkboxes, "Only my builds". |
| Quick settings | Adjusting a view in place: font size, line spacing, density. |
| On compact | The same content in a modal bottom sheet (Sheet), since a small floating panel is hard to reach and dismiss by touch. |

Use Popover when the panel needs a title, a close button or actions; Menu for a list of commands; Popup when focus must stay in a field; Dialog when the change needs confirming or cannot be applied live.

## Specs
| Part | Touch | Pointer |
|---|---|---|
| Width | 240 min, 360 max | 200 min, 320 max |
| Padding | `space-4` 16 | `space-3` 12 sides and top, `space-2` 8 bottom |
| Gap between items | `space-3` 12 | `space-1` 4 (rows carry their own height) |
| Radius | `radius-md` 12 | `radius-md` 12 |
| Container | `surface-container`, `elevation-2` | same |
| Control rows | 48 | 32 (`target-pointer`) |
| Section label | `label-medium`, `on-surface-variant` | same |
| Offset | 4 from the anchor | 4 from the anchor |
| Anchor while open | selected state: `secondary-container` / `on-secondary-container` | same |

## States
- Closed / open. While open the anchor stays selected and reports Expanded.
- Controls inside take their own states; the first control shows the focus ring when the flyout was opened from the keyboard.
- A flyout whose content is loading shows a 48 circular progress centred at its final size (no resize after load).
- Nothing in a flyout is disabled for lack of a confirmation: every change is applied as it is made.

## Behaviour
- Opening: a press on the anchor, or Enter / Space / Down on a focused anchor. Pressing the anchor again closes it.
- Focus moves to the first control on open; Tab and Shift+Tab cycle inside; arrows work within composite controls (segmented button, slider).
- Dismissal: Escape, a press outside, or window deactivation close it and return focus to the anchor. The outside press is consumed; it does not also activate what was under it.
- Changes apply live and are undoable where the app supports undo; there is no Apply step and closing does not revert.
- Placement: below-start of the anchor; shifts to end-aligned when it would leave the window, flips above when there is no room below; 8 inside the window.
- Motion: opens over `duration-medium-1` with `ease-emphasized-decelerate` (fade and grow from the anchor edge); closes over `duration-short-3` with `ease-emphasized-accelerate`. Reduced motion: fade only.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | The WinUI Flyout idiom: light dismiss, pointer density, may take Acrylic; opens below a toolbar button. |
| macOS | A transient `NSPopover`-style panel without the arrow; pointer density; closes on outside click and Escape. |
| Linux | GNOME: a header-bar popover with the same content; KDE: a plain flyout. Pointer density. |
| Android | On compact, present the content as a modal bottom sheet with a drag handle; on medium and up, the flyout at touch density. |
| iOS | Compact: a sheet at the medium detent; iPad: a popover-style panel without a title. |
| Web | `role="dialog"` with `aria-label`; the anchor has `aria-expanded` and `aria-controls`; the Popover API (`popover="auto"`) gives light dismiss. Coarse pointers get the sheet on compact widths. |

## Accessibility
- Role Dialog (non-modal content, modal focus handling), named by the anchor's label ("Filter builds").
- The anchor reports Expanded and controls the flyout.
- Screen readers announce "Filter builds, dialog" and then the first control; changes are announced by the controls themselves.
- Focus is trapped while open and returns to the anchor on close.
- Contrast: labels 4.5:1 on `surface-container`; control rings (checkbox, switch) 3:1.
- Targets: 48 on touch, 32 on pointer hosts.
- Reduced motion: fade only.

## Content
- Section labels are nouns: "Status", "Line spacing". No title; the anchor's label is the title.
- Control labels are short and positive: "Only my builds", not "Don't show others' builds".
- The single footer action, if any, is a verb that resets: "Reset", "Clear filters".

## e.ui today
`overlay.flyout` places the caller's `content` in a bordered `surface` box (`radius-sm`, `elevation-2`, `space-sm` padding) against `anchor`, as a modal Dialog named `label`; Escape and an outside press fire `dismiss`. To reach this design:
- Repaint as `surface-container`, `radius-md` 12, no border, 16 or 12 padding by density.
- Put the anchor in its selected state and report Expanded and Controls on it while open.
- Consume the outside press so it does not reach the control under it, and move focus to the first control on open.
- Shift and flip at the window edges instead of only clamping.
- Present as a bottom sheet on compact touch windows (reuse `overlay.bottom_sheet` with the same content).
