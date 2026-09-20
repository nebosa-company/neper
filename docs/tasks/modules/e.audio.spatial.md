# e.audio.spatial — 9 of 9 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/audio/spatial.e` |
| plan row | layer 2, surface `planned`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/audio/spatial.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.math.fixed` | partial | `lib/e/math/fixed.e` | 0 |
| `e.audio` | partial | `lib/e/audio.e` | 2 |
| `e.audio.mixer` | partial | `lib/e/audio/mixer.e` | 2 |
| `e.algo.rand` | source | `lib/e/algo/rand.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 2 may depend on layers [0, 1, 2].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
// A source at a point in the world becomes a gain and a pan on a mixer voice. Integer
// throughout, so a positioned mix stays as reproducible as an unpositioned one.
type Listener = struct { x: fixed.Fx, y: fixed.Fx, facing: fixed.Fx }
type Source = struct { x: fixed.Fx, y: fixed.Fx, gain: i32, min_distance: fixed.Fx, max_distance: fixed.Fx }
type Cue = struct { id: u16, first_variant: u16, variant_count: u16, gain: i32, cooldown: u16, remaining: u16 }
error Unknown

fn pan(l: Listener, s: Source) -> i32
fn attenuate(l: Listener, s: Source) -> i32
fn place(m: *mixer.Mixer, voice: usize, l: Listener, s: Source) -> err
fn trigger(m: *mixer.Mixer, c: *Cue, variants: []const audio.Frames, state: *rand.Pcg64, l: Listener, s: Source) -> (usize, err)
fn step_cues(cues: []Cue) -> err
```

## Missing declarations

- [ ] `Listener`
- [ ] `Source`
- [ ] `Cue`
- [ ] `Unknown`
- [ ] `pan`
- [ ] `attenuate`
- [ ] `place`
- [ ] `trigger`
- [ ] `step_cues`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/audio/mixer.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/audio/spatial.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/audio_spatial/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 9.

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
