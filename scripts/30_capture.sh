#!/usr/bin/env bash
# Packet capture of one complete attach for the current platform:
#   NGAP + NAS-5GS (gNB <-> AMF, SCTP 38412), PFCP (SMF <-> UPF, UDP 8805) and
#   GTP-U (gNB <-> UPF, UDP 2152) while a fresh UE registers, gets a PDU session
#   and sends 5 pings to the core gateway.
# Output in results/<platform>/<tag>/capture/:
#   capture.pcap  - open in Wireshark
#   flow.txt      - the signalling ladder (time, protocol, source -> destination, message)
#   gtp_qfi.txt   - uplink/downlink GTP-U packets with their PDU Session Container and QFI
#
# Needs: sudo apt install -y tcpdump tshark   (see README)
# The gNB must be running. Usage: ./30_capture.sh [run_tag]   PLATFORM=oai ./30_capture.sh ...
source "$(dirname "$0")/common.sh"
need tcpdump; need tshark
TAG=${1:-$(run_tag)}
OUT_DIR="$RESULTS_ROOT/$TAG/capture"; mkdir -p "$OUT_DIR"
PCAP="$OUT_DIR/capture.pcap"
(( $(gnb_count) >= 1 )) || { fail "$PLATFORM gNB is not running"; exit 1; }
[[ "$PLATFORM" == "oai" ]] && { "$BENCH_ROOT/scripts/04_oai_netns.sh" >/dev/null || exit 1; }
[[ "$PLATFORM" == "freeran" ]] && { "$BENCH_ROOT/scripts/05_freeran_netns.sh" >/dev/null || exit 1; }

info "Stopping any running UE so the capture starts from a clean registration"
stop_ues; sleep 4

info "Capturing on all interfaces (NGAP/SCTP, PFCP, GTP-U)"
sudo tcpdump -i any -s 0 -U -w "$PCAP" 'sctp or udp port 2152 or udp port 8805' >/dev/null 2>&1 &
TCPD=$!
sleep 2

start_ue "$OUT_DIR/ue.log"
ok=0; deadline=$(( $(date +%s) + UE_ATTACH_TIMEOUT ))
while (( $(date +%s) < deadline )); do [[ -n "$(ue_ip)" ]] && { ok=1; break; }; sleep 0.2; done
if (( ok )); then
  ensure_ue_route
  pass "UE got $(ue_ip); sending 5 pings to $UPF_GW"
  # shellcheck disable=SC2046
  ue_exec ping $(ping_bind_args) -c 5 -i 0.5 "$UPF_GW" > "$OUT_DIR/ping.txt" 2>&1
else
  warn "UE did not get an IP within ${UE_ATTACH_TIMEOUT}s; saving the capture anyway"
fi
sleep 2
sudo kill -INT "$TCPD" 2>/dev/null; wait "$TCPD" 2>/dev/null
sudo chown "$(id -u):$(id -g)" "$PCAP"

# NAS uses null ciphering (NEA0) here, so Wireshark can decode it with this preference.
TS=(tshark -r "$PCAP" -o nas-5gs.null_decipher:TRUE)
"${TS[@]}" -c 1 >/dev/null 2>&1 || TS=(tshark -r "$PCAP")   # older/newer tshark without that preference

info "Writing the signalling ladder"
{
  printf "%-10s | %-8s | %-31s | %s\n" "time (s)" "proto" "source -> destination" "message"
  "${TS[@]}" -Y "ngap || pfcp" -T fields -E separator='|' \
      -e frame.time_relative -e _ws.col.Protocol -e ip.src -e ip.dst -e _ws.col.Info 2>/dev/null |
    awk -F'|' '{ printf "%-10.4f | %-8s | %-15s -> %-13s | %s\n", $1, $2, $3, $4, $5 }'
} > "$OUT_DIR/flow.txt"

info "Checking the QoS flow ID in GTP-U packets"
# Field names for the PDU Session Container changed between Wireshark releases, so look them up.
FIELDS=$(tshark -G fields 2>/dev/null | cut -f3 | grep -E '^gtp\.ext_hdr\.pdu_ses_con' || true)
F_TYPE=$(grep -m1 -E 'pdu_type$' <<<"$FIELDS" || true)
F_QFI=$(grep -m1 -E '(qos_flow_id|qfi)$' <<<"$FIELDS" || true)
GTP_FILTER="gtp && udp.port == 2152 && gtp.message == 0xff"
{
  echo "frame | source -> destination | TEID | PDU type (0=DL, 1=UL) | QFI"
  if [[ -n "$F_TYPE" && -n "$F_QFI" ]]; then
    "${TS[@]}" -Y "$GTP_FILTER" -T fields -E separator='|' \
        -e frame.number -e ip.src -e ip.dst -e gtp.teid -e "$F_TYPE" -e "$F_QFI" 2>/dev/null |
      awk -F'|' '{ printf "%s | %s -> %s | %s | %s | %s\n", $1, $2, $3, $4, ($5==""?"none":$5), ($6==""?"none":$6) }' |
      head -n 40
  else
    echo "(this tshark has no PDU Session Container fields; verbose decode of the first GTP-U packets:)"
    # Note: -c would count packets read, not packets matched, so use head instead.
    "${TS[@]}" -Y "$GTP_FILTER" -V 2>/dev/null |
      grep -E "^Frame [0-9]+|Internet Protocol Version 4, Src|TEID|PDU Type|QoS Flow Identifier|QFI" | head -n 60
  fi
} > "$OUT_DIR/gtp_qfi.txt"

n_ngap=$("${TS[@]}" -Y ngap 2>/dev/null | wc -l)
n_gtp=$("${TS[@]}" -Y "$GTP_FILTER" 2>/dev/null | wc -l)
pass "Captured $n_ngap NGAP and $n_gtp GTP-U data packets -> $PCAP"
info "Signalling ladder: $OUT_DIR/flow.txt"
info "QFI check:         $OUT_DIR/gtp_qfi.txt"
info "To open in Wireshark on Windows: explorer.exe \"\$(wslpath -w $OUT_DIR)\"  then double-click capture.pcap"
