# C160 — NeperOS Maps remainder: map data, location, search and turn-by-turn navigation

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.65 of 1 |
| queue position | 55 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C130 (D2417): Maps routes over a small road graph with the library's Dijkstra and draws the way. Acceptance: (1) map data on the device: vector tiles or OpenStreetMap extracts rendered through e.gfx.scene with labels, icons, zoom levels and rotation, offline regions kept in Files, and drag and pinch (the touch layer needs both); (2) a location service (GPS and network location on the Pixel, a simulated provider under QEMU) with its permission in Settings (C126); (3) search by name and category with suggestions, place cards with hours and photos from the network; (4) routing for walking, cycling, driving and transit over the road graph with turn-by-turn instructions, rerouting and voice; (5) saved places, recent searches and a Home and Work shortcut shared with Wallet and Weather; (6) a fixture that loads a small offline region, finds a place and routes to it, checking the route length. Data source (user, 2026-10-11): free, non-Google maps -- OpenStreetMap (ODbL, attribution shown in the app): regional extracts (Geofabrik) or Protomaps/OpenFreeMap vector tiles cached in Files, the road graph built from the extract's highways, search from the extract's names (Nominatim only for light, identified use under its policy), no heavy use of tile.openstreetmap.org. PART (D2454): e.fmt.mvt decodes Mapbox Vector Tiles (fmt_mvt, 36 checks vs an independent encoder). Remaining: drawing tiles with styles and labels, offline regions, the road graph from the highway layer, search, location, navigation. PART (D3904): Maps fetches a zoom-14 vector tile, decodes it with e.fmt.mvt and draws roads, water and POI names with the ODbL line; maps_tile passes against an independent tile encoder. Missing: tile pyramid and panning, offline regions, road graph, search, location, navigation. PART (D4920-D4923): tile pyramid with pan and zoom, offline regions in Files, Nominatim search plus OSRM route with steps, location via the sensor server; rows maps_pyramid, maps_offline(+_again), maps_search, maps_location. Remaining: road graph from an extract, walking/cycling/transit, saved places, rerouting and voice, rotation/pinch.

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
