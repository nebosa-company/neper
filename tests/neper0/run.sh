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
test "$("$neper" run "$repo/tests/neper0/struct.e" --output "$test_build/struct")" = 'struct ok'

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

set +e
pointer_const_error=$("$neper" build "$repo/tests/neper0/pointer-const-error.e" --output "$test_build/pointer-const-error" 2>&1)
pointer_const_status=$?
set -e
test "$pointer_const_status" -eq 1
printf '%s' "$pointer_const_error" | grep -q '10:5: error\[E-TYPE-9999\]'

set +e
recursive_struct_error=$("$neper" build "$repo/tests/neper0/recursive-struct-error.e" --output "$test_build/recursive-struct-error" 2>&1)
recursive_struct_status=$?
set -e
test "$recursive_struct_status" -eq 1
printf '%s' "$recursive_struct_error" | grep -q '3:1: error\[E-TYPE-9999\]'

test "$("$neper" run "$repo/tests/neper0/aggregate-abi.e" --output "$test_build/aggregate-abi")" = 'aggregate abi ok'

set +e
aggregate_param_error=$("$neper" build "$repo/tests/neper0/aggregate-param-mutation-error.e" --output "$test_build/aggregate-param-mutation-error" 2>&1)
aggregate_param_status=$?
set -e
test "$aggregate_param_status" -eq 1
printf '%s' "$aggregate_param_error" | grep -q '10:5: error\[E-TYPE-9999\]'

test "$("$neper" run "$repo/tests/neper0/enum-union-switch.e" --output "$test_build/enum-union-switch")" = 'enum union switch ok'

set +e
exhaustive_error=$("$neper" build "$repo/tests/neper0/switch-exhaustive-error.e" --output "$test_build/switch-exhaustive-error" 2>&1)
exhaustive_status=$?
set -e
test "$exhaustive_status" -eq 1
printf '%s' "$exhaustive_error" | grep -q 'non-exhaustive switch; missing member `Two`'

set +e
enum_value_error=$("$neper" build "$repo/tests/neper0/enum-value-error.e" --output "$test_build/enum-value-error" 2>&1)
enum_value_status=$?
set -e
test "$enum_value_status" -eq 1
printf '%s' "$enum_value_error" | grep -q 'enum member value is outside its backing type'
printf '%s' "$enum_value_error" | grep -q 'duplicate enum backing value'

set +e
tag_trap=$("$neper" run "$repo/tests/neper0/tagged-payload-trap.e" --output "$test_build/tagged-payload-trap" 2>&1)
tag_trap_status=$?
set -e
test "$tag_trap_status" -eq 134
printf '%s' "$tag_trap" | grep -q 'trap\[tag\]'

set +e
enum_zero_error=$("$neper" build "$repo/tests/neper0/enum-zero-error.e" --output "$test_build/enum-zero-error" 2>&1)
enum_zero_status=$?
set -e
test "$enum_zero_status" -eq 1
printf '%s' "$enum_zero_error" | grep -q 'has no zero value'

test "$("$neper" run "$repo/tests/neper0/defer.e" --output "$test_build/defer")" = 'defer ok'

set +e
defer_try_error=$("$neper" build "$repo/tests/neper0/defer-try-error.e" --output "$test_build/defer-try-error" 2>&1)
defer_try_status=$?
set -e
test "$defer_try_status" -eq 1
printf '%s' "$defer_try_error" | grep -q 'try is not legal inside defer'

set +e
defer_value_error=$("$neper" build "$repo/tests/neper0/defer-value-error.e" --output "$test_build/defer-value-error" 2>&1)
defer_value_status=$?
set -e
test "$defer_value_status" -eq 1
printf '%s' "$defer_value_error" | grep -q 'deferred call returning a value'

set +e
defer_ret_error=$("$neper" build "$repo/tests/neper0/defer-ret-error.e" --output "$test_build/defer-ret-error" 2>&1)
defer_ret_status=$?
set -e
test "$defer_ret_status" -eq 1
printf '%s' "$defer_ret_error" | grep -q 'ret is not legal inside defer'

test "$("$neper" run "$repo/tests/neper0/protocol-iteration.e" --output "$test_build/protocol-iteration")" = 'protocol iteration ok'

set +e
protocol_immutable=$("$neper" build "$repo/tests/neper0/protocol-immutable-error.e" --output "$test_build/protocol-immutable-error" 2>&1)
protocol_immutable_status=$?
set -e
test "$protocol_immutable_status" -eq 1
printf '%s' "$protocol_immutable" | grep -q 'iterator subject must be a mutable variable or a mutable pointer'

set +e
protocol_signature=$("$neper" build "$repo/tests/neper0/protocol-signature-error.e" --output "$test_build/protocol-signature-error" 2>&1)
protocol_signature_status=$?
set -e
test "$protocol_signature_status" -eq 1
printf '%s' "$protocol_signature" | grep -q 'iterator next function must have signature'

set +e
protocol_missing=$("$neper" build "$repo/tests/neper0/protocol-missing-error.e" --output "$test_build/protocol-missing-error" 2>&1)
protocol_missing_status=$?
set -e
test "$protocol_missing_status" -eq 1
printf '%s' "$protocol_missing" | grep -q 'protocol iteration needs `fn counter_next'

test "$("$neper" run "$repo/tests/neper0/multiple-return.e" --output "$test_build/multiple-return")" = 'multiple return ok'

set +e
multiple_return_count=$("$neper" build "$repo/tests/neper0/multiple-return-count-error.e" --output "$test_build/multiple-return-count-error" 2>&1)
multiple_return_count_status=$?
set -e
test "$multiple_return_count_status" -eq 1
printf '%s' "$multiple_return_count" | grep -q 'multiple binding count does not match function results'

set +e
multiple_return_mutable=$("$neper" build "$repo/tests/neper0/multiple-return-mutable-error.e" --output "$test_build/multiple-return-mutable-error" 2>&1)
multiple_return_mutable_status=$?
set -e
test "$multiple_return_mutable_status" -eq 1
printf '%s' "$multiple_return_mutable" | grep -q 'multiple assignment target is immutable'

test "$("$neper" run "$repo/tests/neper0/constant-folding.e" --output "$test_build/constant-folding")" = 'constant folding ok'

set +e
constant_cycle=$("$neper" build "$repo/tests/neper0/constant-cycle-error.e" --output "$test_build/constant-cycle-error" 2>&1)
constant_cycle_status=$?
set -e
test "$constant_cycle_status" -eq 1
printf '%s' "$constant_cycle" | grep -q 'constant dependency cycle'

set +e
array_length_type=$("$neper" build "$repo/tests/neper0/array-length-type-error.e" --output "$test_build/array-length-type-error" 2>&1)
array_length_type_status=$?
set -e
test "$array_length_type_status" -eq 1
printf '%s' "$array_length_type" | grep -q 'array length must have type usize'

test "$("$neper" run "$repo/tests/neper0/generic-function.e" --output "$test_build/generic-function")" = 'generic function ok'

set +e
generic_inference=$("$neper" build "$repo/tests/neper0/generic-inference-error.e" --output "$test_build/generic-inference-error" 2>&1)
generic_inference_status=$?
set -e
test "$generic_inference_status" -eq 1
printf '%s' "$generic_inference" | grep -q 'cannot infer compile-time parameter `T`'

printf '%s\n' 'neper-0 Linux tests passed'
