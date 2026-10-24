#!/usr/bin/env bash
# Throughput through the 5G user plane with iperf3 (JSON output):
#   TCP uplink   (UE -> core)
#   TCP downlink (core -> UE, iperf3 -R)
#   UDP uplink at a fixed rate (gives jitter and loss)
# The iperf3 server runs on the host, bound to ogstun's address (UPF_GW).
#
# Usage: ./11_measure_throughput.sh [run_tag]
source "$(dirname "$0")/common.sh"
need iperf3
TAG=${1:-$(run_tag)}
OUT_DIR="$RESULTS_ROOT/$TAG/iperf"; mkdir -p "$OUT_DIR"
UEIP=$(ue_ip); [[ -z "$UEIP" ]] && { fail "$UE_IF has no address"; exit 1; }
ensure_ue_route
info "Platform: $PLATFORM ($UE_IF${UE_NS:+ in $UE_NS})"

# Build the client command so traffic is forced through the UE tunnel
if [[ -n "$UE_NS" ]]; then
  CLIENT=(sudo ip netns exec "$UE_NS" iperf3)
else
  BINDER="$UERANSIM_DIR/build/nr-binder"
  [[ -x "$BINDER" ]] || { fail "nr-binder not found at $BINDER"; exit 1; }
  CLIENT=("$BINDER" "$UEIP" iperf3)
fi

info "Starting iperf3 server on $UPF_GW:5201"
sudo pkill -x iperf3 2>/dev/null; sleep 0.5
iperf3 -s -B "$UPF_GW" -p 5201 >/dev/null 2>&1 &
SRV=$!; trap 'kill $SRV 2>/dev/null' EXIT; sleep 1

run() {  # run <name> <extra iperf args...>
  local name=$1; shift
  for ((r=1; r<=IPERF_REPEATS; r++)); do
    local f="$OUT_DIR/${name}_run${r}.json"
    info "$name run $r/$IPERF_REPEATS (${IPERF_DURATION}s)"
    local before; before=$(ogstun_rx)
    "${CLIENT[@]}" -c "$UPF_GW" -p 5201 -t "$IPERF_DURATION" -J "$@" > "$f" 2>&1 \
      || warn "iperf3 returned an error, see $f"
    python3 - "$f" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1])); e=d["end"]
    s=e.get("sum_received") or e.get("sum")
    extra=f", jitter {s['jitter_ms']:.2f} ms, loss {s['lost_percent']:.2f}%" if "jitter_ms" in s else ""
    print(f"        {s['bits_per_second']/1e6:.1f} Mbit/s{extra}")
except Exception as ex:
    print("        could not parse result:", ex)
PY
    assert_userplane "$before" "${name}_run${r}"
    sleep 2
  done
}
run tcp_uplink
run tcp_downlink -R
run udp_uplink -u -b "$IPERF_UDP_RATE"
pass "Saved to $OUT_DIR"
