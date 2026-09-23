# Accordion

An accordion is a stack of expander headers in one container where opening a section can close the others, for long settings or reference pages read one part at a time.

## Anatomy
1. Container: `surface-container-low` (filled) or `surface` with 1px `outline-variant` (outlined), `radius-md`, clipped.
2. Section header: a full-width row, 56 min (72 with a supporting line): optional leading icon, title, supporting line, trailing chevron.
3. Chevron: `chevron-down` 24 in `on-surface-variant`; turns 180° while open.
4. Divider: 1px `outline-variant` between sections, full width.
5. Section content: below its header, 16 sides and bottom.
6. State layer and inset focus ring on the header.

## Variants and when to use
| Variant | Container | Use for |
|---|---|---|
| Filled | `surface-container-low` | A settings page or sheet on `surface`, where the group should read as one block. |
| Outlined | `surface` + `outline-variant` | Inside a card or on a tinted pane, where a filled block would stack tones. |
| Single-open | one section at a time | Reference and FAQ content; keeps the page short. Default. |
| Multi-open | any number open | Settings people compare across sections. |

Use a single Disclosure for one optional block, Tabs for peer views of equal weight, and a Navigation drawer or list-detail when sections are long enough to be pages.

## Specs
| Part | Default (touch) | Dense (density -1) |
|---|---|---|
| Header height | `control-xl` 56; 72 with supporting line | `control-lg` 48; 64 with supporting line |
| Header padding | `space-4` 16 sides, `space-2` 8 vertical | same |
| Leading icon | `icon-md`, `on-surface-variant`, gap `space-4` | same |
| Title | `body-large`, `on-surface` | `body-medium` |
| Supporting line | `body-medium`, `on-surface-variant` | `body-small` |
| Content | `body-medium` `on-surface-variant`, padding 0 `space-4` `space-4`; indented 56 under a leading icon | same |
| Divider | `divider` 1, `outline-variant` | same |
| Container | `radius-md` 12, no shadow | same |
| Focus ring | inset 3px `focus-ring` | same |

## States
- Header hover `state-hover`, focus `state-focus` plus the inset ring, pressed `state-pressed` (ripple on touch).
- Open: chevron rotated; the header keeps its colours. Only the content tells the sections apart.
- Disabled: header content `on-surface` 38%, not focusable; say why in the title or supporting line ("needs an owner").
- Error inside a section: put an `error` icon and a word in the header's supporting line ("1 field needs attention") so a closed section still reports it.

## Behaviour
- Press or Enter/Space on a header toggles it. In single-open mode, opening one closes the open one in the same motion.
- Up and Down move between headers, Home and End jump to the first and last; Tab leaves the header list for the open content.
- Open over `duration-medium-2` with `ease-emphasized-decelerate`; close with `duration-short-4` and `ease-emphasized-accelerate`. The page scrolls so the opened header stays where it was on screen.
- Opening never moves focus. Deep links may open a section and scroll to it.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Dense; follows WinUI Expander stacks with 4px gaps when outlined inside a settings page. |
| macOS | Dense; in System Settings style, prefer grouped outlined sections; Option-click a header opens or closes all. |
| Linux | Dense; GNOME uses Adwaita expander rows inside boxed lists (outlined variant). |
| Android | Default size, 48 targets, ripple; the filled variant on `surface`. |
| iOS | Default size, 44pt rows; inset grouped style (outlined, `radius-md`); no ripple. |
| Web | Default on touch, dense with a fine pointer; each header a `button` with `aria-expanded` inside a heading element. |

## Accessibility
- Each header is a button inside a heading (level chosen by the page), name = title (+ supporting line as description), state expanded or collapsed, controlling its content region.
- The content region is labelled by its header.
- Announce the state change only; single-open does not announce the section that closed.
- Targets are the full header row. Header text meets 4.5:1 on both containers.
- Reduced motion: content cross-fades in 100ms; the chevron swaps without turning.

## Content
Section titles are short nouns ("Build", "Members"). The supporting line summarises what is inside or its current value ("4 people have access"). Sentence case, no trailing periods, no questions except in FAQ pages.

## e.ui today
`control.accordion` stacks Plain `disclosure`s with a triangle mark and a `primary` label, no container, no dividers, and only single-open via the caller's `expanded` index. To reach this design:
- Draw the filled or outlined container with `radius-md` and 1px `outline-variant` dividers between sections.
- Replace the headers with full-width 56/72 rows (leading icon, title, supporting line, trailing chevron).
- Add a multi-open mode (a set of open indices) alongside the single index.
- Add Up/Down/Home/End between headers, the inset focus ring and state layers.
- Animate open and close with the durations above; carry the error summary into a closed header.
