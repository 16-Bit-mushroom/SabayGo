# edge_app — the in-van phone

A native Android (Kotlin) app, separate from `mobile/` (brief 5.3). Two
parts:

- **The edge app** (brief 5.1–5.3): YOLOv8n and ByteTrack on the phone's
  camera, a door line and a driver's seat mask, door events with a
  blurred still, GPS readings, status reports, and an offline queue, all
  sent to the server's `/edge` endpoints.
- **The benchmark** (Benchmark button): YOLOv8n timed frame by frame,
  with battery temperature and level, written to CSV.

**No frame rate is stated anywhere until `docs/benchmarks/` has the van
Run** (part 1, the bench Sweep, is `edge_sweep_2026-10-18.md`).

## The edge app

Code: `track/` (ByteTrack, the door counter: plain Kotlin, unit-tested),
`vision/Detector.kt` (YOLOv8n, CPU FP16 as the Sweep chose), `count/`
(the foreground service, the per-frame pipeline, stills, lens check),
`link/` (settings, server clock, HTTP, the outbox), and the screens.

**Set-up, once per phone.** The Terminal Manager adds the phone in the
console (Phones) and is shown its token once. On the phone: Set-up, the
server (`http://<laptop>:8000/api/v1`) and the token. A debug build also
takes them over adb:
`adb shell am start -n com.sabaygo.edge/.HomeActivity --es server URL --es token TOKEN`.
Then the Checklist (permissions, battery optimisation off, the Realme
switches an app cannot read).

**Each mounting.** The office checks the phone out to a van and a
Dispatcher. The Dispatcher opens the app, taps Door line, drags the
yellow line across the doorway and the red box over the driver's seat,
sets the cabin arrow, Save. The line is kept on the van (migration 031,
`PUT /edge/door-layout`), so the next phone in that van loads it.

**What it does.** Opening the app starts the counting service, which
runs until stopped:
- counts while `GET /edge/session` says so (from assignment until arrival,
  rule 13), and keeps counting for its van when the server has not
  answered for 2 min; otherwise the model runs only to show the screen;
- a confirmed track crossing the line inward is a boarding, outward an
  alighting (its box centre, past a margin, within the drawn segment);
  someone first seen inside did not board; a box centred in the seat mask
  is never tracked;
- each event: an id, the time on the server's clock, the door count after
  it, the tracker number, the last GPS fix, and the SHA-256 of its still
  (every person box pixelated, the line drawn);
- GPS every second while out with a van; a status report every 30 s;
  a covered lens is a dark and uniform frame for 15 s;
- everything goes through the outbox (SQLite on the phone) and is sent
  every 5 s in order (events, readings, reports, stills); a row the server
  refuses for good is set aside on the phone, not deleted.

**Tested.** `./gradlew testDebugUnitTest`: assignment, ByteTrack and the
door counter on made-up frames (14 tests). On the realme 8 5G against the
dev backend (18 Oct): set-up over adb, the session, status reports and
the outbox reach the server. **Not yet tried with people crossing a
door line**, nor in a van.

**Not built yet.** The per-stop cabin snapshot that corrects drift
(brief 5.2 item 6, a later step with its own server endpoint); a
detection rate that rises near stops and door activity (after the Run);
entering the token by QR code.

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

## The benchmark

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

Opening Benchmark stops the counting service (one camera user at a
time). Keep the app on screen: leaving it ends the run (the camera stops
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
