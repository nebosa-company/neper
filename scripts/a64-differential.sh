#!/bin/sh
# The aarch64 back end's differential check (D2123), WSL half: every pair named in
# build/a64/out/names.txt -- built by scripts/a64-differential.ps1 -- run from the
# repository root, x64 natively and aarch64 under qemu-aarch64, with stdin empty; their
# stdout, stderr and exit status must agree. One line per program, the totals last; the
# exit status is the number that differ unexpectedly, capped at 255.
#
# What the environment needs (D2124): qemu-user, the arm64 libraries a dynamic image loads
# (libc6:arm64 and the rest, from Ubuntu's arm64 archive) and, for extern_struct's C
# library, gcc and aarch64-linux-gnu-gcc. A watch needs a filesystem that reports changes,
# so os_watch runs from a directory in $HOME rather than DrvFS.
#
# Expected differences, each for a reason that is not the back end's:
#   when_target  its exit code encodes the architecture (115 on x64, 104 here)
#   os_fs        QEMU 8.2's user mode has no openat2 (`Unknown syscall 437`)
#   fs_basics    the same: open_at's .NoSymlinks race opens through openat2 (exit 226)
#   os_gaps     QEMU's user mode refuses PR_SET_SECCOMP
#   debug_dump   gcore of a process under QEMU dumps the emulator
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out="$repo/build/a64/out"
cd "$repo"
cabi="$repo/tests/selfhost/fixtures/link/extern_struct/cabi.c"
if command -v aarch64-linux-gnu-gcc > /dev/null 2>&1; then
    mkdir -p "$out/cabi-x64" "$out/cabi-a64"
    cc -std=c99 -O2 -fPIC -shared -o "$out/cabi-x64/nepercabi" "$cabi"
    aarch64-linux-gnu-gcc -std=c99 -O2 -fPIC -shared -o "$out/cabi-a64/nepercabi" "$cabi"
fi
expected() {
    case "$1" in
        link_when_target|link_os_fs|link_fs_basics|link_os_gaps|link_debug_dump) return 0 ;;
    esac
    return 1
}
match=0
differ=0
known=0
while IFS= read -r name; do
    [ -n "$name" ] || continue
    chmod +x "$out/$name.x64" "$out/$name.aarch64"
    place="$repo"
    # A watch, and fs_basics' moved-root contract, need a native filesystem; fs_basics also
    # takes the suite's cross-volume directory and durability target.
    if [ "$name" = link_os_watch ] || [ "$name" = link_fs_basics ]; then
        place=$(mktemp -d "$HOME/a64-native.XXXXXX")
    fi
    (cd "$place" && NEPER_CROSS_VOLUME_DIR="$out" NEPER_PARTIAL_DURABILITY_TARGET=/dev/null LD_LIBRARY_PATH="$out/cabi-x64" timeout 120 "$out/$name.x64" > "$out/$name.x64.out" 2> "$out/$name.x64.err" < /dev/null)
    x64_status=$?
    (cd "$place" && NEPER_CROSS_VOLUME_DIR="$out" NEPER_PARTIAL_DURABILITY_TARGET=/dev/null QEMU_SET_ENV="LD_LIBRARY_PATH=$out/cabi-a64" timeout 300 qemu-aarch64 "$out/$name.aarch64" > "$out/$name.a64.out" 2> "$out/$name.a64.err" < /dev/null)
    a64_status=$?
    [ "$place" = "$repo" ] || rm -rf "$place"
    if [ "$x64_status" = "$a64_status" ] && cmp -s "$out/$name.x64.out" "$out/$name.a64.out" && cmp -s "$out/$name.x64.err" "$out/$name.a64.err"; then
        match=$((match + 1))
        echo "MATCH $name exit=$x64_status"
    else
        if expected "$name"; then
            known=$((known + 1))
            echo "KNOWN $name x64=$x64_status aarch64=$a64_status"
        else
            differ=$((differ + 1))
            echo "DIFF $name x64=$x64_status aarch64=$a64_status"
        fi
    fi
done < "$out/names.txt"
echo "match=$match known=$known differ=$differ"
[ "$differ" -gt 255 ] && differ=255
exit "$differ"
