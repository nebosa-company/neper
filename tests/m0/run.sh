#!/usr/bin/env sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
neper="$repo/build/linux/neper"
test_build="$repo/build/linux/tests"
test -x "$neper" || "$repo/scripts/build-bootstrap.sh" >/dev/null
mkdir -p "$test_build"

test "$("$neper" run "$repo/examples/hello.e" --output "$test_build/hello")" = 'hello, neper'
test "$("$neper" run "$repo/examples/hello.e" --arena 96K --output "$test_build/hello-sized")" = 'hello, neper'
grep -q 'mov rsi, 98304' "$test_build/hello-sized.s"
set +e
invalid_arena=$("$neper" build "$repo/examples/hello.e" --arena 0 --output "$test_build/hello-invalid-arena" 2>&1)
invalid_arena_status=$?
set -e
test "$invalid_arena_status" -eq 2
printf '%s' "$invalid_arena" | grep -q 'invalid arena size `0`'
test "$(cd /tmp && "$neper" run "$repo/examples/hello.e" --output "$test_build/hello-cwd")" = 'hello, neper'
test "$("$neper" run "$repo/tests/m0/control.e" --output "$test_build/control")" = 'control ok'
test "$("$neper" run "$repo/tests/m0/args.e" --output "$test_build/args" -- 'héllo 😀')" = 'héllo 😀'
test "$("$neper" run "$repo/tests/m0/abi.e" --output "$test_build/abi")" = 'abi ok'
test "$("$neper" run "$repo/tests/m0/large-stack.e" --output "$test_build/large-stack")" = 'large stack ok'
grep -q 'call np_stack_probe' "$test_build/large-stack.s"

set +e
bounds=$("$neper" run "$repo/tests/m0/bounds.e" --output "$test_build/bounds" 2>&1)
bounds_status=$?
set -e
test "$bounds_status" -eq 134
printf '%s' "$bounds" | grep -q 'trap\[bounds\]'

set +e
divide=$("$neper" run "$repo/tests/m0/divide.e" --output "$test_build/divide" 2>&1)
divide_status=$?
set -e
test "$divide_status" -eq 134
printf '%s' "$divide" | grep -q 'trap\[divide\]'

set +e
named_error=$("$neper" run "$repo/tests/m0/errors.e" --output "$test_build/errors" 2>&1)
named_status=$?
set -e
test "$named_status" -eq 1
test "$named_error" = 'error: errors.Boom'

set +e
bad=$("$neper" build "$repo/tests/m0/bad-main.e" --output "$test_build/bad-main" 2>&1)
status=$?
set -e
test "$status" -eq 1
printf '%s' "$bad" | grep -q 'E-TYPE-9999'

set +e
missing=$("$neper" build "$repo/tests/m0/missing-module.e" --output "$test_build/missing" 2>&1)
missing_status=$?
set -e
test "$missing_status" -eq 1
printf '%s' "$missing" | grep -q '1:1: error\[E-MODULE-0001\]'

set +e
type_error=$("$neper" build "$repo/tests/m0/type-error.e" --output "$test_build/type-error" 2>&1)
type_status=$?
set -e
test "$type_status" -eq 1
printf '%s' "$type_error" | grep -q '4:5: error\[E-TYPE-0002\]'

printf 'use e.mem\n\nfn main(a: *mem.Arena, args: []str) -> err {\n\tret ok\n}\n' > "$test_build/tab.e"
set +e
tab_error=$("$neper" build "$test_build/tab.e" --output "$test_build/tab" 2>&1)
tab_status=$?
set -e
test "$tab_status" -eq 1
printf '%s' "$tab_error" | grep -q '4:1: error\[E-LEX-0002\]'

printf 'use e.mem\n\303\n' > "$test_build/invalid-utf8.e"
set +e
utf8_error=$("$neper" build "$test_build/invalid-utf8.e" --output "$test_build/invalid-utf8" 2>&1)
utf8_status=$?
set -e
test "$utf8_status" -eq 1
printf '%s' "$utf8_error" | grep -q '2:1: error\[E-LEX-0001\]'

printf '%s\n' 'M0 Linux tests passed'
