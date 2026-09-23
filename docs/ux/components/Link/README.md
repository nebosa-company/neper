# Link

A link navigates: it takes the person to another view, document or site, either inside running text or as a standalone line.

## Anatomy
1. Label: the destination in words.
2. Underline (inline): 1 px, 3 px below the baseline, in the label colour.
3. Trailing icon (standalone): `arrow-forward` at `icon-sm` 18, `space-1` 4 after the label.
4. Target: the label's box padded to `target-pointer` 32 (48 on touch) without moving the text.
5. State wash and focus ring.

## Variants and when to use
| Variant | Look | Use for |
|---|---|---|
| Inline | the surrounding role, `primary`, underlined | A destination named inside a sentence. Built with Rich text. |
| Standalone | `label-large` `primary`, trailing arrow, underline on hover | "View build log", "All releases": a destination on its own line, in cards, empty states, list footers. |
| Quiet | `body-small`, underlined, `on-surface-variant` | Footers, legal and reference rows where many links sit together. |

Use Button for an action that changes something (Save, Delete, Clear cache) even if it looks light: a text button, not a link. Use a list row with a chevron for navigation in a settings list. Use Tabs or navigation components for app sections.

## Specs
| Part | Inline | Standalone | Quiet |
|---|---|---|---|
| Type | the paragraph's role | `label-large` 14/20 600 | `body-small` 12/16 |
| Colour | `primary` | `primary` | `on-surface-variant` (hover `primary`) |
| Underline | 1 px, offset 3, always | none at rest, 1 px on hover | 1 px, always |
| Icon | none | `arrow-forward` 18, `space-1` gap | none |
| Target | line height, padded to 32 / 48 | min 32 tall (48 on touch) | padded to 32 / 48 |
| Radius (wash, ring) | `radius-xs` 4 | `radius-xs` 4 | `radius-xs` 4 |
| Visited | `tertiary` in web and docs views only | not shown | `tertiary` in web and docs views only |

## States
- Hover: underline 2 px (standalone: underline appears), a `primary` wash at `state-hover` 8% behind the label; pointer becomes a hand.
- Focus: the focus ring 3 px `focus-ring`, 2 px outside, following every line of a wrapped link.
- Pressed: `primary` wash at `state-pressed`.
- Visited: `tertiary` (only where the destination is a document the person reads once: help, docs, web content).
- Disabled: `on-surface` 38%, no underline, not focusable. Avoid it: remove the link or explain why the destination is unavailable.

## Behaviour
- Enter follows the link (Space does not, as on the web; Space scrolls). Links are Tab stops.
- Ctrl/Cmd+click and middle-click open in a new window or tab in apps that have them; Shift+click opens in a new window.
- External links (another app or the browser) say so in the accessible name ("opens in browser") and never open without the person's action.
- Right-click or long press offers Open, Open in new window (where supported), Copy link.
- The link does not change when followed, apart from the visited colour.
- Motion: the wash fades in `duration-short-2` with `ease-standard`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | HyperlinkButton behaviour: underlined inline links, `primary` accent; Shift+F10 for the context menu. |
| macOS | Inline links underlined; standalone links may omit the arrow in sidebars; ⌘-click opens in a new window. |
| Linux | GTK link buttons: underlined, visited colour used in help views; middle-click opens in a new tab. |
| Android | 48 targets by padding; long press shows the link preview menu; external links open Custom Tabs. |
| iOS | 44 pt targets; long press shows a preview (context menu with Open, Copy link, Share); external links open Safari or an in-app Safari view. |
| Web | Real `<a href>` so middle-click, copy link and history work; `:visited` for the visited colour; never `<a>` without `href`. |

## Accessibility
- Role Link with the Press (Follow) action, named by the label; external links add "opens in browser".
- The underline (inline) or arrow (standalone) makes links identifiable without colour.
- Contrast: `primary` on `surface` 4.5:1; the `tertiary` visited colour also 4.5:1.
- Target: 32 with a fine pointer, 48 on touch, by padding; adjacent links in a row keep `space-4` 16 apart.
- Readers list links out of context, so every label must make sense alone.
- Reduced motion: no fade on hover.

## Content
- Name the destination, not the gesture: "View build log", not "Click here" or "More".
- Sentence case, 1-5 words for standalone links, no trailing period or arrow character (the icon is the arrow).
- Inline links cover the words that name the destination, not the whole sentence.

## e.ui today
`control.link` draws the label as Body text in `primary` inside a Link-role region at least `hit-target` square, text at its top start. To reach this design:
- Underline inline and quiet links, and add the standalone variant with `label-large` and the trailing arrow.
- Call `control_state` and draw hover, pressed and the focus ring; today a focused link looks like one at rest.
- Centre the label vertically in its target; a single line sits at the top of a 44 box with 12 px of empty target below.
- Add an `enabled` parameter, a visited look for docs views, and the context menu (Copy link).
- Add an external flag that appends "opens in browser" to the name.
