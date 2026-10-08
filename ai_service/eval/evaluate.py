#!/usr/bin/env python3
"""
Run the deployed detector over the manifest and write the Results tables.

The counts come from `inference.count_people`, which is the function the
Flask service itself calls on every audit. That is deliberate: if this
harness loaded its own YOLO handle with its own thresholds, the numbers
printed here would not be the numbers the running system produces, and a
panel would be right to ask which of the two the paper was describing.

Outputs, all under docs/benchmarks/ alongside the locking experiment:

    ai_count_<date>.csv          one row per image per threshold
    ai_count_<date>.txt          the summary tables
    ai_operating_point_<date>.png  false-alarm vs detection against conf

Usage:
    python eval/evaluate.py --limit 20            # smoke run
    python eval/evaluate.py                       # at the configured conf
    python eval/evaluate.py --sweep               # full threshold sweep
"""

from __future__ import annotations

import argparse
import csv
import os
import platform
import sys
import textwrap
from datetime import date, datetime

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
AI_SERVICE = os.path.dirname(HERE)
REPO = os.path.dirname(AI_SERVICE)
sys.path.insert(0, AI_SERVICE)
sys.path.insert(0, HERE)

import inference                                    # noqa: E402
import metrics                                      # noqa: E402

BENCHMARKS = os.path.join(REPO, "docs", "benchmarks")
SWEEP = [0.25, 0.35, 0.45, 0.55, 0.65]
RESULT_COLUMNS = ["image_path", "source", "condition", "conf", "true_count",
                  "visual_count", "error", "confidence_avg", "inference_ms",
                  "min_rel_area"]


# --------------------------------------------------------------------------
# Running the detector
# --------------------------------------------------------------------------
def run(rows: list[dict], confs: list[float], progress_every: int) -> list[dict]:
    results, unreadable = [], 0
    total = len(rows) * len(confs)
    done = 0

    for row in rows:
        frame = cv2.imread(row["image_path"])
        if frame is None:
            unreadable += 1
            continue
        for conf in confs:
            det = inference.count_people(frame, conf=conf)
            true_count = int(row["true_count"])
            results.append({
                "image_path": row["image_path"],
                "source": row["source"],
                "condition": row["condition"],
                "conf": conf,
                "true_count": true_count,
                "visual_count": det.count,
                "error": det.count - true_count,
                "confidence_avg": det.confidence_avg,
                "inference_ms": det.inference_ms,
                "min_rel_area": row["min_rel_area"],
            })
            done += 1
            if progress_every and done % progress_every == 0:
                print(f"  {done}/{total} inferences", file=sys.stderr, flush=True)

    if unreadable:
        print(f"  {unreadable} images unreadable, skipped", file=sys.stderr)
    return results


def subset(results: list[dict], **where) -> np.ndarray:
    """Error array for the rows matching every key=value in `where`."""
    sel = [r for r in results
           if all(r[k] == v for k, v in where.items())]
    return np.array([r["error"] for r in sel], dtype=int), sel


# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------
def rule(title: str) -> str:
    return f"\n{title}\n{'=' * 70}\n"


def pct(x: float) -> str:
    return f"{x * 100:5.1f}%"


def framing_note(rows: list[dict]) -> str:
    """
    The smallest person in the set, read off the manifest rather than
    assumed. build_coco_manifest.py applies the filter; stating the value it
    actually produced keeps the report true for a hand-edited or appended
    manifest too.
    """
    areas = [float(r["min_rel_area"]) for r in rows
             if r.get("min_rel_area") not in (None, "")]
    if not areas:
        return "not recorded in this manifest"
    return (f"smallest person observed = {min(areas):.2%} of frame area "
            f"({len(areas)} of {len(rows)} rows recorded)")


def header(results: list[dict], rows: list[dict], confs: list[float],
           manifest: str, min_rel_area: str) -> list[str]:
    try:
        import torch
        device = "cuda" if torch.cuda.is_available() else "cpu"
        if device == "cuda":
            device = f"cuda ({torch.cuda.get_device_name(0)})"
    except Exception:
        device = "unknown"

    conditions = sorted({r["condition"] for r in results})
    sources = sorted({r["source"] for r in results})
    return [
        "=" * 70,
        "YOLOv8 PASSENGER-COUNT EVALUATION",
        "=" * 70,
        "",
        f"Date                 : {date.today().isoformat()}",
        f"Model                : {inference.MODEL_PATH} "
        f"({inference.MODEL_VERSION})",
        f"Deployed conf / iou  : {inference.CONF_THRESHOLD} / "
        f"{inference.IOU_THRESHOLD}",
        f"Thresholds evaluated : {', '.join(str(c) for c in confs)}",
        f"Host                 : {platform.processor() or platform.machine()}, "
        f"{device}",
        f"Manifest             : {os.path.relpath(manifest, REPO)}",
        f"Sources              : {', '.join(sources)}",
        f"Conditions           : {', '.join(conditions)}",
        f"Frames / inferences  : {len(rows)} / {len(results)}",
        f"Cabin framing        : {min_rel_area}",
        "",
        "Counts come from inference.count_people(), the same function the",
        "Flask service calls on every audit -- not a second copy of it.",
    ]


def table_counting_by_condition(results, conf) -> list[str]:
    out = [rule(f"TABLE 1  Counting accuracy by condition (conf = {conf})"),
           f"{'condition':<14}{'n':>6}{'MAE':>8}{'RMSE':>8}{'bias':>8}"
           f"{'exact':>8}{'within1':>9}"]
    for condition in sorted({r["condition"] for r in results}):
        err, _ = subset(results, condition=condition, conf=conf)
        m = metrics.counting(err)
        if not m["n"]:
            continue
        out.append(f"{condition:<14}{m['n']:>6}{m['mae']:>8.3f}"
                   f"{m['rmse']:>8.3f}{m['bias']:>+8.3f}"
                   f"{pct(m['exact']):>8}{pct(m['within1']):>9}")
    out += ["",
            "bias is signed: negative means the detector counts fewer people",
            "than are present, which is the direction that hides a passenger."]
    return out


def table_by_source(results, conf) -> list[str]:
    """
    Per-source split. This is the table a staged set is added for: it puts
    the real-cabin numbers beside the public-dataset numbers instead of
    averaging the two into a figure that describes neither.
    """
    sources = sorted({r["source"] for r in results})
    if len(sources) < 2:
        return []
    out = [rule(f"TABLE 1b  By source (original, conf = {conf})"),
           f"{'source':<12}{'n':>6}{'MAE':>8}{'bias':>8}{'exact':>8}"
           f"{'false alarm':>13}{'detect k=1':>12}"]
    for source in sources:
        err, _ = subset(results, source=source, condition="original", conf=conf)
        c, lk = metrics.counting(err), metrics.leakage(err)
        if not c["n"]:
            continue
        out.append(f"{source:<12}{c['n']:>6}{c['mae']:>8.3f}{c['bias']:>+8.3f}"
                   f"{pct(c['exact']):>8}{pct(lk['false_alarm_strict']):>13}"
                   f"{pct(lk['detect_strict_k1']):>12}")
    out += ["",
            "Tables 2 to 5 pool the sources. Read this one first to see",
            "whether pooling them is defensible at all."]
    return out


def table_counting_by_band(results, conf) -> list[str]:
    err, sel = subset(results, condition="original", conf=conf)
    true_count = np.array([r["true_count"] for r in sel], dtype=int)
    out = [rule(f"TABLE 2  Counting accuracy by occupancy (original, conf = {conf})"),
           f"{'occupancy':<14}{'n':>6}{'MAE':>8}{'RMSE':>8}{'bias':>8}"
           f"{'exact':>8}{'within1':>9}"]
    for label, m in metrics.by_band(err, true_count):
        out.append(f"{label:<14}{m['n']:>6}{m['mae']:>8.3f}"
                   f"{m['rmse']:>8.3f}{m['bias']:>+8.3f}"
                   f"{pct(m['exact']):>8}{pct(m['within1']):>9}")
    out += ["",
            "The empty-cabin row is the false-positive measurement: any count",
            "above zero there is the detector inventing a passenger."]
    return out


def table_leakage(results, conf) -> list[str]:
    err, _ = subset(results, condition="original", conf=conf)
    m = metrics.leakage(err)
    out = [rule(f"TABLE 3  Leakage detection (original, conf = {conf})"),
           "Two alert rules, both of which the manuscript states somewhere:",
           "  strict   delta != 0   (section 2.3.2.1 reconciliation formula)",
           "  leakage  delta >  0   (section 2.3.4 functional requirement)",
           "",
           f"{'':<34}{'strict':>10}{'leakage':>10}",
           f"{'false alarm, honest crew (k=0)':<34}"
           f"{pct(m['false_alarm_strict']):>10}{pct(m['false_alarm_leakage']):>10}"]
    for k in metrics.LEAKAGE_K:
        out.append(f"{'detection, ' + str(k) + ' hidden passenger(s)':<34}"
                   f"{pct(m[f'detect_strict_k{k}']):>10}"
                   f"{pct(m[f'detect_leakage_k{k}']):>10}")
    out += ["",
            f"{'false alarms that over-count':<34}{pct(m['false_over']):>10}",
            f"{'false alarms that under-count':<34}{pct(m['false_under']):>10}",
            "",
            "Blind spot -- the strict rule misses leakage of exactly k only",
            "when the detector undercounts by exactly k, so the two errors",
            "cancel and delta reads zero:"]
    for k in metrics.LEAKAGE_K:
        out.append(f"  err == -{k} (hides {k}) : {pct(m[f'blindspot_k{k}'])}")
    return out


def table_leakage_by_band(results, conf) -> list[str]:
    """
    Leakage performance split by how full the van is.

    Table 3 pools every frame, and the COCO subset is dominated by one- and
    two-person images, so the pooled figure describes a nearly empty van.
    A UV Express van is interesting when it is full -- that is when fares
    are worth hiding and when passengers occlude each other. Pooling the
    two hides the fact that the mechanism behaves completely differently at
    the two ends, so this table exists to stop the headline number being
    read as if it applied to a full cabin.
    """
    err, sel = subset(results, condition="original", conf=conf)
    true_count = np.array([r["true_count"] for r in sel], dtype=int)
    out = [rule(f"TABLE 3b  Leakage detection by occupancy (conf = {conf})"),
           "The decision-relevant table. Read it before Table 3.",
           "",
           f"{'':<12}{'':>6}{'  ---- strict (delta != 0) ----':>32}"
           f"{'  -- leakage (delta > 0) --':>28}",
           f"{'occupancy':<12}{'n':>6}{'false alarm':>13}{'det k=1':>10}"
           f"{'det k=2':>9}{'false alarm':>14}{'det k=1':>10}{'det k=2':>9}"]
    for label, lo, hi in metrics.BANDS:
        mask = (true_count >= lo) & (true_count <= hi)
        if not mask.any():
            continue
        m = metrics.leakage(err[mask])
        out.append(f"{label:<12}{m['n']:>6}"
                   f"{pct(m['false_alarm_strict']):>13}"
                   f"{pct(m['detect_strict_k1']):>10}"
                   f"{pct(m['detect_strict_k2']):>9}"
                   f"{pct(m['false_alarm_leakage']):>14}"
                   f"{pct(m['detect_leakage_k1']):>10}"
                   f"{pct(m['detect_leakage_k2']):>9}")
    out += ["",
            "Both rules degrade as the van fills, in opposite ways. The",
            "strict rule accuses more and more honest crews; the leakage",
            "rule stays quiet but stops catching anything. The cause is the",
            "same in both: the detector undercounts when passengers occlude",
            "each other (see the bias column of Table 2), and on a full van",
            "an undercount of one or two is indistinguishable from a fare",
            "that was never logged.",
            "",
            "Any claim about catching revenue leakage has to be made at the",
            "occupancy the claim is about. A figure from a two-passenger",
            "frame does not transfer to a fourteen-seat cabin."]
    return out


def table_sweep(results, confs) -> list[str]:
    out = [rule("TABLE 4  Threshold sweep (original frames)"),
           "Both rules, because they move in OPPOSITE directions here and a",
           "sweep showing only one invites the wrong conclusion.",
           "",
           f"{'':>6}{'':>8}{'':>8}{'  --- strict (delta != 0) ---':>30}"
           f"{'  --- leakage (delta > 0) ---':>30}",
           f"{'conf':>6}{'MAE':>8}{'exact':>8}{'false alarm':>13}{'det k=1':>9}"
           f"{'':>8}{'false alarm':>13}{'det k=1':>9}"]
    for conf in confs:
        err, _ = subset(results, condition="original", conf=conf)
        c, lk = metrics.counting(err), metrics.leakage(err)
        if not c["n"]:
            continue
        marker = "  <- deployed" if conf == inference.CONF_THRESHOLD else ""
        out.append(f"{conf:>6}{c['mae']:>8.3f}{pct(c['exact']):>8}"
                   f"{pct(lk['false_alarm_strict']):>13}"
                   f"{pct(lk['detect_strict_k1']):>9}"
                   f"{'':>8}{pct(lk['false_alarm_leakage']):>13}"
                   f"{pct(lk['detect_leakage_k1']):>9}{marker}")
    out += ["",
            "Read both halves before concluding anything. Lowering the",
            "threshold recovers missed people, so UNDERcounting falls -- and",
            "the strict rule, which fires on an undercount, improves. But",
            "the recovered detections are not all real, so OVERcounting",
            "rises, and the leakage rule fires only on an overcount, so its",
            "false-alarm rate gets worse. The two columns disagree, and a",
            "sweep that printed only the strict half would read as though a",
            "lower threshold were free.",
            "",
            "Which half matters depends on the alert rule the cooperative",
            "actually adopts (see TABLE 3b and MANUSCRIPT_CORRECTIONS.md",
            "section 9). Under delta > 0 a false alarm is a false ACCUSATION",
            "of an honest crew, so its cost is not symmetric with a miss.",
            "That is a policy judgement, not a number this table can settle;",
            "what the table does is price the choice."]
    return out


def table_latency(results, conf) -> list[str]:
    out = [rule(f"TABLE 5  Inference latency (conf = {conf}, ms)"),
           f"{'condition':<14}{'n':>6}{'mean':>9}{'median':>9}{'p95':>9}{'max':>9}"]
    for condition in sorted({r["condition"] for r in results}):
        sel = [r for r in results
               if r["condition"] == condition and r["conf"] == conf]
        m = metrics.latency(np.array([r["inference_ms"] for r in sel], dtype=float))
        if not m["n"]:
            continue
        out.append(f"{condition:<14}{m['n']:>6}{m['mean']:>9.1f}"
                   f"{m['median']:>9.1f}{m['p95']:>9.1f}{m['max']:>9.1f}")
    out += ["",
            "Measured on the host named above. The Orange Pi 5 figure in",
            "section 2.3.4's hardware table is NOT measured here and must not",
            "be reported as if it were -- the van kit is not yet installed.",
            "Resolution conditions do not change latency much because",
            "Ultralytics letterboxes every frame to imgsz=640 regardless, so",
            "res_half measures lost information, not a smaller workload."]
    return out


def caveats(sources: list[str], conditions: list[str]) -> list[str]:
    # Written from the manifest, not from an assumption about it. A report
    # that claims COCO when someone has appended staged rows would be a
    # false statement in the one section whose job is to be candid.
    out = [rule("WHAT THIS DOES NOT MEASURE")]
    if "coco" in sources:
        out += [
            "The COCO frames are held-out val2017 photographs filtered to",
            "van-like occupancy and framing. They are street photography, not",
            "footage from a camera mounted in a UV Express cabin.",
        ]
    degraded = [c for c in conditions if c != "original"]
    if degraded:
        out += textwrap.wrap(
            f"The degraded conditions ({', '.join(degraded)}) stand in for "
            f"cabin conditions by removing resolution, light and stillness "
            f"from those same frames. They approximate the loss a cabin "
            f"imposes; they do not reproduce a cabin.", width=70)
    if "staged" in sources:
        out += [
            "The staged frames were shot in a van at known occupancy, so",
            "their ground truth is exact and their framing is real. Read the",
            "per-source split as the closest figure to deployment.",
        ]
    out += [
        "",
        "So these figures characterise the detector and the alert rules built",
        "on it at the system's operating point.",
    ]
    if "staged" not in sources:
        out += [
            "In-cabin accuracy under real seat geometry, occlusion between",
            "rows and Davao afternoon glare remains to be established once",
            "the van kit is installed.",
            "",
            "Adding a staged set closes this: shoot a parked van at known",
            "occupancy, append the rows to the manifest with source=staged,",
            "and re-run. Table 1b then reports it beside these figures",
            "instead of averaging the two together.",
        ]
    return out


# --------------------------------------------------------------------------
# Operating-point figure
# --------------------------------------------------------------------------
def write_figure(results, confs, path) -> bool:
    if len(confs) < 2:
        return False
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as exc:
        print(f"  figure skipped: {exc}", file=sys.stderr)
        return False

    fa, d1, d2 = [], [], []
    for conf in confs:
        err, _ = subset(results, condition="original", conf=conf)
        m = metrics.leakage(err)
        fa.append(m["false_alarm_strict"] * 100)
        d1.append(m["detect_strict_k1"] * 100)
        d2.append(m["detect_strict_k2"] * 100)

    fig, ax = plt.subplots(figsize=(7, 4.5))
    ax.plot(confs, d1, "o-", label="detects 1 hidden passenger")
    ax.plot(confs, d2, "s-", label="detects 2 hidden passengers")
    ax.plot(confs, fa, "^--", label="false alarm, honest crew")
    ax.axvline(inference.CONF_THRESHOLD, color="grey", lw=1, ls=":")
    ax.annotate(f"deployed\n{inference.CONF_THRESHOLD}",
                (inference.CONF_THRESHOLD, 50), fontsize=8, color="grey",
                ha="center", va="center",
                bbox=dict(fc="white", ec="none", alpha=0.8))
    ax.set_xlabel("confidence threshold")
    ax.set_ylabel("rate (%)")
    ax.set_title("Reconciliation operating point")
    ax.set_ylim(0, 100)
    ax.grid(alpha=0.3)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return True


# --------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", default=os.path.join(HERE, "manifest.csv"))
    ap.add_argument("--conf", type=float, default=None,
                    help="single threshold (default: the deployed value)")
    ap.add_argument("--sweep", action="store_true",
                    help=f"evaluate at {SWEEP} instead of one threshold")
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--progress-every", type=int, default=250)
    ap.add_argument("--out-dir", default=BENCHMARKS)
    ap.add_argument("--tag", default="", help="suffix for the output filenames")
    args = ap.parse_args()

    if not os.path.exists(args.manifest):
        print(f"No manifest at {args.manifest}. "
              f"Run eval/build_coco_manifest.py first.", file=sys.stderr)
        return 2

    with open(args.manifest, newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    if args.limit:
        rows = rows[:args.limit]
    if not rows:
        print("Manifest is empty.", file=sys.stderr)
        return 1

    confs = SWEEP if args.sweep else [args.conf or inference.CONF_THRESHOLD]
    primary = args.conf or inference.CONF_THRESHOLD
    if primary not in confs:
        primary = confs[len(confs) // 2]

    print(f"Evaluating {len(rows)} frames at conf {confs} ...", file=sys.stderr)
    results = run(rows, confs, args.progress_every)
    if not results:
        print("No images could be read.", file=sys.stderr)
        return 1

    os.makedirs(args.out_dir, exist_ok=True)
    # Minute precision, not just the date. Two runs on one day is the
    # normal case -- a smoke run then a real one, or a re-run after a fix --
    # and a date-only stamp let the second silently overwrite the first,
    # which briefly left a .txt and a .csv here from different runs.
    stamp = datetime.now().strftime("%Y-%m-%d_%H%M")
    stamp += f"_{args.tag}" if args.tag else ""
    csv_path = os.path.join(args.out_dir, f"ai_count_{stamp}.csv")
    txt_path = os.path.join(args.out_dir, f"ai_count_{stamp}.txt")
    png_path = os.path.join(args.out_dir, f"ai_operating_point_{stamp}.png")

    with open(csv_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=RESULT_COLUMNS)
        w.writeheader()
        w.writerows(results)

    lines = header(results, rows, confs, args.manifest, framing_note(rows))
    lines += table_counting_by_condition(results, primary)
    lines += table_by_source(results, primary)
    lines += table_counting_by_band(results, primary)
    lines += table_leakage(results, primary)
    lines += table_leakage_by_band(results, primary)
    if len(confs) > 1:
        lines += table_sweep(results, confs)
    lines += table_latency(results, primary)
    lines += caveats(sorted({r["source"] for r in results}),
                     sorted({r["condition"] for r in results}))

    report = "\n".join(lines) + "\n"
    with open(txt_path, "w", encoding="utf-8") as fh:
        fh.write(report)

    print(report)
    print(f"per-image rows -> {os.path.relpath(csv_path, REPO)}")
    print(f"summary        -> {os.path.relpath(txt_path, REPO)}")
    if write_figure(results, confs, png_path):
        print(f"figure         -> {os.path.relpath(png_path, REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
