# SpeedDial

A speed dial (FAB menu) opens two to six related creation actions from a floating action button, for a screen whose main job is to make one of a few kinds of thing.

## Anatomy
1. FAB: the closed state, a standard FAB (`primary-container`, `radius-lg`, 56, `elevation-3`) with `add` or the category's icon.
2. Close button: while open, the FAB turns into a 56 `primary` circle holding `close`.
3. Action items: pills 56 tall, `primary-container`, `radius-full`, `elevation-2`, icon then label, stacked above the FAB and end-aligned, 4 apart.
4. Scrim: `scrim` at `scrim-opacity` over the content, on compact windows only.

## Variants and when to use
| Variant | Items | Use for |
|---|---|---|
| Primary (default) | `primary-container` / `on-primary-container` | The screen's creation actions: New project, Import, Upload. |
| Tonal | `secondary-container` / `on-secondary-container` | When the screen already has strong primary colour. |
| With scrim | compact windows | Phones, where the items cover content. |
| Without scrim | medium and up | Tablets and desktop, where the items sit in free space. |

Use a single FAB when there is one creation action, an extended FAB or a Split button when one action leads, and a Menu for more than six items or actions that are not about creating. On desktop with a toolbar, prefer a "New" split button over a floating control.

## Specs
| Part | Value |
|---|---|
| FAB | `control-xl` 56, `radius-lg` 16, `primary-container`, `elevation-3`; 16 from the window's bottom and end edges (24 on medium and up) |
| Close button | 56, `radius-full`, `primary` / `on-primary`, `elevation-3` |
| Items | height `control-xl` 56, padding `space-4` 16 start, `space-6` 24 end, icon `icon-md` 24, gap `space-2` 8, `title-medium` label |
| Item colours | `primary-container` / `on-primary-container`, `elevation-2` |
| Item spacing | `space-1` 4 apart; `space-2` 8 above the close button |
| Alignment | end-aligned to the FAB's end edge; items grow toward the start |
| Scrim | `scrim` at `scrim-opacity` 0.32, compact only |
| Count | 2 to 6 items |

## States
- FAB: rest `elevation-3`, hover `elevation-4` + `state-hover`, focus ring, pressed `state-pressed`.
- Items: hover `state-hover`, focus `state-focus` + ring 2px outside, pressed `state-pressed`.
- Open: close button replaces the FAB; the FAB's icon rotates to `close` as it morphs.
- Disabled item: remove it instead; a speed dial never shows a disabled action.

## Behaviour
- Pressing the FAB opens; pressing the close button, the scrim, Escape or system back closes and returns focus to the FAB. Picking an item runs it and closes.
- Opening moves focus to the first item (the one nearest the FAB); Up/Down move between items and the close button, Home/End jump, Tab cycles inside while open.
- Items enter from the FAB, staggered `duration-stagger` (30 ms) apart bottom to top, each over `duration-medium-1` with `ease-emphasized-decelerate`; the FAB morphs to the circle over `duration-medium-2` with `ease-standard`. Closing reverses with `ease-emphasized-accelerate` in `duration-short-4`.
- The FAB hides on scroll down and returns on scroll up (compact only); an open speed dial closes on scroll.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Rare: prefer a "New" split button in the command bar. If used, no scrim, pointer hover lifts items. |
| macOS | Not used for window content; put these actions in the toolbar and the File menu (File > New Project, Import, Upload). |
| Linux | Not used on GNOME/KDE desktop; use a header-bar split button. Allowed on Linux phones (Phosh, Plasma Mobile) as on Android. |
| Android | The native pattern: scrim on compact, predictive back closes it. 48 targets are met by the 56 items. |
| iOS | Use a toolbar "+" button with a UIMenu instead; the speed dial is not an iOS idiom. |
| Web | Allowed on compact touch layouts; on pointer layouts render the "New" split button. The FAB is a `button` with `aria-haspopup="menu"`. |

## Accessibility
- FAB: role button, name = what it creates ("Create"), has-popup menu, expanded state. Close button: name "Close".
- The items are a menu named by the FAB; each a menu item with its label.
- Focus is trapped in the open speed dial and returned to the FAB on close.
- Announce "Create menu, 3 items" on open.
- Item label contrast meets 4.5:1 on `primary-container`; targets are 56.
- Reduced motion: items fade in together over 100ms, no stagger and no morph.

## Content
Each item is a verb and a noun: "New project", "Import repository", "Upload folder". Two or three words, sentence case. Every item has a label; icons alone are not enough.

## e.ui today
`control.speed_dial` draws a pill-shaped Filled head with a text label, and while open, Filled `button`s in a column above it inside a modal overlay; the head offers Expand even while open. To reach this design:
- Make the head a FAB (`primary-container`, 56, `radius-lg`, `elevation-3`, icon) that morphs into a round `primary` close button while open.
- Draw items as 56 `primary-container` pills with icon and `title-medium` label, end-aligned, 4 apart, `elevation-2`.
- Add the scrim on compact windows only, and the staggered enter and exit motion.
- Offer Collapse while open, move focus to the first item on open and back to the FAB on close; publish the items as a menu.
- Hide on scroll down on compact.
