"""Run the chart benchmark: Neper (chart_bench.e) against matplotlib (mpl_bench.py).

    python benchmarks/charts/run.py <neper-self> [runs]

Builds the Neper program with the given compiler, runs each side `runs` times
(default 5) from the repository root, keeps the median of every pass, and
writes benchmarks/charts/results/<host>.json. ggplot2, base R graphics and lattice
(r_bench.R) are measured when an Rscript is found (on PATH, or under the R
installation directories of Windows and Linux) and the packages ggplot2,
lattice and svglite load; otherwise the result carries "r": null and says why.
"""
import json
import os
import platform
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def parse(output):
    rows = {}
    for line in output.strip().splitlines():
        name, charts, ms, size = line.split()
        rows[name] = (int(charts), float(ms), int(size))
    return rows


def measure(command, runs):
    samples = []
    for _ in range(runs):
        started = time.perf_counter()
        done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        wall = (time.perf_counter() - started) * 1000.0
        if done.returncode != 0:
            sys.exit(f"{command[-1]} failed with exit {done.returncode}:\n{done.stdout}{done.stderr}")
        rows = parse(done.stdout)
        rows["process"] = (0, wall, 0)
        samples.append(rows)
    return {name: {"charts": samples[0][name][0],
                   "ms": statistics.median(s[name][1] for s in samples),
                   "bytes": samples[0][name][2]}
            for name in samples[0]}


def find_rscript():
    """Rscript on PATH or in the usual install directories, or None."""
    found = shutil.which("Rscript")
    if found:
        return found
    roots = [os.environ.get("ProgramFiles", r"C:Program Files") + os.sep + "R", "/usr/lib/R/bin", "/usr/local/lib/R/bin", "/opt/R"]
    for root in roots:
        path = Path(root)
        candidates = sorted(path.glob("R-*/bin/Rscript.exe"), reverse=True) + sorted(path.glob("*/bin/Rscript"), reverse=True)
        candidates += [path / "Rscript"] if (path / "Rscript").exists() else []
        for candidate in candidates:
            if candidate.exists():
                return str(candidate)
    return None


def measure_r(runs):
    """The r_bench.R rows (median of `runs`), or (None, reason)."""
    rscript = find_rscript()
    if rscript is None:
        return None, "no Rscript found: ggplot2, base R graphics and lattice need an R installation"
    probe = subprocess.run([rscript, "-e", "for (p in c('ggplot2','lattice','svglite')) library(p, character.only = TRUE); cat(R.version.string)"],
                           capture_output=True, text=True)
    if probe.returncode != 0:
        return None, "R is installed (" + rscript + ") but its packages are not: " + probe.stderr.strip().splitlines()[-1]
    rows = measure([rscript, str(HERE / "r_bench.R")], runs)
    rows["version"] = probe.stdout.strip().splitlines()[-1]
    return rows, ""


def main():
    compiler, runs = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 5
    host = "windows" if platform.system() == "Windows" else "linux"
    exe = ROOT / "build" / "charts" / ("chart_bench.exe" if host == "windows" else "chart_bench")
    exe.parent.mkdir(parents=True, exist_ok=True)
    built = subprocess.run([compiler, "emit-executable", "benchmarks/charts/chart_bench.e", ".", "x64", host, str(exe)],
                           cwd=ROOT, capture_output=True, text=True)
    if built.stdout.strip() != "executable written":
        sys.exit(f"build failed: {built.stdout}{built.stderr}")
    import matplotlib
    result = {
        "host": host,
        "machine": platform.processor() or platform.machine(),
        "python": platform.python_version(),
        "matplotlib": matplotlib.__version__,
        "runs": runs,
        "neper": measure([str(exe)], runs),
        "matplotlib_results": measure([sys.executable, str(HERE / "mpl_bench.py")], runs),
    }
    r_rows, r_reason = measure_r(runs)
    result["r"] = r_rows
    if r_rows is None:
        result["r_unavailable"] = r_reason
    out = HERE / "results" / f"{host}.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8", newline="\n")
    neper, mpl = result["neper"], result["matplotlib_results"]
    print(f"{host}, {runs} runs, median ms per chart (200 charts per pass)")
    for name in ("svg", "png"):
        n, m = neper[name]["ms"] / 200, mpl[name]["ms"] / 200
        print(f"  {name}: neper {n:.2f}  matplotlib {m:.2f}  ratio {m / n:.1f}x"
              f"  bytes/chart neper {neper[name]['bytes'] // 200} matplotlib {mpl[name]['bytes'] // 200}")
    print(f"  layout only: neper {neper['layout']['ms'] / 200:.3f}; raster only: neper {neper['raster']['ms'] / 200:.2f}"
          f"; matplotlib import {mpl['import']['ms']:.0f} ms")
    print(f"  whole process: neper {neper['process']['ms']:.0f} ms  matplotlib {mpl['process']['ms']:.0f} ms")
    if r_rows is None:
        print(f"  R side not measured: {r_reason}")
    else:
        for package in ("ggplot2", "base", "lattice"):
            for name in ("svg", "png"):
                row = r_rows[f"{package}_{name}"]
                n = neper[name]["ms"] / 200
                print(f"  {name}: {package} {row['ms'] / 200:.2f} ms ({row['ms'] / 200 / n:.1f}x neper)  bytes/chart {row['bytes'] // 200}")


if __name__ == "__main__":
    main()
