# edge_app — the in-van phone

A native Android (Kotlin) app, separate from `mobile/` (brief 5.3). Today
it is only the **benchmark** (CLAUDE.md, step 5.3): YOLOv8n on the
phone's own camera, timed frame by frame, with battery temperature and
level, written to CSV. The edge app proper (door line, ByteTrack, offline
queue, heartbeats against `/edge/*`) grows here after the report exists.

**No frame rate is stated anywhere until `docs/benchmarks/` has the report.**

## Build and install

```bash
tools/export_models.sh      # YOLOv8n → assets/models/yolov8n_{320,416}.tflite
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

The export uses its own Python 3.13 venv (`tools/.venv`), not
`ai_service`'s, and checks each model's input and output layout. The
models are git-ignored, like `*.pt`, so run the export after a clone.

Realme refuses `pm grant` over adb: the first launch asks for the camera
on screen, so unlock the phone and allow it.

## Using it

- **Sweep** runs every model with every backend: 10 s warm-up, 60 s
  measured each, about 10 minutes. It compares the configurations. The
  order is fixed, so later steps start warmer; begin with a cool phone and
  read the thermal column.
- **Run** runs the chosen model and backend until **Stop**. This is the
  full trip on vehicle power. *Min ms between runs* imitates a lower
  detection rate (0 runs flat out).

Backends: `cpu-fp32`, `cpu-fp16` (XNNPACK's FP16 flag), `gpu-fp16`,
`gpu-fp32` (LiteRT's OpenCL/OpenGL accelerator). A backend that fails on
this phone is logged as an `error` row and the sweep continues.

Keep the app on screen: leaving it ends the run (the camera stops
anyway). The screen dims while running so its heat is not counted as the
model's. The back camera is used, at 640 × 480.

## Results

```bash
adb pull /sdcard/Android/data/com.sabaygo.edge/files/ results/
python3 tools/summarise_benchmark.py results/bench_*.csv
```

One row per counted frame. Columns: `time_local, elapsed_s, phase`
(`load`, `warmup`, `measure`, `error`, `end`), `model, input_px, backend,
threads, preprocess_ms, inference_ms` (input upload + run + output read),
`postprocess_ms` (person filter + NMS), `frame_ms` (time since the
previous frame finished), `persons, battery_c, battery_pct, plugged,
thermal_status` (Android's 0–6), `note`.

The report goes in `docs/benchmarks/`. It must say that the phone was
measured with its owner's apps still installed (decided 14 Oct: reset at
deployment), and a short Run after the reset confirms the figures.

The person rule is `ai_service/inference.py`'s (conf 0.45, NMS IoU 0.50,
best class must be person). The export was checked against the PyTorch
model on Ultralytics' sample images: same counts at 320 and 416.
