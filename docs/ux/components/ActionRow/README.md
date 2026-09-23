# ActionRow

An action row lays out the buttons that finish or act on a region (a dialog, a card, a form, a pane) in one consistent order, spacing and overflow, so every footer in an app reads the same way.

## Anatomy
1. Row: no container of its own; it takes its parent's surface.
2. Main action: at most one filled (or tonal) button, always last in reading order.
3. Secondary actions: outlined or text buttons before it, 8 apart.
4. Leading action (optional): one quiet text button pinned to the start ("Save as draft", "Learn more"), separated by the free space.
5. More (optional): an icon button (`more-vert`) at the end of the secondary run that opens a menu of the actions that did not fit.

## Variants and when to use
| Variant | Layout | Use for |
|---|---|---|
| Footer (end-aligned) | secondaries then the main action at the end | Dialogs, forms, wizards, sheets, cards. The default. |
| Split footer | a leading text button at the start, the rest at the end | A footer with a side exit that is not Cancel: "Save as draft", "Skip". |
| Inline (start-aligned) | buttons from the start | Actions that follow content: under a banner's text, after a card's body, in an empty state. |
| Stacked | full-width, one per line, main action first | Compact width on touch hosts when two labels do not fit side by side (under 360 of row width, or any label longer than 20 characters). |
| With overflow | as footer, extra actions in More | Rows whose actions exceed the width; also any row of more than three actions. |

Icon-only commands acting on a view are a Toolbar. Actions on a whole screen belong in the AppBar. A choice among options is a SegmentedButton, not a row of buttons.

## Specs
| Part | Touch (default) | Pointer (density -1) | Dense (-2) |
|---|---|---|---|
| Button height | `control-md` 40, target padded to 48 | `control-sm` 32 | `control-xs` 24 (tool panes only, text buttons) |
| Gap between buttons | `space-2` 8 | `space-2` 8 | `space-1` 4 |
| Gap before a leading action | free space, min `space-6` 24 | same | same |
| Row inset in a dialog | `space-6` 24 sides, `space-6` bottom, `space-2` above | `space-6` / `space-4` | |
| Row inset in a card | `space-4` 16 | `space-4` | |
| Stacked gap | `space-2` 8, each button 100% wide | | |
| More | icon button 40 (32 pointer), menu below-end, `nu-menu`, items 48 / 32 | | |
| Loading | 18 circular progress in the label colour replaces the icon; width kept | same | |

Colours come from the buttons themselves (see Button); the row adds none.

## States
- Default: all enabled, the main action filled.
- Running: the pressed action shows its progress ring and the label turns into the present participle ("Deploying"); the other actions stay enabled unless they conflict (then disabled for the duration).
- Unavailable: a disabled button (on-surface 12% / 38%). Prefer keeping the main action enabled and explaining what is missing when pressed.
- Overflowed: More shows; its menu keeps the hidden actions' order and icons. A destructive action in the menu is last, after a separator, in `error`.
- Focus: moves through the row in reading order; each button shows its own ring.

## Behaviour
- Order is fixed in reading order: leading, secondaries, main. In right-to-left layouts the whole row mirrors.
- Overflow collapses from the least important end (the action just before the main one moves last into More first); the main action never collapses.
- Tab moves between buttons; the row adds no arrow-key navigation. Enter in a dialog presses the main action when focus is not on another button; Escape presses Cancel.
- Stacking happens by width, not by host: a row re-lays itself when its container crosses the threshold, with no animation.
- Pressing a running action again does nothing; it is not a toggle.
- Motion: More's menu opens with `ease-emphasized-decelerate` over `duration-medium-1` and closes with `ease-emphasized-accelerate` over `duration-short-3`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer density. The main (default) action is first of the pair in system dialogs but this system keeps it last for consistency across hosts, except in native message boxes. Access keys: underline on Alt. |
| macOS | Pointer density. Main action last (rightmost) and the default; Cancel immediately before it; a destructive main action is never the default. A leading "Help" or "Learn more" button sits at the far start. |
| Linux | Pointer density. GNOME: main action last; KDE: follow the desktop's button order setting (KDE puts the affirmative first). |
| Android | Default size; footer end-aligned; stacked at compact width with the main action first. |
| iOS | Default size with 44pt targets; alert-style pairs sit side by side with Cancel first; stacked lists put Cancel at the bottom, separated. |
| Web | Default size on touch, pointer density at `window-expanded`; real `<button>`s; the row is a plain `div`, not a toolbar. |

## Accessibility
- The row is not a landmark and has no role of its own; each button is a Button named by its label. A row of three or more related actions in a pane may be a Group named by its purpose ("Build actions").
- More is named "More actions", reports Has popup = menu and Expanded while open.
- A running action reports Busy and its new label ("Deploying"); completion is announced by the snackbar that follows, not by the button.
- Contrast and targets come from Button: 4.5:1 labels, 48 targets on touch, 32 on pointer.
- Reduced motion: the menu cross-fades.

## Content
- Verbs that name the outcome: "Publish release", "Download logs", not "OK", "Submit", "Yes".
- The main action repeats the dialog's question verb: "Delete 3 files?" is answered by "Delete".
- Cancel is always "Cancel"; a leading exit says what it keeps: "Save as draft".
- Sentence case, no trailing punctuation, 1-3 words.

## e.ui today
`navigation.action_row` lays out `navigation.action_button`s of one `style.ControlVariant` from the start with a `space-xs` (4) gap, and `action_button` picks `control.icon_button` when an icon is set. To reach this design:
- Take a variant per action (main filled, secondaries outlined or text) instead of one variant for the whole row.
- Add alignment (end by default, start, split with a leading slot) and the 8 gap; the 4 gap today crowds 40-tall buttons.
- Add width-driven overflow into an `overlay.menu_button` More, and stacking under 360.
- Add a running state per action (the progress ring and busy semantics).
- Tint action icons: today an `action_button` icon is drawn untinted, so it ignores the label colour and theme.
- Keep the items alive past the frame as today; key the More button and its menu items after the buttons (`key + items.len` onwards).
