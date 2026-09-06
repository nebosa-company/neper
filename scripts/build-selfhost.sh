#!/usr/bin/env sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bootstrap=$($repo/scripts/build-bootstrap.sh)
output="$repo/build-linux/neper-self"
"$bootstrap" build "$repo/src/main.e" --arena 1g --output "$output" >/dev/null

printf '%s\n' "$output"
