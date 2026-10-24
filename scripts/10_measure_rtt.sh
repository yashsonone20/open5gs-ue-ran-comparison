#!/usr/bin/env bash
# Latency + packet loss through the UE tunnel, to the UPF gateway and to the internet.
# Raw ping output is saved; analysis/analyze.py computes avg / p50 / p95 / p99 / loss.
#
# Usage: ./10_measure_rtt.sh [run_tag]
source "$(dirname "$0")/common.sh"
TAG=${1:-$(run_tag)}
OUT_DIR="$RESULTS_ROOT/$TAG/rtt"; mkdir -p "$OUT_DIR"
[[ -z "$(ue_ip)" ]] && { fail "$UE_IF has no address - is the UE registered? Run 00_healthcheck.sh"; exit 1; }
ensure_ue_route
info "Platform: $PLATFORM ($UE_IF${UE_NS:+ in $UE_NS})"

for target in gateway internet; do
  [[ $target == gateway ]] && dst=$UPF_GW || dst=$INTERNET_TARGET
  for ((r=1; r<=REPEATS; r++)); do
    f="$OUT_DIR/${target}_run${r}.txt"
    info "RTT to $target ($dst), run $r/$REPEATS, $PING_COUNT pings"
    before=$(ogstun_rx)
    # -D adds timestamps, useful for spotting spikes over time
    # shellcheck disable=SC2046
    ue_exec ping $(ping_bind_args) -D -c "$PING_COUNT" -i "$PING_INTERVAL" "$dst" > "$f" 2>&1
    tail -n 2 "$f" | sed 's/^/        /'
    assert_userplane "$before" "rtt_${target}_run${r}"
  done
done
pass "Saved to $OUT_DIR"
