#!/usr/bin/env python3
"""Summarise logs/bench-hwui-LABEL.txt (scripts/bench-hwui.sh): per-frame times from gfxinfo framestats of the
Settings scroll (frames with Flags=0, deduplicated by IntendedVsync) and median cold-start times.
Usage: scripts/bench-summary.py LABEL [LABEL...]"""
import re
import statistics
import sys
from pathlib import Path

LOGS = Path(__file__).resolve().parent.parent / "logs"


def pct(values, p):
    s = sorted(values)
    return s[min(len(s) - 1, int(p / 100 * len(s)))]


def frames(text):
    header, seen, out = None, set(), []
    for line in text.splitlines():
        if not line.startswith("FS,"):
            continue
        cols = line[3:].rstrip(",").split(",")
        if cols[0] == "Flags":
            header = {name: i for i, name in enumerate(cols)}
            continue
        if header is None or cols[0] != "0":
            continue
        f = {k: int(cols[i]) for k, i in header.items() if i < len(cols) and cols[i].lstrip("-").isdigit()}
        if f["IntendedVsync"] in seen:
            continue
        seen.add(f["IntendedVsync"])
        out.append(f)
    return out


def summarise(label):
    text = (LOGS / f"bench-hwui-{label}.txt").read_text()
    fs = frames(text)
    ms = lambda a, b: [(f[b] - f[a]) / 1e6 for f in fs if f.get(a, 0) > 0 and f.get(b, 0) > 0]
    total = ms("IntendedVsync", "FrameCompleted")
    render = ms("SyncStart", "FrameCompleted")
    gpu = ms("SwapBuffers", "GpuCompleted")
    row = {"renderer": re.search(r"^renderer (\S+)", text, re.M).group(1), "frames": len(fs)}
    for name, v in (("frame", total), ("RenderThread", render), ("GPU after swap", gpu)):
        row[f"{name} mean/p50/p90/p99 ms"] = "{:.2f} / {:.2f} / {:.2f} / {:.2f}".format(
            statistics.mean(v), pct(v, 50), pct(v, 90), pct(v, 99))
    jank = [float(p) for p in re.findall(r"^Janky frames: \d+ \(([\d.]+)%\)", text, re.M)]
    row["janky %"] = round(statistics.mean(jank), 2)
    starts = {}
    for pkg, t in re.findall(r"^coldstart (\S+) (\d+)", text, re.M):
        starts.setdefault(pkg.split(".")[-1], []).append(int(t))
    row.update({f"cold start {p} ms": statistics.median(v) for p, v in starts.items()})
    return row


rows = [summarise(l) for l in sys.argv[1:]]
keys = list(dict.fromkeys(k for r in rows for k in r))
print("| " + " | ".join(keys) + " |")
print("|" + "---|" * len(keys))
for r in rows:
    print("| " + " | ".join(str(r.get(k, "")) for k in keys) + " |")
