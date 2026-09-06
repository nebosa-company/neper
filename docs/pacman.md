# pacman — package manager design

Status: approved architecture for roadmap M6. This document fixes the package
manager contract before implementation. It does not change neper v1 source semantics:
`e.*`, `e.algo.*`, `e.text.*`, `e.crypto.*`, `e.fmt.*`, `e.gfx.*` and `e.ui.*` still ship with the toolchain,
while pacman primarily acquires external `x.*` source.

## 1. Boundary and principles

Pacman is a dependency resolver, immutable source store, registry client, and
publisher. It is not a second build system and never type-checks or compiles neper.
The compiler remains deterministic and never accesses the network; pacman prepares a
locked module map, then invokes the ordinary compiler command when asked.

The contract is:

1. The manifest records intent; the lockfile records the complete truth.
2. A locked build performs no dependency resolution and observes no mutable remote
   state.
3. Package contents are addressed and verified by cryptographic hash.
4. The global cache is immutable. A package cannot modify itself or another package
   after installation.
5. Module names remain path-derived inside a package. Pacman supplies an internal
   virtual source map; it does not copy a `node_modules` tree into the project.
6. The package graph is source-only and acyclic. Native libraries remain explicit
   compiler/linker inputs under the existing `extern` rules.
7. No dependency executes code merely because it was resolved, downloaded, or
   installed.

The package manager is called **pacman**, but its portable command spelling is
`neper pacman`. A standalone `pacman` executable would collide with Arch Linux's
system package manager. A distribution may provide a non-default `neper-pacman`
launcher that forwards to the same command group.

## 2. Tier and namespace policy

- `e.*` is inseparable from a specific neper toolchain version. Pacman must reject a
  package that exports or replaces an `e.*` module.
- The toolchain's `e.algo.*`, `e.text.*`, `e.crypto.*`, `e.fmt.*`, `e.gfx.*` and `e.ui.*` modules follow the same
  rule. Their version is the language/toolchain version, not an independently
  resolved package version.
- Public third-party packages export modules beneath `x.<owner>.*`. The public
  registry verifies that the authenticated owner controls that prefix. Ownerless
  short names are invalid; curated packages use an explicit owner such as
  `x.microsoft.win32` or `x.khronos.vulkan`.
- A private registry may allocate its own owners, but two locked packages may not
  export the same fully qualified module name. Import aliases solve local qualifier
  collisions; they do not make duplicate module definitions legal.
- Package identity and module identity are separate. A package coordinate is
  `<registry>/<package-name>`, where a public package name begins `x.<owner>.`; one
  package may export several modules under its declared prefix.

This keeps the core tiers available offline with the compiler and focuses package
resolution on `x.*`, where external versions and native dependencies actually exist.

## 3. Project manifest: `project.yaml`

`project.yaml` is human-authored intent. Pacman accepts a deliberately small YAML
1.2 subset: UTF-8 mappings, sequences, quoted or plain strings, booleans, and decimal
integers. Anchors, aliases, tags, merge keys, duplicate keys, implicit timestamps,
non-string mapping keys, and multiple documents are errors. Pacman rewrites the file
in a canonical two-space layout without reordering comments across keys.

```yaml
schema: neper-project-1
name: telemetry_agent
version: 0.4.0
language: "0.1"

targets:
  agent:
    root: src/main.e
    before: [generate_grpc]

registries:
  default: https://packages.neper.dev/v1
  internal: https://packages.example.test/neper/v1

dependencies:
  skia:
    package: x.graphics.skia
    version: ^1.2.0
  internal_tool:
    package: x.acme.custom_tool
    git: https://gitlab.example.test/acme/custom_tool.git
    ref: v1.0.4

assets:
  images/logo@1x:
    path: assets/logo.png
    media_type: image/png
    attributes: {base: images/logo, scale: "1", theme: any, locale: ""}
  images/logo@2x-dark:
    path: assets/logo@2x-dark.png
    media_type: image/png
    attributes: {base: images/logo, scale: "2", theme: dark, locale: ""}
  fonts/inter-regular:
    path: assets/Inter-Regular.ttf
    media_type: font/ttf
    attributes: {base: fonts/inter, scale: "1", theme: any, locale: ""}

tasks:
  generate_grpc:
    command: [tools/protoc, --neper_out, .neper/generated, api.proto]
    inputs: [api.proto]
    outputs: [.neper/generated/rpc/client.e]
    capabilities: [process]
```

Required keys are `schema`, `name`, `version`, and `language`. Optional keys are
`targets`, `registries`, `dependencies`, `dev_dependencies`, `tools`, `assets`, and `tasks`.
Unknown keys are errors, so a typo cannot silently change resolution. Pacman locates
the project at the nearest ancestor containing `project.yaml`; that directory must
also be the compiler project root containing `src/` or `lib/`.

Dependency keys such as `skia` are project-local labels used by CLI commands and lock
records. A dependency selects exactly one source:

- Registry: `package`, `version`, and optional `registry` (default: `default`).
- Git: `package`, `git`, and exactly one of `ref`, `tag`, `branch`, or `rev`.
- Path: `package` and `path`, relative to the manifest. Path dependencies are for
  local development and make public publishing invalid.

`tools` is a mapping from a local label to `command`, exact `version`, and a
`sha256` mapping keyed by host triple. Pacman resolves the executable without a shell,
checks its reported version and bytes, and records the selected identity in the task
result. A task using an external tool is portable only across the host triples for
which the manifest supplies a digest; otherwise it is deliberately host-local and its
outputs cannot satisfy a cross-host reproducibility claim.

Versions use SemVer 2.0.0. The supported constraints are an exact version, comparison
sets, `^`, `~`, and comma-separated intersections. There are no optional dependencies,
feature unification, target-conditional dependencies, or arbitrary version scripts in
version 1. Target-specific `.e` files already express platform selection, and one
platform-independent graph keeps a lockfile identical across hosts.

Every target has `root` and an optional ordered `before` task list. This is pacman
metadata, not a new entry-point rule. `neper pacman build agent` runs only those
root-declared tasks, resolves the root to `src/main.e`, and invokes
`neper build src/main.e` with the locked module map. Direct `neper build <file.e>`
remains valid and runs no task.

`assets` maps a unique normalized logical name to `path`, an ASCII-lowercase
`media_type`, and an optional string-to-string `attributes` mapping. Paths are
project-relative, may not escape the root after symlink resolution and must identify
regular files. Logical names use `/` separators, contain no empty, `.` or `..`
segment, and are sorted by UTF-8 bytes before linking. The raw file bytes are embedded
unchanged; executable-section compression is deliberately outside version 1 so
`e.asset.Asset.bytes` is always a zero-copy process-lifetime slice.

The conventional UI attributes are `base`, positive finite decimal `scale`, `theme`
(`any`, `light` or `dark`) and a canonical BCP 47 `locale` or the empty fallback.
`e.ui.asset` ignores unknown attributes but rejects malformed conventional ones.
Ordinary `e.asset` callers may define other attributes. Asset names, metadata, sizes
and SHA-256 values enter incremental and final link identity. Direct `neper build`
outside a project embeds no assets. Dependency-package assets and external runtime
assets are deferred; version 1 embeds only declarations in the root project.

### Package manifests

Every dependency root contains `neper-package.json`, the canonical JSON package
manifest already named by `docs/modules.md`. At M6 its version-1 fields are
`schema:"neper-package"`, `version:1`, package `name`, `package_version`, language
constraint, SPDX `license`, `exports`, and `dependencies`; source URL and digests are
registry/lock metadata, not author-asserted identity. `exports` is the sorted complete
list of modules in the archive. Dependency entries contain package coordinate,
SemVer constraint, and registry name; public releases may not contain path or Git
dependencies. This M6 constraint form supersedes the pre-pacman exact-dependency
placeholder in the module plan—the lockfile, not a published package manifest, pins
the selected transitive versions.

## 4. Lockfile: `project.lock`

`project.lock` is generated canonical JSON despite its extension: UTF-8, LF, sorted
object keys where order is not prescribed below, two-space indentation, one final
newline. JSON makes the truth format unambiguous and cheap for harnesses to validate;
YAML's human conveniences are useful only in the intent file.

The root object contains:

- `schema: "neper-lock"` and `version: 1`;
- the canonical SHA-256 of `project.yaml` after parsing and schema normalization;
- the required language version and resolver version;
- every registry URL used, with its signed metadata snapshot/version;
- `packages`, sorted by package coordinate and version;
- the resolved direct dependency labels and the exact package record they select.

Every package record contains its coordinate, exact SemVer, source kind, immutable
source identity, archive or tree SHA-256, normalized manifest SHA-256, licence
identifiers, exported modules, and exact dependency edges. Registry records carry the
registry URL and release digest. Git records carry URL, requested ref for audit only,
resolved full commit ID, and canonical tree SHA-256. Path records carry the normalized
project-relative path and tree SHA-256.

A branch or tag may move remotely; `sync` never follows it. The lockfile's commit and
tree hash are authoritative. Git submodules are rejected in version 1 rather than
introducing an unrecorded dependency graph. A yanked registry version remains
installable from an existing lock but is not selected by new resolution.

The lockfile contains no machine-local cache path, credential, timestamp, host triple,
or absolute project path. Resolving the same manifest against the same signed registry
snapshot produces byte-identical lockfiles on Windows, Linux, macOS, and inside a
container.

## 5. Resolution

Pacman uses PubGrub: it is fast for ordinary graphs and, unlike a bare SAT failure,
produces a deterministic incompatibility explanation. Candidate ordering is highest
non-yanked stable version first, then prereleases only when the manifest explicitly
admits one. Package coordinate breaks all remaining ties by UTF-8 bytes.

Resolution reads immutable registry metadata snapshots into a local metadata cache.
The chosen snapshot IDs enter the lockfile. Registry mirrors may serve identical
content by digest, but fallback never changes package identity or the chosen version.
Conflicting full module exports, dependency cycles, an incompatible language range,
or two sources for one package coordinate are resolution errors.

Commands have deliberately different mutation rules:

- `add` edits the manifest and resolves a new lock.
- `remove` edits the manifest and resolves a new lock.
- `resolve` regenerates the lock from current manifest constraints.
- `upgrade` changes locked versions only within existing constraints.
- `upgrade --major <label>` edits that dependency's manifest constraint and resolves.
- `sync` never resolves or edits either file.

This makes review straightforward: constraint changes appear in `project.yaml`; newly
selected transitive code appears in `project.lock`.

## 6. Sources: registry, Git, and path

### Registries

The default public registry is configured by the toolchain, and a project may add
named private registries. The lockfile always records the fully qualified registry
URL; user-level aliases are never enough to reproduce a graph. Credentials come from
the OS credential store or environment and never appear in project files, logs, or
lockfiles.

Registry release records are immutable. An upload contains a normalized source
archive, package manifest, SHA-256 digest, licence data, and publisher signature.
Registry index metadata is signed and versioned; clients detect rollback and expired
metadata. Publication is two-phase—upload and verify, then atomically expose the
version—and an exposed coordinate/version can only be yanked, never replaced.

The protocol is static-HTTP/CDN friendly. Search is a separate convenience endpoint;
resolution reads owner/package version metadata and content-addressed archives.

The release archive is deterministic `tar.zst`: path order by UTF-8 bytes, zero
timestamps, uid and gid, regular files and directories only, modes `0644` or `0755`,
and one zstd frame with a content checksum. Absolute paths, `.`/`..`, symlinks, hard
links, device entries, case-folding collisions, and Windows reserved names are
rejected. The release digest hashes the archive bytes; the tree digest hashes, in path
order, each entry's path length and bytes, kind, normalized mode, content length, and
content bytes. Git and path sources are converted to this same logical tree before
hashing.

### Git

Git is a first-class manifest source, but pacman does not embed a second Git
implementation. It invokes a discovered `git` executable for Git dependencies, with
arguments passed directly rather than through a shell. `neper pacman info` reports
that capability. Registry and path dependencies require no Git installation.

Pacman maintains bare mirrors by normalized remote URL, fetches only the requested
ref/commit, resolves it to a full commit, rejects submodules, exports a canonical tree,
and stores that tree by SHA-256. SSH agent and credential behavior belongs to Git;
pacman never copies credentials into its cache.

### Paths

Path dependencies are read directly during local development. `sync --frozen` checks
their locked tree hash and fails when contents differ. `publish` rejects a graph
containing a path dependency. `neper pacman vendor` can replace a Git or registry
dependency with an explicit project-relative path for audited or air-gapped use.

## 7. Global immutable cache

The default package store is:

- Windows: `%LOCALAPPDATA%\neper\pacman\v1`
- Linux and macOS: `$XDG_CACHE_HOME/neper/pacman/v1`, or the platform cache directory
  when `XDG_CACHE_HOME` is absent

`NEPER_PACMAN_CACHE` overrides it for CI and containers. A Distrobox or Docker setup
mounts this directory as a cache volume; no project path is encoded within it.

Package trees live at `store/sha256/<digest>`, metadata at `metadata/<registry-id>`,
and Git mirrors at `git/<remote-hash>`. Store entries are read-only after an atomic
temporary-directory rename. Concurrent commands coordinate per digest, verify after a
contended install, and never expose partial content. A corrupt entry is quarantined,
not repaired in place.

The compiler receives a read-only virtual module map from package module names to
store files. It does not follow project-created symlinks and does not add arbitrary
source roots. Diagnostics and build manifests identify dependency files by package
coordinate plus root-relative path, never by a user-specific cache path.

`cache verify`, `cache list`, and `cache gc` are explicit. GC retains digests reached
from supplied lockfiles or younger than a chosen age; builds never trigger it.

## 8. CLI

```text
neper pacman init [--name NAME]
neper pacman add <package>[@constraint] [--registry NAME]
neper pacman add <package> --git URL (--ref REF|--tag TAG|--branch BRANCH|--rev COMMIT)
neper pacman add <package> --path PATH
neper pacman remove <label>
neper pacman resolve [--offline]
neper pacman sync [--frozen] [--offline]
neper pacman upgrade [label] [--offline]
neper pacman upgrade --major <label>
neper pacman build <target> [-- ARGS...]
neper pacman run <target> [-- ARGS...]
neper pacman task <name> [--allow CAP,...]
neper pacman vendor [label] [--into DIR]
neper pacman publish [--registry NAME]
neper pacman cache <verify|list|gc>
neper pacman info
```

`init` creates `project.yaml`, `src/`, and `.gitignore` entries for `.neper/`; it does
not create a lock until dependencies exist. `add`, `remove`, `resolve`, and `upgrade`
write both files through temporary files and atomically replace them only after the
whole graph validates.

`sync` installs exactly the lock. It fails if manifest and lock disagree; `--frozen`
also forbids path-tree changes and any metadata refresh. CI uses
`neper pacman sync --frozen`, followed by ordinary build/test commands. `--offline`
forbids all network access and reports every missing digest in one deterministic list.

The compiler never performs an implicit `sync`. If a locked digest is absent, build
fails with the exact pacman command needed to obtain it. This keeps builds hermetic
while making recovery obvious.

Every command supports the versioned `--json` stream conventions in
`docs/tooling.md`. Progress is human stderr only; JSON mode emits typed progress and
result records and leaves stderr empty under the same rules as other neper commands.

## 9. Tasks, not lifecycle hooks

Automatic dependency hooks are rejected. A transitive package must not run a shell,
Node.js, or neper program during `sync`, install, or an ordinary build: that would make
downloading code equivalent to executing it, mutate the global store, hide build
control flow, and make host tools part of an unrecorded dependency graph.

Pacman instead provides **root-project tasks**:

- Only the root `project.yaml` may declare a task. Dependency manifests cannot inject
  one into a consumer.
- A task runs only through `neper pacman task <name>` or when a root target explicitly
  lists it in `before`. `sync`, install, and direct compiler commands never run tasks.
- `command` is an argument array, never a shell string. Shell interpretation requires
  the explicit `shell` capability. A command executable must be project-relative and
  included in `inputs`, name a neper target built from the locked graph, or reference a
  `tools` entry with exact version and per-host SHA-256. Node and similar host tools
  therefore work, but never through an unrecorded PATH lookup.
- Inputs, outputs, executable identity, arguments, allowed environment variables, and
  granted capabilities enter the task hash. Outputs live under
  `.neper/generated/<task-hash>/` and are immutable inputs to compilation.
- An `.e` output's module name is its path below that generated directory. Pacman adds
  only the outputs declared by the selected target to the same read-only virtual
  module map as packages; duplicate project, package, or generated modules are an
  error before compilation.
- The default environment is empty except deterministic pacman variables; the working
  directory is a fresh scratch directory. Network, writable project files, shell,
  inherited environment, and processes beyond the named executable are denied unless
  individually declared and approved.
- The first interactive execution records capability approval in a user-local policy,
  never the lockfile. CI supplies explicit `--allow`; missing approval is an error, not
  a prompt.
- A task may use a neper executable that calls `e.proc`, but that grants no extra
  authority: the pacman sandbox still controls the child process.

There is no `post-install` hook. Generated code is a task output, and a package that
needs generated release sources publishes those sources in its immutable archive.

## 10. Publishing and trust

`publish` performs format, test, licence, provenance, and dependency checks before any
upload. It rejects dirty generated outputs, path dependencies, unpinned Git dependencies
in the publish graph, files outside the package root, secrets matched by the registry's
baseline scanner, duplicate module exports, and an archive whose normalized contents
do not reproduce its declared digest.

The publisher signs the release digest with an account-bound key. Registry metadata
uses separately rotated signing keys and a transparency log. The lockfile verifies
content independently of transport security. `neper pacman audit` is reserved for the
registry advisory protocol; M6 does not make vulnerability scanning part of compiler
correctness.

## 11. Failure, offline, and reproducibility rules

- Network failure cannot alter an existing lockfile or store entry.
- Resolution and installation diagnostics are deterministic and redact credentials.
- Interrupted writes leave only removable temporary data.
- `sync --frozen --offline` succeeds from a populated cache without DNS, Git, registry,
  home-directory configuration, or wall-clock access.
- A clean cache populated from the lock produces the same virtual module map and
  package hashes on every supported host.
- Package source hashes, manifests, task outputs, and the exact module map enter the
  compiler build manifest and incremental cache identity.
- Registry timestamps and signature expiry affect acquisition, not a fully offline
  build from already verified content. Explicit `cache verify` can enforce current
  trust policy before an audited release.

## 12. Implementation sequence and acceptance

Roadmap M6 is delivered in four internal stages. P0 and P1 may start after M2 while
GPU work proceeds; P2/P3 and the M6 completion gate require M4's mature platform and
dynamic-linking surface, but do not wait for M5's Metal backend:

1. **P0 — formats and resolver:** strict manifest parser, canonical lock writer,
   SemVer, PubGrub, conflict explanations, module-export validation, golden fixtures.
2. **P1 — local store:** path dependencies, immutable content-addressed cache, atomic
   concurrency, offline/frozen sync, virtual module map, build-manifest integration.
3. **P2 — remote acquisition:** signed registry metadata and archives, Git adapter,
   credentials, mirrors, publish/yank, cache verification and garbage collection.
4. **P3 — controlled generation:** task hashing, scratch execution, capability policy,
   generated-source maps, JSON records, and cross-platform sandbox tests.

M6 is complete when:

- a clean machine can populate its cache from `project.lock`, disconnect, and produce
  byte-identical package maps and compiler outputs under `--frozen --offline`;
- Windows, Linux, macOS, and a container produce a byte-identical lock for the same
  manifest and signed registry snapshot;
- mutable Git refs cannot change a locked sync;
- concurrent syncs neither duplicate nor expose partial store entries;
- a malicious transitive package cannot execute during resolution or installation;
- denied task capabilities fail before the task starts and declared outputs are
  byte-identical on all hosts on which that task claims portability;
- the multi-package workload GP-12 in `docs/general-purpose-verification.md` passes.

## 13. Explicit deferrals

Version 1 deliberately excludes optional feature unification, platform-specific lock
graphs, dependency plugins, dependency-provided hooks, Git submodules, binary package
installation, automatic native-library discovery, workspace/monorepo manifests,
federated identity, and a background daemon. Each adds hidden state or another graph;
none is required to make external neper source reproducible.
