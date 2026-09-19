# Neper tooling protocol — version 2 draft

Status: scheduled, non-normative design input. This document defines requirements
for the future tooling-v2 schema and conformance corpus. It does not modify the
closed version-1 protocol, advertise implemented commands or block unrelated
compiler/backend milestones. [`tooling.md`](tooling.md) remains authoritative for
version 1 until a frozen successor explicitly replaces it.
[`hardening-tracks.json`](hardening-tracks.json) is authoritative for slice ownership
and status; this draft owns only the planned interchange semantics.

Ownership is part of the contract. The compiler/tool service owns parsing, semantic
facts, snapshots, edit/check/test plans and canonical evidence results. The trusted
host owns the final verification decision and receipt, policy grants, credentials, OS
sandboxing, worktree/process isolation, observed effects and durable task storage. E2
owns comparative measurements and claims. This
draft specifies their versioned interchange; a compiler-emitted annotation never
claims that the host enforced it.

The post-M2 T2 work in
[`post-m2-llm-hardening.md`](post-m2-llm-hardening.md) specifies planned semantic
context queries, causal diagnostics, snapshot-bound edits and analysis-completeness
reporting. These are future requirements, not additions to the closed v1 protocol
or currently advertised commands. Their implementation must version the affected
schemas, capability records and compatibility identities before the tooling-v2 conformance gate closes.

H30–H44 require that versioned successor to expose one coherent agent
workflow rather than a collection of merely JSON-capable commands. The v2 design must
include all of the following before implementation is accepted:

- syntax, affected-semantic and workspace check scopes over the same immutable
  overlay snapshot, without code generation or linking;
- diagnostic IDs and causal relationships, role-labelled related spans, typed fields,
  position-independent fingerprints, applicability-classified repair hints, compact
  root-cause views and content-addressed complete-result retrieval without
  re-execution;
- on-demand repair plans separated from diagnostic hints, with transactional edits,
  complete preconditions, effect-labelled tool actions and mandatory verification;
- exact, module, affected-set and full-suite test plans with selection completeness,
  executed-versus-cached provenance, constant-size all-pass summaries, normalized
  failure kinds and retrievable large output;
- per-command byte/token accounting and default budgets covering source guidance,
  context, diagnostics, tests, recovery and verification, not source spelling alone;
- one final snapshot-bound verification record whose state is exactly `verified`,
  `failed`, `incomplete` or `cancelled`, with every requested, cached, skipped,
  omitted and unproved obligation represented, plus a content-addressed verification
  receipt that can be checked without trusting prose; and
- a capability handshake for the canonical snapshot/context/edit/format/check/test/
  verify loop. Batch is required. T2 freezes an absolute warm-latency, startup and
  resource budget before implementation; a bounded cancellable retained session is
  required only if finite batch requests cannot meet that budget. E2 rankings cannot
  add a T2 completion condition. Both transports use identical semantic results.

### Planned v2 correlation, repair, effect and receipt contract

These four requirements are fixed inputs to the v2 schema design. Field ordering and
additional representation details remain schema work; an implementation cannot omit
or weaken the semantics below.

**Diagnostic fingerprints.** A diagnostic has both `id`, unique only within one
result, and `fingerprint`, an opaque `sha256:` identity for correlating the same fault
across invocations after offset-only edits. The fingerprint algorithm is versioned
and uses the registered diagnostic code, source identity, resolved semantic subject
when available, syntax/token kind, normalized content anchor and target/generic
identity where relevant. It excludes message prose, line, column and byte offsets.
The same fault against equivalent anchored content must reproduce the fingerprint;
a changed semantic subject or anchored content must not be assumed to retain it.
Fingerprints are correlation hints, never snapshot identity, edit preconditions or
proof that two diagnostics are semantically identical.

**Repair hint and plan separation.** A diagnostic's default compact view carries
zero or more `repair_hints`, not full edits. Each hint has a stable namespaced
`repair_id`, title, applicability (`machine`, `review`, `placeholders` or
`unspecified`), safety (`automatic`, `review_required`, `dangerous` or `unsupported`)
and `requires_context`. A separate snapshot-bound repair-plan query resolves a chosen
hint. Its result has status `available`, `partial`, `ambiguous`, `unsafe` or
`unavailable`; identifies the target diagnostic ID and fingerprint; and contains the
minimal H29 actions, all preconditions, effects and verification obligations. A plan
with no executable verification is `partial`, never fully available. Applying a plan
is a separate transactional operation and always produces a new snapshot or no
workspace mutation.

**Effect-labelled actions.** Every repair-plan action declares `effects`, even when
the array is empty. Every command action additionally uses an argument vector rather
than a shell string and declares its working directory. The closed core effect kinds
are `workspace_read`, `workspace_write`, `outside_workspace_write`,
`execute_project_code`, `dependency_change`, `network`, `credential`, `vcs` and
`external_service`; extensions require a namespaced kind. Each effect carries its
scope, safety, reason and supporting evidence when known. Build and test commands
that can execute project code say so. Secret values never enter a plan. A consumer
refuses automatic execution when required capabilities or policy are absent, and
`dangerous`/`unsupported` actions can never be disguised as machine-applicable edits.
Applicability describes whether an edit is mechanically complete; safety separately
describes what executing it may affect.

**Verification receipts.** A terminal verification result can be persisted as a
canonical `neper-verification-receipt` artifact. Its proof core contains the exact
snapshot, compiler/language/grammar/tool-stream identities, target/profile/options,
requested obligations, executed or exactly cached check/test evidence, result
references and hashes, unsafe-inventory hash, omissions, skipped and unproved items,
and terminal state. `verified` is legal only when every required obligation has
passing evidence, every referenced artifact validates, and the T2.3 trusted host has
bound enforced policy, environment and H40 coverage evidence. A T2.2-only package is
`incomplete`, never `verified`. The state always means verified for the named
contract, snapshot, policy and environment, not universally correct.
The receipt is itself
content-addressed and has a read-only verifier that checks schema, hashes, identities
and internal claims without rerunning compilation. Timing, host observations and
timestamps live outside the deterministic proof core. Subjective confidence,
self-declared authorship and review labels are not verification evidence; a future
external signed-attestation extension may carry them without changing the receipt's
meaning.

### Planned v2 operational trust contracts

H35–H44 extend the same v2 family; they are not optional sidecar conventions:

The reference implementation is the `neper-agent-host` executable planned under
`tools/neper-agent-host/`. It owns H36/H37/H40 and final H34 verification in T2.3,
then H38/H44 integration and durable operation in T2.4. The compiler/tool service
emits facts, plans and evidence but cannot self-assert that host policy was enforced.

- A canonical external `neper-change-contract` binds base snapshot, inert objective
  provenance, permitted scope, forbidden effects, executable acceptance obligations
  and required verification tier. Plans, tasks, bundles and receipts name its content
  hash; an unproved required obligation makes completion `incomplete`.
- A trusted executor applies a versioned default-deny policy to action effects and
  scopes. It validates resolved paths/arguments and scoped approvals, constrains or
  observes actual effects, records declared/granted/denied/observed differences and
  never persists credential values. Effect annotations alone grant no authority.
- Every executing operation names an environment manifest and status `hermetic`,
  `observed` or `uncontrolled`, covering tool hashes, platform, dependency lock,
  roots, environment allowlist, locale/timezone, time/random/network policy, limits
  and external services. Relevant inputs enter cache and receipt identity.
- A change bundle carries base/result snapshots, typed edits, changed semantic
  identities, effects, contract and receipt. Integrating parallel bundles detects
  textual and semantic conflicts, produces a new snapshot and revalidates the
  combined result; receipts never compose by assertion.
- Test attempts preserve seed/order/shard/environment and use a distinct `flaky`
  aggregate. Retry and quarantine cannot turn a flaky required obligation into a
  verified pass.
- An obligation graph maps requested behavior and inferred safety, compatibility and
  performance risks to accepted evidence with `covered`, `uncovered`, `inapplicable`
  or `unknown` status. Test-selection completeness is not evidence adequacy.
- Runtime results normalize setup/build failure, returned error, trap, signal or
  exception, abnormal exit, timeout, resource limit, cancellation and success, with
  bounded source-mapped frames and retrievable process evidence.
- API comparison classifies source, ABI, behavioral-contract and serialization
  compatibility independently and yields structured migration plans only when they
  are complete and preconditioned.
- Benchmark obligations bind baseline/workload/environment, metric, threshold and
  pre-registered statistical decision and return `pass`, `regression`, `inconclusive`
  or `invalid` with raw evidence by reference.
- Long operations may use an unguessable authorized task handle with durable queued,
  running, `input_required`, cancelling and terminal state, structured approvals,
  cooperative cancellation, expiry and one canonical H34 result across reconnects.

H45 later exports the unchanged native receipt and its source, environment,
dependency and artifact identities into standards-based release provenance. Signing
and external trust policy wrap native evidence; they never strengthen it or change
the meaning of an existing receipt.

The exact v2 field schema remains a tooling-v2 design output and must receive its own JSON
Schema and conformance corpus. These requirements do not reinterpret v1 `test`,
`diagnostic` or `result` records. In particular, v1's per-test pass records and inline
captured output remain v1 behavior until the advertised v2 profile is selected.

The planned device-selection surface in
[spec §10](spec.md#device-discovery-and-selection) also requires a versioned runtime
inventory/report contract under H18/H21, implemented with the backend in M3
(CUDA in M4). It is **not** an extra field or command in the closed v1 stream.
The revised contract must expose:

- Requested backend/index or exact selector separately from the actual opened
  `DeviceInfo`; failed requests have no fabricated selected-device record.
- Canonical backend-prefixed UUID text, explicit key validity, display name, kind,
  capacity/known flag, capabilities and floor support. Encode `u64` capacities
  without losing JSON precision. CPU and Vulkan software devices are not labeled
  hardware GPU executions. Driver names are inert data, not harness instructions.
- Inventory observation identity and completeness, limits/errors, and explicit
  selection/fallback decisions made by the application. An inventory snapshot is
  not a reservation or the same thing as a compiler workspace snapshot.
- Distinct missing, ambiguous, unsupported, resource-exhausted and lost outcomes;
  indices never masquerade as persistent keys. Revalidate exact keys at open.

Hardware inventory is a runtime observation, not part of deterministic source
compilation or a reason for ordinary `check` to probe drivers. Device-specific
pipeline caches use H22's device/driver/options identity, not the selection UUID
alone. Freeze exact record schemas and capability advertisement before tooling-v2 conformance; only
advertise discovery when implemented. No compiler-wide automatic GPU-selection
environment variable or unversioned `neper info` extension is introduced here.

## Installed-library capability inventory

H11/H18 also require the installed-library capability inventory in
[`stdlib-hardening.md`](stdlib-hardening.md). The module-plan `surface`, tier and
milestone describe design/commitment, not current availability. The new versioned
inventory binds compiler/language/target, qualified symbol/signature hash, canonical
import/alias, implementation status, stability, ownership/allocation/failure contracts
and test provenance. Planned-only records must never be returned as callable APIs.
Freeze and validate its schema in T2 rather than adding undocumented fields to
closed v1 `info` records. Static docs checks cannot manufacture implementation or
execution evidence.
