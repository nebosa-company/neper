#!/bin/bash
# Profile the current Linux compiler (release) building ITSELF (release, 8 workers), and
# map samples to functions. Run from WSL: bash /mnt/d/repos/neper-cot/build/profile_own.sh
set -e
exec > /mnt/d/repos/neper-cot/build/profile_own_log.txt 2>&1
cd /mnt/d/repos/neper-cot
SELF=build/linux/tests/selfhost/neper-self
chmod +x $SELF
$SELF emit-executable src/main.e /mnt/d/repos/neper-cot x64 linux build/linux/neper-own --release --arena 14g
chmod +x build/linux/neper-own
rm -rf .neper
build/linux/neper-own emit-executable src/main.e /mnt/d/repos/neper-cot x64 linux build/linux/neper-own2 --release --arena 14g --time 2>&1 | grep '^time' | tr '\n' ' '
echo
rm -rf .neper
sudo -n /usr/lib/linux-tools/6.8.0-139-generic/perf record -F 1999 -o /tmp/perf_own.data build/linux/neper-own emit-executable src/main.e /mnt/d/repos/neper-cot x64 linux build/linux/neper-own2 --release --arena 14g --time 2>&1 | grep '^time' | tr '\n' ' '
echo
sudo -n /usr/lib/linux-tools/6.8.0-139-generic/perf report -i /tmp/perf_own.data --no-children --stdio --sort sym 2>/dev/null | grep '%' | head -8000 > /mnt/d/repos/neper-cot/build/perf_own_top.txt
python3 benchmarks/scale/symmap.py build/linux/neper-own build/perf_own_top.txt 40
echo profiled
