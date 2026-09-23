# Platforms

One design language on six hosts. A Neper app must feel native on each host without becoming six apps. The rule: **identity is shared, idiom is local.** Colour, type roles, shape, iconography and component anatomy are the same everywhere. Density, placement, platform conventions and system integrations follow the host.

## The host matrix

| | Windows | macOS | Linux | Android | iOS / iPadOS | Web |
|---|---|---|---|---|---|---|
| Input | Pointer, keyboard, pen, touch | Pointer, trackpad, keyboard | Pointer, keyboard | Touch, optional keyboard | Touch; iPad adds pointer and keyboard | Any: follow `pointer` and `hover` media |
| Density | -1 (-2 in tool windows) | -1 | -1 | 0 | 0 | -1 fine pointer, 0 coarse |
| Control height | 32 (24 dense) | 32 | 32 | 40 | 40 (44 target) | 32 or 40 |
| Targets | 32 | 32 | 32 | 48 | 44 | 32 or 48 |
| Body text | `body-medium` | `body-medium` | `body-medium` | `body-large` | `body-large` | By pointer |
| System face | Segoe UI Variable | SF Pro | Noto Sans / Cantarell | Roboto | SF Pro | The platform stack |
| Menus | In-window menu bar | The system menu bar | In-window (GNOME: header bar menu) | Overflow in the app bar | Context menus and toolbar | In-window |
| Back | Button in the title bar | ⌘[ and toolbar back | Header bar back | System back, predictive | Edge swipe and back button | Browser history |
| Window chrome | Mica title bar, snap layouts | Unified toolbar, traffic lights | Client-side header bar (GNOME) or server decoration | Edge-to-edge, system bars | Safe areas, home indicator | None: the page |
| Accessibility API | UI Automation | NSAccessibility | AT-SPI | AccessibilityNodeInfo | UIAccessibility | ARIA / the DOM |

## Rules every host follows

- **Adapt by capability, then by size class.** Report `hover`, `fine_pointer`, `keyboard` and `touch` truthfully. A touch-first host takes density 0 and 48 targets whatever its OS. A window's width picks its size class, which picks navigation and pane layout.
- **Respect safe areas and insets.** Bars pad by the system insets. Content scrolls under translucent bars but never ends under them. The on-screen keyboard pushes the focused field into view.
- **Follow appearance settings live.** Switch themes on the host's dark mode, contrast setting and accent colour. The accent may replace `primary` on Windows and macOS when the user asks for "use system accent"; the tonal ramp is regenerated from it.
- **Keyboard parity.** Tab and Shift+Tab move focus, arrows move within composite controls, Enter and Space activate, and Escape dismisses. Shortcuts use Ctrl on Windows and Linux and ⌘ on macOS and iPadOS, spelled in each platform's glyphs.
- **Scale by the host.** Layout is in logical pixels (DIPs, points, dp, CSS px). Follow the text-size setting up to 200% without clipping.

## Per-host idiom

- **Windows.** Honour Mica or Acrylic backdrops on the window ground (`surface` becomes translucent where the host allows). Underline access keys on Alt. The filled button is the dialog default, and dialog buttons order affirmative first. Snap layouts on the maximise button. Tray and notifications go through the shell.
- **macOS.** The menu bar holds every command; keep the in-window toolbar lean. Sheets slide from the title bar for document-modal questions. Affirmative actions go last, and ⌘. cancels. Scroll bars overlay and fade. Use the unified title bar.
- **Linux.** On GNOME, use client-side decorations with a header bar (title, back, primary action, a menu button), and put the affirmative action last. On KDE, follow its order and server decorations. Honour the portal for file dialogs.
- **Android.** Draw edge-to-edge. Support predictive back with a preview animation. Use bottom sheets over dialogs for choices on compact. Every press has a ripple. Honour dynamic colour when the user enables it.
- **iOS and iPadOS.** Navigate with large titles that collapse on scroll, back swipes from the edge, sheets with detents, context menus on long press, and haptics on toggles and pickers. No ripple: state layers darken. Use a wheel for time and dates on compact.
- **Web.** Use real links for navigation and real buttons for actions, with `:focus-visible`. The URL reflects the navigation state and history works. Respect `prefers-color-scheme`, `prefers-contrast` and `prefers-reduced-motion`. No hover-only affordances on coarse pointers.

## What `e.ui` needs to get there

1. **Host backends.** Today `e.os` has Windows (Win32) and Linux (X11) only. macOS (AppKit), iOS (UIKit), Android (NDK plus an activity shim), Web (wasm on canvas or DOM) and Wayland each need a variant behind the same surface.
2. **Theme v2 in `style.e`.**
   - Replace the fourteen `ColorRole`s with the tonal role set, generated from a seed by a tonal-palette function.
   - Replace the seven `TextRole`s with the fifteen type styles.
   - Add the shape scale, elevation levels 0 to 5, state-layer opacities, and density as a number.
   - Make `adapt` apply density and targets per host capability.
   - Give `MaterialLike` and `CupertinoLike` real idiom switches (ripple, back gesture, dialog button order) instead of metric changes.
3. **Focus ring painted by `widget.place`** for every focusable element, as the Button card specifies.
4. **State layers and ripples** as a paint feature of `widget`, not colour mixes in `resolve`.
5. **IME composition and text scaling** in `e.ui.input` and `e.text.layout`.
6. **System accent and appearance events** from each host into the theme.
