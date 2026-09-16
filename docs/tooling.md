# neper tooling protocol — version 1

Status: normative companion to `docs/spec.md` §13–§14. Nothing here requires an
implementation before the compiler work begins; it fixes the interface that every
implementation and harness must share.

## 1. Version and stream envelope

On every finite command, `--json` means UTF-8 JSON Lines on stdout and no human text
on stdout. `neper dap` is the sole exception: it uses DAP's own framed JSON transport
and rejects `--json` and `--absolute-paths`. The first
line is always this header, with keys in the shown order:

```json
{"schema":"neper-stream","version":1,"record":"header","command":"index","tool_version":"0.1.0","language_version":"0.1","grammar_revision":3}
```

Every later object has a `record` discriminator. Diagnostics are records in the same
stream; stderr is empty unless the process cannot initialize JSON output, in which
case it contains one ASCII line and the process exits 2. A command emits its final
`result` record last, including on source or option failure. Unknown record-level
keys are forbidden at version 1. `result.data` is the sole extension map: its
command-specific scalar keys are described with that command and unknown keys there
must be ignored. Integers outside JSON's exactly representable range are decimal
strings.

`neper info --json` emits the header followed by one `info` record and one successful
`result`. `info` contains `tool_version`, `language_profiles`, `commands`,
`host_target`, `build_targets`, `cpu_levels`, and `features`, with every collection
sorted by UTF-8 bytes. Each `language_profiles` entry contains `language_version`,
`grammar_revision`, `stream_version`, and `experimental`; versions are related by
that entry rather than by parallel-array position. This is the capability query;
harnesses never scrape `--help`.

`--language-version MAJOR.MINOR` selects one advertised version and defaults to the
newest non-experimental version. An unsupported value is `E-CLI-9999` before source
is read. The selected version fixes its grammar revision, stream versions and
conformance corpus; a build manifest records all three.

## 2. Sources and spans

A source identifier is:

```json
{"root":"project-src","path":"parse/expr.e"}
```

`root` is one of `project`, `project-src`, `project-lib`, `toolchain-lib`, `operand`,
`generated`, or `external`. `project` addresses non-neper inputs relative to the
project root; `external` uses a generator-supplied stable URI as `path`. Every other
`path` uses `/`, is relative to that root, contains no `.` or `..`
segment, and is NFC-normalized UTF-8. For a file outside all roots, `operand` uses
the file's basename; a stdin source uses the normalized `--path` spelling. Only one
such operand exists in a command, so that identity is unambiguous. Machine output contains no absolute
path unless `--absolute-paths` is explicitly passed; then a separate `absolute_path`
field is added and never replaces the source identifier.

A span is half-open and has this exact shape:

```json
{
  "source":{"root":"project-src","path":"parse/expr.e"},
  "byte_start":128,
  "byte_end":133,
  "line":9,
  "column":5,
  "end_line":9,
  "end_column":10,
  "column_utf16":5,
  "end_column_utf16":10
}
```

Byte offsets address the original input bytes, including a BOM and physical CRLF;
line and column values address the normalized source of spec §3. Lines and both
column forms are one-based. `column` counts Unicode scalar values and `column_utf16`
counts UTF-16 code units. A zero-width location has equal byte offsets. Generated
locations use the same representation.
For recovery after invalid UTF-8, each Unicode maximal subpart occupies one logical
scalar and one UTF-16 unit. A maximal subpart is the longest prefix, from one through
three bytes, that could begin a valid sequence before the first missing, disallowed
or non-continuation byte; an illegal lead or continuation byte therefore occupies
one unit. This convention affects locations only, never acceptance or decoded source.

Captured bytes use one representation everywhere. Valid UTF-8 is a JSON string;
otherwise the value is `{ "encoding":"base64", "data":"..." }` using canonical
padded RFC 4648 base64 with no whitespace. Empty bytes use the empty JSON string.

## 3. Diagnostics and fixes

A diagnostic record is:

```json
{
  "record":"diagnostic",
  "severity":"error",
  "code":"E-TYPE-0003",
  "message":"cannot pass `i64` where `i32` is expected",
  "span":{...},
  "related":[{"message":"parameter declared here","span":{...}}],
  "fixes":[{
    "message":"convert explicitly",
    "applicability":"maybe",
    "edits":[{"span":{...},"replacement":"i32(value)"}]
  }]
}
```

`severity` is `error` or `note`. A note has no independent exit effect and carries
`parent`, the zero-based diagnostic-record index of its error. `applicability` is
`machine` only when applying all edits cannot change a valid program's behavior;
otherwise it is `maybe`. Edits within one fix are non-overlapping and sorted by
source then descending `byte_start`, so they can be applied without offset repair.
Replacement text is normalized UTF-8 with LF endings.

Every diagnostic field is present: an error has `parent:null`, a location-free
command diagnostic has `span:null`, and empty `related` or `fixes` arrays are `[]`.
Every `E-SAFETY` diagnostic that is about two sites carries the other one as its
`related` entry (D364, H09): the acquisition for a forgotten cleanup, an overwrite,
an untested acquisition or a loop consumption; the move for a use after move; the
`defer` for a consumption it reserved; the borrow, the pointer, the reset, the
container's change, the thread's start -- with a `message` saying which, and a
`span` in the same module as the primary.

Codes are allocated from the checked registry `docs/diagnostics.md` and have the
form `E-<CATEGORY>-<NNNN>`. Categories are stable semantic names, not document
section numbers. A code is never reused, even after its diagnostic is retired.
Diagnostics sort by source identifier, `byte_start`, severity (`error` before its
notes), code, then message. Parser recovery and the required primary diagnostics are
part of the conformance corpus.

## 4. Token and syntax commands

```text
neper tokens [--json] [--path VIRTUAL.e] <FILE.e|->
neper parse  [--json] [--path VIRTUAL.e] <FILE.e|->
```

`-` reads UTF-8 source from stdin. `--path` supplies its source identity and module
name and is required with `-`; it has no filesystem effect. In text mode `tokens`
prints one token per line and `parse` prints an indented tree. In JSON mode:

- `tokens` emits one `token` record per token, including `NEWLINE` and `EOF`.
  Fields are `record`, `index`, `kind`, `lexeme`, `span`, `leading_trivia`. Trivia
  items have `kind` (`space`, `comment`, or `bom`), exact `text`, and `span`. `bom`
  may occur only once, as the first token's first trivia item (the EOF token when the
  file contains only a BOM). Invalid bytes
  produce diagnostics and an `INVALID` token whose `lexeme` uses the base64 captured-
  bytes object from §2; other lexemes are strings. Token output therefore remains total.
- `parse` emits token records followed by one `syntax` record. A syntax node has
  `kind`, `span`, `token_start`, `token_end`, and ordered `children`; a child is
  either `{"node":...}` or `{"token":N}`. The tree is lossless because tokens retain
  lexemes and trivia. Error recovery inserts an `ErrorNode` but never invented
  source text.

A token span covers its lexeme and excludes leading trivia. `EOF` has an empty
lexeme and a zero-width span at the original byte length. String lexemes retain the
original decoded source spelling: a `NEWLINE` lexeme is `"\n"`, `"\r\n"`, or `"\r"`
according to the input, even though the parser sees normalized LF; a leading BOM is
retained as `bom` trivia even though the parser ignores it. A malformed string,
character or raw-string token that reaches its matching closing delimiter is one
`INVALID` token through that delimiter. Without a closing delimiter, an ordinary
string or character stops before the next physical line ending or at EOF, while a raw
string extends through EOF. Leading trivia is ordered
by byte offset: the BOM is one item, every maximal non-empty run of ASCII spaces is
one `space` item, and each `//` comment through but excluding its physical line ending
is one `comment` item. Because every physical line ending is a `NEWLINE` token, no
trivia item crosses a normalized line boundary. If an `INVALID` token interrupts a
comment, its valid prefix and suffix become separate `comment` items on the adjacent
tokens; a suffix item therefore need not begin with `//`. Concatenating each trivia
text and token lexeme in index order reconstructs every original byte (using decoded
base64 for an object lexeme). A syntax-node span runs from its first token's
`byte_start` through its last token's `byte_end`, excluding that first token's trivia;
a recovery node with no token is zero-width at the recovery point.

Token kinds and syntax-node kinds are closed registries in `docs/grammar.ebnf`; a
new kind requires a grammar-revision increase. Parsing is syntactic: the common
`BracketPostfix` node is classified as indexing, slicing, or comptime arguments only
during name resolution, so a parser never needs a symbol table.

## 5. Symbol and reference index

`neper index --json` emits a `symbol` record for every module, function, kernel,
test, type, field, enum/union member, constant, module variable, parameter, local,
error, extern and intrinsic. Its closed `kind` values are `module`, `fn`, `kernel`,
`test`, `type`, `field`, `member`, `const`, `module_var`, `parameter`, `local`,
`error`, `extern`, and `intrinsic`.

Each symbol contains `id`, `kind`, `name`, `qualified_name`, `module`, `signature`,
`span`, `selection_span`, `container_id`, `attributes`, and nullable `documentation`
from spec §3's attached `///` lines. `id` is the zero-based
record number among symbol records and is stable for identical source. Nullable
fields are present as JSON null; no field is omitted.

A `reference` record contains `source_span`, `role`, `spelling`, `target_id`,
`target_qualified_name`, and `origin`. `role` is `import`, `type`, `call`, `read`,
`write`, `address`, `protocol`, or `instantiate`; `origin` is `source` or `compiler`.
Compiler-origin protocol, iterator and formatting calls use the smallest source span
that caused the call and name the concrete target. This makes call graphs and
protocol resolution inspectable without duplicating compiler logic.
If source errors prevent resolution, both target fields are JSON null; the reference
is still emitted so an editor can retain the occurrence.

Records sort by source identifier, span start, record kind, then qualified name.
Null-span intrinsics sort first by qualified name.
The stream ends with
`{"record":"result","ok":true,"exit_code":0,"data":{"symbols":N,"references":N}}`.

### Dispatch and instantiation

`neper explain-file PATH ROOT ARCH OS --json` (D359, H06) checks the program as
`check-file` does and then emits what the checker decided, one record per site,
ordered by source identifier, byte offset, kind and decision, a site decided twice
the same way written once:

- `dispatch` — a protocol call resolved: `protocol` (`eq`, `cmp`, `hash`, `format`,
  `next`, ...), `receiver` (the type as a program spells it, `module.Name`, `*T`,
  `[]T`, `[N]T` or a scalar), `selected` — `{"kind":"declared","function":
  "module.name"}` for the type's own declaration, `{"kind":"supplied","rule":
  "eq"|"cmp"|"hash"}` for spec §9 rule 4's supplied operation, `{"kind":"none"}`
  when neither exists (the check then fails, and the record says where) — and
  `span`, the point where the call was checked, which for a template body is the
  template's site once per instance.
- `instance` — a generic function instantiated: `template` (`module.name`),
  `arguments` (each as a type spelling, a decimal, or a string literal as written),
  and `span`, the call that first asked for it, in whichever module that was.
- `discard` (D360, H07) — an `err` bound to `_`: `function` (`module.name` of the
  call whose error is dropped), `deferred` (true under `defer`), and `span`, the
  binding. Dropping an error is an explicit source choice, and this is where a
  harness reads the choices a program made.

The stream ends with `{"record":"result","ok":true,"exit_code":0,"data":{"records":N}}`,
with `"truncated":true` beside `records` when the checker's table overflowed. A
program that does not check emits the check diagnostic on stderr and exits 1, as
`check-file` without `--json` does.

### Context

`neper context-file PATH ROOT ARCH OS --json --symbol module.name [--budget N]
[--cursor N]` (D361, H08) checks the program and answers what the compiler knows
about one declared function, under a record budget (64 by default):

- `subject` — always first: `subject`, `kind` (`fn`), the module's `source`
  identity and `source_sha256` (the snapshot the answer is bound to), `target`,
  `checks` (the policy), `grammar_revision`, and the declaration's `span`.
- `fact` — one per fact, in a fixed order: the `signature`; an `ownership` fact per
  `own` parameter; `resources` (the checker's rules held for the body) or
  `boundary` (an `@unsafe` function, where they were not applied); then the body's
  decisions in source order -- `call` (the resolved target, or `unknown` for a
  call through a value), `dispatch`, `instance`, `discard` -- each with its `span`.
  `provenance` is `compiler-proved` for what the checker established,
  `declared-and-checked` for what the source says and the checker accepted,
  `unknown` for what it cannot know; `trusted-external` and `runtime-observed`
  are reserved for facts no command emits yet.

The result carries `records` (written), `omitted` (past the budget),
`complete` (nothing omitted and the checker's table did not overflow) and
`cursor`, which passed back as `--cursor` continues from the next fact; the
pagination is deterministic for identical source, and a source change --
visible as a different `source_sha256` -- invalidates the cursor. A subject no
function of the program has is an `E-CLI-9999` diagnostic and exit 2.

### Uses

`neper uses-file PATH ROOT ARCH OS --json --symbol module.name` (D362, H17) checks
the program and lists every use of one declared function the checker resolved,
anywhere in the program, by module then byte offset: a `use` record with
`relation` -- `call` (a direct call, of the function or of one of its instances),
`dispatch` (a protocol call that chose it), `instance` (an instantiation of it),
`value` (its name taken as a function value) -- `provenance` (`compiler-proved`),
`in` (the function the use lies in), and `span`. Then a `root` record per reason
the function is alive without a use: `entry` (`main` of the root module), `test`
(`@test`), `export` (`@export`). The result carries `uses`, `roots`,
`indirect_calls` -- how many calls through function values the program has, each a
consumer no name can trace, so a function whose name was taken as a value may be
called from any of them -- and `complete`, false only when the checker's table
overflowed. A safe-delete claim needs `uses` and `roots` both zero and, when the
function's name is taken as a value anywhere, `indirect_calls` zero as well; a
rename plan edits every `use` span's spelling and the declaration, and nothing in
comments, strings or generated registrations, which this command does not see.

### Rename plans

`neper plan-rename-file PATH ROOT ARCH OS --json --symbol module.name --to NEW`
(D376, H29) is the first structured edit: a plan, not an application. It checks
the program and emits one `precondition` record per file the rename touches --
`source` and the file's SHA-256 as read -- then one `edit` record per site: `op`
`rename-symbol`, `symbol`, `site` (`declaration` or `use`), the `span` of the name
token (qualified uses edit the name after the qualifier) and `replacement`; then a
`postcondition` record whose `check` says what re-checking must find; then the
result with `edits`, `files` and `complete`. A harness applies the edits to files
whose hashes still match -- all of them or none -- from the highest offset down, and
re-checks; `scripts/apply_plan.py` is the reference applier. What `uses-file` does
not see (comments, strings, generated registrations) the plan does not edit.
`m25-h29-structured-edits.md` fixes the plan shape for the operations to come.

## 6. Formatting contract

`neper fmt` is a canonical **layout** formatter, not a semantic normalizer. It does
not remove explicit parentheses, change a numeric base, rename identifiers, reorder
declarations, or rewrite ordinary strings as raw strings. Its complete v1 contract:

- UTF-8 without BOM, LF endings, one final LF, no trailing whitespace or trailing
  blank lines; indentation is four ASCII spaces and tabs are never emitted.
- One ASCII space surrounds binary and assignment operators and follows commas and
  colons. No space appears just inside delimiters, before comma, before a call or
  comptime-argument list, around `.`, or around a range's `..`.
- Opening block braces remain on the declaration/control line; closing braces occupy
  their own indentation level. Empty blocks are `{}`. `else` follows `}` on the same
  line. A non-empty statement occupies its own line.
- A bracketed list that exceeds 100 Unicode-scalar columns breaks after its opening
  delimiter, contains one element per line with a trailing comma, and closes on its
  owning indentation level. Otherwise it is one line and has no trailing comma. The
  formatter never splits a token, comment, or expression outside a legal continuation
  delimiter; such an indivisible line may exceed 100 columns, making the width a
  deterministic wrapping threshold rather than a source-validity limit.
- Exactly one blank line separates top-level declarations. Attribute lines remain
  adjacent to their declaration, are sorted by attribute name, and duplicates are
  compile errors. Inside a block, runs of blank lines collapse to one.
- Comment text is preserved byte-for-byte after newline normalization. A trailing
  comment is preceded by one space. Comments are never column-aligned or moved across
  a declaration/statement. A comment between attributes and a declaration is illegal
  because attributes must be immediately adjacent.
- Contiguous comment-free `use` declarations at the start of a file sort by module
  path then alias. Other declarations retain source order. Raw strings use the
  smallest safe delimiter count; all other literal spellings are preserved.

`neper fmt --check` writes nothing and exits 1 if output would differ. `neper fmt -`
reads stdin and writes only formatted source to stdout; `--json` instead emits one
`formatted` record whose `text` contains that source. On syntax failure no formatted
output is produced. Idempotence and every rule above are fixed by golden fixtures in
the conformance corpus.

## 7. Test, build and command results

Test records are buffered and emitted in deterministic module/source order, never
completion order. They contain `record:"test"`; the last test record is followed by
one `record:"test_summary"`, then the command `result`. The summary contains explicit
`passed`, `failed`, `crashed`, `timeout`, `total`, and `duration_ms` fields.

`run --json` captures the program's stdout and stderr into files beside the
executable (`<exe>.stdout`, `<exe>.stderr`) and emits one `run` record with
`process_exit_code`, `stdout`, `stderr`, and nullable `trap`; captured bytes use
§2's representation. The record is **bounded** (D370, H18): it holds the first
`--capture N` bytes of each stream, a mebibyte without the flag, and the command's
`result.data` carries `stdout_bytes` and `stderr_bytes` (the whole streams' sizes),
`capture_limit`, and `captured_complete` -- `false` when either stream was cut, in
which case the files hold the rest. A flooding child therefore costs the harness at
most two bounds of memory and never a pipe: the streams are files, drained by the
OS. It does not stream raw child bytes into the JSONL
channel. `dis --json` emits one `disassembly` record per function with `symbol`,
`target`, and `text`. These records precede the final command `result`.

Every build writes `.neper/<mode>/build-manifest.json`. It is one canonical JSON
object with `schema:"neper-build-manifest"`, `version:1`, `tool_version`,
`language_version`, `grammar_revision`, `target`, `mode`, `root_module`, `inputs`,
`dependencies`, `libraries`, `assets`, `artifacts`, `unsafe`, and `options`. Inputs and dependencies carry
source identifiers and SHA-256 hashes; libraries carry the requested name, ordered
search roots, resolved source identifier or absolute external path, and SHA-256;
assets carry logical name, source identifier, media type, sorted attributes, byte
size and SHA-256;
artifacts carry project-relative paths, kind, target and SHA-256; `unsafe` is the
inventory of the program's unsafe boundaries (D355, D371, H03/H27) -- one entry per
`@unsafe` function and `@nocheck` block (`provenance: "declared"`) and per `extern
fn`, `mem.cast`, `mem.bitcast` and bare `union` site (`provenance: "trusted"`: the
checker trusts the program there and checks nothing), with `kind`, `provenance`,
`module`, `function` (the type, for a `union`) and `line`, read off every module's
bytes so a warm build lists them too, in module then line order; a raw dereference
is not enumerable by this pass and is the boundary the inventory does not list; `incremental` (D363, H14) is what an
`--incremental` build decided per module, in graph order -- `decision` `kept` or
`rebuilt` and `reason`: `stable` (source and every dependency unchanged),
`edges-hold` (source unchanged, every imported interface still as recorded),
`edge-changed` (an imported interface differs), `source-changed`, `mode-changed`,
`no-artifact`, `invalid-artifact` (a file that failed its checksum or layout
validation, rebuilt like a missing one) -- empty for a build that read no artifacts;
`mode-changed` covers `--unchecked` too, whose artifacts share `.neper/release/`
with checked ones and carry their own mode (D369);
`options.checks` is the
check policy the image was built under, `retained` (spec section 11: every row
kept in both modes). Arrays use the
deterministic order in which their corresponding compiler operation is specified,
and object keys use the order listed here.

Every JSON command ends with a `result` record containing `ok`, `exit_code`, and a
`data` object holding command-specific counts or artifact identifiers. Exit statuses remain those in
spec.md §13; the record and process status must agree.

`emit-executable ... --release --unchecked` (D355) builds the release image with
spec section 11's memory rows left out, which the manifest records as
`options.checks: "off"`; without it a release build keeps them.

## 8. Generated source maps

A generator may place `<file>.e.map.json` beside `<file>.e`. It contains
`schema:"neper-source-map"`, `version:1`, the generated source identifier and hash,
and `mappings`. Each mapping has `generated_span`, `original_span`, and nullable
`name`; both spans use §2's exact shape and the generated span must be non-empty.
Mappings are sorted,
non-overlapping, and may leave generated regions unmapped. Paths obey §2 above.

When the generated hash matches, diagnostics use the original span as primary and
include the generated span as a related location. A stale or malformed map produces
`E-TOOL-0001`; the compiler still analyzes the generated file to report independent
source errors, but the command fails and writes no final artifact until the map is
updated or removed. Source maps never affect parsing, type checking, code generation
or cache identity.

A **version 2** map (D373, H19) adds two optional things. `generator` names the
generator and the one input it read -- `name`, `input` (a path relative to the
generated file's directory) and `input_sha256` -- and the compiler checks the
input: a missing input, or one whose hash is not the recorded one, is `E-TOOL-0001`
("the generated source is stale: the generator's input changed") under the same
rule as a stale map, so a generated file is stale when its *input* moved, not only
when it did. Each mapping may carry `edit`: `direct` (the generated output may be
edited in place), `generator` (regeneration-owned: an edit targets the original,
and a hand edit of the generated span is overwritten by the next generation) or
`unknown`; the related location's message says which, and a mapping without `edit`
is `unknown`. An original span is a location, not a fix: nothing in the stream
offers an edit to an original span, since the mapping may be many-to-one. The
compiler never runs a generator; the map's metadata is data.

## 9. Conformance and compatibility

`tests/conformance/` is a normative corpus shipped with the specification. It has
`accept/`, `reject/`, `format/`, `tokens/`, `parse/`, and `tools/`. Every fixture has
expected versioned output; rejected-source fixtures fix primary diagnostic codes and
recovery points. Implementations must pass the corpus at each claimed
language/grammar/stream version. Source-derived output is compared byte-for-byte.
Runtime `duration_ms` values are schema-checked as nonnegative and replaced with `0`
before golden comparison; no other field is volatile.

The corpus also contains a generated-code benchmark reported, not gated by the
language-conformance suite, for each release: tokens per syntax node under each named
tokenizer, parse/type-check success rate, mean repair attempts, identifier-collision
rate, and formatted diff size. The separate general-purpose claim is gated by
`general-purpose-verification.md`. No claim of universal LLM-token optimality is
made: tokenizers differ. Syntax changes are accepted only when this report shows the
intended trade rather than inferring it from character count.

The machine-checkable JSON Schema for every record and document in this file is
[`schemas/neper-v1.schema.json`](schemas/neper-v1.schema.json). Sequence, key-order,
sorting and cross-record constraints that JSON Schema cannot express remain normative
in this prose.
