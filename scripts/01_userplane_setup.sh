#!/usr/bin/env bash
# One-time (per boot) user-plane setup from the Open5GS quickstart, made idempotent.
# Safe to run repeatedly: every rule is checked before it is added.
# WSL note: these settings are lost when WSL restarts (wsl --shutdown), so rerun after a restart.
source "$(dirname "$0")/common.sh"
need iptables

info "Enabling IPv4 forwarding"
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

if ! ip link show ogstun >/dev/null 2>&1; then
  info "Creating ogstun"
  sudo ip tuntap add name ogstun mode tun
fi
ip -4 addr show ogstun | grep -q "$UPF_GW" || sudo ip addr add "$UPF_GW/${UE_SUBNET#*/}" dev ogstun
sudo ip link set ogstun up

add_rule() {  # add_rule <table> <chain> <rule...>  (only if missing)
  local t=$1 c=$2; shift 2
  sudo iptables -t "$t" -C "$c" "$@" 2>/dev/null || sudo iptables -t "$t" -A "$c" "$@"
}
info "NAT for the UE pool $UE_SUBNET"
add_rule nat POSTROUTING -s "$UE_SUBNET" ! -o ogstun -j MASQUERADE
add_rule filter FORWARD -i ogstun -j ACCEPT
add_rule filter FORWARD -o ogstun -j ACCEPT
add_rule filter INPUT   -i ogstun -j ACCEPT

pass "User plane configured. Current NAT table:"
sudo iptables -t nat -vnL POSTROUTING
