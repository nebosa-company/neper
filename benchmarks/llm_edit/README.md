# LLM search/edit benchmark

This benchmark tests the claim in spec §14 that Neper source is easier for a model
to search and amend reliably. It gives the same search and surgical-edit requests to
fresh copies of `examples/sample.e` and `examples/sample.rs`, then checks exact
answers, required replacements, stale references, and unrelated changed lines.

These search/edit tests do not establish lifetime safety, behavioral correctness or
the post-M2 release decision. The mandatory pre-M3 M2.5 evaluation is specified in
[`docs/post-m2-llm-hardening.md`](../../docs/post-m2-llm-hardening.md), H12. It adds
held-out semantic tasks, actual compiler tools, independent behavioral oracles,
baseline comparisons and per-family correctness/repair thresholds. Implementing
that extension is scheduled for M2.5; the existing suite does not satisfy it yet.

The adopted [library hardening](../../docs/stdlib-hardening.md) adds catalogue
shadowing/alias, composable I/O, exact JSON integer/patch, bounded process and
cancellation fixtures to that evaluation. Later streaming HTTP/SSE, crypto and
image/codec cases activate only when their actual implementations are available.
The static plan validator is run with `python scripts/check_module_plan.py` from
the repository root; its tests are `python -m unittest discover -s tests -p test_module_plan.py`.
Neither static success nor a generated API PDF is evidence of executable support.

Run at least three trials because model output is nondeterministic:

```text
python benchmarks/llm_edit/run.py --trials 5 --agent-command "YOUR_AGENT --prompt-file {prompt_file}"
```

The command runs with an isolated temporary directory as its working directory.
Available placeholders are `{workspace}`, `{file}`, `{prompt}`, and `{prompt_file}`.
The agent must print its answer for search tasks and directly edit the file for update
tasks. `--json` emits machine-readable results.

The primary metric is pass rate. Mean changed lines measures edit precision; elapsed
time is secondary because provider and network variance can dominate it. Use the same
model, settings, tool permissions, and number of trials for both extensions. The
benchmark deliberately does not claim statistical significance: add tasks covering
more language constructs and run enough trials before drawing a general conclusion.

The harness itself has dependency-free unit tests:

```text
python -m unittest discover -s tests
```

## Jev routing experiment

`jev_router.py` runs a paired A/B experiment: the baseline always uses a strong
coding agent, while the routed arm asks TypeSafe Jev whether the same task can use a
fast agent. Jev sees the task text and source statistics, not repository source. A
low-confidence, malformed, or failed routing response falls back to the strong agent;
the ordinary benchmark checks correctness after either choice.

Set `OPENROUTER_API_KEY`, then run:

```text
python benchmarks/llm_edit/jev_router.py --trials 5 --json \
  --strong-agent-command "STRONG_AGENT --prompt-file {prompt_file}" \
  --fast-agent-command "FAST_AGENT --prompt-file {prompt_file}"
```

The router uses OpenRouter's Decisions API and the `~typesafe/jev-latest` model by
default. The JSON report records the resolved Jev model, provider, confidence,
probabilities, routing latency, token use and cost alongside both agent results.
Replay exactly those routing
choices without another Jev request by passing `--replay-report REPORT.json`. The
default corpus is Neper only; add `--languages e,rs` when `examples/sample.rs` is
present. Treat the task text sent to Jev as an external-service disclosure even
though source text is excluded.

## One-million-line corpus

`mega.py` generates a fresh, exactly one-million-line workspace per language (500
modules of 2,000 lines) for every case. It measures a unique definition search, a
cross-module rename, and deletion of a definition plus all call sites:

```text
python benchmarks/llm_edit/mega.py --agent-command "YOUR_AGENT --prompt-file {prompt_file}"
```

## Semantic migration corpus

`semantic.py` uses the same 1M-LOC shape but adds real definitions, imports,
constructors, field accesses, and distributed callers. Its isolated tasks are:

- add a parameter and migrate a cross-module function signature;
- rename `Sensor.sensor_id: u32` to `Sensor.id: u64`, including explicit conversions;
- remove a module, its imports, and all call sites.

```text
python benchmarks/llm_edit/semantic.py --agent-command "YOUR_AGENT --prompt-file {prompt_file}"
```

Use `--context-files 20 --context-lines 10000` to give the agent a context budget
(these are advisory for generic shell agents). The JSON report includes Codex CLI's
reported token-use counter when the configured agent emits one. Compare token figures
only between runs using the same agent version, model, and settings.

The semantic JSON report also includes transcript-derived activity counts: tool calls,
searches, direct read commands, patches, observed source paths, and returned generated
filler lines. These are observable proxies for retrieval behavior, not a hard audit of
every source byte the agent read.

## Hard-capped retrieval corpus

`hard_context.py` keeps its randomized 1M-LOC corpus in the benchmark process's
memory. The agent receives only a controlled `search`/`read` client, and a local
server rejects reads beyond the configured line budget. The agent submits exact
replacements in `edits.json`, which the harness applies to and validates against the
hidden corpus. This suite tests a cross-module signature migration:

```text
python benchmarks/llm_edit/hard_context.py --read-limit 500 --trials 3 --agent-command "YOUR_AGENT --prompt-file {prompt_file}"
```

Pass `--neper-card` to give Neper cases [`docs/llm-neper-card.md`](../../docs/llm-neper-card.md),
a compact guide derived from the normative grammar and `neper index --json` contracts.
This creates an `e+card` arm while keeping Rust unchanged.

Pass both `--neper-card --rust-card` for a symmetric language-plus-structured-index
comparison. The Rust card is [`docs/llm-rust-card.md`](../../docs/llm-rust-card.md).

Use `--languages e,rs,js,ts` with all four card flags to compare Neper, Rust,
JavaScript, and TypeScript under the same randomized hidden corpus and read limit.
The JavaScript and TypeScript cards are
[`docs/llm-javascript-card.md`](../../docs/llm-javascript-card.md) and
[`docs/llm-typescript-card.md`](../../docs/llm-typescript-card.md).

For semantic tasks intended to test Neper's design claims rather than a symmetric
index control, see [the semantic-advantage matrix](neper_advantage_matrix.md). It
requires the real `neper index`, parser, and formatter executables; this repository
currently documents those contracts but does not include their implementation.
