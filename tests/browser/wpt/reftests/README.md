# WPT CSS reftests (vendored)

These `*.html` / `*.xht` files are **reftests** from the Web Platform Tests
project, vendored from:

- https://github.com/web-platform-tests/wpt (`css/` subtrees)

WPT is licensed under the 3-Clause BSD License (© the W3C and WPT
contributors). Only **self-contained** reftests are kept here — inline styles
only, no `<script>`, no external stylesheet (other than the Ahem font), no
external images/iframes — because Vaper's offline reftest runner reads only
inline `<style>`. `tool/fetch_wpt_reftests.dart` performs the fetch + filter.

`manifest.txt` lists each pair: `test.html | reference.html | match|mismatch`.

Consumed by `wpt_reftest_test.dart`, which renders the test and reference
through Vaper's pipeline and pixel-compares them — a real **rendering**
conformance baseline (vs. the html5lib corpus, which tests only the parser
front-end). Baseline 2026-06-18: **69 / 122 (56.6%)**.
