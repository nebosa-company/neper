# Neper UI design system

The design language `e.ui` is being built to (widget plan phase P5; progress in `docs/progress.html`). `tokens.json` holds every value, `platforms.md` the per-host rules, `components/<Name>/` one specification and preview per control, and `icons/` the 55 Neper Icons. The previews render with `components/bundle.css` over the tokens compiled to CSS custom properties.

Neper UI is the design language of `e.ui`, neper's native UI framework, for apps that run on Windows, macOS, Linux, Android, iOS and the Web from one codebase. It is calm, precise and dense where tools need density, and it is built on a tonal colour system seeded from the neper navy. Every value is a token, every control has one specification, and each host adapts only density, placement and platform idiom.

## Principles

- **Clarity over decoration.** Content leads. Chrome recedes into tonal surfaces; colour is spent on the one thing a person should do next.
- **One system, native manners.** A Neper app looks like itself everywhere and behaves like it belongs: macOS menus in the menu bar, iOS back-swipe, Windows access keys, Android predictive back, the Web's real focus and links.
- **Every state is designed.** Rest, hover, focus, pressed, dragged, selected, disabled, error, loading and empty each have a specified look. Nothing is left to a default.
- **Accessible by construction.** Contrast pairs are part of the tokens, not an afterthought. Every control has a role, a name and a keyboard path, and status is never shown by colour alone.
- **Density is a setting, not a redesign.** Touch hosts use the default metrics; pointer hosts step down one density level, and dense tool UIs two. Layout and hierarchy stay the same.

## Colour

The palette is tonal. Six key colours each generate a tonal ramp from the brand seed (`brand-ink`, #1b3a6b): primary (navy-blue), secondary (slate), tertiary (copper), error (red), success (green) and warning (amber), plus two neutrals. Roles pick tones from the ramps, so every theme is the same design at different tones.

- **Four themes:** `light`, `dark`, `high-contrast` and `high-contrast-dark`. Follow the host's appearance and contrast settings; never offer only one.
- **Surfaces:** `surface` is the window. Containers step up in tone, `surface-container-lowest` through `surface-container-highest`. Each step up means "in front of": cards on `surface-container-low`, bars on `surface-container`, dialogs on `surface-container-high`, fields on `surface-container-highest`.
- **Content on containers:** text and icons are `on-surface`, secondary text `on-surface-variant`, and every accent fill has its `on-` pair. Use only those pairs. They hold 4.5:1 in light and dark, and 7:1 in both high-contrast themes.
- **Emphasis:** `primary` is for the single most important action and the selected state of navigation. `primary-container` and `secondary-container` carry quieter emphasis: tonal buttons, selected chips, nav indicators. `tertiary` is the warm counter-accent; use it once on a screen, if at all.
- **Status:** `error`, `success` and `warning` each come with a container for banners and a strong tone for icons. Pair them with an icon or a word every time; success and error also differ in lightness.
  - Status words sit in `on-surface` or `on-surface-variant`, or in the `on-…-container` of their banner. The strong tone is for icons, marks and fills.
  - `error` alone may also colour supporting text under a field.
- **Selection and links:** selected text is `text-selection` (the primary container). Links are `primary`. `link-visited` (tertiary) is for web and documentation views only.
- **Data:** chart series take `data-1` to `data-6` in order. Series also differ by stroke style and direct labels, and every series holds 3:1 on `surface`.
- **User content keeps its own colour.** Swatches, images and colour-picker spectra show the colour itself, not a token, and sit on a 1px `outline-variant` edge so they read on any theme.
- **Lines:** `outline` for boundaries that must be seen (field outlines, checkbox rings, outlined buttons), at 3:1 on every surface. `outline-variant` for decorative dividers.
- **Focus:** `focus-ring` is solid, 3px wide, 2px outside the control, and 3:1 or better on every surface in every theme.

## Typography

- The system face on every host: Segoe UI Variable on Windows, SF Pro on macOS and iOS, Roboto on Android, Noto Sans or Cantarell on Linux, and the platform stack on the Web. `display` uses the display optical size where the host has one.
- Fifteen styles in five roles. **Display** (57, 45, 36) is for hero numbers and big statements. **Headline** (32, 28, 24) is for page and dialog titles. **Title** (22, 16, 14) is for bars, cards and section heads. **Body** (16, 14, 12) is for reading. **Label** (14, 12, 11, weight 600) is for controls. `code` is mono.
- Touch hosts set body copy in `body-large`; pointer hosts in `body-medium`.
- Sentence case everywhere. No ALL CAPS, including buttons and tabs. Right-to-left mirrors layout, not glyphs.

## Layout

- A 4px grid. Spacing steps are `space-1` 4 through `space-16` 64. Components pad in `space-4`, dialogs in `space-6`, sections separate by `space-8`.
- **Window size classes:** compact below 600, medium from 600, expanded from 840, large from 1200, extra-large from 1600.
  - Compact: bottom navigation bar, one pane, full-screen dialogs for forms, bottom sheets.
  - Medium: navigation rail, one pane or list plus detail.
  - Expanded and up: rail or standing drawer, list-detail panes, side sheets.
- **Page margins:** 16 on compact, 24 on medium and up. Content caps at 1040 on extra-large, and the extra space becomes margin.
- Size by the window, never by the device.

## Shape

`radius-none` for bars and full-bleed media. `radius-xs` 4 for snackbars, tooltips and tags. `radius-sm` 8 for chips and menus. `radius-md` 12 for cards. `radius-lg` 16 for the FAB and drawer edge. `radius-xl` 28 for dialogs, sheets and the search bar. `radius-full` for buttons, switches, sliders, nav indicators and avatars. Nested shapes shrink their radius by the padding between them.

## Elevation

Elevation is tonal first and shadow second. Most surfaces are flat and separated by container tone. Only things that float cast a shadow: menus and the navigation bar under scrolled content cast `elevation-2`; the FAB, dialogs and pickers `elevation-3`; dragged items `elevation-4` to `elevation-5`. Shadows are two soft layers in `shadow`, stronger in dark themes, where tone does most of the work.

## States and interaction

- A **state layer** is the content colour laid over the container: hover at 8%, focus at 10%, pressed at 10%, dragged at 16%.
- On touch hosts, a press also spreads a ripple from the touch point. On iOS the layer darkens without a ripple.
- **Focus** shows the ring only after keyboard navigation (`:focus-visible` semantics). A press never shows it.
- **Disabled** is `on-surface` at 12% for containers and 38% for content. Disabled controls are not focusable. Prefer explaining why an action is unavailable to disabling it silently.
- **Targets** are 48 on touch hosts (never below 44 on iOS) and at least 32 with a fine pointer, padded when the visual is smaller.
  - Desktop chrome that only a pointer reaches (a 24px status bar, a menu bar's titles, tab close buttons) may be 24, provided each item is also reachable by keyboard.
  - A pane sash draws 1px and hit-tests 8px, taking the rest from the neighbouring panes.
- **Fields show focus by their outline.** Text fields, selects, combo boxes and list boxes show focus with the 2px `primary` outline (or active indicator), not the ring; the ring would double it. Everything else shows the ring.
- **Rings on inverse surfaces.** On `inverse-surface` (snackbars, plain tooltips) the ring is `inverse-primary`.
- **Active is not selected.** In menus, list boxes, combo boxes and pickers, the keyboard-active row takes the `state-focus` layer; the selected row takes `secondary-container` with a check. A row can be both.
- **Disabled, with a reason.** A disabled control's label and container follow the 38% and 12% rule. Outlined containers take a 12% outline. The message that says why it is disabled stays at full `on-surface-variant`.
- **Scrims.** Modal overlays take a scrim at `scrim-opacity`: dialogs, modal sheets, the modal drawer, the command palette and the window switcher. Non-modal ones never do: menus, popovers, flyouts, tooltips, snackbars and docked pickers.
- **Anchored overlays** open below and start-aligned to their anchor. They flip above, then to the side, when they would leave the window, and stay 8px from its edges. A press outside dismisses them without passing through to what is underneath.
- **Timing.** A tooltip waits 500ms on hover and hides 1500ms after the pointer leaves (at once on focus loss). A snackbar stays 4s, or 10s with an action, and pauses while hovered or focused. A toast stays 5s. A skeleton appears only after 300ms of waiting.

## Motion

Motion explains where things come from and go.

- **Durations:** short (50 to 200ms) for state changes, medium (250 to 400ms) for components entering and expanding, long (500ms) for page transitions.
- **Easing:** things entering use `ease-emphasized-decelerate`, things leaving `ease-emphasized-accelerate`, and changes in place `ease-standard`.
- **Reduced motion:** replace movement with a 100ms cross-fade, and stop indeterminate animations at a static frame.

## Iconography

- Neper Icons: a 24px grid, 1.75px strokes, round caps and joins, and a 2px live-area inset. Icons are line icons; a filled variant marks the selected state where the outline alone is ambiguous (star, nav destinations).
- Sizes are `icon-xs` 16 in 24px desktop chrome, `icon-sm` 18 inside buttons and chips, `icon-md` 24 in bars, lists and icon buttons, and `icon-lg` 36 for empty states.
- An icon takes the colour of the label it sits with. Icons that act need an accessible name; decorative ones are hidden from the tree.
- The set ships as SVG in the Icons group. On a host, prefer the platform's own glyph for platform chrome only: window controls, the share sheet and system back.

## Voice and content

- Plain, specific and calm. Say what happened and what to do next: "Build 4128 failed on Linux. View log". Avoid "An error occurred".
- Name actions by outcome ("Delete project", "Save changes"), never "OK", "Yes" or "Submit".
- Sentence case. Numerals for numbers. No exclamation marks, no emoji, no trailing periods on labels. Use a period in body text.
- Address the person as "you" and the app as nothing: say "Saved", not "We saved your file".
- **Required fields:** mark whichever kind is the minority. If most fields are required, mark the rest "(optional)". Otherwise mark each required field with "*" and explain it once with a "* Required" legend.
- **Dialog actions:** the default action is a filled button at the end (at the start on Windows and KDE), with the other actions as text buttons. A destructive default uses Danger.

## Logo

The mark is a lowercase italic *e* with a rising tail, drawn in `brand-ink`. Use the lockup in headers, the mark at 48px and above, the small cut below 48px, and the icon tile on dark grounds and as the app icon. Keep clear space of half the mark's height on every side. Don't re-slant, recolour, outline, add effects, or reset the wordmark in a font.

## Accessibility

- Every component card lists its role, name, states, actions and keyboard path. `e.ui.accessibility` publishes them to Narrator/UIA, VoiceOver/NSAccessibility, Orca/AT-SPI, TalkBack and the browser's tree.
- Honour host settings: text size (scale type and layout; never clip), bold text, reduce motion, increase contrast (switch to a high-contrast theme), and reduce transparency.
- Everything a pointer can do, a keyboard can do. On touch hosts, every gesture has a visible alternative.
