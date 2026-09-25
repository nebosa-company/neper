# Landing page maintenance

The landing page is a static GitHub Pages site. Its entry point is
`docs/index.html`; shared UI styles and previews live under `docs/ux`, and public
media lives under `docs/gtm`. There is no front-end build step: the HTML, CSS,
JavaScript, JSON, Markdown catalogues, and media are published directly.

Use this guide when a measured claim or catalogue total changes. The page keeps
some totals beside the data they validate, so changing only the visible number
can make a modal fail to load.

## Sources of truth

| Claim | Current value | Source | Page/video locations |
| --- | ---: | --- | --- |
| Hello compile time | 32 ms | A fresh release build of the exact hello program shown on the page | `docs/index.html`, `docs/video/neper-capabilities.jsx`, narration |
| Hello executable size | 3,648 bytes | The resulting native artifact's byte length | `docs/index.html`, `docs/video/neper-capabilities.jsx`, narration |
| Standard-library modules | 344 | Unique `tiers[].modules` entries in `docs/modules.json` | Library statistic, module modal title, `loadModules` expected count |
| Function signatures | 7,963 | Lines beginning with `fn ` in `docs/module-apis.md` | Video library scene and narration |
| Standard-library algorithms | 1,232 | Implementable `e.*` and `pacman.*` entries in `docs/algos.md` | Library statistic, algorithm modal title, `loadAlgorithms` expected count, video and narration |
| Native UI controls | 112 | Component directories in `docs/ux/components`, mirrored by `controlGroups` in `docs/index.html` | Library statistic, control modal title, `loadControls` expected count, video and narration |

Other numeric claims, especially `1M+ LOC`, `< 1 sec`, test totals, and the 26
LLM-native features, must follow the same rule: update them only from their
benchmark, test, or feature inventory—not by estimating from the old copy.

## Recount the catalogues

Run these from the repository root. They require only Python and `rg`.

```powershell
# Modules
python -c "import json; d=json.load(open('docs/modules.json', encoding='utf-8')); print(len({m for t in d['tiers'] for m in t['modules']}))"

# Public function signatures
rg -c '^fn ' docs/module-apis.md

# Algorithms accepted by the landing-page parser
python -c "print(sum(x[:1].isdigit() and ('→ '+chr(96)+'e.' in x or '→ '+chr(96)+'pacman.' in x) for x in open('docs/algos.md', encoding='utf-8')))"

# UI controls
python -c "from pathlib import Path; print(sum(p.is_dir() for p in Path('docs/ux/components').iterdir()))"
```

For modules and algorithms, the modal reads the source file at runtime. Update
the visible statistic, modal heading, and the expected count passed to
`renderCatalog`. For controls, also add or remove the control name in the
appropriate `controlGroups` category. The component-directory count and the
sum of `controlGroups` must agree.

## Refresh compile time and executable size

1. Use the exact hello source displayed in the `#syntax` terminal. Keep its
   source and output identical in `docs/index.html` and the video composition.
2. Build with the current release compiler for the advertised target. Record
   the Neper commit, target, build mode, host, and whether the timing is cold or
   warm in the change description so the next result is comparable.
3. Use one declared timing method consistently. Prefer the compiler's own
   elapsed build time; otherwise measure only the build command, not editor or
   test startup.
4. Read the generated artifact's exact byte length—do not use filesystem “size
   on disk.” On PowerShell use `(Get-Item PATH_TO_EXE).Length`; on Linux use
   `stat -c%s PATH_TO_BINARY`.
5. Repeat enough runs to reject an obvious outlier and publish the median. Keep
   the raw measurements in the commit or pull-request description.

The visible terminal uses `msec` and ungrouped bytes; the video cards use `ms`
and grouped bytes. Preserve those display formats.

## Update the page

Edit `docs/index.html` and check all of these surfaces:

- visible statistics and terminal output;
- modal titles and `renderCatalog(..., expected)` counts;
- `controlGroups`, module-description overrides, and catalogue category copy;
- SEO description, Open Graph, Twitter, and JSON-LD claims near the top;
- accessibility labels when the meaning—not merely the number—changes.

Find every old numeric occurrence before finishing:

```powershell
rg -n '32 msec|32 ms|3648|3,648|344|7,963|1,232|112|1M\+|< 1 sec' docs/index.html docs/video
```

Replace the values in that command with the old values during future refreshes.
This catches prose, captions, narration, and validation constants that a visual
scan misses.

## Refresh the video

The editable records are:

- `docs/video/neper-capabilities.jsx` — Higgsedit composition, on-screen copy,
  timing, syntax highlighting, and poster render;
- `docs/video/neper-capabilities-narration.json` — narration text, time windows,
  voice choice, and generated job IDs;
- `docs/video/voice.lock` — locked Gideon preset ID;
- `docs/gtm/logo/neper-icon.png` — the approved Neper logo;
- `docs/gtm/ui-library-showcase.png` — the Forge image used by the library scene.

Keep Gideon as the voice and the pronunciation note `NEE-per`. When spoken data
changes, regenerate the affected narration block rather than the whole voiceover,
record the new job ID, rerender the composition, and replace both published files:

- `docs/gtm/neper-capabilities.mp4`
- `docs/gtm/neper-capabilities-poster.png`

The Higgsedit project expects the logo and showcase assets as `neper-icon.png`
and `forge.png`. After rendering, watch the final MP4 from start to finish and
check voice timing, pronunciation, on-screen text, syntax highlighting, clipping,
captions/on-screen explanations, logo, and the final frame. Do not approve from
the source composition alone.

## Preview and publish

Serve the `docs` directory so runtime `fetch()` calls work:

```powershell
python -m http.server 8765 --directory docs
```

Open `http://127.0.0.1:8765/` and verify desktop and narrow layouts, all three
Explore modals, outside-click and X-button closing, video playback, keyboard
focus, links, and the custom cursor. Also check the browser console for failed
catalogue counts or missing assets.

Before committing:

```powershell
git diff --check -- docs/index.html docs/video docs/gtm docs/landing-page-maintenance.md
git diff -- docs/index.html docs/video docs/landing-page-maintenance.md
```

GitHub Pages publishes from `docs`. Keep `docs/CNAME` exactly `neper.dev`; DNS
and the GitHub Pages custom-domain setting are external configuration and should
not be replaced by generated site files.
