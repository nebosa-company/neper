#!/usr/bin/env sh
# The refresh mode of refresh-goldens.sh: a snapshot-only difference is rewritten, any other is not, and without
# NEPER_REFRESH_GOLDENS a difference is just a difference.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$here/refresh-goldens.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tests/conformance/tools"
golden="$work/tests/conformance/tools/t.x64-linux.expected.jsonl"
stale='{"record":"subject","snapshot":"aaaa","checks":"retained"}'
printf '%s\n' "$stale" > "$golden"
printf '%s\n' '{"record":"subject","snapshot":"bbbb","checks":"retained"}' > "$work/snapshot_only"
printf '%s\n' '{"record":"subject","snapshot":"bbbb","checks":"dropped"}' > "$work/other"

cmp -s "$work/snapshot_only" "$golden" && { echo 'a difference passed without NEPER_REFRESH_GOLDENS' >&2; exit 1; }
[ "$(cat "$golden")" = "$stale" ] || { echo 'the golden changed without NEPER_REFRESH_GOLDENS' >&2; exit 1; }
export NEPER_REFRESH_GOLDENS=1
cmp -s "$work/other" "$golden" && { echo 'a non-snapshot difference was refreshed' >&2; exit 1; }
[ "$(cat "$golden")" = "$stale" ] || { echo 'the golden changed on a non-snapshot difference' >&2; exit 1; }
cmp -s "$work/snapshot_only" "$work/other" && { echo 'a golden outside tests/conformance/tools was refreshed' >&2; exit 1; }
cmp -s "$work/snapshot_only" "$golden" > /dev/null || { echo 'a snapshot-only difference was not refreshed' >&2; exit 1; }
printf '%s\n' "$stale" > "$golden"
cmp "$work/snapshot_only" "$golden" > /dev/null || { echo 'a snapshot-only difference was not refreshed (cmp without -s)' >&2; exit 1; }
cmp -s "$work/snapshot_only" "$golden" || { echo 'the refreshed golden does not match' >&2; exit 1; }
printf '%s\n' 'refresh goldens ok'
