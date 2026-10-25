# C200 — A launch's requirements depend on the worker count

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.00 of 1 |
| queue position | 92 of 94 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Found by C184's differential (D5641): `emit-executable tests/selfhost/fixtures/link/gpu_tensor/src/main.e . x64 windows OUT` writes different bytes at the default worker count and at `-j 1` (offsets 50339, 51948 and 53420 for x64 windows: the `mov r8d` of `launch_run`'s requirements argument is 0 with eight workers and 4, 256, 256 with one). `lower.e` `lower_launcher_instance` emits `check.kernel_fact(c, template) & 511` as a constant, but the facts are a per-checker table filled by `check_kernel_profile` when the kernel's body is checked, so a launcher lowered by a worker that did not check the kernel (`tensor.add[i64]` instantiated in main, kernel `add_i64` in e.gpu.tensor) reads 0 and a device without Int64 would be launched anyway. Plan: make the requirements a companion of the kernel like `K$frame` and `K$shared` (`emit_kernel_size` beside the kernel, `emit_kernel_size_call` in the launcher, the suffix in `em.e`'s companion list), so the module that checked the kernel answers. Acceptance: (1) gpu_tensor emits the same bytes at -j 1, -j 2 and the default on x64 windows and x64 linux, and its requirements are the -j 1 values; (2) a fixture whose launcher and kernel live in different modules checks the requirement a launch reports; (3) `scripts/wasm-compiler.sh --all` reports no `differ` pair.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `lower.e`: `src/main.e`×17‡, `lib/e/os.neperos.e`×1, `lib/e/ui/navigation.e`×1‡, `scripts/lint_bootstrap.py`×1
- `lower_launcher_instance`: `src/lower.e`×2‡
- `check_kernel_profile`: `src/check.e`×2‡
- `add_i64`: `lib/e/gpu/tensor.e`×2, `lib/e/fmt/flatbuffers.e`×1
- `emit_kernel_size`: `src/lower.e`×6‡
- `emit_kernel_size_call`: `src/lower.e`×3‡
- `em.e`: `src/check.e`×14‡, `lib/e/ui/navigation.e`×9‡, `src/main.e`×5‡, `lib/x/elastic/rest.e`×4, `lib/e/ui/overlay.e`×3‡, `src/tool.e`×3‡, `benchmarks/baseline/results/context-linux-d948.json`×2†, `benchmarks/baseline/results/context-windows-d948.json`×2†

## Existing fixtures

- `tests/selfhost/fixtures/link/gpu_tensor/src/main.e`

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
