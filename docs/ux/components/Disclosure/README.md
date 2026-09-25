# Disclosure

A disclosure is a header that shows or hides the content under it, for detail that most people can skip; the expander is the same control drawn as its own outlined section.

## Anatomy
1. Header: a button, `radius-sm`, 40 tall, holding the chevron and the label.
2. Chevron: `chevron-right` 24 (`icon-md`) in `on-surface-variant`; turns 90° to point down while open.
3. Label: `title-small`, `on-surface`; an optional meta (a count or summary) after it in `body-medium`, `on-surface-variant`.
4. Content: below the header, indented to the label's start (40).
5. State layer and focus ring on the header only.
6. Expander only: a container, 1px `outline-variant`, `radius-md`, with a 56 header row (leading icon, title, supporting line, trailing chevron).

## Variants and when to use
| Variant | Look | Use for |
|---|---|---|
| Disclosure | Plain header, content inline | Secondary detail inside a form or pane: advanced options, raw output, "Show 12 more". |
| Expander | Outlined container, list-row header | A self-contained section in a settings page that should read as a box. |

For several sections where one is open at a time use Accordion. For peer views use Tabs. For a hierarchy use Tree. Never hide a required field inside a closed disclosure.

## Specs
| Part | Disclosure | Expander |
|---|---|---|
| Header height | `control-md` 40 (`control-sm` 32 at density -2) | `control-xl` 56 min; 72 with a supporting line |
| Header padding | `space-2` 8 start, `space-3` 12 end | `space-4` 16 sides, `space-2` 8 vertical |
| Chevron | `icon-md`, `on-surface-variant`, gap `space-2` | trailing `icon-md` `chevron-down`, gap `space-4` |
| Label | `title-small`, `on-surface` | title `body-large` `on-surface`; supporting `body-medium` `on-surface-variant` |
| Header shape | `radius-sm` | square inside the container |
| Content | indent `space-10` 40; `body-medium` `on-surface-variant`; `space-1` above, `space-2` below | `space-4` 16 sides and bottom; indented 56 when the header has a leading icon |
| Container | none | `surface`, 1px `outline-variant`, `radius-md`, clipped |
| Focus ring | 2px outside the header | inset 3px (the header is edge to edge) |

## States
- Hover: `state-hover` layer of `on-surface` on the header.
- Focus: `state-focus` layer plus the ring, after keyboard navigation only.
- Pressed: `state-pressed` layer; ripple on touch hosts.
- Open: chevron rotated, content shown. The header does not change colour.
- Disabled: header content `on-surface` 38%, no layer, not focusable; the content stays as it was.
- Loading content: show a Skeleton in the content area, not a spinner on the header.

## Behaviour
- A press anywhere on the header toggles it. The content is never a press target for closing.
- Enter and Space toggle a focused header. Right opens and Left closes (mirrored in right-to-left), matching tree conventions.
- Opening expands the content height over `duration-medium-2` with `ease-emphasized-decelerate` while the chevron turns over `duration-short-3` with `ease-standard`; closing uses `duration-short-4` with `ease-emphasized-accelerate`. Content below moves, it is never covered.
- Opening scrolls the header into view only if the content would fall off screen; focus stays on the header.
- The app remembers open state per section key across sessions in settings pages.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Density -1: 32 header. Expander follows the WinUI Expander: chevron trailing, on the right. |
| macOS | Density -1. The inline disclosure uses a trailing "Show more" / "Show less" text in `primary` on sidebar sections, the chevron form in inspectors; Option-click opens all siblings. |
| Linux | Density -1. GTK expander shape: chevron leading, label bold. |
| Android | Default size; 48 target; ripple. Expander rows are 56. |
| iOS | Default size, 44pt target; in grouped lists the expander is a row with a trailing chevron that rotates, no ripple. |
| Web | Default size; built on `<details>`/`<summary>` semantics or a `button` with `aria-expanded`; `:focus-visible` ring. |

## Accessibility
- Header role button with `expanded` state; name = the label (plus meta, e.g. "Environment variables, 3 set"). Actions Expand or Collapse, whichever applies.
- The header controls the content region; the content is a group labelled by the header.
- Announce "expanded" or "collapsed" on toggle; do not move focus into the content.
- The chevron is decorative. Header target 40 visual, padded to 48 on touch.
- Reduced motion: the content appears with a 100ms cross-fade, no height animation, and the chevron swaps without turning.

## Content
Name what is hidden, as a noun phrase: "Advanced build options", "Environment variables". Not "More", "Click to expand" or a question. Sentence case, no trailing punctuation. Put a count in the meta rather than the label.

## e.ui today
`control.disclosure` draws a Plain `pressable` with a 20px filled triangle and the label in `primary`; `control.expander` wraps it in a bordered `radius-sm` surface. To reach this design:
- Replace the triangle with the `chevron-right` icon in `on-surface-variant`, rotated by animation, and set the label in `title-small` `on-surface`.
- Add the meta slot and the expander's list-row header (leading icon, supporting line, trailing chevron, 56 tall) on `outline-variant`, `radius-md`.
- Draw state layers and the focus ring (outside for disclosure, inset for expander) instead of mixing the fill.
- Animate open and close with `duration-medium-2`; honour reduced motion.
- Add Left and Right to close and open; keep `key + 1` as the controlled content group.
