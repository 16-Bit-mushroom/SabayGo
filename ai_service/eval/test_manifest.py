#!/usr/bin/env python3
"""
Filter cases for eval/build_coco_manifest.py, on a synthetic annotation
file so the test needs neither the 800 MB download nor a model.

These three filters decide what counts as ground truth, so a bug here
would quietly corrupt every number in the Results chapter rather than
crashing. Worth pinning.

    python eval/test_manifest.py
"""
from __future__ import annotations

import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_coco_manifest as b  # noqa: E402

W = H = 100  # a 100x100 frame, so a 10x10 box is exactly 1% of its area


def img(i):
    return {"id": i, "width": W, "height": H, "file_name": f"{i}.jpg"}


def ann(iid, w, h, crowd=0, cat=b.PERSON_CATEGORY_ID):
    return {"image_id": iid, "category_id": cat, "bbox": [0, 0, w, h],
            "iscrowd": crowd}


coco = {
    "images": [img(i) for i in range(1, 8)],
    "annotations": [
        ann(1, 20, 20), ann(1, 20, 20),            # two 4% people    -> keep
        ann(2, 20, 20), ann(2, 5, 5),              # one is 0.25%     -> drop
        ann(3, 20, 20), ann(3, 20, 20, crowd=1),   # a crowd blob     -> drop
        *[ann(4, 20, 20) for _ in range(15)],      # 15 > capacity    -> drop
        ann(5, 10, 10),                            # exactly 1%       -> keep
        ann(6, 30, 30, cat=3),                     # a car, no people -> empty
        # image 7 has no annotations at all                          -> empty
    ],
}

with tempfile.TemporaryDirectory() as tmp:
    path = os.path.join(tmp, "instances.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(coco, fh)
    rows, stats = b.build(path, "/imgs", min_rel_area=0.01, max_count=14,
                          empty_limit=10, limit=None)

got = {os.path.basename(r["image_path"]): r["true_count"] for r in rows}
assert got == {"1.jpg": 2, "5.jpg": 1, "6.jpg": 0, "7.jpg": 0}, got

# Each filter fired exactly once, and for the intended image.
assert stats["dropped_small"] == 1, stats      # image 2, the 0.25% person
assert stats["dropped_crowd"] == 1, stats      # image 3, uncountable
assert stats["dropped_count"] == 1, stats      # image 4, over capacity
assert stats["kept_occupied"] == 2, stats
assert stats["kept_empty"] == 2, stats

# The small-person rule drops the whole IMAGE. Deleting just that person
# from the count would invent a label, and that is the bug this guards.
assert "2.jpg" not in got

# 1% is kept, so the boundary is inclusive and stated correctly in the docs.
by_name = {os.path.basename(r["image_path"]): r for r in rows}
assert by_name["5.jpg"]["min_rel_area"] == 0.01

# min_rel_area is the smallest person in the image, not the first or largest.
assert by_name["1.jpg"]["min_rel_area"] == 0.04

# An image with objects but no people is a zero count, not an exclusion:
# it is the cheapest false-positive measurement in the set.
assert by_name["6.jpg"]["true_count"] == 0
assert by_name["6.jpg"]["min_rel_area"] == ""

print("build_coco_manifest: all filter cases passed")
