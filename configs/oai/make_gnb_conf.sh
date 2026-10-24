#!/usr/bin/env bash
# Builds ~/oai-config/gnb.conf from OAI's band-78 106-PRB example, pointed at a local Open5GS:
# AMF 127.0.0.5, gNB N2/N3 on 127.0.0.1, PLMN 999/70 (Open5GS's default).
set -e
OAI="${1:-$HOME/openairinterface5g}"
mkdir -p "$HOME/oai-config"
cp "$OAI/targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb.sa.band78.fr1.106PRB.usrpb210.conf" "$HOME/oai-config/gnb.conf"
sed -i 's/192\.168\.70\.132/127.0.0.5/g; s/192\.168\.70\.129/127.0.0.1/g' "$HOME/oai-config/gnb.conf"
sed -i 's/mcc *= *001;/mcc = 999;/; s/mnc *= *01;/mnc = 70;/' "$HOME/oai-config/gnb.conf"
cp "$(dirname "$0")/ue.conf" "$HOME/oai-config/ue.conf"
grep -nE "mcc|mnc|tracking_area_code|amf_ip_address|GNB_IPV4" "$HOME/oai-config/gnb.conf"
echo "Written: ~/oai-config/gnb.conf and ~/oai-config/ue.conf"
