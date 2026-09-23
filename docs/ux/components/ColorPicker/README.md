# ColorPicker

A colour picker chooses a colour for user content (a label, an accent, a chart series): a swatch field that opens a panel of preset swatches, a spectrum with hue and opacity strips, and typed channel values.

## Anatomy
1. Trigger: a text field with a leading 20 swatch of the current colour, the value as hex, and a chevron; or a compact button with a swatch and a label in toolbars.
2. Panel: a popover on pointer hosts, a bottom sheet on touch.
3. Spectrum: a saturation-and-brightness area (150 tall) with a 20 ring thumb.
4. Hue strip: a 12 tall rounded strip of the full hue circle with a 20 ring thumb.
5. Opacity strip (optional): the colour fading to transparent over a checkerboard.
6. Channel row: a format select (Hex, RGB, HSL), the value field(s) in `code`, and opacity in %.
7. Swatches: rows of 32 circles (40 on touch): the app's palette ("Theme"), then recent colours; a "No colour" swatch shows the checkerboard; an Add swatch opens the spectrum.
8. Mode switch (touch): a segmented button, Swatches and Spectrum.
9. Readout: the colour's name when it has one ("Copper") and its hex.

## Variants and when to use
| Variant | Use for |
|---|---|
| Swatches only | Picking from a fixed palette: label colours, calendar colours. Most apps need only this. |
| Swatches and spectrum | Custom colours in design and theming tools: accents, chart series. |
| With opacity | When the target supports transparency: overlays, highlights. |
| Host panel | When the app wants the platform's own colour panel (macOS, Windows); offered as "More colours…" at the end of the swatches. |

Use Select or a segmented button when the choice is between three or four named colours; never ask users to type hex as the only way in.

## Specs
| Part | Pointer (popover) | Touch (sheet) |
|---|---|---|
| Container | `surface-container-high`, `radius-md` 12, `elevation-3`, 296 wide, `space-4` 16 padding, 4 below the trigger | modal bottom sheet (`surface-container-low`, `radius-xl` top), `space-4` 16 sides |
| Gap between blocks | `space-4` 16 | `space-4` 16 |
| Spectrum | 150 tall, full width, `radius-sm` 8 | 200 tall |
| Strips | 12 tall, `radius-full` | 16 tall |
| Thumbs | 20 ring: 2 `surface-container-lowest` inner ring, 1 `outline` outer ring, `elevation-1`; filled with the colour on the spectrum, hollow on strips | 28 ring |
| Channel fields | 32 tall, `radius-xs`, `divider` in `outline`, `code` 13/20 text, `space-2` 8 apart | 48 tall |
| Swatch | 32, `radius-full`, 1px inner hairline `on-surface` at 16% so light colours stay visible; `space-2` 8 apart | 40, rows `space-4` 16 apart, 5 columns spread |
| Selected swatch | 2px `on-surface` ring, 2 outside | same |
| Section labels | `label-medium` in `on-surface-variant` | same |
| Checkerboard | `outline-variant` and `surface-container-lowest`, 5px squares | same |
| Trigger | text field 40 dense, swatch 20 leading | 56 field or 40 button |

## States
- Swatch: rest, hover (`on-surface` layer at `state-hover`), focus (focus ring 2 outside), selected (the `on-surface` ring; never a colour change), disabled (`on-surface` 12% disc, no colour shown).
- Thumbs: rest, hover (grows to 24), focus (the focus ring, 4 outside), dragged (`elevation-2`).
- Channel field: rest, focus (2px `primary`), invalid (2px `error`, the last valid colour kept in the preview, "Enter 6 hex digits").
- Trigger: the field's states; Expanded while the panel is open.
- No colour: the checkerboard swatch selected; the trigger shows the checkerboard and "None".

## Behaviour
- Pointer: press or drag in the spectrum and strips; the colour updates live and the trigger previews it. A press on a swatch sets it and, in swatches-only mode, closes the panel.
- Keyboard: Tab moves between spectrum, hue, opacity, the channel fields and the swatch group. In the spectrum, arrows move saturation (left/right) and brightness (up/down) by 1%, with Shift by 10%; on strips, arrows by 1 degree or 1%, Page Up/Down by 10, Home/End to the ends. Swatches are one tab stop with arrow keys between them, Enter or Space to choose. Escape closes and keeps the colour committed so far; Cancel is not offered because every change is live and undoable.
- Typing: hex accepts 3, 6 or 8 digits, with or without "#"; RGB and HSL accept numbers per channel; the value commits on Enter or blur.
- Recent colours: the last 8 committed custom colours, newest first, per app.
- Contrast hint (optional): when the colour is used behind text, show "Low contrast with text" under the readout with the warning icon.
- Motion: the panel opens like a Flyout; thumbs move without animation while dragged and with `duration-short-3` `ease-standard` on keyboard steps. Reduced motion: none.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Ours in a popover (the WinUI ColorPicker idiom: spectrum, hue, hex); "More colours…" may open the system colour dialog. |
| macOS | Ours for swatches; "Show colours…" opens the shared `NSColorPanel`, which stays open as a floating panel and drives the selection. |
| Linux | Ours; GNOME's GtkColorChooser layout (palette first, custom with "+") is the model for swatches-first. |
| Android | The sheet as specified: swatches first, spectrum one tab away; 40 swatches, 28 thumbs. |
| iOS | `UIColorPickerViewController` (grid, spectrum, sliders, eyedropper) presented as a sheet, or ours for a fixed palette. |
| Web | Ours; `<input type="color">` only as a fallback where no custom picker fits. The EyeDropper API where available. |

## Accessibility
- The trigger is a Button (or Combobox) named by its label, with the colour as its value in words and hex ("Copper, #944A23"); HasPopup Dialog and Expanded.
- The panel is a Dialog labelled by the trigger's label.
- The spectrum is a 2D Slider exposed as two values ("Saturation 72%, brightness 70%"); hue and opacity are Sliders with value text ("Hue 214 degrees", "Opacity 100%").
- Swatches are a RadioGroup; each swatch is named by its colour name, or by its hex when it has none; "No colour" is named so.
- Selection is shown by a ring (shape), never by colour alone; every swatch has a hairline so a colour close to the surface is still visible.
- Contrast: labels and fields 4.5:1; thumbs 3:1 against any colour through their double ring.
- Targets: 32 swatches with 8 gaps reach 40 on pointer hosts; 40 swatches with 16 gaps on touch.
- Reduced motion: no thumb animation.

## Content
- Trigger label: what the colour is for: "Accent colour", "Label colour".
- Name palette colours in plain words ("Copper", "Slate"); show hex in upper case with "#".
- Section labels: "Theme", "Recent". Actions: "More colours…".
- Errors: "Enter 6 hex digits", "Enter a value from 0 to 255".

## e.ui today
`overlay.color_picker` is a `hit-target` swatch of `value` beside `control.slider`s for red, green, blue and optional alpha, each moving the whole `paint.Color` by 0.01. To reach this design:
- Replace the RGB sliders with the spectrum, hue and opacity strips, keep channels as typed fields (Hex, RGB, HSL), and add swatches (palette, recent, no colour) as the first mode.
- Make `width` widen the controls; today the tracks stay 120 wide whatever `width` says.
- Give the colour a readable value (name and hex) on the trigger and the panel; today the swatch has no semantics and no text value.
- Draw the checkerboard behind transparent colours; today the swatch shows whatever is behind it.
- Localise the channel names (fixed English strings today) and name swatches by colour.
- Put the picker behind a trigger in a popover or sheet, and offer the host panel on macOS and Windows.
