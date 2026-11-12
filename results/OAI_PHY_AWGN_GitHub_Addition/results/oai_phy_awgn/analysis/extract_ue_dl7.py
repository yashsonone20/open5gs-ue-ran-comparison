import re
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LOG_DIR = ROOT / "results" / "oai_phy_awgn" / "raw_logs"
CSV_DIR = ROOT / "results" / "oai_phy_awgn" / "csv"

log_file = LOG_DIR / "ue-dl-noise-7-60s.txt"
output_file = CSV_DIR / "ue_phy_dl7.csv"

rows = []

with open(log_file, "r", errors="ignore") as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    m = re.search(
        r"DL Chan: SSB \d+ SINR ([\d.-]+) dB RSRP ([\d.-]+) dBm, RI (\d+) CQI: (\S+)",
        line
    )

    if not m:
        continue

    row = {
        "ss_sinr_db": float(m.group(1)),
        "ss_rsrp_dbm": float(m.group(2)),
        "ri": int(m.group(3)),
        "cqi": m.group(4),
        "dl_harq": "",
        "dl_harq_errors": "",
        "ul_harq": "",
        "ul_harq_errors": ""
    }

    for j in range(i + 1, min(i + 4, len(lines))):
        dl = re.search(r"DL harq: (\d+)/(\d+)", lines[j])
        ul = re.search(r"UL harq: (\d+)/(\d+)", lines[j])

        if dl:
            row["dl_harq"] = int(dl.group(1))
            row["dl_harq_errors"] = int(dl.group(2))

        if ul:
            row["ul_harq"] = int(ul.group(1))
            row["ul_harq_errors"] = int(ul.group(2))

    rows.append(row)

with open(output_file, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)

print("UE samples extracted:", len(rows))
print("Saved:", output_file)
