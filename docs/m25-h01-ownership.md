# M2.5 stage B: H01 -- ownership, resource states and cleanup

Sections 1-14 are the proposal as written before the D rows; section 15 is the
closure record (D352) -- what was built, where it differs, what it measures and
what remains. Where the two disagree, section 15 is the language.

The design H01 of [`post-m2-llm-hardening.md`](post-m2-llm-hardening.md) section 4
asks for, written against the language as it stands (spec section 5's `defer`, the
multiple-return `(T, err)` model, `zero`/`undef`, the fixed `e.os` surface) and
against the compiler that will have to check it. It is a recommendation with its
alternatives; nothing here is decided until its D row is recorded, and the questions
at the end are the ones the row must answer. H02 (regions and borrows), H04 (scoped
concurrency) and H05 (by-value snapshots) build on the identity model here and are
written after it locks; where they need a hook it is named.

The shape is the smallest model that meets H01's acceptance list: a **resource type**
is affine (moved at most once) and, when it names a cleanup, **obligated** (consumed
on every exit); ownership moves through signatures marked `own`; everything else
borrows as it does today. No hidden destructors, no new runtime, no reference
counting; a checker pass over states the checker already walks.

## 1. Resource types

```
type File = resource(close) struct { raw: usize }     // affine, obligated: close
type Arena = resource struct { base: *u8, cap: usize, off: usize }   // affine only
```

`resource` before a `struct` or `union enum` body makes the type a resource type.
The optional `(name)` names the type's **cleanup**: a function of the declaring
module with the signature `fn name(x: own T) -> err` (or `-> void`), which consumes
the value. A resource type without a cleanup is affine and nothing more: it cannot
be duplicated, but nothing has to be done with it.

**Containment.** A type is affine if it is a resource type or has a field, element,
member or type argument that is affine: a struct holding a `File`, an array of them,
a slice `[]File`, a `List[File]`, a union enum with a `File` payload. Such a type is
obligated if any contained type is. There is no way to opt a container out; a
container that wants to hold handles without owning them holds borrows (`*File`)
or the raw bits behind an unsafe boundary (section 8).

**Representation.** The fields of a resource type are visible only in its declaring
module: `f.raw` and the literal `File { raw: 3 }` outside `e.os` are refused
(E-SAFETY-0010). This is the narrow opacity H01 asks for, and the whole of it; no
general visibility system. Inside the module the fields are ordinary.

## 2. Ownership and moves

An owned resource value lives in exactly one place. These **consume** it:

| form | what happens |
|---|---|
| `let y = x`, `var y = x` | `x` moves into `y`; `x` is unusable after |
| `y = x` | moves; the old value of `y` must be null or already moved (section 5) |
| `f(x)` where the parameter is `own` | moves into the callee, which now owns it |
| `ret x`, `ret (x, ok)` | moves out to the caller |
| `S { field: x }`, `xs[i] = x`, `s.field = x` | moves into the aggregate, which becomes the owner |
| `defer close(x)` | reserves: consumed at the block's exit (section 6) |

Everything else **borrows**: `&x`, `&const x`, `x.field` read of a copyable field,
`x` passed to a parameter that is not `own`, `x` as the subject of a `for`, `x`
compared or inspected. A borrow does not change ownership and needs no annotation
at the call site.

**Use after move** is E-SAFETY-0001, naming the move and the use. A moved variable
may be assigned again, which makes it owned again. **Partial moves** -- `let f =
s.file` where `s` stays -- are E-SAFETY-0003 in this design: move the whole `s`, or
borrow the field. Field-sensitive states are not tracked; the rule can be relaxed
later without changing what was accepted.

**Branches and loops.** State is tracked per local through the checker's walk:
`Owned`, `Moved`, `Null`, `Reserved` (section 6). At a join the state is the join:
moved on every path is moved; moved on some paths is `Maybe`, which any later use
or exit refuses (E-SAFETY-0001 naming the path that moved it). A value declared
outside a loop and consumed inside its body is E-SAFETY-0011 unless the body
assigns it again before the back edge, since the second iteration would use a moved
value. `break` and `continue` are exits of the body for the obligation rule.

**Parameters.** A parameter is a borrow unless declared `own`:

```
fn write(f: File, buf: []const u8) -> (usize, err)     // borrows: today's signatures unchanged
fn close(f: own File) -> err                           // consumes
fn into_list(l: *List[File], f: own File) -> err       // moves into the container
```

The callee of an `own` parameter owns the value and has its obligation; the caller's
copy is moved. Every existing `e.os` signature stays as it is, since none of them
transfers ownership except `close`, `wait` (a `Proc`), `thread_join` (a `Thread`),
`close_handle` and the process-group and mapping closers, which gain `own`.

**Returns.** A resource type in a return position is always owned by the caller
after the call; there is no borrowed return. The three producers that hand out
handles the process owns -- `os.stdin`, `os.stdout`, `os.stderr` -- are declared
`@borrowed`, and a value that comes from an `@borrowed` producer is affine but
carries no obligation and cannot be closed (E-SAFETY-0012 "closing a borrowed
handle"). The attribute is visible in the signature and in `index`.

**Argument evaluation.** Left to right, as today; a moved argument is moved at its
evaluation, so `f(x, x)` with two `own` parameters is E-SAFETY-0001 at the second,
and `f(x, &x)` where the first is `own` is a borrow of a moved value, refused the
same way. H05's snapshot rule for copyable by-value arguments is unaffected.

## 3. Duplication

Copying the bits of a resource is not duplicating the resource. `os.dup(f: File)
-> (File, err)` (new) asks the OS for a second identity and returns an owned value
with its own obligation; likewise `os.dup_handle`. In checked code every other way
to copy is refused at the instantiation or the site: `mem.copy[T]` and `mem.eq[T]`
over an affine `T`, `mem.bitcast` into or out of a resource type, a pointer cast to
`*File` from anything but `*File`, and any generic whose body would copy an
affine value (the instance is checked like any code and fails where the copy is).
Reflection and the format codecs see a resource type as having no fields outside
its module, so a serializer over a struct with a `File` field fails to instantiate
with the field named. All of these are E-SAFETY-0005 with the site.

## 4. Cleanup obligations

An owned value of an obligated type acquires an obligation at the point it becomes
owned: the `let`, the assignment, the `own` parameter. The obligation is discharged
by consuming the value (section 2's table) -- and a move transfers the obligation to
the new owner. At every exit of the block that holds the owner -- its end, `ret`,
a `try` that returns, `break`, `continue` -- every live obligation of a local of
that block must be discharged; one that is not is E-SAFETY-0002 "cleanup forgotten",
reported at the acquisition and naming the exit. A value moved into an aggregate
transfers the obligation to the aggregate's owner; an aggregate local carrying
obligations is discharged by moving it out or by a consuming call on it.

Module-scope `var`s of obligated types are exempt: their owner is the process, and
H01 keeps that contract (traps, `os.exit` and termination clean nothing up).
Function parameters that are `own` carry the obligation into the body; borrowed
parameters carry none.

The discharge is always visible in source: `try close(f)`, `let _ = close(f)`,
`defer let _ = close(f)`, `ret f`, `l.push(f)`. There is no destructor and no
implicit close; a value that must be dropped without closing does not exist in
checked code, and an unsafe wrapper (section 8) is where a handle is forgotten on
purpose.

## 5. States: `zero`, `undef`, failed construction

- `var f: File = zero` is the **null** resource: owned by nobody, no obligation,
  assignable. Inspecting it is allowed (`f.raw` inside the module, comparisons);
  passing it to `close` is the same E-SAFETY-0001 as using a moved value, since a
  null is not an owned value. Assigning an owned value into a variable whose state
  is `Owned` -- overwriting a live handle -- is E-SAFETY-0006.
- `undef` of a resource type is refused (E-SAFETY-0007): there is no valid
  uninitialized handle.
- A function returning `(T, err)` with `T` obligated promises: when the error is
  not `ok`, the `T` is null and carries nothing. The checker knows a resource result
  is owned only after the error has been tested: `try` does it; `let (f, e) = open()`
  followed by `if e != ok { ret e }` (or any `if e != ok { <diverges> }`) narrows `f`
  to owned after the `if`; using `f` before such a test is E-SAFETY-0008 "acquisition
  not checked". Partially built containers follow from this: a builder that fails
  mid-way returns its error and the values it took are its own obligations,
  discharged by its own cleanup, which the caller runs -- the failed-construction
  rule for H07's partial-failure table.

## 6. `defer` and reservation

`defer close(f)` (or `defer let _ = close(f)`) is a deferred consuming call. Its
arguments are captured when the `defer` is registered (spec section 6), and
registering it puts `f` into the **Reserved** state: `f` may still be borrowed, but
any later move or consuming call of `f` in the block is E-SAFETY-0009 "deferred
close would consume a moved value", naming the `defer`. At the block's exit the
deferred call runs and the obligation is discharged. Deferred calls run in reverse
registration order, an inner block's first, so partial acquisition is the existing
`defer` discipline: acquire, `defer` the release, acquire the next; a `try` between
runs what was registered. A deferred consuming call in a loop body is registered
per iteration and reserves per iteration.

A `defer { ... }` block that consumes a resource is the same: the consuming
statement inside reserves at registration.

## 7. Failure of consuming operations

A consuming operation that fails has consumed. `close` returning an error does not
hand the handle back; the value is moved whatever the error, so a retry with the
same handle is E-SAFETY-0001. Where the primary operation failed and its cleanup
also fails, the primary error is the one propagated and the cleanup's is discarded
by an explicit `let _` (H07 records that discard in the context output). `os.wait`
and `os.thread_join` consume on success and on failure alike; a wait that times out
does not consume (the `Proc` is still owned) -- the surface says which by `own`.

## 8. The unsafe boundary

Code that must touch a resource's bits -- the `e.os` implementations, an `@import`
wrapper, a serializer of handles across a process boundary -- is a function marked
`@unsafe`. Inside such a function: resource fields are visible, `mem.bitcast` and
pointer casts to resource types are allowed, an owned value may be dropped without
consumption, and copying is allowed. Nothing else changes: bounds, null and tag
checks stay (H03), and the function's signature is checked like any other, so an
`@unsafe` function that returns a `File` hands out an owned one. The build manifest
lists every `@unsafe` function of the program (H03's inventory), and `index` marks
them. A block form was considered and not taken: a function is the audit unit H01
names, and a block inside a checked function would leave the checker to reason
about states across the boundary in both directions.

## 9. Diagnostics

Registered in `diagnostics.md` under E-SAFETY, each with the sites H01 requires:

| code | violation | sites named |
|---|---|---|
| E-SAFETY-0001 | use after move, or use of a null/maybe-moved resource | the move (or the path), the use |
| E-SAFETY-0002 | cleanup forgotten | the acquisition, the exit |
| E-SAFETY-0003 | partial move out of an aggregate | the move, the aggregate's declaration |
| E-SAFETY-0004 | move while a borrow is live | the borrow, the move |
| E-SAFETY-0005 | resource copied (generic, bitcast, cast, reflection) | the copy, the type |
| E-SAFETY-0006 | owned value overwritten | the live acquisition, the assignment |
| E-SAFETY-0007 | `undef` of a resource type | the site |
| E-SAFETY-0008 | acquisition used before its error was tested | the acquisition, the use |
| E-SAFETY-0009 | deferred close of a value later consumed | the `defer`, the consumption |
| E-SAFETY-0010 | resource representation touched outside its module | the site, the type |
| E-SAFETY-0011 | resource consumed inside a loop it was declared outside | the declaration, the consumption |
| E-SAFETY-0012 | a borrowed handle closed | the producer, the close |

`E-SAFETY-9999` stays for what this table does not name.

## 10. What the checker does

One pass per function body, inside the existing body check (D326's workers, so it
costs check-body time and nothing on the warm path): a state per local of affine
type (and per `own` parameter), updated by the consuming forms and joined at every
merge of the checker's walk (if arms, switch arms, loop back edge, `try` exits);
the exits of every block audited for live obligations; borrows recorded as "a
pointer was taken in this scope" for E-SAFETY-0004's lexical rule. Instances are
checked as instances are today. Nothing is inferred across modules: an `own`
parameter is the whole contract, which is what keeps the cross-module rule
serializable in the artifact's interface (an `own` on a parameter is a signature
edge, D205).

Budget: the check-bodies phase of the D338 baseline plus 10% on every workload; the
pass touches only functions that hold an affine local, which in the compiler is a
few dozen of two thousand.

## 11. Migration

- `e.os`: `File`, `Proc`, `Thread`, `Handle`, `ProcGroup`, the mapping and poller
  handles become `resource(...)` types; `close`, `wait`, `wait_usage`, `thread_join`,
  `close_handle` and the other closers take `own`; `stdin`/`stdout`/`stderr` get
  `@borrowed`; `dup` is added. The per-host implementations become `@unsafe` where
  they read `raw`.
- `e.mem.Arena` becomes `resource` (affine, no cleanup): an arena is handed around
  by `*mem.Arena` everywhere already; `arena_from` returns an owned one; the two
  places in the compiler that copy an `Arena` struct into a worker are moves.
- `e.fs`, `e.proc`, `e.thread`, `e.net`, `e.db`, `e.async.io`: their handle types
  follow `e.os`'s, each `close`/`join` an `own` parameter; the migration is the
  suites, since every fixture that opens something must now close it or say why.
- The compiler: the driver's file handling is `open`/`defer close` already; where a
  handle is stored in a struct and closed later, the struct owns it and the close
  moves it out. Expected: a few dozen sites, each a visible `defer` or an `own`.
- Spec: sections 4 (resource types), 5 (`own`, `@borrowed`, `@unsafe`), 6 (the
  reservation rule under `defer`), 11 (the check table gains no row: these are
  static), 12 (`own` in the interface hash), 14 (the states in context output);
  `grammar.ebnf` gains `resource` and `own`; `diagnostics.md` the twelve codes;
  `module-apis.md` the changed fences; the bootstrap is not touched (M2.5 policy),
  so the self-hosted compiler's own sources use the new spellings only once the
  stage-1 compiler is the self-hosted one -- the D95 recovery path is rebuilt from
  the tag, as planned for the bootstrap's retirement.

## 12. Acceptance fixtures

Under `tests/conformance/reject/safety_*` and `tests/selfhost/fixtures/safety/`:

- reject: `let g = f` then `f` used; `defer close(f)` then `close(f)`; `close(f)`
  twice; a `File` field in a struct passed to a serializer; `open` without close on
  a `try` exit, a `break`, a `continue` and the block's end; `s.file` moved out of
  a live `s`; `&f` taken then `f` moved; `f = open()` over a live `f`; `undef` of a
  `File`; `open`'s result used before its error is tested; `close(os.stdout())`.
- accept: `ret f` and a caller that closes; `own` parameter taking and closing;
  `os.dup` then both closed; close on every exit kind; acquisition of three handles
  with the second failing and the first released by its `defer`; a close that
  fails inside a `defer let _`; a `List[File]` filled by moves and drained by a
  consuming pop.

Each fixture is a program that also runs, so the trap-free execution is the oracle
beside the diagnostic.

## 13. Alternatives considered

- **Consume by default, borrow by annotation** (`f(x)` moves, `f(&x)` borrows): the
  Rust default. Every `os.write(f, ...)` in every program would change, and the
  handle types would be passed by pointer throughout the library for no safety
  gain; the borrow-by-default rule keeps the surface and puts the one annotation
  where the semantics changes.
- **A `move` keyword at the call site** (`close(move f)`): more visible, one token
  per consuming call, and the signature already says it; tooling shows the
  transfer. Left as the question below rather than decided here.
- **Destructors**: excluded by H01.
- **Reference-counted handles**: a runtime, hidden control flow, no static story;
  excluded.
- **Generation-tagged handles** (H02's alternative for containers): orthogonal;
  may still be chosen for selected dynamic containers under H02.

## 14. Questions to lock in

1. Transfer visible at the call site (`close(move f)`) or in the signature only
   (`own` parameter; recommended: signature only, tooling shows it)?
2. The parameter spelling: `own` (recommended), `move`, or `consume`?
3. `mem.Arena` affine in this stage (recommended: yes -- it costs two moves in the
   compiler and gives H02 its owner identity) or left to H02?
4. Standard streams: `@borrowed` producers (recommended) or a separate copyable
   `Stream` type with its own `write`?
5. The unsafe unit: a function attribute (recommended) or a block?
6. Partial moves refused outright (recommended for this stage) or field-sensitive
   from the start?

## 15. Closure record (D352)

**Selected design.** The proposal's, implemented under its recommended answers to
section 14 as stated assumptions (the `/goal` run did not wait for a lock-in):
transfer in the signature alone, spelled `own`; `mem.Arena` affine (D351);
standard streams borrowed by table rather than by an `@borrowed` attribute (D349);
`@unsafe` a function attribute (D345); partial moves field-sensitive from D348 on,
since the flat per-field state cost nothing more than refusing them. Delivered in
D345 (the rules over the seeded handles, `own`, `@unsafe`), D348 (declared
`resource(cleanup)` types, containment, views, opacity), D349 (borrows given to no
one, copies refused, `os.dup`), D350 (every other `e.os` handle a resource), D351
(a kept pointer pins, `mem.Arena` affine, the view bug) and D352 (the cost brought
back under measurement, and this record).

**Alternatives** are section 13's, unchanged; the one taken up since is the pin
rule's shape (D351): a pointer pins only when the statement keeps it, since pinning
on every `&` refused the commonest borrow there is.

**Normative changes.** Spec section 5 (`own`), section 8 (commit-on-touch, D340,
alongside), section 11 "Resources: static rules" (the whole model: resource types,
`resource(cleanup)`, containment, views, borrows, copies, pins, `os.dup`, the
seeded handles and `mem.Arena`, `@unsafe`); `grammar.ebnf` revision 3 (`own`
before a parameter type, `resource_prefix` before a type body); `diagnostics.md`
E-SAFETY-0001 to 0012 and 9999; `module-apis.md`: `own` on `close`, `wait`,
`wait_usage`, `thread_join`, `thread_detach`, `dir_close`, `dlclose`,
`proc_group_close`, `watch_close`, `mapping_close`, `poller_close`, `socket_close`,
`file_unlock`, `thread.join`/`detach`, `fs.mmap.close`, `fs.watch.close`, `net.close`,
plus `os.dup`, `sha256_blocks` and `crc32c_bytes`; the artifact format is 8, since
`own` is a signature edge (D345).

**Implementation.** `src/check.e`: the `resource_*` functions at the file's end, the
`Resource` record beside each `Local`, hooks in the statement, block, binding,
assignment, return, `try`, `if`/`while`/`for`/`switch`, call and address-of paths,
gated by `resources_on` (the body sweep and instances; off in `@unsafe`) and by
`any_affine_local`, which is O(1) per statement. `src/parse.e`: `own`,
`resource(name)`. `src/em.e`: the `own` byte in the canonical signature.
`src/main.e`: the E-SAFETY messages. Library: the eleven `e.os` handle types and
their closers in both host variants, `e.thread`, `e.fs.mmap`, `e.fs.watch`,
`e.proc`. Fixtures: `tests/conformance/reject/safety_*` (seventeen) and
`accept/safety.e`, `accept/safety_resource/`, `reject/safety_opaque/`;
`tests/selfhost/fixtures/link/os_dup`; the suites register every one.

**Compatibility.** A source that closes a borrowed parameter, opens without
closing on some exit, or reads a declared resource's fields outside its module no
longer compiles; the migration inside this repository was the D345 leaks (four in
the compiler, one in `e.proc`, thirteen fixtures), D349's two check fixtures, D350's
two handle-bit comparisons and D351's three writer scopes. Artifacts of format 7
are rebuilt. The bootstrap is untouched: `own` and `resource` appear in the library
and the fixtures only, and `src/check.e` sits 210 tokens under its token limit.

**Measurements** (`-j 1`, five runs, p50, Windows, this machine; `sc500k` holds no
resource at all, the compiler's own source holds every kind):

| workload | mode | check bodies, D344 (before H01) | D352 | delta | budget |
|---|---|---|---|---|---|
| sc500k | debug | 489 ms | 544 ms | +11% | +10% |
| sc500k | release | 1166 ms | 1235 ms | +6% | +10% |
| compiler | debug | 88 ms | 102 ms | +16% | +10% |
| compiler | release | 102 ms | 118 ms | +16% | +10% |

The compiler's source grew 3.6% over the same span (D345-D352 themselves), which
is part of its row. Under `perf` on `sc500k`, the resource functions together are
0.2% of the build, about 2% of the phase; the rest of the delta is the checker's
changed shape -- the call path split for `resource_call`, the per-statement
bookkeeping, the larger `Checker` -- which D352's gates, memo and lean `Local`
brought down from +16%/+7% but not under the line. **The budget is not met on the
debug rows**; this is recorded as the breach the baseline asks for rather than
relabelled. Against the D338 baseline itself, single-worker check bodies are +12%
(debug) and +7% (release) on `sc500k`; the eight-worker figures in
`benchmarks/baseline/h01-windows-d351.json` (D351, eight workers, three runs) are worse (+36%/+29%) for a reason that predates H01:
D339/D340's commit-on-touch pays a page fault per megabyte in every worker's fresh
reservation and makes every touched page resident, which is also why peak RSS
against the baseline is +73% on the compiler workload (D344 alone is +67%). That is
D340's breach, not this one's, and it is listed under limitations for D340's
follow-up. Cold wall, warm wall and image size are within their budgets
(warm p50 96 ms against 82 ms is +17% at eight workers, +0% single-worker).

**Remaining limitations** (each an obligation, none closed by this record):
reflection and the format codecs are not stopped at a resource's fields
(E-SAFETY-0005's last case); D616-D617 track comptime-indexed slots of fixed arrays, but
dynamic indices and slices of resources are not tracked as wholes; the generic containers take their element by `own` (D353), but none can hold an
obligated resource yet: growth relocates elements and an insert can fail after
taking the value, which the instance refuses -- the container with a failure story
is H02's; the seeded handles' `raw` stays readable until the fixed
surface gains `file_handle`; the `@unsafe` inventory in the manifest and `index`
(section 8, H27) is not written; the pin rule is lexical, and infers nothing about what a callee keeps
(H02); the debug-mode check-bodies budget above.

**D610 follow-up.** A consuming call through a pointer alias (`os.close(*p)` where
`p` was bound from `&f`) resolves to the resource it points at before applying the
ordinary move rule. The kept pointer therefore pins `f` and the call is
E-SAFETY-0004 rather than an untracked close.

**D611 follow-up.** A concrete generic aggregate clears the unresolved template's
affine memo and classifies its substituted fields. `Box[File]` therefore moves and
audits its `File` field like an equivalent nongeneric struct.

**D612 follow-up.** A tagged union whose possible payloads include an affine type
is affine as a whole. Its live arm is not statically tracked, so only whole-value
moves participate; no partial payload move is claimed.

**D613 follow-up.** A declared resource's cleanup may take context parameters when
its final parameter is `own T`. Calls consume that last argument through the
ordinary signature rule, enabling the frozen `gpu.release(q, b)` contract without
a GPU-specific ownership path.

**D616 follow-up.** A fixed array inherits the affine/obligated classification of
its element. Literal-indexed slots carry independent states through stores, moves,
branches, loops and exit audits; the existing dynamic worker-array idiom remains a
view until the set-of-elements rule is specified.

**D617 follow-up.** The slot identity accepts any comptime integer expression, not
only a literal. Constant names and arithmetic that evaluate to the same index reach
the same state, and a failed attempt to fold a dynamic expression leaves the normal
checker diagnostic state untouched.

**D618 follow-up.** A tracked array slot retains its own acquisition or last-move
token. Diagnostics render the semantic subject as `name[index]` and use that slot's
token for the related span, rather than blaming the array generally or whichever
slot happened to be assigned last.

**D619 follow-up.** A local full-slice view of a tracked fixed array retains the
array owner and zero offset; direct slice aliases retain that same owner. A comptime
index through either spelling reads or consumes the array's one slot state, so a
slice cannot manufacture a second resource identity. Offset ranges and dynamic
indices remain outside this increment.

**D620 follow-up.** A slice range with a comptime lower bound retains that offset
into the fixed array's slot table, including through direct slice aliases. Thus
`files[1..][0]` and `files[1]` name one ownership identity. Dynamic lower bounds and
slices without a tracked fixed-array owner remain outside the rule.
