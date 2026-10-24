#!/usr/bin/env bash
# Provision N consecutive subscribers in Open5GS so `nr-ue -n N` can register N UEs.
# UERANSIM's -n option starts N UEs whose IMSIs count up from the one in UE_CFG,
# all sharing the same key and OPc - so we add exactly those IMSIs.
#
# Usage: ./02_add_subscribers.sh 20            (UERANSIM: IMSIs ...001-...020)
#        PLATFORM=oai ./02_add_subscribers.sh 8 (OAI: IMSIs ...100-...107)
#        PLATFORM=freeran ./02_add_subscribers.sh 20 (free-ran-ue: IMSIs ...110-...129)
source "$(dirname "$0")/common.sh"
COUNT=${1:-20}

DBCTL=${OPEN5GS_DBCTL:-$(command -v open5gs-dbctl)}
if [[ -z "$DBCTL" ]]; then
  fail "open5gs-dbctl not found."
  echo "  Get it with:"
  echo "  wget https://raw.githubusercontent.com/open5gs/open5gs/main/misc/db/open5gs-dbctl"
  echo "  chmod +x open5gs-dbctl && sudo mv open5gs-dbctl /usr/local/bin/"
  exit 1
fi

# Read IMSI, key and OPc from the platform's UE config; add COUNT consecutive IMSIs from there.
if [[ "$PLATFORM" == "freeran" ]]; then
  yv() { grep -E "^\s*$1:" "$FRUE_UE_CFG" | head -n1 | sed -E "s/^\s*$1:\s*['\"]?([^'\"#]*)['\"]?.*/\1/" | tr -d ' '; }
  BASE="$(yv mcc)$(yv mnc)$(yv msin)"; KEY=$(yv encPermanentKey); OPC=$(yv encOpcKey)
  [[ ${#BASE} -lt 15 || -z "$KEY" || -z "$OPC" ]] && { fail "Could not read mcc/mnc/msin/keys from $FRUE_UE_CFG"; exit 1; }
elif [[ "$PLATFORM" == "oai" ]]; then
  conf_val() { grep -E "^\s*$1\s*=" "$OAI_UE_CFG" | head -n1 | sed -E 's/.*"([^"]*)".*/\1/'; }
  BASE=$(conf_val imsi); KEY=$(conf_val key); OPC=$(conf_val opc)
  [[ -z "$BASE" || -z "$KEY" || -z "$OPC" ]] && { fail "Could not read imsi/key/opc from $OAI_UE_CFG"; exit 1; }
else
  yaml_val() { grep -E "^\s*$1:" "$UE_CFG" | head -n1 | sed -E "s/^\s*$1:\s*['\"]?([^'\"#]*)['\"]?.*/\1/" | tr -d ' '; }
  SUPI=$(yaml_val supi); KEY=$(yaml_val key); OPC=$(yaml_val op)
  OPTYPE=$(yaml_val opType)
  BASE=${SUPI#imsi-}
  [[ -z "$BASE" || -z "$KEY" || -z "$OPC" ]] && { fail "Could not read supi/key/op from $UE_CFG"; exit 1; }
  [[ "$OPTYPE" != "OPC" ]] && warn "opType is '$OPTYPE' in $UE_CFG; this script provisions it as OPc. Use OPC in the UE config."
fi

LEN=${#BASE}
info "Provisioning $COUNT subscribers starting at $BASE"
for ((i=0; i<COUNT; i++)); do
  imsi=$(printf "%0${LEN}d" $((10#$BASE + i)))
  "$DBCTL" remove "$imsi" >/dev/null 2>&1   # avoid duplicates on reruns
  if "$DBCTL" add "$imsi" "$KEY" "$OPC" >/dev/null; then pass "imsi-$imsi"; else fail "imsi-$imsi"; fi
done
info "Done. Check in the WebUI (http://localhost:9999) or with: $DBCTL showpretty | grep imsi"
