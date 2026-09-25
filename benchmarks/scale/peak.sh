#!/bin/bash
# peak.sh EXE ARGS... : runs the command and prints its peak working set in MB (Windows).
"$@" > peak_out.txt 2>&1 &
pid=$!
peak=0
while kill -0 $pid 2>/dev/null; do
  v=$(NEPER_PEAK_PROCESS="$(basename "${1%.exe}")" pwsh -NoProfile -Command '(Get-Process -Name $env:NEPER_PEAK_PROCESS -ErrorAction SilentlyContinue | Measure-Object -Property PeakWorkingSet64 -Maximum).Maximum' 2>/dev/null | tr -d '\r')
  [ -n "$v" ] && [ "$v" -gt "$peak" ] 2>/dev/null && peak=$v
done
wait $pid; echo "exit=$? peak working set MB: $((peak/1048576))"
