#!/bin/bash
# Profile `check-file` of the compiler's own root by the Linux release compiler: the
# front end and the checker alone, mapped to functions. Run from WSL via pwsh.
set -e
exec > /mnt/d/repos/neper-cot/build/profile_check_log.txt 2>&1
cd /mnt/d/repos/neper-cot
chmod +x build/linux/neper-own
for i in 1 2 3; do /usr/bin/time -f 'check-file %e s' build/linux/neper-own check-file src/main.e /mnt/d/repos/neper-cot x64 linux; done
sudo -n /usr/lib/linux-tools/6.8.0-139-generic/perf record -F 4999 -o /tmp/perf_check.data build/linux/neper-own check-file src/main.e /mnt/d/repos/neper-cot x64 linux
sudo -n /usr/lib/linux-tools/6.8.0-139-generic/perf report -i /tmp/perf_check.data --no-children --stdio --sort sym 2>/dev/null | grep '%' | head -8000 > /mnt/d/repos/neper-cot/build/perf_check_top.txt
python3 benchmarks/scale/symmap.py build/linux/neper-own build/perf_check_top.txt 45
echo profiled
