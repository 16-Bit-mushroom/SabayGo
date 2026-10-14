#!/usr/bin/env bash
# Export YOLOv8n to LiteRT (.tflite) at 320 and 416 px into the app's assets.
#
# Python 3.13 in its own venv, not ai_service's: Ultralytics' LiteRT export
# (litert-torch) targets 3.13, and installing it into the AI node's 3.14
# venv would put a second torch toolchain beside the one serving audits.
#
# The weights are the same pretrained, unmodified yolov8n.pt the AI node
# uses (ai_service/yolov8n.pt; downloaded by Ultralytics if absent).
# Output is FP32; FP16 is chosen at run time (GPU precision, XNNPACK flag).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
venv="$here/.venv"
out="$here/out"
assets="$here/../app/src/main/assets/models"
sizes=(320 416)

if [[ ! -x "$venv/bin/python" ]]; then
    python3.13 -m venv "$venv"
    "$venv/bin/pip" install -q --upgrade pip
    "$venv/bin/pip" install -q --extra-index-url https://download.pytorch.org/whl/cpu \
        "ultralytics==8.4.157" "litert-torch>=0.9.0" "ai-edge-litert>=2.1.4"
fi

mkdir -p "$out" "$assets"
weights="$here/../../ai_service/yolov8n.pt"
[[ -f "$weights" ]] && cp "$weights" "$out/yolov8n.pt"

cd "$out"
for s in "${sizes[@]}"; do
    "$venv/bin/python" -I -c "
from ultralytics import YOLO
YOLO('yolov8n.pt').export(format='litert', imgsz=$s)
" 2>&1 | grep -E "LiteRT|export|Error|error" || true
    mv yolov8n.tflite "$assets/yolov8n_$s.tflite"
done

# Check each model has the layout the app assumes (Detector.kt).
"$venv/bin/python" -I - "$assets" <<'PY'
import sys, pathlib
from ai_edge_litert.interpreter import Interpreter
for f in sorted(pathlib.Path(sys.argv[1]).glob("yolov8n_*.tflite")):
    s = int(f.stem.split("_")[1])
    i = Interpreter(model_path=str(f))
    inp = i.get_input_details()[0]
    outp = i.get_output_details()[0]
    anchors = sum((s // k) ** 2 for k in (8, 16, 32))
    ok = list(inp["shape"]) == [1, 3, s, s] and list(outp["shape"]) == [1, 84, anchors]
    print(f"{f.name}: {f.stat().st_size / 1e6:.1f} MB  in {[int(d) for d in inp["shape"]]} {inp['dtype'].__name__}"
          f"  out {[int(d) for d in outp["shape"]]}  {'OK' if ok else 'UNEXPECTED LAYOUT'}")
    if not ok:
        sys.exit(1)
PY
