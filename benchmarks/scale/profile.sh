#!/bin/bash
# Rebuild the Linux compiler from the current src, profile it on a program, and map the
# samples to functions through the image's own symbol table.
#   build/profile.sh build/sc200k/src/main.e [arena]
set -e
exec > /mnt/d/repos/neper/build/profile_log.txt 2>&1
cd /mnt/d/repos/neper
program=${1:-build/sc200k/src/main.e}
arena=${2:-2047m}
scripts/build-bootstrap.sh > /dev/null 2>&1
build/linux/neper build src/main.e --arena 1g --output build/linux/neper-try > /dev/null 2>&1
build/linux/neper-try emit-executable src/main.e /mnt/d/repos/neper x64 linux build/linux/neper-prof --arena $arena > /dev/null 2>&1
chmod +x build/linux/neper-prof
dir=$(dirname "$(dirname "$program")")
cd "$dir"
sudo /usr/lib/linux-tools/6.8.0-139-generic/perf record -F 499 -o /tmp/perf.data /mnt/d/repos/neper/build/linux/neper-prof emit-executable src/main.e /mnt/d/repos/neper x64 linux m --time 2>&1 | grep '^time' | tr '\n' ' '
echo
sudo /usr/lib/linux-tools/6.8.0-139-generic/perf report -i /tmp/perf.data --no-children --stdio --sort sym 2>/dev/null | grep '%' | head -400 > /mnt/d/repos/neper/build/perf_top.txt
