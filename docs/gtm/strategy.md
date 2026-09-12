# neper — commercial strategy

Status: draft, 2026-09-13. A working position, not a decision record; the numbers
below are assumptions to be replaced by measurements, and each says so.

## 1. The premise

No systems language of the last twenty years has been sold directly. Rust, Go, Zig,
Swift and Kotlin are free because a language that costs money gets no codebase bet on
it, and a language with no codebases has nothing to sell. Money in this space comes
from what surrounds a free language: hosted services, enterprise assurance, and the
tools people use to write it.

neper's one real differentiator is not syntax or speed. It is that the toolchain was
built so that code written by a model can be checked rather than trusted: a
deterministic compiler that never touches the network, `.em` artifacts with a
stage-2 == stage-3 fixed point, a stdlib whose every module is fenced to a frozen
surface and driven by per-check fixtures on two hosts, the LLM editing cards, the
M2.5 hardening spec, and a package manager that verifies by hash and executes nothing
on install. That is a product story for agents, not for people learning a language.

The bet: **the first users are agents.** If a model writes neper reliably where it
writes flaky C++ or Rust, the pull comes from teams shipping agent-generated tools and
backends, and the humans arrive after the agents. Everything below follows from that
bet, and section 6 says how to test it before spending on it.

## 2. What stays free, forever

- The compiler, linker and every `e.*` module, on every host.
- `neper pacman` (the client, resolution, the immutable store).
- The language spec, the LLM cards, the grammar, the diagnostics registry.
- The MCP server in its single-user form.

License: MIT or Apache-2.0. Not a source-available or "fair" license: the buyers
that matter run legal review before adopting a language, and anything that is not on
their approved list ends the conversation. The stdlib's crypto modules in particular
must be free or nobody will build a networked program on them.

## 3. What is sold

Ordered by when it can exist and how much it can earn.

### 3.1 Hosted agent ("neper agent") — the business

A coding agent that writes neper end to end: it generates the program, compiles it
with the deterministic toolchain, runs the fixtures it wrote against the fence it
declared, and hands back a verified artifact with its `.em` hashes. The MCP server is
the free seed of this; the hosted form adds the model, the sandbox, the fixture
runner on both hosts, persistence of the project, and the verification report.

Why it is defensible: the verification loop is the moat, and it only works because
the whole toolchain is deterministic and self-describing. A generic agent on a
generic language cannot promise "this binary is what the fixtures say it is".

Pricing (assumption, to be tested): developer-tool norms. **$25–40 per seat per
month** for individuals and small teams; **usage-based on top of model cost** for
heavy agent use, since the customer's own token spend dominates. A free tier bounded
by compile minutes, not by features.

### 3.2 Registry and enterprise tier — the annuity

Around pacman: a private registry, signed provenance and SBOM output from the hash
graph pacman already keeps, LTS toolchain lines with backported diagnostics, and a
support SLA. Enterprises buy this without a decision meeting once they have neper in
production, and not before.

Pricing (assumption): **$100–300 per developer per year**, seat-counted, annual.
Small, recurring, and the kind of line that keeps a company alive between larger
deals.

### 3.3 Certified builds — the niche

Reproducible, attested builds for regulated buyers (medical, automotive, finance
infrastructure): a signed statement that a given source produced a given binary under
a given toolchain, checkable by anyone with the toolchain. The fixed-point property
and `.em` byte equality are the substance; the certificate is the product.

Per contract, five figures and up, and only after 3.1 and 3.2 exist and a customer
asks. Not to be built speculatively.

### 3.4 Consulting and porting — the bridge

Pays bills in year one, does not scale, and pulls effort away from 3.1. Take it when
the customer is one who would buy 3.1 or 3.2 later; decline it otherwise.

### Not sold

- Premium stdlib modules (GPU, UI). A stdlib with paid corners is a stdlib nobody
  targets. `e.gpu` and `e.ui` ship free when they ship.
- Marketplace fees on the registry. It taxes the people who make the ecosystem worth
  anything.
- Training courses. Fine as marketing, not as revenue.

## 4. Positioning and message

One line: **the language a model can write and a compiler can prove.**

Supporting claims, each backed by something in the repo:

| Claim | Evidence to point at |
| --- | --- |
| Deterministic, offline compiler | no network in the compiler; pacman prepares the map, the compiler reads it |
| Self-verifying toolchain | stage-2 == stage-3 fixed point in the suite; `.em` byte equality |
| A stdlib a model can trust | every module fenced, fixture-driven, both hosts; `docs/progress.html` |
| Written for models | the LLM cards, the hardening spec, M2.5 |
| Batteries included | crypto, codecs, compression, time zones, concurrency in `e.*` |

The audience for the first year is not "developers". It is the people choosing what
their agents should write: platform teams, AI-tooling teams, and founders shipping
agent-built products. They do not need to like the syntax; they need the defect rate.

## 5. Rough model

Assumptions, all of them; the point is the shape and the order of magnitude, and
every figure here is to be replaced by a measured one.

| Year | Free users (est.) | Agent seats | Enterprise devs | Revenue (est.) |
| --- | --- | --- | --- | --- |
| 1 | hundreds | 0 (free MCP only) | 0 | consulting only, $0–50k |
| 2 | low thousands | 200–500 at $30/mo | 0–100 at $200/yr | $90–200k |
| 3 | 10k | 2,000 at $30/mo | 500 at $200/yr | $800k–1M |

Year 3 is a business at one or two people's salaries with a large model bill in the
middle of it; anything beyond that depends on the agent bet paying off in a way that
cannot be modelled from here. If year 1 ends with no outside team using the free
MCP server on real work, the model above is void and the honest move is to keep
neper as an open project rather than a company.

## 6. The test that decides

Before any of section 3 is built, measure the premise:

1. Give a current model the cards and the MCP server. Have it build ten real programs
   (a CLI, a service, a parser, a codec, a concurrent job runner, ...).
2. Do the same tasks in Go and in Rust with the same model.
3. Count defects found by an independent test pass, compile-fix iterations, and
   human interventions per task.

If neper's defect rate is not dramatically lower — not 20% lower, but a different
category — the agent bet is wrong and no pricing fixes it. If it is, that table is
the launch material and the sales deck in one.

## 7. Sequence

1. Finish M2.5 hardening; ship the MCP server publicly, free, with the cards.
2. Run the benchmark in section 6 and publish it, including where neper lost.
3. Hosted agent (3.1) once three to five outside teams use the free one on real work.
4. Registry and enterprise tier (3.2) when the first of those teams asks for a
   private registry — they will name the moment.
5. Certified builds (3.3) only on a signed request.

## 8. Risks named

- **Model drift.** The agent product rides on a model neper does not own; the cards
  and the verification loop must be re-measured on every model generation.
- **Big-vendor language.** A large lab could ship an "agent-native" language with
  distribution neper cannot match. The defence is being first with published
  numbers and a stdlib that already exists.
- **Adoption is slow no matter what.** Languages take years. The free tier has to
  survive on a hobby budget for longer than feels reasonable.
- **Selling the moat.** A hosted agent that exposes the verification report as an
  API invites customers to reproduce it locally with the free toolchain — which is
  fine, and is what the free toolchain is for. The paid product is convenience,
  scale and persistence, not the check itself.
