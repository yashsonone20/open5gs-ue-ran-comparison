#!/usr/bin/env bash
# The only change to UERANSIM's stock Open5GS configs: put each UE in its own network
# namespace, so traffic to the UE really crosses the 5G user plane on a single host.
# Also creates /etc/iproute2/rt_tables, which UERANSIM needs and Ubuntu >= 24.10 no longer ships.
set -e
UE_CFG="${1:-$HOME/UERANSIM/config/open5gs-ue.yaml}"
sed -i 's/^\(\s*useNamespace:\s*\)false/\1true/' "$UE_CFG"
grep -n "useNamespace" "$UE_CFG"
if [ ! -f /etc/iproute2/rt_tables ]; then
  sudo mkdir -p /etc/iproute2
  sudo cp /usr/share/iproute2/rt_tables /etc/iproute2/rt_tables 2>/dev/null ||
    printf "255\tlocal\n254\tmain\n253\tdefault\n0\tunspec\n" | sudo tee /etc/iproute2/rt_tables >/dev/null
  echo "Created /etc/iproute2/rt_tables"
fi
