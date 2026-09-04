#!/usr/bin/env sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build="$repo/build-linux"

mkdir -p "$build/lib/e"
${CC:-cc} -std=c99 -Wall -Wextra -Wpedantic -O2 \
    -o "$build/neper" "$repo/bootstrap/neper.c"
cp "$repo/lib/e/mem.e" "$build/lib/e/mem.e"
cp "$repo/lib/e/io.e" "$build/lib/e/io.e"
printf '%s\n' "$build/neper"
