# GP-09 / GP-10 performance corpus

The five implementations use the same fixed algorithms and inputs. `run.py`
alternates builds and executions by round, rejects any output mismatch, and records
all samples plus p50/p95 compile time, runtime, peak RSS and image size.

From Linux or WSL:

```sh
python3 benchmarks/gp/run.py \
  --neper /path/to/linux/neper \
  --repo "$PWD" \
  --go /path/to/go \
  --runs 7 \
  --out benchmarks/gp/results/linux.json
```

GP-09 encodes and decodes 4,194,317 bytes eight times. Neper's body uses explicit
`Vec[u8, 16]` operations and masks, with a scalar tail; all implementations validate
the same lower-case Base16 output through the final checksum.

GP-10 applies `y[i] = 3*x[i] + y[i]` to 1,048,576 `u32` elements sixteen times.
Neper runs the same kernel on `.Cpu` and `.Vulkan`; C, C++, Rust and Go are CPU
comparators. Every implementation must print the same checksum before timing counts.
