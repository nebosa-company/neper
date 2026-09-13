# LLM generation-cost smoke benchmark

Neper vs Rust on ten tiny tasks (`tasks/<name>/{neper.e,rust.rs,expected.txt}`), measuring
per language: source tokens, compile time and success, run time and correctness, and
executable size. Run from the repository root:

```text
python benchmarks/llm_gen/run.py --trials 3
```

This is a **smoke run**, not the M2.5 evaluation. It uses reference solutions written
first-try by one author and one tokenizer (tiktoken `cl100k_base`, a GPT tokenizer, not
Claude's), so it measures **source density and toolchain cost**. It does not measure a live
model's few-shot success or repair loop -- that is the H12 evaluation in
[`docs/post-m2-llm-hardening.md`](../../docs/post-m2-llm-hardening.md), which also
requires baselines. The sibling [`llm_edit`](../llm_edit/README.md) suite measures the
different claim in spec §14 (search/edit reliability).

## Result (2026-09-13, x64-windows, 3 trials, both languages in debug mode)

| | tokens (10 tasks) | correct | median compile | median run | median executable |
|---|---:|:-:|---:|---:|---:|
| Neper (`neper-try`, C bootstrap) | **941** | 10/10 | 465 ms | 10.6 ms | **24 KB** |
| Rust (`rustc` 1.98) | **431** | 10/10 | 409 ms | 15.0 ms | 4.97 MB |

**The "fewer tokens" hypothesis does not hold here: Neper costs ~2.2x the source tokens of
Rust for the same programs.** The tax is concrete and mostly fixed-cost, so it dominates tiny
programs and would shrink on larger ones:

- Mandatory `main` boilerplate -- `use e.mem`, `use e.io`, `fn main(a: *mem.Arena, args: []str)
  -> err`, `ret ok` -- is ~30 tokens per program against Rust's `fn main() {`. `hello` is 38 vs 10.
- Every integer literal carries its type: `1i32`, `0usize`, `101i32` (2-3 tokens each) where Rust
  infers `1`.
- No `else if` (nested `} else { if`), and no iterator combinators, so `(1..=100).sum()` or
  `.chars().filter(..).count()` become explicit loops. This partly measures library richness,
  not syntax.
- Tokenizer bias: `cl100k_base` was trained on a great deal of Rust-shaped code and none of
  Neper's, so Neper's spellings may tokenize less efficiently. Re-run with Claude's tokenizer
  before treating the ratio as exact.

What Neper wins is **toolchain, not generation cost**: executables ~200x smaller, run time a
third lower, compile time comparable -- none of which is an LLM-friendliness claim.

First-try compile rate, the one few-shot signal here: Rust 10/10, Neper 9/10 -- the miss was
the array literal (`[_]i32{ 3i32, 9i32 }`, not `[3, 9]`), the shape a Rust-trained model
reaches for. Rust is in every model's training data; Neper is in none, which is the confound
the full evaluation exists to control.

The cheapest token wins are language decisions, not benchmark work: literal-suffix inference
where the type is already fixed, and `else if`. Neither is taken here.
