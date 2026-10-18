# Phone benchmark, part 1: the bench Sweep (18 Oct 2026)

YOLOv8n on the in-van phone, every model size against every backend, to
choose the configuration for part 2. **Part 2, one full Run on vehicle
power over a real trip, is still to come.** It measures what a trip does to
the phone (heat, battery, throttling). No operating frame rate is set until
it exists. The rates below are bench rates, for comparing configurations.

Raw data: `edge_sweep_2026-10-18.csv` (one row per frame). Table made with
`edge_app/tools/summarise_benchmark.py`. The app and its columns are
described in `edge_app/README.md`.

## The phone

realme 8 5G (RMX3241), Android 13, MediaTek Dimensity 700 (MT6833), Mali-G57
MC2 GPU, 7.5 GiB RAM.

**Not a clean device.** It was measured with its owner's apps installed
(decided 14 Oct; factory reset at deployment, then a short Run to confirm
these figures). Third-party packages present, besides `com.sabaygo.edge`:
Agoda, ColorOS Backup & Restore, Facebook Lite, Google News, Google One,
YouTube Music, Google Contact Keys, Google Play Games, Android
SafetyCore, Google Android Verifier, `com.hk.ugc`, Instagram, realme
Community, Realme Link, WhatsApp, TikTok Lite, eGov PH (17).

## Conditions

- On a desk, indoors, powered over USB from a laptop (charging: 70 % → 72 %).
- The phone started warm: battery 40.6 °C at the first step, after a
  stopped Sweep an hour earlier.
- Back camera at 640 × 480, pointed at a screen showing five people. The
  model counted 5 on every measured frame, so box merging (post ms) ran
  with people in view.
- 4 CPU threads (not varied). Each step: load, 10 s warm-up, 60 s measured.
  The order is fixed, so later steps start warmer.
- Started 14:10:00, complete after 9.5 min, no step failed.

## Results

| model | backend | threads | frames | pre ms | inference ms mean / p50 / p95 | post ms | frames/s | battery °C start → end (max) | battery % | worst thermal |
|---|---|---|---|---|---|---|---|---|---|---|
| yolov8n_320 | cpu-fp32 | 4 | 1228 | 3.0 | 42.3 / 41.9 / 45.7 | 0.2 | 20.5 | 40.6 → 41.1 (41.1) | 70 → 70 | 0 |
| yolov8n_320 | cpu-fp16 | 4 | 1796 | 3.1 | 26.2 / 26.0 / 29.2 | 0.1 | 29.9 | 41.1 → 42.1 (42.1) | 70 → 71 | 0 |
| yolov8n_320 | gpu-fp16 | – | 936 | 10.0 | 47.0 / 45.9 / 58.6 | 0.4 | 15.6 | 42.1 → 42.1 (42.1) | 71 → 71 | 0 |
| yolov8n_320 | gpu-fp32 | – | 858 | 10.1 | 53.1 / 52.7 / 57.0 | 0.4 | 14.3 | 42.1 → 42.0 (42.1) | 71 → 71 | 0 |
| yolov8n_416 | cpu-fp32 | 4 | 744 | 5.1 | 72.0 / 71.6 / 77.1 | 0.2 | 12.4 | 41.9 → 42.1 (42.1) | 71 → 71 | 0 |
| yolov8n_416 | cpu-fp16 | 4 | 1103 | 5.4 | 45.4 / 45.2 / 49.5 | 0.2 | 18.4 | 42.1 → 43.0 (43.0) | 71 → 71 | 0 |
| yolov8n_416 | gpu-fp16 | – | 828 | 16.0 | 49.8 / 49.4 / 54.4 | 0.4 | 13.8 | 43.3 → 43.3 (43.3) | 72 → 72 | 0 |
| yolov8n_416 | gpu-fp32 | – | 550 | 17.2 | 85.0 / 79.7 / 122.1 | 0.4 | 9.2 | 43.1 → 42.9 (43.1) | 72 → 72 | 0 |

Model load: CPU 56–82 ms; GPU 1.5–2.1 s.

## What it shows

1. **CPU with FP16 is the fastest at both sizes:** 26.2 ms mean inference
   at 320 px, 45.4 ms at 416 px.
2. **The GPU is slower than the CPU's FP16 path on this phone.** It also
   loads 25–35 times slower and spends 10–17 ms per frame moving the input
   to the GPU (pre ms). At 416 px FP32 its p95 reaches 122 ms.
3. **At 320 px, CPU FP16 kept up with the camera.** Its work per frame was
   29.4 ms (pre + inference + post), but frames arrived every 33.4 ms: the
   camera delivers about 30 a second. Its 29.9 frames/s is the camera's
   limit, not the model's.
4. **Nothing throttled.** Android's thermal status stayed 0 throughout, and
   the battery rose 2.7 °C in 9.5 min while charging. Ten minutes on a desk
   say nothing about a trip in a van, which is part 2's question.

## Not measured here

- Heat, battery and throttling over a whole trip, on vehicle power, in a
  van's cabin (part 2).
- The rest of the edge app running beside the model: ByteTrack, the
  offline queue, uploads, GPS. They take CPU from the same cores.
- Thread counts other than 4.
- Counting accuracy at 320 or 416 px. The COCO evaluation
  (`ai_count_2026-10-09_full.txt`) is at 640 px; the cabin view is not yet
  measured at any size.
