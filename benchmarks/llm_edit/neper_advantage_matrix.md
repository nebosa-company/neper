# Neper semantic-advantage benchmark matrix

This matrix measures the claims that a restricted language plus a machine-readable
index reduces LLM uncertainty. Every case uses a randomized 1M-LOC corpus, exact
server-side oracle, and a hard source-read budget. Report correctness first, then
net session tokens, source lines read, tool calls, and elapsed time.

| Case | Corpus condition | Required proof | Neper capability under test |
|---|---|---|---|
| Ambiguous symbol | 40 same-spelling functions in different modules; only one resolved target has eight callers | Edit only records whose `target_id` equals the selected definition; no decoy edits | `index --json` resolved `reference.target_id` |
| Conversion-aware field migration | `Sensor.sensor_id: u32` occurs in constructors, reads, write sites, and a similarly named unrelated field | Rename to `id: u64`, update all resolved field references, insert only explicit conversions | No implicit conversions; field/reference records |
| Re-export and alias API migration | API is imported via module aliases and re-export layers; decoy local functions share its spelling | Change one public signature and exactly its resolved call graph | Qualified references; import/reference origins |
| Feature deletion | A feature owns a module, imports, calls, tests, and generated filler; unrelated textual lookalikes remain | Remove the feature graph while retaining decoys; index contains no target references afterward | Total reference inventory and no hidden textual generation |
| Parser/formatter verification | Correct edit is deliberately reformatted and one candidate contains a syntax error | `parse --json` has no diagnostic records and `fmt --check` succeeds | Lossless parse stream and canonical formatter |

## Tool policy

For Neper, invoke the actual tools when available:

```text
neper index --json
neper parse --json
neper fmt --check
```

The harness must persist their JSONL transcript and verify that every edited Neper
reference came from a resolved index record. Rust, JavaScript, and TypeScript should
use their native language-server/compiler interfaces when available; do not give them
a synthetic Neper-format index in this suite. This intentionally measures the
language-and-tooling package, unlike the earlier symmetric-index control benchmark.

## Acceptance rule

Run 20 randomized seeds per case and language. A row is comparable only if its
correctness rate is 100%; otherwise report correctness and exclude its token/time
figures from an efficiency ranking. Compare medians and paired seed deltas, not just
means. Treat source lines returned by a tool as retrieval volume, not as a token
counter.
