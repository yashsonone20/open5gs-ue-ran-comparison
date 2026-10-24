#!/usr/bin/env bash
# Checks every link in the chain UE -> gNB -> AMF/SMF -> UPF -> ogstun -> NAT -> internet
# and tells you which one is broken. Run this before every measurement session.
source "$(dirname "$0")/common.sh"
problems=0
bad() { fail "$*"; problems=$((problems+1)); }

echo "== 1. Open5GS core services =="
for s in nrfd scpd amfd smfd upfd ausfd udmd udrd pcfd nssfd bsfd; do
  st=$(systemctl is-active "open5gs-$s" 2>/dev/null)
  if [[ "$st" == "active" ]]; then pass "open5gs-$s"; else bad "open5gs-$s is '${st:-unknown}' (sudo systemctl restart open5gs-$s)"; fi
done
pgrep -x mongod >/dev/null && pass "mongod running" || bad "mongod not running (sudo systemctl start mongod)"

echo; echo "== 2. ogstun and forwarding =="
if ip link show ogstun >/dev/null 2>&1; then
  ip -4 addr show ogstun | grep -q "$UPF_GW" && pass "ogstun has $UPF_GW" || bad "ogstun exists but has no $UPF_GW (run 01_userplane_setup.sh)"
  ip link show ogstun | grep -q "UP" && pass "ogstun is UP" || bad "ogstun is DOWN (run 01_userplane_setup.sh)"
else
  bad "ogstun interface missing (run 01_userplane_setup.sh)"
fi
[[ "$(cat /proc/sys/net/ipv4/ip_forward)" == "1" ]] && pass "ip_forward=1" || bad "ip_forward=0 (run 01_userplane_setup.sh)"
if sudo iptables -t nat -S POSTROUTING | grep -q -- "-s $UE_SUBNET"; then
  pass "NAT rule for $UE_SUBNET present"
  sudo iptables -t nat -vnL POSTROUTING | grep "${UE_SUBNET%/*}" | sed 's/^/        /'
else
  bad "No NAT (MASQUERADE) rule for $UE_SUBNET (run 01_userplane_setup.sh)"
fi

echo; echo "== 3. RAN/UE processes ($PLATFORM) =="
ng=$(gnb_count); nu=$(ue_count)
(( ng == 1 )) && pass "1 $GNB_PROC instance running" || bad "$ng $GNB_PROC instances (want exactly 1)"
(( nu >= 1 )) && pass "$nu $UE_PROC instance(s) running" || bad "no $UE_PROC running"
(( nu > 1 )) && warn "More than one $UE_PROC instance. Stale UEs give confusing results. Run 03_reset_ues.sh."
for other in nr-gnb nr-ue nr-softmodem nr-uesoftmodem free-ran-ue; do
  [[ "$other" == "$GNB_PROC" || "$other" == "$UE_PROC" ]] && continue
  pgrep -x "$other" >/dev/null && bad "$other (other platform) is also running - run one platform at a time"
done

echo; echo "== 4. UE tunnel interfaces =="
mapfile -t tuns < <(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(uesimtun|oaitun|ueTun)' || true)
info "In root namespace: ${tuns[*]:-none}"
for ns in $(ip netns list 2>/dev/null | awk '{print $1}'); do
  t=$(sudo ip netns exec "$ns" ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(uesimtun|oaitun|ueTun)' | tr '\n' ' ')
  [[ -n "$t" ]] && info "In namespace $ns: $t"
done
ip_ue=$(ue_ip)
ensure_ue_route
if [[ -n "$ip_ue" ]]; then pass "$UE_IF has address $ip_ue${UE_NS:+ (namespace $UE_NS)}"; else bad "$UE_IF not found${UE_NS:+ in namespace $UE_NS} - check UE_IF/UE_NS in config.env"; fi

echo; echo "== 5. Data path through the 5G user plane =="
if [[ -n "$ip_ue" ]]; then
  for tgt in "$UPF_GW" "$INTERNET_TARGET"; do
    before=$(ogstun_rx)
    # shellcheck disable=SC2046
    if ue_exec ping $(ping_bind_args) -c 3 -W 2 "$tgt" >/dev/null 2>&1; then
      after=$(ogstun_rx)
      if (( after > before )); then pass "ping $tgt via UE works and crossed ogstun"
      else bad "ping $tgt replied but NOT via ogstun (loopback shortcut). Use namespace mode (UE_NS)."; fi
    else
      bad "ping $tgt via UE failed"
    fi
  done
fi

echo
if (( problems == 0 )); then pass "All checks passed - ready to measure."; else fail "$problems problem(s). Fix the first FAIL above first; later ones often follow from it."; fi
exit $(( problems > 0 ))
