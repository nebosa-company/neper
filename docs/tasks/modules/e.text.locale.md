# e.text.locale — 21 of 21 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/text/locale.e` |
| plan row | layer 6, surface `planned`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/text/locale.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Extended pure algorithms, text and cryptography:** `e.algo.stat`, `e.algo.complex`, `e.algo.decimal`, `e.algo.bignum`, `e.algo.deflate`, `e.algo.linalg.matrix`, `e.algo.linalg.tensor`, `e.text.unicode`, `e.text.encoding`, `e.text.normalize`, `e.text.collate`, `e.text.regex`, `e.text.locale`, `e.crypto.hash`, `e.crypto.mac`, `e.crypto.kdf`, `e.crypto.aead`, `e.crypto.sign`, `e.crypto.kx`, `e.crypto.random` and `e.crypto.x509`. Preserve caller-owned allocation, caller-supplied entropy and the declared dependency edges. Cryptographic delivery requires published standard vectors, malformed-input cases and verification of every API that explicitly promises constant-time behavior.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.decimal` | partial | `lib/e/algo/decimal.e` | 2 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.time.calendar` | partial | `lib/e/time/calendar.e` | 4 |
| `e.text.collate` | source | `lib/e/text/collate.e` | 2 |
| `e.text.unicode` | partial | `lib/e/text/unicode.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Database = struct { state: *void }
type Locale = struct { state: *const void }
type NumberOptions = struct { minimum_fraction: u8, maximum_fraction: u8, grouping: bool, sign_always: bool }
type CurrencyOptions = struct { code: str, accounting: bool }
type DateStyle = enum u8 { Short, Medium, Long, Full }
error InvalidData
error NotFound
error Invalid

fn load(a: *mem.Arena, source: []const u8) -> (Database, err)
fn builtin(a: *mem.Arena) -> (Database, err)
fn version(db: *const Database) -> str
fn locale(db: *const Database, tag: str) -> (Locale, err)
fn canonical_tag(a: *mem.Arena, tag: str) -> (str, err)
fn format_i64(a: *mem.Arena, selected_locale: Locale, value: i64, options: NumberOptions) -> (str, err)
fn format_f64(a: *mem.Arena, selected_locale: Locale, value: f64, options: NumberOptions) -> (str, err)
fn parse_f64(selected_locale: Locale, value: str) -> (f64, err)
fn format_currency(a: *mem.Arena, selected_locale: Locale, value: decimal.Decimal, options: CurrencyOptions) -> (str, err)
fn format_date(a: *mem.Arena, selected_locale: Locale, value: calendar.DateTime, style: DateStyle) -> (str, err)
fn compare(selected_locale: Locale, a: str, b: str) -> i32
fn lower(a: *mem.Arena, selected_locale: Locale, value: str) -> (str, err)
fn upper(a: *mem.Arena, selected_locale: Locale, value: str) -> (str, err)
```

`builtin` uses the CLDR release pinned to the toolchain and reported by `version`;
`load` accepts explicit compatible data. Parsing consumes the whole input. Currency
codes are caller-supplied ISO 4217 identifiers. No process-global locale exists.

## Missing declarations

- [ ] `Database`
- [ ] `Locale`
- [ ] `NumberOptions`
- [ ] `CurrencyOptions`
- [ ] `DateStyle`
- [ ] `InvalidData`
- [ ] `NotFound`
- [ ] `Invalid`
- [ ] `load`
- [ ] `builtin`
- [ ] `version`
- [ ] `locale`
- [ ] `canonical_tag`
- [ ] `format_i64`
- [ ] `format_f64`
- [ ] `parse_f64`
- [ ] `format_currency`
- [ ] `format_date`
- [ ] `compare`
- [ ] `lower`
- [ ] `upper`

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

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/text/locale.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/text_locale/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 21.

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
