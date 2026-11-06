# Handover: the non-browser issue campaign (2026-11-07)

For whoever picks this up. Read `AGENTS.md`/`CLAUDE.md` first. This file is the state of
the campaign that closed every GitHub issue outside the Browser CSS session's territory,
what was measured, and the traps — not a replacement for the standing rules.

## Standing goal and where it ended

`/goal continue closing issues that do not affect the other browser session "Browser CSS Gaps"`. The goal is
complete as of this session: **124 open issues remain and every one is `area:web`** — the Browser CSS session's
queue (`lib/e/fmt/css/*`, `lib/e/web/*`, `lib/e/net/fetch.e`, site CSS). No non-browser issue is queued,
blocked-on-us, or closeable from this side.

Labels were normalised on the way out: the CSS-engine and fetch issues that were labelled
`area:fmt`/`area:other`/`area:net` now carry `area:web` (36 issues relabelled), so a label filter matches reality.

## What landed in this campaign (last stretch)

| commits | result |
|---|---|
| `76dcba220` | CPU-features ABI threaded through `sha256_blocks`/`crc32c_bytes` and **every** runtime blob (ELF x64/a64, PE, neperos, none, macOS); bootstrap rebuilt in two stages (#28) |
| `899d512e2` | aarch64 runtime symbols 4-aligned, embed script now refuses misaligned symbols (#1637) |
| `f254922fb` | macOS runtimes assembled as ELF objects (Mach-O target truncated the blob at 240 bytes) (#1638) |
| `8bc553cd7` | inline oracle sizes its defer table from the candidate's span (`gpu_barrier_chain` green, debug and release) |
| `ae2d5a53f`, `b30813e41` | negated signed literal validated at its negative value and folded in lowering (`-2147483648i32` works; `fmt_protobuf`, `simd_lanes`) |
| `c649f94a6` | `e.net.policy` migrated to the pinned Vaper jar (`#900`): default cookie path `/`, no public-suffix list, SameSite Lax/Strict on top-level only, CHIPS partition rule, path-limited filter rules out of `domains`; vectors regenerated |
| `8e5b5655a` | `#205`/`#55` landed against regenerated references: Appdor budget N-for-N + `case:<n>` journaling, Petcow Puppet skip-one; `lib/e/algo/workflow.e` and `lib/x/migrate/migrate.e` mirror them |
| `6d734908d` | oracle sources pinned in-repo: `tests/oracles/vaper/net/`, `tests/oracles/appdor/src/…`, `tools/migrate_reference/`; generators are self-contained (ADR **D5964**) |
| earlier rounds | `#289` input cap, `#257` (27 items: mail vault, wsc accept/random mask), `#202` window/table/stack reclaim, `#213` air-fixture, `#32` PE runtime, `#262` aarch64 kernel runtime, `#178`/`#179`/`#515`/`#516`/`#512`/`#513`/`#380`/`#388`/`#389`/`#438`/`#208`/`#290`/`#301`/`#302`/`#293`/`#292`, `#869` gRPC trailers-only commit, `#319`/`#329` site |

Open count went from 688 at the campaign start to **124**.

## Upstream repositories (the test oracles)

- `nebosa-company/appdor` — `main` is `f24389d8f` (budget/journal fix, pushed).
- `oboobortot/petcow` — `main` is `e6811e19` (Puppet resync, pushed with the `gaddlord` account; the default
  `nebosa-company` account gets a 404 on this private repo). A patch copy is `build/petcow-e6811e19.patch`.
- `nebosa-company/vaper` — pinned at `e874cad5076`; not modified.
- `tests/oracles/README.md` carries the pins and the exact regeneration commands (Dart via
  `D:/flutter/bin/cache/dart-sdk/bin/dart.exe` with `APPDATA`/`LOCALAPPDATA`/`USERPROFILE` under `build/` to keep
  analytics inside the workspace; node; offline cargo with `CARGO_HOME=D:\cargo-home`).

Rule: generated fixture vectors are never hand-edited. Change the oracle → regenerate → land the neper side in
the same commit. The template files (`scripts/*_fixture_template.e`, `scripts/net_policy_fixture_template.e`)
are hand-written asserts and must follow the oracle when its semantics move.

## Verification in this environment

- Compiler work: clear `.neper`, `neper-try build src/main.e` twice, `neper-try self-test`, `check-file` per target.
- Fixtures: `emit-executable <fixture>/src/main.e . x64 windows OUT --gpu glsl` then run; the fresh compiler
  matters for compiler-side fixes (the prebuilt `neper-try` embeds the old compiler).
- Not runnable here: NeperOS QEMU boots, aarch64/macOS execution, Vulkan/CUDA devices, the full self-host suite
  (WSL denied). Those claims are stated as inspection-only in the issues.
- Python is `D:\tools\python312\python.exe` (the generators need it); Node is on PATH; Lighthouse installs into
  `build/lh` and runs with `CHROME_PATH=D:\tools\chrome-win64\chrome.exe` (PSI API is not reachable).

## Site work that closed with the campaign

- `#319`: DNS `google-site-verification` TXT live for neper.dev, Bing `msvalidate.01` meta deployed
  (`45f71bea9`), homepage indexed and first for "Neper programming language LLM" in Bing/DDG, sitemap served.
- `#329`: 19 pages load `bundle.css` non-blocking (`media="print" onload` + `<noscript>`; `036c2c077`,
  sitemap `d76b115cf`). Lighthouse 13.6.0 mobile: FCP/LCP 1.9 s → 1.0–1.1 s, render-blocking audit fail → pass,
  locally and on the live site.

## Traps

- The working tree is shared. Stage only touched paths; the Browser CSS session's files are
  `lib/e/fmt/css/*`, `lib/e/web/*`, `lib/e/net/fetch.e`, `lib/e/net/tls/hoststore*.e`, `examples/browser/main.e`,
  `tests/browser/wpt/*`, `tests/selfhost/fixtures/link/net_fetch`, `scripts/page_fixture_template.e`.
- `docs/decisions.md` is edited by several sessions; append a `## D<n> —` entry and regenerate
  `docs/digest/decisions.tsv` with `scripts/render_digest.py`. Do not stage other sessions' hunks.
- `docs/` is the published site: any HTML change needs `node scripts/render_sitemap.mjs` and
  `python scripts/seo_lint.py`, and the docs-seo gate fails on a stale sitemap. Commit the pages, then regenerate
  the sitemap in a second commit (lastmod comes from `git log -1 -- date`, i.e. the *committed* date).
- GitHub Pages deployments lag and get cancelled when another commit lands; the `pages-build-deployment` run for
  the newest commit is the one to watch, not the `pages/builds` API entries.
- Two GitHub logins are on this machine: `nebosa-company` (default) and `gaddlord` (has `oboobortot/petcow`);
  use `gh auth token --user gaddlord` with an HTTPS `extraheader` for that repo.
- `git fetch origin` before committing: the browser session pushes often, and a missing fetch looks like a
  non-fast-forward push failure.
