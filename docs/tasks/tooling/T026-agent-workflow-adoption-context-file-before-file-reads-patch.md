# T026 — Agent workflow adoption: context-file before file reads, patch or plan-* before scripts

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.70 of 1 |
| queue position | 48 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> The tools exist (context-file C053/D361, tools/patch D1455, plan-*-file C052) and nothing routes agents to them: scripts/lang-stats.py on every transcript to 2026-09-26 puts the median context at a turn that lands Neper code at 515K tokens against Dart's 235K, while context-file answers in 1.2K-5K (D948); 39% of landed Neper source arrived inside Python patch scripts and heredocs at 5x the cost per byte of a direct edit, and 5.0% of edit applications failed, almost all of them heredoc scripts. Done when the AGENTS.md rule and a card section route both paths and lang-stats.py's ctx Ktk and script% move on new sessions; the two numbers are the score. The same routing gap holds for the language card: 19 of 161 Neper sessions in 2026-09-20..27 ever named docs/llm-neper-card.md, AGENTS.md carries no language guidance, and the card lists the keywords but not the traps that ended most builds -- `target` (D31), `Vec` and `i8` as reserved names, D66's rule that a local may not reuse a module-scope function, use qualifier or builtin, the string escape set (`\u000F` was written for `\x0F`), and the bootstrap-only rules until C088. A traps section in the card, pointed to from AGENTS.md, is part of this item. Follow-on (D1898): fix the render_card.py mojibake in the normative refs and land the traps section (target, Vec/i8, D66, escapes, bootstrap-only); T036 routes agents to read the repaired card first. Measured on Claude alone (lang-stats.py --harness claude, 2026-08-28..09-27), context is the one gap left against Dart: 513K tokens at a turn that lands Neper code against 210K, with 5.7 turns per edit against 3.9; correctness is level (1st-ok% 96.4 vs 95.0, selfcor% 14.4 vs 15.2, fail% 4.9 vs 3.8), and the 35% cost gap ($0.691 vs $0.513 per KB) is the script share alone (38% vs 17%; direct $/KB 0.198 vs 0.263). Over the last 7 days of it the script share fell to 22% and context to 422K after tools/patch replaced Python patches of src/ on 2026-09-26 (254 and 326 such scripts a day on 09-20 and 09-21, one on 09-27), while 448 patch scripts named dNNNN.py still reached test fixtures, most on 09-25 and 09-26. The score is read from --harness claude: ctx Ktk toward Dart's ~200K and script% toward its 6-17%. Codex on Neper (10% of its code) reads 16 bytes per byte landed and repeats the previous error code 78% of the time, so the traps section serves it too. Snapshot 2026-10-03 (14d, --harness): Claude ctx 388 Ktk (was 422), script 19% (was 22%), $/KB 0.442 (was 0.691, under Dart's 0.468), turns/ed 6.0 (was 5.7), 1st-ok 94.0% (was 96.4). Codex: 3.4 MB landed, script 0% via native apply_patch, ctx 166 Ktk but 15.8 read/KB, turns/ed 7.0, 1st-ok 89.0%, fail 7.2%, 2.7x think per byte. DeepSeek (dsh): zero rows in 14d â€” the split currently measures nothing (D1904). LANDED (D2308): the card's Traps section (reserved names target/Vec/i8, D66 shadowing of functions and qualifiers, ok/err/error field names, tuple-call return, the escape set, bootstrap-only rules) with five checked examples; AGENTS.md routing was already in place. REMAINING: the measured movement of lang-stats ctx Ktk and script% on new sessions.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D31` — Conditional compilation and reserved names (`docs/decisions.md:53`)
- `D66` — Composable names and imports (`docs/decisions.md:88`)
- `D361` — `context-file`: one function's facts, with provenance, under a budget (`docs/decisions.md:7924`)
- `D948` — H25's context/repair workflow: what an agent is handed, and repairs by the compiler's own fixes (`docs/decisions.md:19007`)

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
