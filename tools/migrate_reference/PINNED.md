# Petcow migrate pin

- Upstream: D:/repos/petcow, commit d26e2034
- Source: src/migrate.rs (lines 1..2570, before `#[cfg(test)]`), plus error.rs,
  naming.rs and a minimal ModuleSource (parse / looks_like_git / split_subdir).
- Build (offline; the cached registry is enough):
  $env:CARGO_HOME='D:\cargo-home'; $env:CARGO_TARGET_DIR='D:\repos\neper\build\migrate-reference-target'
  cargo build --release --offline --manifest-path tools/migrate_reference/Cargo.toml
- Consumer: scripts/migrate_reference.py <built exe>
- Protocol: `MODE FILE PROJECT`; prints `migrated: N`, `warning: ...`, `---`, YAML;
  `error:` on stderr with exit 1.
- Licence: company project; keep in-repo.
