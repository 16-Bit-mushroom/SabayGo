#!/usr/bin/env python3
"""Summarise the edge app's benchmark CSVs as Markdown for docs/benchmarks/.

    python3 tools/summarise_benchmark.py results/bench_*.csv > fragment.md

Per model, backend and thread count, over `measure` rows only (warm-up is
left out): frames, mean preprocess / inference / postprocess time, the
inference median and 95th percentile, frames per second from the time
between frames, battery temperature and level at start and end, and the
worst thermal status (0 none, 1 light: throttling starts, 2 moderate,
3 severe, 4 critical). A Run also gets 10-minute windows, which is where
a trip's throttling shows. Failed steps are listed, never dropped.

Standard library only, so it runs anywhere.
"""
import csv
import statistics
import sys
from collections import defaultdict

WINDOW_S = 600


def num(v):
    return float(v) if v not in ("", None) else None


def p(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, round(q * (len(xs) - 1)))]


def mean(xs):
    xs = [x for x in xs if x is not None]
    return statistics.fmean(xs) if xs else None


def f(v, fmt="{:.1f}"):
    return "–" if v is None else fmt.format(v)


def summarise(path):
    with open(path, newline="") as fh:
        rows = list(csv.DictReader(fh))
    print(f"## {path.rsplit('/', 1)[-1]}\n")

    groups = defaultdict(list)
    for r in rows:
        if r["phase"] == "measure":
            groups[(r["model"], r["backend"], r["threads"])].append(r)

    print("| model | backend | threads | frames | pre ms | inference ms mean / p50 / p95 | post ms "
          "| frames/s | battery °C start → end (max) | battery % | worst thermal |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for (model, backend, threads), g in groups.items():
        inf = [num(r["inference_ms"]) for r in g]
        frame = mean([num(r["frame_ms"]) for r in g])
        temps = [num(r["battery_c"]) for r in g if r["battery_c"]]
        pcts = [r["battery_pct"] for r in g if r["battery_pct"]]
        thermal = max(int(r["thermal_status"]) for r in g)
        print(f"| {model} | {backend} | {threads or '–'} | {len(g)} | {f(mean([num(r['preprocess_ms']) for r in g]))} "
              f"| {f(mean(inf))} / {f(p(inf, .5))} / {f(p(inf, .95))} | {f(mean([num(r['postprocess_ms']) for r in g]))} "
              f"| {f(1000 / frame if frame else None)} "
              f"| {f(temps[0] if temps else None)} → {f(temps[-1] if temps else None)} ({f(max(temps) if temps else None)}) "
              f"| {pcts[0] if pcts else '–'} → {pcts[-1] if pcts else '–'} | {thermal} |")

    loads = [r for r in rows if r["phase"] == "load"]
    if loads:
        print("\nModel load: " + "; ".join(f"{r['model']} {r['backend']} {r['note'].removeprefix('load ')}"
                                           for r in loads))
    errors = [r for r in rows if r["phase"] == "error"]
    for r in errors:
        print(f"\n**Failed:** {r['model']} {r['backend']}: {r['note']}")
    end = [r for r in rows if r["phase"] == "end"]
    if end:
        print(f"\nEnded: {end[-1]['note']} after {float(end[-1]['elapsed_s']) / 60:.1f} min.")

    if "_run" in path:
        windows = defaultdict(list)
        for g in groups.values():
            t0 = float(g[0]["elapsed_s"])
            for r in g:
                windows[int((float(r["elapsed_s"]) - t0) // WINDOW_S)].append(r)
        print(f"\n| minutes | frames | inference ms mean | frames/s | battery °C max | battery % end | worst thermal |")
        print("|---|---|---|---|---|---|---|")
        for w, g in sorted(windows.items()):
            frame = mean([num(r["frame_ms"]) for r in g])
            temps = [num(r["battery_c"]) for r in g if r["battery_c"]]
            print(f"| {w * 10}–{w * 10 + 10} | {len(g)} | {f(mean([num(r['inference_ms']) for r in g]))} "
                  f"| {f(1000 / frame if frame else None)} | {f(max(temps) if temps else None)} "
                  f"| {g[-1]['battery_pct'] or '–'} | {max(int(r['thermal_status']) for r in g)} |")
    print()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for path in sys.argv[1:]:
        summarise(path)
