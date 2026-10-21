#!/bin/bash
# usage: build-corpus.sh COMPILER ROOT OUTDIR [JOBS]
# Compiles every link fixture under ROOT/tests/selfhost/fixtures/link for aarch64-macos and x64-macos with
# COMPILER (a Neper compiler that can run `emit-executable`), into OUTDIR/aarch64 and OUTDIR/x64, and prints
# a TSV of NAME, ARCH, ok|fail and the compiler's last lines. Pack each directory as corpus-<arch>.tar.gz and
# attach both to a pre-release named in tests/macos/corpus-tag.txt to start the macos-corpus workflow; delete
# the release afterwards.
# ponytail: six parallel compiles can exhaust memory (the compiler then dies with an access violation);
# rebuild any such fixture alone with `build-one`.
compiler=$1; root=$2; out=$3; jobs=${4:-6}
build_one() {
  n=$1; arch=$2
  dir=$out/$arch; mkdir -p "$dir"
  msg=$(timeout 300 "$compiler" emit-executable "$root/tests/selfhost/fixtures/link/$n/src/main.e" "$root" "$arch" macos "$dir/$n" 2>&1 | tail -3 | tr '\n\t' '  ' | cut -c1-200)
  if [ -f "$dir/$n" ] && echo "$msg" | grep -q "executable written"; then st=ok; else st=fail; rm -f "$dir/$n"; fi
  printf '%s\t%s\t%s\t%s\n' "$n" "$arch" "$st" "$msg"
}
export -f build_one; export compiler root out
for n in $(ls "$root/tests/selfhost/fixtures/link"); do
  [ -f "$root/tests/selfhost/fixtures/link/$n/src/main.e" ] && { echo "$n aarch64"; echo "$n x64"; }
done | xargs -P "$jobs" -L 1 bash -c 'build_one $0 $1'
