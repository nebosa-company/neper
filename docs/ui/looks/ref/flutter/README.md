# Flutter reference captures

References for the Neper, Material (Android) and Cupertino (macOS/iOS) looks only. No real macOS, iOS or Android screenshots exist, so Flutter's own widgets stand in. There is no reference for the GNOME or Fluent looks (Flutter core has no such widgets).

Layout: `<neper|material|cupertino>/<light|dark>/<control>-<state>@<1x|1.5x|2x>.png`. `manifest.csv` maps every file to a Neper control id (`lib/e/ui` inventory id) and the Flutter widget used. 3048 PNGs: neper 1338, material 1338, cupertino 372.

## How they were made

- Flutter 3.44.2 (stable, Dart 3.12.2), offline: `flutter test` with `flutter_tester`, nothing downloaded. Regenerate with `pwsh scripts/flutter_refs/run.ps1` (sources in `scripts/flutter_refs/`; the project lives outside the repo at `D:/Temp/flutter-looks`).
- Each sheet is one widget in a fixed-size `MaterialApp`/`CupertinoApp` (view devicePixelRatio 1), captured from a `RepaintBoundary` with `toImage(pixelRatio: 1, 1.5, 2)`. Layout is identical at all three; only the raster scale changes.
- Neper: `ThemeData(useMaterial3: true, ColorScheme.fromSeed(0xFF1B3A6B))`. Material: same with the baseline seed `0xFF6750A4`. Cupertino: `CupertinoThemeData` light and dark.
- Fonts (real, loaded with `FontLoader`): Roboto 100 to 900 from `D:/flutter/bin/cache/artifacts/material_fonts`; `MaterialIcons` from the same folder; `CupertinoIcons` from the pub cache (`cupertino_icons-1.0.9`).
- States: rest, hover (mouse pointer moved onto the control), focus (Tab key, traditional highlight mode), pressed (mouse button held down, so hover is also active), disabled and selected (built with the widget's own options). Overlay controls (dialogs, menus, pickers, sheets, snackbar, tooltip) use state `open`.

## What is approximate

- Cupertino text is Roboto, registered under the `.SF Pro Text`, `.SF Pro Display`, `.SF UI Text` and similar names. Metrics, weights and glyph shapes differ from San Francisco. No Inter was available. Treat Cupertino text width and baseline as approximate; colours, shapes and geometry are Flutter's own.
- Hover, focus and pressed are simulated by the test gestures, not captured from an OS. Controls with no visible change in that state (Cupertino slider pressed/disabled, Cupertino tab bar pressed, search bar focus) are identical to rest.
- A thin near-black outline appears on hovered Material buttons and on snackbar, popup menu and dropdown surfaces in this headless run. It also appears in a minimal plain app, so it is the framework's rendering here, but it is not in the Material spec: do not match it without checking against a real run.
- The Material pressed state shows the ripple mid-expansion (about 500 ms after press), not a settled frame. Indeterminate progress is one fixed frame.
- Platform is Flutter's test default (android), so Material typography is Roboto and ripples are the Android ones, even for the Neper set.
- Mapping to Neper ids is by closest role: `ListTile` is `list`, `Stepper` is `wizard`, `CupertinoPicker` is `list_box`, `DropdownMenu` is `combo_box`, `CupertinoContextMenu` is `popup_menu`. Not captured: FAB-like variants beyond the four listed, the Cupertino compact date picker, and anything with no Flutter core equivalent.
