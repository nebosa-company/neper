# Standard-library composition and harness hardening

Status: adopted next-contract design, 2026-09-06 (D84). No declaration in this
document is evidence of implementation. Exact declarations live in
[`module-apis.md`](module-apis.md), delivery/dependency identity in
[`modules.json`](modules.json), and general rules in [`modules.md`](modules.md).
This document owns the composition, migration and acceptance obligations below.

## Delivery boundary

Complete M2 against its preserved contract. During M2.5 H01/H02/H07/H11/H17/H18,
migrate delivered CPU surfaces to this contract, implement the common `e.cancel`
primitive and basic `e.text.utf8`, and validate the whole next-contract catalogue.
These two core additions retain `schedule:"later", milestone:null` because M2.5
is a cross-cutting gate, not an added Mn module milestone; this document explicitly
schedules their CPU delivery within that gate. Do not retroactively claim them in
the M2 baseline. Core release/admission checks must include these cross-cutting
obligations as well as the manifest's numbered milestones.

Future networking, cryptographic and test-support libraries remain independently
delivered extended modules. Their exact API designs and conformance plans freeze
now; implementation and runtime proof occur at their own delivery. The image/codecs
cohort has one coordinated release gate below, independent of M3 and the UI gate.
No optional module is marked implemented by promoting its intended stability tier.

## SL01 — names that obey the language

Keep ordinary parameters and the existing no-shadow rule. Do not introduce
`@parameters`, implicit function fallback, or a second parameter namespace.
Parameters and locals cannot shadow module declarations, import qualifiers,
enclosing bindings or reserved names. Disjoint sibling scopes may reuse names.

The catalogue renames collisions with descriptive roles: `repeat_count`,
`bit_count`, `cancel_token`, `source_reader`, `sink_writer`, `target_path` and
similar names. Include import-qualifier conflicts, not just function-name conflicts.
Parameter renames do not change positional call syntax, but update signatures,
examples, generated metadata and future source together. An added module helper
can invalidate an existing local name even if no call changed: H17's insertion and
move plans must expose that impact, not only deletions or protocol lookup changes.

Static validation checks the exact fragments and graph now. During M2.5, feed
extracted declarations plus their imports into the real parser/resolver in a
declaration-validation mode; omission of function bodies is not permission to
accept illegal parameter names. Dependent compiler-intrinsic metavariables retain
their documented exception. A regex check is not semantic/compiler verification.

Required fixture families: top-level function before/after a colliding local;
parameter/import/loop/switch-capture collisions; reserved `target`; separate type
and qualifier positions; sibling reuse; insertion causing a collision; source-order
permutations. Negative diagnostics identify the binding and conflicting declaration;
suggested renames preserve reference identity and unrelated text.

## SL02 — composable I/O and resource ownership

`e.io.Writer` has an explicit optional flush callback. `writer` makes an unbuffered
adapter; `writer_with_flush` supplies buffered behavior. `buffered_source` and
`buffered_sink` bridge opaque buffers back to ordinary I/O. Adapters borrow wrapper,
context and underlying storage. Flush neither closes the underlying sink nor means
filesystem durability or compression/protocol finalization. No runtime registry or
guessing the dynamic type of `ctx` is allowed.

Preserve exact partial progress on write failure, including buffered suffixes.
Specify EOF, zero-length requests, `(0, ok)` no-progress protection and positive
bytes with an error. Never retry already accepted bytes after failed flush. Closing
or resetting a borrowed wrapper/source requires completion of outstanding uses.

Acceptance: file -> buffer -> decompressor -> JSON stream using only public APIs;
nested buffered sinks; short writes; data plus error; flush failure after a prefix;
empty input; abandoned traversal; no double-close and no borrowed view after reset.
Run the delivered portion in M2.5; later codec branches activate on codec delivery.

## SL03 — common control and honest cancellation

`e.cancel` is a small core primitive independent of worker pools. Token is shared,
non-copyable state; Control borrows it and carries an explicit optional monotonic
deadline. It has no arbitrary values, ambient context, automatic timer registry or
hidden allocator. `e.task.Cancel` aliases the common Token; task-specific token
constructors are replaced with the shared module, not kept as parallel semantics.

Operation completion, not a cancellation request, ends borrowed-buffer lifetimes.
Define the commit point deciding whether success or cancellation wins; preserve
partial read/write effects and stable terminal states. `e.async.io.progress` exposes
completed bytes, and its cancellation result is request acceptance, not a join.
No rule can undo a packet transmitted before cancellation. Unknown external effects
are unknown, not zero. A caller must not blindly replay non-idempotent work.

Controlled process, DNS, connect, byte I/O and TLS/HTTP paths share this contract.
An implementation unable to meet a promised deadline/cancellation bound rejects
that mode or retains resources until actual completion; it cannot acknowledge
cancellation while an uninterruptible callback still uses caller memory.

Acceptance: already-cancelled input, expired/zero/no deadline, completion race,
partial transfer then cancellation, blocking callback, early cleanup, shared token
and shutdown. H04's join and ownership rules remain authoritative.

## SL04 — lossless JSON and transactional data edits

JSON Number stores a validated lexical representation, not only an `f64`. Generic
tree/event paths preserve all digits. Conversion to integer is exact and checked;
conversion to floating point is explicit. Input, reader-event and copied patch
result lifetimes are distinct. Typed encoding never rounds a `u64` through a float.
Generic writes preserve object order and number spelling, not original whitespace.

JSON Pointer and Patch follow [RFC 6901](https://www.rfc-editor.org/rfc/rfc6901)
and [RFC 6902](https://www.rfc-editor.org/rfc/rfc6902). Patch constructs a separate
owned result or fails without changing its input; it does not provide filesystem
transactionality. Duplicate-key objects are rejected for edits. Exact numeric test
equality must work without lossy conversion. Bound operation count, tree depth,
input sizes and allocation; malicious exponent/digit lengths cannot cause unbounded
integer conversion or comparison. Arena failure is explicit.

Acceptance: 2^53 +/- 1, signed/unsigned 64-bit boundaries, negative zero, huge
exponents, escaped pointer components, duplicate keys, append/remove/move, failed
test in the middle of a patch, input/output aliasing, depth limits and OOM rollback.
H09/H15 still protect concurrent source edits and stale preconditions.

## SL05 — bounded subprocess supervision

`e.proc.run` accepts explicit control, capture limits, shutdown grace and containment
policy. It drains both output pipes concurrently, retains bounded prefixes, reports
observed byte totals/truncation, and reaps the child. Nonzero exit, timeout,
cancellation and output overflow are distinguishable from supervisor failure.
Structured results remain valid on error where specified; zero/unknown exit status
is not success. Negative grace durations fail before spawning.

Containment must be installed before child code runs. Windows job objects are one
implementation; POSIX process groups alone cannot guarantee containment of arbitrary
escaping descendants. If the requested strict guarantee is unsupported, return
`os.Unsupported` before spawning; do not downgrade it silently. Child-only mode is
explicit and makes no descendant-cleanup guarantee. Containment is not a general
security sandbox. The driver/linking layer remains `e.os`.

Acceptance: flooded simultaneous stdout/stderr, stuck stdin, child-created descendants,
inherited pipe writers, nonzero exit, spawn failure, timeout during cleanup, missing
containment capability and no surviving contained descendants. Limits include a
bounded post-termination drain; closing remaining capture pipes records truncation.
Test the exact platform contract, including unsupported outcomes.

D578 delivers `RunOptions` and `run` over the two hosts' process-group/job support:
independent bounded prefixes, observed byte counts, explicit exit/cancel/timeout/limit
outcomes, pre-start control checks, live deadline termination and negative-grace
rejection are exercised by `link/proc_output`. The module remains partial: a child-only
descendant retaining an inherited pipe still needs the bounded post-termination drain.

D580 closes that drain gap with `os.pipe_read`, a zero-time readiness probe on both hosts.
`run` reaps on a waiter while it drains ready bytes, then closes any capture writer still
held after a fixed bounded drain and records truncation. The real-child fixture now spawns
a descendant that retains both writers: child-only mode returns bounded and truncated,
while process-group/job mode ends the descendant and reaches ordinary EOF. The remaining
SL05 acceptance gap is a descendant that ignores gentle group termination through the
complete grace interval.

D581 closes that final gap with a synchronized real descendant. Its Linux variant installs
`SIG_IGN` for `SIGTERM` before the direct child exits; the fixture proves the contained run
does not return before its requested grace and then forces the group, closing the retained
capture writer without truncation. The Windows variant pins the same completed contained
result under job objects, where cooperative and forced termination are the same host action.
SL05's adopted subprocess contract is now covered on both target-specific paths.

## SL06 — handle-anchored filesystem operations

`e.fs.Root` owns an `os.Dir`; relative opens/removes/replaces operate through that
handle. Reject absolute paths, embedded NULs and parent traversal. NoSymlinks rejects
all traversed symlinks/reparse points. Beneath accepts only resolution the platform
can enforce inside the root, otherwise Unsupported. A path-string prefix comparison
or canonicalize-then-open is not a confinement proof.

Define final-link removal, hard-link limitations, root movement, replacement of
directory entries, case sensitivity and Windows reparse behavior. Directory-relative
authority limits path traversal, not other hard links to the same data. Atomic
replacement and durable persistence are different guarantees; a durability failure
may occur after replacement. Locks are cooperative unless explicitly stronger.
`walk_close` handles early traversal abandonment; exhaustion releases traversal
handles. Native primitives enter through `e.os`, not new host externs in `e.fs`.

Acceptance: malicious concurrent symlink/reparse replacement, moved roots, final
symlink removal, cross-volume replacement, lock contention, early walk exit and
partial durability failure. Reject unsupported guarantees rather than emulate them
with race-prone string checks. No recursive-delete convenience is added implicitly.

## SL07 — streaming HTTP and event streams

ResponseStream separates headers from bounded incremental body reads. It owns the
connection, preserves control through reads, and exposes an explicit close path.
Memory is bounded by parser buffers and caller chunks, not total response length.
Full-body wrappers remain available with explicit total size limits. Automatic
retry, redirect, cookie, credential forwarding and reconnection remain out of scope.

SSE follows the [HTML event-stream algorithm](https://html.spec.whatwg.org/multipage/server-sent-events.html).
Pin the tested standard snapshot at delivery. Cover split UTF-8 and line delimiters,
comments, repeated data, empty IDs, ignored invalid retry fields and EOF without
a dispatching blank line. Reader-owned strings expire on next call. Persistent
reconnection state belongs to the application; the parser performs no networking.

Acceptance: one-byte reads, long-lived streams, event/line/body limit failure,
chunked transfer boundaries, client disconnect/cancellation and bounded memory over
many events. Neither SSE nor streaming HTTP requires HTTP/2 implementation.

## SL08 — reusable cryptographic composition

Add `e.crypto.mac` (HMAC-SHA256/SHA512) and `e.crypto.kdf` (HKDF-SHA256/SHA512), with
independent vectors, fixed-length verification and no hidden entropy. HKDF uses
[RFC 5869](https://www.rfc-editor.org/rfc/rfc5869); it is not a password hashing API.
Key material must not appear in diagnostics; define secret lifetime/zeroization
limitations and alias rules. Authentication failure must not publish unauthenticated
plaintext as a successful result. Test malformed tags and output bounds.

TLS delivery names exact cipher suites, certificate/signature algorithms, entropy
requirements and supported chains, not just a TLS version. Unsupported RSA/ECDSA or
SHA-384 profiles remain explicit until reviewed surfaces exist. Do not claim broad
public-Web certificate interoperability from Ed25519 alone, and never work around
missing algorithms by disabling verification. Native trust/time/entropy remain
explicit inputs. Cryptographic implementation/review stays a later release gate.

## SL09 — fallible iteration, patterns and test support

TryMap/TryFilter and fallible consumers preserve `next_err` failures and borrow the
source; ordinary `for` remains infallible. Terminal errors are not retried implicitly.
Consumer allocation rollback does not rewind a file/socket or undo callback effects.

`e.path.glob`/`glob_match` are bounded pure path matching with explicit syntax,
separator/case policies and no implicit ignore-file rules. Pattern matching is not
filesystem confinement; combine it with SL06 for filesystem actions.

`e.test.support` supplies caller-owned fake clocks, scripted partial/failing I/O,
bounded captured output and a cooperative schedule driver. It neither hooks ambient
OS state nor promises deterministic scheduling of arbitrary threads. Extend source
APIs through explicit inputs rather than adding global testing modes.

Acceptance: next_err plus valid items, callback failure, partial accumulator, early
exit/cleanup; glob malformed syntax, **, dotfiles, style differences and work limits;
fake-clock overflow and deterministic replay of I/O/schedule scripts.

## SL10 — stable pure image and codec cohort

Promote `e.gfx.geometry`, `e.gfx.paint` and `e.gfx.image` to extended alongside existing
extended `e.fmt.png`, `e.fmt.jpeg` and `e.fmt.webp`. The complete public-type dependency
closure shares the `image-codec-conformance` gate. Implement/review them as one
coordinated wave and publish compatibility guarantees together. This is promotion
of a planned contract, not evidence that the code exists today.

GPU scene rendering, text shaping/layout, assets and UI stay experimental. Image
codecs must not depend on device/window initialization. Validate pixel layout,
stride, alpha, overflow, malformed inputs, round trips and independent codec vectors.
No extended/core module may expose an experimental dependency at stable delivery;
the manifest validator conservatively checks all dependency edges now.

## SL11 — truthful discoverability and allocation/error metadata

The module plan is not a runtime availability manifest. A versioned compiler-derived
inventory identifies each module/symbol, installed toolchain/language/target,
implemented versus planned capability, stability/deprecation, signature hash,
canonical import/alias, ownership/borrow effects, allocation source and contract/test
references. H18 freezes its schema and compatibility behavior; no closed v1 stream
is extended silently. Missing evidence means unavailable/unverified, not delivered.

Allocation categories are no allocation, caller arena, stored borrowed arena,
caller-provided storage, bounded private scratch, and explicitly documented driver
storage. Specify per-call versus retained storage, bounds and failure behavior.
Do not disguise stored-arena growth as allocation-free or ban legitimate stack scratch.

`last_error_detail` remains a legacy M2 temporal API during migration. H07 replaces
it in the revised checked surface; an explicitly returned structure alone does not
erase the need to retrieve it before another failure in the old contract. Version
the new transport and propagate primary plus cleanup failures and partial effects.

## Closure evidence

Run `python scripts/check_module_plan.py` and its regression tests after edits.
They validate graph, tier closure, catalogue coverage, signature naming/qualifiers
and extraction structure; they do not prove compiler acceptance or API semantics.
The two self-host suites additionally run `check_module_surfaces.py --compiler` over
all source-delivered modules and require their compiler-resolved declarations to
match the extracted catalogue. The sixteen compiler-origin functions in the
source-delivered `e.atomic`, `e.io` and `e.str` surfaces expose canonical signatures
through the index and are compared exactly as well. All thirteen partial M1/M2
source modules must also deliver every catalogue declaration; twelve have exact
checked signatures, while `e.simd` retains SL01's documented dependent-metavariable
spelling exception. Partial modules may still expose helpers or legacy declarations;
variant-composed `surface:"spec"` modules and other compiler seeds remain outside
this source-file signature gate. Executable CPU fixtures above remain required;
later libraries need their own independent runtime evidence, never a static-check
substitute.

H11 closure links SL01–SL11 to chosen versions, migrated CPU source, conformance
results and deferred-library fixture manifests. H12/H25 exercise end-to-end file
discovery/edit, bounded process execution, lossless JSON and controlled cancellation;
activate TLS/SSE/image workloads when those extended libraries arrive. Record
latency, memory, tokens, repair turns and unrelated diffs per verified success.
