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
such operand exists in a command, so that identity is unambiguous. A diagnostic
raised in a module that is not the operand -- a toolchain module a generic was
instantiated in, a sibling under the project's `src` -- carries that module's
identity under its own root, the rule the build manifest uses (D427); the
operand keeps its spelling. Machine output contains no absolute
path unless `--absolute-paths` is explicitly passed; then a separate `absolute_path`
(its `.` and `..` segments collapsed, D489, never past a drive or the root)
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
    "edits":[{"span":{...},"replacement":"i32(value)"}],
    "preconditions":[{"source":{...},"sha256":"..."}]
  }]
}
```

`severity` is `error` or `note`. A note has no independent exit effect and carries
`parent`, the zero-based diagnostic-record index of its error. A check stops at the
first failure inside a function, since what follows it in that body is a reading
of the failure, and goes on to the next function (D553, H09): `check --json` over a
program whose bodies fail in several functions carries each function's first
diagnostic, in source order, the instances the bodies made after them, and the
result's `diagnostics` counts them; a failure with no site -- a limit, the
deadline -- ends the stream as before, and a name or declaration failure still
comes alone, the bodies not being checked past it. `applicability` is
`machine` only when applying all edits cannot change a valid program's behavior;
otherwise it is `maybe`. Edits within one fix are non-overlapping and sorted by
source then descending `byte_start`, so they can be applied without offset repair.
Replacement text is normalized UTF-8 with LF endings. A type mismatch between
two scalar numbers at a one-token expression -- a name or a literal -- carries
the conversion as a fix (D444, H09): `convert explicitly`, `maybe`, one edit
replacing the expression's span with `T(expr)` for the expected `T`; a wider
expression gets no fix, since which of its parts to convert is a reading. An
unknown value name within two edits of a local or of one of the module's own
values (D445, H09) names it -- `unknown value name; did you mean `x`?` -- and
carries `use the nearest name in scope`, `maybe`, one edit over the token; a
member a module does not export is ``m` has no member `x`` at the member's
token, with the module's nearest export named and offered the same way (D447),
and a field an aggregate does not declare is ``T` has no field `x`` at the
member's token with the nearest field (D448). A
fix's `preconditions` (D432, H18) are the plans' (§5): the identity and SHA-256 of every source its edits
touch, as the diagnostic saw it, so an applier refuses a file edited since -- an
edit's byte offsets mean nothing against other bytes.

Every diagnostic field is present: an error has `parent:null`, a location-free
command diagnostic has `span:null`, and empty `related` or `fixes` arrays are `[]`.
A type mismatch (D401, H09) -- an argument, an initializer, an assignment, a
returned value, a constant's value, a thread's context, two operands of one
type -- carries both types as two further fields, `expected` and `actual`, in the
spelling `context-file` uses for types, and names them in its message (``type
mismatch: expected `i32`, found `u64` ``) except for a returned value, whose
words the bootstrap parity fixes; a diagnostic that is not a mismatch has neither
field. A name diagnostic (D514, H18) -- an unknown value name, an unknown type, a
module without the member named -- carries the name as `symbol`, the module or
type it was looked up in as `owner` when there is one, and the nearest candidate
the message offers as `near` when there is one, so a harness reads the names
without parsing the message.
Every `E-SAFETY` diagnostic that is about two sites carries the other one as its
`related` entry (D364, H09): the acquisition for a forgotten cleanup, an overwrite,
an untested acquisition or a loop consumption; the move for a use after move; the
`defer` for a consumption it reserved; the borrow, the pointer, the reset, the
container's change, the thread's start -- with a `message` saying which, and a
`span` in the same module as the primary.

The first fix (D381, H09): `E-SAFETY-0002`, a resource still owned at an exit,
carries one `maybe` fix -- an insertion of `defer <closer>(x)` on its own line
after the acquiring statement, indented as that line is, the closer being the
type's declared cleanup qualified as the module imports it (`sync.release`,
`os.dir_close`) or the seeded closer of an `os` handle (`os.close`, `os.wait`,
`os.thread_join`). It is `maybe` because it changes what the program does and
because an explicit cleanup later in the block then becomes a second consumption
(`E-SAFETY-0009`): the harness applies it, re-checks, and removes the explicit
one when the checker says so. `E-SAFETY-0008`, a resource used before the error it
was returned beside was tested, carries `if e != ok { ret e }` on the line after the
acquisition (D382) -- when the second result is an `err` and the function returns a
bare `err`; a flag, or another result shape, gets no fix. A diagnostic mapped through
a source map carries no fix (section 8). No other diagnostic carries a fix yet.

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
`span`, `selection_span`, `container_id`, `attributes`, `unsafe` (D513, H27: the
kinds of the manifest's unsafe inventory that name the declaration -- `unsafe`,
`nocheck`, `deref`, `extern`, `union`, `bitcast`, `cast` -- each once, empty for a
symbol that holds none), and nullable `documentation`
from spec §3's attached `///` lines. `id` is the zero-based
record number among symbol records and is stable for identical source. Nullable
fields are present as JSON null; no field is omitted. `neper index-file - ROOT
ARCH OS --json --path REL` (D488) and `neper check-file - ROOT ARCH OS --json
--path REL` (D490) read the module from stdin under the `--path` identity, as
`tokens` and `parse` do (D289); its imports resolve as the file at `REL` would,
and no source map is looked for beside it. A `local` (D483, H17) is a
`let`/`var` binding -- each name of a tuple binding its own -- or a `for` variable,
nested under its function like a `parameter`, its `span` and `selection_span` the
name, its `signature` the name; a bare name in the body that is one of the
function's locals or parameters declared before it is a `read`, `write`, `call` or
`address` reference to that symbol, its `target_qualified_name` `module.fn.name`
(spec section 5 lets no local shadow a module-scope name, so a known name is never
a local). A comptime parameter is not yet a symbol.

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
  "eq"|"cmp"|"hash"}` for spec §9 rule 4's supplied operation, `{"kind":"none",
  "reason":...,"candidates":[...]}` when neither exists (D430, H06; the check then
  fails, and the record says where): `reason` is why the supplied rule refused --
  a struct, which no rule supplies; the first arm of a tagged union or the element
  of a sequence that has no such protocol, named with its type; a scalar the rule
  does not cover -- or null, and `candidates` lists a function of the protocol's
  name declared outside the receiver's module, which rule 4 never reads, with its
  reason — and
  `span`, the point where the call was checked, which for a template body is the
  template's site once per instance.
- `instance` — a generic function instantiated: `template` (`module.name`),
  `arguments` (each as a type spelling, a decimal, or a string literal as written),
  and `span`, the call that first asked for it, in whichever module that was.
- `discard` (D360, H07) — an `err` bound to `_`: `function` (`module.name` of the
  call whose error is dropped), `deferred` (true under `defer`), and `span`, the
  binding. Dropping an error is an explicit source choice, and this is where a
  harness reads the choices a program made.
- `phase` (D463, H06) — an `if` settled before the program runs (spec §9: one side
  a `meta` question): `construct` (`if`), `phase` (`comptime`), `taken` (whether
  the first arm is the one that stands; the other is not code), and `span`, the
  `if`. A template's `if` that folds each way in different instances is two
  records, `false` first. And, after every site's record (D468), one per `const`
  the operand module declares and the checker settled: `construct` (`const`),
  `phase` (`comptime`), `symbol` (`module.NAME`), `type`, `value` (a decimal, or
  `true`/`false`) and `span`, the declaration -- what the source cannot show
  without evaluating it.
- `layout` (D463, H06) — after every site's record, one per aggregate the operand
  module declares or instantiates, as the target lays it out: `type`
  (`module.Name`), `kind` (`struct`, `union`, `tagged-union`, `enum`), `size`,
  `align`, `fields` -- each with `name`, and for a struct or union `type`,
  `offset` and `size` (a tagged union's arm without a payload has offset 0 and
  size 0), for an enum `value` -- and `span`, the declaration.

The stream ends with `{"record":"result","ok":true,"exit_code":0,"data":{"records":N}}`,
with `"truncated":true` beside `records` when the checker's table overflowed. A
program that does not check (D430) still answers the stream: the records the
checker made before it stopped -- the dispatch that found nothing among them --
then the diagnostic as `check-file --json` spells it and a result of exit 1; the
E-NAME-9999 for a missing protocol names the foreign candidate too.

### Context

`neper context-file PATH ROOT ARCH OS --json --symbol module.name [--budget N]
[--cursor N] [--unchecked]` (D361, H08) checks the program and answers what the compiler knows
about one declared function, under a record budget (64 by default):

- `subject` — always first: `subject`, `kind` (`fn`), the module's `source`
  identity and `source_sha256` (the module's text), `snapshot` (D407, H15: the
  program's identity -- every module's source hash folded in graph order, sixteen
  hex digits; an edit anywhere in the program changes it, and a cursor or a fact
  that carries a different one is stale), `target`, `checks` (the policy),
  `grammar_revision`, and the declaration's `span`.
- `fact` — one per fact, in a fixed order: the `signature`; an `ownership` fact per
  `own` parameter; the caller's contract per pointer parameter (D396, H11) --
  `allocation` for a `*mem.Arena` (what comes back holding a pointer is the caller's
  region's), `borrow` for a `*const T` or a `*T` whose call gives back a view,
  `mutation` for a `*T` whose call gives back nothing holding a pointer (the
  caller's views dangle); `errors` when a result is `err` (`fallible`, or `partial`
  beside other results); `threads` when the body starts a thread; then
  `resources` (the checker's rules held for the body) or
  `boundary` (an `@unsafe` function, where they were not applied); then a
  `dependency` fact per module the subject's module imports (D498, H08), naming
  it and its interface hash -- the manifest's `interface_sha256` -- so an answer
  can be held against the interfaces it rests on; then the body's
  decisions in source order -- `call` (the resolved target, or `unknown` for a
  call through a value), `dispatch`, `instance`, `discard`, `value` (a function
  named as a value), `move` (D486, H17: a resource consumed at the site --
  closed, returned, rebound or handed to an `own` parameter -- named in the
  value), `phase` (an `if` settled at compile time, D463, saying which arm is
  taken) and `borrow` (D487, H17: a local bound to a view of another local --
  `&x`, `x[a..b]`, `x.items`, a literal holding `&x` -- naming both, which is the
  relation D393's rules hold the body to; and, D501, a view ended: the local that
  views nothing from a `mem.reset` of its region or a call given its container by
  pointer) -- each with its `span`.
  `provenance` is `compiler-proved` for what the checker established,
  `declared-and-checked` for what the source says and the checker accepted,
  `unknown` for what it cannot know; `trusted-external` and `runtime-observed`
  are reserved for facts no command emits yet.

A subject that names a declared type rather than a function (D419, H08) --
`--symbol module.Name` for a struct, union, tagged union or enum -- answers with
`kind` `type` and facts in a fixed order: the `signature` (the declaration's
head, with the resource's cleanup when it is one), one `field` per field or
member (a field's type, an enum member's value), the `layout` (size and
alignment on the target, `compiler-proved`), then what the rules make of a
value: `resource` (owed its cleanup, moves once, fields read in its module
alone), `borrow` (holds a pointer: a value views what it points at) or `copy`
(plain data). A subject that names a constant or a module-scope variable
(D437, H08) answers with `kind` `const` or `global`: the `signature` (`const
NAME: T` or `var NAME: T`), the `value` -- a constant's as the interpreter
settled it, `compiler-proved`; a global's `zero-initialised` or `initialised by
its expression before main runs` -- and, for a global, `threads`: every thread
of the program shares it and no rule tracks it. A subject that names none of
these is `E-CLI-9999` and exit 2.

`neper context-file PATH ROOT ARCH OS --json --module module.name [--budget N]
[--cursor N] [--unchecked]` (D397, H11) is the catalogue: every declared, non-generic function
of the module in declaration order, each a `subject` record followed by its
contract facts (the signature through `resources`/`boundary`; the body's
decisions are `--symbol`'s), under one budget that counts subjects and facts
alike. A page may end inside a function's facts; the next page continues them,
and they belong to the last subject written. A name no module of the program
has is an `E-CLI-9999` diagnostic and exit 2.

Both direct forms take standalone `--unchecked` among their paging and overlay
flags (D555, H27). It describes the intended whole-image check policy rather than
changing the static query: every subject then carries `checks: "off"` and one
additional paginated `boundary` fact stating that runtime safety checks are omitted
from the whole image and values it produces are trusted. Without the flag the subject
carries `checks: "retained"` and no whole-image boundary fact. A module catalogue
emits that whole-image boundary once for each of its subjects.

`neper query-batch PATH ROOT ARCH OS --json --batch FILE [--unchecked]` (D409, H16)
answers many
queries from one check: the batch file (`-` for standard input) holds one query
per line -- `context SYMBOL [BUDGET [BYTES [CURSOR]]]`, `catalog MODULE [BUDGET
[BYTES [CURSOR]]]`, `uses SYMBOL`, `memory` -- and each line's answer is a whole stream,
header to result, written in the line's order, so a harness splits the output
at the headers. A blank line is passed over; a line no query reads gets a
diagnostic stream of its own. A refused query or an unreadable line makes the
process exit 2 once every line is answered. Each line is a request of its own
(D410): what it allocates is given back when it is answered, and `memory` asked
before and after a run of queries reports the same `arena_used`, which both
suites assert. Measured on the compiler's own source: twenty `context` queries
in one batch 447 ms, as twenty processes 6.6 s; five hundred and fifty lines 3.2
s with the arena where it started.

The `memory` result separates retained and temporary storage (D558, H16):
`arena_used` is live allocation and `arena_capacity` is reserved capacity;
`snapshot_used` is the checked graph/checker before the batch input is loaded;
`session_used` is the baseline retained for the batch; and `request_peak` is the
largest temporary allocation of any completed line before its request arena was
reset. `queries_completed` counts successful context, catalogue and uses lines
before this memory report. Thus a report after warmup shows both the completed
work, its peak, and that live memory
returned to the session baseline instead of merely relying on process exit.

Standalone `--unchecked` applies one intended image policy to the whole batch
(D556, H27). Every `context` and `catalog` answer then has the same `checks: "off"`
subjects and whole-image boundary facts as the direct forms; `uses` and `memory`
answers are unchanged. The program is still loaded, resolved and statically checked
once. Without the flag, existing batch streams remain `retained` and byte-identical.

Both forms take `--bytes N` beside `--budget` (D400, H08): a budget in serialized
bytes, measured on what has been flushed; the record that crosses it is the last
written and the rest is omitted, so a page is at most the budget plus one record.
The result carries `records` (written), `omitted` (past either budget),
`complete` (nothing omitted and the checker's table did not overflow), `bytes`
(the serialized bytes of the records before the result -- what the harness held,
H18) and
`cursor`, which passed back as `--cursor` continues from the next fact; the
pagination is deterministic for identical source, and a source change --
visible as a different `source_sha256` -- invalidates the cursor. A subject no
function of the program has is an `E-CLI-9999` diagnostic and exit 2.

`test-file` takes `--only n1,n2,...` as its last two arguments (D424, H10): the
tests to run, by name or as `module.name` with any qualifier -- the form
`test-impact-file` names them in -- and the rest are not compiled into the
runner; a name the module does not declare is passed over, since a project-wide
list names other modules' tests too. `test-project` does not take it.

Every plan's `result.data` carries `snapshot` (D436, H29), the program identity
a `context-file` subject names (D407): a harness that applies a plan against a
tree whose snapshot differs applies edits computed for other sources, and the
file-hash preconditions catch the file that changed while the snapshot says the
program did.

An error declared by a module is a subject too (D451, H17): `uses-file --symbol
module.Name` lists every value naming it, bare in its own module or qualified
from another, as `use` records with relation `error`, and `plan-rename-file
--symbol module.Name --to New` renames the declaration's name token and every
such value, applied and re-checked by both suites.

### Test impact

`neper test-impact-file PATH ROOT ARCH OS --json --changed m1,m2,...` (D423, H10)
answers which `@test` functions of the program an edit to the named modules can
reach: the program is checked with the explain table open, its resolved calls,
dispatches, instantiations and function values are the edges (an instance's the
template's), and from each test everything reachable is walked; a test that lies
in a changed module or reaches a function in one is `affected`. One `impact`
record per test (`test`, `affected`, `span`) in module then declaration order,
the result counting `tests` and `affected`; a module the program has not is
`E-CLI-9999` and exit 2. A harness runs the affected tests and no other after an
edit, with the whole set the answer when the edges overflowed
(`complete:false`).

### Uses

Every query over a program that does not check -- `context-file`, `uses-file`,
the plans, `test-impact-file` -- answers as a stream (D520, H08, H18): its header,
the diagnostic, and a result of exit 1, nothing on stderr; `explain-file` answers
with what the checker decided before it stopped as well (D430); `query-batch`
answers with one such stream under a `query-batch` header (D523), since no line
of it can be answered. A program that
does not load -- a module that does not parse, a `use` naming no module -- is a
stream too (D521): the query's header, the loader's diagnostic, a result of exit
1; and `index-file` over a file that does not parse begins with its header. So do
`dis-file --json` and `build-manifest-file --json` (D522): the latter answers with
section 1's envelope under a `manifest` header in place of the object.

`neper uses-file PATH ROOT ARCH OS --json --symbol module.name` (D362, H17) checks
the program and lists every use of one declared function the checker resolved,
anywhere in the program, by module then byte offset: a `use` record with
`relation` -- `call` (a direct call, of the function or of one of its instances -- a call in a
constant's initializer, evaluated at compile time, included, D510, so a function
only a constant reaches has that use and the plans that site),
`dispatch` (a protocol call that chose it), `instance` (an instantiation of it),
`value` (its name taken as a function value), or `type` (D516: the subject names a
type, and every annotation and literal naming it, through a qualifier or bare, from
the index of every module, is a use) -- `provenance` (`compiler-proved`),
`in` (the function the use lies in), and `span`. A subject `module.Type.field`
(D420, H17) names a field: its uses are every access `x.field` and every literal
`{ field: .. }` the checker typed, relation `field`, and `plan-rename-file` over
the same subject plans the field's rename -- the declaration's token and every
such spelling. Then a `root` record per reason
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
(D376, H29) is the first structured edit: a plan, not an application. A subject
that names a type (D515) plans the type's rename: the index of every module of
the program is taken in memory, and each reference whose target is the type --
an annotation, a literal, spelled through a `use` qualifier or bare -- and the
declaration are the sites, the same records as a function's; and every function
of the type's module spelled `<snake>_<op>` for it, `op` one of section 12's --
`rec_cmp`, `rec_eq`, `rec_hash`, `rec_format`, `rec_next`, `rec_next_err` for
`Rec` -- is renamed with it (D517, D537), `pair_cmp`, at its declaration and every
use, since the lookup that finds it is by the spelling; a helper merely named for
the type, `rec_count`, is not. For the same reason a subject that is such a
function -- `deep.rec_cmp` -- is refused a name of its own (D518): the plan says
whose `cmp` it is by its spelling and exits 2, and the type's rename is the way. It checks
the program and emits one `precondition` record per file the rename touches --
`source` and the file's SHA-256 as read -- then one `edit` record per site: `op`
`rename-symbol`, `symbol`, `site` (`declaration` or `use`), the `span` of the name
token (qualified uses edit the name after the qualifier) and `replacement`; then a
`postcondition` record whose `check` says what re-checking must find; then the
result with `edits`, `files` and `complete`. A harness applies the edits to files
whose hashes still match -- all of them or none -- from the highest offset down, and
re-checks; `neper apply-plan PLAN.jsonl --root DIR [--project-src DIR] [--json]`
(D481) is the applier: every precondition's file must hash as recorded or nothing is
written (`E-TOOL-0003`, exit 2, the file named in the message as the precondition
spells it and carried as `symbol` (D547); and the same code for an edit with no
precondition or outside its file, or a plan whose result was not `ok`), each file's edits go on from
the highest offset down and the file is published through `.tmp` and one replace;
plain, it prints `applied N edits to PATH` per file and the `postcondition`; with
`--json`, a stream whose result carries `edits`, `files` and `postcondition`.
An `edit` inside a range the operand's source map marks `"edit": "generator"`
(D512, H19) carries `"owner": "generator"` and `original` -- the generator's input
and the byte where the edited text begins in it -- since the generated file is
regenerated from that input and an edit made in it would be undone; `apply-plan`
refuses such a plan with `E-TOOL-0003`, nothing applied. The other edits of the
plan are plain, so a harness edits the original and re-plans.

`neper compare-manifests A B [--json]` (D482) holds two build manifests against
each other by what identifies a build -- `target`, `mode`, `root_module`,
`tool_version`, `options.checks`, every input by path and hash, every dependency
by module and both hashes, every artifact by kind, target and hash but not its
path -- and prints one line per difference and `manifests agree` (exit 0) or
`manifests differ (N)` (exit 1); with `--json`, a `difference` record each
(`kind`, `name`, `left`, `right`, a side with no such entry `null`) and the
result's `same` and `differences`, exit 0 either way.
`scripts/apply_plan.py` (D376) did the same in Python and is retired. What
`uses-file` does not see (comments, strings, generated registrations) the plan does
not edit.
`neper plan-add-parameter-file PATH ROOT ARCH OS --json --symbol module.name
--parameter "name: T" --argument EXPR` (D406, H17) is the signature-change plan in
the same shape: the `edit` records carry `op` `add-parameter-and-migrate`, the
declaration's edit inserts the parameter last in its list and every resolved call's
edit inserts the argument last (with the `, ` a non-empty list needs), the
insertion point being the list's closing `)`; the postcondition says the signature
and the use count re-checking must find. A function named as a value (a thread
entry, a callback) or chosen by a protocol cannot be migrated -- its type is its
signature -- and the plan is refused with an `E-CLI-9999` naming the first such
site and exit 2, so no half-migration is emitted. `--arguments FILE` in place of
`--argument EXPR` (D455, H29) gives each call its own argument: one `LINE:COL
EXPR` line per call, the position the call's name as `uses-file` spells it, and
a `* EXPR` line for every other call; a call the file leaves out with no `*`
line refuses the plan, naming the call's line. `neper
plan-replace-expression-file PATH ROOT ARCH OS --json --span START:END --with EXPR`
(D414, H29) plans one expression's replacement: the bytes START..END of the
operand must be exactly one expression node of its tree, else the plan is
refused; the `edit` (`op` `replace-expression`, `symbol` the expression's text,
site `use`) carries the span and the replacement, the precondition the file's
hash, the postcondition that re-checking passes with the expression's type
unchanged. `neper plan-change-signature-file PATH ROOT ARCH OS --json --symbol
module.name --order I,J,...` (D415, H29) plans a reordering or removal: the
order lists the parameters kept as indices into the old list, none repeated;
the declaration's list and every resolved call's argument list are re-rendered
from the texts of their items in that order, one `change-signature` edit per
site over the text between the parentheses; a function named as a value or
chosen by a protocol, a repeated or out-of-range index, a list of more than
sixteen items, or a parameter left out of the order that the body still names
(D439) is refused. Every refused query (a subject that names nothing, a
plan that cannot be made) exits 2 as its result says.
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
§2's representation. A backtrace frame whose line lies in a module other than its
function's -- a body inlined there in a release build -- names that module's
function holding the line as `inlined_from` (D519, H19), the frame's `function`
staying the one whose code holds the site; the operand's own frames and the trap's
span are under the operand's identity, `project-src` in a project. The record is **bounded** (D370, H18): it holds the first
`--capture N` bytes of each stream, a mebibyte without the flag, and the command's
`result.data` carries `stdout_bytes` and `stderr_bytes` (the whole streams' sizes),
`capture_limit`, and `captured_complete` -- `false` when either stream was cut, in
which case the files hold the rest. A flooding child therefore costs the harness at
most two bounds of memory and never a pipe: the streams are files, drained by the
OS. It does not stream raw child bytes into the JSONL
channel. `dis --json` emits one `disassembly` record per function with `symbol`,
`target`, `text` and `inlined` (D542): with `--release` after `--json`, the release
image is listed, and `inlined` names each run of the function's code that is the
copy of another function's body -- `from` as `module.function`, `start` and `end`
as function-relative byte offsets, `end` exclusive, and the callee's `line` the
run begins at; the innermost callee for a copy through a copy, and empty in a
debug build. These records precede the final command `result`.

Every build writes `.neper/<mode>/build-manifest.json`. It is one canonical JSON
object with `schema:"neper-build-manifest"`, `version:1`, `tool_version`,
`language_version`, `grammar_revision`, `target`, `mode`, `root_module`, `inputs`,
`dependencies`, `libraries`, `assets`, `artifacts`, `unsafe`, and `options`. Inputs and dependencies carry
source identifiers and SHA-256 hashes; libraries carry the requested name, ordered
search roots, resolved source identifier or absolute external path, and SHA-256;
assets carry logical name, source identifier, media type, sorted attributes, byte
size and SHA-256;
artifacts carry project-relative paths, kind, target and SHA-256; the operand's
source map, when present, is an input with `kind: "source-map"` (D467); `unsafe` is the
inventory of the program's unsafe boundaries (D355, D371, H03/H27) -- one entry per
`@unsafe` function and `@nocheck` block (`provenance: "declared"`) and per `extern
fn`, `mem.cast`, `mem.bitcast` and bare `union` site (`provenance: "trusted"`: the
checker trusts the program there and checks nothing), with `kind`, `provenance`,
`module`, `function` (the type, for a `union`) and `line`, read off every module's
bytes so a warm build lists them too, in module then line order; every
dereference inside a `@nocheck` block is a `deref` site of its own (D497), the
read whose null check the block left out, at its line under the block's
function -- a `*` before a name or a `(`, not after `:`, `[` or `->`.

`manifest-em ARTIFACT... --json` returns that same `neper-build-manifest`
schema from `.em` files alone (D557, H27), without source, parsing or checking.
The first artifact names `root_module`, as it does for `link-em`; every artifact
must carry an Inventory section and have the same target and build mode. The
manifest has empty `inputs`, `dependencies`, `libraries` and `assets`, hashes
each named artifact into `artifacts`, concatenates their stored unsafe records,
and derives `mode` and `options.checks` from the artifacts (`off` for an
unchecked image, `retained` otherwise).

`incremental` (D363, H14) is what an
`--incremental` build decided per module, in graph order -- `decision` `kept` or
`rebuilt` and `reason`: `stable` (source and every dependency unchanged),
`edges-hold` (source unchanged, every imported interface still as recorded --
"unchanged" leaving every comment's body out, D504, and every line's trailing
spaces, tabs and carriage return, D534, so an edit inside a comment that moves no
line is no change, nor a comment added at a line's end or blanked to spaces; the 64-bit key is a candidate, D507, and a hit
is proved by the bytes' SHA-256 when they are the artifact's and by the canonical
text's otherwise, the artifact carrying both, so a collision is a source change),
`edge-changed` (an imported interface differs -- a parameter's type or `own`, not its name, D535), `source-changed`, `mode-changed`,
`no-artifact`, `invalid-artifact` (a file that failed its checksum or layout
validation, rebuilt like a missing one), `compiler-changed` (written by another
compiler executable, D398), `options-changed` (written by this compiler under
another `--inline-cap`, which rides in the identity's top byte, D431) -- empty for
a build that read no artifacts; an artifact whose recorded imports close a cycle
-- naming a module that imports it, which no source can spell -- is `invalid-artifact`
too (D472, H24): a kept module's imports are read from its artifact, so such an
artifact is distrusted, its module parsed from source, and the build is the clean
build's; each entry carries `artifact_crc32c` (D473, H24), the checksum of the
module's artifact as this build wrote or kept it, and the next warm build refuses
as `invalid-artifact` an artifact whose checksum is not the recorded one -- the
manifest is the cache's anchor, so a file that is whole by its own checksum but
was replaced, or rewritten with the checksum redone, is not read as the cache's;
a module the previous manifest did not record stands on the file's own checksum;
`mode-changed` covers `--unchecked` too, whose artifacts share `.neper/release/`
with checked ones and carry their own mode (D369);
`options.checks` is the
check policy the image was built under, `retained` (spec section 11: every row
kept in both modes); `work` (D405, H14) is what the build did rather than kept --
`bodies_checked` (modules whose function bodies were checked), `modules_lowered`
and `functions_lowered` -- so a warm build over a stable cache reports zero of
each, and a build after an edit the modules the edit reached -- and
`declarations_checked` (D446), the declarations the front end holds after its
declaration pass: the seeded surface and every parsed module's, a kept module's
coming from its artifact -- so a warm build over a stable cache reports the
seeds alone (28 on the incremental fixture, against 403 cold) and a build after
an edit the edited modules' too; `--stats` prints the same four rows, and (D450, H20) three of register pressure:
`values allocated` (the NIR values the allocator placed), `values spilled` (the
ones it put on the stack) and `functions spilling` (the functions with any) --
the measurement H20 asks for, so a change to the allocator or to what the
lowering emits is a number before it is a wall-clock figure. Arrays use the
deterministic order in which their corresponding compiler operation is specified,
and object keys use the order listed here.

Every JSON command ends with a `result` record containing `ok`, `exit_code`, and a
`data` object holding command-specific counts or artifact identifiers. Exit statuses remain those in
spec.md §13; the record and process status must agree.

`--explain` on a release build (D346, H20) explains every inlining decision --
`inline: module.function: <decision>: <reason>` on stderr -- and under `--json`
(D408) as `inline` records of the build stream: `symbol`, `decision`
(`inlinable`, `rejected`, `not-a-candidate`, or `truncated` when the
explanations outgrew their storage), `reason`, and `pass` (1 for the oracle that
lowers every candidate alone, 2 for the one that lowers the first's entries
against each other, where a decision can differ). The records are gathered per
worker and written after the phase in worker order, so they never interleave and
a given worker count gives the same order run to run; `-j 1` is module order.

`--json --time` on a build (D454, H18) makes every phase a `progress` record of
the stream -- `phase`, `ms` (the phase's own), `arena_mb` and `elapsed_ms`
(since the build began) -- written as the phase ends, so a harness watching
the stream sees the build move and can read where a deadline would land;
without `--json` the same is the text `time` line on stderr.

`--json --stats` on a build (D476, H18) makes the `--stats` table one `stats`
record of the stream, before the `result`: flat, one key per row, the row's name
in snake_case with the unit as its suffix (`files`, `loc`, `function_instances`,
`source_bytes`, `compile_mode`, `target_arch`, `target_os`, `wall_time_ms`,
`compiler_peak_working_set_mb`), `@tests` and its kind as `at_tests`, the
module sizes as `module_size_min`, `_median` and `_max`, each phase as
`phase_<name>_ms`, the run's rows `execution_time_ms`,
`executable_peak_working_set_mb` and `exit_code` (`null` when nothing ran), and
`--stats-full`'s pools as `pool_<name>_capacity` and `pool_<name>_used` (`null`
where the table leaves the column blank). Values are scalars under the rule
`result.data` has, numbers bare; without `--json` the table on stderr is
unchanged, and the two are one row list rendered twice.

`--overlay PATH=FILE` (D502, H15) on a build command, any number of times, reads
the module at PATH -- spelled as the loader spells it, or a suffix of that on a
separator, `dep.e` or `src/dep.e` -- from FILE instead of its own file: an
editor's unsaved buffer. The overlay's bytes are the module's for the build, its
hash the input's in the manifest and the artifact's identity, and the file on
disk is not touched; a build without the flag reads the file again. The same
pairs after a `check-file`'s flags and after a query's own arguments (D524) --
`context-file`, `uses-file`, `explain-file`, the plans, `test-impact-file`,
`query-batch` -- answer over the buffers: a plan's preconditions then hash the
overlay's bytes, so it applies to the buffer saved and to nothing else.

`--deadline MS` (D399, H16) on a build command (`emit-executable`, `emit-em-all`,
`run`, with or without `--json`) is a wall-clock deadline: at every checkpoint
between phases -- after load and parse, resolve, check declarations, settle, check
bodies, inline oracles, lower, regalloc and codegen, link -- a build past it stops;
inside the interpreter too (D496, H16), every 65536 steps of a constant's
evaluation, so a constant that would run for seconds stops within milliseconds
of the deadline.
One `E-CLI-0001` diagnostic names the deadline and the phase that finished last,
the `result` has `exit_code` 3 and `data.cancelled_after`, and no image and no
manifest are written; an artifact a hot build's worker had already published is
complete on its own and stays. Inside the two long phases -- the body sweep and
the lowering -- every worker checks the deadline between the modules it holds
(D422), and the body sweep and the lowering between the functions of a module
too (D441, D442), so a cancellation waits for the function in hand and no
longer for the module; `cancelled_after` then names the phase and "between
modules" or "between functions". A deadline is not a work budget (D218's comptime
budgets are): the same build under the same deadline may finish on one machine and
be cancelled on another, which is what a harness's deadline means. `--deadline 0`
is a deadline already passed and cancels at the first checkpoint, the corpus's
`tools/deadline` case.

`--explain` on a build (D408) also lists, after the lowering, every generic
instance the build made as an `instance-cost` record (D453, H06): `symbol` (the
template, `module.name`), `instance` (which of the template's instances, from
one), `instructions` (its NIR) and `bytes` (its machine code before folding) --
gathered per worker and written in worker order, so a given worker count gives
the same order run to run; under `--json` a record of the build stream, a text
line on stderr otherwise. A harness weighing a specialization reads its cost
here rather than guessing it from the template.

`--instances N` (D426, H06) on a build command is a budget over the
specializations the build makes: after the bodies are checked, the instances of
generic functions they asked for are counted -- each worker's own, since a
module's instances stay with the checker that made them, so a program whose
modules share an instantiation counts it once per worker -- and a count past
`N` is one `E-COMPTIME-0001` diagnostic naming the count and the budget, exit 1,
no image and no manifest. Unlike a deadline it is a work budget: the same
program under the same budget and worker count answers the same way on every
machine. `--stats` reports the count as `function instances`; the corpus's
`tools/instances` case makes three.

`--comptime-steps N` (D474, H24) is the same kind of budget over the interpreter:
every step it took in the whole build -- the constants the main checker settled,
the settled conditions in each worker's bodies -- is summed after the bodies are
checked, and a total past `N` is one `E-COMPTIME-0002` naming the count and the
budget, exit 1, no image and no manifest. Spec §9's ten million steps per
evaluation stand as they are; this is the whole. The corpus's
`tools/comptime_steps` case takes 1210.

The manifest's `unsafe` inventory of a kept module comes from its artifact
(D457): the sites are rendered when the artifact is written, on the worker that
lowered the module, and a warm build copies them -- the manifest phase of the
compiler's own warm build fell from 20 ms to 4 -- scanning only the modules it
parsed, so the inventory is whole either way.

Every `E-SAFETY-*` diagnostic carries `symbol` (D545, H18): the name in its
message's backticks -- the resource local, the view, or the resource type whose
cleanup or fields the rule is about -- so a harness reads the subject as a field,
as D514's name facts and D401's `expected`/`actual` are read.

`--fault-cancel N` (D540, H16) on a build makes the deadline pass at the Nth
statement checked or lowered, so a suite can see a cancellation inside a function
without a clock: the body sweep and the lowering read the deadline every four
thousand and ninety-six statements, and the result's `cancelled_after` names `the
body sweep, inside a function` or `lowering, inside a function`.

`--fault-collision` (D507, H15) on a hot build makes every artifact's key a hit
whatever the text, so a suite can see that a hit is verified beyond the key: a
body edit under it is still rebuilt as `source-changed`. The manifest's input
digests are always the bytes' own, a kept module's included.

`--fault-write N` (D435, H24) on a hot build makes the artifact write of module
`N` (by load order, the root 0) die after its `.tmp` is staged and before the
replace, as a crash there would: the build stops with one `E-CLI-9999`, exit 1,
no image, the staged file left and every artifact published before it whole. A
harness reads what the next build finds -- the module rebuilt as `no-artifact`,
the rest `stable`, the image the clean build's -- which the suites do.

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
when it did. The two hashes together tell a hand edit apart (D418, H19): a
generated file that is not what the map recorded while the input still is was
edited after generation, and that is `E-TOOL-0002` ("regenerate it, or drop the
map to own the edit"), not a stale map -- the harness knows which of the two to
do. Each mapping may carry `edit`: `direct` (the generated output may be
edited in place), `generator` (regeneration-owned: an edit targets the original,
and a hand edit of the generated span is overwritten by the next generation) or
`unknown`; the related location's message says which, and a mapping without `edit`
is `unknown`. An original span is a location, not a fix: nothing in the stream
offers an edit to an original span, since the mapping may be many-to-one. The
compiler never runs a generator; the map's metadata is data.

A generator that read several inputs lists them (D464, H19): `generator.inputs`
is an array of `{"path", "sha256"}`, each path relative to the generated file's
directory, checked in order after `input` (which may be absent when `inputs` is
present); the first that is missing or whose hash is not the recorded one is
`E-TOOL-0001` naming it, and the hand-edit rule (D418) holds only when every
listed input is unchanged. One input that became several declarations is several
mappings to one original span, each diagnostic mapped to it; the corpus's
`combined_inputs.e` is the shape.

A **nested map** (D465, H19): when the original a mapping names is itself a
generated file with a map of its own beside it (`<original>.map.json`, whose
`generated_sha256` is the original's bytes), the compiler follows it one level:
the primary span is the root original's, and `related` carries the intermediate
first ("in the generated input, itself regenerated from the original") and the
generated source second, with the edit rule as before. The chain is bounded at
three levels (D499) -- a root that is itself generated past them is shown as the
root, and every intermediate is related, the one nearest the root first. A nested map
that is present but stale or malformed is not followed, and the related message
says so ("the original is generated too, and its own map is stale"), so a
harness knows the span shown is not the root. Paths in a nested map are
resolved as the outer map's are, relative to the operand's directory; the
corpus's `nested_map.e` and `nested_stale.e` are the two shapes.

Provenance through specialisation (D466, H19): a diagnostic inside a generic
function's body belongs to one instance, and when the checker fails there the
record's `related` carries the site that first asked for that instance --
"in the instance `module.name[T, ...]`, requested here", the arguments as the
`instance` record spells them -- in whichever module asked, as a §2 span of
that module. The template body's span stays primary: it is where the text
that failed is. A diagnostic that already carries a related location (a
resource's other site, D364) keeps it. `reject/instance_site.e` is the shape.
When the instance was asked for by another instance's body (D543, H09), the
chain follows in `related`, innermost first: the site that asked for the failing
instance, then the site that asked for the instance whose body that is, up to
three links, ending at the program's own code. `reject/instance_chain.e` is the
shape: `widen[bool]` requested in `lift`'s body, `lift[bool]` requested in `main`.

The map in the build's identity (D467, H19): the operand's `<file>.e.map.json`,
when it is there, is an entry of the manifest's `inputs` with its `sha256` and
`kind: "source-map"`, after the sources. A map-only change therefore changes
the manifest and nothing else: artifacts, the executable and the incremental
decisions are keyed on the sources, so diagnostics refresh while no code is
rebuilt. Other modules' maps are never read by the compiler and are not
listed.

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
