#!/bin/sh
# The aarch64 back end's differential check (D2123), WSL half: every pair named in
# build/a64/out/names.txt -- built by scripts/a64-differential.ps1 -- run from the
# repository root, x64 natively and aarch64 under qemu-aarch64, with stdin empty; their
# stdout, stderr and exit status must agree. One line per program, the totals last; the
# exit status is the number that differ, capped at 255.
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out="$repo/build/a64/out"
cd "$repo"
match=0
differ=0
while IFS= read -r name; do
    [ -n "$name" ] || continue
    chmod +x "$out/$name.x64" "$out/$name.aarch64"
    timeout 120 "$out/$name.x64" > "$out/$name.x64.out" 2> "$out/$name.x64.err" < /dev/null
    x64_status=$?
    timeout 300 qemu-aarch64 "$out/$name.aarch64" > "$out/$name.a64.out" 2> "$out/$name.a64.err" < /dev/null
    a64_status=$?
    if [ "$x64_status" = "$a64_status" ] && cmp -s "$out/$name.x64.out" "$out/$name.a64.out" && cmp -s "$out/$name.x64.err" "$out/$name.a64.err"; then
        match=$((match + 1))
        echo "MATCH $name exit=$x64_status"
    else
        differ=$((differ + 1))
        echo "DIFF $name x64=$x64_status aarch64=$a64_status"
    fi
done < "$out/names.txt"
echo "match=$match differ=$differ"
[ "$differ" -gt 255 ] && differ=255
exit "$differ"
