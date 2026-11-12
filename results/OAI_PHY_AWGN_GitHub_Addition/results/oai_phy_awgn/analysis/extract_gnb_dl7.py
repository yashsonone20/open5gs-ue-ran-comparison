import re
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LOG_DIR = ROOT / "results" / "oai_phy_awgn" / "raw_logs"
CSV_DIR = ROOT / "results" / "oai_phy_awgn" / "csv"

log_file = LOG_DIR / "gnb-dl-noise-7-60s.txt"
output_file = CSV_DIR / "gnb_phy_dl7.csv"

rows = []
current = {}

with open(log_file, "r", errors="ignore") as f:
    for line in f:

        rsrp = re.search(r"average RSRP ([\d.-]+)", line)
        if rsrp:
            current["gnb_rsrp_dbm"] = float(rsrp.group(1))

        dl = re.search(
            r"dlsch_rounds (\d+)/(\d+)/(\d+)/(\d+), dlsch_errors (\d+), "
            r"pucch0_DTX (\d+) \(SNR ([\d.-]+)",
            line
        )

        if dl:
            current.update({
                "dl_rounds": int(dl.group(1)),
                "dl_bler": float(re.search(r"BLER ([\d.]+)", line).group(1)),
                "dl_errors": int(dl.group(5)),
                "pucch_dtx": int(dl.group(6)),
                "pucch_snr_db": float(dl.group(7))
            })

        ul = re.search(
            r"ulsch_rounds (\d+)/(\d+)/(\d+)/(\d+), ulsch_errors (\d+), "
            r"ulsch_DTX (\d+), BLER ([\d.]+).*?MCS \(0\) (\d+).*?NPRB (\d+) "
            r"SNR ([\d.+-]+)",
            line
        )

        if ul:
            current.update({
                "ul_rounds": int(ul.group(1)),
                "ul_errors": int(ul.group(5)),
                "ul_dtx": int(ul.group(6)),
                "ul_bler": float(ul.group(7)),
                "ul_mcs": int(ul.group(8)),
                "ul_nprb": int(ul.group(9)),
                "pusch_snr_db": float(ul.group(10))
            })

            rows.append(current.copy())
            current = {}

if not rows:
    raise RuntimeError("No complete gNB samples extracted. Check log format.")

with open(output_file, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)

print("gNB samples extracted:", len(rows))
print("Saved:", output_file)
