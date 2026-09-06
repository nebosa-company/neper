# neper — module architecture

Status: normative plan; implementation has not started. `docs/spec.md` controls
language semantics and signatures already fixed there. [`modules.json`](modules.json)
is the machine-readable authority for names, delivery tiers, layers, status,
milestones, dependencies and blockers. [`module-apis.md`](module-apis.md) fixes the exact proposed public
surface of every toolchain module. All three views change together.

---

## 1. Namespace policy

| Prefix | Meaning | Distribution |
|---|---|---|
| `e.*` | Stable facilities owned by the language and guaranteed by the applicable toolchain version | Toolchain |
| `algo.*` | Pure algorithms over caller-owned data | Toolchain |
| `text.*` | Unicode and text processing | Toolchain |
| `crypto.*` | Pure cryptographic primitives; entropy is caller-supplied | Toolchain |
| `fmt.*` | Interchange-format parsers and writers | Toolchain |
| `gfx.*` | Pure geometry/paint/image values and GPU scene rendering | Toolchain |
| `ui.*` | Declarative, GPU-rendered application framework | Toolchain |
| `x.<owner>.<package>.*` | Optional, platform, vendor or externally versioned package | Separate source package |

Namespaces describe ownership and domain, not whether code is implemented with an
intrinsic. `e.*` availability begins at the module's delivery milestone; it does not
put every module into the bootstrap.

Imports use spec §2's default final-segment qualifier or an explicit alias. Final
segments are not globally reserved:

```neper
use e.data.map
use x.acme.collections.map as acme_map
```

External packages always include an owner. Each vendored package root contains a
canonical `neper-package.json` recording schema version, owner-qualified name,
semantic version, license, source URL and SHA-256, pinned dependencies, and any
upstream ABI/data version. It is package-manager data recorded by the build manifest,
not a second compiler resolver.

---

## 2. Delivery tiers

Delivery tier is independent of dependency layer. The ordered `tiers` arrays in
`modules.json` are authoritative, contain every toolchain module exactly once and
express product commitment rather than import legality:

| Tier | Compatibility and delivery contract |
|---|---|
| `core` | Required for the first stable CPU release; its scheduled milestone gates that release |
| `extended` | Toolchain-owned and stable once delivered, but independently deliverable and not a first-stable gate |
| `experimental` | An API proposal available for evaluation with no compatibility promise |

Core is deliberately small: language foundations; ordinary collections; hashing,
randomness, UUIDs and bit sets; host I/O/process/thread/time services; testing; and
JSON, CSV and INI. Extended contains specialized containers and algorithms, Unicode,
cryptography, GPU support, application services, networking and advanced formats.
Experimental contains workload-dependent collection conveniences, GPU tensor
composition, and the declarative GPU UI proposal. Promotion changes `modules.json`, adds the
applicable conformance workload and records a compatibility decision. Experimental
modules never satisfy a dependency of a core module.

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
- Every allocation names a caller-owned `*mem.Arena`; there is no global allocator,
  hidden module state or pre-`main` initializer.
- Pure modules never read files, environment, clocks, entropy or network state.
- Portable `err` values remain the default propagation surface. Host modules that
  expose native detail copy it into an explicit `os.ErrorDetail`; messages and
  subjects are never hidden exception or process-global payloads.
- Mutating slice/container operations use `_in_place`, except stateful resource
  operations whose receiver already makes mutation explicit.
- A CI source check compares column-zero `use` declarations with the exact edges in
  `modules.json`; the compiler independently enforces an acyclic import graph.

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

Containers are one module per data structure rather than the former `e.data` grab bag:

- `e.data.list`, `e.data.deque`, `e.data.stack`, `e.data.queue`, `e.data.linked`,
  `e.data.ring`, `e.data.heap`, `e.data.tree`.
- `e.data.map`, `e.data.sort`, `e.data.iter`, `e.data.disjoint_set`,
  `e.data.graph`, `e.data.slot_map`.

Pure algorithm domains are:

- `algo.rand`, `algo.uuid`, `algo.hash`, `algo.graph`, `algo.stat`, `algo.bitset`,
  `algo.complex`, `algo.decimal`, `algo.bignum`, `algo.deflate`.
- `algo.linalg.matrix`, `algo.linalg.tensor`.
- `text.encoding`, `text.utf8`, `text.unicode`, `text.normalize`, `text.collate`,
  `text.regex`.
- `crypto.hash`, `crypto.aead`, `crypto.sign`, `crypto.kx`, `crypto.random`.
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

- `e.io`, `text.io`, `e.fs`, `e.fs.mmap`, `e.fs.watch`, `e.proc`, `e.thread`,
  `e.sync`, `e.channel`, `e.concurrent.queue`, `e.concurrent.map`,
  `e.task`, `e.time`, `e.time.calendar`, `e.tz`.

Channels are separate from locks because they allocate and impose a higher-level
concurrency protocol. `e.task` is a bounded, cooperative-cancellation pool rather
than compiler-generated async syntax. Calendar arithmetic is pure despite living at
the host-service layer beside the clocks it commonly consumes. `e.tz` carries the
toolchain-pinned IANA database and also accepts explicit compatible data. Timers live
in `e.time`, not `e.debug`.

### Layer 5 — language-owned runtimes

- `e.gpu`: compiler-owned GPU model and host runtime.
- `e.asset`: immutable, linker-generated lookup over manifest-declared executable assets.
- `e.test`: assertion functions; discovery and isolation stay in the compiler.
- `e.debug`: backtrace capture and symbolization only.

### Layer 6 — application and protocols

- `e.metrics`, `e.log`, `e.cli`, `e.async`, `e.async.io`, `text.locale`.
- `e.net`, `e.net.tls`, `e.net.http`, `e.net.ws`.
- `e.gpu.tensor`: explicit GPU tensor operations over pure `algo.linalg.tensor` views.
- `gfx.scene`: renderer-neutral display lists, retained scenes and GPU composition.
- `ui.asset`: deterministic scale/theme/locale variant selection, fonts and bounded
  decoded-image/GPU texture caching over `e.asset`.
- `ui.window`, `ui.input`, `ui.widget`, `ui.animation`, `ui.accessibility`,
  `ui.testing`, `ui.app`: the experimental declarative GPU application framework.
- `fmt.json`, `fmt.csv`, `fmt.ini`, `fmt.uri`, `fmt.mime`, `fmt.gzip`, `fmt.zstd`,
  `fmt.zip`, `fmt.tar`, `fmt.yaml`, `fmt.xml`, `fmt.html`, `fmt.bson`, `fmt.msgpack`,
  `fmt.protobuf`.

HTTP/1.1 is the initial `e.net.http` surface. HTTP/2 requires a separate future
proposal because HPACK and multiplexed connection state are not an incremental flag.
`e.async` is an explicit readiness/completion loop, not futures or compiler-generated
coroutines; `e.async.io` composes typed, cancellation-aware operations over it.

`fmt.html` is distinct from `fmt.xml`: it implements HTML error recovery and the
WHATWG tree-construction algorithm into a bounded, arena-owned tree. Like every
format module it receives bytes or a reader and never opens a file or fetches a
resource itself.

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
- `spec` surfaces change only through `DECISIONS.md`. `planned` surfaces are frozen
  before implementation of their milestone begins.
- Optional `x.*` packages own separate specifications because an exact binding cannot
  exist before an upstream version is selected.
- Removing or renaming a module or declaration is an ecosystem compatibility change.
  Adding a declaration is non-breaking only when it creates no protocol collision.
