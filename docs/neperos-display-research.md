# NeperOS display: how other systems carry a screen-sized wallpaper

Research for C115 (the Pixel 9 Pro screen, 1280 x 2856, with the Neper crater wallpaper). The target
panel is 20:9, about 495 PPI, 3.65 megapixels: one BGRA frame is 14.6 MB. The source image
(`neper-crater.jpg`) is 688 x 1552, so it has to be *up*-scaled to the panel, not down-scaled; the
rules below apply either way.

## What the platforms do

- **Android decodes to the size it will show.** `BitmapFactory` reads the bounds first
  (`inJustDecodeBounds`), picks a power-of-two `inSampleSize` that keeps the result at or above the
  requested size, and decodes that, because a bitmap's memory is width x height x 4 regardless of
  how small it is drawn ([Loading Large Bitmaps Efficiently](https://developer.android.com/topic/performance/graphics/load-bitmap)).
  `WallpaperManager` advertises a *desired minimum* width and height so an app can hand it a
  wallpaper cropped to the display
  ([WallpaperManager](https://developer.android.com/reference/android/app/WallpaperManager)).
- **The wallpaper is one GPU texture in its own layer.** SystemUI's `ImageWallpaper` draws the crop
  as a single texture through EGL, and a crop larger than the GPU's maximum texture size made
  SystemUI crash-loop, so AOSP validates the crop against it when generating it
  ([Validate wallpaper dimension while generating crop](https://android.googlesource.com/platform/frameworks/base/+/767039e%5E%21/)).
- **Wayland desktops treat it as a separate surface.** `swaybg` and `wallr` are ordinary clients on a
  background layer; they offer five fits (fill/cover, fit/contain, stretch, centre, tile) and decode
  once, caching the result ([swaybg](https://www.linuxlinks.com/swaybg-wallpaper-utility-wayland-compositors/),
  [wallr](https://docs.rs/crate/wallr/0.3.1)). The compositor then only recomposites damage.
- **GNOME's shell keeps the sharpest level that is still big enough.** For a wallpaper larger than the
  monitor, Mutter mipmaps it down but limits the levels to the smallest one at or above the monitor
  size, so detail is not lost to a needless extra halving
  ([mutter MR 1003](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/1003)). A mip level is a
  2 x 2 box average of the one above
  ([mipmapping](https://www.shawnhargreaves.com/blog/texture-filtering-mipmaps.html)).

## What that means here

1. **Resample once, offline, to the panel.** The build converts the source to a PNG of exactly
   1280 x 2856 (cover fit, a Lanczos or box filter), so the device never rescales a 3.6 MP image and
   the shell draws it 1:1. This is Android's "decode to the size you will show" taken to its end.
2. **The wallpaper is a static bottom layer.** It is decoded and uploaded once; later frames change
   only the shapes above it, and the compositor's flush is damage-only (it already is, since D2164).
3. **Check sizes against the renderer, not the hardware.** The CPU renderer's per-frame buffers
   scale with width x height (about 12 bytes a pixel, 44 MB at this size), and the GPU pool, shared
   frame and window region all have fixed ceilings. Validate the surface against them when the
   window opens and fail with a message, the way AOSP checks the texture limit.
4. **Ship the pixels in the initrd.** The C106 filesystem stores a file in one 512-byte block, so the
   wallpaper travels as an archive entry that a loader reads through a kernel call (D2199).
5. **Icons are vectors.** App and top-bar icons are `.svg` files drawn through `e.gfx.svg` at the size
   asked for, so one file serves the 1x launcher and any later density.
