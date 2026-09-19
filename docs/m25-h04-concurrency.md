# M2.5 stage B: H04 -- scoped concurrency and shared-state contracts

The design H04 of [`post-m2-llm-hardening.md`](post-m2-llm-hardening.md) section 7
asks for, written against the language after H01 and H02: `os.Thread` is a
resource owed a join or a detach at every exit (D345), a thread is started over a
pointer to its context (`os.thread_create[T](entry, &ctx, stack)`,
`thread.spawn`), and `e.atomic` and `e.sync` are the sharing primitives. Sections
1-6 are the proposal; section 7 is what each D row delivered.

The shape: **a thread borrows what it is started over, and the parent's frame is
the scope of that borrow**. The join is the obligation H01 already tracks; H04 adds
what the borrow forbids while the thread runs and what a thread may not be given.

## 1. The join obligation

A `Thread` is affine and owed: joined or detached on every exit of the block that
owns it (D345, E-SAFETY-0002), including the `try` exits -- so an early `try` with
a live worker is refused unless the worker is joined before it, which is H04's
"joining on error paths must precede reset/cleanup". A thread stored into an array
and joined by element is the compiler's own shape and stays legal; the array is not
tracked, and its elements' joins are the program's discipline.

## 2. Stack escape (D357)

A thread started over `&x` where `x` is a local of the frame -- not a slice or a
pointer, whose storage is elsewhere -- reads the frame while it runs. It can be
joined in the frame, bound to another name in it, or stored into storage declared
after `x` (which dies no later); detached, handed to an `own` parameter, returned
or stored anywhere else it would outlive what it reads (E-SAFETY-0015). A
detached thread must be given arena storage, which is what the fixtures do. A
callback that borrows the frame indirectly -- a function value stored in the
context that reads a frame local through a pointer taken earlier -- is not seen;
section 5 lists it.

## 3. Sharing while the thread runs (D365)

What a thread was given is lent to it until the join: from the start to the join
of that thread local, the parent neither reads nor writes `x` (E-SAFETY-0016) --
a value read (`x.field`, `x[i]`, `x`), a store through the place, a move. What it
may do is take `&x` or `&x.field` again: that is how an atomic reaches a counter
(`atomic.load(&x.hits, .SeqCst)`), how a second thread is given the same context,
and how a lock is taken -- the sanctioned sharing H04 names, each through an
address, none through a plain read. The lending ends at the join of the thread
local; it also ends when the thread local is moved anywhere else (into an array
the loop joins by element), since a local's state cannot follow an element, and
that is a limit, not a rule. A detached thread's lending never ends: what a
detached thread was given is read by no one, which is right.

The rule is per statement: a statement that joins and reads in one expression is
refused, since the uses are checked before the moves; the join is written as its
own statement, which the one fixture that did otherwise now does.

A thread context passed through a local pointer alias of `&x` identifies and lends
the same `x` (D674). The stack-escape and pre-join access rules therefore do not
depend on whether the start call spells the context directly or through that alias.
An address into a local slice whose backing local is known, `&s[i]`, likewise lends
the backing storage rather than only the slice descriptor (D679). An address reached
through a tracked aggregate pointer field, `&ctx.target.hits`, lends the pointed-to
local rather than the aggregate that carries the pointer (D686). The field-specific
identity also holds for the second and later tracked pointer fields in an aggregate
(D695, D700), including pointers reached through recursively nested aggregate paths
(D705). A runtime-indexed pointer element may name any tracked element owner, so
all candidates are lent until the join (D714).

## 4. Locks, guards and atomics

The first half (D379): a lock held as a value. `sync.guard(&m)` takes the mutex
and returns a `sync.Guard`, a `resource(release)` struct, so H01 makes the
release an obligation of every exit of the block that holds it -- an early `ret`
or `try` with the lock held is E-SAFETY-0002, a second `release` E-SAFETY-0001,
a guard moved into `defer sync.release(g)` released at the block's end --
without a rule of its own: the guard is a handle like a file. `try_guard`
returns `(Guard, err)`, `Invalid` when the lock was not taken, and on the err
path nothing is owed -- the convention of every acquiring call. The guard refers to the lock's
identity (`g.m`), not to the data it protects.

`sync.ReadGuard` and `sync.WriteGuard` (D433) are the same shape over an
`RwLock`, one resource per side since the releases differ: `read_guard` /
`try_read_guard` / `read_release`, `write_guard` / `try_write_guard` /
`write_release`; the fixtures `sync_rwguard` and `reject/safety_rwguard_leak`.

Not designed yet, the second half: the data as a view of the guard (H02's view
rule over the guard's lifetime, so a borrow of the protected data cannot survive
the release), reentrancy, condition-variable wait and reacquire through a guard
(`condition_wait` takes the mutex, not the guard, and stays that way until the
view rule exists), cancellation.

## 5. Outside the rule

- A pointer to the frame taken before the thread starts and reached through the
  context indirectly (a callback environment, a struct of pointers).
- Storage reached through a slice whose backing local is unknown. A local slice
  bound from an array place is followed when used as a thread context (D679), and
  a pointer local bound from `&x` is followed
  (D393), as is a slice bound from a place of `x` (D395) and a struct local holding `&x` in a field, through that field (D413): a read or a store
  through it while `x` is lent is refused, and `&p.f` is an address like `&x.f`;
  a pointer that came from anywhere else is not.
- Globals: a module-scope `var` read by both is not tracked; it is the program's
  to protect with an atomic or a lock.
- Partial spawn failure: a loop that starts N threads and fails at the K-th owes
  the K-1 joins, which H01's exit audit enforces for locals and not for arrays.
  `thread.Group` (D434) is the library's answer: `spawn_all` starts one thread
  per context, joins what it started when a start fails, and the group is one
  resource owed to `join_all`, so the array's joins are audited as a local's are.
- Schedule perturbation as evidence (H04): `--perturb` (D331) reorders the
  compiler's own workers and the suites compare the images; no fixture yet
  perturbs a program's threads.

## 6. Diagnostics and fixtures

| code | violation | sites |
|---|---|---|
| E-SAFETY-0015 | a thread over this frame's storage detached, handed on, returned or stored past it | the start, the site |
| E-SAFETY-0016 | storage lent to a running thread read or written before its join | the start, the use |

Fixtures: `reject/safety_detached_frame` (a detached thread over a stack counter),
`reject/safety_thread_shared` (the counter read before the join); the link fixtures
`thread_spawn`, `os_thread`, `sync_threads`, `channel_threads`, `atomic_threads`,
`concurrent_queue_map` are the valid shapes -- arena storage for a detached thread,
atomics through addresses while workers run, joins by element.

## 7. Implementation record

**D357** delivered section 2; **D365** section 3 and this document; **D674**
extended section 3 to thread starts through local pointer aliases; **D679** follows
thread contexts through local slices to known backing storage; **D686** gives an
address through a tracked aggregate pointer field that same underlying identity;
**D695** proves the second tracked pointer field lends its own owner rather than the
first field's owner or the carrier;
**D700** proves the same identity for a sparse third-or-later pointer field;
**D705** proves a later pointer on a recursively nested path lends its own owner;
**D710** proves a later comptime-indexed fixed-array pointer element lends its own
owner rather than an earlier element or the carrier;
**D714** lends every possible owner when that fixed-array element is selected by a
runtime index;
**D379**
section 4's first half (`sync.Guard`, the fixtures `sync_guard` and
`reject/safety_guard_leak`). The compiler's own crews pass as written under
all three. Not delivered: section 4's second half, section 5's cases, the
perturbation fixture.
