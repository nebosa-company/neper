# Dialog

A dialog is a modal window over a scrim that asks for a decision or a short piece of input the user must deal with before going on; the alert variant interrupts to confirm a consequential action.

## Anatomy
1. Scrim: `scrim` at `scrim-opacity` 32% over the whole window.
2. Container: `surface-container-high`, `radius-xl`, `elevation-3`, 24 padding.
3. Icon (optional): 24 icon in a 40 well, centred above the title; the well takes the tone of the consequence (`error-container` for delete, `secondary-container` otherwise).
4. Title: `headline-small`, start-aligned, or centred when there is an icon.
5. Content: `body-medium` text in `on-surface-variant`, or form controls, or a list.
6. Dividers (scrolling content only): `outline-variant`, full bleed, shown only while the content is scrolled away from that edge.
7. Actions: a row at the end; the default action a filled button, the others text buttons, `space-2` apart. A third, dismissive action ("Don't save") sits at the start.

## Variants and when to use
| Variant | Use for |
|---|---|
| Basic | A short task or choice with a title: rename, choose a branch, confirm settings. |
| With icon | A consequential confirmation that benefits from a glance: delete, sign out, overwrite. Centred title. |
| Alert | An interruption that needs an answer now: unsaved changes, a failed save. Role `alertdialog`; the title may be omitted when the message is one question. |
| Full-screen | A multi-field task on compact windows (under `window-medium` 600): new task, edit profile. A top bar with Close, the title and a Save text button replaces the action row. From 600 up the same content is a basic dialog. |

Do not use a dialog for information that needs no answer (use a Snackbar or Banner), for a long task beside the page (Sheet), or for content about one control (Popover). Never open a dialog from a dialog; replace it or use a full-screen flow.

## Specs
| Part | Value |
|---|---|
| Width | 280 min, 560 max; 312 default for text, 360 for a form |
| Max height | window height minus 48 top and bottom; content scrolls beyond it |
| Padding | `space-6` 24 all round |
| Gap between blocks | `space-4` 16 |
| Radius | `radius-xl` 28 |
| Container | `surface-container-high`, `elevation-3` |
| Icon | `icon-md` 24 in a 40 well (`secondary-container` / `on-secondary-container`, or `error-container` / `on-error-container`) |
| Title | `headline-small` in `on-surface` |
| Text | `body-medium` in `on-surface-variant`; an alert's lead question in `body-large` `on-surface` |
| Actions | `control-md` 40 buttons (32 on pointer hosts), `space-2` apart, `space-2` above the row |
| Full-screen top bar | 56 tall, Close icon button, `title-large` title, Save text button; content 16 side padding |
| Scrim | `scrim` at 32% |

## States
- Open: the scrim and container present; focus on the first focusable control, or on the default action when there is nothing to fill in; on a destructive confirmation, focus goes to Cancel.
- Content scrolled: dividers appear above and below the scroll area.
- Default action disabled until the input is valid (Rename with an empty name); prefer inline validation that says why.
- Busy: after the default action is pressed and the work takes more than 300 ms, the action shows its loading state and the other actions disable; the dialog stays until the work succeeds or fails, and a failure shows as field or banner error inside it.
- Buttons take their own states (hover, focus ring, pressed, disabled) as Button specifies.

## Behaviour
- Modal: the rest of the window is inert and hidden from assistive technology; focus is trapped and Tab cycles inside the dialog.
- Enter presses the default action when focus is not in a multi-line field; Escape presses Cancel (or closes, when there is no Cancel). A dialog always has a way out: an alert with only destructive answers is not allowed.
- A press on the scrim closes a basic dialog as Cancel; it does nothing on an alert or while input has changed (it would lose work).
- On Android, system back acts as Cancel, with the predictive-back preview shrinking the dialog.
- Closing returns focus to the control that opened it.
- Motion: enter over `duration-medium-4` with `ease-emphasized-decelerate` (fade in the scrim, scale the container from 90%, grow the height from the top); leave over `duration-short-4` with `ease-emphasized-accelerate` (fade). Full-screen dialogs slide up from the bottom. Reduced motion: cross-fade only.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | ContentDialog order: the default (filled) action first, then the others, then Cancel last, right-aligned; buttons 32 tall. Access keys on the buttons; Enter default, Escape cancel. |
| macOS | Document-modal questions attach to the window as a sheet sliding from the title bar; app-modal alerts use the native alert (icon, bold message, informative text). Default action last (rightmost), Escape and ⌘. cancel, "Don't save" at the start. |
| Linux | GNOME (libadwaita) alert: centred heading and body, affirmative last; KDE: follow its button order (affirmative first). 32 tall buttons. |
| Android | As specified; full-screen on compact; system back is Cancel; alerts are basic dialogs with role alertdialog. |
| iOS | Alerts use the native alert (`UIAlertController.alert`): centred title and message, up to two side-by-side actions (Cancel at the start, the default bold), more stack vertically. Forms use a page sheet with Cancel and Done in its navigation bar rather than a dialog. |
| Web | A `<dialog>` element opened with `showModal()`, or `role="dialog"` / `role="alertdialog"` with `aria-modal="true"`; the page behind is `inert`. |

## Accessibility
- Role Dialog (or AlertDialog) with the Modal state, labelled by the title and described by the text (`labelled_by`, `described_by`). An untitled alert is labelled by its question.
- The title is a Heading level 2 (the window keeps level 1).
- Screen readers announce the role, the title and the description on open; an alert also plays the host's alert sound where it has one.
- Focus: into the dialog on open, trapped while open, back to the opener on close.
- Contrast: title and text 4.5:1 on `surface-container-high`; the scrim is decorative and needs none.
- Targets: 48 on touch (the 40 buttons pad to it), 32 on pointer hosts.
- Reduced motion: cross-fade, no scale.

## Content
- Title: a question or a statement of the task, sentence case, no period, ideally under 40 characters: "Delete 3 files?", "Rename project".
- Text: say what will happen, with the specifics ("build.log, cache.bin and out.em will be deleted"); one or two sentences with periods. Don't repeat the title.
- Actions: verbs that name the outcome and match the title ("Delete", "Rename", "Set default"), never "OK" / "Yes" / "No". Cancel is always "Cancel".
- Put the dismissive third option in words ("Don't save"), not "No".

## e.ui today
`overlay.dialog` centres a `surface` card with a border, `radius-md` and `elevation-3`, holding the title (Title role), the content and a button row; `overlay.alert_dialog` puts a `message` in it. `DialogButton.kind` is `Plain`, `Default`, `Cancel` or `Destructive`. To reach this design:
- Paint a scrim at 32% behind the dialog; today the page behind is painted as it is.
- Repaint the card as `surface-container-high`, `radius-xl` 28, 24 padding, no border, `headline-small` title; `Plain` and `Cancel` become text buttons (not Outlined), `Destructive` a filled `error` button.
- Announce `alert_dialog` with role AlertDialog, not Dialog.
- Make Escape and a scrim press close a dialog that has no `Cancel` button (they do nothing today), and never close an alert on a scrim press.
- Add an optional icon, scroll dividers, the busy state, and a full-screen presentation below 600 wide.
- Order the buttons by host (Windows default-first, macOS/GNOME affirmative-last) instead of by array order; drop the title to Heading level 2.
