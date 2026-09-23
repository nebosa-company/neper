# Text

A text shows a run of words in one type role and one colour role: every label, heading, paragraph and value a view prints.

## Anatomy
1. Glyph run: shaped in the role's family (`font-sans`, `font-display` for display and headline, `font-mono` for code).
2. Line box: the role's line height; lines stack with no extra leading.
3. Optional truncation mark: an ellipsis `…` at the end of the last allowed line, or in the middle of a path.
4. Bounds: no padding, no background. Spacing belongs to the parent.

## Variants and when to use
| Role | Size / line | Weight | Use for |
|---|---|---|---|
| `display-large/medium/small` | 57/64, 45/52, 36/44 | 400 | Hero numbers and one-word statements. Never more than one per screen. |
| `headline-large/medium/small` | 32/40, 28/36, 24/32 | 400 | Page titles by window class (expanded, medium, compact); dialog titles use small. |
| `title-large` | 22/28 | 400 | The small top app bar, a sheet's title. |
| `title-medium` | 16/24 | 600 | Card titles, list headers, pane headers. |
| `title-small` | 14/20 | 600 | Section heads inside cards, menus and group boxes. |
| `body-large` | 16/24 | 400 | Body copy on touch hosts; list headlines. |
| `body-medium` | 14/20 | 400 | Body copy on pointer hosts; supporting text. The default. |
| `body-small` | 12/16 | 400 | Captions, field support text, table meta. |
| `label-large/medium/small` | 14/20, 12/16, 11/16 | 600 | Text inside controls: buttons, chips, tabs, nav labels, badges. Not for paragraphs. |
| `code` | 13/20 | 400 mono | Paths, identifiers, values to copy. |

For text the person will copy use Selectable text. For mixed styles or inline links in one paragraph use Rich text. For a standalone link use Link.

## Specs
| Part | Value |
|---|---|
| Colour, primary copy | `on-surface` (on `surface*`), or the `on-*` of the container it sits on |
| Colour, secondary copy | `on-surface-variant` |
| Colour, emphasis | `primary`, only for a value that is also interactive or a live count |
| Colour, error | `error`, always with an `error` icon (`icon-sm` 18, `space-1` 4 gap) or the word "Error" |
| Measure | 40-80 characters; cap paragraphs at 520 wide on expanded windows |
| Paragraph gap | one line height of the role (`space-4` for body-medium) |
| Wrap | `.Word` by default; `.None` for labels inside controls |
| Truncation | End ellipsis after `max_lines`; paths and file names truncate in the middle, keeping the file name |
| Alignment | Start (left in LTR, right in RTL); centre only in empty states and dialogs with an icon; numbers in columns align end with tabular figures |
| Minimum size | 11 px (`label-small`); never scale below it |

## States
- Static text has no interactive states.
- Disabled: inside a disabled control the text takes `on-surface` at 38% (`state-disabled-content`); on its own a text is never disabled.
- Truncated: the full value is the accessible name and shows in a tooltip after `duration-short-4` of hover or a long press.
- Loading: a `nu-skeleton` bar the height of one line box and 60-80% of the expected width, one bar per expected line.

## Behaviour
- Text scales with the host's text size setting (Windows text scaling, Dynamic Type, Android font scale, browser zoom) from 85% to 200%; layouts reflow instead of clipping, and `max_lines` grows by the scale so no copy is lost at 200%.
- A text is not a target. If a whole row is pressable, the row takes the press, not the text.
- Changing a value in place (a counter, a status) cross-fades over `duration-short-3` with `ease-standard`; with reduced motion it swaps.
- Bidirectional text follows Unicode bidi; the start edge flips in RTL locales.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Segoe UI Variable (Text optical size under 20 px, Display above); body-medium is the default; respect the text scaling slider (Settings, Accessibility, Text size). |
| macOS | SF Pro Text / Display with system tracking; body-medium maps near the 13 pt system font, so pointer layouts use body-medium; follow the Larger Text accessibility setting where the app supports it. |
| Linux | Cantarell (GNOME) or Noto Sans (KDE) from the desktop's font setting; honour the text scaling factor and the hinting and antialiasing the desktop sets. |
| Android | Roboto; body-large is the default body; scale with the system font scale using sp units, non-linearly above 130%. |
| iOS | SF Pro with Dynamic Type: each role maps to a text style (body-large to Body, title-medium to Headline, body-small to Footnote) and follows the user's size, including accessibility sizes. |
| Web | The `--font-sans` stack; sizes in rem so browser zoom and the user's default size apply; real headings (`h1`-`h6`) for headline and title roles. |

## Accessibility
- Role Text (a static text node); headline and title roles also report Heading with a level (headline-large 1, headline-medium/small 2, title-large 3, title-medium 4, title-small 5) so screen readers can navigate by heading.
- The name is the full value, even when the visible line is truncated.
- Contrast: 4.5:1 for body and label roles, 3:1 allowed only for display and headline sizes (24 px and up); 7:1 in the high-contrast themes. `on-surface-variant` on `surface-container-highest` is the lowest documented pair and still meets 4.5:1.
- Colour never carries meaning alone: error and success text carry an icon or a word.
- Live values (a build status that changes) sit in a polite live region so the change is announced once, not on every frame.
- Reduced motion: value changes swap without the cross-fade.

## Content
- Sentence case for every role, headings included: "Recent files", not "Recent Files". No ALL CAPS; the label roles are not an excuse for uppercase.
- No trailing period on headings, labels or single-sentence captions; full stops only in body copy of two or more sentences.
- Numbers as numerals with units: "3 files", "1 min 12 s", "42 ms".
- Say what happened, then what to do: "2 tests failed. Open the log to see which."

## e.ui today
`control.text` shapes `value` in a `TextOptions { role, color, align, wrap, max_lines, ellipsis }` with seven roles (Heading 28/36, Title 20/28, Body 14/20, Label 13/18, BodySmall 12/16, Caption 11/14, Code 13/18) and flat colour roles (`Text`, `TextMuted`, `Primary`...). To reach this design:
- Replace `style.TextRole` with the 16-role ramp above (display, headline, title, body, label in three sizes, plus code), keeping `.Body` as an alias of body-medium.
- Map colour roles to the tonal set: `Text` to `on-surface`, `TextMuted` to `on-surface-variant`, and add the `on-*-container` roles so text on a container gets its pair.
- Report Heading with a level for headline and title roles; today every text is a plain Text node.
- Add middle truncation for paths (`ellipsis` only cuts the end today) and put the full value in the node's name when truncated.
- Scale with the host text size; roles are fixed pixel sizes today.
- A theme with no fonts lays out nothing (D802): fall back to the host's system font instead of an empty node.
