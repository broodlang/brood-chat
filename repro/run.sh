#!/usr/bin/env bash
# §1.2 repro — a clean peer exit fires [:nodedown] on the survivor promptly,
# via socket-EOF close-detection rather than the 6s heartbeat-timeout window.
#
# Sequences two real `nest run` node processes (nodes are per-runtime, so this
# genuinely needs two): start the peer, wait for its socket, then run the
# survivor and assert it printed PASS.
#
# Usage:  repro/run.sh        (from anywhere)
# Exit 0 + "VERIFIED" => §1.2 behaves correctly; non-zero => it does not.

set -uo pipefail
cd "$(dirname "$0")/.."

SOCK="/run/user/$(id -u)/brood/peerb.sock"
PEER_OUT="$(mktemp)"
rm -f "$SOCK"

echo "[run] starting peer (node B)…"
nest run repro/nodedown_peer.blsp >"$PEER_OUT" 2>&1 &
BPID=$!

# Wait up to 3s for B's Unix socket to appear (deterministic readiness signal).
for _ in $(seq 1 30); do [ -S "$SOCK" ] && break; sleep 0.1; done
if [ ! -S "$SOCK" ]; then
  echo "[run] FAIL: peer socket ($SOCK) never appeared"
  kill "$BPID" 2>/dev/null
  echo "--- peer output ---"; cat "$PEER_OUT"; rm -f "$PEER_OUT"
  exit 1
fi

echo "[run] peer is listening; starting survivor (node A)…"
OUT="$(nest run repro/nodedown_survivor.blsp 2>&1)"
echo "$OUT"

wait "$BPID" 2>/dev/null

if grep -q '^PASS:' <<<"$OUT"; then
  echo "[run] §1.2 VERIFIED: a clean disconnect fires [:nodedown] promptly (close-detection, not heartbeat)."
  rm -f "$PEER_OUT"
  exit 0
else
  echo "[run] §1.2 NOT verified — survivor did not report PASS."
  echo "--- peer output ---"; cat "$PEER_OUT"; rm -f "$PEER_OUT"
  exit 1
fi
