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

A second entry point exists for the same pipeline: a phone acting as the
camera instead of a server-attached webcam.

    ai_capture_app (phone)
        -> this service  POST /api/audit/capture-upload  (multipart image)
        <- {visual_count, snapshot, timings}

Same model, same thresholds, same never-fabricate-a-count rule -- only the
frame's origin differs, so it reuses inference/annotation and just skips
the Camera class.

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

from inference import (
    CONF_THRESHOLD,
    JPEG_QUALITY,
    MODEL_PATH,
    MODEL_VERSION,
    blur_faces,
    count_people,
    draw_boxes,
    load_model,
)

# --------------------------------------------------------------------------
# Configuration -- environment driven, never hardcoded IPs or paths.
#
# Model path, thresholds and JPEG quality live in inference.py, because the
# evaluation harness shares them. What stays here is the camera and the API
# key: service concerns the harness has no use for.
# --------------------------------------------------------------------------
CAMERA_INDEX      = int(os.getenv("AI_NODE_CAMERA_INDEX", "0"))
API_KEY           = os.getenv("AI_NODE_API_KEY")  # required in production
WARMUP_FRAMES     = 5

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("sabaygo-ai-node")

app = Flask(__name__)

# Loaded here rather than on the first request: a cold model load inside an
# audit would add seconds to it, and logging is configured by this point so
# the load's own log lines are visible.
load_model()


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
# Shared inference tail -- capture (server webcam) and capture-upload
# (phone photo) differ only in where `frame` comes from. Everything from
# "run the model" onward is identical, including the never-fabricate-a-
# count error handling, so both routes call this.
# --------------------------------------------------------------------------
def _infer_and_package(frame: np.ndarray, capture_ms: int, started: float):
    try:
        det = count_people(frame)
    except Exception as exc:
        # Fail loudly, never with a number. A fabricated count looks
        # authoritative and would flag an innocent driver.
        log.exception("Inference failed")
        return jsonify({"error": "inference_failed", "detail": str(exc)}), 500

    annotated = draw_boxes(blur_faces(frame, det.xyxy), det.xyxy, det.confs)
    ok, buf = cv2.imencode(".jpg", annotated,
                           [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY])
    if not ok:
        return jsonify({"error": "encode_failed"}), 500

    result = AuditResult(
        visual_count=det.count,
        confidence_avg=det.confidence_avg,
        model_version=MODEL_VERSION,
        conf_threshold=CONF_THRESHOLD,
        capture_ms=capture_ms,
        inference_ms=det.inference_ms,
        total_ms=int((time.perf_counter() - started) * 1000),
        snapshot_b64=base64.b64encode(buf).decode("utf-8"),
    )

    log.info("Visual count=%s conf_avg=%s inference=%sms",
             det.count, det.confidence_avg, det.inference_ms)
    return jsonify(asdict(result))


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
    log.info("--- LIVE AUDIT TRIGGERED (server camera) ---")

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

    return _infer_and_package(frame, capture_ms, started)


# The phone-as-camera path: no server-attached webcam involved, the frame
# arrives as a multipart file. Everything downstream (model, thresholds,
# annotation, response shape) is identical to /api/audit/capture.
@app.post("/api/audit/capture-upload")
def capture_upload_audit():
    if not require_api_key():
        return jsonify({"error": "unauthorized"}), 401

    started = time.perf_counter()
    log.info("--- LIVE AUDIT TRIGGERED (phone upload) ---")

    file = request.files.get("image")
    if file is None or file.filename == "":
        return jsonify({"error": "no_image", "detail": "Missing 'image' file field."}), 400

    t0 = time.perf_counter()
    data = np.frombuffer(file.read(), dtype=np.uint8)
    frame = cv2.imdecode(data, cv2.IMREAD_COLOR)
    decode_ms = int((time.perf_counter() - t0) * 1000)

    if frame is None:
        return jsonify({"error": "decode_failed", "detail": "Not a decodable image."}), 400

    # Reuses the capture_ms field: for this path it times decode rather
    # than a camera grab, which is the equivalent "getting the frame
    # ready" cost.
    return _infer_and_package(frame, decode_ms, started)


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