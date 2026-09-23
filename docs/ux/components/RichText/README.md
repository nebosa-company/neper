# RichText

Rich text is one paragraph built from styled spans, for copy that mixes emphasis, code, keys, mentions or inline links.

## Anatomy
1. Paragraph: one base Text role (usually `body-medium`) that sets the line height for every line.
2. Spans: runs with their own weight, style, role or colour role, laid out inline and wrapped together.
3. Inline code: `code` role on `surface-container-high`, `radius-xs`, `space-1` sides.
4. Inline key: Keyboard key (`nu-kbd`), 24 tall, `space-1` apart.
5. Mention: weight 600 in `primary`, pressable when it opens a profile.
6. Inline link: `primary`, 1 px underline 3 px below the baseline.
7. Inline icon: `icon-sm` 18 in the line, centred on the x-height.

## Variants and when to use
| Span | Style | Use for |
|---|---|---|
| Strong | weight 600, same colour | The one fact the reader must not miss: "Cache is stale." |
| Emphasis | italic | A word that changes the meaning. Rare. |
| Code | `code` on `surface-container-high` | Branch names, paths, identifiers, commands. |
| Key | Keyboard key | Shortcuts written inside a sentence. |
| Mention | 600 `primary` | A person or team, opening their profile. |
| Link | underlined `primary` | Navigation inside the sentence. |
| Colour | a role's colour with an icon or sign | A status inside a sentence: "+12%", a check icon. |

Use Text when the paragraph is one style. Use Link for a link standing alone. Use a Markdown or document viewer for more than a few paragraphs, headings and lists.

## Specs
| Part | Value |
|---|---|
| Base role | `body-medium` 14/20 on pointer hosts, `body-large` 16/24 on touch |
| Line height | the base role's; taller spans (a key, inline code) must fit inside it without raising the line |
| Baseline | all spans align on the text baseline, including spans of larger roles |
| Inline code | `code` 13/20, `surface-container-high`, `radius-xs`, padding 0 `space-1` 4 |
| Key | `nu-kbd`: 24 tall, `surface-container-lowest`, 1 px `outline-variant` with a 2 px bottom edge, `font-mono` 12/16 |
| Link | `primary`, underline 1 px at 3 px offset; hover 2 px underline and a `primary` 8% wash; target padded to `target-pointer` 32 tall (48 on touch) without moving the text |
| Visited | `tertiary`, only in web content and documentation views |
| Mention | weight 600, `primary`; no underline |
| Inline icon | `icon-sm` 18, in the span's colour, `space-1` gap |
| Wrap | across spans at word boundaries; code and key spans never break inside |
| Clamp | `max_lines` with an end ellipsis; an ellipsis falls before a link, never inside it |

## States
Spans are static except links and mentions:
- Hover: underline thickens to 2 px, a `primary` 8% wash behind the span.
- Focus: the focus ring 3 px `focus-ring`, 2 px outside the span's box on every line it covers.
- Pressed: `primary` 10% wash.
- Visited: `tertiary` (web and docs only).
- Disabled: `on-surface` 38%, no underline, not focusable. Prefer removing the link.

## Behaviour
- Links and mentions are Tab stops in reading order; Enter opens. Everything else is not focusable.
- A link spanning two lines is one target: hover and focus paint both fragments.
- Pointer: the cursor is a hand over links, an I-beam over the rest if the text is selectable.
- Touch: a tap on a link opens it; long press shows the link's preview or a menu (Open, Copy link) on hosts that offer one.
- Rich text is not selectable by default; set it selectable for messages that people quote.
- Motion: the hover wash fades in `duration-short-2` with `ease-standard`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Hyperlinks underline at rest, like the WinUI HyperlinkButton in text; Shift+F10 opens the link's context menu. |
| macOS | Links may be un-underlined in sidebars, but inside a sentence keep the underline; ⌘-click opens in a new window where the app has windows. |
| Linux | Follow GTK link colours only through the tokens; middle-click on a link opens it in a new tab in apps with tabs. |
| Android | body-large base; links get a 48 target by padding the line, not by enlarging the text; long press shows a link preview. |
| iOS | body-large base with Dynamic Type; long press shows the link preview (context menu with Open, Copy link, Share). |
| Web | Real `<a href>` for links, `<code>`, `<kbd>`, `<strong>`, `<em>` for spans; visited colour applies. |

## Accessibility
- The paragraph is one Text node read as a whole; links and mentions inside it are Link nodes with the Press action, reachable by the reader's link navigation.
- Strong and emphasis carry no role; if they change the meaning, reword instead.
- Keys are read by their names ("Control Shift B"), not as symbols.
- Colour spans must carry a sign, an icon or a word, never colour alone.
- Contrast: every span colour meets 4.5:1 on the ground; the link underline makes links identifiable without colour (WCAG 1.4.1).
- Reduced motion: no fade on hover.

## Content
- One idea per paragraph, 1-3 sentences. Sentence case.
- Link text says where it goes: "Read about build caches", never "click here" or a bare URL.
- One link per sentence at most; put more in a list.
- Wrap code in code spans, never quotation marks: `release/2.4`.

## e.ui today
`control.rich_text` lays `Span { value, role, color, link }` pieces side by side in a horizontal flex, gap 0, cross Start; a linked span becomes a Link-role region. To reach this design:
- Replace the flex with an inline paragraph layout: wrap across spans at word boundaries (the `ponytail:` one-line limit) and align spans on the baseline, not the top.
- Add span kinds (strong, emphasis, code, key, mention) instead of only role and colour.
- Underline linked spans and give them hover, focus, pressed and visited looks; today nothing marks a link.
- Pad a linked span's target to `target-pointer` (48 on touch); it has no minimum size today.
- Support `max_lines` with an ellipsis that avoids links, and report the paragraph as one Text node with Link children.
