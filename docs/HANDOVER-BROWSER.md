# Browser (script side, WPT): handover

Written 2026-11-03. The numbers live in one place: `docs/browser-progress.html`, row 9.3 (script-side WPT) and row 9.2 (CSS reftests). This file holds what the numbers do not say: how the runs work, the traps, and what is left.

## Where the code is

| Area | File |
|---|---|
| DOM/web API prelude (JS embedded as `try str.push(b, "...\n")` lines) | `lib/e/web/dom_js.e` |
| Native glue the prelude calls (`N.*`) | `lib/e/web/script.e` |
| Native DOM tree, selectors, serializer | `lib/e/fmt/dom.e`, `lib/e/fmt/html.e` |
| Script-side WPT runner | `tests/browser/web/run.e`, `tests/browser/web/run.sh` |
| CSS reftest runner | `tests/browser/wpt/run.e` |

The prelude is JavaScript inside Neper strings. Edit it with a Node script that writes each JS line as `try str.push(b, "<line>\n")`, doubling backslashes and quotes with `String.fromCharCode`. Inline `\\t`-style escapes in shell, heredoc or Edit calls get mangled. A Node script written with the Write tool is the reliable way.

## Running the script-side WPT

Clone: `D:/data/wpt-script` (sparse; `git sparse-checkout add <dir>` to add one). Lists of test paths are plain text, one per line, relative to the clone.

```bash
cd /d/repos/neper
build/windows/neper-try.exe emit-executable tests/browser/web/run.e . x64 windows build/windows/web-run-js.exe --arena 6g
export WEB_RUN_EXE=$PWD/build/windows/web-run-js.exe     # same shell call as run.sh
bash tests/browser/web/run.sh --root /d/data/wpt-script --out /d/Temp/t5/OUT --jobs 2 --chunk 8 LIST
```

Prints `FILE path pass/total` per file. The per-chunk raw output stays in `--out`; `grep FAIL` there for the reasons.

Traps, all hit this session:

- `WEB_RUN_EXE` must be exported in the same shell call as `run.sh`. A fresh shell falls back to the stale default `web-run.exe`, and the result looks like a regression or a missing feature.
- Rebuild into `web-run-js.exe`; for a long comparison copy it to `web-run-cmp.exe` and run that, so rebuilding does not hit `os.Denied`. Kill stray `web-run-*.exe` and `xargs.exe` first.
- `--jobs 2`. More processes exhaust memory and fork.
- A file that ends `(no result)` at about 4855MB hit the interpreter memory limit (`it.mem_limit` in `run.e`, 5 GB). Its count is partial; the large reflection, Range and iframe-heavy files do this.
- Background runs die with the session. Restart them.
- Compare per file against the last full run, never against a partial one; do not overwrite the baseline from an interrupted run.
- Windows, bash and Node see different paths for temp files; keep working files under `D:/Temp/t5` and pass `D:/` style paths.

## State at the end of this stretch

Covered and compared against earlier runs (lists: DOM, custom-elements, shadow-dom, domparsing = 1152 files; `html/dom` = 229 files; `html/semantics/forms` = 514 files; sanitizer-api = 48 files). The last comparisons showed no real regressions; the losses were large files at the memory limit.

Implemented this stretch: Sanitizer API and the `setHTML` family, streaming HTML methods, scoped custom element registries, form-associated custom elements and `ElementInternals`, `Node.moveBefore`, `dataset`, attr-associated ARIA element references, enumerated ARIA reflection, `document.characterSet` from the meta charset, protocol handler validation, history URL rewriting rules, plus many reflection fixes.

## Open gaps

| Gap | Why it is left |
|---|---|
| Trusted Types (`trustedTypes`, `TrustedHTML`, the `createParserOptions` extension) | About a dozen sanitizer-api files report 0/0. Needs CSP enforcement on every sink and the `.headers` files, which the runner does not read. |
| Scoped registries, remaining cases | About 50 subtests: cross-realm nodes passed to a registry, define-upgrade order across documents, a few `initialize` cases. |
| `document` named properties (`document.test1`) | Needs the document object itself to be a Proxy. |
| SVG: `SVGElement` interface, animation (`SVGAnimatedString`, `beginEvent`) | No `SVGElement` exists, so SVG has no `.dataset` and `sanitizer-svg-animate` cannot pass. |
| `setFormValue` submission tests | Need form navigation into an iframe. |
| `OpaqueRange` (tentative) | Unimplemented API, needs layout geometry. |
| `moveBefore` state preservation | Focus, selection and running CSS animations are lost; it is a remove plus insert. |
| Tests needing `testdriver` actions | `get_computed_role`, `action_sequence`, user gestures. Cannot run headless. |
| `html/browsers/history` | Scroll position and cross-origin location tests need layout and real iframes. |
| innerText getter | Needs computed styles the headless runner does not have. |
| Encoding tests needing server headers | Charset set by `Content-Type`; the runner only has meta charset and the `encoding.py` shim. |

## Known deliberate trade-offs

- The runner parses the whole document before any script runs, so a custom element in the page is upgraded after parsing, with its attributes already present. `custom-elements/parser/parser-sets-attributes-*` loses subtests because of this.
- `aria-attribute-reflection.html` expects string semantics; `aria-attribute-reflection-enumerated.tentative.html` expects enumerated. The enumerated behaviour is implemented (it gains about 1,100 subtests; the string file loses 13).
- Every element now carries a `registry` slot. `ElementInternals-target-element-is-held-strongly.html` (100,000 elements) sits at the memory limit because of it.
