#!/usr/bin/env python3
"""
Hand-checked cases for eval/metrics.py.

The leakage table is the result the thesis leans on, and it is pure
arithmetic over the count-error array, so it can and should be verified
against numbers worked out by hand rather than trusted because it ran.

    python eval/test_metrics.py
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import metrics  # noqa: E402

FAIL = []


def eq(label, got, want, tol=1e-9):
    if abs(got - want) > tol:
        FAIL.append(f"{label}: got {got!r}, want {want!r}")


# err = C_visual - C_true for five frames.
err = np.array([0, 0, -1, 1, -2])

c = metrics.counting(err)
eq("n",       c["n"], 5)
eq("mae",     c["mae"], 0.8)                       # (0+0+1+1+2)/5
eq("rmse",    c["rmse"], np.sqrt(1.2))             # (0+0+1+1+4)/5
eq("bias",    c["bias"], -0.4)                     # (0+0-1+1-2)/5
eq("exact",   c["exact"], 0.4)                     # two zeros
eq("within1", c["within1"], 0.8)                   # all but the -2

m = metrics.leakage(err)
# k=0: nothing is hidden, so every alert is a false accusation.
eq("false_alarm_strict",  m["false_alarm_strict"], 0.6)   # err != 0  -> 3/5
eq("false_alarm_leakage", m["false_alarm_leakage"], 0.2)  # err >  0  -> 1/5
eq("false_over",          m["false_over"], 0.2)
eq("false_under",         m["false_under"], 0.4)          # -1 and -2

# k=1: delta = err + 1. Strict alerts unless err == -1 exactly.
eq("detect_strict_k1",  m["detect_strict_k1"], 0.8)       # err != -1 -> 4/5
eq("detect_leakage_k1", m["detect_leakage_k1"], 0.6)      # err >  -1 -> 3/5
eq("blindspot_k1",      m["blindspot_k1"], 0.2)

# k=2: the one frame that undercounts by 2 is the blind spot.
eq("detect_strict_k2",  m["detect_strict_k2"], 0.8)       # err != -2 -> 4/5
eq("detect_leakage_k2", m["detect_leakage_k2"], 0.8)      # err >  -2 -> 4/5
eq("blindspot_k2",      m["blindspot_k2"], 0.2)

# k=3: no frame undercounts by 3, so nothing is missed.
eq("detect_strict_k3",  m["detect_strict_k3"], 1.0)
eq("detect_leakage_k3", m["detect_leakage_k3"], 1.0)
eq("blindspot_k3",      m["blindspot_k3"], 0.0)

# A perfect detector must never accuse anyone and must catch everything.
perfect = metrics.leakage(np.zeros(10, dtype=int))
eq("perfect false alarm", perfect["false_alarm_strict"], 0.0)
for k in metrics.LEAKAGE_K:
    eq(f"perfect detect k={k}", perfect[f"detect_strict_k{k}"], 1.0)
    eq(f"perfect leakage k={k}", perfect[f"detect_leakage_k{k}"], 1.0)

# A detector that always undercounts by one is invisible to leakage of one:
# delta reads zero and the audit passes with a stowaway aboard.
blind = metrics.leakage(np.full(10, -1, dtype=int))
eq("blind detect k=1", blind["detect_strict_k1"], 0.0)
eq("blind blindspot",  blind["blindspot_k1"], 1.0)
eq("blind detect k=2", blind["detect_strict_k2"], 1.0)

# Bands partition by true occupancy, and drop bands with no frames.
true_count = np.array([0, 2, 5, 9, 13])
bands = dict(metrics.by_band(err, true_count))
assert set(bands) == {"0 (empty)", "1-3", "4-7", "8-11", "12-14"}, sorted(bands)
eq("band 0 n", bands["0 (empty)"]["n"], 1)
eq("band 12-14 mae", bands["12-14"]["mae"], 2.0)

sparse = dict(metrics.by_band(np.array([0, 1]), np.array([1, 2])))
assert set(sparse) == {"1-3"}, sorted(sparse)

lat = metrics.latency(np.array([10.0, 20.0, 30.0, 40.0]))
eq("latency mean",   lat["mean"], 25.0)
eq("latency median", lat["median"], 25.0)
eq("latency max",    lat["max"], 40.0)

# Empty input must not raise; the runner hands it empty subsets routinely.
assert metrics.counting(np.array([], dtype=int))["n"] == 0
assert metrics.leakage(np.array([], dtype=int))["n"] == 0
assert metrics.latency(np.array([]))["n"] == 0

if FAIL:
    print(f"{len(FAIL)} FAILED")
    for f in FAIL:
        print("  " + f)
    sys.exit(1)
print("metrics: all cases passed")
