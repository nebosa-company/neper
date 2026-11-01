# Neper arc corners against Flutter (round 72, lane g)

Change: the Neper and Neper dark sheet looks draw rounded corners as true quarter-circle arcs (cubic, k 0.5523) instead of quadratic corners, as Flutter does. The switch is `widget.set_arc_corners`, set for the Neper profile in `looks.set_look`; `control.focus_look` leaves the flag alone for the Neper profile so it is not reset while a sheet draws. Windows, Linux, Cupertino and Material keep their old setting. The runtime outside the sheet harness is unchanged.

Why: a quadratic corner on a full-radius shape (radius half the side) is a squircle, fatter than a circle at the diagonals.

## Measured

Own comparer (scratch, not committed): flat-colour components, then the farthest filled pixel on 360 rays from the centre of each circular component (spread = max minus min radius), plus a stadium coverage test for pills.

- Time picker dial, 224 px face: spread 7.75 px before, 1.0 px after; the Flutter ref (256 px face) has 1.25 px. Dark identical. Mean radius 112 as expected.
- 70 px and 46 px circles (empty state): spread 3.25 and 2.5 before, 1.0 and 1.0 after. 40 px circles (check list, calendar, pagination, dialog message): 2.0 before, 1.25 after. 30 px (rating, toast, date edit, calendar): 2.0 before, 1.0 after. 38 px (notification list, banner): 2.25 before, 1.25 after.
- Pills (buttons, 32 px tall): area against the ideal stadium +0.30 px of boundary before, -0.07 after; the Flutter filled button ref (88 x 40) reads -0.59 on the same test, so within 1 px.
- 20 sheets measured this way against the ideal arc or the ref: time_picker_dial (light, dark), button, button_states, button_kinds, button_arrows, icon_button, avatar, badge, toggle_button, split_button, rating, toast, notification_list, empty_state, date_edit, calendar, pagination, radio_states, radio_group_states, check_list_box.

Unchanged by design: rounded squares and small radii (checkbox, 2 to 4 px), which differ by well under 0.3 px between a quadratic and an arc.

## Re-render

All 146 sheet apps whose runners draw the Neper look were compiled and run one at a time (329 runs incl. the multi-sheet arguments); 1064 Neper and Neper dark PNGs changed (1x and 1.5x), 265 sheets. About 30 PNGs were viewed (buttons, badges, avatars, icon buttons, radios, range slider, search field, rating, toggle, dials, speed dial, bottom app bar, snackbar, progress, pagination, toast, alert dialog, bottom sheet, banner, popover, notifications, empty state, calendar, button states dark): all draw correctly, nothing broken, so no row moves to review.

The same runs rewrote the Windows, Windows dark, Linux, Linux dark, Material, Material dark and Cupertino PNGs of those apps and left them byte-identical, except Cupertino and Cupertino dark `duration_picker`, `font_picker` and `time_picker`: the committed pictures come from a later app, the run_ten output differs with or without this change (checked by rendering `duration_picker` on the unmodified source), so those 12 files were restored from git.

Known leftovers seen, not caused by this change: alert dialog, toast and sheets draw a hard-edged shadow strip under the card in Neper.

## Rows

No status change: Neper rows stay `ready`. Overlay `status.d/zzz...-round72-g.json` is empty.
