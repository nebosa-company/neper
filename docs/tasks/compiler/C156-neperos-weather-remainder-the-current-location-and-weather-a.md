# C156 — NeperOS Weather remainder: the current location and weather alerts

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.75 of 1 |
| queue position | 51 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C119 (D2408): Weather shows live Open-Meteo forecasts for places the user adds, kept in storage with the unit. Acceptance: (1) the current location as a place by the user's choice once the location service exists (C131: GPS or network location, a permission the user grants); (2) alerts for a place from a source that has them (the Norwegian MET API's alerts, or a national feed), shown on the main screen and as a notification (C106), checked against recorded responses. PART (D2452): e.fmt.cap reads Common Alerting Protocol alerts (fmt_cap, 74 checks vs ElementTree). Remaining: the alert source and place-to-area match in Weather, the notification, and the current location (C161). PART (D3902): MetAlerts alert list and its CAP resource read with e.fmt.cap, headline in a red bar; weather_alert passes. Test server alert JSON is written from the documented shape, not captured. Missing: notification (no status-service grant), current location, other feeds. PART (D4930-D4932): NWS alerts for US places, MET for Oslo, the alert notification, current location as a place; rows weather_notify, weather_here. Remaining: other national feeds, location permission UI.

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
