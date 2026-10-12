# C113 — NeperOS shell 9: the Clock and Calculator apps

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.70 of 1 |
| queue position | 32 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued by D2148. Acceptance: Clock (time and date, alarms that post a notification, stopwatch, timer) and Calculator (arithmetic with operator precedence, percent, memory, history) as e.ui apps on NeperOS, launched from the C112 grid; each has a QEMU fixture that drives it by injected taps and checks a screendump hash. BEGUN D2179/D2180: both C113 app FACES render through e.gfx.scene over the e.gpu CPU backend, host==neperos both QEMU -- clock_app.e a digital clock (card + "12:34" in the 3x5 bitmap digit font + colon, hash 733107141), calc_app.e a result display + 4x4 keypad (digit glyphs + rect-composed operator symbols / * - + = C, hash 558372214). D2188: the Clock is now LIVE -- clock_app reads the wall clock through e.time (os.clock -> PL031 RTC) and renders the current HH:MM instead of the fixed face, printing `clock live HH:MM`; booted raw on `gpu bigarena` it rendered `clock live 09:51` on both QEMU hosts, exit 0. The frame varies with the clock, so its fixture asserts the serial time pattern, not a golden; clock_app leaves the deterministic app-face loop (calc/tasks/settings stay). CORRECTION: the earlier gpu-boot 'toolchain wall' (D2184-D2187) was a test-harness error of mine -- single-program driver/app images must boot RAW, not wrapped in a shell archive; booted raw the gpu driver and all app faces verify here, and a clean compiler built in-session from the frozen bootstrap confirms it was never the toolchain. C113 -> 0.65: the clock is live; the calculator's tap-to-compute interactivity and hosting the apps in the unified shell still wait on C112. D2189: the Calculator now COMPUTES -- calc_app runs a fixed press sequence `7 * 6 + 9 =` left-to-right through an accumulator/pending-op engine and renders the computed result 51 (was a hard-coded 42 face), printing `calc result 51`; host==neperos hash 1192592031 both QEMU, and the app-face loop now also asserts the literal `calc result 51` for correctness. C113 -> 0.7: clock live + calculator computes; live tap input and shell-hosting still wait on C112's prodshell.

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] live/interactive behavior (clock ticking, calculator button taps computing) and hosting the apps in the shell with tap input
- [ ] which waits on C112's unified launcher (blocked prodshell)

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
