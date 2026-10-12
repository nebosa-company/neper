# T042 — T2.3+T2.4 trusted host: policy, verified receipts, durable tasks

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.60 of 1 |
| queue position | 140 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Planning only (D1954). Reference host tools/neper-agent-host/ missing: policy and sandbox mediation, environment identity, scoped verified receipts (one exact change contract per receipt), isolated parallel change bundles and durable authorized tasks across reconnect and approval. First slice allowed to emit verified. Pickup immediately after the chart cluster; compiler declares facts, host owns authority. FIRST SLICE (D2323): lib/x/agent/contract.e, the H35 change contract (parse fail-closed, canonical form, SHA-256 identity, verdict, amendment link), fixture x_agent_contract (267 cases against an independent reference), both hosts. NOT DONE: policy and sandbox mediation, environment identity, change bundles, receipts, durable tasks, the host. SECOND SLICE (D2324): lib/x/agent/environment.e, the H37 environment manifest (secrets only as hashes, hermetic/observed/uncontrolled with named omissions, identity over the core, observation kept apart), fixture x_agent_environment (265 cases, the perturbation acceptance), both hosts. NOT DONE: replay description, the host that observes a real run, policy/sandbox mediation (H36), change bundles (H38), receipts and durable tasks (H44). THIRD SLICE (D2325): lib/x/agent/policy.e, the H36 action policy (most-specific decision, path classification, audit verdicts with fail-closed unenforced, HMAC approvals with expiry/replay/scope, redaction), fixture x_agent_policy (1259 cases), both hosts. NOT DONE: OS sandbox mediation and the executor that observes effects, replay description, change bundles (H38), receipts and durable tasks (H44). FOURTH SLICE (D2326): lib/x/agent/bundle.e, the H38 change bundle and integration verdict (stale/conflict/incomplete/clean with structured causes, combined identity, never verified), fixture x_agent_bundle (364 cases), both hosts. NOT DONE: identities derived from the compiler's index, candidate re-planning operations, OS sandbox mediation and the observing executor, replay description, receipts and durable tasks (H44), the host. FIFTH SLICE (D2327): lib/x/agent/receipt.e, the verification receipt (unbound/unsafe/unhermetic/failed/incomplete/verified, cached never fresh), fixture x_agent_receipt (364 cases), both hosts. NOT DONE: the host that runs obligations and observes effects, OS sandbox mediation, durable tasks (H44), replay description. SIXTH SLICE (D2328): lib/x/agent/task.e, the H44 durable task state machine (unguessable owner-bound handles, monotonic status, terminal results never rewritten, bound single-use input), fixture x_agent_task (381 cases), both hosts. NOT DONE: the transport that serves handles, retention/reclamation, the host that runs obligations and observes effects, OS sandbox mediation, replay description. SUITE (run 19, seeded Windows, static gate and live-API assertion excluded): the six x_agent_* rows pass in run.ps1 together with x_migrate, the capabilities, --compact, --why and --retries rows; the run stopped later at a NeperOS thread-order assertion (D-free fix in 9e3587d2, interleaved scheduler output).

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- Every emitted record must validate: `python scripts/validate_stream.py`.
- `python scripts/render_progress.py` must run clean after the queue edit.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
