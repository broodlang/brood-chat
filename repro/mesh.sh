#!/usr/bin/env bash
# Transitive-mesh group-chat regression (ADR-088). Starts three real chat nodes —
# A is the entry point; B and C each `/connect` only A, never each other. If the
# mesh works, B and C are still linked transitively, so every node ends up seeing
# the other two (peers=2) and hearing both their messages (recv=2).
#
# This is the multi-node counterpart to run.sh (which covers clean-disconnect
# [:nodedown]). Each node drives the actual chat module, so it exercises the app's
# own connect / presence-reconcile / broadcast paths.
#
# Usage:  repro/mesh.sh          (from anywhere)
# Exit 0 + "VERIFIED" => the mesh forms a shared room; non-zero => it does not.

set -uo pipefail
cd "$(dirname "$0")/.."

RT="/run/user/$(id -u)/brood"
A="$(mktemp)"; B="$(mktemp)"; C="$(mktemp)"
rm -f "$RT"/mnA.sock "$RT"/mnB.sock "$RT"/mnC.sock

cleanup() { kill "$PA" "$PB" "$PC" 2>/dev/null; rm -f "$A" "$B" "$C"; }
trap cleanup EXIT

echo "[mesh] starting node A (cluster entry point)…"
NODE=mnA           SAY="hello from A" nest run repro/mesh_node.blsp >"$A" 2>&1 & PA=$!
# Wait up to 3s for A's socket so B/C can dial deterministically.
for _ in $(seq 1 30); do [ -S "$RT/mnA.sock" ] && break; sleep 0.1; done
if [ ! -S "$RT/mnA.sock" ]; then echo "[mesh] FAIL: A never listened"; cat "$A"; exit 1; fi

echo "[mesh] starting nodes B and C (each dials only A)…"
NODE=mnB DIAL=mnA  SAY="hello from B" nest run repro/mesh_node.blsp >"$B" 2>&1 & PB=$!
sleep 0.4   # let B join + register before C, so A gossips B→C (avoids a simultaneous-join race)
NODE=mnC DIAL=mnA  SAY="hello from C" nest run repro/mesh_node.blsp >"$C" 2>&1 & PC=$!

wait "$PA" "$PB" "$PC"

echo "----- node A -----"; cat "$A"
echo "----- node B -----"; cat "$B"
echo "----- node C -----"; cat "$C"

# Each node says one line and should end up seeing both peers (peers=2) and holding
# all three conversational lines (its own + the other two = conv=3).
ok=$(cat "$A" "$B" "$C" | grep -c 'RESULT .* peers=2 conv=3')
if [ "$ok" -eq 3 ]; then
  echo "[mesh] VERIFIED: all three nodes share one room — B and C meshed via A (peers=2 conv=3 each)."
  exit 0
else
  echo "[mesh] NOT verified — expected 3 nodes at peers=2 conv=3, got $ok."
  exit 1
fi
