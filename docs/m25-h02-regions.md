# M2.5 stage B: H02 -- regions, borrowing and stable container views

The design H02 of [`post-m2-llm-hardening.md`](post-m2-llm-hardening.md) section 5
asks for, written against the language as it stands after H01
([`m25-h01-ownership.md`](m25-h01-ownership.md)): arenas with `mark`/`reset`,
slices and pointers as the only views, containers over a `*mem.Arena`, and a
checker that already keeps a state per local. Sections 1-7 are the proposal;
section 8 says what each D row of the implementation delivered and what it did not.

The shape is a **bounded lexical subset**, as H02 permits: what a pointer or slice
borrows from is known when it is bound, inside one function, from the signature of
the call that made it; a region ends and a container mutates at a visible
statement; a use after either is refused. What escapes -- into a struct, a global,
a callback, an imported function, another thread -- is outside the guarantee and
said to be, and the raw-pointer cases are listed rather than inferred.

## 1. What can dangle

Two things make a slice or pointer invalid in checked code today, and neither is
a trap:

- **A region reset.** `let m = mem.mark(a)`, allocations from `a`, `mem.reset(a, m)`:
  everything allocated from `a` after the mark is gone, and a slice into it reads
  the debug fill or, in release, whatever came next. The compiler's own sources do
  this in a hundred places for a C string or a scratch buffer, and the discipline
  is by convention.
- **A container's growth.** `let items = list.slice(&l)`, `list.push(&l, x)`: the
  push may reallocate the backing, and `items` now points at the old one -- still
  addressable, so no fill and no trap finds it.

Section 11's debug fills catch some of the first and none of the second; H02 asks
for a static rule that catches both before invalid memory is read.

## 2. Regions

A **mark** is a local bound from `mem.mark(a)`. A **region value** is a local
bound, after that mark and in the same function, from a call that took the same
arena (`a` written as the same name) as an argument and returned a type that can
hold a pointer -- a slice, a pointer, a function, a struct or array holding one --
including the result of `mem.alloc[T](a, n)`. A region value belongs to the
innermost live mark of that arena at its binding. A binding from a region value
(`let t = s[1..]`, `let p = &s[0]`, `let u = s`) is a region value of the same mark.

`mem.reset(a, m)` ends the region: every region value of `m` (and of any mark taken
after it on the same arena) is **dangling** from that statement on. A dangling
value cannot be read, passed, stored or returned (`E-SAFETY-0013` "used after its
region was reset", naming the reset); it can be rebound. A `defer mem.reset(a, m)`
ends the region at the block's exit, not where the defer is registered, so uses in
the rest of the block remain valid. Returning one of those region values is refused
with E-SAFETY-0018 because the reset runs before the caller receives it (D675).

The arms of an `if` join as H01's states do: a value reset on one path and not the
other is dangling-maybe, which no use accepts.

A pointer local bound from `&x` -- `let first = &cells[0]` -- a slice local
bound from a place of `x` -- `let head = counts.hits[0..2]` (D395) -- or a struct
local given `&x` in a field, `Context { target: &x, .. }` or `ctx.target = &x`,
through that field alone (D413), is `x` by another name (D393, D394), from the
binding or the assignment that made it so until the next (D416): once `x` dangles, `*first`, `first.field` and `first[i]`, read
or stored to, are refused as `x`'s own use is, naming `x`; `first.len` is not,
for the reason `x.len` is not. A pointer from anywhere else is not followed.
Pointer-bearing fields in one aggregate retain distinct lexical targets at every
nested aggregate path (D691, D696, D701), and a fixed array literal retains them
per comptime element (D706), so a later path follows its own owner rather than the
first pointer found.

## 3. Views of containers

A **view** is a local bound from a call that received `&c` -- the address of a
local `c` -- and returned a type that can hold a pointer: `list.slice(&l)`,
`map.get_ptr(&m, k)`, `list.iter(&l)`, `str.done(&b)`. It borrows `c`. A binding
from a view is a view of the same container.

A **mutation** of `c` is a later call that receives `&c` through a parameter typed
`*T` (not `*const T`) and returns nothing that can hold a pointer: `list.push(&l,
x)`, `list.clear(&l)`, `map.remove(&m, k)`, `str.push(&b, ...)`. From that statement
on every view of `c` is dangling (`E-SAFETY-0014` "view used after its container
was mutated", naming the mutation). A call through `&const c` mutates nothing; a
call that returns a view of `c` is an accessor and invalidates nothing, since a
view-returning function that also mutates is not a shape the standard containers
have (section 5 lists it as outside).

A view that is stored into a struct or returned is outside the subset, as in
section 2; a view used as a `for` subject is a use.

## 4. What escapes, and is not claimed

Stated so that no one reads the rules above as more than they are:

- A region value or a view **returned** from the function, except across a deferred
  reset of its region (D675): the caller otherwise sees an
  ordinary slice. The signature does not say what it borrows; H02's borrow
  summaries across modules are later delivery (section 7).
- **Stored** into a global or a dynamic container: the store is a use, and the
  copy is not tracked. Local named aggregates and comptime-indexed fixed arrays
  retain the lexical pointer paths explicitly covered in section 2.
- Passed to a **callback** or an **imported** function, or handed to another
  **thread**: the call is a use; what the callee keeps is not known.
- A pointer made by `mem.cast`, `mem.address_of`, arithmetic on a `usize`, or read
  out of a struct (`s.items`): not a region value or a view, since nothing says what
  it borrows. These are the raw-pointer cases H02 asks to record outside the
  guarantee, and an `@unsafe` function is where they belong when they matter.
- A container mutation through a pointer alias (`let p = &l; list.push(p, x)`) is
  followed and invalidates `l`'s views (D671). Copying that pointer local preserves
  the same target, so local pointer-copy chains are followed too (D672). A mutable
  call addressed through a tracked aggregate pointer field likewise mutates the
  pointed-to local rather than the aggregate carrying that pointer (D687).
- Non-lexical liveness: a view whose last use is before the mutation is still
  refused if it is used after. H02 asks to measure before inferring liveness; the
  measurement is in section 8.

## 5. Signatures and summaries

Nothing is added to a signature in this stage: what a result borrows is read from
the parameter types the callee already has (`*mem.Arena`, `*T`, `*const T`) and
from the result type, in the caller, at the binding. This is the reading a caller
can do without the callee's body and without a serialized summary, which is what
keeps it warm-path free (H14, D205: a signature edge). The later delivery is a
summary per function in the artifact -- "the result borrows parameter 1", "no
argument escapes" -- inferred from the body and checked against the callers,
which is the cross-module contract H02 names; it needs the escape analysis of
section 4's cases, and is not attempted here.

## 6. Diagnostics and fixtures

| code | violation | sites named |
|---|---|---|
| E-SAFETY-0013 | a region value used after its region was reset | the reset, the use |
| E-SAFETY-0014 | a view used after its container was mutated | the mutation, the use |
| E-SAFETY-0018 | a region value returned across its deferred reset | the defer, the return |

Fixtures under `tests/conformance`: a slice allocated after a mark and read after
the reset (reject); a view of a list read after a push (reject); a value reset on
one arm and read after the join (reject); the valid counterparts -- a scratch
region reset after its last use, a view retaken after the push, a `defer`red
reset registered before or after allocation, a view through `&const` -- in the
accept fixtures. A return across that deferred reset is rejected. The compiler's own
`mark`/`reset` sites are the measurement of false positives (section 8).

## 7. Delivery

**M2.5:** sections 2, 3, 4 and 6 as written; the fixtures; the false-positive
measurement over the compiler and the library; the closure record.

**Later:** borrow summaries in the artifact and their check at the callers;
escape through structs, callbacks and threads; alias tracking through pointer
locals; non-lexical liveness if the measurement asks for it; build-then-freeze
containers -- a `freeze` that consumes the builder and returns the slice, after
which the builder cannot grow (H02's container redesign) -- and generation-tagged
handles for the dynamic containers that want them, with the owner identity,
generation-wrap policy and per-access cost H02 lists.

## 8. Implementation record

**D354** delivered sections 2, 3 and 6 in `src/check.e`, on the state machinery
H01 left: a mark is an owned view local that remembers its arena as written; a
region value or a view is an owned view local tagged with its mark or its
container; `mem.reset` and a mutating call move the tagged locals to a dangling
state that names the reset or the mutation, and H01's use, join and loop rules do
the rest. Two readings narrowed section 3 on the way: a call that takes an arena
hands back an allocation and not a view, whatever else it was given (the driver's
`run_program(a, &report, ...)` is that shape); and a view is a slice, a pointer or a
string, not a struct that holds one, since `json.parse_value(&p) -> Value` is a
parse, not a view of the parser. Also from the sweep: the length of a dangling
slice is not a use, the way the arena-scope test reads it; a view invalidated in
a loop body is not a resource consumed in it; and `debug_fills` is `@unsafe`,
being the fixture that reads a reset region on purpose.

False positives in the compiler, the library and every fixture, after those
readings: none. Cost on `sc500k` single-worker, debug: 544 ms to 564 ms (+4%; H01
and H02 together +15% over D344). Not delivered, as section 7 lists: summaries,
escapes, aliases through pointer locals, non-lexical liveness, `freeze`, tagged
handles; and `list.iter(&l)`-shaped struct views, which the narrowed reading
leaves untracked.

**D671-D672** close the local pointer-alias mutation hole: a mutable pointer argument
bound from `&c` resolves to `c` before the view invalidation pass runs, and copies of
that pointer retain the same target. The same E-SAFETY-0014 and mutation provenance
now cover direct aliases and local pointer-copy chains; focused fixtures pin both
forms on both hosts.

**D673** gives arena arguments the same local storage identity across their direct,
addressed, and pointer-alias spellings. A mark opened through `p = &arena` therefore
owns allocations made through `&arena`, and reset through either spelling ends the
same region with the existing E-SAFETY-0013 evidence.

**D675** models a deferred reset at scope exit: registering it does not dangle
already-bound region values, but returning such a value is E-SAFETY-0018 because
the reset executes before delivery to the caller. Focused accept and reject fixtures
pin both halves of that timing rule.

**D676** extends canonical storage identity to copies of pointer parameters. The
parameter is the lexical identity when its external pointee has no local of its own,
so marks and allocations made through the original and its copies share one region.

**D677** preserves a mark's original checkpoint across local copies. Reset through
the copy therefore invalidates allocations made after the original mark, including
those bound before the copy itself; the copy is not modeled as a nested mark.

**D678** follows local pointer aliases on the accessor side of the view rule as well
as the mutation side. A slice, pointer or string returned by a call through `p = &c`
is tagged as a view of `c`, so a later mutation reports E-SAFETY-0014.

**D680** extends deferred-reset escape checking from a region local to a slice derived
from it at the return site. Returning `scratch[a..b]` is E-SAFETY-0018 for the same
reason as returning `scratch`: the deferred reset runs before the caller sees either.

**D681** applies the same boundary to a pointer formed from region storage at the
return site. Returning `&scratch[i]` across the deferred reset is E-SAFETY-0018 with
the defer registration as related evidence.

**D682** follows that boundary through the existing lexical alias facts. A pointer
copied from an aggregate field that holds `&scratch[i]` still names `scratch`, so it
cannot be returned across the same deferred reset.

**D683** applies the boundary to the aggregate carrier as well. Returning the local
aggregate that holds `&scratch[i]` is E-SAFETY-0018; extracting its pointer first is
not required for the checker to retain the region identity.

**D684** preserves that identity across a direct lexical aggregate copy. If `copy`
is bound from a local aggregate that carries `&scratch[i]`, returning `copy` across
the deferred reset is E-SAFETY-0018 as well.

**D685** gives a direct local assignment the same semantics. Assigning the carrier
into an existing local copies its lexical region identity, so returning the assigned
local across the deferred reset is E-SAFETY-0018.

**D687** resolves an addressed mutable call through a tracked aggregate pointer
field before falling back to the syntactic address base. A mutation such as
`mutate(&ctx.target.field)` therefore invalidates views of the local named by
`target`, with the existing E-SAFETY-0014 evidence.

**D688** applies the same identity on the accessor side. A view returned by
`view(&ctx.target.field)` belongs to the local named by `target`, so a later direct
mutation of that local invalidates the view with E-SAFETY-0014.

**D689** finds the first tracked address recursively inside nested aggregate
literals. The outer carrier retains the region identity, so returning it across a
deferred reset is E-SAFETY-0018 without flattening or copying the nested value.

**D690** preserves that identity when the pointer-bearing aggregate literal is
assigned into a field of an existing outer aggregate. The outer local then carries
the enclosed region pointer and cannot escape its deferred reset.

**D691** retains a second independent pointer field in an aggregate literal. Alias
resolution selects the target by the field used, so a post-reset use through the
second field is E-SAFETY-0013 even when the first field points at live storage.

**D692** extends the deferred-return boundary to the whole two-pointer carrier. If
the first field names live storage but the second belongs to the deferred-reset
region, returning the aggregate is E-SAFETY-0018 against that second owner.

**D693** preserves both recorded pointer-field targets when a two-pointer aggregate
is copied to another local. Returning the copy across the deferred reset therefore
remains E-SAFETY-0018 against the owner named by its second field.

**D694** keeps independently assigned pointer fields in separate alias slots. A
later assignment to one sibling cannot erase the other sibling's region identity,
so returning the carrier still reports E-SAFETY-0018 for that owner.

**D696** removes the two-field ceiling for top-level aggregate aliases. The first
two targets remain inline in the existing resource record; only a third or later
target enters a sparse checker-side table. A post-reset use through that later field
is therefore E-SAFETY-0013 without increasing every local's resource footprint.
At D696 nested aggregates still retained only the first address below each top-level
field; D701 subsequently removes that path ambiguity.

**D697** includes those sparse aliases at the deferred-return boundary. Returning a
whole aggregate whose third or later field points into the region reset before
delivery is E-SAFETY-0018 against that field's owner, even when the first two fields
point at live storage.

**D698** copies sparse aliases with the named aggregate that carries them. A direct
lexical copy therefore preserves a third or later field's region identity, and
returning the copy across the deferred reset remains E-SAFETY-0018 against that
field's owner.

**D699** routes separate pointer-field assignments through the same alias insertion
used by aggregate literals. Assigning a third or later field therefore inserts or
updates its sparse identity without erasing either inline sibling, so a deferred
return remains E-SAFETY-0018 against its region owner.

**D701** records a complete field-segment path for every pointer found recursively
inside an aggregate literal. Alias resolution selects the longest path prefix used
by the expression, so `outer.middle.inner.scratch` follows `scratch` rather than the
first pointer below `middle`; a post-reset use is E-SAFETY-0013. Nested paths live
only in the sparse side table, leaving the per-local `Resource` record unchanged.

**D702** lets a sparse nested path establish a carrier escape without requiring any
top-level inline alias. Returning an aggregate whose later nested pointer belongs to
the deferred-reset region is therefore E-SAFETY-0018 against that actual owner.

**D703** copies sparse nested paths even when the source aggregate has no inline
alias. Returning the lexical copy across the deferred reset therefore remains
E-SAFETY-0018 against the later nested pointer's region owner.

**D704** uses the same complete path representation for separate nested field
assignments. Direct pointer stores upsert their exact carrier path, while an
aggregate literal assigned at any nesting depth recursively contributes all paths
below it. A later nested region pointer therefore remains E-SAFETY-0018 at return.

**D706** extends those paths with comptime fixed-array element segments. A pointer
in a later array-literal element retains its own local owner, so a use through that
element after the owner's region reset is E-SAFETY-0013 rather than resolving to an
earlier live element. Numeric segments reuse the sparse aggregate-path table and do
not grow every local's `Resource` record.
