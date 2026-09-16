#!/bin/bash
# Profile a WARM release build of the compiler by itself (nothing changed, artifacts
# kept): the link, the artifact reads and the executable write. Run from WSL.
set -e
exec > /mnt/d/repos/neper-cot/build/profile_warm_log.txt 2>&1
cd /mnt/d/repos/neper-cot
chmod +x build/linux/neper-own
rm -rf .neper
build/linux/neper-own emit-executable src/main.e /mnt/d/repos/neper-cot x64 linux build/linux/neper-own2 --release --arena 14g --incremental --time 2>&1 | grep '^time' | tr '\n' ' '
echo
build/linux/neper-own emit-executable src/main.e /mnt/d/repos/neper-cot x64 linux build/linux/neper-own2 --release --arena 14g --incremental --time 2>&1 | grep '^time' | tr '\n' ' '
echo
sudo -n /usr/lib/linux-tools/6.8.0-139-generic/perf record -F 4999 -o /tmp/perf_warm.data build/linux/neper-own emit-executable src/main.e /mnt/d/repos/neper-cot x64 linux build/linux/neper-own2 --release --arena 14g --incremental --time 2>&1 | grep '^time' | tr '\n' ' '
echo
sudo -n /usr/lib/linux-tools/6.8.0-139-generic/perf report -i /tmp/perf_warm.data --no-children --stdio --sort sym 2>/dev/null | grep '%' | head -8000 > /mnt/d/repos/neper-cot/build/perf_warm_top.txt
python3 benchmarks/scale/symmap.py build/linux/neper-own build/perf_warm_top.txt 40
grep '\[k\]' build/perf_warm_top.txt | head -12
echo profiled
