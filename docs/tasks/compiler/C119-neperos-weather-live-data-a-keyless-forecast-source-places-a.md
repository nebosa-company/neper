# C119 — NeperOS Weather live data: a keyless forecast source, places and units

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.90 of 1 |
| queue position | 8 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued by the user (2026-10-08). The Weather app (D2214) ships on a seeded sample forecast; this item replaces it once C117 (networking) exists. Acceptance: (1) a keyless forecast source (Open-Meteo or the Norwegian MET API; no account) giving the current temperature and condition, the hourly strip, seven days, humidity, wind and UV, with the sample data as the offline fallback and a visible 'updated' time; (2) places: search by name, add and remove, the current location by the user's choice, kept in storage; (3) units (C and F, km/h and mph) remembered; (4) sunrise and sunset, precipitation chance and alerts; (5) a condition for each hour (the sample strip shows today's condition for all eight hours, so it cannot show a change coming), precipitation chance per hour, and hours and weekdays in the place's own time zone (the sample follows UTC). Fixtures run against recorded responses, not the live internet.  DONE (D2286): Open-Meteo forecast (current, 24 hours with a condition and rain chance each, 7 days, sunrise and sunset, humidity, wind, UV) in the place's own time zone with an updated time and the sample as fallback; place search (Open-Meteo geocoding), add and remove; C/F and km/h/mph; fixtures weather and weather_live pass on Windows and WSL. NOT DONE: places and units are not kept (storage: C116, C125); no current location (GPS: C131); no alerts (Open-Meteo has none).

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
