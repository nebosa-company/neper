#!/bin/bash
# Profile a warm release build of the compiler after a one-line body edit in tool.e
# (the copy under build/fuzz/edit): what a rebuild of one module costs, by function.
set -e
exec > /mnt/d/repos/neper-cot/build/profile_edit_log.txt 2>&1
cd /mnt/d/repos/neper-cot
chmod +x build/linux/neper-own
rm -rf build/fuzz/edit_linux && mkdir -p build/fuzz/edit_linux && cp -r src build/fuzz/edit_linux/src
cd build/fuzz/edit_linux
../../linux/neper-own emit-executable src/main.e /mnt/d/repos/neper-cot x64 linux out --release --arena 14g --incremental > /dev/null
echo "// edit $RANDOM" >> src/tool.e
../../linux/neper-own emit-executable src/main.e /mnt/d/repos/neper-cot x64 linux out --release --arena 14g --incremental --time 2>&1 | grep '^time' | tr '\n' ' '
echo
echo "// edit $RANDOM" >> src/tool.e
sudo -n /usr/lib/linux-tools/6.8.0-139-generic/perf record -F 9999 -o /tmp/perf_edit.data ../../linux/neper-own emit-executable src/main.e /mnt/d/repos/neper-cot x64 linux out --release --arena 14g --incremental --time 2>&1 | grep '^time' | tr '\n' ' '
echo
sudo -n /usr/lib/linux-tools/6.8.0-139-generic/perf report -i /tmp/perf_edit.data --no-children --stdio --sort sym 2>/dev/null | grep '%' | head -8000 > /mnt/d/repos/neper-cot/build/perf_edit_top.txt
cd /mnt/d/repos/neper-cot
python3 benchmarks/scale/symmap.py build/linux/neper-own build/perf_edit_top.txt 40
grep '\[k\]' build/perf_edit_top.txt | head -8
echo profiled
