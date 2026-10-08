#!/usr/bin/env python3
"""
Build the evaluation manifest from COCO val2017.

Why val2017: the deployed weights are Ultralytics' `yolov8n.pt`, trained on
COCO *train*2017. val2017 is therefore genuinely held out, and
`instances_val2017.json` already carries one person annotation per person,
so a ground-truth count comes for free -- no hand labelling at all.

Three selection rules, each of which exists to keep the ground truth honest
rather than to flatter the result:

  1. **No crowd regions.** An annotation with `iscrowd=1` is a blob covering
     an unknown number of people. An image containing one has no countable
     ground truth, so the whole image is dropped. Keeping it and treating
     the blob as one person would invent a label.

  2. **Count within van capacity.** 1..14 people, matching the UV Express
     cabin. A COCO street scene with 40 pedestrians is not a thing this
     system will ever be pointed at, and including it would move the
     headline error without telling us anything about a van.

  3. **Cabin-like framing.** Every person in the image must occupy at least
     `--min-rel-area` of the frame (default 1%). A passenger seated two
     metres from a cabin camera fills a large part of the frame; a pedestrian
     200 m down a COCO street fills forty pixels. Without this rule the
     measured error is dominated by distant specks the system will never be
     asked about. The rule applies per *image*, not per annotation -- an
     image with one tiny person is dropped entirely, rather than that person
     being quietly deleted from its count.

Empty frames are kept separately (`--empty`): a count on an empty cabin is
the cheapest false-positive measurement there is.

Output columns, consumed by evaluate.py and degrade.py:

    image_path,true_count,source,condition,min_rel_area

`source` and `condition` make the file extensible. A staged shoot in a
parked van drops in later as more rows with `source=staged`, and
`evaluate.py` splits its metrics by source with no code change.

Usage:
    ./eval/fetch_coco.sh                 # once, downloads ~800 MB
    python eval/build_coco_manifest.py
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ANN = os.path.join(HERE, "data", "annotations", "instances_val2017.json")
DEFAULT_IMG = os.path.join(HERE, "data", "val2017")
DEFAULT_OUT = os.path.join(HERE, "manifest.csv")

PERSON_CATEGORY_ID = 1  # COCO's own id for 'person' (not YOLO's class 0)

MANIFEST_COLUMNS = ["image_path", "true_count", "source", "condition", "min_rel_area"]


def build(ann_path: str, img_dir: str, min_rel_area: float,
          max_count: int, empty_limit: int, limit: int | None):
    with open(ann_path, encoding="utf-8") as fh:
        coco = json.load(fh)

    images = {img["id"]: img for img in coco["images"]}

    counts: dict[int, int] = {}
    min_area: dict[int, float] = {}
    has_crowd: set[int] = set()

    for ann in coco["annotations"]:
        if ann["category_id"] != PERSON_CATEGORY_ID:
            continue
        iid = ann["image_id"]
        if ann.get("iscrowd", 0):
            has_crowd.add(iid)
            continue
        img = images[iid]
        frame_area = float(img["width"] * img["height"])
        _, _, bw, bh = ann["bbox"]
        rel = (bw * bh) / frame_area
        counts[iid] = counts.get(iid, 0) + 1
        min_area[iid] = min(min_area.get(iid, 1.0), rel)

    rows, stats = [], {
        "total_images": len(images),
        "with_person": len(counts),
        "dropped_crowd": 0,
        "dropped_count": 0,
        "dropped_small": 0,
        "kept_occupied": 0,
        "kept_empty": 0,
    }

    for iid, count in sorted(counts.items()):
        if iid in has_crowd:
            stats["dropped_crowd"] += 1
            continue
        if not 1 <= count <= max_count:
            stats["dropped_count"] += 1
            continue
        if min_area[iid] < min_rel_area:
            stats["dropped_small"] += 1
            continue
        rows.append({
            "image_path": os.path.join(img_dir, images[iid]["file_name"]),
            "true_count": count,
            "source": "coco",
            "condition": "original",
            "min_rel_area": round(min_area[iid], 5),
        })
        stats["kept_occupied"] += 1

    # Empty frames: no person annotation at all, and no crowd blob either.
    empties = [iid for iid in sorted(images)
               if iid not in counts and iid not in has_crowd][:empty_limit]
    for iid in empties:
        rows.append({
            "image_path": os.path.join(img_dir, images[iid]["file_name"]),
            "true_count": 0,
            "source": "coco",
            "condition": "original",
            "min_rel_area": "",
        })
        stats["kept_empty"] += 1

    if limit:
        rows = rows[:limit]
    return rows, stats


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--annotations", default=DEFAULT_ANN)
    ap.add_argument("--images", default=DEFAULT_IMG)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--min-rel-area", type=float, default=0.01,
                    help="smallest person, as a fraction of frame area (default 0.01)")
    ap.add_argument("--max-count", type=int, default=14,
                    help="van capacity; images with more people are dropped")
    ap.add_argument("--empty", type=int, default=50,
                    help="how many 0-person frames to include")
    ap.add_argument("--limit", type=int, default=None,
                    help="truncate the manifest, for a smoke run")
    args = ap.parse_args()

    if not os.path.exists(args.annotations):
        print(f"Annotations not found: {args.annotations}\n"
              f"Run ./eval/fetch_coco.sh first.", file=sys.stderr)
        return 2

    rows, stats = build(args.annotations, args.images, args.min_rel_area,
                        args.max_count, args.empty, args.limit)
    if not rows:
        print("No images survived the selection rules.", file=sys.stderr)
        return 1

    missing = [r for r in rows if not os.path.exists(r["image_path"])][:3]
    if missing:
        print(f"Image files missing, e.g. {missing[0]['image_path']}\n"
              f"Run ./eval/fetch_coco.sh first.", file=sys.stderr)
        return 2

    with open(args.out, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=MANIFEST_COLUMNS)
        w.writeheader()
        w.writerows(rows)

    print(f"val2017 images                 : {stats['total_images']}")
    print(f"  containing people            : {stats['with_person']}")
    print(f"  dropped, crowd region        : {stats['dropped_crowd']}")
    print(f"  dropped, count outside 1-{args.max_count:<2}  : {stats['dropped_count']}")
    print(f"  dropped, person < {args.min_rel_area:.1%} of frame: {stats['dropped_small']}")
    print(f"kept, occupied                 : {stats['kept_occupied']}")
    print(f"kept, empty                    : {stats['kept_empty']}")
    print(f"\nWrote {len(rows)} rows -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
