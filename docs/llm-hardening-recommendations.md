# Neper — LLM-processing hardening recommendations

Status: adopted recommendation set, recorded 2026-09-06. This document distils the
post-M2 LLM review into a prioritized, concrete list of what a language must do to be
**optimized for LLM processing end-to-end** — generate, search, edit, verify, repair —
rather than merely *readable by the human reviewing model output*.

It adds no syntax, runtime facility or standard-library API. `spec.md`, `grammar.ebnf`,
`tooling.md`, `modules.md` and `decisions.md` remain authoritative. Items R01–R07 map
onto the mandatory obligations H01–H25 in
[`post-m2-llm-hardening.md`](post-m2-llm-hardening.md) and sharpen their priority;
items R08–R11 are new and are registered as H26–H29 there. Each recommendation names
the problem it closes, the concrete direction, its mapping, and the acceptance rule it
inherits or adds.

## 1. Summary and priority order

| Rec | Recommendation | Priority | Maps to |
|---|---|---|---|
| R01 | Compiler-enforced ownership and lifetime | P0 | H01–H04 |
| R02 | Semantic context query (`neper context`) | P0 | H08 |
| R03 | Token-cost measurement steers syntax | P0 | H06, H11, H12, H25 |
| R04 | Transactional multi-file repair and refactor | P1 | H09, H15, H17, H18 |
| R05 | Executable, retrievable API catalogue | P1 | H11, SL11 |
| R06 | Edit-loop latency: reuse, snapshots, lifetimes | P1 | H14–H16 |
| R07 | Held-out two-family evidence gate | P1 | H12, H25 |
| R08 | Tokenizer grounding as a design input | P2 | H26 (new) |
| R09 | Unsafe/escape-hatch enumeration as a review surface | P2 | H27 (new) |
| R10 | LLM cards compiled from the grammar | P2 | H28 (new) |
| R11 | Structured (AST-level) edits over raw spans | P2 | H29 (new) |

P0 items block any claim that the language is "optimized for LLM processing"; P1 items
block the M3 admission gate in practice even where the existing H-plan does not yet
sequence them first; P2 items are lower-volume but close the difference between
"readable by reviewers" and "operated on by models".

## 2. R01 — Compiler-enforced ownership and lifetime (P0)

**Problem.** The language's central promise — §14 goal 1, "a model should not be able
to write a line whose meaning depends on context it cannot see" — fails on *temporal*
context. Use-after-reset, aliasing across container growth, double-close, and
borrow-after-free are exactly hidden context, and today they are unguarded:
`general-purpose-verification.md` §2 states that "the current spec explicitly leaves a
pre-growth slice silently stale." LLMs are systematically weakest at this class, so it
is the highest-leverage gap.

**Recommendation.**

1. Adopt the checked ownership/region subset of H01–H02 as **default-on**: affine
   ownership of `Arena` and owned OS handles, and lexical region/view validity for
   slices and pointers. Escaping a borrow or bitwise-copying an owned resource is a
   compile error in checked code, not a `0xDD` fill to be noticed later.
2. Make the unsafe boundary first-class (H03): raw dereference, `mem.cast`,
   `mem.bitcast`, `@nocheck`, unchecked indexing and `extern` calls occur only inside a
   named construct that states its obligations in source and is enumerated by
   `neper index` (see R09).
3. Sequence H01 → H02 → H03 → H04 as the hardening doc §29 already orders them, and do
   not deliver H04 (scoped concurrency) until H01/H02 land, since H04 depends on both.
4. End "release removes checks" as the default (H03): retain bounds/null/tag/align
   checks in the optimized build unless a proof removes them, and publish the check
   table per build mode as part of the build manifest.

**Acceptance.** Inherits the H01–H04 acceptance lists verbatim, plus one regression: a
model-generated "reset then slice" and a "push then retain view" pair must each be
rejected at compile time in checked code, not trapped at run time.

## 3. R02 — Semantic context query (`neper context`) (P0)

**Problem.** `neper index --json` gives names, signatures and spans but not *semantic*
facts; the model therefore reads whole files or prose and guesses. H08 is the
highest-leverage tooling item and is unimplemented.

**Recommendation.**

1. Deliver `neper context` as the **first** M2.5 tooling increment, before repair and
   refactor, because H09/H17/H18 consume its output.
2. Make provenance a required field on every returned fact —
   `compiler-proved` / `declared-and-checked` / `trusted-external` /
   `runtime-observed` / `unknown` — and never promote a comment or a model-written
   claim to a fact (H08's deceptive-comment fixture is non-negotiable).
3. Return ownership/borrow/invalidation/effect/error/unsafe facts, not just types,
   because those are precisely the facts an LLM needs to edit one function safely.
4. Bound output by bytes/records, return omission counts and a completeness flag, and
   use snapshot-bound cursors.

**Acceptance.** Inherits the H08 list, plus a fixture where the context for a function
that mutates an arena-backed slice names the invalidation point and its origin.

## 4. R03 — Token-cost measurement steers syntax (P0)

**Problem.** The language buys certainty with verbosity, but "character count is not
token count" has been used to defer optimization rather than to measure and steer. For
an LLM-first language, total tokens per verified edit is a design input, not a
post-hoc gate.

**Recommendation.**

1. Stand up a reproducible token-cost harness *now*, before M2.5: fixed model families,
   fixed tokenizer identities, fixed task corpus, reporting input/output/total tokens,
   tokens per non-comment line and per syntax node, and repair turns — the metrics
   already listed in `general-purpose-verification.md` §4.
2. Treat the result as an input to syntax decisions: a proposed spelling change must
   show a measured token or repair-turn improvement, never a character-count argument
   (this is H06/H11 policy promoted to a running obligation, not a gate-only one).
3. Publish the token-cost report in a machine-readable, grammar-versioned form
   (`neper info`-adjacent) so a harness can cite the numbers.
4. Keep the "no universal optimality" honesty, but optimize the *intersection* of the
   supported tokenizers and document where tokenizers disagree, rather than abandoning
   the metric.

**Acceptance.** A checked-in, reproducible token-cost report with per-tokenizer numbers;
a documented accept/reject decision for at least one verbosity-reduction candidate
driven by that report.

## 5. R04 — Transactional multi-file repair and refactor (P1)

**Problem.** The closed v1 `edit`/`fix` record cannot carry an expected-source hash;
rename/move/delete has no tooling; cross-module signature migration — the hard,
high-value LLM task — is unsupported. The hardening doc §29 already flags the missing
fix precondition as a known contract defect.

**Recommendation.**

1. Close the four known contract defects named in the hardening doc §29, the
   fix-precondition defect among them.
2. Ship a **versioned v2 stream schema** with snapshot/document preconditions, byte
   spans or structured edits, applicability, and validation obligations (H18); do not
   extend closed v1 while continuing to label it v1.
3. Implement compiler-backed rename/move/delete planning (H17) with explicit
   completeness: "unknown indirect/external consumers" must render as *incomplete*,
   never as *safe to delete*.
4. Make apply transactional across files: validate every precondition, then write;
   failure leaves all sources untouched (H09).

**Acceptance.** Inherits the H17/H18 lists, plus a fixture that renames an error or
module and proves no stale spelling remains, and a fixture where a concurrent edit
makes a precondition stale and the transaction aborts atomically.

## 6. R05 — Executable, retrievable API catalogue (P1)

**Problem.** The four LLM cards are static prose; the 128-module catalogue
(`modules.json`) is JSON the model cannot query; hallucinated APIs are a top failure
mode.

**Recommendation.**

1. Add a `neper apis` query (or extend `context`) returning exact signatures plus
   ownership/borrow/failure/allocation contracts, runnable examples and test
   references, filtered by module or symbol, with provenance and
   implemented/planned/target-specific status (SL11).
2. Never return a planned-only API as callable; missing evidence is
   `unavailable`/`unverified` (SL11's explicit rule).
3. Generate the language cards from the same registry (see R10) so the card and the
   query cannot disagree.

**Acceptance.** Inherits the H11/SL11 lists, plus a fixture proving a planned-only
module is reported unavailable, and that every example returned by the command
compiles and runs.

## 7. R06 — Edit-loop latency: reuse, snapshots, lifetimes (P1)

**Problem.** The 1M-lines/sec target describes throughput; an LLM edit loop is
dominated by per-declaration reuse, immutable snapshots, and request lifetimes, none of
which exists yet.

**Recommendation.**

1. Implement declaration/query-level incremental reuse (H14) and immutable snapshots
   with complete cache identity (H15) **as a pair**, because reuse without correct
   identity is unsound.
2. Deliver bounded request/snapshot/cache lifetimes and cancellation (H16) before
   adding any persistent daemon; record the daemon decision either way.
3. Gate on p50/p95 "no-op check" and "local edit/revert" latency budgets frozen from
   the M2 baseline (H25), not on aggregate throughput.

**Acceptance.** Inherits the H14–H16 lists; the comment-only-edit and edit-then-revert
fixtures must show the expected reused/invalidated units, not a full recheck.

## 8. R07 — Held-out two-family evidence gate (P1)

**Problem.** All LLM-optimization claims are currently hypotheses; the shipped
benchmark disclaims statistical significance and its semantic matrix has no compiler
to run against.

**Recommendation.**

1. Keep the H12 two-family, held-out, pre-registered evaluation as a hard gate, and
   archive the reproducible M2 baseline before it runs.
2. Report full harness cost per verified success — tokens, turns, retries, timeouts,
   escaped defects, false rejection — not first-pass rates alone (H25).
3. Feed the R03 token-cost report into the H12 decision as a required input.

**Acceptance.** Inherits the H12/H25 gates; no "faster", "safer" or "more
LLM-friendly" claim appears without the paired evidence.

## 9. R08 — Tokenizer grounding as a design input (P2, new → H26)

**Recommendation.** The language already has a closed, frozen vocabulary (94 token
kinds, 54 syntax-node kinds in `grammar.ebnf`). Publish an official tokenizer profile
for each supported model family — a documented BPE extension where `fn`, `ret`, `try`,
`[]const`, `union enum`, `u64`, `->` and the other frequent forms are single tokens,
or, where that is not deployable, a canonical vocabulary table so token cost is
measurable and stable. Version the profile as tooling data and stamp it into the build
manifest. This converts R03 from "measure after the fact" into "design in".

**Acceptance.** A grammar-versioned tokenizer profile per supported family; the R03
report reproduces its numbers from the profile and the frozen corpus.

## 10. R09 — Unsafe/escape-hatch enumeration as a review surface (P2, new → H27)

**Recommendation.** Every unsafe boundary — `@nocheck`, bare `union`, `mem.bitcast`,
`mem.cast`, raw dereference, `extern` — must appear in `neper index` as a
symbol/reference carrying a provenance tag, and `neper context` (or a dedicated
command) must enumerate all of them in one bounded pass. The reviewer's job is "audit
exactly the un-proved surface"; make that a one-command operation. This is a
precondition for any "checked subset" claim: the checked/unchecked boundary must be
enumerable, not merely declared.

**Acceptance.** A fixture with unsafe sites in several modules is fully enumerated by
one command, and every site carries `trusted` or `unknown` provenance, never `proved`.

## 11. R10 — LLM cards compiled from the grammar (P2, new → H28)

**Recommendation.** Replace hand-maintained card prose with a card generated from
`grammar.ebnf` plus the closed registries and selected library contracts, emitted with
a grammar-revision stamp and content hash. Hand-edited commentary may remain, but never
as the normative surface. This closes the drift risk and is a prerequisite for H11's
"cards for old and revised language versions cannot be confused".

**Acceptance.** The four shipped cards are produced by the generator and their hashes
are recorded; a grammar change that is not reflected in a card is a CI failure.

## 12. R11 — Structured (AST-level) edits over raw spans (P2, new → H29)

**Recommendation.** In the v2 tooling stream, express edits as typed operations —
replace-expression, change-signature, add-parameter-and-migrate, rename-symbol — with
pre/postconditions, in addition to byte spans. Byte spans remain for lossless/trivia
cases, but semantic refactors must not be expressed as text replacement. This makes
R04's transactional multi-file refactors verifiable rather than brittle, and lets the
compiler re-derive spans instead of the model guessing them.

**Acceptance.** A cross-module signature migration is expressed as a structured
operation, applied transactionally, and verified by re-check; no edit is applied from
a span that the compiler has not re-validated against the target snapshot.

## 13. Documentation wiring applied

| Change | Location |
|---|---|
| New recommendation set R01–R11 | this document |
| Register R08–R11 as H26–H29; pointer at head | `post-m2-llm-hardening.md` |
| M2.5 reference and H26–H29 scope | `roadmap.md` |
| Token-cost steering note in §4 | `general-purpose-verification.md` |
| D82 reference updated to H01–H29 | `decisions.md` |
| Document index entry | `README.md` |
