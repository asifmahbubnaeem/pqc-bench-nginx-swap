#!/usr/bin/env python3
"""
Phase 7 analysis. Reads every run under results/ and writes:

  summary.md            footprint table, per-run table, per-event table
  <run>/timeline.png    per-second throughput / errors / latency / PQ share / masters+RSS,
                        with server events drawn as vertical lines

Usage: python3 analyze.py [results] [--vcpus=2]

Event windows: each nginx event (reload, usr2, winch, quit, hup) gets a window of
WINDOW_S seconds after it. Errors and p99 inside the window are compared with the
run's "quiet" baseline (all seconds after warm-up that are in no window).
"""
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

WINDOW_S = 3.0
EVENT_KINDS = ("reload", "usr2", "winch", "quit", "hup")

# reference palette (dataviz skill)
BLUE, ORANGE, AQUA, RED = "#2a78d6", "#eb6834", "#1baf7a", "#d03b3b"
INK2, FAINT, SURFACE = "#52514e", "#cfcec9", "#fcfcfb"


def first_existing(d: Path, *names):
    for n in names:
        if (d / n).exists():
            return d / n
    return None


def load_run(d: Path):
    meta = json.loads((d / "meta.json").read_text())
    ev = []
    if (d / "events.log").exists():
        for line in (d / "events.log").read_text().splitlines():
            ts, _, rest = line.partition(" ")
            ev.append((float(ts), rest.split(" ")[0], rest))
    events = pd.DataFrame(ev, columns=["ts", "kind", "text"])
    lg = None
    lg_path = first_existing(d, "loadgen.csv", "loadgen.csv.gz")
    if lg_path:
        lg = pd.read_csv(lg_path, dtype={"worker_pid": str, "error": str}, keep_default_na=False)
        lg["ts"] = lg["start_ns"] / 1e9
        lg["ok"] = (lg["status"] == 200) & (lg["error"] == "")
    smp = pd.read_csv(d / "sampler.csv") if (d / "sampler.csv").exists() else None
    acc = None
    acc_path = first_existing(d, "bench.log", "bench.log.gz")
    if acc_path and acc_path.stat().st_size:
        acc = pd.read_csv(acc_path, sep=" ", header=None,
                          compression="gzip" if acc_path.suffix == ".gz" else None,
                          names=["ts", "pid", "conn", "proto", "curve", "status", "rt"])
    return meta, events, lg, smp, acc


def pctl(s, q):
    return float(np.percentile(s, q)) if len(s) else float("nan")


def summarize(d: Path):
    meta, events, lg, smp, acc = load_run(d)
    row = {"run": d.name, **{k: meta[k] for k in ("scenario", "arm", "profile", "rate", "trial")}}
    ev_rows = []
    if smp is not None and len(smp):
        t0 = smp["ts"].min()
        warm = smp[smp["ts"] > t0 + meta.get("warm_s", 30) * (0 if meta["scenario"] in ("idle", "soak") else 1) + 3]
        row["cpu_busy_med_pct"] = round(warm["cpu_busy_pct"].median(), 1) if len(warm) else np.nan
        row["rss_total_mb_med"] = round(smp["rss_kb_total"].median() / 1024, 1)
        row["rss_worker_mb_max"] = round(smp["rss_kb_worker_max"].max() / 1024, 1)
        row["rss_master_mb_max"] = round(smp["rss_kb_master_max"].max() / 1024, 1)
        # steady window = the load period minus 10 s ramp-up and 3 s ramp-down
        if lg is not None and len(lg):
            lo, hi = lg["ts"].min() + 10, lg["ts"].max() - 3
            steady = smp[(smp["ts"] >= lo) & (smp["ts"] <= hi)]
            if len(steady):
                row["cpu_busy_med_pct"] = round(steady["cpu_busy_pct"].median(), 1)
                if "nginx_cpu_cores" in steady.columns:
                    row["nginx_cores_med"] = round(steady["nginx_cpu_cores"].median(), 3)
                win = lg[(lg["ts"] >= lo) & (lg["ts"] <= hi)]
                row["ok_rate"] = round(win["ok"].sum() / max(hi - lo, 1), 1)
                if "nginx_cores_med" in row and row["ok_rate"] > 0:
                    row["cpu_us_per_hs"] = round(row["nginx_cores_med"] * 1e6 / row["ok_rate"], 1)
        # leak check only means something over a long run
        if meta["scenario"] == "soak" and meta.get("duration_s", 0) >= 300 and len(smp) > 30:
            x = (smp["ts"] - smp["ts"].min()) / 3600
            slope = np.polyfit(x, smp["rss_kb_total"] / 1024, 1)[0]
            row["rss_slope_mb_per_h"] = round(slope, 2)
    if lg is not None and len(lg):
        ok = lg[lg["ok"]]
        row["requests"] = len(lg)
        row["errors"] = int((~lg["ok"]).sum())
        row["error_pct"] = round(100 * row["errors"] / len(lg), 4)
        errs = lg.loc[~lg["ok"], "error"].replace("", "http").value_counts()
        row["error_kinds"] = "; ".join(f"{k}={v}" for k, v in errs.items())
        for col, name in (("total_ms", "req"), ("tls_ms", "tls")):
            row[f"{name}_p50"] = round(pctl(ok[col], 50), 2)
            row[f"{name}_p99"] = round(pctl(ok[col], 99), 2)
            row[f"{name}_p999"] = round(pctl(ok[col], 99.9), 2)
        row["worker_pids_seen"] = ok["worker_pid"].nunique()

        # event windows
        marks = events[events["kind"].isin(EVENT_KINDS)]
        in_win = np.zeros(len(lg), bool)
        for _, e in marks.iterrows():
            m = (lg["ts"] >= e["ts"]) & (lg["ts"] < e["ts"] + WINDOW_S)
            in_win |= m.values
            w = lg[m]
            wok = w[w["ok"]]
            ev_rows.append({"run": d.name, "event": e["text"][:70], "t_rel_s": None, "ts": e["ts"],
                            "requests": len(w), "errors": int((~w["ok"]).sum()),
                            "p99_ms": round(pctl(wok["total_ms"], 99), 2),
                            "max_ms": round(float(wok["total_ms"].max()) if len(wok) else np.nan, 2)})
        start = lg["ts"].min() + (meta.get("warm_s", 30) if meta["scenario"] != "soak" else 5)
        base = lg[(~in_win) & (lg["ts"] > start) & lg["ok"]]
        row["quiet_p99"] = round(pctl(base["total_ms"], 99), 2)
        for r in ev_rows:
            r["t_rel_s"] = round(r.pop("ts") - lg["ts"].min(), 1)
            r["quiet_p99_ms"] = row["quiet_p99"]
    if acc is not None and len(acc):
        row["pq_share_pct"] = round(100 * (acc["curve"] == "X25519MLKEM768").mean(), 1)
    return row, ev_rows, (meta, events, lg, smp, acc)


def timeline(d: Path, data):
    meta, events, lg, smp, acc = data
    if lg is None or not len(lg):
        return
    t0 = lg["ts"].min()
    lg = lg.assign(sec=((lg["ts"] - t0)).astype(int))
    per = lg.groupby("sec").agg(ok=("ok", "sum"), n=("ok", "size"))
    per["err"] = per["n"] - per["ok"]
    lat = lg[lg["ok"]].groupby("sec")["total_ms"].quantile([0.5, 0.99]).unstack()

    panels = 4 if acc is not None else 3
    fig, ax = plt.subplots(panels, 1, figsize=(12, 2.3 * panels), sharex=True, facecolor=SURFACE)
    ax[0].plot(per.index, per["ok"], color=BLUE, lw=1.4, label="ok / s")
    ax[0].bar(per.index, per["err"], color=RED, width=1.0, label="errors / s")
    ax[0].set_ylabel("requests / s"); ax[0].legend(loc="lower left", frameon=False, fontsize=8)
    ax[1].plot(lat.index, lat[0.99], color=ORANGE, lw=1.4, label="p99")
    ax[1].plot(lat.index, lat[0.5], color=BLUE, lw=1.4, label="p50")
    ax[1].set_ylabel("request ms"); ax[1].legend(loc="upper left", frameon=False, fontsize=8)
    i = 2
    if acc is not None:
        a = acc.assign(sec=(acc["ts"] - t0).astype(int))
        share = a.groupby("sec")["curve"].apply(lambda c: 100 * (c == "X25519MLKEM768").mean())
        ax[i].plot(share.index, share.values, color=AQUA, lw=1.6)
        ax[i].set_ylim(-5, 105); ax[i].set_ylabel("% X25519MLKEM768")
        i += 1
    if smp is not None and len(smp):
        s = smp.assign(sec=smp["ts"] - t0)
        ax[i].plot(s["sec"], s["rss_kb_total"] / 1024, color=BLUE, lw=1.4, label="nginx RSS total (MB)")
        ax[i].set_ylabel("RSS MB")
        ax[i].set_ylim(0, None)
        # shade seconds where two nginx masters coexist (binary swap in progress)
        two = s[s["masters"] >= 2]["sec"]
        for a_ in ax:
            for x in two:
                a_.axvspan(x - 0.5, x + 0.5, color="#eaf2fc", lw=0, zorder=0)
        if len(two):
            ax[i].text(0.995, 0.04, "shaded: two masters running", transform=ax[i].transAxes,
                       ha="right", fontsize=7, color=INK2)
    for a_ in ax:
        a_.set_facecolor(SURFACE)
        for sp in ("top", "right"):
            a_.spines[sp].set_visible(False)
        for _, e in events[events["kind"].isin(EVENT_KINDS)].iterrows():
            a_.axvline(e["ts"] - t0, color=FAINT, lw=1, zorder=0)
    for _, e in events[events["kind"].isin(EVENT_KINDS)].iterrows():
        ax[0].text(e["ts"] - t0, ax[0].get_ylim()[1], e["kind"], rotation=90, va="top", ha="right",
                   fontsize=7, color=INK2)
    ax[-1].set_xlabel("seconds since load start")
    fig.suptitle(f"{d.name}  —  {meta['arm']} / {meta['profile']} / {meta['rate']} req/s",
                 x=0.01, ha="left", fontweight="bold")
    plt.tight_layout()
    plt.savefig(d / "timeline.png", dpi=130, facecolor=SURFACE)
    plt.close(fig)


def md_table(df):
    if df.empty:
        return "_none_\n"
    cols = list(df.columns)
    out = "| " + " | ".join(cols) + " |\n|" + "---|" * len(cols) + "\n"
    for _, r in df.iterrows():
        out += "| " + " | ".join("" if pd.isna(v) else str(v) for v in r.values) + " |\n"
    return out


ARM_LABEL = {("ossl30", "classical"): "A: OpenSSL 3.0, classical",
             ("ossl35", "classical"): "B: OpenSSL 3.5, classical",
             ("ossl35", "pq"): "B: OpenSSL 3.5, X25519MLKEM768"}
ARM_COLOR = {("ossl30", "classical"): INK2, ("ossl35", "classical"): BLUE, ("ossl35", "pq"): AQUA}


def ladder(runs: pd.DataFrame, root: Path, vcpus: int):
    """CPU ladder v2: trials named L1..Ln. Returns markdown."""
    lad = runs[runs["trial"].astype(str).str.match(r"^L\d+$")].copy()
    if lad.empty or "cpu_us_per_hs" not in lad.columns:
        return ""
    g = lad.groupby(["arm", "profile", "rate"])
    t = g.agg(trials=("trial", "count"),
              ok_rate=("ok_rate", "mean"),
              errors=("errors", "sum"),
              nginx_cores=("nginx_cores_med", "mean"),
              nginx_cores_sd=("nginx_cores_med", "std"),
              us_per_hs=("cpu_us_per_hs", "mean"),
              us_per_hs_sd=("cpu_us_per_hs", "std"),
              host_cpu_pct=("cpu_busy_med_pct", "mean"),
              tls_p50=("tls_p50", "mean"),
              req_p99=("req_p99", "mean")).reset_index().round(3)
    t["arm_label"] = [ARM_LABEL.get((a, p), f"{a}/{p}") for a, p in zip(t["arm"], t["profile"])]
    t.to_csv(root / "ladder.csv", index=False)

    md = "## CPU ladder (nginx processes only, steady window, mean ± sd over trials)\n\n"
    view = t[["arm_label", "rate", "trials", "ok_rate", "errors", "nginx_cores", "nginx_cores_sd",
              "us_per_hs", "us_per_hs_sd", "host_cpu_pct", "tls_p50", "req_p99"]]
    md += md_table(view) + "\n"

    # per-handshake cost: one number per arm = median over error-free rates
    clean = t[t["errors"] == 0]
    per_arm = clean.groupby(["arm", "profile"])["us_per_hs"].median()
    lines = []
    for (a, p), us in per_arm.items():
        ceiling = vcpus * 1e6 / us if us else float("nan")
        lines.append((ARM_LABEL.get((a, p), f"{a}/{p}"), us, ceiling))
    md += (f"### Cost per full handshake and implied ceiling ({vcpus} vCPU, nginx CPU only)\n\n"
           "| arm | µs CPU per handshake (median over clean rates) | implied max handshakes/s at 100% CPU |\n"
           "|---|---|---|\n")
    for lab, us, cap in lines:
        md += f"| {lab} | {us:.0f} | {cap:,.0f} |\n"
    base = per_arm.get(("ossl30", "classical")); b_cl = per_arm.get(("ossl35", "classical"))
    b_pq = per_arm.get(("ossl35", "pq"))
    if base and b_cl and b_pq:
        md += (f"\nOpenSSL 3.0 → 3.5 (classical): {b_cl - base:+.0f} µs/handshake ({100*(b_cl/base-1):+.1f}%).  \n"
               f"Adding X25519MLKEM768 on 3.5: {b_pq - b_cl:+.0f} µs/handshake ({100*(b_pq/b_cl-1):+.1f}%).  \n"
               f"Net, A → B with PQ: {b_pq - base:+.0f} µs/handshake ({100*(b_pq/base-1):+.1f}%).\n\n")

    # chart: cores vs rate, and µs per handshake vs rate
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(12, 4.2), facecolor=SURFACE)
    for key, grp in t.groupby(["arm", "profile"]):
        grp = grp.sort_values("rate")
        c, lab = ARM_COLOR.get(key, INK2), ARM_LABEL.get(key, str(key))
        a1.errorbar(grp["rate"], grp["nginx_cores"], yerr=grp["nginx_cores_sd"].fillna(0),
                    color=c, lw=2, marker="o", ms=5, capsize=3, label=lab)
        a2.errorbar(grp["rate"], grp["us_per_hs"], yerr=grp["us_per_hs_sd"].fillna(0),
                    color=c, lw=2, marker="o", ms=5, capsize=3, label=lab)
    a1.set_xlabel("new TLS 1.3 connections per second"); a1.set_ylabel("nginx CPU (cores)")
    a1.set_title("CPU used by nginx", loc="left", fontsize=11)
    a1.axhline(vcpus, color=FAINT, lw=1)
    a1.text(t["rate"].max(), vcpus, f"{vcpus} vCPU = 100% ", va="bottom", ha="right", fontsize=8, color=INK2)
    a1.set_ylim(0, vcpus * 1.12)
    a2.set_xlabel("new TLS 1.3 connections per second"); a2.set_ylabel("µs of CPU per handshake")
    a2.set_ylim(0, None)
    a2.set_title("CPU per full handshake", loc="left", fontsize=11)
    a2.legend(frameon=False, fontsize=8, loc="lower left")
    for ax in (a1, a2):
        ax.set_facecolor(SURFACE)
        for sp in ("top", "right"):
            ax.spines[sp].set_visible(False)
    fig.suptitle("nginx handshake CPU: OpenSSL 3.0 vs 3.5, classical vs X25519MLKEM768",
                 x=0.01, ha="left", fontweight="bold")
    plt.tight_layout()
    plt.savefig(root / "ladder.png", dpi=150, facecolor=SURFACE)
    plt.close(fig)
    return md


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--vcpus=")]
    vcpus = int(next((a.split("=")[1] for a in sys.argv[1:] if a.startswith("--vcpus=")), 2))
    root = Path(args[0] if args else "results")
    rows, evs = [], []
    for d in sorted(p for p in root.iterdir() if (p / "meta.json").exists()):
        row, ev_rows, data = summarize(d)
        rows.append(row); evs += ev_rows
        if not str(row["trial"]).startswith("L"):
            timeline(d, data)
    runs = pd.DataFrame(rows)
    for c in ("requests", "errors", "worker_pids_seen"):
        if c in runs.columns:
            runs[c] = runs[c].astype("Int64")
    events = pd.DataFrame(evs)

    md = "# Phase 7 results\n\n## Static footprint\n\n"
    for name in ("build/build.csv", "footprint/footprint.csv"):
        f = root / name
        if f.exists():
            md += f"`{name}`\n\n" + md_table(pd.read_csv(f)) + "\n"
    idle = runs[runs["scenario"] == "idle"] if len(runs) else runs
    if len(idle):
        md += "## Idle memory\n\n" + md_table(idle[["arm", "profile", "rss_total_mb_med",
                                                   "rss_master_mb_max", "rss_worker_mb_max"]]) + "\n"
    load = runs[(runs["scenario"] != "idle") & ~runs["trial"].astype(str).str.match(r"^(L\d+|ladder)$")] \
        if len(runs) else runs
    if len(load):
        keep = [c for c in ["scenario", "arm", "profile", "rate", "trial", "requests", "errors", "error_pct",
                            "error_kinds", "req_p50", "req_p99", "req_p999", "tls_p50", "tls_p99", "quiet_p99",
                            "cpu_busy_med_pct", "rss_total_mb_med", "rss_worker_mb_max",
                            "rss_slope_mb_per_h", "pq_share_pct", "worker_pids_seen"] if c in load.columns]
        md += "## Runs under load\n\n" + md_table(load[keep]) + "\n"
    md += ladder(runs, root, vcpus) if len(runs) else ""
    if len(events):
        md += (f"## Event windows ({WINDOW_S:.0f} s after each signal)\n\n"
               + md_table(events[["run", "t_rel_s", "event", "requests", "errors", "p99_ms",
                                  "quiet_p99_ms", "max_ms"]]) + "\n")
    (root / "summary.md").write_text(md)
    runs.to_csv(root / "runs.csv", index=False)
    events.to_csv(root / "events.csv", index=False)
    print(md)
    print(f"wrote {root/'summary.md'}, runs.csv, events.csv, ladder.csv/png and <run>/timeline.png")


if __name__ == "__main__":
    main()
