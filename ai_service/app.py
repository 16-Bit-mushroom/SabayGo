"""
SabayGo AI Node -- YOLOv8 edge passenger-count inference service.

Runs on the in-van edge device (Orange Pi / Raspberry Pi), or on a laptop
with a webcam standing in for the cabin camera during the prototype demo.

Responsibility is deliberately narrow: capture a frame, count people,
blur faces, report. It does NOT know about trips, manifests, or variance
-- the FastAPI backend owns that, because variance must be computed
against the authoritative manifest in MySQL, not by a client.

    Flutter/Operator Console
        -> FastAPI  POST /api/audits/trigger
            -> this service  POST /api/audit/capture
            <- {visual_count, snapshot, timings}
        -- FastAPI reads booked_count, computes variance,
           writes yolov8_audit_logs, returns the audit row
    <- audit result

Run:
    export AI_NODE_API_KEY="something-long-and-random"
    python app.py
"""

from __future__ import annotations

import base64
import logging
import os
import threading
import time
from dataclasses import dataclass, asdict

import cv2
import numpy as np
from flask import Flask, jsonify, request
from ultralytics import YOLO

# --------------------------------------------------------------------------
# Configuration -- environment driven, never hardcoded IPs or paths.
# --------------------------------------------------------------------------
MODEL_PATH        = os.getenv("AI_NODE_MODEL", "yolov8n.pt")
MODEL_VERSION     = os.getenv("AI_NODE_MODEL_VERSION", "yolov8n-1.0")
CAMERA_INDEX      = int(os.getenv("AI_NODE_CAMERA_INDEX", "0"))
# 0.45 rather than the 0.25 default. A dim van cabin produces spurious
# low-confidence detections, and a false positive here means an innocent
# driver gets flagged for revenue leakage. Tune this on real cabin footage
# and report the chosen value in your Results chapter.
CONF_THRESHOLD    = float(os.getenv("AI_NODE_CONF", "0.45"))
IOU_THRESHOLD     = float(os.getenv("AI_NODE_IOU", "0.50"))
JPEG_QUALITY      = int(os.getenv("AI_NODE_JPEG_QUALITY", "70"))
API_KEY           = os.getenv("AI_NODE_API_KEY")  # required in production
PERSON_CLASS_ID   = 0  # COCO class 0 == person
WARMUP_FRAMES     = 5

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("sabaygo-ai-node")

app = Flask(__name__)

log.info("Loading YOLOv8 model: %s", MODEL_PATH)
model = YOLO(MODEL_PATH)
log.info("Model ready.")


# --------------------------------------------------------------------------
# Camera -- held open, guarded by a lock.
#
# The original opened VideoCapture per request: 1-3s of startup latency
# every call, and Flask's threaded dev server means two simultaneous
# audits both grab /dev/video0 and one gets garbage. A persistent handle
# behind a lock fixes both.
# --------------------------------------------------------------------------
class Camera:
    def __init__(self, index: int):
        self._index = index
        self._cap: cv2.VideoCapture | None = None
        self._lock = threading.Lock()

    def _ensure_open(self) -> None:
        if self._cap is None or not self._cap.isOpened():
            log.info("Opening camera index %s", self._index)
            self._cap = cv2.VideoCapture(self._index)
            if not self._cap.isOpened():
                raise RuntimeError(f"Cannot open camera index {self._index}")
            # Warm up so auto-exposure settles before the first real frame.
            for _ in range(WARMUP_FRAMES):
                self._cap.read()

    def capture(self) -> np.ndarray:
        with self._lock:
            self._ensure_open()
            assert self._cap is not None
            # Drain one stale buffered frame, then take the live one.
            self._cap.read()
            ok, frame = self._cap.read()
            if not ok or frame is None:
                self.release()
                raise RuntimeError("Camera returned no frame")
            return frame

    def release(self) -> None:
        if self._cap is not None:
            self._cap.release()
            self._cap = None


camera = Camera(CAMERA_INDEX)


# --------------------------------------------------------------------------
# Privacy
#
# Your manuscript promises a "privacy-compliant blurred snapshot". This is
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


@dataclass
class AuditResult:
    visual_count: int
    confidence_avg: float | None
    model_version: str
    conf_threshold: float
    capture_ms: int
    inference_ms: int
    total_ms: int
    snapshot_b64: str


def require_api_key() -> bool:
    if not API_KEY:
        log.warning("AI_NODE_API_KEY unset -- endpoint is unauthenticated.")
        return True
    return request.headers.get("X-API-Key") == API_KEY


# --------------------------------------------------------------------------
# Routes
# --------------------------------------------------------------------------
@app.get("/health")
def health():
    return jsonify({
        "status": "ok",
        "model": MODEL_PATH,
        "model_version": MODEL_VERSION,
        "camera_index": CAMERA_INDEX,
        "conf_threshold": CONF_THRESHOLD,
    })


# POST, not GET: this activates physical hardware and has side effects.
@app.post("/api/audit/capture")
def capture_audit():
    if not require_api_key():
        return jsonify({"error": "unauthorized"}), 401

    started = time.perf_counter()
    log.info("--- LIVE AUDIT TRIGGERED ---")

    try:
        t0 = time.perf_counter()
        frame = camera.capture()
        capture_ms = int((time.perf_counter() - t0) * 1000)
    except RuntimeError as exc:
        # Fail loudly. The Flutter client must show an error state and must
        # never fabricate a count -- a silently faked audit is worse than
        # no audit, because it looks authoritative.
        log.error("Capture failed: %s", exc)
        return jsonify({"error": "camera_unavailable", "detail": str(exc)}), 503

    try:
        t0 = time.perf_counter()
        results = model(
            frame,
            classes=[PERSON_CLASS_ID],
            conf=CONF_THRESHOLD,
            iou=IOU_THRESHOLD,
            verbose=False,
        )
        inference_ms = int((time.perf_counter() - t0) * 1000)
    except Exception as exc:
        log.exception("Inference failed")
        return jsonify({"error": "inference_failed", "detail": str(exc)}), 500

    det = results[0].boxes
    if det is not None and len(det) > 0:
        xyxy = det.xyxy.cpu().numpy()
        confs = det.conf.cpu().numpy()
    else:
        xyxy = np.empty((0, 4))
        confs = np.empty((0,))

    person_count = int(len(xyxy))
    confidence_avg = round(float(confs.mean()), 3) if person_count else None

    annotated = draw_boxes(blur_faces(frame, xyxy), xyxy, confs)
    ok, buf = cv2.imencode(".jpg", annotated,
                           [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY])
    if not ok:
        return jsonify({"error": "encode_failed"}), 500

    result = AuditResult(
        visual_count=person_count,
        confidence_avg=confidence_avg,
        model_version=MODEL_VERSION,
        conf_threshold=CONF_THRESHOLD,
        capture_ms=capture_ms,
        inference_ms=inference_ms,
        total_ms=int((time.perf_counter() - started) * 1000),
        snapshot_b64=base64.b64encode(buf).decode("utf-8"),
    )

    log.info("Visual count=%s conf_avg=%s inference=%sms",
             person_count, confidence_avg, inference_ms)
    return jsonify(asdict(result))


if __name__ == "__main__":
    if not API_KEY:
        log.warning("Running WITHOUT authentication. Set AI_NODE_API_KEY.")
    log.info("SabayGo AI node listening on :5000")
    try:
        # threaded=False: one camera, one consumer. Serialising requests
        # here is correct, not a limitation.
        app.run(host="0.0.0.0", port=5000, threaded=False)
    finally:
        camera.release()