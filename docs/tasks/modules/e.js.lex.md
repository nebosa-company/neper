# e.js.lex — 3 of 41 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/js/lex.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/js/lex.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.data.list` | source | `lib/e/data/list.e` | 2 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
const T_EOF: u8 = 0u8
const T_IDENT: u8 = 1u8
const T_PUNCT: u8 = 2u8
const T_NUM: u8 = 3u8
const T_STR: u8 = 4u8
const T_TEMPLATE: u8 = 5u8
const T_REGEX: u8 = 6u8
const T_PRIVATE: u8 = 7u8
error SyntaxError
type Tok = struct { kind: u8, start: usize, end: usize, line: u32, nl: bool, text: str, flags: str, num: f64, big: bool, escaped: bool, legacy_octal: bool }
type Template = struct { cooked: []const str, raw: []const str, valid: []const bool, exprs: []const str }
type Lexer = struct { a: *mem.Arena, src: str, pos: usize, line: u32, template: Template, message: str, module: bool }
fn new_lexer(a: *mem.Arena, src: str) -> Lexer
fn is_id_start(c: u8) -> bool
fn is_digit(c: u8) -> bool
fn is_id_part(c: u8) -> bool
fn hex_value(c: u8) -> i32
fn fail(lx: *Lexer, message: str) -> err
fn put_cp(b: *str.Builder, c: u32)
fn line_terminator(src: str, at: usize) -> usize
fn skip_space(lx: *Lexer) -> (bool, err)
fn read_unicode_escape(src: str, pos: usize) -> (i64, usize)
fn put_unit(b: *str.Builder, src: str, c: i64, after: usize) -> usize
fn read_ident(lx: *Lexer) -> (str, bool, err)
fn digits_value(lx: *Lexer, radix: u32, pos: usize) -> (f64, bool, usize, err)
fn read_number(lx: *Lexer, t: *Tok) -> err
type Esc = struct { good: bool, next: usize, octal: bool }
fn read_escape(lx: *Lexer, b: *str.Builder, pos: usize, template: bool) -> Esc
fn read_string(lx: *Lexer, t: *Tok, quote: u8) -> err
fn read_template(lx: *Lexer, t: *Tok) -> err
fn punct_len(src: str, at: usize) -> usize
fn is_punct_start(c: u8) -> bool
fn next_token(lx: *Lexer) -> (Tok, err)
fn regex_at(lx: *Lexer, start: usize) -> (Tok, err)
fn id_part_at(s: str, at: usize) -> bool
fn id_part_cp(cp: u32) -> bool
fn id_start_cp(cp: u32) -> bool
fn newer_than_tables(cp: u32, cat: unicode.Category) -> bool
fn regex_may_start(src: str, from: usize, at: usize) -> bool
fn scalar_in(s: str, at: usize) -> u32
fn uspace_len(s: str, at: usize) -> usize
```

## Missing declarations

- [ ] `id_part_at`
- [ ] `newer_than_tables`
- [ ] `scalar_in`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/js/ast.e`
- `lib/e/js/b_array.e`†
- `lib/e/js/b_atomics.e`
- `lib/e/js/b_bigint.e`
- `lib/e/js/b_collections.e`
- `lib/e/js/b_control.e`
- `lib/e/js/b_date.e`
- `lib/e/js/b_json.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/js/lex.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/js_lex/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 3.

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
