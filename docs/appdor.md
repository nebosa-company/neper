# appdor → neper migration plan

Status: plan. Source: `d:\repos\appdor` (JS SPA + Supabase stack, v1.30.0). Almost all `src/*` cores are dependency-free pure modules; I/O lives in `services/` workers and `supabase/` SQL. Target: neper `lib/e` (pure stdlib), `lib/x` (drivers), tools and services.

Rule: pure + deterministic + fixture-testable → `e.*`; socket/credential/platform → `x.*`; app workflow and service wiring → tool/service, never `e.*`. SQL stays portable Postgres (no Supabase-only constructs in ported logic). No browser/DOM code in `e.*`. `docs/progress.html` stays the only readiness record; this file is the work plan.

## 0. Ground rules

- Fenced modules, arena-first allocating calls, `snake_case`, per-module fixtures. Every port carries appdor's per-file Jest suites forward as vectors.
- Count drifts flagged, not silently adopted: formula functions measured 279 vs documented 184–193; field types measured 90 vs documented 62. Recount on landing.
- Unread files stay flagged: `materialize/backfill/host-query`, `coerce/conversion/settings-schema`, `views.js`, `registry/data-table/widgets`, PAT persistence tail, NDJSON parser (not located). Port only what was read.

## 1. Algo (port the pure cores)

| # | appdor source | neper home | Backlog | Notes / acceptance |
|---|---|---|---|---|
| A1 | `src/formula/tokenizer.js,parser.js` (10k maxNodes), `evaluator.js` (errors-as-values, lazy IF/LET/MAP, 2M maxSteps, cycle DFS+topo), `registry.js` (aliasing, volatility/pushdown flags) | `e.algo.formula` | L026 | Pure, dep-free. Fixtures: engine, cycles, validate suites. |
| A2 | `src/formula/{logical,information,math,text,datetime,convertion,random-hash-encode,array,lookup,reference,extraction,finance}.js` + LET/LETS | `e.math` / `e.text` / `e.time` / `e.fmt` / `e.data` | L027 | Per-category vectors; keep arity checks and error pass-through. |
| A3 | `src/formula/compat/dialects.js` (7 RAW tables) + `translate/detectDialect/translateBatch` with converted/warnings/failed outcomes | `e.algo.transpile` | L028 | Data-not-code is the point. |
| A4 | `src/formula/sql-compiler.js` (AST → parameterized `$N` Postgres) + `pushdown.js` (full/partial/none) | `e.algo.sql` / `e.db.query` | L029 | Direct fit for `e.db`; sql-conformance fixtures. |
| A5 | `src/fields/specialized.js,barcode.js,nace.js` (IBAN mod97, Luhn, ISBN, EAN, ISIN, VIN, Verhoeff, GS1, Code39-mod43, NACE table) | `e.algo.checksum` + `e.data.validate` | L030 | Best candidates; all pure and tested. |
| A6 | `src/validation/validators.js,index.js,conditional.js,bulk.js` | `e.data.validate` | L031 | Keep hidden-skip, intra-batch uniqueness, non-constraining suggestions. |
| A7 | `src/views/query.js`, `grid/multi-sort.js,filter-tree.js`, `pivot/index.js`, `charts/aggregate.js,server-aggregate.js` | `e.algo.sort/filter/group/agg/pivot` | L032 | Stable empty-last sorts, topN-Other, reason-coded server refusal. |
| A8 | `grid-ops/records-engine.js` (keyset paginate, key minter), `virtual-rows.js`, `performance/limits.js`, `bulk.js`, `undo-redo.js` | `e.algo.page/window/batch/undo` | L033 | Cursor + truncation-plan fixtures. |
| A9 | `src/search/index.js,indexing-pipeline.js` (weighted AND scoring, trim-before-rank, idempotent outbox, dead letters) | `e.algo.search/queue` | L034 | Client/server plan threshold fixture. |
| A10 | `src/scheduling/{index,dependencies,working-calendar}.js`, `src/workflow/schedule.js` (5-field cron + TZ, catch-up, single-concurrency) | `e.algo.sched` + `e.time.cron/calendar` | L035 | Extends experimental `e.time.cron`. |
| A11 | `src/workflow/runtime.js,flow-engine.js`, `src/workflows/definition.js,guard.js` (journal replay, fork-join, idempotent retry, FSM validate, optimistic version) | `e.algo.workflow/fsm/dag` | L036 | Store/effects stay injected. |
| A12 | `src/offline/*`, `src/sync/*`, `src/history/*`, `src/realtime/index.js` (coalescing queue, cursor pull, LWW/field-merge, durable queue, revision replay, sha256 chains, presence) | `e.algo.sync/merge/queue/diff/chain/presence` | L037 | Polling transport flagged, not ported. |
| — | `automations/run-steps.js` (UI helper), DOM/virtual-row mounting, dashboard widgets | skip | — | — |

Order: A1 → A4 → A5 → A2/A3 → A6/A7/A8/A9 → A10/A11 → A12.

## 2. Formats (decode + envelopes; containers already covered)

Neper covers csv/json/yaml/xml/ini/toml/zip/html/markdown/protobuf/msgpack.

| # | appdor source | neper home | Backlog | Notes / acceptance |
|---|---|---|---|---|
| F1 | `src/io/xlsx.js` (dep-free `sheetToTable`) + `src/importers/{monday,airtable,quickbase,more-sources}.js` type maps + fidelity report | `e.fmt.xlsx` decode + `x.migrate` data | L044 | Top port; export-xlsx stays out (upstream LC gap). |
| F2 | `src/identity/jose.js` (BigInt RS256 verify-only; neper `jwt.e` lacks RS256), `oidc.js` (discovery parse), `saml.js+xml.js` (validate + C14N subset), `scim-protocol.js` (filter/PATCH grammar) | `e.crypto.sign` + `e.fmt.*` | L045 | Zero npm; host I/O on `e.net.http/tls/dns`. SAML C14N coverage in `xml.e` unverified — check on landing. |
| — | CSV hardening (BOM, `neutralizeFormula`, delimiter detect) | deltas over `e.fmt.csv` | — | Port only what `csv.e` lacks (unverified). |
| — | App JSON envelope, templates, workflow IR, audit taxonomy, i18n catalogs | app data | — | Containers covered; vocabularies are trivial. |

Order: F1 → F2.

## 3. Drivers (logic dep-free; serve via `e.net` + `e.db`)

| # | appdor source | neper home | Backlog | Notes / acceptance |
|---|---|---|---|---|
| D1 | `src/webhooks/sign.js` (HMAC `t,v1`, 300s window), `src/auth-schemes` (14 pure `apply()`), `src/mcp/protocol.js`, `src/api/openapi-builder.js` (3.0.3) | `e.crypto.mac` + `e.net.http` | L049 | No new deps. |
| D2 | `services/mcp-server` (stdio NDJSON + HTTP, caller-JWT RLS), `src/sharing` tokens (b64url.HMAC, distinct from `jwt.e`), `src/audit` taxonomy, recipe catalog as data | service tools | T032 | DB-poll worker shape → `e.task` + `e.db.pool`; no AMQP assumed. |
| D3 | `src/io/ssrf-guard.js` + pinned-fetch | rides with L046 | — | Covered by the vaper HTTP-policy item; appdor pinning included there. |
| — | `supabase-js`/`pg` clients, GoTrue/Kong/storage-api, SMTP/VAPID send paths, Stripe raw-fetch, SCIM/portal servers | replaced / deferred | — | `e.db` + `lib/x/postgresql`; RLS SQL portable on demand; no IdP/gateway equivs. |

Order: D1 → D2.

## 4. Explicitly out of scope

UI rendering and grid chrome; workflow recipe copy (data, not code); unread files listed in §0 until read; NDJSON import parser (not located); PAT persistence tail (unverified); mail/SMS provider accounts and secrets handling.

## 5. Acceptance per landing

- Fixture-driven goldens in-repo incl. per-category suites and error/warn cases; deterministic reruns; Linux + Windows where platform matters.
- No `unsafe`, no new native deps, no network in `e.*` tests (injected stores/transports only).
- Docs: module API rows in `docs/module-apis.md` + `docs/modules.json` surface flags; this plan file tracks intent, `docs/progress.html` (generated) tracks readiness.
