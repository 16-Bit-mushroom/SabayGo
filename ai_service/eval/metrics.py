#!/usr/bin/env python3
"""
The metric definitions, separated from the runner so they can be reasoned
about (and unit-tested) without a model, a GPU or a gigabyte of images.

Everything here is a function of one array: `err = C_visual - C_true`.

That is not a simplification -- it is the whole point. The system's output
is a count, and its claim is about a *variance between two counts*, so the
count error distribution determines the claim's performance exactly. No
bounding boxes are needed to compute any of it.
"""

from __future__ import annotations

import numpy as np

# Occupancy bands for the stratified table. A 14-seat cabin, split so that
# each band is a situation a dispatcher would recognise.
BANDS = [
    ("0 (empty)",  0,  0),
    ("1-3",        1,  3),
    ("4-7",        4,  7),
    ("8-11",       8, 11),
    ("12-14",     12, 14),
]

LEAKAGE_K = (1, 2, 3)


def counting(err: np.ndarray) -> dict:
    """Accuracy of the count itself."""
    if err.size == 0:
        return {"n": 0}
    return {
        "n": int(err.size),
        "mae": float(np.abs(err).mean()),
        "rmse": float(np.sqrt((err.astype(float) ** 2).mean())),
        # Signed, deliberately. A detector that misses occluded passengers
        # has a negative bias, and that is a different problem from noise.
        "bias": float(err.mean()),
        "exact": float((err == 0).mean()),
        "within1": float((np.abs(err) <= 1).mean()),
    }


def leakage(err: np.ndarray) -> dict:
    """
    What the count error implies for the reconciliation claim.

    For leakage of k undocumented passengers, the manifest reads
    C_booked = C_true - k, so

        delta = C_visual - C_booked = err + k

    Two alert rules appear in the manuscript and they are not the same rule:

      strict   -- delta != 0  (section 2.3.2.1's reconciliation formula:
                  "delta != 0 -> Discrepancy Detected")
      leakage  -- delta >  0  (section 2.3.4's functional requirement:
                  "trigger a revenue leakage alert ... if the physical
                  count exceeds the manifested count")

    Both are reported, because the difference is operationally large: the
    strict rule raises an alert every time the detector miscounts in either
    direction, so it carries the higher false-alarm cost against an honest
    crew, while the leakage rule is blind to undercounting.

    At k = 0 there is nothing to find, so every alert is a false alarm.
    At k >= 1 an alert is a correct detection, and note which case is
    missed: strict misses exactly when err == -k, i.e. when the detector
    happens to undercount by precisely the number of people being hidden.
    That single coincidence is the mechanism's blind spot, and it is worth
    naming in the Results chapter rather than leaving it in a rate.
    """
    if err.size == 0:
        return {"n": 0}
    out = {
        "n": int(err.size),
        "false_alarm_strict": float((err != 0).mean()),
        "false_alarm_leakage": float((err > 0).mean()),
        # Direction of the false alarms, for the discussion.
        "false_over": float((err > 0).mean()),
        "false_under": float((err < 0).mean()),
    }
    for k in LEAKAGE_K:
        out[f"detect_strict_k{k}"] = float((err + k != 0).mean())
        out[f"detect_leakage_k{k}"] = float((err + k > 0).mean())
        out[f"blindspot_k{k}"] = float((err == -k).mean())
    return out


def by_band(err: np.ndarray, true_count: np.ndarray) -> list[tuple[str, dict]]:
    """Counting accuracy stratified by how full the van is."""
    rows = []
    for label, lo, hi in BANDS:
        mask = (true_count >= lo) & (true_count <= hi)
        if mask.any():
            rows.append((label, counting(err[mask])))
    return rows


def latency(ms: np.ndarray) -> dict:
    if ms.size == 0:
        return {"n": 0}
    return {
        "n": int(ms.size),
        "mean": float(ms.mean()),
        "median": float(np.median(ms)),
        "p95": float(np.percentile(ms, 95)),
        "max": float(ms.max()),
    }
