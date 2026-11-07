#!/usr/bin/env sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bootstrap=$($repo/scripts/build-bootstrap.sh)
output="$repo/build/linux/neper-self"
# No `--arena`: the size is a lazily-committed ceiling, so the compiler grows into what it
# needs instead of failing against an arbitrary cap. See the note in tests/selfhost/run.sh.
"$bootstrap" build "$repo/src/main.e" --output "$output" >/dev/null

printf '%s\n' "$output"
