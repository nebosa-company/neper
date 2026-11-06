# Pinned oracle sources

These are copies of the sibling projects whose behaviour the `e.*` ports must match.
They exist so fixture regeneration is **self-contained**: no checkout of another repo,
no `file:///D:/...` paths, no network.

| directory | upstream | pinned commit | used by |
|---|---|---|---|
| `vaper/` | D:/repos/vaper (`packages/vaper_engine_core/lib/src/net/`) | `e874cad5076131095204cb84294be26cc7e7a0d3` | `scripts/policy_vectors.mjs`, `scripts/policy_reference.dart` → `net_policy` |
| `appdor/` | D:/repos/appdor (`src/`, the workflow runtime's import closure) | `417009d97` | `scripts/workflow_reference.mjs` → `algo_workflow` |

`tools/migrate_reference/` is the petcow oracle: a small standalone crate built from
petcow's `src/migrate.rs` (commit `d26e2034`) with its
`error.rs`, `naming.rs` and a minimal module source. It is built with
`cargo build --release --offline` and consumed by `scripts/migrate_reference.py`.

## Regenerating

```powershell
# net_policy (Dart; the SDK's direct binary, not the flutter wrapper)
$env:DART='D:/flutter/bin/cache/dart-sdk/bin/dart.exe'
$env:DART_SUPPRESS_ANALYTICS='true'
node scripts/policy_vectors.mjs

# algo_workflow (node only)
node scripts/workflow_reference.mjs

# x_migrate (rust shim, then python)
cargo build --release --offline --manifest-path tools/migrate_reference/Cargo.toml
python scripts/migrate_reference.py tools/migrate_reference/target/release/migrate_reference.exe
```

The generated answer vectors are the reference; the fixture templates
(`scripts/*_fixture_template.e`, `scripts/net_policy_fixture_template.e`) hold the
hand-written assertions and must be kept consistent with the pinned oracle.

## Updating a pin

Copy the upstream files again, run the generator, and review the fixture diff as a
semantic change to the port — never hand-edit the generated vectors. Licence status:
`vaper` carries no explicit licence file upstream; `appdor`/`petcow` are company
projects. Do not publish these copies outside the repository until that is settled.
