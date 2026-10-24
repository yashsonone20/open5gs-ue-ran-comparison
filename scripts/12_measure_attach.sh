#!/usr/bin/env bash
# Control-plane KPI, identical for every platform: time from starting a fresh UE until
# its data tunnel has an IP address ("time to connectivity" = cell search/sync +
# registration + PDU session + tunnel setup). Repeated ATTACH_ATTEMPTS times.
# For UERANSIM the timestamped logs also give a registration / PDU-session breakdown.
#
# The gNB must already be running. The last UE is left running at the end.
# Usage: ./12_measure_attach.sh [run_tag]          (PLATFORM=oai ./12_measure_attach.sh ...)
source "$(dirname "$0")/common.sh"
TAG=${1:-$(run_tag)}
OUT_DIR="$RESULTS_ROOT/$TAG/attach"; mkdir -p "$OUT_DIR"
(( $(gnb_count) >= 1 )) || { fail "$PLATFORM gNB is not running"; exit 1; }
[[ "$PLATFORM" == "oai" ]] && { "$BENCH_ROOT/scripts/04_oai_netns.sh" >/dev/null || exit 1; }
[[ "$PLATFORM" == "freeran" ]] && { "$BENCH_ROOT/scripts/05_freeran_netns.sh" >/dev/null || exit 1; }

CSV="$OUT_DIR/times.csv"
echo "attempt,success,time_to_ip_ms" > "$CSV"
for ((a=1; a<=ATTACH_ATTEMPTS; a++)); do
  stop_ues; sleep 4                       # let the gNB notice the old UE is gone
  log="$OUT_DIR/attempt$a.log"
  t0=$(date +%s%N)
  start_ue "$log"
  ok=0
  deadline=$(( $(date +%s) + UE_ATTACH_TIMEOUT ))
  while (( $(date +%s) < deadline )); do
    if [[ -n "$(ue_ip)" ]]; then ok=1; break; fi
    sleep 0.1
  done
  t1=$(date +%s%N)
  ms=$(( (t1 - t0) / 1000000 ))
  if (( ok )); then
    echo "$a,1,$ms" >> "$CSV"; pass "attempt $a/$ATTACH_ATTEMPTS: UE got $(ue_ip) after ${ms} ms"
  else
    echo "$a,0," >> "$CSV"; warn "attempt $a/$ATTACH_ATTEMPTS: no IP within ${UE_ATTACH_TIMEOUT}s (see $log)"
  fi
done
ensure_ue_route
pass "Results in $CSV"
info "The last UE is still running in the background, so you can continue measuring."
