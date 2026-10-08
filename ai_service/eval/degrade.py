#!/usr/bin/env python3
"""
Degradation sensitivity: the same frames under conditions that stand in for
a van cabin.

This is the honest answer to the obvious objection that COCO val2017 is
street photography and a UV Express cabin is not. We cannot make COCO into
a cabin, but we can measure how the count holds up as the frame loses the
qualities a cabin takes away -- resolution, light, stillness -- and report
the curve. The manuscript's Scope and Limitations already names in-van
lighting and camera placement as the mechanism's dependency; this measures
that dependency instead of only conceding it.

Conditions, and why each one:

  res_half / res_quarter
      Long side halved, then quartered. A passenger at half the pixel
      height is what a wider-angle cabin camera produces from the same
      seat. Note that an absolute "720p" target would be meaningless here:
      COCO val images cap at 640 px on the long side, so resizing to 720
      would *upscale* and invent detail.

  dim_60 / dim_35
      Brightness at 60% and 35%. An overcast afternoon through tinted van
      glass, and dusk on a cabin light.

  motion_blur
      Horizontal blur, kernel scaled to image width. A moving van on
      Davao road surface; the capture is not a studio shot.

  jpeg_70
      Re-encode at the service's own JPEG_QUALITY. Every snapshot the
      system stores has already been through this, so any count read off a
      stored snapshot inherits the loss.

Degraded images are written to eval/data/degraded/<condition>/ and appended
to the manifest as extra rows carrying the same true_count. Ground truth is
untouched by construction: darkening an image does not change how many
people are in it.

Usage:
    python eval/degrade.py                   # appends to eval/manifest.csv
    python eval/degrade.py --only dim_35
"""

from __future__ import annotations

import argparse
import csv
import os
import sys

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))  # so `import inference` resolves

from inference import JPEG_QUALITY  # noqa: E402  -- the service's own value

from build_coco_manifest import MANIFEST_COLUMNS  # noqa: E402

DEFAULT_MANIFEST = os.path.join(HERE, "manifest.csv")
DEGRADED_DIR = os.path.join(HERE, "data", "degraded")


def _scale(frame: np.ndarray, factor: float) -> np.ndarray:
    h, w = frame.shape[:2]
    # INTER_AREA is the correct filter for shrinking; INTER_LINEAR would
    # alias and make the degradation look worse than the optics would.
    return cv2.resize(frame, (max(int(w * factor), 1), max(int(h * factor), 1)),
                      interpolation=cv2.INTER_AREA)


def _dim(frame: np.ndarray, alpha: float) -> np.ndarray:
    return cv2.convertScaleAbs(frame, alpha=alpha, beta=0)


def _motion_blur(frame: np.ndarray) -> np.ndarray:
    w = frame.shape[1]
    k = max(w // 80, 5) | 1          # odd, ~1.2% of frame width
    kernel = np.zeros((k, k), dtype=np.float32)
    kernel[k // 2, :] = 1.0 / k      # horizontal streak
    return cv2.filter2D(frame, -1, kernel)


def _jpeg(frame: np.ndarray) -> np.ndarray:
    ok, buf = cv2.imencode(".jpg", frame,
                           [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY])
    if not ok:
        raise RuntimeError("JPEG encode failed")
    return cv2.imdecode(buf, cv2.IMREAD_COLOR)


CONDITIONS = {
    "res_half":    lambda f: _scale(f, 0.5),
    "res_quarter": lambda f: _scale(f, 0.25),
    "dim_60":      lambda f: _dim(f, 0.60),
    "dim_35":      lambda f: _dim(f, 0.35),
    "motion_blur": _motion_blur,
    "jpeg_70":     _jpeg,
}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", default=DEFAULT_MANIFEST)
    ap.add_argument("--only", action="append", choices=sorted(CONDITIONS),
                    help="run one condition (repeatable); default is all")
    ap.add_argument("--limit", type=int, default=None,
                    help="degrade only the first N original rows")
    args = ap.parse_args()

    if not os.path.exists(args.manifest):
        print(f"No manifest at {args.manifest}. Run build_coco_manifest.py first.",
              file=sys.stderr)
        return 2

    with open(args.manifest, newline="", encoding="utf-8") as fh:
        all_rows = list(csv.DictReader(fh))

    # Only ever degrade originals. Re-running must not stack conditions on
    # top of conditions, which would produce a label no one can interpret.
    base = [r for r in all_rows if r["condition"] == "original"]
    if args.limit:
        base = base[:args.limit]
    if not base:
        print("No rows with condition=original to degrade.", file=sys.stderr)
        return 1

    wanted = args.only or sorted(CONDITIONS)
    kept = [r for r in all_rows
            if r["condition"] == "original" or r["condition"] not in wanted]
    new_rows = []

    for condition in wanted:
        out_dir = os.path.join(DEGRADED_DIR, condition)
        os.makedirs(out_dir, exist_ok=True)
        transform = CONDITIONS[condition]
        failed = 0
        for row in base:
            frame = cv2.imread(row["image_path"])
            if frame is None:
                failed += 1
                continue
            stem = os.path.splitext(os.path.basename(row["image_path"]))[0]
            dest = os.path.join(out_dir, stem + ".png")
            # Written lossless: the condition under test must be the only
            # loss in the file. jpeg_70 applies its own loss in-memory and
            # is then stored as PNG, so the measurement is not doubled.
            cv2.imwrite(dest, transform(frame))
            new_rows.append({
                "image_path": dest,
                "true_count": row["true_count"],
                "source": row["source"],
                "condition": condition,
                "min_rel_area": row["min_rel_area"],
            })
        note = f"  ({failed} unreadable, skipped)" if failed else ""
        print(f"{condition:<12} {len(base) - failed:>5} frames -> {out_dir}{note}")

    with open(args.manifest, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=MANIFEST_COLUMNS)
        w.writeheader()
        w.writerows(kept + new_rows)

    print(f"\nManifest now {len(kept) + len(new_rows)} rows -> {args.manifest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
