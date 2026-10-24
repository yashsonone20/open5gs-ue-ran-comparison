#!/usr/bin/env bash
# Multi-UE scaling test, for both platforms. For N in the platform's scaling steps:
#   - start N UEs at once and log their signalling
#   - measure how many get a PDU session (= a tunnel with an IP) and how long it takes
#   - ping the gateway from every UE at the same time
#   - sample CPU/RAM of every 5G process during attach and steady state
#
# UERANSIM: one nr-ue process simulates N UEs (nr-ue -n N), IMSIs ...001 upwards.
# free-ran-ue: one process simulates N UEs (-n N -p N) in namespace frue-ue, IMSIs ...110 upwards.
# OAI:      N separate nr-uesoftmodem processes, each in its own namespace oai-scaleK
#           with its own veth link (host 10.210.K.1 <-> UE 10.210.K.2), IMSIs ...100 upwards.
# Prerequisites: the platform's gNB running (and no single UE needed - it is stopped),
#   subscribers provisioned:  ./02_add_subscribers.sh 20   /   PLATFORM=oai ./02_add_subscribers.sh 8
#
# Usage: ./20_run_scaling.sh [run_tag]        PLATFORM=oai ./20_run_scaling.sh [run_tag]
source "$(dirname "$0")/common.sh"
need python3
TAG=${1:-$(run_tag)}
(( $(gnb_count) >= 1 )) || { fail "$PLATFORM gNB is not running. Start it first."; exit 1; }
[[ "$PLATFORM" == "freeran" ]] && { "$BENCH_ROOT/scripts/05_freeran_netns.sh" >/dev/null || exit 1; }
if [[ "$PLATFORM" == "oai" ]]; then STEPS="$OAI_SCALING_STEPS"; TIMEOUT=$OAI_SCALING_TIMEOUT
else STEPS="$SCALING_STEPS"; TIMEOUT=$UE_ATTACH_TIMEOUT; fi

# ---- OAI helpers: one namespace + veth per UE ----
oai_ns_up() {  # oai_ns_up <k>
  local k=$1 ns="oai-scale$1" h="vsh$1" u="vsu$1"
  ip netns list | grep -qw "$ns" || sudo ip netns add "$ns"
  if ! ip link show "$h" >/dev/null 2>&1; then
    sudo ip link add "$h" type veth peer name "$u"
    sudo ip link set "$u" netns "$ns"
  fi
  ip -4 addr show "$h" | grep -q "10.210.$k.1" || sudo ip addr add "10.210.$k.1/30" dev "$h"
  sudo ip link set "$h" up
  sudo ip netns exec "$ns" ip -4 addr show "$u" | grep -q "10.210.$k.2" || sudo ip netns exec "$ns" ip addr add "10.210.$k.2/30" dev "$u"
  sudo ip netns exec "$ns" ip link set "$u" up
  sudo ip netns exec "$ns" ip link set lo up
}
oai_imsi() {  # IMSI for UE k = base IMSI from ue.conf + (k-1)
  local base; base=$(grep -E '^\s*imsi\s*=' "$OAI_UE_CFG" | head -n1 | sed -E 's/.*"([^"]*)".*/\1/')
  printf "%0${#base}d" $((10#$base + $1 - 1))
}

# Lists every UE tunnel that has an IPv4 address, as "<namespace or -> <ifname>"
list_tunnels() {
  local ifc ns
  for ifc in $(ip -o -4 addr show 2>/dev/null | awk '{print $2}' | grep -E '^(uesimtun|oaitun|ueTun)'); do echo "- $ifc"; done
  for ns in $(ip netns list 2>/dev/null | awk '{print $1}' | grep -E '^(ueransim|oai-scale|frue-ue)'); do
    for ifc in $(sudo ip netns exec "$ns" ip -o -4 addr show 2>/dev/null | awk '{print $2}' | grep -E '^(uesimtun|oaitun|ueTun)'); do
      echo "$ns $ifc"
    done
  done
}

for N in $STEPS; do
  OUT_DIR="$RESULTS_ROOT/$TAG/scaling/n$N"; mkdir -p "$OUT_DIR/ping"
  echo; info "===== $PLATFORM: $N UE(s) ====="
  stop_ues; sleep 5                       # let the gNB release the previous UEs
  if [[ "$PLATFORM" == "oai" ]]; then for ((k=1; k<=N; k++)); do oai_ns_up "$k"; done; fi

  python3 "$BENCH_ROOT/scripts/resource_sampler.py" "$OUT_DIR/resources.csv" &
  SAMPLER=$!
  sleep 2   # baseline before attach

  t_start=$(date +%s.%N)
  echo "$t_start" > "$OUT_DIR/t_start.txt"
  if [[ "$PLATFORM" == "oai" ]]; then
    for ((k=1; k<=N; k++)); do
      # shellcheck disable=SC2086
      ( cd "$OAI_BUILD" && sudo ip netns exec "oai-scale$k" stdbuf -oL -eL ./nr-uesoftmodem \
          ${OAI_UE_ARGS/--rfsimulator.\[0\].serveraddr $OAI_RFSIM_SERVER/} \
          --rfsimulator.[0].serveraddr "10.210.$k.1" --uicc0.imsi "$(oai_imsi "$k")" \
          > "$OUT_DIR/ue_$k.log" 2>&1 ) &
    done
  elif [[ "$PLATFORM" == "freeran" ]]; then
    # one process simulates N UEs (IMSIs from msin upwards, tunnels ueTun0..), all started at once (-p N)
    ( cd "$FRUE_DIR" && sudo ip netns exec "$FRUE_NS" ./build/free-ran-ue ue -c "$FRUE_UE_CFG" -n "$N" -p "$N" \
        > "$OUT_DIR/ue.log" 2>&1 ) &
  else
    sudo stdbuf -oL -eL "$UERANSIM_DIR/build/nr-ue" -c "$UE_CFG" -n "$N" > "$OUT_DIR/ue.log" 2>&1 &
  fi

  # wait for N tunnels with an IP (= N PDU sessions)
  got=0; deadline=$(( $(date +%s) + TIMEOUT ))
  while (( $(date +%s) < deadline )); do
    got=$(list_tunnels | wc -l)
    (( got >= N )) && break
    sleep 0.5
  done
  t_ready=$(date +%s.%N)
  attach_s=$(python3 -c "print(round($t_ready-$t_start,3))")
  echo "requested=$N tunnels_up=$got wall_time_s=$attach_s" > "$OUT_DIR/summary.txt"
  (( got >= N )) && pass "$got/$N UEs got a PDU session in ${attach_s}s" \
                 || warn "only $got/$N UEs got a PDU session within ${TIMEOUT}s"

  # concurrent ping from every UE to the gateway
  before=$(ogstun_rx)
  pings=()
  while read -r ns ifc; do
    if [[ "$ns" == "-" ]]; then
      ping -I "$ifc" -c 20 -i 0.2 "$UPF_GW" > "$OUT_DIR/ping/$ifc.txt" 2>&1 &
    else
      [[ "$ifc" == oaitun* ]] && sudo ip netns exec "$ns" ip route replace default dev "$ifc"
      if [[ "$ifc" == ueTun* ]]; then
        # free-ran-ue: all UEs share one namespace. Give each tunnel its own routing table,
        # selected by source address (policy routing, as UERANSIM does internally), and ping
        # from that UE's address.
        k=${ifc#ueTun}
        src=$(sudo ip netns exec "$ns" ip -4 -o addr show dev "$ifc" | awk '{print $4}' | cut -d/ -f1)
        sudo ip netns exec "$ns" ip rule del priority $((1000+k)) 2>/dev/null
        sudo ip netns exec "$ns" ip rule add from "$src" table $((200+k)) priority $((1000+k))
        sudo ip netns exec "$ns" ip route replace default dev "$ifc" table $((200+k))
        sudo ip netns exec "$ns" ping -I "$src" -c 20 -i 0.2 "$UPF_GW" > "$OUT_DIR/ping/${ns}_$ifc.txt" 2>&1 &
      else
        sudo ip netns exec "$ns" ping -c 20 -i 0.2 "$UPF_GW" > "$OUT_DIR/ping/${ns}_$ifc.txt" 2>&1 &
      fi
    fi
    pings+=($!)
  done < <(list_tunnels)
  (( ${#pings[@]} )) && wait "${pings[@]}" 2>/dev/null
  OUT_DIR=$OUT_DIR assert_userplane "$before" "scaling_n${N}_ping"

  info "Steady-state sampling for ${STEADY_STATE_SECS}s"
  sleep "$STEADY_STATE_SECS"
  kill -TERM $SAMPLER; wait $SAMPLER 2>/dev/null
done

stop_ues
pass "Scaling results in $RESULTS_ROOT/$TAG/scaling"
info "Start your normal single UE again before other tests."
