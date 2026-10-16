# Adwaita (GNOME / libadwaita) tokens, measured

Source: libadwaita 1.5.0 + GTK 4.14.5 (Ubuntu 24.04), read from the running library by
`scripts/linux/tokens.py` (colours) and from the rendered sizes in `manifest.csv` (metrics).
Confidence: **measured** = taken from the live library here; **stylesheet** = from the published
libadwaita 1.5 SCSS, not independently re-measured; **guess** = unverified.
Corrections to the brief: window bg is `#fafafa` (not `#fafafb`), and the light header bar is
`#ffffff` (not `#ebebeb`; `#ebebeb` is the sidebar). Libadwaita 1.6+ changed some values
(for example the dark `@window_bg_color` stays `#242424`, but the font becomes Adwaita Sans in 1.7).

## Named colours (measured)

libEGL warning: DRI3 error: Could not get DRI3 device
libEGL warning: Ensure your X server supports DRI3 to get accelerated rendering
/mnt/d/repos/neper/scripts/linux/tokens.py:20: DeprecationWarning: Gtk.Widget.get_style_context is deprecated
  ctx = win.get_style_context()
/mnt/d/repos/neper/scripts/linux/tokens.py:24: DeprecationWarning: Gtk.StyleContext.lookup_color is deprecated
  ok, c = ctx.lookup_color(n)
| name | light | dark |
|---|---|---|
| `@window_bg_color` | #fafafa | #242424 |
| `@window_fg_color` | #000000 a=0.80 | #ffffff |
| `@view_bg_color` | #ffffff | #1e1e1e |
| `@view_fg_color` | #000000 a=0.80 | #ffffff |
| `@headerbar_bg_color` | #ffffff | #303030 |
| `@headerbar_fg_color` | #000000 a=0.80 | #ffffff |
| `@headerbar_border_color` | #000000 a=0.80 | #ffffff |
| `@headerbar_backdrop_color` | #fafafa | #242424 |
| `@headerbar_shade_color` | #000000 a=0.12 | #000000 a=0.36 |
| `@card_bg_color` | #ffffff | #ffffff a=0.08 |
| `@card_fg_color` | #000000 a=0.80 | #ffffff |
| `@card_shade_color` | #000000 a=0.07 | #000000 a=0.36 |
| `@dialog_bg_color` | #fafafa | #383838 |
| `@dialog_fg_color` | #000000 a=0.80 | #ffffff |
| `@popover_bg_color` | #ffffff | #383838 |
| `@popover_fg_color` | #000000 a=0.80 | #ffffff |
| `@popover_shade_color` | #000000 a=0.07 | #000000 a=0.25 |
| `@sidebar_bg_color` | #ebebeb | #303030 |
| `@sidebar_fg_color` | #000000 a=0.80 | #ffffff |
| `@accent_color` | #1c71d8 | #78aeed |
| `@accent_bg_color` | #3584e4 | #3584e4 |
| `@accent_fg_color` | #ffffff | #ffffff |
| `@destructive_color` | #c01c28 | #ff7b63 |
| `@destructive_bg_color` | #e01b24 | #c01c28 |
| `@destructive_fg_color` | #ffffff | #ffffff |
| `@success_color` | #1b8553 | #8ff0a4 |
| `@success_bg_color` | #2ec27e | #26a269 |
| `@warning_color` | #9c6e03 | #f8e45c |
| `@warning_bg_color` | #e5a50a | #cd9309 |
| `@error_color` | #c01c28 | #ff7b63 |
| `@error_bg_color` | #e01b24 | #c01c28 |
| `@borders` | #000000 a=0.12 | #ffffff a=0.15 |
| `@scrollbar_outline_color` | #ffffff | #000000 a=0.50 |
| `@shade_color` | #000000 a=0.07 | #000000 a=0.25 |
| `@thumbnail_bg_color` | #ffffff | #383838 |

`a=` is alpha: foreground text is black at 80 % on light, white on dark. Button face is
`rgb(0 0 0 / 8%)` light, `rgb(255 255 255 / 10%)` dark (stylesheet); hover adds 3 % / 5 %, active
darkens by 8 % (stylesheet).

## Metrics

| Item | Value | Confidence |
|---|---|---|
| Button | min-height 34 (rendered 82 x 34 for "Button"), padding 5 10, radius 6 | measured |
| Entry / spin button / drop down | height 34, radius 6, entry padding 0 9 | measured / stylesheet |
| Check button | 28 high row, 20 x 20 indicator, radius 4 | measured |
| Radio | 20 x 20 indicator, radius 100 % | measured |
| Switch | 46 x 26 | measured |
| Progress bar | 8 high, radius 99 | measured |
| Scale | 34 high row, trough 10, slider 20 | measured / stylesheet |
| Scrollbar | 20 high lone horizontal; overlay slider 8, grows on hover | measured / stylesheet |
| Header bar | 47 high | measured |
| Menu bar (GtkPopoverMenuBar) | 28 high | measured |
| Boxed list row | 50 min (action row with subtitle 55) | measured |
| Popover / menu | radius 12, 1 px outline, shadow 0 1 3 / 0 2 6 | stylesheet |
| Dialog (AdwAlertDialog) | radius 18, buttons flat in a split row | measured visually |
| Focus ring | 2 px accent at 50 % alpha, offset -2 | stylesheet |
| Font | Cantarell 11 (Adwaita Sans from 1.7) | stylesheet |
| Tooltip | dark `rgb(0 0 0 / 80%)` surface, white text; the gallery's tooltip is only the CSS node, not the real tooltip surface | guess |

Hover / pressed / focus renders are produced by forcing state flags, which matches what the
stylesheet does for `:hover`, `:active` and `:focus-visible` (see README for limits).
