# SearchBar

A search bar is the entry point to searching a view or the whole app. Focused, it expands into a search view that holds the query, recent searches and live suggestions.

## Anatomy
1. Bar container: a fully rounded pill (`radius-full`) on `surface-container-high`.
2. Leading icon: search, or the navigation menu when the bar replaces the top app bar on compact screens.
3. Placeholder or query: `body-large` (`body-medium` at 40).
4. Trailing slot: up to two icon buttons (voice, filter), an avatar, or a shortcut hint (`nu-kbd`, Ctrl K). While the bar holds a query, clear replaces them.
5. Search view: the container the bar expands into. It fills the screen on compact windows and docks below the bar on medium and larger ones.
6. View header: back (compact) or search icon, the query with the caret, and clear.
7. Divider: 1px `outline-variant` between the header and the results.
8. Suggestions: list rows grouped under subheaders (Recent, Files, People). The matched part of each suggestion is set in weight 600.
9. Fallback row: "Search all files for …", always last. It runs the full search.

## Variants and when to use
| Variant | Where | Use for |
|---|---|---|
| Bar, touch (56) | The top of a compact screen, in place of the top app bar | Search is the main way into the content: files, projects, people. |
| Bar, desktop (40) | A title bar, toolbar or pane header | Search inside a window or pane. Show the shortcut hint. |
| Search view, full screen | Compact windows (below 600) | The expanded state on phones. It covers the app bar and navigation. |
| Search view, docked | Medium and wider (600 and up) | A floating panel at the bar's width (at least 360, at most 720), anchored below it. |

To filter a list already on screen use an outlined Text field with a search icon, which filters in place without suggestions. To run commands as well as find things use Command palette. To pick one value from a long list use Autocomplete.

## Specs
| Part | Touch | Pointer (density -1) |
|---|---|---|
| Bar height | `control-xl` 56 | `control-md` 40 |
| Bar padding | 16 leading, 8 trailing | 12 leading, 4 trailing |
| Icon to text gap | `space-4` 16 | `space-3` 12 |
| Icons | `icon-md` 24 | `icon-sm` 18 |
| Query type | `body-large` | `body-medium` |
| Bar radius | `radius-full` | `radius-full` |
| Bar width | fills the layout, max 720 | 240 to 480 in a toolbar |
| View header height | 72 (full screen), 56 docked | 40 |
| View radius | 0 full screen; `radius-xl` 28 docked | `radius-xl` 28 |
| View elevation | none full screen; `elevation-3` docked | `elevation-3` |
| Suggestion row | 56 (one line), 72 (two lines) | 40 (`nu-li dense`) |
| Max docked height | 2/3 of the window, then the list scrolls | same |

| Part | Colour role |
|---|---|
| Bar and view container | `surface-container-high`; hover adds `on-surface` at `state-hover` |
| Placeholder, icons | `on-surface-variant` |
| Query | `on-surface`; caret `primary` |
| Suggestion headline | `on-surface`; the matched part weight 600, other text regular |
| Suggestion supporting text, subheaders | `on-surface-variant` |
| Shortcut hint | `nu-kbd` on `surface-container-lowest` |
| Divider | `outline-variant` |

## States
- Rest: the placeholder names what is searched ("Search projects").
- Hover: `state-hover` layer on the bar.
- Focused (keyboard on the bar, before it expands): `state-focus` layer and the 3px focus ring, 2px outside.
- Expanded: the view is open and the caret is in the query. With an empty query it shows recent searches. After the first character it shows live suggestions.
- Loading: when suggestions take longer than 300 ms, a 2px indeterminate progress bar runs under the header. The previous suggestions stay until new ones arrive.
- No results: one line of `body-medium` in `on-surface-variant` names the query and offers the next step. The fallback row stays.
- Disabled: rarely correct. Hide the bar instead when search is unavailable.

## Behaviour
- Opening: a tap on the bar, the shortcut (Ctrl K, ⌘K on macOS), or `/` in a content view. Compact: the bar grows into the full-screen view over `duration-medium-4` with `ease-emphasized-decelerate`. Docked: the view fades and grows from the bar over `duration-medium-1`.
- Closing: Escape clears a non-empty query first, and a second Escape closes the view. Back (compact), a click outside (docked), and choosing a suggestion also close it. Closing uses `ease-emphasized-accelerate` over `duration-short-4`. With reduced motion, both directions cross-fade.
- Suggestions update 150 ms after the last keystroke. Never reorder rows under the pointer or the keyboard focus.
- Keyboard: Down and Up move through the suggestions while the caret stays in the query (active descendant). Home and End stay in the text. Enter runs the highlighted suggestion, or the full search when none is highlighted. Tab moves to the view's first action, if any. Alt+Down opens the view without typing.
- Pointer: a hover highlights a row, and a click runs it. A trailing edit icon on a recent search copies it into the query without running it.
- Touch: the keyboard's action key is Search. Scrolling the suggestions hides the keyboard.
- The query stays in the bar after the view closes, so the results page and the bar agree. Clear empties it and returns focus to the query.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | 40 bar in the title bar or toolbar with the Ctrl K hint. Docked view. Follows the Fluent AutoSuggestBox keyboard model (Down enters the list). |
| macOS | 40 bar in the toolbar, trailing aligned, with a ⌘F or ⌘K hint. Docked view. Escape clears and then ends search. Where the app has a sidebar, prefer a toolbar search field over a bar in the content. |
| Linux | 40 bar. On GNOME, a search bar can reveal below the header bar and typing anywhere in a list starts search (type-to-search). KDE uses a toolbar field. Docked view. |
| Android | 56 bar replacing the top app bar on compact. Full-screen view with back. The IME action is Search. Voice as a trailing icon when available. |
| iOS | 56 bar under a large title, collapsing as the list scrolls. Cancel appears as a text button to the right while searching. Full-screen view. Scope chips appear under the header. |
| Web | `role="search"` landmark around an `<input type="search">` with `enterkeyhint="search"`. `/` focuses it. Full screen below 600, docked above. |

## Accessibility
- The bar sits in a search landmark. The input is a combobox with the name "Search" plus its scope ("Search projects"), expanded while the view is open, and controls the suggestion listbox.
- Suggestions are options with the active descendant pattern, so focus never leaves the input. Each option's name is its full text. The match highlight is not announced.
- A polite status announces the count after results settle ("6 suggestions") and "No results" when empty.
- The shortcut is exposed as the input's keyboard shortcut. The hint is decorative.
- Contrast: placeholder and icons 4.5:1 on `surface-container-high`. The bar's edge is not needed for contrast, because the placeholder and icon identify it.
- Targets: every icon button 48 on touch and 32 with a pointer. Rows meet the list-row minimums.
- Reduced motion: the view cross-fades in place and nothing grows from the bar.

## Content
- Placeholder: "Search" plus what is searched: "Search projects", "Search files and people". No ellipsis, no "Type to search".
- Subheaders are plural nouns: "Recent", "Files", "People".
- No results: name the query and give a way forward: "No results for "quarternion". Check the spelling or search all files."
- Fallback row: "Search all files for "build"". Quote the query exactly as typed.

## e.ui today
`control.search_field` is a `control.field` with no label and a "Search" placeholder, plus a Plain `button` labelled "Clear" beside it while it holds text. Enter fires `submit`. There is no bar or search view. To reach this design:
- Add `control.search_bar`: a `radius-full` pill on `surface-container-high`, 56 or 40 by density, with a leading icon, trailing slots and a shortcut hint.
- Move clear inside the bar as a trailing icon button with the name "Clear search", and drop the separate text button.
- Add `overlay.search_view`: full screen below the Medium size class, docked with `elevation-3` and `radius-xl` above it, with a header, divider and grouped suggestion rows fed by the caller.
- Give the input the combobox role with expanded and active-descendant semantics, and a polite result count.
- Wire Ctrl K or ⌘K and `/` to open it, Escape to clear and then close, and Down and Up to move through suggestions.
