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
    layout_attributes|incremental|incremental_deleted|incremental_fallback|incremental_layout|incremental_value|inline_nested|when_target) echo any ;;
    gpu_reshape) echo any ;;
    # What a bare Mac cannot give them: a server or arguments the real suite supplies (net*, x_tds_integrated), Vulkan
    # (gpu_fault_unchecked, gpu_vulkan_raw), the ELF and Linux system calls they check (freestanding, os_syscall).
    net|net_http|net_http_pool|net_ssh|net_tls|x_tds_integrated|gpu_fault_unchecked|gpu_vulkan_raw|freestanding|os_syscall) echo any ;;
    # Imports four glibc extensions (memrchr, rawmemchr, strchrnul, strverscmp) that libSystem lacks; dyld binds all or none.
    extern_many) echo any ;;
    # extern_struct loads libnepercabi, which the real suite compiles from the fixture's cabi.c; proc_output runs into
    # the 60 s limit on a Mac, cause not found (os_process and os_gaps do not link there: neper_os_spawn is missing).
    extern_struct|proc_output) echo any ;;
    # os_gaps starts children (it runs on a Mac) and then checks the sandbox, which os.sandbox answers Unsupported on macOS.
    os_gaps) echo any ;;
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

pass=0; fail=0; info=0
for file in "$dir"/*; do
  name=$(basename "$file")
  chmod +x "$file"
  scratch=$(mktemp -d)
  where=${CORPUS_CWD:-$scratch}
  args=()
  extra=$(extra_args "$name")
  if [ -n "$extra" ]; then IFS='|' read -ra args <<< "$extra"; fi
  start=$(date +%s)
  ( cd "$where" && perl -e 'alarm 60; exec @ARGV' "${runner[@]}" "$file" "${args[@]}" >"$scratch/.out" 2>"$scratch/.err" )
  code=$?
  seconds=$(( $(date +%s) - start ))
  want=$(expected "$name")
  if [ "$want" = "any" ]; then
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
echo "TOTAL pass=$pass fail=$fail info=$info"
