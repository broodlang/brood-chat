#!/usr/bin/env bash
# Cross-machine + history-backfill regression. Three TCP nodes on loopback (the same
# code path as real remote hosts — only the IP differs). Node A listens, says two
# lines BEFORE anyone joins, then B and C dial A's TCP address. If TCP meshing and
# history backfill both work, B and C converge to peers=2 and — crucially — replay
# A's two pre-join lines they never received live, plus everyone's live line.
#
# Usage:  repro/tcp.sh          (from anywhere)
# Exit 0 + "VERIFIED" => TCP mesh + backfill work; non-zero => they do not.

set -uo pipefail
cd "$(dirname "$0")/.."

A="$(mktemp)"; B="$(mktemp)"; C="$(mktemp)"
cleanup() { kill "$PA" "$PB" "$PC" 2>/dev/null; rm -f "$A" "$B" "$C"; }
trap cleanup EXIT

echo "[tcp] starting node A on 127.0.0.1:9201 (says two lines before peers join)…"
NODE=tcpA LISTEN=127.0.0.1:9201 PRECHAT="early one|early two" SAY="live from A" \
  nest run repro/mesh_node.blsp >"$A" 2>&1 & PA=$!
# Wait for A to print its readiness marker (bound + registered) before B/C dial —
# ensure-link swallows an initial connect that races ahead of the listener.
for _ in $(seq 1 50); do grep -q '^READY tcpA' "$A" && break; sleep 0.1; done

echo "[tcp] starting B and C — each dials A over TCP (never each other)…"
NODE=tcpB LISTEN=127.0.0.1:9202 DIAL="tcpA@127.0.0.1:9201" SAY="live from B" \
  nest run repro/mesh_node.blsp >"$B" 2>&1 & PB=$!
sleep 0.4   # stagger so A gossips B→C (avoids a simultaneous-join race)
NODE=tcpC LISTEN=127.0.0.1:9203 DIAL="tcpA@127.0.0.1:9201" SAY="live from C" \
  nest run repro/mesh_node.blsp >"$C" 2>&1 & PC=$!

wait "$PA" "$PB" "$PC"

echo "----- node A -----"; cat "$A"
echo "----- node B -----"; cat "$B"
echo "----- node C -----"; cat "$C"

fail=0
# Every node meshed to the other two over TCP.
[ "$(cat "$A" "$B" "$C" | grep -c 'RESULT .* peers=2')" -eq 3 ] || { echo "[tcp] FAIL: not all nodes reached peers=2"; fail=1; }
# B and C backfilled A's two pre-join lines they never saw live.
for f in "$B" "$C"; do
  grep -q 'early one' "$f" && grep -q 'early two' "$f" || { echo "[tcp] FAIL: $(basename "$f") missing backfilled history"; fail=1; }
done

if [ "$fail" -eq 0 ]; then
  echo "[tcp] VERIFIED: TCP mesh spans the (loopback) 'machines' and late joiners backfill missed history."
  exit 0
else
  echo "[tcp] NOT verified."
  exit 1
fi
