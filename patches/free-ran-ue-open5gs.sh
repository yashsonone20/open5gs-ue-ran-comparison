#!/usr/bin/env bash
# Makes free-ran-ue (built for free5GC) work with Open5GS. Idempotent; run once after cloning.
# Tested with free-ran-ue commit 7587e14 (Oct 2026) and Open5GS 2.8.0.
#   1. Open5GS AMF: disable network_name (free-ran-ue cannot decode the UCS-2 name in the
#      Configuration Update Command). Cosmetic: the operator name shown to the UE.
#   2. free-ran-ue UE: PDU Session Establishment Request used PTI 0; TS 24.501 requires a UE to
#      allocate 1-254 and Open5GS's SMF rejects 0 ("No PTI").
#   3. free-ran-ue gNB: uplink GTP-U had no PDU Session Container, so no QFI; Open5GS's UPF
#      matches uplink PDRs on QFI and answered with Error Indication. Adds QFI = 1.
# Usage: ./free-ran-ue-open5gs.sh [path to free-ran-ue]   (default ~/free-ran-ue)
set -e
FRUE="${1:-$HOME/free-ran-ue}"
cd "$FRUE"

# 1. Open5GS network_name
if grep -qE '^\s*network_name:' /etc/open5gs/amf.yaml; then
  sudo cp -n /etc/open5gs/amf.yaml /etc/open5gs/amf.yaml.bak
  sudo sed -i '/^\s*network_name:/,/^\s*short:/ s/^/#/' /etc/open5gs/amf.yaml
  sudo systemctl restart open5gs-amfd
  echo "[1] network_name disabled in /etc/open5gs/amf.yaml (backup: amf.yaml.bak)"
else
  echo "[1] network_name already disabled"
fi

# 2. PTI
if grep -qE 'PTI:\s*0x00,' ue/nas.go; then
  sed -i -E 's/(PTI:\s*)0x00,/\10x01,/' ue/nas.go; echo "[2] PTI set to 1 in ue/nas.go"
else
  echo "[2] PTI already patched"
fi

# 3. QFI in uplink GTP-U
python3 - gnb/gtp.go <<'EOF'
import sys, re
p = sys.argv[1]; s = open(p).read()
if "QFI = 1" in s:
    print("[3] QFI already patched"); sys.exit(0)
m = re.search(r'\tgtpHeader := make\(\[\]byte, 12\)\n.*?gtpHeader\[8\], gtpHeader\[9\], gtpHeader\[10\], gtpHeader\[11\] = 0x00, 0x00, 0x00, 0x00\n', s, re.S)
if not m: sys.exit("[3] pattern not found - different free-ran-ue version; patch gnb/gtp.go by hand")
new = '''\t// Uplink G-PDU with PDU Session Container (QFI = 1): Open5GS's UPF matches uplink packets on QFI
\tgtpHeader := make([]byte, 16)
\tgtpHeader[0] = 0x34 // version 1, PT=1, E=1
\tgtpHeader[1] = 0xff // G-PDU
\tbinary.BigEndian.PutUint16(gtpHeader[2:], uint16(len(packet)+8))
\tcopy(gtpHeader[4:], teid)
\tgtpHeader[8], gtpHeader[9], gtpHeader[10] = 0x00, 0x00, 0x00
\tgtpHeader[11] = 0x85 // next extension: PDU Session Container
\tgtpHeader[12] = 0x01 // length 1 (x4 bytes)
\tgtpHeader[13] = 0x10 // PDU type 1 = UL PDU SESSION INFORMATION
\tgtpHeader[14] = 0x01 // QFI = 1
\tgtpHeader[15] = 0x00 // no more extension headers
'''
open(p, 'w').write(s[:m.start()] + new + s[m.end():]); print("[3] QFI = 1 added to uplink GTP-U in gnb/gtp.go")
EOF

make
echo "Done: build/free-ran-ue rebuilt with the Open5GS fixes."
