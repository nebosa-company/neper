# Wizard

A wizard walks the user through a task in a fixed order of steps (create a project, import data, set up an account), showing where they are, validating each step before the next, and letting them go back without losing what they entered.

## Anatomy
1. Title: the task, `headline-small`.
2. Progress: a horizontal stepper (expanded), a vertical stepper (a side column in wide dialogs), or "Step 2 of 4: Build" with a linear progress bar (compact).
3. Step marker: a 24 circle with the step's number; a check when done; the `error` icon when the step needs attention.
4. Step label: `body-medium`, the current one at 600; an optional second line (`body-small`) for "Optional" or the problem.
5. Connector: 1px `outline-variant`, 2px `primary` once the step before it is done.
6. Content: the current step's fields and text.
7. Footer: Cancel at the start, Back and Next (Finish on the last step) at the end (an ActionRow, split).

## Variants and when to use
| Variant | Use for |
|---|---|
| Horizontal stepper | 3-5 steps with short labels, in a page or a large dialog at `window-medium` and up. |
| Vertical stepper | 5-7 steps, or labels too long for one row; the steps as a column at the start of a dialog or page (installers, setup). |
| Compact | Under 600: full-screen, "Step 2 of 4: Build" with a progress bar, Next full-width at the bottom, Back through the app bar or the system back. |
| Non-linear | Any step can be visited in any order once the first is done (settings-like setups): steps become pressable. |

A task that fits one screen is a Dialog or a Form; do not split it to look simpler. Free navigation between sections is Tabs or a NavigationStack. Onboarding tours with no input are a Carousel.

## Specs
| Part | Expanded | Compact |
|---|---|---|
| Container | page `surface`, or a dialog: `surface-container-high`, `radius-xl`, 560-720 wide | full screen, `surface` |
| Title | `headline-small`, 24 sides, 20 top | app bar `title-large` with Close |
| Stepper padding | `space-6` 24 sides, `space-4` 16 vertical | |
| Marker | 24 circle, `label-medium` 12/16 600; upcoming 1 `outline` ring, `on-surface-variant`; current and done `primary` fill, `on-primary` content | |
| Error marker | `error` icon 24, `error`; label `on-surface`, second line `error` | |
| Label | `body-medium` 14/20, upcoming `on-surface-variant`, current `on-surface` 600, done `on-surface`; 8 after the marker | "Step 2 of 4: Build" `label-medium` `on-surface-variant` |
| Connector | flex, min 16, 1 `outline-variant`; done 2 `primary`; 8 gap each side, centred on the marker | progress bar 4, `primary` on `secondary-container` |
| Content | 24 sides, 8 top; fields 12 apart | 16 sides |
| Footer | 24 sides, 16 vertical; Cancel text button at the start; Back outlined, Next filled at the end, 8 apart | Next full-width `control-md` (48 target), 16 sides and bottom |
| Pointer density | buttons `control-sm` 32, fields dense 40 | |

## States
- Step: upcoming, current, done, needs attention (error), optional, disabled (not yet reachable in a linear wizard: not pressable, same look as upcoming).
- Next: enabled when the step is valid; if the user presses it while invalid, focus moves to the first invalid field and its message appears (preferred over a disabled Next, which gives no reason).
- Back: hidden on the first step (not disabled), so Next and Cancel keep their places.
- Last step: Next becomes Finish (or the task's verb: "Create project"); while finishing, it shows its progress ring and the other buttons disable.
- Done: the wizard closes and a snackbar confirms, or a final page summarises with one action ("Open project").

## Behaviour
- Next validates the step, then advances; Back never validates and keeps the entered values. Enter in the last field presses Next; Escape (or Close) cancels, asking first if anything was entered ("Discard new project?").
- Pressing a done step (or a reachable step in a non-linear wizard) jumps to it; Tab reaches the stepper's pressable steps, arrow keys move between them.
- On each step change focus moves to the step's heading (or first field) and the step is announced.
- Going back and changing an earlier answer that invalidates later steps marks them "Needs review" (the error marker) rather than clearing them.
- The step count is fixed once the wizard starts; conditional steps appear from the start as optional or are merged into an existing step.
- Motion: content slides 8% and fades in the direction of travel (forward: from the end) with `ease-emphasized-decelerate` over `duration-medium-1`; the connector fills with `ease-standard` over `duration-medium-2`; the progress bar advances with `ease-standard` over `duration-medium-2`. Reduced motion: cross-fade, no slide.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer density; dialog wizard with Back / Next / Cancel as in Windows setup conventions (Cancel at the end is also accepted, keep this system's split footer inside the app); Alt+B / Alt+N access keys. |
| macOS | Pointer density; the Installer / Setup Assistant convention: a vertical step list at the start ("Introduction, License, Destination...") and Go Back / Continue at the bottom end; the last button says what it does ("Install", "Create"). |
| Linux | Pointer density; GNOME prefers a carousel of pages with the header bar holding Back and Next at the ends; KDE uses the dialog footer as here. |
| Android | Compact variant; system back goes to the previous step before leaving the wizard. |
| iOS | Compact variant as a pushed stack in a sheet: Next in the navigation bar's end (or a bottom button), Back is the navigation bar's back; swipe down dismisses only after confirming. |
| Web | Each step may be a URL segment so the browser's Back works; warn before unload when there is entered data. |

## Accessibility
- The stepper is an ordered List; the current step reports Current = step; done steps add "completed" and error steps "needs attention: fix 1 field" to their names.
- The wizard is a Dialog (in a dialog) or a Region named by its title; the step content has a Heading level 2 with the step name.
- Step changes announce "Step 2 of 4, Build".
- Status never relies on colour: done has a check, error an icon and words.
- Contrast: `on-primary` on `primary` markers, `on-surface-variant` labels on `surface` 4.5:1 or better; the 1px `outline` ring of upcoming markers is 3:1.
- Targets: pressable steps are at least 32 (pointer) or 48 (touch) tall including the label.
- Reduced motion: cross-fade.

## Content
- Title: the task as a noun phrase, "New project", "Import builds".
- Step labels: one or two words, nouns, sentence case: "Template", "Build", "Repository", "Review".
- Buttons: "Back", "Next", and a final verb that names the result: "Create project", not "Finish" or "Done" when a verb fits.
- Error second lines say what to do: "Fix 1 field", "Choose a branch".

## e.ui today
`navigation.wizard` shows the step names in a row (done ones prefixed "+ ", the current `primary`, later ones `text-muted`), the current `content`, and a footer of Cancel (Plain), Back (Outlined, disabled on the first step) and Next or Finish (Filled, disabled while `can_advance` is false). To reach this design:
- Replace the "+ " prefix and colour-only states with markers (number, check, error icon), connectors and label weights; add the optional second line.
- Let the stepper wrap or switch to vertical or compact forms: today many or long step names run past `width`, since the row neither wraps nor clips.
- Keep Next enabled and report invalid steps (take a `validate` callback or a per-step error count) instead of disabling it through `can_advance`; hide Back on the first step.
- Split the footer: Cancel at the start, Back and Next at the end; let the caller name the final action.
- Add the compact variant, pressable done steps, step-change focus and announcements, and the discard confirmation on cancel.
