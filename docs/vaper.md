# vaper → neper migration plan

Status: plan. Source: `d:\repos\vaper` (Dart/Flutter browser, engine 0.1.0). Target: neper `lib/e` (pure stdlib), `lib/x` (drivers), tools.

Rule: pure + deterministic + fixture-testable → `e.*`; socket/credential/platform → `x.*`; app workflow → tool/recipe, never `e.*`. Isolate-safe pure Dart only: no `dart:ui`/Flutter/`dart:ffi` in `e.*`. No weaker duplicate crypto (vaper `siphash/hkdf/chacha` carry no RFC vectors; neper already covers them). `docs/progress.html` stays the only readiness record; this file is the work plan.

## 0. Ground rules

- Fenced modules, arena-first allocating calls, `snake_case`, per-module fixtures. Every port carries vaper's test vectors forward (tokenizer, WPT, value, net-policy suites).
- Spec-backed: WHATWG/W3C/RFC sections named per item; approximations flagged (PSL subset, IDNA subset — both skipped in favour of neper supersets).
- Unverified overlaps are diffed before landing: `ui/animation.e` vs `interpolate.dart`, `e.net.snapshot` vs `render_tree_snapshot.dart`.

## 1. Algo (port the CSS front-end, skip the DOM-bound rest)

| # | vaper source | neper home | Backlog | Notes / acceptance |
|---|---|---|---|---|
| A1 | `engine_core/css/css_tokenizer.dart` (Syntax-3 §4, offsets, never-throw recovery), `css_syntax.dart` (§5 grammar), `selector_parser.dart` + `selector.dart` (Selectors-4, An+B, is/where/not/has, specificity) | `e.fmt.css` / `e.text.css` | L038 | Pure, deterministic, vector-backed. Neper `css.e` has no tokenizer or grammar. Fixtures: token streams, grammar recovery, selector parse + specificity. |
| A2 | `vaper_css_values/value.dart` (`parseColor` incl. lab/light-dark, `parseLength` with calc/min/max/clamp/… reduced to px offset, `toPx`) + `interpolate.dart` (number/color/2D-matrix lerp, cubicBezier) | `e.gfx.color` + `e.ui.animation` | L039 | Pure, heavily vector-tested. Diff `ui/animation.e` first; port on no-overlap. |
| A3 | `css/container_query.dart` (Kleene and/or/not, scope proximity), rule-index buckets + origin/importance/specificity/order/proximity sort, right-to-left matcher (adapted off `package:html`), a11y role + accName precedence | `e.algo.logic` + `e.ui.accessibility` | L040 | Logic kernels only, no DOM. |
| — | `style_resolver.dart` (full, DOM-bound), `snapshot_builder.dart`, `layout_engine.dart` (~6810, Paragraph-bound), `paint/*`, `protocol/*` (internal model) | skip / shape only | — | Dispatch and snapshot-ABI notes at most; layout has no neper counterpart by design. |
| — | `net/siphash.dart`, `hkdf.dart`, `chacha20_poly1305.dart` | skip | — | Vector-weak duplicates of covered `e.crypto.*` / `e.algo.hash`. |
| — | `net/brotli.dart`, `idna.dart` | skip | — | Covered (`e.fmt.brotli`, `e.net.idna` is a superset). |
| — | `js/quickjs*.dart`, `native/` | never | — | FFI/DLL-bound. |

Order: A1 → A2 → A3.

## 2. Formats (one real gap)

Neper already covers HTML decode, Brotli, IDNA (superset), json/yaml/csv/xml.

| # | vaper source | neper home | Backlog | Notes / acceptance |
|---|---|---|---|---|
| F1 | `net/woff_decoder*.dart` (WOFF1 → sfnt via inflate) + `net/woff2_decoder.dart` (pure container + brotliDecode, transform reversal, checksum fixup, ttcf rejected) | `e.fmt.woff` / `e.fmt.woff2`, decode-only | L043 | Reuse `e.fmt.brotli` and inflate. Land only if a font pipeline is wanted. |

## 3. Drivers (policy cores now, sockets later or never)

| # | vaper source | neper home | Backlog | Notes / acceptance |
|---|---|---|---|---|
| D1 | `net/http_cache.dart` (RFC9111 freshness/age/conditional), `cookie_jar.dart` (RFC6265 + prefixes/CHIPS/caps; neper encodes only), `private_network.dart` (IP-literal SSRF classifier), `cors.dart`, `csp_policy.dart` (response parse; neper builds only), `filter_list_parser.dart` (ABP subset) | `e.net.http` policy + `x.*` stores | L046 | Pure policy; appdor SSRF pinning rides along. |
| D2 | `http2_resource_loader.dart`, `websocket.dart` socket binding, `secure_cache.dart`, `caching/cached_loader.dart` I/O, `engine_isolate.dart` pipeline | defer to `x.*` / shape only | — | Neper `ws.e` already does frames-over-caller-I/O; loader interface and per-tab pipeline are architecture notes. |
| — | `layout/paint/render` (dart:ui/Flutter), `apps/vaper` chrome | never in `e` | — | Easing/dispatch notes only. |

Order: D1 → D2 (deferred).

## 4. Explicitly out of scope

Full layout/paint/render ports; JS execution; encrypted-cache driver (primitives covered); GoTrue/Kong-class services (vaper has none — noted for contrast with appdor); H2/QUIC socket work (no neper socket layer for it yet).

## 5. Acceptance per landing

- Fixture-driven goldens in-repo incl. W3C/RFC vectors and error/recovery cases; deterministic reruns; no `dart:ui` in `e.*` tests (fake measurement/canvas only).
- No `unsafe`, no new native deps, no network in `e.*` tests.
- Docs: module API rows in `docs/module-apis.md` + `docs/modules.json` surface flags; this plan file tracks intent, `docs/progress.html` (generated) tracks readiness.

F1 landed (D2346): `e.fmt.woff` (`lib/e/fmt/woff.e`) and `e.fmt.woff2` (`lib/e/fmt/woff2.e`), differential against `woffToSfnt`/`woff2ToSfnt` over 480 cases (`scripts/woff_vectors.mjs`).
