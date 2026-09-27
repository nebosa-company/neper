#!/usr/bin/env bash
# The Linux suite from a copy on WSL's own disk: run from /mnt/d, every file the suite
# reads or writes crosses to Windows and back, and it takes about four times as long.
#
#   bash scripts/run-linux-suite.sh [suite script under tests/selfhost, default run.sh]
#
# The copy is ~/neper-suite/<checkout name>; build/linux lives there, not in the checkout.
set -eu
src=$(cd "$(dirname "$0")/.." && pwd)
dst=~/neper-suite/$(basename "$src")
mkdir -p "$dst"
rsync -a --delete --exclude=/build --exclude=/.git --exclude=.neper/ "$src/" "$dst/"
exec bash "$dst/tests/selfhost/${1:-run.sh}"
