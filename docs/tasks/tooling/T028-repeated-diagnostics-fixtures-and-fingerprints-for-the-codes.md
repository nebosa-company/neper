# T028 — Repeated diagnostics: fixtures and fingerprints for the codes that recur across a repair

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.85 of 1 |
| queue position | 50 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Over 198 observed repairs in the transcripts (lang-stats.py, REPAIR table), a compile diagnostic is fixed in the next reply but only 15.7% of repairs took one edit, and 61.5% of consecutive failed builds repeat an error code from the failure before -- E-TYPE-0002 and the other kind-level codes cannot tell a second site from an unfixed first one. H31's cross-run fingerprints are T2; the v1 precursor is a fixture per recurring code that pins what the message must name (the span, the expected and found types, the binding) so a model can act on it once, tracked by lang-stats.py's repeat% and 1-edit%. Follow-on (D1898): the repeat metrics must cover OpenCode rows once the T037 harness split lands, or agent-visible progress stays Claude-only. Transcripts 2026-09-20..27 name the first fixtures: 134 builds failed on a compile code and 24 of 42 consecutive ones repeated a code. E-TYPE-9999 (29) printed an internal error name for its message -- `type checking failed: check.UnknownCallable`, `.ArgumentCount`, `.InvalidOperator`, `.Unsupported`, `.InvalidType`, `.MissingContext` -- naming no callee, count or operator; E-LEX-0003 (21) said `invalid token` for a malformed escape without naming the escape or the legal set (src/main.e print_parse_failure); E-NAME-9999 (8) said `unknown value name` without the name; E-TYPE-0003 (9) said `ret gives a different number of values` without the two counts; E-SYNTAX-9999 (9) said `unexpected ==` without what was expected. Each of those messages names its subject, the check.* names get codes of their own, and a fixture pins each. D1679 does that: ArgumentCount is E-TYPE-0005 (`take` takes 1 argument and this call gives 0) or E-TYPE-0007 (results discarded), UnknownCallable E-NAME-0004 with the callee, InvalidOperator E-TYPE-0006 with the operator and its expression, MissingContext E-TYPE-0001, InvalidType and Unsupported E-TYPE-0008/0009 quoting the statement; the unknown name, both ret counts, the bad escape with the legal set (and an unclosed literal, a control byte, a tab, a non-UTF-8 byte), and `; expected X` after `unexpected` where the parser knows X. The C bootstrap says the two messages its neper-0 fixtures pin, so self-host parity stays byte-equal. Pinned: seven check fixtures by text in both suites, the conformance and tools goldens, byte-equal on Linux. E-TYPE-0009 is reached by reject/not_supported, an assignment to an array range quoted by its first line (D1706, both suites). Snapshot 2026-10-03 (14d): repeat% Claude 59.5 (was 61.5), Codex 70.0; 1-edit% identical across harnesses (54.3/53.5), so landed fixes transfer but recurrence does not; DeepSeek empty. Cross-run fingerprints remain the stuck point on both measured harnesses (D1904).

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] lang-stats.py's repeat% and 1-edit% over transcripts written after D1679

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `.ArgumentCount`: `src/lower.e`×57‡, `src/check.e`×1‡
- `.InvalidOperator`: `src/lower.e`×2‡, `src/check.e`×1‡
- `.Unsupported`: `src/codegen_a64.e`×73†, `src/lower.e`×56‡, `lib/e/crypto/x509.e`×18†, `lib/x/postgresql/libpq.e`×12†, `lib/e/ui/app.e`×10†, `scripts/xsd_schema_reference.py`×10, `lib/e/gpu/tensor.e`×9, `lib/x/oracle/mysql.e`×8
- `.InvalidType`: `src/lower.e`×54‡, `src/tool.e`×2‡, `src/check.e`×1‡, `src/layout.e`×1, `src/main.e`×1‡
- `.MissingContext`: `src/lower.e`×2‡, `src/check.e`×1‡

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
