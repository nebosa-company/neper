# GP-09 / GP-10 performance result

This is the first performance-language result required by
[`general-purpose-verification.md`](general-purpose-verification.md). It is a
comparison, not a claim that every backend is equally optimised.

The source revision is `54923ebd2dedce88221951411dd23be57fe33ecd` and the raw,
reproducible record is
[`benchmarks/gp/results/linux-wsl.json`](../benchmarks/gp/results/linux-wsl.json).
The host was WSL2 Linux 6.18 on a 12th Gen Intel Core i5-12500H. Toolchains were
GCC/G++ 13.3.0, Rust 1.97.1, Go 1.27.1, and the self-hosted Neper compiler. Every
cell had one warm-up followed by seven alternated runs. Times are milliseconds;
RSS is the peak of a separate oracle-checked run.

## GP-09 — SIMD Base16 codec

Each program lower-case-hex encodes and decodes 4,194,317 bytes eight times and
prints checksum `534775349`. Neper uses explicit 16-byte vectors and masks with a
scalar tail; the comparison implementations use the same encode/decode algorithm.

| implementation | compile p50 | compile p95 | runtime p50 | runtime p95 | peak RSS | image |
|---|---:|---:|---:|---:|---:|---:|
| C | 163.7 | 177.1 | 50.4 | 54.6 | 17.4 MiB | 15.8 KiB |
| C++ | 255.3 | 298.3 | 51.4 | 55.1 | 19.3 MiB | 16.3 KiB |
| Rust | 291.5 | 337.0 | 42.8 | 47.0 | 17.9 MiB | 4,267.9 KiB |
| Go | 1,513.8 | 1,749.7 | 69.7 | 77.4 | 18.6 MiB | 1,484.2 KiB |
| Neper | 178.4 | 183.4 | 1,576.2 | 1,692.9 | 16.0 MiB | 28.4 KiB |

The result exposes the remaining GP-09 optimisation gap rather than hiding it:
vector nibble classification is packed, but the interleave and pair assembly remain
scalar lane loops. M4's workload-backed vector optimisation owns that performance
work; correctness and output equivalence pass here.

## GP-10 — CPU/GPU numerical workload

Each program applies `y[i] = 3*x[i] + y[i]` to 1,048,576 `u32` elements sixteen
times and prints checksum `25745686528`. Neper runs the same kernel through its CPU
debug backend and WSL Vulkan; C, C++, Rust and Go are CPU comparators.

| implementation | compile p50 | compile p95 | runtime p50 | runtime p95 | peak RSS | image |
|---|---:|---:|---:|---:|---:|---:|
| C | 159.8 | 165.7 | 3.7 | 5.0 | 9.4 MiB | 15.7 KiB |
| C++ | 254.5 | 306.2 | 4.4 | 4.6 | 11.3 MiB | 16.1 KiB |
| Rust | 219.0 | 240.4 | 6.4 | 7.0 | 9.9 MiB | 4,257.0 KiB |
| Go | 1,552.1 | 1,601.1 | 11.3 | 12.4 | 10.3 MiB | 1,484.2 KiB |
| Neper CPU | 201.5 | 205.0 | 1,910.9 | 1,992.8 | 17.6 MiB | 279.8 KiB |
| Neper Vulkan | 201.5 | 205.0 | 59.8 | 66.2 | 103.0 MiB | 279.8 KiB |

The CPU backend is the checked, serial debugger defined by D38, not an optimised
fallback; its number records that cost. The Vulkan cell includes process startup,
loader/device creation, uploads and download, which is the complete public workload.

## Reproduce

```sh
python3 benchmarks/gp/run.py \
  --neper /path/to/linux/neper \
  --repo "$PWD" \
  --go /path/to/go \
  --runs 7 \
  --out benchmarks/gp/results/linux-wsl.json
```

The runner refuses a mismatched or unstable checksum before writing the result.
