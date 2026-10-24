#!/usr/bin/env bash
# Creates the network namespace the free-ran-ue UE runs in, plus a veth "cable" so the UE
# can reach the gNB at 10.202.1.1 (ranControlPlaneIp/ranDataPlaneIp in gnb.yaml).
# Safe to rerun; needed after every WSL/Windows restart.
source "$(dirname "$0")/common.sh"
NS="$FRUE_NS"
ip netns list | grep -qw "$NS" || sudo ip netns add "$NS"
if ! ip link show vfr-host >/dev/null 2>&1; then
  sudo ip link add vfr-host type veth peer name vfr-ue
  sudo ip link set vfr-ue netns "$NS"
fi
ip -4 addr show vfr-host | grep -q "$FRUE_RAN_IP" || sudo ip addr add "$FRUE_RAN_IP/30" dev vfr-host
sudo ip link set vfr-host up
sudo ip netns exec "$NS" ip -4 addr show vfr-ue | grep -q 10.202.1.2 || sudo ip netns exec "$NS" ip addr add 10.202.1.2/30 dev vfr-ue
sudo ip netns exec "$NS" ip link set vfr-ue up
sudo ip netns exec "$NS" ip link set lo up
if sudo ip netns exec "$NS" ping -c 1 -W 2 "$FRUE_RAN_IP" >/dev/null; then
  pass "Namespace $NS ready (UE side 10.202.1.2 can reach $FRUE_RAN_IP)"
else
  fail "Namespace $NS exists but cannot reach $FRUE_RAN_IP"; exit 1
fi
