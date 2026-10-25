#!/bin/bash
# usage: run-corpus.sh DIR [runner...]
# Runs every executable in DIR from CORPUS_CWD (default: a scratch directory), each bounded at sixty
# seconds, and prints one line per program: PASS, FAIL or INFO, its exit status and its seconds, then
# the first lines it wrote to stderr when it failed. A pass is the exit status the fixture is built
# to give: 0 unless it is listed below.
dir=$1; shift
runner=("$@")

# Fixtures that end in a trap by design (134), and those whose exit status is the answer they
# compute (the real suite compares it; here it is reported, not judged).
# (A case, not an associative array: the Mac's /bin/bash is 3.2.)
expected() {
  case "$1" in
    gpu_barrier_helper_occurrence|gpu_barrier_occurrence|gpu_divergence|release_build|trap_backtrace) echo 134 ;;
    # The unedited sources' answers, which the same program gives on Windows (incremental 7, deleted 5, fallback 3, layout 7, value 8).
    incremental|incremental_layout) echo 7 ;;
    incremental_deleted) echo 5 ;;
    incremental_fallback) echo 3 ;;
    incremental_value) echo 8 ;;
    # The linux suite's answers, which hold on a Mac too (layout_attributes, inline_nested), and `when_target`'s sum of the arms
    # a Mac takes: 127 for the OS, plus 96 for its code and 8 more on x64.
    layout_attributes) echo 35 ;;
    inline_nested) echo 5 ;;
    when_target) if [ "${runner[0]:-}" = arch ]; then echo 231; else echo 223; fi ;;
    # Four workgroups of four, the buffer's sum (the fixture's own comment).
    gpu_reshape) echo 50 ;;
    # Skipped, each for a reason a Mac has by nature: net_ssh needs the server the workflow's SSH step starts and is reported as that
    # step's SSH line; x_tds_integrated is SSPI (Windows); gpu_vulkan_raw and gpu_fault_unchecked call Vulkan, which a Mac does not
    # have (a Metal backend is C193); freestanding and os_syscall check an ELF image and Linux system call numbers; extern_many
    # imports four glibc extensions that libSystem lacks (dyld binds all or none) and then reads its own ELF header.
    net_ssh|x_tds_integrated|gpu_vulkan_raw|gpu_fault_unchecked|freestanding|os_syscall|extern_many) echo skip ;;
    *) echo 0 ;;
  esac
}

# Fixtures that take arguments, as the real suite passes them.
extra_args() {
  case "$1" in
    os_seek) echo "/tmp/neper-corpus-seek.txt" ;;
    os_dup) echo "/tmp/neper-corpus-dup.txt" ;;
    main_args) echo "one|two words" ;;
    gfx_chart_labels|gfx_chart_composition|gfx_chart_clipped_annotation|gfx_chart_shared_guides) echo "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf" ;;
    differential) printf 'alpha\nbeta\n' > /tmp/neper-corpus-diff.txt; echo "/tmp/neper-corpus-diff.txt" ;;
  esac
}

pass=0; fail=0; info=0; skipped=0
for file in "$dir"/*; do
  name=$(basename "$file")
  chmod +x "$file"
  scratch=$(mktemp -d)
  where=${CORPUS_CWD:-$scratch}
  args=()
  extra=$(extra_args "$name")
  if [ -n "$extra" ]; then IFS='|' read -ra args <<< "$extra"; fi
  start=$(date +%s)
  # CORPUS_LIBS: a directory of dylibs the programs name by leaf (extern_struct's nepercabi). It is set inside a shell
  # because `arch` strips DYLD_* from what it launches.
  launch=("$file")
  if [ -n "${CORPUS_LIBS:-}" ]; then launch=(/bin/sh -c 'DYLD_LIBRARY_PATH="$0" exec "$@"' "$CORPUS_LIBS" "$file"); fi
  ( cd "$where" && perl -e 'alarm 60; exec @ARGV' "${runner[@]}" "${launch[@]}" "${args[@]}" >"$scratch/.out" 2>"$scratch/.err" )
  code=$?
  seconds=$(( $(date +%s) - start ))
  want=$(expected "$name")
  if [ "$want" = "skip" ]; then
    skipped=$((skipped+1)); echo "SKIP $name $code ${seconds}s"
  elif [ "$want" = "any" ]; then
    info=$((info+1)); echo "INFO $name $code ${seconds}s"
  elif [ "$code" -eq "$want" ]; then
    pass=$((pass+1)); echo "PASS $name $code ${seconds}s"
  else
    fail=$((fail+1)); echo "FAIL $name $code ${seconds}s"
    # awk, not sed: a cut-off last line has no newline, and the next result line would be glued to it.
    head -c 300 "$scratch/.err" | head -3 | awk '{print "    | " $0}'
    head -c 700 "$scratch/.out" | head -6 | awk '{print "    > " $0}'
  fi
  rm -rf "$scratch"
done
echo "TOTAL pass=$pass fail=$fail info=$info skip=$skipped"
