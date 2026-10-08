"""
SabayGo AI Node -- the inference core, shared by the service and the
evaluation harness.

Extracted from app.py so that `eval/evaluate.py` measures *the deployed
code path* rather than a second copy of it. If the harness loaded its own
YOLO handle with its own thresholds, the numbers in the Results chapter
would not be the numbers the running system produces, and that is a fair
question for a panel to ask.

What lives here: configuration, the model handle, the person count, and
the two image treatments that accompany it (privacy blur, annotation).

What deliberately does NOT live here: the camera, the HTTP layer, and the
never-fabricate-a-count error handling. Those are app.py's, because they
are about the service, not about counting. `count_people` lets exceptions
propagate; app.py decides that a failure is a 500 and never a count.
"""

from __future__ import annotations

import logging
import os
import threading
import time
from dataclasses import dataclass

import cv2
import numpy as np
from ultralytics import YOLO

# --------------------------------------------------------------------------
# Configuration -- environment driven, never hardcoded IPs or paths.
# --------------------------------------------------------------------------
MODEL_PATH        = os.getenv("AI_NODE_MODEL", "yolov8n.pt")
MODEL_VERSION     = os.getenv("AI_NODE_MODEL_VERSION", "yolov8n-1.0")
# 0.45 rather than the 0.25 default.
#
# The original reasoning was that a dim van cabin produces spurious
# low-confidence detections. The degradation run (9 Oct) refuted that: at
# 35% brightness the OVERcount rate fell, 2.7% -> 1.9%, with zero false
# detections across fifty empty frames. Dim light makes this detector see
# fewer things, not phantom ones.
#
# The value survives on a different and measured argument. Under the
# delta > 0 alert rule -- where a false alarm is a false accusation against
# an honest crew -- the threshold trades accusation against detection:
#
#     0.25   9.6% false accusation,  87.7% catches one hidden fare
#     0.35   4.6%                    82.8%
#     0.45   2.7%                    77.5%   <- here
#     0.65   0.7%                    65.6%
#
# Where to sit on that curve is the cooperative's judgement, not ours, and
# it should be revisited once staged in-cabin frames exist -- these numbers
# come from street photographs. docs/benchmarks/ai_count_*_full.txt.
CONF_THRESHOLD    = float(os.getenv("AI_NODE_CONF", "0.45"))
IOU_THRESHOLD     = float(os.getenv("AI_NODE_IOU", "0.50"))
JPEG_QUALITY      = int(os.getenv("AI_NODE_JPEG_QUALITY", "70"))
PERSON_CLASS_ID   = 0  # COCO class 0 == person

log = logging.getLogger("sabaygo-ai-node.inference")

# --------------------------------------------------------------------------
# Model handle
#
# Lazy, not loaded at import. Two reasons: importing this module must not
# cost seconds for a caller that only wants a constant (degrade.py wants
# JPEG_QUALITY and nothing else), and app.py configures logging in its own
# module body -- a load at import time would fire its log lines before any
# handler existed and they would vanish.
# --------------------------------------------------------------------------
_model: YOLO | None = None
_model_path: str | None = None
_load_lock = threading.Lock()


def load_model(path: str | None = None) -> YOLO:
    """Load the detector, once. Idempotent for a given path."""
    global _model, _model_path
    want = path or MODEL_PATH
    with _load_lock:
        if _model is None or _model_path != want:
            log.info("Loading YOLOv8 model: %s", want)
            _model = YOLO(want)
            _model_path = want
            log.info("Model ready.")
        return _model


@dataclass
class Detections:
    """Person boxes from one frame. `count` is C_visual."""
    xyxy: np.ndarray          # (n, 4)
    confs: np.ndarray         # (n,)
    inference_ms: int

    @property
    def count(self) -> int:
        return int(len(self.xyxy))

    @property
    def confidence_avg(self) -> float | None:
        return round(float(self.confs.mean()), 3) if self.count else None


def count_people(frame: np.ndarray,
                 conf: float | None = None,
                 iou: float | None = None) -> Detections:
    """
    Count the people in one frame.

    `conf` and `iou` override the configured thresholds. They exist for the
    evaluation harness's threshold sweep; the service passes neither, so
    production behaviour is exactly the configured operating point.
    """
    model = load_model()
    t0 = time.perf_counter()
    results = model(
        frame,
        classes=[PERSON_CLASS_ID],
        conf=CONF_THRESHOLD if conf is None else conf,
        iou=IOU_THRESHOLD if iou is None else iou,
        verbose=False,
    )
    inference_ms = int((time.perf_counter() - t0) * 1000)

    det = results[0].boxes
    if det is not None and len(det) > 0:
        xyxy = det.xyxy.cpu().numpy()
        confs = det.conf.cpu().numpy()
    else:
        xyxy = np.empty((0, 4))
        confs = np.empty((0,))

    return Detections(xyxy=xyxy, confs=confs, inference_ms=inference_ms)


# --------------------------------------------------------------------------
# Privacy
#
# The manuscript promises a "privacy-compliant blurred snapshot". This is
# where that promise is kept, and it matters under RA 10173: the image is
# retained as evidence against a driver, so faces must not be legible.
#
# Heuristic: YOLOv8 gives a whole-person box; the head occupies roughly the
# top quarter. Blur that region. This is intentionally cheap -- running a
# second face-detection model on an Orange Pi would roughly double
# inference time. Document the heuristic and its limitation (profile and
# occluded heads may be partially missed) rather than overclaiming.
# --------------------------------------------------------------------------
def blur_faces(frame: np.ndarray, boxes: np.ndarray) -> np.ndarray:
    out = frame.copy()
    h, w = out.shape[:2]
    for x1, y1, x2, y2 in boxes.astype(int):
        box_h = y2 - y1
        head_y2 = y1 + max(int(box_h * 0.28), 12)
        x1c, y1c = max(x1, 0), max(y1, 0)
        x2c, y2c = min(x2, w), min(head_y2, h)
        if x2c <= x1c or y2c <= y1c:
            continue
        region = out[y1c:y2c, x1c:x2c]
        # Kernel scaled to region size so blur strength is resolution
        # independent; forced odd because GaussianBlur requires it.
        k = max(int(min(region.shape[:2]) / 3) | 1, 15)
        out[y1c:y2c, x1c:x2c] = cv2.GaussianBlur(region, (k, k), 0)
    return out


def draw_boxes(frame: np.ndarray, boxes: np.ndarray, confs: np.ndarray) -> np.ndarray:
    out = frame.copy()
    for (x1, y1, x2, y2), conf in zip(boxes.astype(int), confs):
        cv2.rectangle(out, (x1, y1), (x2, y2), (0, 200, 0), 2)
        cv2.putText(out, f"{conf:.2f}", (x1, max(y1 - 6, 12)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 200, 0), 1, cv2.LINE_AA)
    return out
