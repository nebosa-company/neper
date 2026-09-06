# neper — module architecture

Status: normative next-contract plan, not an implementation-status report. `docs/spec.md` controls
language semantics and signatures already fixed there. [`modules.json`](modules.json)
is the machine-readable authority for names, delivery tiers, layers, status,
milestones, dependencies and blockers. [`module-apis.md`](module-apis.md) fixes the exact proposed public
surface of every toolchain module. All three views change together.

The adopted [standard-library hardening](stdlib-hardening.md) (D84) defines
composition, migration and executable acceptance. Delivered CPU surfaces migrate
in M2.5; later modules remain proposals until their own tests and implementation
exist. The catalogue currently has 128 modules: 33 core, 77 extended, 18 experimental.

---

## 1. Namespace policy

| Prefix | Meaning | Distribution |
|---|---|---|
| `e.*` | Stable facilities owned by the language and guaranteed by the applicable toolchain version | Toolchain |
| `algo.*` | Concrete domain types and pure computation over caller-owned data | Toolchain |
| `text.*` | Unicode and text processing | Toolchain |
| `crypto.*` | Pure cryptographic primitives; entropy is caller-supplied | Toolchain |
| `fmt.*` | Interchange-format parsers and writers | Toolchain |
| `gfx.*` | Pure geometry/paint/image values and GPU scene rendering | Toolchain |
| `ui.*` | Declarative, GPU-rendered application framework | Toolchain |
| `x.<owner>.<package>.*` | Optional, platform, vendor or externally versioned package | Separate source package |

Namespaces describe ownership and domain, not whether code is implemented with an
intrinsic. `e.*` availability begins at the module's delivery milestone; it does not
put every module into the bootstrap.

### `e.data.*` against `algo.*`

Genericity decides which of the two a module belongs to:

- **`e.data.*` is generic containers**, parameterised by the element type the caller
  puts in them: `List[T]`, `Map[K, V]`, `Ring[T]`, `Heap[T]`, `Tree[K, V]`,
  `SlotMap[T]`.
- **`algo.*` is concrete domain types and pure computation over caller-owned data**:
  `Uuid`, `Decimal`, `Bignum`, `BitSet`, `Pcg64`, and the sorting and traversal
  functions. Where an `algo.*` type is generic it is over a numeric parameter, as
  `Complex[F]`, `Matrix[F]` and `Tensor[F]` are, and not over an arbitrary `T`.

**Storage ownership is not the test.** `e.data.ring` takes `init(storage: []T)` and
`algo.disjoint_set` takes `init(parent: []u32, rank: []u8, ...)`. Both borrow caller
storage; the first is a container and the second is not.

A type that can never hold an arbitrary `T` belongs in `algo.*` even where general
convention files it with the containers. `algo.bitset` is a bit vector over `[]u64`
words holding bit indices, which makes it kin to `Uuid` and `Decimal`; the generic
`Set` in `e.data.map` is the contrast, a container over whatever key type the caller
names. Same word, different thing.

Imports use spec §2's default final-segment qualifier or an explicit alias. Final
segments are not globally reserved:

```neper
use e.data.map
use x.acme.collections.map as acme_map
```

External packages always include an owner. Each vendored package root contains a
canonical `neper-package.json`. The legacy pre-pacman form records exact source and
dependency pins; the M6 form in [pacman.md](pacman.md#package-manifests) records
language/exports and dependency constraints, while source identity and resolved
pins belong to registry/lock metadata. This migration must version the closed
schema explicitly; the two forms are not interchangeable just because earlier
drafts both called them version 1. Neither is a second compiler resolver.

---

## 2. Delivery tiers

Delivery tier is independent of dependency layer. The ordered `tiers` arrays in
`modules.json` are authoritative, contain every toolchain module exactly once and
express product commitment rather than import legality:

| Tier | Compatibility and delivery contract |
|---|---|
| `core` | Required for the first stable CPU release; numbered milestones and explicitly documented cross-cutting gates both apply |
| `extended` | Toolchain-owned and stable once delivered, but independently deliverable and not a first-stable gate |
| `experimental` | An API proposal available for evaluation with no compatibility promise |

Core is deliberately small: language foundations; ordinary collections; hashing,
randomness, UUIDs and bit sets; basic UTF-8; shared cancellation; host I/O/process/thread/time services; testing; and
JSON, CSV and INI. Extended contains specialized containers and algorithms, Unicode,
cryptography, GPU support, application services, networking and advanced formats.
Pure geometry/paint/image values and PNG/JPEG/WebP codecs form one extended
stabilization cohort (`image-codec-conformance`); GPU rendering and UI do not gate it.
Experimental contains workload-dependent collection conveniences, GPU tensor
composition, and the declarative GPU UI proposal. Promotion changes `modules.json`, adds the
applicable conformance workload and records a compatibility decision. Experimental
modules never satisfy a dependency of a core or extended module. This conservative
rule protects public-type stability transitively, not only import legality.

`text.utf8` and `e.cancel` are core additions delivered through M2.5's cross-cutting
library gate, with `schedule:"later", milestone:null` rather than inventing an
unvalidated Mn value. Their gate is specified in `stdlib-hardening.md`; this does
not change the preserved M2 completion criteria or imply they are already available.

The catalogue in `module-apis.md` remains dependency-layer ordered so a reader can
understand implementation direction. Product UI and generated documentation present
the tier order from `modules.json`: core, extended, then experimental.

---

## 3. Dependency layers

| Layer | Role |
|---:|---|
| 0 | Language foundations and compiler intrinsics |
| 1 | Pure byte, string and path foundations |
| 2 | Containers and pure algorithm/text/crypto domains |
| 3 | Host platform boundary |
| 4 | Host services |
| 5 | Language-owned runtimes |
| 6 | Application facilities, networking and interchange formats |

`modules.json` lists every direct edge. A module may use only a layer allowed by its
layer's `may_depend_on`, and a same-layer dependency is legal only when listed. This
prevents the cycles that a loose “same row or lower” diagram cannot catch.

The JSON arrays carry presentation order, not identity or priority. Consumers key
layers by `id` and modules/packages by `name`; they reject duplicate keys, unknown
dependency names, disallowed layer edges, dependency cycles, or any mismatch between
module names and the level-three headings in the `api_catalog` file. A `blocked_by`
value is either a toolchain module name or a stable kebab-case design identifier;
only `direct_dependencies` defines graph edges. A package reservation is never
inserted into the toolchain module graph.

Global constraints:

- `e.os` is the only ordinary toolchain module declaring host-platform `extern`s.
  Reviewed GPU-driver loading in `e.gpu` and explicit `x.*` bindings are the two
  exceptions.
- Every allocation has a documented source: caller arena, retained borrowed arena,
  caller-provided storage, bounded private scratch or an explicit driver exception.
  Classify allocation-free calls separately. No general global allocator or
  pre-`main` initializer is introduced; compiler-owned test-report state and existing
  legacy platform-detail state are explicit exceptions, not invisible guarantees.
- Pure modules never read files, environment, clocks, entropy or network state.
- Portable `err` values remain the default propagation surface. Host modules that
  expose native detail identify its capture time and ownership. The old
  `last_error_detail` path is thread-local and temporal despite returning a struct;
  H07 replaces it in the revised checked API. Primary errors, cleanup failures and
  partial progress must remain distinguishable; do not imply the migration is done.
- Mutating slice/container operations use `_in_place`, except stateful resource
  operations whose receiver already makes mutation explicit.
- A CI source check compares column-zero `use` declarations with the exact edges in
  `modules.json`; the compiler independently enforces an acyclic import graph.
- `python scripts/check_module_plan.py` checks the current plan/catalogue's graph,
  tiers, naming and import-qualifier consistency. It supplements, not replaces,
  the M2.5 real parser/resolver and executable API tests.

---

## 4. Canonical grouping

### Layer 0 — foundations

- `e.mem`: arenas, layout and casts.
- `e.meta`: compile-time type shape.
- `e.math`: scalar floating operations.
- `e.simd`: vectors and masks.
- `e.atomic`: atomic operations and ordering.

### Layer 1 — pure primitives

- `e.bytes`: endian and bit operations.
- `e.str`: byte strings, ASCII search/edit/classification, builders, parsing and formatting.
- `e.path`: platform-explicit path manipulation with no filesystem access.

### Layer 2 — containers and pure domains

Containers are one module per data structure, each generic over its element type
(§1), rather than the former `e.data` grab bag:

- `e.data.list`, `e.data.deque`, `e.data.stack`, `e.data.queue`, `e.data.linked`,
  `e.data.ring`, `e.data.heap`, `e.data.tree`.
- `e.data.map`, `e.data.iter`, `e.data.graph`, `e.data.slot_map`.

Pure algorithm domains are:

- `algo.rand`, `algo.uuid`, `algo.hash`, `algo.graph`, `algo.stat`, `algo.bitset`,
  `algo.sort`, `algo.disjoint_set`, `algo.complex`, `algo.decimal`, `algo.bignum`,
  `algo.deflate`.
- `algo.linalg.matrix`, `algo.linalg.tensor`.
- `text.encoding`, `text.utf8`, `text.unicode`, `text.normalize`, `text.collate`,
  `text.regex`.
- `crypto.hash`, `crypto.mac`, `crypto.kdf`, `crypto.aead`, `crypto.sign`, `crypto.kx`, `crypto.random`;
  `crypto.x509` composes certificates and validation over the format layer.
- `gfx.geometry`, `gfx.paint`, `gfx.image`; `ui.style` and `ui.layout` are pure value
  and constraint engines despite their application-facing names.
- `text.shape`, `text.layout`: deterministic font shaping and visual text layout over
  caller-provided font data.

This separation keeps non-cryptographic table/checksum hashes out of the security
namespace, decomposes the former `algo.text`, and prevents matrices and tensors from
becoming unrelated top-level buckets.

### Layer 3 — platform boundary

- `e.os`: the reviewed minimum for files, processes, VM, clocks, threads, wait/wake,
  sockets, polling, dynamic loading, environment and entropy. Higher modules add a
  primitive here before using a platform facility; they never declare their own host
  extern.

### Layer 4 — host services

- `e.cancel`, `e.io`, `text.io`, `e.fs`, `e.fs.mmap`, `e.fs.watch`, `e.proc`, `e.thread`,
  `e.sync`, `e.channel`, `e.concurrent.queue`, `e.concurrent.map`,
  `e.task`, `e.time`, `e.time.calendar`, `e.tz`.

Channels are separate from locks because they allocate and impose a higher-level
concurrency protocol. `e.task` is a bounded, cooperative-cancellation pool rather
than compiler-generated async syntax. Calendar arithmetic is pure despite living at
the host-service layer beside the clocks it commonly consumes. `e.tz` carries the
toolchain-pinned IANA database and also accepts explicit compatible data. Timers live
in `e.time`, not `e.debug`.

### Layer 5 — language-owned runtimes

- `e.gpu`: compiler-owned GPU model and host runtime, including bounded device
  discovery, backend-scoped exact-ID selection, device descriptors and explicit
  per-device queues/buffers (spec §10; CPU/Vulkan M3, CUDA M4).
- `e.asset`: immutable, linker-generated lookup over manifest-declared executable assets.
- `e.test`: assertion functions; discovery and isolation stay in the compiler.
- `e.test.support`: explicit fake clocks, scripted I/O and cooperative schedule
  drivers, not hooks into ambient OS state or a general deterministic thread runtime.
- `e.test.coverage` and `e.test.fuzz`: compiler-instrumented coverage plus
  deterministic corpus mutation and minimization.
- `e.debug`: backtrace capture and symbolization only.

### Layer 6 — application and protocols

- `e.metrics`, `e.log`, `e.cli`, `e.async`, `e.async.io`, `text.locale`,
  `text.template`.
- `e.net`, `e.net.tls`, `e.net.http`, `e.net.ws`.
- `e.db`: generic SQL connections, transactions, prepared statements and streaming
  row readers; concrete drivers remain owner-qualified packages.
- `e.gpu.tensor`: explicit GPU tensor operations over pure `algo.linalg.tensor` views.
- `gfx.scene`: renderer-neutral display lists, retained scenes and GPU composition.
- `ui.asset`: deterministic scale/theme/locale variant selection, fonts and bounded
  decoded-image/GPU texture caching over `e.asset`.
- `ui.window`, `ui.input`, `ui.widget`, `ui.animation`, `ui.accessibility`,
  `ui.testing`, `ui.app`: the experimental declarative GPU application framework.
- `fmt.json`, `fmt.csv`, `fmt.ini`, `fmt.uri`, `fmt.mime`, `fmt.asn1`, `fmt.pem`,
  `fmt.multipart`, `fmt.mail`, `fmt.quoted_printable`, `fmt.gzip`, `fmt.zstd`,
  `fmt.bzip2`, `fmt.lzw`, `fmt.zlib`, `fmt.zip`, `fmt.tar`, `fmt.yaml`, `fmt.xml`,
  `fmt.html`, `fmt.html.template`, `fmt.png`, `fmt.jpeg`, `fmt.webp`, `fmt.bson`,
  `fmt.msgpack`, `fmt.protobuf`.

HTTP/1.1 is the initial `e.net.http` surface. HTTP/2 requires a separate future
proposal because HPACK and multiplexed connection state are not an incremental flag.
`e.async` is an explicit readiness/completion loop, not futures or compiler-generated
coroutines; `e.async.io` composes typed, cancellation-aware operations over it.
Streaming response bodies and bounded SSE parsing are part of `e.net.http`; they
need no new namespace or HTTP/2 implementation. `e.path` owns pure bounded glob
matching; `fmt.json` owns lossless numbers, Pointer and transactional in-memory Patch.
`e.proc` owns bounded child supervision, and `e.fs` exposes handle-relative root
operations over reviewed `e.os` primitives. Exact semantics and delivery tests are
in `stdlib-hardening.md`; none permits automatic retries of partial side effects.

`fmt.html` is distinct from `fmt.xml`: it implements HTML error recovery and the
WHATWG tree-construction algorithm into a bounded, arena-owned tree. Like every
format module it receives bytes or a reader and never opens a file or fetches a
resource itself.

`fmt.html.template` adds context-sensitive escaping over `text.template`; it is
separate from parsing because template execution generates a stream rather than an
HTML tree. Image codecs decode into caller-owned `gfx.image` pixels. Certificate
validation is split the same way: `fmt.asn1` and `fmt.pem` own encodings, while
`crypto.x509` owns chain and identity policy used by `e.net.tls`.

The UI family is specified in [`ui-framework.md`](ui-framework.md). Declarative
widgets are immutable frame-arena descriptions, not runtime objects. Reconciliation
stores persistent elements and state behind generation-checked identifiers;
layout produces retained render nodes, and `gfx.scene` compiles them into explicit
GPU work. Native windows, input, clipboard, IME and accessibility enter only through
reviewed `e.os` primitives. There is no garbage collector, global widget registry,
reflection-based property system or hidden allocation.

---

## 5. Optional package reservations

Optional package names identify their actual external owner; `x.neper.*` is forbidden
because toolchain-owned facilities use the domain namespaces above:

- `x.khronos.{vulkan,opengl}`, `x.google.skia`,
  `x.nvidia.cuda.{cublas,cudnn}`, `x.apple.metal`.
- `x.sqlite.sqlite`, `x.oracle.mysql`, `x.postgresql.libpq`: concrete database
  drivers implementing `e.db`, named for the SQLite project, Oracle-owned MySQL,
  and PostgreSQL's official `libpq` client library respectively.

A package has no promised declarations until its own versioned specification pins its
upstream ABI/data version and enumerates the complete surface. Compiler backends such
as ROCm, OpenCL or WebGPU are not library package reservations. URI, MIME, locale,
TLS, compression and archives are toolchain modules rather than pseudo-external
packages; their standard/data snapshot is tied to the toolchain version and exposed
where reproducibility requires it.

---

## 6. Protocol dependencies

| Protocol | Consumers |
|---|---|
| `<t>_hash`, `<t>_eq` | `e.data.map`, equality assertions and document nodes |
| `<t>_cmp` | sorting, heaps, ordered trees and collation |
| `<t>_format` | formatted output, logging and writers |
| `<i>_next` | in-memory containers and iterator adapters |
| `<i>_next_err` | filesystem, network and streaming-format readers |
| `e.meta` shape queries | structural encoders/decoders and CLI configuration |

These are direct monomorphized calls fixed by spec §9, not runtime interfaces,
registration or RTTI.

---

## 7. API ownership

- `surface:"spec"` means `spec.md` already fixes the declarations' semantics;
  `surface:"partial"` means the spec fixes only the subset it names; and
  `surface:"planned"` means `module-apis.md` is the exact proposal to freeze before
  implementation of that milestone. `surface:"source"` means an implementation
  exists and the same revision verifies its complete public declarations against
  `module-apis.md`.
- `schedule:"scheduled"` requires a non-null `milestone`; every other schedule has
  `milestone:null`. A blocker describes a prerequisite and does not alter that
  normalized delivery state.
- [`module-apis.md`](module-apis.md) lists every proposed public type, error, constant
  and function for layers 0–6. A name absent there is not planned.
- `spec` surfaces change only through `decisions.md`. `planned` surfaces are frozen
  before implementation of their milestone begins.
- Optional `x.*` packages own separate specifications because an exact binding cannot
  exist before an upstream version is selected.
- Removing or renaming a module or declaration is an ecosystem compatibility change.
  Adding a declaration also requires protocol, import-qualifier and local/parameter
  shadowing impact analysis. No blanket non-breaking claim follows from addition.
- Installed availability is a separate compiler-derived versioned inventory, with
  per-symbol/target implementation, stability, contract and test evidence. Never
  infer availability from `surface` or `milestone` alone (H11/H18, SL11).
