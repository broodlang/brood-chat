#!/usr/bin/env bash
# Run every networked regression in sequence; exit non-zero if any fails.
# Each sub-script drives real `nest run` node processes (see the individual files).
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
for r in repro/mesh.sh repro/tcp.sh repro/run.sh; do
  echo "═══ $r ═══"
  log="$(mktemp)"
  if "$r" >"$log" 2>&1; then
    grep -E 'VERIFIED' "$log" || tail -1 "$log"
  else
    echo "FAILED: $r"; cat "$log"; fail=1
  fi
  rm -f "$log"
done

if [ "$fail" -eq 0 ]; then echo "✓ all repros passed"; else echo "✗ some repros failed"; fi
exit "$fail"
