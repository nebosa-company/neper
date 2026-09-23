# Icon

An icon is a small symbol from the Neper icon set that names an action, an object or a status at a glance, tinted to the content colour of whatever it sits on.

## Anatomy
1. Canvas: a 24 × 24 grid, drawn once and scaled.
2. Live area: 20 × 20, a 2 px inset on every side; strokes may reach the inset only for optical balance (circles, diagonals).
3. Glyph: 1.75 stroke at 24, round caps and joins, no fill; the "on" form of a toggleable icon is filled (`star` / `star-filled`).
4. Tint: one colour, `currentColor`, taken from the content role of the container.

## Variants and when to use
| Variant | Size | Use for |
|---|---|---|
| Small | `icon-sm` 18 | Inside buttons, chips, segmented buttons, menus on dense hosts, inline in text. |
| Medium | `icon-md` 24 | The default: app bars, list leading icons, navigation, icon buttons. |
| Large | `icon-lg` 36 | Empty states on compact windows, large list leading icons, a dialog's hero icon. |
| Outline | stroke | Every icon at rest. |
| Filled | fill | The selected or "on" form: a selected nav destination, a favourited item. |
| Status | stroke, status colour | `check-circle` success, `warning` warning, `error` error, `info` neutral; always with a word. |

For an icon that is pressed use Icon button. For a picture use Image. For a person use Avatar. For brand marks use the logo assets, never an icon.

## Specs
| Part | Value |
|---|---|
| Grid | 24 × 24, live area 20 × 20 |
| Stroke | 1.75 at 24 (scales with the icon: 1.31 at 18, 2.63 at 36); round caps and joins |
| Sizes | `icon-sm` 18, `icon-md` 24, `icon-lg` 36; never other sizes, never below 16 |
| Colour, default | `on-surface-variant` in lists, fields, app bars; `on-surface` when the icon is the main content |
| Colour, on a container | the container's `on-*` role: `on-primary`, `on-secondary-container`, `on-tertiary-container`, `inverse-on-surface` |
| Colour, emphasis | `primary` for a selected or active icon on `surface` |
| Colour, status | `success`, `warning`, `error`, `primary` (info), each with a label |
| Disabled | `on-surface` at 38% (`state-disabled-content`) |
| Gap to a label | `space-2` 8 inside controls (`icon-sm`), `space-4` 16 in list rows |
| Pixel snapping | the canvas snaps to whole device pixels; strokes are not snapped |

## States
An icon has no interactive states of its own; its container (Icon button, list row, chip) draws the state layer and focus ring.
- Selected: the filled form, in the container's selected content colour.
- Disabled: 38% `on-surface`.
- Loading: a Progress ring of the same size replaces it; the space does not change.
- Missing glyph: a blank square of the size (never a tofu box or a letter); log the missing name in debug builds.

## Behaviour
- Icons flip in RTL only when they show direction (`arrow-back`, `arrow-forward`, `chevron-left`, `chevron-right`, `share`); clocks, checks, media and brand-neutral objects do not flip.
- Morphing between two forms (outline to filled, `menu` to `close`) cross-fades over `duration-short-3` with `ease-standard`; with reduced motion it swaps.
- Icons scale with the host's text size only inside text (inline icons); control icons keep their token size.
- An icon is never a target by itself.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | The Neper set, not Segoe Fluent Icons, for consistency across hosts; tint follows the tokens, and in Windows high contrast it takes the system `ButtonText` / `GrayText` colours. |
| macOS | The Neper set, drawn to align with SF Symbols' weight at regular (1.75 matches SF's regular at 17 pt); menu bar and Dock images are template images so the system tints them. |
| Linux | The Neper set by default; apps may opt to use the freedesktop icon theme for file types and devices only. |
| Android | The Neper set at 24 dp; notification and launcher icons follow Android's own grids (outside this component). |
| iOS | The Neper set at 24 pt; tab bar icons use the filled form when selected, as UITabBar does. |
| Web | Inline SVG with `currentColor` and `aria-hidden`; no icon fonts. |

## Accessibility
- Decorative (next to a label): hidden from the tree (`aria-hidden`).
- Meaningful on its own (a status with no word nearby, which the rules forbid in controls): role Image with a name that says the meaning, "Failed", not the shape "red circle".
- An icon inside an Icon button is hidden; the button carries the name.
- Contrast: 3:1 against the ground for non-text graphics (WCAG 1.4.11); every documented `on-*` pair meets 4.5:1.
- Status is never icon colour alone: the shape differs per status and a word goes beside it.
- High contrast themes tint with the high-contrast content role; the stroke never thins.
- Reduced motion: no morph animation.

## Content
- Pick the icon for its meaning, not its looks, and use the same icon for the same meaning across the app: `delete` means delete everywhere.
- When an icon means something unusual, add a label; if you need a tooltip to explain it everywhere, it needs a word instead.
- Never use letters, emoji or screenshots as icons.

## e.ui today
`control.icon` draws a caller-uploaded `scene.TextureId` as a `size` square, fit `.Contain`, under an Image-role node labelled `label`. To reach this design:
- Tint: the texture paints in its own colours (`ponytail:` tint waits on the image brush), so dark icons vanish in the dark theme; render icons as vector paths (the 49-icon set) filled with a colour role.
- Take an icon name from the shared set instead of a texture per call site, and the three token sizes instead of a free `size`.
- Hide the icon from the tree when `label` is empty (decorative), as `image` already does; today an empty label still makes an Image node.
- Add the filled "on" form and RTL mirroring for directional icons.
