# Complete code editor control for Neper

Planning snapshot: 2026-10-02. This is an implementation contract, not a
readiness report. `docs/progress.html` remains the only readiness document.
The component inventory is phase P7 in `docs/widget-plan.json`; nothing in
P7 is marked delivered by this planning change.

## Reference and scope

`D:/repos/justcode` uses **CodeMirror 6**, not Monaco. The inspected checkout
is `b27ef93ccd8bc25669079d474563414e599d30f2`, application version 0.4.6.
`package.json` declares the CodeMirror packages; `package-lock.json` resolves
state 6.7.1, view 6.43.6 and autocomplete 6.20.3. `src/editor.js` constructs
`EditorState` and `EditorView`, installs extensions and reconfigures them
through compartments. Tauri supplies the application host.

Here, the requested `e.lib.ui` library means Neper's existing `e.ui.*`
imports under `lib/e/ui`. Add the public control as `e.ui.code_editor`,
implemented in `lib/e/ui/code_editor.e`. Do not introduce a second UI namespace.

The required endpoint has three explicit layers of coverage:

1. Every editor behavior installed or added by the inspected JustCode source.
2. The user-facing editor capabilities of CodeMirror 6's state, view, commands,
   language, autocomplete, search and lint packages, with native equivalents
   for browser-specific hooks.
3. The full code-control services requested here: semantic completion, snippets,
   navigation, refactoring, inline information, diff/merge and provider hooks.
   These extend JustCode's current feature set and are required work, not an MVP
   follow-up that can disappear from the completion criteria.

“All” is bounded by this inventory and reference snapshot. It does not mean
JavaScript API compatibility or every third-party extension ever published.
An extension can express arbitrary application behavior; support its public
extension points and migrate each required behavior as a concrete provider.
Newly discovered reference behavior must be added to P7 before claiming parity.

Sources: [CodeMirror system guide](https://codemirror.net/docs/guide/),
[reference manual](https://codemirror.net/docs/ref/),
[core extension catalogue](https://codemirror.net/docs/extensions/), and
[LSP 3.17 specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/).
The CodeMirror pages were discoverable through official search results but direct
page fetches returned 403; the installed package declarations and JustCode source
are the concrete baseline for this plan. Pin these packages in a parity harness.

## Observed JustCode behavior and destination

| Source in `D:/repos/justcode` | Behavior to preserve | Work packages |
|---|---|---|
| `src/editor.js` | Per-tab state, transactions, history, multicursor and rectangle selection, drop cursor, active line/gutter, special characters, brackets, indentation, folding, typed completion | P7-01 through P7-11 |
| `src/editor.js` | Theme/font/wrap/spell/bionic reconfiguration; read-only placeholder; background-tab language changes guarded against races; focused-pane status updates | P7-05, P7-12, P7-15, P7-17 |
| `src/languages.js` | Lazy language loading, retry after failure, extension mapping, embedded JS/CSS in HTML, JS local/global completion, SQL dialects, plain-text fallback | P7-07, P7-08, P7-11 |
| `src/search.js` | Find/replace, case/regex/whole-word toggles, next/previous, replacement expansion, top panel, N-of-M and bounded 999+ count | P7-10 |
| `src/bookmarks.js` | Three numbered slots per document, toggle/jump, edit-mapped positions, dynamic gutter width | P7-06 |
| `src/links.js` | Visible-range HTTP/HTTPS/mailto detection, punctuation trimming, modifier hover/click and keyboard activation | P7-06, P7-14 |
| `src/linters.js` | Parser recovery diagnostics; Acorn JS checks; HTML/embedded-script, CSS, XML, JSON, Rust and YAML checks; no invented errors for unlinted modes | P7-07, P7-08, P7-12 |
| `src/spellcheck.js` | Lazy dictionary, suggestions/corrections, code-word exclusions, separate spelling count, immediate refresh and marker removal when disabled | P7-12 |
| `src/theme.js` | Dark, light and autism palette; complete editor/panel/gutter styling | P7-15 |
| `src/symbols.js` | Filterable local declaration outline and jump; approximate extraction for stream modes | P7-14 |
| `src/main.js` | Cut/copy/paste, delete/move/duplicate lines, smart comment toggle, upper/lowercase, case-sensitive line sort, GUID insertion | P7-03, P7-09 |
| `src/main.js` | Tabs and up to four split panes; tab movement/dragging/closing; focused status; saved-state comparison; external-file-change handling | P7-04, P7-17 |
| `src/main.js`, `src/i18n.js` | Menu/context command enablement, keyboard reference, zoom/reset, wrapping, spelling and bionic toggles, localization | P7-15, P7-17 |

JustCode's Go to Symbol is a local outline, not proof of project-wide semantic
Go to Definition. Its completions come from language packages and its JavaScript
global-scope source. No LSP client was found in the inspected editor path.
Semantic providers, hover, rename, minimap and diff below are additional targets;
do not describe them as already implemented by JustCode.

## Architecture and contracts

Reuse `e.ui.widget`, `e.ui.style`, `e.ui.overlay`, `e.ui.collection`,
`e.ui.navigation`, `e.ui.accessibility`, `e.ui.testing` and the existing scene.
Use text/Unicode/segmentation/bidi/layout/shaping, regex/search/diff, JSON,
process/pipe and clipboard services already present. Add helper modules only
when a landed implementation actually needs a separate reusable contract.

The editor needs one runtime integration point because it owns input, focus,
virtualization, hit testing and editable semantics. A painted `Custom` node alone
has insufficient editing semantics; wrapping the current flat `widget.Edit`
in colored spans has insufficient storage and selection semantics. Introduce
the smallest editor runtime kind that routes those operations to the persistent
editor view. Menus, tooltips and panels remain ordinary composites.

| Proposed public concept | Ownership and responsibility |
|---|---|
| `Document` | Caller-owned arena/storage; UTF-8 content, identity, revision, line index, snapshots, history and saved revision |
| `View` | Stable caller-held state per view: selections, affinity, scroll, wrap, local folds and configuration; several views may share one document |
| `Transaction` / `Edit` / `ChangeMap` | Validated batch over one base revision; content and selection changes, origin, effects and history grouping; maps old positions into new content |
| `Options` / `Theme` | Explicit editor configuration and token styles; runtime reconfiguration invalidates only affected caches |
| `Language` / `Provider` | Language metadata and explicit callback context for tokens, structure and asynchronous services |
| `Decoration` / `Gutter` | Document ranges or view-local ranges, inclusive boundary policy, layer, metrics, hit action and semantic description |
| `Request` / `Result` | Document ID, revision, view ID, request ID and cancellation; results copied into owned storage before provider scratch is reset |
| `code_editor(...) -> (widget.Node, err)` | Borrows live document/view/controller; widget rebuild does not replace content or undo history |
| `dispatch(...)`, `command(...)`, query/event hooks | All edits use the same validated transaction path, including clipboard, completion, formatter and programmatic mutation |

These are design names, not declarations to insert into `module-apis.md` today.
Use explicit context pointers and caller storage rather than closures or hidden
heap ownership, matching the existing library.

Hard invariants:

- Public offsets are UTF-8 byte boundaries; caret movement respects grapheme
  clusters and bidi affinity. Line/column conversion explicitly names its units.
  LSP adapters negotiate UTF-8/UTF-16/UTF-32 and never equate byte and UTF-16 columns.
- A batch is sorted, non-overlapping and applied against one revision. Duplicate
  cursors/overlapping selections normalize deterministically; ambiguous edits
  fail before mutation. Every edit path enforces document/region read-only rules.
- Reserve text, metadata, inverse edits and history space before committing.
  Allocation/capacity failure leaves content, history, selections and saved state
  intact. Never accept half a replacement or half a workspace edit.
- Map selections, marks, diagnostics and provider requests through changes with
  explicit before/after association and deletion policy. Sharing content does not
  silently share every view's selection/folds/scroll.
- Cancel or discard stale asynchronous work after edits, tab/language switches,
  view destruction and provider replacement. A late result cannot edit a new tab.
- Paint, hit testing, gutters, minimap and IME candidate placement use the same
  row geometry. Zoom, DPI, font fallback, wrapping, folds and inline widgets
  invalidate that geometry together.
- Provider failure cannot prevent plain-text editing. Keep capability failure
  observable, support retry, and retract markers when a provider is disabled.
- No command executes arbitrary shell text or opens a URL merely because a server
  or diagnostic supplies it. Host actions go through typed application callbacks.

Storage: evaluate `e.data.rope` first. Its current nodes mutate in place, use
u32 weights and append-only caller pools; it is not a ready-made persistent,
balanced editor document. Reuse/extend it with balancing, newline metrics,
capacity preflight and reclamation if it passes P7-01's checks. Otherwise use
one measured balanced piece tree over original/add buffers. Do not ship both
backends or rebuild the entire line index on every keystroke. Snapshot/history
lifetimes must survive compaction without dangling references.

Native prerequisites are real work. `e.ui.input` currently conflates physical
and logical keys and does not deliver IME composition. `e.text.layout` documents
two-level bidi and `e.text.shape` skips contextual and mark-attachment lookups.
Reuse the full `e.text.bidi` kernel and close shaping/layout gaps needed for
mixed scripts. Native accessibility adapters must expose editable text ranges,
not just a generic named widget. Synthetic composition events alone do not
complete the native input task.

## Ordered work packages and acceptance checks

All packages are mandatory. Order follows P7's serial inventory. The dependency
column also identifies work that can be scheduled independently if that becomes
authorized later; it does not add an agent workflow.

| ID | Implement | Depends on | Minimum evidence that closes the package |
|---|---|---|---|
| P7-01 | Document/storage, line metrics, snapshots, atomic changes, position mapping, revision/lifetime/error contracts | Existing memory/text kernels | Differential edit sequences against a flat reference; newline and UTF conversions; adversarial edits stay balanced; failure injection leaves state unchanged; compaction preserves held history/snapshots |
| P7-02 | Native physical/logical keys, modifiers/repeat, dead keys, composition start/update/commit/cancel, IME candidate rectangle, mouse/touch/pen and editable accessibility bridge | P7-01, host input adapters | Windows and Linux native IME/dead-key sessions plus deterministic event replay; correct zoomed candidate placement; composition committed as one undo item |
| P7-03 | Navigation and selection by grapheme/word/subword/line/page/document; visual bidi movement; preferred X; multicursor; rectangles; pointer granularity; drag/drop; cut/copy/paste; primary selection where available | P7-01, P7-02 | Replayed keyboard/pointer traces covering emoji/combining marks, wrapped rows, RTL, overlap normalization and multi-range clipboard round trips |
| P7-04 | Undo/redo, selection history, typing coalescing, explicit groups, inverse edits, saved state, limits/reclamation and snapshot serialization | P7-01, P7-03 | Paste/completion/replace-all each undo once; save/undo/redo/branch/eviction keep dirty state truthful; two views survive document changes |
| P7-05 | Virtual rows; cached shaping/layout; scrollbars/overscan/scroll anchoring; wrap; tab stops; horizontal scroll; caret/drop cursor; geometry queries; zoom/DPI; long lines; bidi/fallback fonts; touch selection handles | P7-01 through P7-03 | Same geometry drives painted glyphs, selection, hits and gutters; wrapped/folded long-file scroll/zoom has no drift; bounded work per visible region |
| P7-06 | Range sets; inline/line/block/replacement/atomic decorations; custom widgets/layers; gutter API; numbers/current line; folds/diagnostics/bookmarks/change/breakpoint marks; whitespace, rulers, indentation guides | P7-01, P7-05 | Marks map through insert/delete/undo; three-slot bookmarks match JustCode; gutter baseline and hit regions remain correct after wraps/zoom/inline blocks; selection stays visible |
| P7-07 | Language metadata, lazy/retryable load and hot switch; incremental tokens and parse regions; mixed languages; cancellation/budgets; semantic overlay; neutral token themes; error recovery | P7-01, P7-05, P7-06 | Edit a multiline comment/string and embedded JS/CSS; downstream tokens converge without full-file synchronous rescans; late grammar loads cannot switch the wrong view |
| P7-08 | Every baseline language/dialect pack below; extension mapping and override; grammar/token, indent/comment/bracket/fold/completion/symbol metadata | P7-07 | Per-language valid/invalid/unfinished-source fixtures and long edits; compare baseline styling/structure/completion where supported; raw strings and custom modes match their reference rules |
| P7-09 | Autoindent/dedent, indent selection, tab policy, smart newline, bracket/quote pairs and matching, tag close/match, comments, structural fold/select; delete/move/duplicate/join/split/transpose/sort/case commands; GUID insertion callback | P7-03, P7-07, P7-08 | Each transformation is one transaction across all selections; repeated comment toggle round-trips; brackets/tags obey strings/comments and mixed-language boundaries |
| P7-10 | Incremental literal/regex search, whole word/case, selection scope, next/previous/wrap, highlight/select matches, match counter, replace next/all, capture expansion, query persistence and accessible panels | P7-01, P7-03, P7-06 | Unicode, multiline/zero-width and invalid regex cases; 999+ count without blocked typing; cancellation/time-limit error visible; replace-all is atomic and undoable |
| P7-11 | Local/provider completion, trigger/manual invocation, scoring/filter/sort/sections/icons/docs, async cancel/cache/resolve, replacement/additional edits/commit characters, snippets/tabstops/choices/mirrors, inline ghost text | P7-03, P7-07, P7-08 | JS local/global and SQL metadata completion; quick switch/edit rejects stale results; Unicode replacement and multicursor snippets undo once; nested fields and Escape/Tab preserve editor focus |
| P7-12 | Revisioned diagnostics, severity/source/code/related ranges, squiggles/gutters/tooltips, problems navigation/list/counts, quick fixes; spell dictionaries/suggestions/ignore words/exclusions; refresh/retraction | P7-06 through P7-08 | Baseline lint checks, delayed diagnostics, zero-width errors and correction undo; disabling spelling clears marks/counts; spelling remains separate from syntax errors |
| P7-13 | LSP base framing/JSON-RPC, process or supplied transport, lifecycle/capabilities, document sync/versions/encodings, cancellation/timeouts, progress/restart, workspace/configuration/file events and bounded messages | P7-01, P7-07; process/JSON services | Recorded fragmented/coalesced protocol streams and a real server session; malformed messages/exit/restart do not lose text; negotiate encoding and reject obsolete versions |
| P7-14 | LSP/service adapters for completion/hover/signatures, definition/declaration/type/implementation/references, symbols/outline/breadcrumbs, rename/actions/formatting, semantic tokens/folds/selection ranges, links, code lens, inlays/colors/linked editing/inline values, hierarchies and workspace edits | P7-09 through P7-13 | Real Neper provider plus representative external server; supported/unsupported features correctly exposed; versioned multi-file edit preflight, apply/undo and resource-operation refusal checked |
| P7-15 | Config compartments/precedence and extension lifecycle; state/effect/update filters; keymaps/chords/platform bindings; themes/token roles; dark/light/autism/high contrast; fonts/ligatures/zoom; bionic decoration; localization and accessible popups | P7-03, P7-06, P7-11, P7-12 | Reconfigure active/background tabs without losing history; keymap priority and chord timeout; active-line selection layering; Bionic toggle changes paint only; all popup commands work by keyboard |
| P7-16 | Side-by-side/unified diff, merge/conflicts/hunk actions, alignment/folded unchanged regions; minimap/overview ruler/sticky context; breakpoint/execution gutter callbacks; collaboration transaction/presence adapter | P7-01, P7-05, P7-06, P7-14 | Large diff incremental update; hunk accept/reject/undo; three-way conflict preservation; mapped remote carets; local undo does not erase remote edits; no debugger/collaboration server required inside the widget |
| P7-17 | Shared documents and independent views; tab/split shell integration; state restore; dirty/status events; command/context menu hooks; encoding/EOL/save/reload conflicts; preview/run/terminal/explorer host hooks; print/export | P7-04, P7-05, P7-14, P7-15 | Four-pane JustCode parity example; only focused pane updates status; safe reload/save races; session round-trip including selection/scroll/folds/bookmarks; typed host commands and print layout verified |
| P7-18 | Full parity scenario suite; allocation/error/security fuzz cases; native accessibility/IME matrix; performance harness and retained-scene samples; API examples and documentation | All earlier packages | Every inventory component has implementation and reproducible evidence; both self-host targets and native interaction matrix pass; all declared performance budgets are measured |

## Language coverage

Preserve these **35 registry IDs**, including dialects/variants. The grouped
inventory components are packaging units, not permission to omit a language.
Every pack declares the operations it supplies; semantic services are separate
provider capabilities. Do not claim semantic completion just because keywords
can be completed.

| Inventory component | Required IDs | Reference behavior and extra required work |
|---|---|---|
| `CodeWebLanguages` | `html`, `css`, `javascript` | HTML nested JS/CSS, closing/matching tags; JS local/global names; CSS properties/values; baseline specialized lint |
| `CodeTypedWebLanguages` | `typescript`, `jsx`, `tsx` | Grammar variants; no plain-JS Acorn false positives; semantic completion via provider |
| `CodeProseLanguages` | `markdown`, `text` | Markdown structure/embedded fenced languages; text/txt/log/csv neutral mode; spelling and reading decoration; no false invalid-Markdown diagnostic |
| `CodeSystemsLanguages` | `cpp`, `rust`, `go` | C/C++ extensions and language override; Rust recovery diagnostics; Go stream baseline; semantic providers |
| `CodeManagedLanguages` | `java`, `csharp`, `kotlin`, `swift`, `dart` | Preserve grammar versus stream metadata differences; independent provider capabilities |
| `CodeScientificLanguages` | `python`, `r` | Indentation/string rules; Python semantic services and R keyword/stream baseline |
| `CodeDataLanguages` | `json`, `yaml`, `xml`, `toml`, `protobuf` | JSON validation; YAML recovery; XML balance and Delphi project files; TOML/protobuf token modes. Preserve `.jsonc` association but explicitly support comments rather than silently treating JSONC as invalid strict JSON |
| `CodeSqlDialects` | `sql`, `sqlite`, `mysql`, `postgresql` | Distinct keyword/quoting rules; caller-provided schemas/tables/columns; no database connection hidden in control |
| `CodeScriptLanguages` | `powershell`, `shell`, `batch`, `terraform` | Existing stream/custom modes including HCL heredocs, comments and interpolation; host-run action separate from parsing |
| `CodeNeperPascalAssembly` | `neper`, `objectpascal`, `assembly`, `intelasm` | Neper lexer authority and raw-string hashes; Pascal comments/strings/declarations; GNU as versus NASM/MASM rules kept separate |

Implement Neper first as the native reference language, then web/data, then the
remaining packs; the package closes only after all ten JustCode groups, all 35
baseline IDs and all 16 additional TIOBE entries below. Preserve both sets.
Translate behavior and test cases from JustCode; account for upstream licences
if copying grammar data/code. Do not put JavaScript/Lezer in the native rendering
path. A web host may reuse CodeMirror behind an adapter if desired, but it cannot
stand in for the required native control.

### Explicit JustCode language and file-extension matrix

Every row below is mandatory P7-08 scope, verified against JustCode's
`src/languages.js`. “Parser” and “stream” describe the reference implementation,
not the required native implementation technique. The final column records
JustCode's installed lint checks; an empty lint capability must never manufacture
syntax errors. Semantic completion, navigation and refactoring use the P7-11
through P7-14 provider contracts independently of the baseline tokenizer.

| Language | Registry ID | File extensions | Reference mode | Reference lint |
|---|---|---|---|---|
| HTML | `html` | `.html`, `.htm`, `.xhtml` | Parser; embedded JavaScript/CSS | HTML, CSS and executable embedded JavaScript checks |
| CSS | `css` | `.css` | Parser | Syntax and missing declaration values |
| JavaScript | `javascript` | `.js`, `.mjs`, `.cjs` | Parser; local/global completion | Acorn and syntax recovery |
| TypeScript | `typescript` | `.ts`, `.mts`, `.cts` | Parser variant | None installed |
| JavaScript JSX | `jsx` | `.jsx` | Parser variant | None installed |
| TypeScript TSX | `tsx` | `.tsx` | Parser variant | None installed |
| Markdown | `markdown` | `.md`, `.markdown`, `.mdown`, `.mkd` | Parser | None installed |
| Python | `python` | `.py`, `.pyw`, `.pyi` | Parser | None installed |
| C / C++ | `cpp` | `.c`, `.cc`, `.cpp`, `.cxx`, `.h`, `.hpp`, `.hh`, `.hxx` | Parser | None installed |
| Java | `java` | `.java` | Parser | None installed |
| C# | `csharp` | `.cs`, `.csx` | Stream | None installed |
| Kotlin | `kotlin` | `.kt`, `.kts` | Stream | None installed |
| Swift | `swift` | `.swift` | Stream | None installed |
| R | `r` | `.r` | Stream | None installed |
| TOML | `toml` | `.toml` | Stream | None installed |
| Protocol Buffers | `protobuf` | `.proto` | Stream | None installed |
| Go | `go` | `.go` | Stream | None installed |
| Rust | `rust` | `.rs` | Parser | Syntax recovery |
| GNU assembly | `assembly` | `.s` | Stream | None installed |
| Intel assembly (NASM/MASM) | `intelasm` | `.asm`, `.nasm` | Custom stream | None installed |
| Neper | `neper` | `.e` | Custom stream | None installed |
| JSON / JSONC associations | `json` | `.json`, `.jsonc`, `.webmanifest` | Parser | Strict JSON parsing; native JSONC support required separately |
| YAML | `yaml` | `.yaml`, `.yml` | Parser | Syntax recovery |
| XML / Delphi project XML | `xml` | `.xml`, `.dproj`, `.xsd`, `.xsl`, `.xslt` | Parser | Tag balance and syntax checks |
| Standard SQL | `sql` | `.sql` | Parser/dialect | None installed |
| SQLite SQL | `sqlite` | `.sqlite`, `.sqlite3` | Parser/dialect | None installed |
| MySQL SQL | `mysql` | `.mysql` | Parser/dialect | None installed |
| PostgreSQL SQL | `postgresql` | `.pgsql`, `.psql` | Parser/dialect | None installed |
| Dart | `dart` | `.dart` | Stream | None installed |
| Object Pascal / Delphi / Free Pascal | `objectpascal` | `.pas`, `.pp`, `.dpr`, `.dpk`, `.lpr`, `.inc` | Custom stream | None installed |
| PowerShell | `powershell` | `.ps1`, `.psm1`, `.psd1` | Stream | None installed |
| Shell | `shell` | `.sh`, `.bash`, `.zsh`, `.ksh` | Stream | None installed |
| Terraform / HCL | `terraform` | `.tf`, `.tfvars`, `.hcl` | Custom stream | None installed |
| Windows Batch | `batch` | `.bat`, `.cmd` | Custom stream | None installed |
| Plain text / logs / CSV | `text` | `.txt`, `.log`, `.csv` | Plain text | None installed |

Each language must have explicit metadata for token styles, comments, indentation,
brackets/quotes, folding, completion and symbols. Supply working language rules
where applicable; expose a capability as unavailable where the syntax has no such
operation. All code languages require offline keyword/document-word/snippet
completion as well as the shared semantic-provider interface. Plain text keeps
editing/search/spelling and word completion without invented code structure.

Acceptance requires a fixture per registry ID and extension lookup checks for
every listed suffix. Compare multiline strings/comments, incomplete input,
indent/comment operations, brackets, fold boundaries, completion and symbols
against the reference wherever supplied. Check case-insensitive suffix mapping
(including `.S` and `.R`), explicit language override for ambiguous `.h`/`.inc`
files, C++'s `.cpp` new-file default, unknown-suffix plain-text fallback and lazy
load failure/retry. SQL suffixes are reference editor associations, not proof that
an on-disk `.sqlite` file is text; binary database content must be refused or opened
through a separate database viewer. Add future JustCode registry entries to both
this matrix and the appropriate P7-08 pack before claiming ongoing parity.

### TIOBE top-30 coverage in addition to JustCode

Snapshot checked 2026-10-02: the latest published
[TIOBE Index](https://www.tiobe.com/tiobe-index/) is **September 2026**.
The ranking below pins the required top 30; TIOBE labels ranks 21–50 as its
unofficial extended table. C# and Java were already in JustCode coverage;
PHP and the other missing entries are now mandatory P7-08 components.

| Rank | TIOBE language | Owning P7-08 component | Mode/adapter ID |
|---|---|---|---|
| 1 | Python | `CodeScientificLanguages` | `python` |
| 2 | C | `CodeSystemsLanguages` | `cpp` with explicit C dialect |
| 3 | C++ | `CodeSystemsLanguages` | `cpp` |
| 4 | Java | `CodeManagedLanguages` | `java` |
| 5 | C# | `CodeManagedLanguages` | `csharp` |
| 6 | JavaScript | `CodeWebLanguages` | `javascript` |
| 7 | Visual Basic | `CodeVisualBasicNet` | `vbnet` |
| 8 | SQL | `CodeSqlDialects` | `sql` |
| 9 | R | `CodeScientificLanguages` | `r` |
| 10 | Rust | `CodeSystemsLanguages` | `rust` |
| 11 | Fortran | `CodeFortranLanguage` | `fortran` |
| 12 | Go | `CodeSystemsLanguages` | `go` |
| 13 | Delphi/Object Pascal | `CodeNeperPascalAssembly` | `objectpascal` |
| 14 | PHP | `CodePhpLanguage` | `php` |
| 15 | Scratch | `CodeScratchProjects` | `scratch` project adapter |
| 16 | Assembly language | `CodeNeperPascalAssembly` | `assembly`, `intelasm` |
| 17 | Ada | `CodeAdaLanguage` | `ada` |
| 18 | Swift | `CodeManagedLanguages` | `swift` |
| 19 | Objective-C | `CodeObjectiveCLanguage` | `objectivec` |
| 20 | COBOL | `CodeCobolLanguage` | `cobol` |
| 21 | Julia | `CodeJuliaLanguage` | `julia` |
| 22 | Ruby | `CodeRubyLanguage` | `ruby` |
| 23 | Perl | `CodePerlLanguage` | `perl` |
| 24 | SAS | `CodeSasLanguage` | `sas` |
| 25 | Classic Visual Basic | `CodeClassicVisualBasic` | `vbclassic` |
| 26 | Kotlin | `CodeManagedLanguages` | `kotlin` |
| 27 | MATLAB | `CodeMatlabLanguage` | `matlab` |
| 28 | Caml | `CodeCamlLanguage` | `caml` |
| 29 | Prolog | `CodePrologLanguage` | `prolog` |
| 30 | GML | `CodeGmlLanguage` | `gml` |

The added implementation contracts are:

| Component | Proposed file suffixes | Required language-specific behavior |
|---|---|---|
| `CodeVisualBasicNet` | `.vb` | .NET syntax, case-insensitive keywords, line continuation, XML literals and block indentation/folding; .NET semantic provider |
| `CodeFortranLanguage` | `.f`, `.for`, `.f77`, `.f90`, `.f95`, `.f03`, `.f08` | Fixed/free source forms, continuation and column rules, strings/comments, module/procedure outline and provider services |
| `CodePhpLanguage` | `.php`, `.phtml`, `.php3`, `.php4`, `.php5`, `.phps` | PHP mixed with HTML/CSS/JS, heredoc/nowdoc/interpolation, namespaces/classes/functions, modern syntax and PHP semantic provider |
| `CodeScratchProjects` | `.sb3`; decoded `project.json` | Structured project/block data adapter with editable source projection and block inspector, opcode/variable/procedure completion, block-reference diagnostics, assets preserved on import/export |
| `CodeAdaLanguage` | `.adb`, `.ads`, `.ada` | Case-insensitive keywords, package/body/spec outline, attributes and based literals, matching constructs and semantic provider |
| `CodeObjectiveCLanguage` | `.m`, `.mm`, `.h` | Objective-C and Objective-C++ variants, selectors/messages, directives and class/protocol outline; C/C++ provider integration |
| `CodeCobolLanguage` | `.cob`, `.cbl`, `.cpy` | Fixed/free formats, column/continuation rules, divisions/sections/paragraphs, COPY metadata and provider diagnostics |
| `CodeJuliaLanguage` | `.jl` | Unicode identifiers, macros, interpolation/multiline strings, multiple-dispatch declarations and provider services |
| `CodeRubyLanguage` | `.rb`, `.rake`, `.gemspec` | Heredocs, interpolation, percent literals, matching blocks, classes/modules/methods and provider services |
| `CodePerlLanguage` | `.pl`, `.pm`, `.t` | Sigils, quote-like/regex operators, heredocs/POD, package/subroutine outline and provider services |
| `CodeSasLanguage` | `.sas` | DATA/PROC steps, macro language, comment/string rules, step folding, local/schema completion and provider hooks |
| `CodeClassicVisualBasic` | `.bas`, `.cls`, `.frm` | VB6/VBA-style source rules, distinct from VB.NET; module/procedure outline, form-source preservation, local completion and provider hooks |
| `CodeMatlabLanguage` | `.m` | Matrix literals versus strings/transposes, sections, functions/classes, block structure, local/toolbox completion and provider hooks |
| `CodeCamlLanguage` | `.ml`, `.mli` | Caml syntax, nested comments, patterns, declarations and local completion; explicit dialect metadata and provider hooks |
| `CodePrologLanguage` | `.pl`, `.pro` | Facts/rules, operators, quoted atoms, variables, predicate/arity outline, local predicate completion and provider hooks |
| `CodeGmlLanguage` | `.gml` | GameMaker functions/events, directives, strings/comments, built-in symbol metadata and provider hooks |

Suffixes here are planned associations, not new JustCode claims. Shared suffixes
require project/dialect metadata or explicit user selection: `.m` must distinguish
MATLAB from Objective-C, `.pl` Perl from Prolog, `.ml` the selected Caml dialect,
and `.h` C/C++ from Objective-C. Register conventional extensionless Ruby files
such as `Gemfile` and `Rakefile` through filename metadata. Never guess a language
from a filename and silently rewrite incompatible syntax.

Reuse the normal language/provider contracts for each text language: highlighting,
indent/comments/brackets/folding, offline completion/snippets, outline and
diagnostics/semantic services when a supporting provider is connected. No new
language closes with only an extension association or a keywords-only demo.
Acceptance checks include valid/unfinished/malformed code, edit invalidation,
dialect cases and unavailable-provider behavior. C needs actual C dialect rules
and completion metadata rather than treating every `.c` file as C++.

Scratch's archive cannot be opened as ordinary UTF-8 source. Use a bounded archive
and JSON adapter based on the [Scratch project serializer](https://github.com/scratchfoundation/scratch-vm/blob/develop/src/serialization/sb3.js),
preserving targets, block links, variables, procedures, extension metadata and
opaque assets. Provide lossless no-edit and edited round-trip fixtures, unknown
opcode preservation and damaged/oversized archive refusal. The code editor hosts
the structured source projection; a visual block workspace is a separate host
integration. Neither plain JSON coloring nor renaming `.sb3` to `.json` counts as
Scratch support. Caml dialect selection must account for
[Caml Light](https://caml.inria.fr/caml-light/) rather than silently substituting
OCaml, which TIOBE lists separately. GML means
[GameMaker Language](https://manual.gamemaker.io/monthly/en/GameMaker_Language/GameMaker_Language_Index.htm).

P7-08 now covers **51 required modes/adapters**: 35 JustCode IDs plus 16 additions.
P7 totals **247 components** across the same 18 work packages. A closure check must
map all 30 ranked entries to working packs/adapters and retain the complete
JustCode matrix. Refresh the TIOBE snapshot before implementation release; add
new top-30 entrants without removing an already promised language. Refreshes are
manual scope checks, not a scheduled monitor.

## Completion and language-service details

Local completion works without a server: keywords, document words, parsed local
scope, snippets, language built-ins and supplied SQL/schema/member data. Merge
sources with deterministic ordering and deduplication; define `valid_for` reuse,
trigger characters, manual invocation and whether incomplete lists need reruns.
Typing during a request must not flash a stale list. Support label detail,
kind/section, filter/sort text, preselection/deprecation, documentation resolution,
replacement range, commit characters, insert/replace edits, additional edits and
post-accept host commands. Snippets include numbered/final tabstops, linked fields,
choices, escapes and variable/default/transform handling with bounded evaluation.
Inline completion has explicit accept-word/line/all and dismissal commands.

LSP 3.17 is the pinned transport baseline, not a claim that all servers implement
every optional feature. Negotiate dynamic registration, position encoding,
incremental/full synchronization, save notifications, workspace folders and file
operations. Implement push/pull diagnostics and refresh requests; completion,
hover, signatures, locations/location links, references/highlights, document and
workspace symbols, prepare/rename, code actions and resolution, full/range/on-type
formatting, semantic tokens full/range/delta, folding and selection ranges,
document links, code lens and resolution, inlay hints and resolution, document
colors/presentations, linked editing, inline values, call/type hierarchies and
monikers. Support configuration, watched-file events, applyEdit, progress,
work-done/partial results, show/log messages and server crash recovery through
host hooks. Never advertise a feature that has only an empty handler.

Inline completion and collaboration are explicit provider extensions where the
pinned LSP does not supply their contract. Reuse Neper's tooling for tokens,
diagnostics, symbol index, formatting and planned refactors; `src/tool.e` is not
evidence that a completion server already exists. Add the missing semantic
completion adapter rather than inferring types from colored text. Compiler work
stays outside the UI thread; unfinished code must still yield useful partial
results. Test a local fake provider for every service and representative live
servers for Neper, TS/JS, Rust and Python; versions are pinned when implemented.

Workspace edits first validate versions, URIs, writable ranges and capacities for
all documents. Disk creates/deletes/renames belong to the host's recoverable file
transaction, with explicit conflicts and undo policy; never imply a partially
completed filesystem operation was atomic. Rendering server Markdown must treat
it as untrusted content and keep external links behind host activation.

## Boundaries with application features

The control exposes events/hooks for file opening, persistence, preview, run,
terminal, explorer, status bars, debugger and remote transport. Existing
`e.ui.navigation` tab/editor-group/split controls and `e.ui.app` services own the
shell. P7-17's example must wire every corresponding JustCode interaction, so
separating ownership does not drop a feature. Implement missing shell behavior
in its existing owner rather than putting a terminal or file browser inside
the editor buffer engine. File associations and recent-file policy remain host
services; the example demonstrates the hooks and their command enablement.

Remote edit and presence providers map into the same transaction/decorations
contracts. Reuse existing collaboration/text algorithms where suitable, then
verify convergence and local-undo semantics; a transaction callback alone is
not evidence of working collaborative editing. Debugger/execution marks are
interactive gutter services; protocol/process launching is the application's.
CodeMirror diff/merge ecosystem equivalents are native views over `e.text.diff`.
Minimap, overview ruler and sticky context share viewport/structure data rather
than maintaining a second document model.

## Delivery, measurement and definition of done

P7 is next-release work, matching the existing P6 convention. P7 depends on P5's
UI contracts, not P6's unrelated motion catalogue. The current serial picker
still visits P6 first; reordering/releasing work is a separate queue decision.
Within P7, deliver one inventory component at a time and close prerequisites
before dependent behavior. No partial release may be labelled complete parity.

For each landed capability, follow `AGENTS.md`: update the actual active first
work-queue record truthfully; retain it while partial; at score 1 append its
record to `docs/work-done.jsonl` and remove it from the queue. Add P7 execution
records through the normal queue process before starting implementation; L065
now tracks the complete editor capability at the end of the backlog, with score
equal to the fraction of P7's 247 components delivered with evidence. Full
completion also requires every package acceptance check. Do not overwrite the
current chart record's evidence with editor claims. Update P7's
`delivered`/`evidence`, module contracts/fixtures when implemented, append design
decisions, regenerate progress and commit only the touched paths. Planning alone
does not advance any capability score or declare a new implemented module.

Use the existing fixture and UI testing harness, not a new test framework.
Record deterministic transaction traces and expected document/selection/mark
outputs; replay shared behaviors in pinned CodeMirror and the native control.
Fixtures must cover both Windows and Linux self-hosted builds. Native checks
also cover screen readers, IMEs, non-US keyboards, clipboard, high contrast,
touch/pen where supported, 100/150/200% DPI and mixed-script text. macOS/mobile
native guarantees require their host adapters and tests; absence is an explicit
blocked platform capability, never a silent desktop fallback.

Initial performance acceptance targets, to be measured on named hardware:

| Workload | Target and recorded evidence |
|---|---|
| 1 MiB / 10k-line source, normal editing | p95 input-to-paint <=16.7 ms, p99 <=50 ms; parsing/completion excluded from the synchronous mutation path |
| 10 MiB / 100k-line source | first editable viewport <=500 ms after bytes are supplied; p95 edit <=33 ms; viewport paint visits visible rows plus bounded overscan |
| 100 MiB / 1M lines, 1 MiB single line, 1000 cursors | no blocking full-document shaping or unbounded scan on input; incremental/cancellable preparation; report latency, peak storage and refusal limits |
| Resize/wrap/font/zoom/folding | stable scroll anchor and gutter/text alignment; sample screenshots and per-frame layout/damage counts |
| Long-running repeated edits and undo/redo | bounded retained storage under declared limits; compaction/reclamation preserves live references; no steady growth caused by abandoned provider requests |

Targets are requirements to validate, not measurements achieved today. Large-file
budgets may schedule expensive features incrementally; they cannot silently
disable required capabilities and still claim full coverage. Capacity options
and explicit `TooLarge`/unsupported/conflict/stale errors must be documented.
Benchmark distributions and memory alongside matching pinned CodeMirror traces;
browser versus native timing differences are reported, not concealed.

P7 completes only when every listed component has working code, reproducible
evidence, documentation and platform coverage; the JustCode parity example passes
every source-map row; optional provider capabilities work with a real supporting
provider; read-only/error/Unicode/lifetime invariants hold; and performance targets
pass or are changed through an explicit recorded design decision. A control that
only colors text, returns a dummy completion list, or has unconnected gutters
cannot complete this plan.
