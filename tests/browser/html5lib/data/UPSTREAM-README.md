# html5lib tree-construction corpus

The `*.dat` files (except `basic.dat`) are the official HTML parsing
tree-construction tests, vendored from:

- https://github.com/html5lib/html5lib-tests (`tree-construction/`)

They are licensed under the MIT License (© the html5lib contributors). Each
file holds many cases in the form:

```
#data
<input html>
#errors
…
#document
| <html>
|   …
```

`basic.dat` is a small hand-written file kept for the original structural
`html5lib_test.dart`.

These are consumed by:
- `test/conformance/html5lib_tree_construction_test.dart` — full-corpus
  baseline (serializes the parsed tree and compares to `#document`).
- `tool/html5lib_conformance.dart` — ad-hoc pass-rate / failure diagnostic.

They validate the **parser front-end** (`package:html`) that Vaper wraps, not
Vaper's own layout/CSS.
