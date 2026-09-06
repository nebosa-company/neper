#!/usr/bin/env sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
neper="$repo/build/linux/neper"
test_build="$repo/build/linux/tests/neper0"
"$repo/scripts/build-bootstrap.sh" >/dev/null
mkdir -p "$test_build"

test "$("$neper" run "$repo/tests/neper0/range.e" --output "$test_build/range")" = 'range ok'
test "$("$neper" run "$repo/tests/neper0/unsigned-ops.e" --output "$test_build/unsigned-ops")" = 'unsigned ops ok'
set +e
unsigned_divide=$("$neper" run "$repo/tests/neper0/unsigned-divide-trap.e" --output "$test_build/unsigned-divide-trap" 2>&1)
unsigned_divide_status=$?
set -e
test "$unsigned_divide_status" -eq 134
printf '%s' "$unsigned_divide" | grep -q 'trap\[divide\]'
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

readelf --debug-dump=info "$test_build/aggregate-abi" >"$test_build/aggregate-abi.dwarf" 2>"$test_build/aggregate-abi.dwarf.err"
readelf --debug-dump=info "$test_build/enum-union-switch" >"$test_build/enum-union-switch.dwarf" 2>"$test_build/enum-union-switch.dwarf.err"
readelf --debug-dump=info "$test_build/array" >"$test_build/array.dwarf" 2>"$test_build/array.dwarf.err"
test ! -s "$test_build/aggregate-abi.dwarf.err"
test ! -s "$test_build/enum-union-switch.dwarf.err"
test ! -s "$test_build/array.dwarf.err"
for tag in compile_unit subprogram formal_parameter variable base_type structure_type member pointer_type const_type; do
    grep -q "DW_TAG_$tag" "$test_build/aggregate-abi.dwarf"
done
grep -q 'DW_TAG_union_type' "$test_build/enum-union-switch.dwarf"
grep -q 'DW_TAG_enumeration_type' "$test_build/enum-union-switch.dwarf"
grep -q 'DW_TAG_array_type' "$test_build/array.dwarf"
grep -q 'DW_OP_fbreg' "$test_build/aggregate-abi.dwarf"
test "$(grep -c DW_AT_location "$test_build/aggregate-abi.dwarf")" = "$(grep -c DW_OP_fbreg "$test_build/aggregate-abi.dwarf")"
if readelf -S "$test_build/aggregate-abi" | grep -Eq '\.debug_(loc|loclists|ranges|rnglists)'; then
    printf '%s\n' 'unexpected DWARF location or range list section' >&2
    exit 1
fi

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

test "$("$neper" run "$repo/tests/neper0/generic-aggregate.e" --output "$test_build/generic-aggregate")" = 'generic aggregate ok'

set +e
generic_aggregate_arity=$("$neper" build "$repo/tests/neper0/generic-aggregate-arity-error.e" --output "$test_build/generic-aggregate-arity-error" 2>&1)
generic_aggregate_arity_status=$?
set -e
test "$generic_aggregate_arity_status" -eq 1
printf '%s' "$generic_aggregate_arity" | grep -q 'compile-time argument count does not match generic type'

test "$("$neper" run "$repo/tests/neper0/arena-alloc.e" --output "$test_build/arena-alloc")" = 'arena alloc ok'

set +e
arena_exhausted=$("$neper" run "$repo/tests/neper0/arena-exhausted.e" --output "$test_build/arena-exhausted" 2>&1)
arena_exhausted_status=$?
set -e
test "$arena_exhausted_status" -eq 1
printf '%s' "$arena_exhausted" | grep -q 'error: mem\.Exhausted'

test "$("$neper" run "$repo/tests/neper0/arena-scope.e" --output "$test_build/arena-scope")" = 'arena scope ok'

set +e
arena_reset_bounds=$("$neper" run "$repo/tests/neper0/arena-reset-bounds.e" --output "$test_build/arena-reset-bounds" 2>&1)
arena_reset_bounds_status=$?
set -e
test "$arena_reset_bounds_status" -eq 134
printf '%s' "$arena_reset_bounds" | grep -q '6:5: trap\[bounds\]: arena reset mark is ahead of the current cursor'

os_helper="$test_build/os-spawn-helper"
"$neper" build "$repo/tests/neper0/os-spawn-helper.e" --output "$os_helper" >/dev/null
os_output="$test_build/os-output.txt"
test "$("$neper" run "$repo/tests/neper0/os-intrinsics.e" --output "$test_build/os-intrinsics" -- "$os_output" "$repo/tests/neper0" "$os_helper")" = 'intrinsic ok'
test "$(cat "$os_output")" = 'neper os!'

set +e
os_error=$("$neper" run "$repo/tests/neper0/os-error.e" --output "$test_build/os-error" -- "$test_build/does-not-exist.neper0" 2>&1)
os_error_status=$?
set -e
test "$os_error_status" -eq 1
printf '%s' "$os_error" | grep -q 'error: os\.NotFound'

set +e
"$neper" run "$repo/tests/neper0/os-exit.e" --output "$test_build/os-exit" >/dev/null
os_exit_status=$?
set -e
test "$os_exit_status" -eq 23

printf '%s\n' 'neper-0 Linux tests passed'
