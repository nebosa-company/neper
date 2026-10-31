# L150 — NodaTime-style dates: non-ISO calendars, patterns, maps

| field | value |
|---|---|
| category | library / Algorithms |
| score | 0.99 of 1 |
| queue position | 51 of 106 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Planning only (D1890). NodaTime parity gap (verified: TZif parsing present, non-ISO calendars absent): Japanese/Islamic/Hebrew calendar arithmetic over e.time.calendar, pattern-based text parsing/formatting and a Windows to IANA zone map. Fixtures against reference conversions. PART (D2800): e.time.calendars (Julian, Islamic civil, Hebrew vs convertdate; Japanese eras), e.time.pattern (runtime date patterns, 573 checks) and e.tz.winzones (Windows to IANA zone ids). NOT DONE: Persian, Coptic, Thai/Buddhist, Chinese and Umm al-Qura calendars; windows zone mapping beyond territory 001; non-English pattern names. PART (D2450): Coptic and Ethiopic calendars (time_calendars_african, 643 checks vs convertdate). Remaining: Persian, Thai Buddhist, Chinese, Umm al-Qura; zone mapping beyond territory 001; non-English pattern names. PART (D2451): Thai Buddhist calendar (Gregorian + 543; time_calendars_african, 765 checks). Remaining: Persian, Chinese, Umm al-Qura. PART (D3300): Persian (33-year rule, matches astronomical calendar 1278..1502 AP) and Umm al-Qura (1343..1500 AH) calendars; time_calendars_persian_uq 644 checks vs convertdate/hijridate. Missing: Chinese calendar, zone mapping beyond territory 001, non-English pattern names. PART (D3600-D3601): e.time.chinese 1900..2100 from Meeus astronomy vs lunar_python (201 years, 9 years daily), territory zone rows vs .NET and Babel, e.time.names CLDR names for 27 languages (868 vectors vs Babel). Missing: region variants, genitive month forms, Chinese outside 1900..2100. PART (D4605): e.time.names 52 rows (27 languages and 25 regional/script variants, 159 identifiers) with locale_index resolution and genitive/stand-alone month forms; time_pattern_locales 1,909 vectors vs Babel. Behaviour change: ru MMMM without a day is nominative. Missing: further locales beyond Babel's CLDR subset.

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
