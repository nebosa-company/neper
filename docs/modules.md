# neper — module architecture

Status: normative plan; implementation has not started. `docs/spec.md` controls
language semantics and signatures already fixed there. [`modules.json`](modules.json)
is the machine-readable authority for names, layers, status, milestones, dependencies
and blockers. [`module-apis.md`](module-apis.md) fixes the exact proposed public
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

## 2. Dependency layers

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
- Mutating slice/container operations use `_in_place`, except stateful resource
  operations whose receiver already makes mutation explicit.
- A CI source check compares column-zero `use` declarations with the exact edges in
  `modules.json`; the compiler independently enforces an acyclic import graph.

---

## 3. Canonical grouping

### Layer 0 — foundations

- `e.mem`: arenas, layout and casts.
- `e.meta`: compile-time type shape.
- `e.math`: scalar floating operations.
- `e.simd`: vectors and masks.
- `e.atomic`: atomic operations and ordering.

### Layer 1 — pure primitives

- `e.bytes`: endian and bit operations.
- `e.str`: byte strings, builders, parsing and formatting.
- `e.path`: platform-explicit path manipulation with no filesystem access.

### Layer 2 — containers and pure domains

Containers are one module per data structure rather than the former `e.data` grab bag:

- `e.data.list`, `e.data.deque`, `e.data.ring`, `e.data.heap`, `e.data.tree`.
- `e.data.map`, `e.data.sort`, `e.data.iter`.

Pure algorithm domains are:

- `algo.rand`, `algo.uuid`, `algo.hash`, `algo.stat`, `algo.bignum`.
- `algo.linalg.matrix`, `algo.linalg.tensor`.
- `text.utf8`, `text.unicode`, `text.normalize`, `text.collate`, `text.regex`.
- `crypto.hash`, `crypto.aead`, `crypto.sign`, `crypto.kx`, `crypto.random`.

This separation keeps non-cryptographic table/checksum hashes out of the security
namespace, decomposes the former `algo.text`, and prevents matrices and tensors from
becoming unrelated top-level buckets. Locale databases remain optional external data.

### Layer 3 — platform boundary

- `e.os`: the reviewed minimum for files, processes, VM, clocks, threads, wait/wake,
  sockets, polling, dynamic loading, environment and entropy. Higher modules add a
  primitive here before using a platform facility; they never declare their own host
  extern.

### Layer 4 — host services

- `e.io`, `e.fs`, `e.proc`, `e.thread`, `e.sync`, `e.channel`, `e.time`.

Channels are separate from locks because they allocate and impose a higher-level
concurrency protocol. Timers live in `e.time`, not `e.debug`.

### Layer 5 — language-owned runtimes

- `e.gpu`: compiler-owned GPU model and host runtime.
- `e.test`: assertion functions; discovery and isolation stay in the compiler.
- `e.debug`: backtrace capture and symbolization only.

### Layer 6 — application and protocols

- `e.metrics`, `e.log`, `e.cli`, `e.async`.
- `e.net`, `e.net.http`, `e.net.ws`.
- `e.gpu.tensor`: explicit GPU tensor operations over pure `algo.linalg.tensor` views.
- `fmt.json`, `fmt.csv`, `fmt.ini`, `fmt.yaml`, `fmt.xml`, `fmt.bson`,
  `fmt.msgpack`, `fmt.protobuf`.

HTTP/1.1 is the initial `e.net.http` surface. HTTP/2 requires a separate future
proposal because HPACK and multiplexed connection state are not an incremental flag.
`e.async` is an explicit readiness/completion loop, not futures or compiler-generated
coroutines. A web framework is not a guaranteed language facility and belongs in
`x.neper.web`.

---

## 4. Optional package reservations

Optional package names are ownership reservations, not fabricated API promises:

- `x.neper.web`, `x.neper.locale`.
- `x.neper.os.{win,linux,macos,android}`.
- `x.neper.compress.{gzip,zstd}` and `x.neper.archive.{zip,tar}`.
- `x.neper.image.{png,jpeg,webp}` and `x.neper.audio.{wav,mp3,ogg}`.
- `x.neper.document.pdf`, `x.neper.tui`.
- `x.neper.db.{sqlite,mysql,pgsql}`.
- `x.neper.{tls,x509,jwt}` as three security concerns, not the former `x.sec` bucket.
- `x.khronos.{vulkan,opengl}`, `x.google.skia`,
  `x.nvidia.cuda.{cublas,cudnn}`, `x.apple.metal`.

A package has no promised declarations until its own versioned specification pins its
upstream ABI/data version and enumerates the complete surface. Compiler backends such
as ROCm, OpenCL or WebGPU are not library package reservations.

---

## 5. Protocol dependencies

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

## 6. API ownership

- `surface:"spec"` means `spec.md` already fixes the declarations' semantics;
  `surface:"partial"` means the spec fixes only the subset it names; and
  `surface:"planned"` means `module-apis.md` is the exact proposal to freeze before
  implementation of that milestone. `surface:"source"` is reserved for a future
  plan revision after an implementation exists.
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
