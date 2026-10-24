#!/usr/bin/env bash
# Creates the network namespace the OAI UE runs in, plus a veth "cable" so the UE
# can reach the gNB's RF simulator at 10.201.1.1. Safe to rerun; needed after every
# WSL/Windows restart (namespaces do not survive a restart).
source "$(dirname "$0")/common.sh"
NS="$OAI_NS"
ip netns list | grep -qw "$NS" || sudo ip netns add "$NS"
if ! ip link show veth-host >/dev/null 2>&1; then
  sudo ip link add veth-host type veth peer name veth-ue
  sudo ip link set veth-ue netns "$NS"
fi
ip -4 addr show veth-host | grep -q "$OAI_RFSIM_SERVER" || sudo ip addr add "$OAI_RFSIM_SERVER/30" dev veth-host
sudo ip link set veth-host up
sudo ip netns exec "$NS" ip -4 addr show veth-ue | grep -q 10.201.1.2 || sudo ip netns exec "$NS" ip addr add 10.201.1.2/30 dev veth-ue
sudo ip netns exec "$NS" ip link set veth-ue up
sudo ip netns exec "$NS" ip link set lo up
if sudo ip netns exec "$NS" ping -c 1 -W 2 "$OAI_RFSIM_SERVER" >/dev/null; then
  pass "Namespace $NS ready (UE side 10.201.1.2 can reach $OAI_RFSIM_SERVER)"
else
  fail "Namespace $NS exists but cannot reach $OAI_RFSIM_SERVER"; exit 1
fi
