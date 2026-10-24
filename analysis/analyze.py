#!/usr/bin/env python3
"""Turn raw results into summary tables (CSV + Markdown) and report figures (PNG).

Reads   results/<platform>/<run_tag>/...   for every platform found.
Writes  analysis_out/   (tables, figures, summary.md)

For each platform and each kind of test, the MOST RECENT run tag that contains
that test is used, so a rerun after a fix replaces the old numbers.
Override with --tag <run_tag> to pin one run. Tests flagged in VALIDITY.txt
(traffic bypassed the 5G user plane) are excluded and listed in summary.md.

Usage:  python3 analysis/analyze.py [--results results] [--out analysis_out] [--tag TAG]
Needs:  pandas, matplotlib  (sudo apt install -y python3-pandas python3-matplotlib)
"""
import argparse, json, re, statistics as st
from datetime import datetime
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

# Validated categorical slots 1-3 (fixed order, never cycled) + recessive ink
SERIES = ["#2a78d6", "#eb6834", "#1baf7a"]
INK, INK2, GRID = "#0b0b0b", "#52514e", "#e4e3df"
plt.rcParams.update({
    "figure.dpi": 150, "savefig.bbox": "tight", "font.size": 10,
    "axes.edgecolor": INK2, "axes.labelcolor": INK, "axes.titleweight": "bold",
    "xtick.color": INK2, "ytick.color": INK2, "axes.grid": True, "axes.grid.axis": "y", "grid.color": GRID,
    "axes.spines.top": False, "axes.spines.right": False, "axes.axisbelow": True,
    "legend.frameon": False,
})

# ---------------------------------------------------------------- helpers
def mdt(df):
    try:
        return df.to_markdown(index=False)
    except ImportError:  # 'tabulate' not installed
        return "```\n" + df.to_string(index=False) + "\n```"

def latest(platform_dir: Path, sub: str, tag=None):
    if tag:
        d = platform_dir / tag / sub
        return d if d.exists() else None
    cands = sorted(p / sub for p in platform_dir.iterdir() if (p / sub).exists())
    return cands[-1] if cands else None

def invalid_labels(d: Path):
    f = d / "VALIDITY.txt"
    return {l.split()[0] for l in f.read_text().splitlines() if l.strip()} if f.exists() else set()

PING_LINE = re.compile(r"icmp_seq=(\d+).*?time=([\d.]+) ms")
PING_SUM = re.compile(r"(\d+) packets transmitted, (\d+) received")

def parse_ping(path: Path):
    txt = path.read_text(errors="ignore")
    rtts = [float(m.group(2)) for m in PING_LINE.finditer(txt)]
    m = PING_SUM.search(txt)
    sent, recv = (int(m.group(1)), int(m.group(2))) if m else (len(rtts), len(rtts))
    return rtts, sent, recv

def pct(xs, q):
    if not xs: return float("nan")
    xs = sorted(xs); k = (len(xs) - 1) * q / 100
    f = int(k); c = min(f + 1, len(xs) - 1)
    return xs[f] + (xs[c] - xs[f]) * (k - f)

# UERANSIM log line: [2026-10-19 12:34:56.789] [nas] [info] msg
#            or multi-UE: [2026-10-19 12:34:56.789] [imsi-001010000000001|nas] [info] msg
LOG = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\] \[(?:([^\]|]+)\|)?([\w-]+)\] \[\w+\] (.*)$")
EVENTS = {
    "reg_send": re.compile(r"sending initial registration", re.I),
    "reg_ok":   re.compile(r"initial registration is successful", re.I),
    "pdu_send": re.compile(r"sending pdu session establishment request", re.I),
    "pdu_ok":   re.compile(r"pdu session establishment is successful", re.I),
}

def parse_ue_log(path: Path):
    """Return one dict per UE: first-line time and the time of each event."""
    ues = {}
    for line in path.read_text(errors="ignore").splitlines():
        m = LOG.match(line.strip())
        if not m: continue
        t = datetime.strptime(m.group(1)[:23], "%Y-%m-%d %H:%M:%S.%f").timestamp()
        ue = m.group(2) or "ue"
        rec = ues.setdefault(ue, {"first": t})
        for k, rx in EVENTS.items():
            if k not in rec and rx.search(m.group(4)): rec[k] = t
    rows = []
    for ue, r in ues.items():
        def d(a, b):
            return round((r[b] - r[a]) * 1000, 2) if a in r and b in r else float("nan")
        rows.append({"ue": ue,
                     "registration_ms": d("reg_send", "reg_ok"),
                     "pdu_session_ms": d("pdu_send", "pdu_ok"),
                     "attach_total_ms": round((r["pdu_ok"] - r["first"]) * 1000, 2) if "pdu_ok" in r else float("nan"),
                     "registered": "reg_ok" in r, "pdu_up": "pdu_ok" in r})
    return rows

def resource_stats(csv: Path):
    """Mean/peak CPU and RAM for each process group (summed over instances)."""
    df = pd.read_csv(csv)
    if df.empty: return {}
    def group(n):
        if n == "SYSTEM": return "System total"
        if n.startswith("open5gs-"): return "Open5GS core"
        if n == "mongod": return "MongoDB"
        if n in ("nr-ue", "srsue", "nr-uesoftmodem", "free-ran-ue-ue"): return "UE(s)"
        return "gNB"
    df["group"] = df["process"].map(group)
    # CPU: add up every process. RAM: OAI forks a child that shares memory with its parent,
    # so take the largest RSS per program instance (avoids double counting), then add instances.
    if "root_pid" not in df: df["root_pid"] = df["pid"]   # older CSVs
    # one row per program instance (parent+forked child share root_pid), then sum instances
    per = df.groupby(["t_s", "group", "root_pid"]).agg(cpu_percent=("cpu_percent", "sum"), rss_mb=("rss_mb", "max")).reset_index()
    g = per.groupby(["t_s", "group"])[["cpu_percent", "rss_mb"]].sum().reset_index()
    out = {}
    for name, s in g.groupby("group"):
        out[name] = {"cpu_mean": s.cpu_percent.mean(), "cpu_peak": s.cpu_percent.max(),
                     "ram_mean_mb": s.rss_mb.mean(), "ram_peak_mb": s.rss_mb.max()}
    return out

def save(fig, out, name):
    fig.savefig(out / name); plt.close(fig); print("  figure:", out / name)

# ---------------------------------------------------------------- statistics
def significance_tests(rtt_raw, at_raw, tp_raw, n_boot=2000, seed=0):
    """Pairwise tests between platforms; returns a list of row dicts (empty if scipy is missing)."""
    try:
        import numpy as np
        from scipy import stats
    except ImportError:
        print("  (scipy not installed: skipping significance tests - sudo apt install -y python3-scipy)")
        return []
    from itertools import combinations
    rng = np.random.default_rng(seed)
    rows = []

    def boot_ci(a, b):
        a, b = np.asarray(a, float), np.asarray(b, float)
        d = [np.median(rng.choice(a, a.size)) - np.median(rng.choice(b, b.size)) for _ in range(n_boot)]
        return np.percentile(d, [2.5, 97.5])

    def welch_ci(res):
        try:
            lo, hi = res.confidence_interval(0.95)
            return f"[{lo:.2f}, {hi:.2f}]"
        except Exception:  # older scipy
            return ""

    def mw(metric, unit, A, B, a, b):
        if len(a) < 2 or len(b) < 2: return
        res = stats.mannwhitneyu(a, b, alternative="two-sided")
        lo, hi = boot_ci(a, b)
        rows.append({"metric": metric, "A": A, "B": B, "n_A": len(a), "n_B": len(b),
                     "median_A": round(float(np.median(a)), 3), "median_B": round(float(np.median(b)), 3),
                     f"diff_A_minus_B ({unit})": round(float(np.median(a) - np.median(b)), 3),
                     "ci95": f"[{lo:.3f}, {hi:.3f}]",
                     "effect_r": round(2 * res.statistic / (len(a) * len(b)) - 1, 3),
                     "test": "Mann-Whitney U", "p": float(res.pvalue)})

    plats = sorted({k[0] for k in rtt_raw} | set(at_raw) | {k[0] for k in tp_raw})
    for A, B in combinations(plats, 2):
        for target, label in (("gateway", "RTT to gateway"), ("internet", "RTT to internet")):
            if (A, target) in rtt_raw and (B, target) in rtt_raw:
                mw(label, "ms", A, B, rtt_raw[(A, target)], rtt_raw[(B, target)])
        if A in at_raw and B in at_raw:
            mw("Time to connectivity", "ms", A, B, at_raw[A], at_raw[B])
        for test in ("tcp_uplink", "tcp_downlink"):
            a, b = tp_raw.get((A, test), []), tp_raw.get((B, test), [])
            if len(a) >= 2 and len(b) >= 2:
                res = stats.ttest_ind(a, b, equal_var=False)
                rows.append({"metric": f"Throughput {test.replace('_', ' ')}", "A": A, "B": B,
                             "n_A": len(a), "n_B": len(b),
                             "median_A": round(float(np.mean(a)), 2), "median_B": round(float(np.mean(b)), 2),
                             "diff_A_minus_B (Mbit/s)": round(float(np.mean(a) - np.mean(b)), 2),
                             "ci95": welch_ci(res), "effect_r": "", "test": "Welch t (means)", "p": float(res.pvalue)})
    if not rows: return rows
    # Holm-Bonferroni across all tests
    order = sorted(range(len(rows)), key=lambda i: rows[i]["p"])
    m, running = len(rows), 0.0
    for rank, i in enumerate(order):
        running = max(running, min(1.0, (m - rank) * rows[i]["p"]))
        rows[i]["p_holm"] = running
    for r in rows:
        r["significant"] = "yes" if r["p_holm"] < 0.05 else "no"
        r["p"] = f"{r['p']:.2e}"; r["p_holm"] = f"{r['p_holm']:.2e}"
    # one diff column per unit -> merge into a single readable column
    for r in rows:
        unit_key = next(k for k in r if k.startswith("diff_A_minus_B"))
        r["difference A-B"] = f"{r.pop(unit_key)} {unit_key.split('(')[1].rstrip(')')}"
    cols = ["metric", "A", "B", "n_A", "n_B", "median_A", "median_B", "difference A-B", "ci95",
            "effect_r", "test", "p", "p_holm", "significant"]
    return [{c: r.get(c) for c in cols} for r in rows]

# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--results", default=root / "results", type=Path)
    ap.add_argument("--out", default=root / "analysis_out", type=Path)
    ap.add_argument("--tag")
    a = ap.parse_args()
    out = a.out; out.mkdir(parents=True, exist_ok=True)
    platforms = sorted(p for p in a.results.iterdir() if p.is_dir()) if a.results.exists() else []
    if not platforms: raise SystemExit(f"No results in {a.results}. Run the scripts first.")
    if len(platforms) > 3:
        print("Note: more than 3 platforms; figures are designed for up to 3 (colour-safe limit).")
    pcolor = {p.name: SERIES[i % 3] for i, p in enumerate(platforms)}
    cfg = root / "config.env"
    m_t = re.search(r'^INTERNET_TARGET="?([^"\s]+)', cfg.read_text(), re.M) if cfg.exists() else None
    internet_target = m_t.group(1) if m_t else "internet target"
    excluded, md = [], ["# 5G KPI summary\n"]

    # ---------- RTT
    rtt_rows, rtt_raw = [], {}
    for p in platforms:
        d = latest(p, "rtt", a.tag)
        if not d: continue
        bad = invalid_labels(d)
        for target in ("gateway", "internet"):
            allr, sent, recv = [], 0, 0
            for f in sorted(d.glob(f"{target}_run*.txt")):
                if f"rtt_{f.stem}" in bad: excluded.append(f"{p.name}: {d.parent.name}/rtt/{f.name}"); continue
                r, s, rc = parse_ping(f); allr += r; sent += s; recv += rc
            if not sent: continue
            rtt_raw[(p.name, target)] = allr
            rtt_rows.append({"platform": p.name, "run": d.parent.name, "target": target, "samples": len(allr),
                "avg_ms": round(st.mean(allr), 3) if allr else None,
                "p50_ms": round(pct(allr, 50), 3), "p95_ms": round(pct(allr, 95), 3),
                "p99_ms": round(pct(allr, 99), 3), "max_ms": round(max(allr), 3) if allr else None,
                "jitter_mdev_ms": round(st.pstdev(allr), 3) if len(allr) > 1 else None,
                "loss_pct": round(100 * (sent - recv) / sent, 2)})
    if rtt_rows:
        df = pd.DataFrame(rtt_rows); df.to_csv(out / "rtt_summary.csv", index=False)
        md += ["## Latency (RTT through the UE tunnel)\n", mdt(df), "\n"]
        fig, axes = plt.subplots(1, 2, figsize=(9, 3.6))
        for ax, target in zip(axes, ("gateway", "internet")):
            names = [p.name for p in platforms if (p.name, target) in rtt_raw]
            data = [rtt_raw[(n, target)] for n in names]
            if not data: ax.set_visible(False); continue
            bp = ax.boxplot(data, patch_artist=True, widths=0.5, showfliers=True,
                            medianprops={"color": INK, "linewidth": 2},
                            flierprops={"marker": "o", "markersize": 3, "markeredgecolor": INK2})
            for patch, n in zip(bp["boxes"], names):
                patch.set_facecolor(pcolor[n]); patch.set_alpha(0.85); patch.set_edgecolor(INK2)
            ax.set_xticks(range(1, len(names) + 1), names)
            ax.set_title(f"RTT to {'UPF gateway' if target == 'gateway' else f'internet ({internet_target})'}")
            ax.set_ylabel("Round-trip time (ms)")
        fig.tight_layout(); save(fig, out, "fig_rtt.png")

    # ---------- Throughput
    tp_rows, tp_raw = [], {}
    for p in platforms:
        d = latest(p, "iperf", a.tag)
        if not d: continue
        bad = invalid_labels(d)
        for test in ("tcp_uplink", "tcp_downlink", "udp_uplink"):
            vals, jit, loss = [], [], []
            for f in sorted(d.glob(f"{test}_run*.json")):
                if f.stem in bad: excluded.append(f"{p.name}: {d.parent.name}/iperf/{f.name}"); continue
                try:
                    e = json.loads(f.read_text())["end"]
                except Exception:
                    excluded.append(f"{p.name}: {f.name} (unreadable/failed run)"); continue
                s = e.get("sum_received") or e.get("sum")
                vals.append(s["bits_per_second"] / 1e6)
                if "jitter_ms" in s: jit.append(s["jitter_ms"]); loss.append(s["lost_percent"])
            if vals:
                tp_raw[(p.name, test)] = vals
                tp_rows.append({"platform": p.name, "run": d.parent.name, "test": test, "runs": len(vals),
                    "mean_mbps": round(st.mean(vals), 2), "min_mbps": round(min(vals), 2),
                    "max_mbps": round(max(vals), 2),
                    "std_mbps": round(st.stdev(vals), 2) if len(vals) > 1 else 0,
                    "udp_jitter_ms": round(st.mean(jit), 3) if jit else None,
                    "udp_loss_pct": round(st.mean(loss), 3) if loss else None})
    if tp_rows:
        df = pd.DataFrame(tp_rows); df.to_csv(out / "throughput_summary.csv", index=False)
        md += ["## Throughput (iperf3)\n", mdt(df), "\n"]
        tests = ["tcp_uplink", "tcp_downlink", "udp_uplink"]
        names = list(dict.fromkeys(df.platform))
        fig, ax = plt.subplots(figsize=(7.5, 3.6)); w = 0.8 / len(names)
        for i, n in enumerate(names):
            sub = df[df.platform == n].set_index("test").reindex(tests)
            xs = [k + (i - (len(names) - 1) / 2) * w for k in range(len(tests))]
            ax.bar(xs, sub.mean_mbps, w * 0.92, yerr=sub.std_mbps, color=pcolor[n], label=n,
                   error_kw={"ecolor": INK2, "capsize": 3, "linewidth": 1})
            for x, v, e in zip(xs, sub.mean_mbps, sub.std_mbps.fillna(0)):
                if pd.notna(v): ax.text(x, v + e, f"{v:.0f}", ha="center", va="bottom", fontsize=8, color=INK)
        ax.set_xticks(range(len(tests)), ["TCP uplink", "TCP downlink", "UDP uplink"])
        ax.margins(y=0.12); ax.set_ylabel("Throughput (Mbit/s)"); ax.set_title("Throughput, mean ± std over runs")
        if len(names) > 1: ax.legend()
        save(fig, out, "fig_throughput.png")

    # ---------- Attach (single UE, repeated): time to connectivity, every platform
    tt_rows, at_rows, at_raw = [], [], {}
    for p in platforms:
        d = latest(p, "attach", a.tag)
        if not d: continue
        if (d / "times.csv").exists():
            t = pd.read_csv(d / "times.csv"); t.insert(0, "platform", p.name); t.insert(1, "run", d.parent.name)
            tt_rows.append(t)
        for f in sorted(d.glob("attempt*.log"), key=lambda x: int(re.sub(r"\D", "", x.stem) or 0)):
            for r in parse_ue_log(f):  # only UERANSIM logs carry timestamps
                at_rows.append({"platform": p.name, "run": d.parent.name, "attempt": f.stem, **r})
    if tt_rows:
        df = pd.concat(tt_rows); df.to_csv(out / "attach_times.csv", index=False)
        ok = df[df.success == 1]
        at_raw = {n: g.time_to_ip_ms.tolist() for n, g in ok.groupby("platform")}
        summ = df.groupby("platform").agg(attempts=("attempt", "count"), success=("success", "sum")).join(
            ok.groupby("platform").time_to_ip_ms.agg(mean_ms="mean", median_ms="median", min_ms="min", max_ms="max",
                                                    p95_ms=lambda s: pct(s.tolist(), 95))).round(1).reset_index()
        summ.to_csv(out / "attach_summary.csv", index=False)
        md += ["## Control plane: time from UE start to data connectivity\n",
               "Cell search/sync + registration + PDU session + tunnel setup, measured the same way on every platform.\n",
               mdt(summ), "\n"]
        names = [n for n in (p.name for p in platforms) if n in set(ok.platform)]
        if names:
            fig, ax = plt.subplots(figsize=(6, 3.6))
            bp = ax.boxplot([ok[ok.platform == n].time_to_ip_ms.tolist() for n in names], patch_artist=True, widths=0.5,
                            medianprops={"color": INK, "linewidth": 2},
                            flierprops={"marker": "o", "markersize": 3, "markeredgecolor": INK2})
            for patch, n in zip(bp["boxes"], names):
                patch.set_facecolor(pcolor[n]); patch.set_edgecolor(INK2)
            ax.set_xticks(range(1, len(names) + 1), names)
            ax.set_ylabel("Time to connectivity (ms)"); ax.set_title("UE start → IP address (single UE, repeated)")
            ax.set_ylim(bottom=0)
            save(fig, out, "fig_attach.png")
    if at_rows:
        df = pd.DataFrame(at_rows).dropna(subset=["registration_ms"])
        if not df.empty:
            df.to_csv(out / "attach_breakdown_ueransim.csv", index=False)
            br = df.groupby("platform")[["registration_ms", "pdu_session_ms"]].agg(["mean", "median", "max"]).round(1)
            br.columns = ["_".join(c) for c in br.columns]
            md += ["### Breakdown from UE logs (UERANSIM only; OAI logs have no timestamps)\n", mdt(br.reset_index()), "\n"]

    # ---------- Scaling
    sc_rows = []
    for p in platforms:
        d = latest(p, "scaling", a.tag)
        if not d: continue
        for nd in sorted(d.glob("n*"), key=lambda x: int(x.name[1:])):
            n = int(nd.name[1:]); row = {"platform": p.name, "run": d.parent.name, "ues_requested": n}
            s = (nd / "summary.txt").read_text() if (nd / "summary.txt").exists() else ""
            m = re.search(r"tunnels_up=(\d+) wall_time_s=([\d.]+)", s)
            if m: row["pdu_sessions_up"] = int(m.group(1)); row["all_up_wall_s"] = float(m.group(2))
            if (nd / "ue.log").exists():
                r = pd.DataFrame(parse_ue_log(nd / "ue.log"))
                if not r.empty:
                    row["registered_in_log"] = int(r.registered.sum())
                    row["registration_ms_mean"] = round(r.registration_ms.mean(), 2)
                    row["attach_total_ms_mean"] = round(r.attach_total_ms.mean(), 2)
                    row["attach_total_ms_max"] = round(r.attach_total_ms.max(), 2)
            rt, se, rc = [], 0, 0
            for f in (nd / "ping").glob("*.txt"):
                r_, s_, c_ = parse_ping(f); rt += r_; se += s_; rc += c_
            if se:
                row["rtt_avg_ms"] = round(st.mean(rt), 3) if rt else None
                row["rtt_p95_ms"] = round(pct(rt, 95), 3); row["loss_pct"] = round(100 * (se - rc) / se, 2)
            if "scaling_n%d_ping" % n in invalid_labels(nd): row["note"] = "ping bypassed user plane"
            if (nd / "resources.csv").exists():
                rs = resource_stats(nd / "resources.csv")
                for grp, key in (("Open5GS core", "core"), ("gNB", "gnb"), ("UE(s)", "ue"), ("System total", "sys")):
                    if grp in rs:
                        row[f"{key}_cpu_mean_pct"] = round(rs[grp]["cpu_mean"], 1)
                        row[f"{key}_cpu_peak_pct"] = round(rs[grp]["cpu_peak"], 1)
                        row[f"{key}_ram_peak_mb"] = round(rs[grp]["ram_peak_mb"], 1)
            sc_rows.append(row)
    if sc_rows:
        df = pd.DataFrame(sc_rows); df.to_csv(out / "scaling_summary.csv", index=False)
        cols = [c for c in ["platform", "ues_requested", "pdu_sessions_up", "all_up_wall_s", "attach_total_ms_mean",
                            "rtt_avg_ms", "loss_pct", "core_cpu_mean_pct", "gnb_cpu_mean_pct", "ue_cpu_mean_pct",
                            "core_ram_peak_mb", "ue_ram_peak_mb"] if c in df]
        md += ["## Multi-UE scaling\n", mdt(df[cols]), "\n"]
        names = list(dict.fromkeys(df.platform))
        panels = [("pdu_sessions_up", "UEs with a PDU session"), ("all_up_wall_s", "Time until all UEs up (s)"),
                  ("rtt_avg_ms", "Mean RTT to gateway (ms)"), ("ue_cpu_mean_pct", "UE process CPU, mean (%)"),
                  ("core_cpu_mean_pct", "Open5GS core CPU, mean (%)"), ("ue_ram_peak_mb", "UE process RAM, peak (MB)")]
        panels = [pn for pn in panels if pn[0] in df]
        fig, axes = plt.subplots((len(panels) + 2) // 3, 3, figsize=(11, 3.2 * ((len(panels) + 2) // 3)), squeeze=False)
        for ax, (col, title) in zip(axes.flat, panels):
            for n in names:
                sub = df[df.platform == n].sort_values("ues_requested")
                ax.plot(sub.ues_requested, sub[col], marker="o", markersize=5, linewidth=2, color=pcolor[n], label=n)
            if col == "pdu_sessions_up":
                mx = df.ues_requested.max(); ax.plot([0, mx], [0, mx], "--", color=INK2, linewidth=1, label="ideal")
            ax.set_title(title, fontsize=10); ax.set_xlabel("UEs requested")
            ax.set_ylim(bottom=0)
            ax.set_xticks(sorted(df.ues_requested.unique()))
        for ax in list(axes.flat)[len(panels):]: ax.set_visible(False)
        axes.flat[0].legend(fontsize=8)
        fig.suptitle("Scaling with number of UEs", fontweight="bold"); fig.tight_layout()
        save(fig, out, "fig_scaling.png")

    # ---------- Baseline resources
    rb = []
    for p in platforms:
        cands = sorted(p.glob("*/resources_baseline.csv")) if not a.tag else [p / a.tag / "resources_baseline.csv"]
        cands = [c for c in cands if c.exists()]
        if cands:
            for grp, v in resource_stats(cands[-1]).items():
                rb.append({"platform": p.name, "component": grp, **{k: round(x, 1) for k, x in v.items()}})
    if rb:
        df = pd.DataFrame(rb); df.to_csv(out / "resources_baseline.csv", index=False)
        md += ["## CPU / RAM during the single-UE tests\n", mdt(df), "\n"]

    # ---------- Significance tests (pairwise between platforms)
    st_rows = significance_tests(rtt_raw, at_raw, tp_raw)
    if st_rows:
        sdf = pd.DataFrame(st_rows)
        sdf.to_csv(out / "stat_tests.csv", index=False)
        md += ["## Significance tests\n",
               "Pairwise, two-sided. Latency and attach time: Mann-Whitney U (no normality assumed), "
               "median difference A - B with a 95% bootstrap confidence interval, and the rank-biserial "
               "effect size r = P(A > B) - P(A < B) (between -1 and 1; 0 = no difference). Throughput (3 runs "
               "each): Welch's t-test, and the median columns hold the means. p-values are Holm-corrected across all tests in this table. "
               "Consecutive pings are not fully independent, so treat latency p-values as optimistic and judge "
               "by the effect size and interval.\n",
               mdt(sdf), "\n"]

    if excluded:
        md += ["## Excluded measurements\n", "These runs did not cross the 5G user plane (or failed) and were left out:\n"]
        md += [f"- {e}" for e in excluded]
    (out / "summary.md").write_text("\n".join(md) + "\n")
    print("  summary:", out / "summary.md")

if __name__ == "__main__":
    main()
