# L048 — Reference drivers: k8s labels, AWS subset, SSH transport

| field | value |
|---|---|
| category | library / Drivers |
| score | 0.35 of 1 |
| queue position | 56 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Petcow k8s provider (petcow.io/managed labels must never be renamed), aws CloudControl uniform CRUD with s3/ec2/iam subset plus lightsail non-uniform gap, transport/ssh.rs with the Transport trait and lazy per-host PerHostTransport. Land as x.cloud.aws, x.cloud.k8s, x.ssh; local stays e.proc/e.os.shell, ssm/winrm stay cloud- and platform-specific. Plan: docs/petcow.md D3/D4. Follow-on (D1881): consul/vault/etcd/docker client scope (service discovery, secrets, registries). Follow-on (D1889): SFTP subsystem client once the queued SSH transport lands. Part one landed: x.cloud.aws (Cloud Control identity, tags, desired state, patches, catalogue merge) and x.ssh.args (ssh argument builder), 311 differential cases against Petcow's Rust on Windows and Linux (D2354). Remaining: the k8s kubectl provider's identity rules (label marker, last-applied), ec2/s3/iam/lightsail and the per-host transport table.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
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
