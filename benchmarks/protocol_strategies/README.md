# Protocol strategy measurement

`measure.py` generates two equivalent 256-type programs: one selects `cmp`
implicitly through `T.cmp`, and one passes the same operation as a comptime
function strategy. It builds each once to warm filesystem caches, then five times
with one worker and records:

- the compiler-reported `check bodies` phase distribution;
- the sum of `instance-cost` NIR instructions and machine-code bytes; and
- final executable bytes.

Run from the repository root:

```text
python benchmarks/protocol_strategies/measure.py --compiler build/windows/neper-self.exe --repo . --host windows --out benchmarks/protocol_strategies/results/d730-windows.json
python3 benchmarks/protocol_strategies/measure.py --compiler build/linux/neper-self --repo . --host linux --revision REV --out benchmarks/protocol_strategies/results/d730-linux.json
```

`--revision` is only needed when a worktree's `.git` pointer uses a host path the
measurement environment cannot resolve, such as WSL reading a Windows worktree.

The D730 reports show identical specialization bytes and executable sizes between
the two strategies. The explicit form's median body-check time was 1 ms lower on
Windows and 3 ms lower on Linux; these small distributions establish no speed
claim, only that the explicit mechanism did not add a measured check-time or
code-size cost on this fixed equivalent workload.
