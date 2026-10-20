#!/bin/bash
# usage: run-corpus.sh DIR [runner...]
# Runs every executable in DIR, each from its own scratch directory and bounded at sixty seconds, and
# prints one line per program: PASS or FAIL, its exit status and its seconds, then the first lines it
# wrote to stderr when it failed. A pass is exit 0.
dir=$1; shift
runner=("$@")
pass=0; fail=0
for file in "$dir"/*; do
  name=$(basename "$file")
  chmod +x "$file"
  scratch=$(mktemp -d)
  start=$(date +%s)
  ( cd "$scratch" && perl -e 'alarm 60; exec @ARGV' "${runner[@]}" "$file" >"$scratch/.out" 2>"$scratch/.err" )
  code=$?
  seconds=$(( $(date +%s) - start ))
  if [ "$code" -eq 0 ]; then
    pass=$((pass+1)); echo "PASS $name 0 ${seconds}s"
  else
    fail=$((fail+1)); echo "FAIL $name $code ${seconds}s"
    head -c 300 "$scratch/.err" | head -3 | sed 's/^/    | /'
  fi
  rm -rf "$scratch"
done
echo "TOTAL pass=$pass fail=$fail"
