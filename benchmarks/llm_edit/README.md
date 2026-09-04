# LLM search/edit benchmark

This benchmark tests the claim in spec §14 that Neper source is easier for a model
to search and amend reliably. It gives the same search and surgical-edit requests to
fresh copies of `examples/sample.e` and `examples/sample.rs`, then checks exact
answers, required replacements, stale references, and unrelated changed lines.

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
