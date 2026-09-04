#!/usr/bin/env sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
neper="$repo/build-linux/neper"
test_build="$repo/build-linux/tests/neper0"
"$repo/scripts/build-bootstrap.sh" >/dev/null
mkdir -p "$test_build"

test "$("$neper" run "$repo/tests/neper0/range.e" --output "$test_build/range")" = 'range ok'
test "$("$neper" run "$repo/tests/neper0/array.e" --output "$test_build/array")" = 'array ok'
test "$("$neper" run "$repo/tests/neper0/slice-mutate.e" --output "$test_build/slice-mutate" -- original)" = 'slice mutation ok'
test "$("$neper" run "$repo/tests/neper0/slice-iterate.e" --output "$test_build/slice-iterate" -- 'slice iteration ok')" = 'slice iteration ok'
test "$("$neper" run "$repo/tests/neper0/slice.e" --output "$test_build/slice")" = 'slice ok'

set +e
slice_bounds=$("$neper" run "$repo/tests/neper0/slice-bounds.e" --output "$test_build/slice-bounds" 2>&1)
slice_bounds_status=$?
set -e
test "$slice_bounds_status" -eq 134
printf '%s' "$slice_bounds" | grep -q 'trap\[bounds\]'

set +e
array_bounds=$("$neper" run "$repo/tests/neper0/array-bounds.e" --output "$test_build/array-bounds" 2>&1)
array_bounds_status=$?
set -e
test "$array_bounds_status" -eq 134
printf '%s' "$array_bounds" | grep -q 'trap\[bounds\]'

set +e
count_error=$("$neper" build "$repo/tests/neper0/array-count-error.e" --output "$test_build/array-count-error" 2>&1)
count_status=$?
set -e
test "$count_status" -eq 1
printf '%s' "$count_error" | grep -q '4:18: error\[E-TYPE-9999\]'

set +e
mutation_error=$("$neper" build "$repo/tests/neper0/array-mutation-error.e" --output "$test_build/array-mutation-error" 2>&1)
mutation_status=$?
set -e
test "$mutation_status" -eq 1
printf '%s' "$mutation_error" | grep -q '5:5: error\[E-TYPE-9999\]'

set +e
binding_error=$("$neper" build "$repo/tests/neper0/for-binding-error.e" --output "$test_build/for-binding-error" 2>&1)
binding_status=$?
set -e
test "$binding_status" -eq 1
printf '%s' "$binding_error" | grep -q '6:9: error\[E-TYPE-9999\]'

set +e
slice_mutation_error=$("$neper" build "$repo/tests/neper0/slice-mutation-error.e" --output "$test_build/slice-mutation-error" 2>&1)
slice_mutation_status=$?
set -e
test "$slice_mutation_status" -eq 1
printf '%s' "$slice_mutation_error" | grep -q '6:5: error\[E-TYPE-9999\]'

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

printf '%s\n' 'neper-0 Linux tests passed'
