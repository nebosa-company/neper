# e.text.regex — 11 of 11 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/text/regex.e` |
| plan row | layer 2, surface `planned`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/text/regex.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Extended pure algorithms, text and cryptography:** `e.algo.stat`, `e.algo.complex`, `e.algo.decimal`, `e.algo.bignum`, `e.algo.deflate`, `e.algo.linalg.matrix`, `e.algo.linalg.tensor`, `e.text.unicode`, `e.text.encoding`, `e.text.normalize`, `e.text.collate`, `e.text.regex`, `e.text.locale`, `e.crypto.hash`, `e.crypto.mac`, `e.crypto.kdf`, `e.crypto.aead`, `e.crypto.sign`, `e.crypto.kx`, `e.crypto.random` and `e.crypto.x509`. Preserve caller-owned allocation, caller-supplied entropy and the declared dependency edges. Cryptographic delivery requires published standard vectors, malformed-input cases and verification of every API that explicitly promises constant-time behavior.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.text.utf8` | source | `lib/e/text/utf8.e` | 2 |
| `e.text.unicode` | partial | `lib/e/text/unicode.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 2 may depend on layers [0, 1, 2].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Regex = struct { state: *void }
type Match = struct { start: usize, end: usize }
type Captures = struct { whole: Match, groups: []const Match }
type Options = struct { case_insensitive: bool, multiline: bool, dot_matches_newline: bool }
error InvalidPattern
error TooComplex

fn compile(a: *mem.Arena, pattern: str, options: Options) -> (Regex, err)
fn is_match(r: *const Regex, text: str) -> bool
fn find(r: *const Regex, text: str, from: usize) -> (Match, bool)
fn captures(a: *mem.Arena, r: *const Regex, text: str, from: usize) -> (Captures, bool, err)
fn replace_all(a: *mem.Arena, r: *const Regex, text: str, replacement: str) -> (str, err)
```

The accepted syntax is regular only: no backreferences, recursion or lookbehind.

## Missing declarations

- [ ] `Regex`
- [ ] `Match`
- [ ] `Captures`
- [ ] `Options`
- [ ] `InvalidPattern`
- [ ] `TooComplex`
- [ ] `compile`
- [ ] `is_match`
- [ ] `find`
- [ ] `captures`
- [ ] `replace_all`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/text/collate.e`
- `lib/e/text/encoding.e`
- `lib/e/text/io.e`
- `lib/e/text/normalize.e`‡
- `lib/e/text/template.e`
- `lib/e/text/unicode.e`‡
- `lib/e/text/utf8.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/text/regex.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/text_regex/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 11.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
