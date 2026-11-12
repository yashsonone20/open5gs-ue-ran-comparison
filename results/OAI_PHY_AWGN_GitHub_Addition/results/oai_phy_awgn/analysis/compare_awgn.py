from pathlib import Path
import pandas as pd
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "results" / "oai_phy_awgn" / "csv"
OUT = BASE
PLOT_DIR = ROOT / "results" / "oai_phy_awgn" / "plots"
PLOT_DIR.mkdir(parents=True, exist_ok=True)

experiments = [
    ("-19 dB", "ue_phy_chanmod.csv", "gnb_phy_chanmod.csv"),
    ("-15 dB", "ue_phy_dl15.csv", "gnb_phy_dl15.csv"),
    ("-10 dB", "ue_phy_dl10.csv", "gnb_phy_dl10.csv"),
    ("-8 dB", "ue_phy_dl8.csv", "gnb_phy_dl8.csv"),
    ("-7 dB", "ue_phy_dl7.csv", "gnb_phy_dl7.csv"),
]

ue_frames = []
gnb_frames = []
summary_rows = []

for noise, ue_file, gnb_file in experiments:
    ue = pd.read_csv(BASE / ue_file)
    gnb = pd.read_csv(BASE / gnb_file)
    gnb = gnb.rename(columns={"gnb_rsrp_dbm": "gnb_avg_rsrp_dbm"})

    ue["dl_noise_setting"] = noise
    gnb["dl_noise_setting"] = noise

    ue_frames.append(ue)
    gnb_frames.append(gnb)

    metrics = [
        (ue, "ss_sinr_db", "UE SS-SINR"),
        (ue, "ss_rsrp_dbm", "UE SS-RSRP"),
        (gnb, "gnb_avg_rsrp_dbm", "gNB average RSRP"),
        (gnb, "pucch_snr_db", "PUCCH SNR"),
        (gnb, "pusch_snr_db", "PUSCH SNR"),
        (gnb, "dl_bler", "DL BLER"),
        (gnb, "ul_bler", "UL BLER"),
    ]

    for df, column, metric in metrics:
        values = pd.to_numeric(df[column], errors="coerce").dropna()
        summary_rows.append({
            "dl_noise_setting": noise,
            "metric": metric,
            "samples": len(values),
            "mean": values.mean(),
            "std": values.std(ddof=1),
            "minimum": values.min(),
            "maximum": values.max(),
        })

ue_all = pd.concat(ue_frames, ignore_index=True)
gnb_all = pd.concat(gnb_frames, ignore_index=True)
summary = pd.DataFrame(summary_rows)

ue_all.to_csv(OUT / "ue_awgn_combined.csv", index=False)
gnb_all.to_csv(OUT / "gnb_awgn_combined.csv", index=False)
summary.to_csv(OUT / "awgn_comparison_summary.csv", index=False)

# Plot 1: UE SS-SINR
plot_metrics = [
    ("ss_sinr_db", "UE SS-SINR", "SS-SINR (dB)", "ss_sinr_vs_noise.png", ue_all),
    ("ss_rsrp_dbm", "UE SS-RSRP", "SS-RSRP (dBm)", "ss_rsrp_vs_noise.png", ue_all),
    ("pucch_snr_db", "PUCCH SNR", "PUCCH SNR (dB)", "pucch_snr_vs_noise.png", gnb_all),
    ("pusch_snr_db", "PUSCH SNR", "PUSCH SNR (dB)", "pusch_snr_vs_noise.png", gnb_all),
    ("dl_bler", "DL BLER", "DL BLER", "dl_bler_vs_noise.png", gnb_all),
    ("ul_bler", "UL BLER", "UL BLER", "ul_bler_vs_noise.png", gnb_all),
]

order = ["-19 dB", "-15 dB", "-10 dB", "-8 dB", "-7 dB"]

for column, title, ylabel, filename, df in plot_metrics:
    grouped = df.groupby("dl_noise_setting")[column].agg(["mean", "std"])
    grouped = grouped.reindex(order)

    fig, ax = plt.subplots(figsize=(7, 4.5))
    ax.errorbar(
        order,
        grouped["mean"],
        yerr=grouped["std"].fillna(0),
        marker="o",
        capsize=4,
    )
    ax.set_title(title + " vs DL noise setting")
    ax.set_xlabel("Configured DL noise power")
    ax.set_ylabel(ylabel)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(PLOT_DIR / filename, dpi=300)
    plt.close(fig)

print("AWGN comparison completed.")
print(f"Output directory: {OUT}")
print("\nSummary:")
print(summary.to_string(index=False))
print("\nGenerated files:")
for path in sorted(OUT.iterdir()):
    print(path.name)
