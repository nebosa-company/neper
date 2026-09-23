# Image

An image shows a picture (a screenshot, a preview, a photo or an illustration) in a box of a fixed aspect ratio, with a placeholder while it loads and a clear state when it cannot.

## Anatomy
1. Frame: the box, sized by width and aspect ratio, `radius-md`, clipping its content.
2. Picture: the decoded image, fitted by cover or contain.
3. Ground: `surface-container-highest`, visible behind a contained picture, a transparent picture, and every non-loaded state.
4. Status content (non-loaded states): an icon, a `body-small` message and an optional Retry text button, centred.
5. Optional caption: `body-small` `on-surface-variant`, `space-2` below.
6. State layer and focus ring: only when the image is pressable (opens a viewer).

## Variants and when to use
| Variant | Shape | Use for |
|---|---|---|
| Rounded | `radius-md` | Thumbnails, previews and screenshots in content. The default. |
| Full-bleed | `radius-none` | Card media, hero images and headers that meet the container's edge; the container clips the corners. |
| Contain | ground shows around it | Screenshots, diagrams and documents that must not be cropped. |
| Cover | crops to fill | Photos and illustrations where the centre matters and edges do not. |

Use Icon for a symbol, Avatar for a person or account, Canvas for something drawn at run time (a chart, a live preview).

## Specs
| Part | Value |
|---|---|
| Aspect ratios | 16:9 (previews), 3:2, 4:3, 1:1 (thumbnails); set one, never a free height |
| Radius | `radius-md` 12 standalone; `radius-sm` 8 under 48 wide; `radius-none` full-bleed |
| Ground | `surface-container-highest` |
| Status icon | `icon-md` 24 (`icon-lg` 36 when the frame is 120 wide or more), `on-surface-variant` |
| Status text | `body-small` 12/16, `on-surface-variant`, `space-1` below the icon, max 2 lines |
| Retry | Text button, small |
| Caption | `body-small`, `on-surface-variant`, `space-2` below, start aligned |
| Hover layer | `on-surface` at `state-hover` over the picture |
| Focus | ring 3 px `focus-ring`, 2 px outside the frame |
| Resolution | decode at the frame's size × the display scale; never upscale a thumbnail past 2× |

## States
- Loading: a `nu-skeleton` ground the size of the frame; with a known dominant colour or a blurred thumbnail, show that instead. The picture fades in over `duration-short-4` with `ease-standard`.
- Loaded: the picture.
- Error: `error` icon, "Couldn't load" and Retry. Never show a broken-image glyph.
- Empty (no image): the `image` icon and "No preview".
- Hover and pressed (pressable only): `state-hover` / `state-pressed` layer of `on-surface`.
- Focus (pressable only): the focus ring.
- Selected (in a grid): see Grid view; the frame insets by 8 and shows a check.

## Behaviour
- The frame reserves its space before the picture arrives: layout never shifts on load.
- Pressable images open a viewer (Enter or Space; double-click on desktop is not required).
- Pinch and scroll-wheel zoom belong to the viewer, not to the image.
- Images below the fold decode lazily; decoding never blocks input.
- Animated images play once, then stop on the first frame, and never autoplay with reduced motion; a play button starts them.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Decode through WIC; honour the display scale per monitor; drag an image out to Explorer to save it. |
| macOS | Decode through ImageIO with the display's colour profile (Display P3); Quick Look (Space) opens a pressable image; drag out to Finder. |
| Linux | Decode in-process; colour management follows the compositor where available, otherwise assume sRGB. |
| Android | Long press opens a menu (Save image, Share); the picture follows the system's data saver by loading thumbnails only. |
| iOS | Long press shows the context menu with a preview (Save to Photos, Copy, Share); Live Text on images where the app allows it. |
| Web | `<img>` with `width`, `height` and `alt`; `loading="lazy"`, `decoding="async"`; `srcset` for scale. |

## Accessibility
- Informative images: role Image with an alt text that says what matters in the picture ("Build farm, rack 3, two nodes offline"), not the file name.
- Decorative images: hidden from the tree (empty alt).
- A pressable image is a Button named by its action ("Open screenshot") with the alt as description.
- Error and empty states expose their message; Retry is a Button.
- Status content meets 4.5:1 on `surface-container-highest`; the focus ring meets 3:1.
- Reduced motion: no fade-in, no autoplay.

## Content
- Alt text: one sentence, sentence case, no "Image of". Put detail in the caption if everyone needs it.
- Captions: sentence case, no trailing period for a label-style caption ("Build farm, rack 3"); full sentences end with a period.
- Error text: "Couldn't load", with the action "Retry". No codes in the frame.

## e.ui today
`control.image` draws a caller-uploaded texture at exactly `width` by `height`, fitted by `widget.Fit` (Fill, Contain, Cover, None), under an Image-role node that is hidden when `label` is empty. To reach this design:
- Add the `radius-md` frame with clipping and the `surface-container-highest` ground; today a contained texture leaves the rest of the box empty and square.
- Take an aspect ratio with a width instead of both dimensions, so the frame reserves space before the texture exists.
- Add the loading, error (with Retry) and empty states; the caller has no way to say the texture is not ready.
- Add an optional pressable form with state layers and the focus ring, reported as a Button.
- Keep the empty-label-is-decorative rule; it is right.
