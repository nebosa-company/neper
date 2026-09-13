# Generation-cost benchmark at scale: Neper vs Rust, Go, JavaScript, TypeScript

One program, five languages. The program is the shape machine-generated code actually
takes -- thousands of small functions, not one big one:

    leaf_i(x) = (x * 7 + 13 + i) % 1009      64-bit, max 1009, never overflows
    group_g() = sum of leaf_{g*100+j}(j), j in 0..100
    main()    = sum of every group_g(), printed

`G` groups means `100*G` leaf functions. Every language prints the same checksum,
verified against a Python oracle in `spec.py`. Arithmetic stays small on purpose so
Neper's checked overflow (§11) never trips and no language needs wrapping operators.

    python run.py --groups 198 --trials 3

## Headline: Neper cannot compile 100k lines

The target was ~100,000 lines of Neper. It does not get there. Neper caps at about
**14,700 lines (2,900 functions)**; one more group fails. The other four compile the
same program without complaint.

| | lines | tokens | correct | median compile | median run | executable |
|---|---:|---:|:-:|---:|---:|---:|
| **Neper** | 100,196 | 893,989 | **no** | **capacity** | -- | -- |
| Rust | 40,594 | 834,759 | yes | 19,241 ms | 14.0 ms | 12,716,109 |
| Go | 40,598 | 733,779 | yes | **764 ms** | 12.3 ms | 2,533,888 |
| JavaScript | 40,592 | **674,566** | yes | n/a | 221.6 ms | 1,442,765 |
| TypeScript | 40,592 | 773,764 | yes | 2,114 ms | 252.6 ms | 1,522,771 |

Neper's failure is not a syntax error, though that is what it prints:

    neper.e:15422:2: error[E-SYNTAX-9999]: unexpected end of line

The parse tables are fixed-size and program-wide, allocated in `init_cli_graph` and its
neighbours (`src/main.e:1357`): 65,536 `syntax.Node`, 524,288 `syntax.Child`, 131,072
`lex.Token`, 16,384 `resolve.Symbol`, 4,096 `check.Function`. The node table fills at
source line 15,422 and the parser reports the next token as a syntax error. **A capacity
limit that blames the user's source is the worst kind of diagnostic**, and it is the same
failure mode recorded three times before in this project.

Raising the constants is not a one-line change: the compiler's own arena is fixed at
build time (1 GB, with a measured 388 MB peak for the self-host build), and the tables
above would add roughly 370 MB of reservations. That has to be done and then verified
against the full suite, which is why it is written down here rather than attempted.

## At the largest scale Neper reaches (G=29, 2,900 functions)

The honest five-way comparison, since it is the only scale all five share:

| | lines | tokens | correct | median compile | median run | executable |
|---|---:|---:|:-:|---:|---:|---:|
| Neper | 14,682 | 128,419 | yes | 5,448 ms | **9.1 ms** | 2,971,648 |
| Rust | 5,949 | 119,720 | yes | 1,790 ms | 11.0 ms | 6,097,631 |
| Go | 5,953 | 104,930 | yes | **924 ms** | 14.3 ms | 2,498,048 |
| JavaScript | 5,947 | **96,248** | yes | n/a | 83.7 ms | **204,143** |
| TypeScript | 5,947 | 110,777 | yes | 535 ms | 90.5 ms | 215,873 |

## What the numbers say

**Tokens -- Neper is the most expensive of the five.** For the identical program it costs
+7% over Rust, +16% over TypeScript, +22% over Go and +33% over JavaScript. It needs 2.5x
the *lines* of any other language, because a function body cannot be written on one line
the way `fn leaf(x: i64) -> i64 { ... }` can in Rust or Go. The token gap is much smaller
than the line gap -- braces and newlines are cheap tokens -- but it points the same way.
This is the same ~2x-ish result the small-program benchmark found, and scale does not
rescue it: the per-function overhead is structural, not fixed cost that amortises.

**Compile speed is not a Neper win.** Per function it is the slowest of the compiled
three: at 2,900 functions Neper takes 5.4 s against Rust's 1.8 s and Go's 0.9 s. Go is the
outlier in the other direction -- 764 ms for 20,000 functions, essentially flat from 200
functions to 20,000, while Rust degrades steeply (1.5 s -> 19.2 s).

**Run time is a Neper win**, but a small one in absolute terms: 9.1 ms against 11-14 ms
for Rust and Go. Node pays 84-253 ms, nearly all of it interpreter startup.

**Executable size: the small-binary advantage disappears at scale.** On tiny programs
Neper emits 24 KB against Rust's 5 MB. Here it is 2.97 MB against Go's 2.50 MB -- Go's
runtime is a fixed cost that stops mattering, and Neper's output grows past it. Rust
reaches 12.7 MB at 100k lines.

## Agentic cost (n=1, self-measured -- read with suspicion)

Wall time to author each emitter, and the tool calls needed to get a first correct compile:

| | authoring | emitter tokens | tool calls to first correct compile |
|---|---:|---:|---|
| Neper | 8.1 s | 271 | ~12, and a compiler fix |
| Rust | 5.7 s | 224 | 2 -- first try |
| Go | 5.6 s | 221 | 2 -- first try (needs a `go.mod`) |
| JavaScript | 5.2 s | 192 | 2 -- first try |
| TypeScript | 7.1 s | 198 | 2 -- first try |

The wall-clock column is noise at this resolution. The tool-call column is not: the four
mainstream languages compiled the program the moment it was written, and Neper needed six
times the interaction plus a change to the compiler. Both Neper traps are the kind a model
walks into precisely because it writes idiomatic code:

1. `ret (x * 7 + 13 + i) % 1009` did not parse. After `ret`, a `(` was always read as the
   start of the multi-return tuple `ret (a, b)`, so a grouped expression could not carry a
   binary operator -- while the same expression in a `let` or an `if` was fine. Fixed
   (D247) by deciding tuple-vs-group on a top-level comma before the matching `)`.
   **Fixing it removed 79,200 tokens from this program, 10.3%**, because the leaf body
   collapsed from two lines to one.
2. `io.printf["{}\n"]` needs a literal backslash-n. Trivial once known, invisible before.

## Method and limits

- Windows 11, x64. Neper: `neper-try` (C bootstrap). Rust 1.98 `rustc -C debuginfo=0`
  (debug). Go 1.27.1 `go build`, installed to `D:\toolchains\go`. Node 24.19. TypeScript
  7.0.2 (`tsc`), then run on Node. Debug/default codegen throughout -- no `-O`, no LTO.
- Tokens are `cl100k_base` over the whole source file. **That tokenizer learned on a great
  deal of Rust, Go and JavaScript and none of Neper**, so it may spell Neper less
  efficiently than a fair encoder would. Treat the token ratios as indicative.
- Medians of 3 trials. JavaScript has no compile step; its "executable" is its source, and
  TypeScript's is the emitted `.js`.
- The machine was shared with another active build throughout, so absolute timings carry
  noise; the orders of magnitude do not.
- The agentic numbers are one run by one model that had already read the spec. They are
  evidence of where the traps are, not a measurement of model performance.
- This measures generation cost and toolchain behaviour on machine-shaped code. It is not
  the M2.5/H12 evaluation, which requires held-out tasks, live model generation, a repair
  loop and independent oracles.
