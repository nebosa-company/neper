# e.fmt.url — 1 of 82 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/fmt/url.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/fmt/url.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.data.list` | source | `lib/e/data/list.e` | 2 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.net.uts46` | source | `lib/e/net/uts46.e` | 6 |
| `e.str` | source | `lib/e/str.e` | 1 |
| `e.text.utf8` | source | `lib/e/text/utf8.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Url = struct { scheme: str, username: str, password: str, host: str, has_host: bool, port: i32, path: str, opaque_path: bool, query: str, has_query: bool, fragment: str, has_fragment: bool }
error Failure
type State = enum u8 { SchemeStart, Scheme, NoScheme, SpecialRelativeOrAuthority, PathOrAuthority, Relative, RelativeSlash, SpecialAuthoritySlashes, SpecialAuthorityIgnoreSlashes, Authority, Host, Hostname, Port, File, FileSlash, FileHost, PathStart, Path, OpaquePath, Query, Fragment }
type EncodeSet = enum u8 { C0, Fragment, Query, SpecialQuery, Path, Userinfo, Component }
const EOF: u32 = 4294967295u32
type Buf = struct { data: []u8, len: usize }
fn buf_new(a: *mem.Arena, cap: usize) -> (Buf, err)
fn buf_byte(b: *Buf, c: u8)
fn buf_str(b: *Buf, s: str)
fn buf_text(b: *const Buf) -> str
fn buf_take(a: *mem.Arena, b: *const Buf) -> str
fn copy_str(a: *mem.Arena, s: str) -> str
fn is_alpha(c: u32) -> bool
fn is_digit(c: u32) -> bool
fn is_hex(c: u32) -> bool
fn lower_ascii(c: u32) -> u32
fn hex_val(c: u32) -> u32
fn hex_digit(n: u32) -> u8
fn in_set(c: u32, set: EncodeSet) -> bool
fn put_pct(b: *Buf, byte: u8)
fn put_encoded(b: *Buf, c: u32, set: EncodeSet)
fn put_scalar(b: *Buf, c: u32)
fn is_special_scheme(s: str) -> bool
fn default_port(s: str) -> i32
fn is_special(u: *const Url) -> bool
fn includes_credentials(u: *const Url) -> bool
fn forbidden_host(c: u32) -> bool
fn forbidden_domain(c: u32) -> bool
fn pct_decode_utf8(a: *mem.Arena, s: str) -> str
fn lower_ascii_copy(a: *mem.Arena, s: str) -> str
fn all_ascii(s: str) -> bool
fn has_xn_label(s: str) -> bool
fn domain_to_ascii(a: *mem.Arena, domain: str) -> (str, bool)
fn ipv4_number(s: str) -> (u64, bool)
fn split_dots(a: *mem.Arena, s: str) -> []const str
fn list_of_str(a: *mem.Arena) -> list.List[str]
fn ends_in_number(a: *mem.Arena, domain: str) -> bool
fn parse_ipv4(a: *mem.Arena, input: str) -> (str, bool)
fn put_decimal(b: *Buf, v: u64)
fn put_hex16(b: *Buf, v: u32)
fn parse_ipv6(a: *mem.Arena, input: str) -> (str, bool)
fn parse_host(a: *mem.Arena, input: str, opaque: bool) -> (str, bool)
fn is_windows_drive_letter(s: str) -> bool
fn is_normalized_drive_letter(s: str) -> bool
fn starts_with_drive_letter(cps: []const u32, at: usize) -> bool
fn is_single_dot(s: str) -> bool
fn is_double_dot(s: str) -> bool
type Parser = struct { a: *mem.Arena, scheme: str, username: str, password: str, host: str, has_host: bool, port: i32, segs: list.List[str], opaque_path: bool, opaque_text: Buf, query: str, has_query: bool, fragment: str, has_fragment: bool }
fn from_parser(p: *const Parser) -> Url
fn join_path(p: *const Parser) -> str
fn path_segments(a: *mem.Arena, path: str) -> list.List[str]
fn to_parser(a: *mem.Arena, u: *const Url) -> Parser
fn shorten_path(p: *Parser)
fn push_seg(p: *Parser, s: str)
fn decode_input(a: *mem.Arena, input: str) -> ([]u32, err)
fn is_c0_or_space(c: u32) -> bool
fn is_tab_newline(c: u32) -> bool
fn run(a: *mem.Arena, input_text: str, base: *const Url, has_base: bool, p: *Parser, has_override: bool, override: State) -> bool
fn zero_buf(a: *mem.Arena, cap: usize) -> Buf
fn new_parser(a: *mem.Arena) -> Parser
fn parse(a: *mem.Arena, input: str, base: *const Url, has_base: bool) -> (Url, err)
fn parse_against(a: *mem.Arena, input: str, base_text: str) -> (Url, err)
fn serialize_authority(buf: *Buf, u: *const Url)
fn href(a: *mem.Arena, u: *const Url, exclude_fragment: bool) -> str
fn origin(a: *mem.Arena, u: *const Url) -> str
fn protocol(a: *mem.Arena, u: *const Url) -> str
fn join2(a: *mem.Arena, x: str, y: str) -> str
fn host_port(a: *mem.Arena, u: *const Url) -> str
fn port_text(a: *mem.Arena, u: *const Url) -> str
fn search(a: *mem.Arena, u: *const Url) -> str
fn hash(a: *mem.Arena, u: *const Url) -> str
fn cannot_have_credentials_or_port(u: *const Url) -> bool
fn set_protocol(a: *mem.Arena, u: *const Url, value: str) -> Url
fn set_username(a: *mem.Arena, u: *const Url, value: str) -> Url
fn set_password(a: *mem.Arena, u: *const Url, value: str) -> Url
fn set_host(a: *mem.Arena, u: *const Url, value: str) -> Url
fn set_hostname(a: *mem.Arena, u: *const Url, value: str) -> Url
fn set_port(a: *mem.Arena, u: *const Url, value: str) -> Url
fn set_pathname(a: *mem.Arena, u: *const Url, value: str) -> Url
fn strip_trailing_spaces(u: *Url)
fn set_search(a: *mem.Arena, u: *const Url, value: str) -> Url
fn set_hash(a: *mem.Arena, u: *const Url, value: str) -> Url
```

## Missing declarations

- [ ] `zero_buf`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/fmt/arrow.e`
- `lib/e/fmt/asn1.e`
- `lib/e/fmt/avro.e`
- `lib/e/fmt/bincode.e`
- `lib/e/fmt/bmp.e`
- `lib/e/fmt/brotli.e`‡
- `lib/e/fmt/bson.e`
- `lib/e/fmt/bzip2.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/fmt/url.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/fmt_url/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 1.

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
