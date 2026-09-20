# T010 — dis

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.85 of 1 |
| queue position | 42 of 51 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

The contract is `docs/tooling.md`, section `## 7. Test, build and command results` (the closed v1 authority; `docs/tooling-v2-draft.md` is the non-normative successor draft).

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `dis-file PATH ROOT ARCH OS --json` (D233): the codegen pipeline, then one `disassembly` record per emitted function with its module.function symbol, the target triple and its listing, ending in the result with the function count; tests/conformance/tools/dis.e pins it per host. The listing is a mnemonic disassembly (D269, src/disasm_x64.e): one line per instruction -- the function-relative offset, the Intel-order mnemonic and operands (64/32/16/8-bit and xmm registers, `[base + index*scale + disp]` and rip-relative memory, signed immediates, jump targets as offsets), then the bytes after `;` -- from a linear sweep over the encodings emit_x64 produces, with section 11's inline trap text listed as one `text` line rather than decoded; 3,546 instructions across three fixtures were cross-checked against GNU objdump with no semantic difference, and eight fixtures list with no unknown byte. A `call` is named after its bytes (D278): `-> module.function` when its resolved displacement lands on a function's start, and the runtime or imported symbol from the relocation that will fill it otherwise (`-> neper_os_exit`)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] AT&T syntax
- [ ] following jumps rather than sweeping
- [ ] every encoding the emitter does not yet produce

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D233` — `dis --json` lists each function's bytes (`docs/decisions.md:4216`)
- `D269` — `dis` lists mnemonics, from a decoder over what the emitter produces (`docs/decisions.md:5218`)
- `D278` — A `call` in the listing is named (`docs/decisions.md:5461`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `disassembly`: `src/tool.e`×3‡, `src/main.e`×2‡, `tests/conformance/tools/dis.x64-linux.expected.jsonl`×2, `tests/conformance/tools/dis.x64-windows.expected.jsonl`×2, `tests/conformance/tools/dis.e`×1, `tests/conformance/tools/dis_inlined.x64-linux.expected.jsonl`×1, `tests/conformance/tools/dis_inlined.x64-windows.expected.jsonl`×1

## Existing fixtures

- `tests/conformance/tools/dis.e`

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
