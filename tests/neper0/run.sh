#!/usr/bin/env sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
neper="$repo/build-linux/neper"
test_build="$repo/build-linux/tests/neper0"
"$repo/scripts/build-bootstrap.sh" >/dev/null
mkdir -p "$test_build"

test "$("$neper" run "$repo/tests/neper0/range.e" --output "$test_build/range")" = 'range ok'

set +e
scope_error=$("$neper" build "$repo/tests/neper0/scope-error.e" --output "$test_build/scope-error" 2>&1)
scope_status=$?
set -e
test "$scope_status" -eq 1
printf '%s' "$scope_error" | grep -q '7:23: error\[E-NAME-9999\]'

set +e
break_error=$("$neper" build "$repo/tests/neper0/break-error.e" --output "$test_build/break-error" 2>&1)
break_status=$?
set -e
test "$break_status" -eq 1
printf '%s' "$break_error" | grep -q '4:5: error\[E-TYPE-9999\]'

printf '%s\n' 'neper-0 Linux control-flow tests passed'
