# C051 — Tokenizer grounding (v1 precursor for T2 H26)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.60 of 1 |
| queue position | 12 of 53 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `benchmarks/tokens/profile.py` writes a grammar-versioned vocabulary table per public tokenizer (cl100k_base, o200k_base): the model-token cost of every grammar terminal and the frequent composite forms, and `--measure` reproduces the corpus numbers from it -- 1.27 model tokens per lexical token on the conformance corpus, keywords one token each, fixed-width type names two, a typed literal three (D375); the card carries the table, rendered from the profiles and refused when a profile is of another grammar revision (D429)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] families without a public tokenizer
- [ ] the profile in the build manifest

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D375` — The tokenizer profile: what the vocabulary costs, versioned with the grammar (`docs/decisions.md:8311`)
- `D429` — The card carries the token-cost table (`docs/decisions.md:9512`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `benchmarks/tokens/profile.py`: `scripts/render_card.py`×1

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
