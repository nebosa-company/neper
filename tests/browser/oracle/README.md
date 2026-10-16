# Vaper (Dart) oracle for the Neper browser

Frozen 2026-10-16 from the Dart/Flutter Vaper at git tag `dart-oracle-final`
(repo `D:\repos\vaper`, tool commit `8e0c4e9`). Vaper is not continued; these
files are what the Neper browser (`docs/browser-progress.html`, queue L166 to
L171) is compared against. Tracker item 0.3.

Each site directory holds:

- `store/` every HTTP response the Dart engine fetched while loading the page
  live (`manifest.json` + one `<key>.bin` body per request; key is a 64-bit
  FNV-1a of `"GET <url>"`, which can print with a leading `-`). Replaying
  from it needs no network.
- `golden/render.png` the page painted by Dart's engine from the store at
  1900 px wide, capped at 2400 px high; `nodes.txt` the snapshot node dump;
  `displaylist.txt` one line per display item; `summary.txt` counts and the PNG
  hash; `misses.txt` URLs the page asked for that were not in the store
  (answered 404).

| site | URL | nodes | store misses |
|---|---|---|---|
| hn | https://news.ycombinator.com | 431 | 0 |
| example | https://example.com/ | 3 | 0 |
| wikipedia | https://en.wikipedia.org/wiki/Comparison_of_web_browsers | 12317 | 0 |
| mdn | https://developer.mozilla.org/en-US/docs/Web/CSS | 281 | 0 |
| craigslist | https://www.craigslist.org/about/sites | 2627 | 0 |
| abv | https://www.abv.bg | 79 | 77 |

Determinism: each golden was produced twice from its store and the two PNGs
are byte-identical. abv.bg's JavaScript requests URLs that vary per run, hence
its misses; Dart settles only ~79 of the ~272 nodes the app shows (known limit
in `vaper/docs/render-tool.md`). Treat its golden as a coarse reference.

Caveats: fonts came from the Windows system (`arial.ttf`, `segoeui.ttf`), so
glyph shapes only match on a similar font; compare structure and geometry with a
tolerance, not bit for bit. The jQuery 3.5.1 page set is not captured yet.

Licensing: the stores contain third-party pages and assets captured for
local conformance testing. Check each site's terms before publishing this
directory outside the project.

Regenerate or add a site (from `D:\repos\vaper\packages\vaper_layout`, quickjs
dll staged as for `render_url_tool`; `git checkout dart-oracle-final` first):

    flutter test test/oracle_capture_tool.dart --dart-define=MODE=record  --dart-define=URL=<url> --dart-define=STORE=<dir>/store
    flutter test test/oracle_capture_tool.dart --dart-define=MODE=replay  --dart-define=URL=<url> --dart-define=STORE=<dir>/store --dart-define=OUT=<dir>/golden
