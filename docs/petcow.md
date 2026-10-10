# petcow → neper migration plan

Status: plan. Source: `d:\repos\petcow` (Rust, v0.343.0). Target: neper `lib/e` (pure stdlib), `lib/x` (drivers), tools (importers).

Rule: pure + deterministic + fixture-testable → `e.*`; socket/credential/platform → `x.*`; app workflow → tool/recipe, never `e.*`. No new third-party deps, no hand-rolled crypto, no gRPC bridge in the library. `docs/progress.html` stays the only readiness record; this file is the work plan.

## 0. Ground rules

- Fenced modules, arena-first allocating calls, `snake_case`, per-module fixtures (`tests/` + goldens). Every port carries petcow's test vectors forward.
- Self-host constraint: portable Neper first; hardware intrinsics (AES, SHA, CRC) only behind the existing link-gated pattern (cf. C098, D336). The C bootstrap still builds stage 1 (T021), so avoid constructs it rejects until C088 lands.
- Honest migration: untranslatable input warns, never silently drops (petcow `src/migrate.rs:1` FR-12 discipline).

## 1. Algo (pure, port first)

| # | petcow source | neper home | Notes / acceptance |
|---|---|---|---|
| A1 | `src/interp.rs:499` CIDR: `cidrsubnet`, `cidrhost`, `cidrsubnets` | `e.net` CIDR math (new fns, no new module) | IPv4 prefix arithmetic, pure. Fixtures: TF subnet vectors + edge (hostnum OOB, prefix len 0/32). Biggest net gap. |
| A2 | `src/interp.rs:499` strings: `substr` (neg-len), `chomp/indent/trimprefix/suffix`, `basename/dirname` (slash-pure), `title/strrev/startswith/endswith/strcontains` | `e.text.*` extensions | Keep slash-pure `basename/dirname` semantics (`src/interp.rs:791`). Fixtures per fn incl. unicode chars (not bytes). |
| A3 | `src/interp.rs:499` collections: `flatten/distinct/matchkeys/zipmap/transpose/setproduct/one/element/range/slice/compact/sum/product/min/max/pow/log/signum/parseint` | `e.algo.*` + `e.text.template` where string-shaped | `range` keeps the 1M-element cap (`src/interp.rs:1091`); `log` fails on non-finite; `parseint` base 2–36. Fixtures incl. error cases. |
| A4 | `src/interp.rs:499` encodings: `base64encode/decode`, `textencodebase64` (UTF-8-only), `urlencode`, `jsonencode/decode`, `yamlencode/decode`, `csvdecode` | thin wrappers over existing `e.fmt.{json,yaml,csv}`, `e.crypto.hash` | `require_utf8_encoding` stays fail-closed (`src/interp.rs:477`). No new codec code. |
| A5 | `src/engine/order.rs:16` `topo_order` (Kahn, `for_each[..]` expansion, `logical_id` tie-break, cycle error) | `e.algo.graph.path` or `e.algo.schedule` | Verbatim-portable (~110 lines). Fixtures: linear, diamond, deterministic order, cycle, unknown dep, `for_each` set. |
| A6 | `src/scan.rs:50,398` `stable_id` (FNV-1a hex) + `merge_owned` (preserve `accepted`, auto-`fixed`, owner-tool namespace) | `e.algo.hash` + recipe for `e.valid`/`e.algo.check` | Idempotent reconciliation pattern for any lint/scan integration. Fixtures from `src/scan.rs:589` tests. |
| A7 | `src/currency.rs:341,248` `version_at_least` (numeric dotted, prerelease rule) + `days_from_civil` | extend `e.fmt.semver` + `e.time.calendar` | Lexical compare is the bug (`"10.2" < "9.6"`); fixtures from `src/currency.rs:373`. |
| A8 | `src/spartan/filter.rs,predicate.rs,eval.rs` value-rule subset | `e.algo.query` / `e.valid` | Predicates only; not the full policy engine. Native rules (`src/spartan/builtin.rs`, `src/scan.rs:83`) become fixture rows. |
| A9 | `src/facts.rs:88` `parse_facts`, `src/inventory.rs:88,133` `resolve/select/synthesize_hosts` | driver helpers under future `x.ops`, not `e` | Pure but app-shaped; port when the ssh/ssm driver lands. |
| — | `src/cm.rs:615,1020` `compile/compile_check`, `FACT_SCRIPT`, `UPDATE_PROBE_SCRIPT` | recipe text, not stdlib | Keep as versioned script fixtures for drivers to serve. |
| — | `src/parallel.rs`, `reactor/beacon/heartbeat`, `os_eol`, currency probes | skip | Covered by `e.thread.pool`/`e.task`, or app data/ops. |

Order: A5 → A1 → A7 → A2/A3/A4 → A6 → A8 → A9.

## 2. Formats (fill two gaps, wrap the rest as tools)

Neper already has `e.fmt.{json,yaml,csv,xml,ini,toml,zip,tar,gzip,msgpack,protobuf,…}` — no re-import.

| # | petcow source | neper home | Notes / acceptance |
|---|---|---|---|
| F1 | HCL via `hcl-rs` (`Cargo.toml:47`, `src/migrate.rs:58` `migrate_hcl`, `render_expr`, `migrate_dynamic`, `migrate_lifecycle`) | new `e.fmt.hcl` (read-only first) or `e.parse.hcl` | TF-import story. Scope: `resource/variable/locals/data/output/provider/module`, `count/for_each/depends_on/lifecycle/dynam

ic`, `${…}`→template mapping. Warn on registry sources, splats, `self/path/terraform` refs. Golden round-trips from `src/migrate.rs:2583` tests. |
| F2 | `src/scan.rs:226,278` `parse_checkov_json`, `parse_semgrep_json`, `map_external` | `x.lint` helpers (not core `e`) | Lenient severity parse, hint→resource substring map. Fixtures from `src/scan.rs:1031` tests. |
| F3 | `src/diagram.rs:11` `to_mermaid` (+ `finding_to_value/inject_findings`, `src/scan.rs:489,542`) | `e.fmt.mermaid` emitter (or tool-side) | `flowchart TD`, dep→dependent edges, `blocked` class only for blocking findings, empty-graph case. Goldens from `src/diagram.rs:78` tests. |
| F4 | `src/migrate.rs:1013,1414,1816,2193` `migrate_ansible/salt/puppet/chef` + `ansible_task_to_resource`, `salt_state_to_resource`, `lex_puppet/puppet_resource`, `parse_chef_header/chef_resource` | `x.migrate.*` tools | Mapping tables only; keep warn-instead-of-drop. Cross-matrix fixture: pip/pkg/service/user/group/cron/file/symlink across all four (cf. `src/migrate.rs:3238` test). |
| — | `src/vault.rs:1` `PETCOW_VAULT;v1;hex(salt‖nonce‖ct)` | rule only | Design (Argon2id + ChaCha20-Poly1305, random salt/nonce, fail-closed) maps onto existing `e.crypto.kdf/aead`. No new format. |
| — | tfplugin protobuf wire, zip | skip | Have zip/protobuf; wire format stays out of the library. |

F4 landed (D2318): `x.migrate.migrate` (`lib/x/migrate/migrate.e`), differential against the reference importers over 372 cases.

Order: F1 → F2/F3 → F4.

## 3. Drivers (shape first, one REST pattern, defer the fleet)

| # | petcow source | neper home | Notes / acceptance |
|---|---|---|---|
| D1 | `src/provider/mod.rs:122,214` `Provider` trait (`read/read_scoped/create/update/delete/discover/discover_scoped/discover_unmanaged`, `parent_link`) + `Registry` + alias key + `source_of/resolve` precedence | shape for future `x.cloud.*` (mirrors `e.db` driver contract) | Adopt the shape, not the code. `is_managed` prefix guard (`mod.rs:82`) and fail-closed unknown-dep/cycle errors ride along. |
| D2 | `src/provider/declarative.rs,manifest.rs,http.rs` + `DECLARATIVE_CLOUDS` (`mod.rs:41`) + `ParentLink` (`mod.rs:97`: name- vs id-addressed parents) | `x.cloud` declarative REST core | Highest leverage: GCP/Azure/Aliyun/IBM/OCI via manifest data (`list_url/item_url`, `{parent}` scoping) over existing `e.net.http/tls`. Fixture: file-backed fake HTTP, parent-by-id vs by-name negative controls. |
| D3 | `src/provider/k8s/mod.rs` `petcow.io/managed` label convention; `src/provider/aws/cloudcontrol.rs` uniform CRUD; `s3.rs,ec2.rs,iam.rs`; `lightsail.rs` (non-CF gap) | `x.cloud.aws`, `x.cloud.k8s` (subset) | k8s labels + CloudControl pattern first; S3/EC2/IAM subset as reference drivers. Labels stay `petcow.io/*` (cf. `src/lib.rs:359` gate) — renaming orphans live objects. |
| D4 | `src/transport/ssh.rs` (+ `mod.rs:54` `Transport` trait, `PerHostTransport` lazy-per-kind + host-naming errors) | new `x.ssh` | Only real transport gap (neper has no ssh). `local` stays `e.proc`/`e.os.shell`; `ssm`→`x.cloud.aws`, `winrm`→platform-specific. Per-host select + lazy build is the pattern to keep. |
| — | `src/provider/tfbridge/` (tonic/prost/rmpv/rcgen, `Cargo.toml:68`) | never in library | gRPC + msgpack + go-plugin mTLS contradicts self-hosted minimal deps. Interop via CLI process boundary only. Document as anti-pattern for `e`. |
| — | full AWS/GCP/Azure fleet (~300-row catalog, only ~15 real in petcow) | defer | One declarative driver + one reference cloud proves the pattern; breadth follows demand. |

Order: D1 (trait shape, doc-only) → D2 (fake-HTTP declarative core) → D4 (`x.ssh`) → D3 (k8s labels + one AWS reference type).

## 4. Explicitly out of scope

tfbridge gRPC bridge; full multi-cloud fleet parity; `transport/ssm,winrm` in core; `cm` script bodies as library APIs; `facts`/`currency` probe scripts as stdlib; `reactor/beacon/heartbeat/exec` ops runtime; `os_eol`/baseline data files; checkov/semgrep binaries themselves.

## 5. Acceptance per landing

- Fixture-driven goldens in-repo (inputs + expected outputs, incl. error/warn cases named above); deterministic byte-equal reruns; Linux + Windows where shell/platform matters (cf. `facts.rs:113` CRLF control).
- No `unsafe`, no new native deps, no network in `e.*` tests (fake transports/HTTP only).
- Docs: module API rows in `docs/module-apis.md` + `docs/modules.json` surface flags; this plan file tracks intent, `docs/progress.html` (generated) tracks readiness.
