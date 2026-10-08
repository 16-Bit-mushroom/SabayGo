# Evaluating the YOLOv8 headcount

What the adviser asked for, and what this directory produces.

## What is actually being measured

The detector is **not trained in this study**. `yolov8n.pt` is Ultralytics'
COCO checkpoint, unmodified. So there are no training curves, no loss, and no
"our model versus a baseline" — claiming otherwise would be describing work
nobody did. The manuscript already concedes the point at §2.3.2.1 ("a
pretrained model rather than one built from scratch").

What *can* be measured, and is:

1. **Counting accuracy** at the deployed operating point — MAE, RMSE, signed
   bias, exact-match and ±1 rates, stratified by how full the van is.
2. **Leakage-detection performance** — the thesis claim. Given the count
   error distribution, how often does `Δ = C_visual − C_booked` accuse an
   honest crew, and how reliably does it catch 1, 2 or 3 hidden passengers?
3. **Operating-point justification** — the same two, swept across confidence
   thresholds, which is what justifies the `0.45` in `inference.py` instead
   of leaving it a matter of taste.
4. **Latency** — mean, median, p95 inference time on a named host.

Point 2 is the one to lead with in the Results chapter. It is the only number
here that speaks directly to the contribution, and it costs nothing extra:
it is arithmetic over the same count errors as point 1. `metrics.py` derives
it, and `test_metrics.py` checks that arithmetic against hand-computed cases.

**No bounding boxes are labelled anywhere in this harness.** The system's
output is a count and its claim is about a variance between two counts, so
count-level ground truth measures the real thing. Box-level mAP would measure
an intermediate the system never looks at, and would cost days of labelling.

## Where the data comes from

**COCO val2017**, filtered. The deployed weights were trained on COCO
*train*2017, so val2017 is genuinely held out, and `instances_val2017.json`
already carries one annotation per person — a ground-truth count for free.

`build_coco_manifest.py` applies three filters, each there to keep ground
truth honest rather than to flatter the result:

| Filter | Why |
|---|---|
| no `iscrowd` regions | a crowd blob covers an unknown number of people, so the image has no countable truth |
| count within 1–14 | van capacity; a 40-pedestrian street scene tells us nothing about a cabin |
| every person ≥ 1% of frame | a seated passenger fills much of a cabin frame, a distant pedestrian fills forty pixels |

Plus 50 zero-person frames, which is the cheapest false-positive measurement
available: any count above zero on an empty frame is the detector inventing a
passenger.

**Degraded copies of those same frames** (`degrade.py`) stand in for cabin
conditions — resolution halved and quartered, brightness at 60% and 35%,
horizontal motion blur, and a re-encode at the service's own `JPEG_QUALITY`.
This does not turn COCO into a van. It does measure how the count holds up as
the frame loses the things a cabin takes away, which is the dependency
§Scope and Limitations already names.

### The honest limitation

These are street photographs, not footage from a camera mounted in a UV
Express cabin. The report says so in its own closing section, and
`MANUSCRIPT_CORRECTIONS.md` carries the Limitations wording.

**The cheap way to fix it:** shoot a parked van at occupancy 0→14 with
classmates, three lighting conditions, two camera positions — about 90 frames,
and the ground truth is exact because you set the occupancy. Append the rows
to `manifest.csv` with `source=staged` and re-run. Table 1b then reports the
staged frames *beside* the COCO ones rather than averaging the two into a
figure that describes neither. No code change; the manifest format is
source-agnostic for exactly this reason.

## Running it

```fish
cd ai_service && source venv/bin/activate.fish

./eval/fetch_coco.sh                      # once, ~1 GB
python eval/test_metrics.py               # the metric arithmetic
python eval/build_coco_manifest.py --limit 20   # smoke
python eval/evaluate.py --limit 20

python eval/build_coco_manifest.py        # the real run
python eval/degrade.py
python eval/evaluate.py --sweep
```

Outputs land in `docs/benchmarks/`, next to the locking experiment:

- `ai_count_<date>.txt` — the tables, for the Results chapter
- `ai_count_<date>.csv` — one row per image per threshold, for re-analysis
- `ai_operating_point_<date>.png` — false alarm against detection, versus
  confidence threshold

`--sweep` multiplies the run time by five. On CPU, budget roughly 100 ms per
inference: the full manifest with all degradations and the sweep is a few
hours, so start it and go and do something else. A single-threshold run over
originals only is minutes.

The figure needs `matplotlib`, which arrives transitively with `ultralytics`.
It is not in `requirements.txt` because the *service* does not need it, and
`evaluate.py` skips the figure with a warning rather than failing if it is
absent.

## Why the harness imports the service's own code

`evaluate.py` counts through `inference.count_people()` — the same function
`app.py` calls on every real audit. If the harness carried its own YOLO handle
and its own thresholds, the numbers in the paper would not be the numbers the
running system produces, and a panel would be right to ask which of the two
the paper was describing. `inference.py` exists to make that impossible; the
only thing `evaluate.py` overrides is the confidence threshold, for the sweep.

## Files

| File | Role |
|---|---|
| `fetch_coco.sh` | download val2017 + annotations, resumable, idempotent |
| `build_coco_manifest.py` | annotations → `manifest.csv`, with the filters above |
| `degrade.py` | the cabin-condition copies, appended to the manifest |
| `metrics.py` | every metric definition, as functions of the count error |
| `test_metrics.py` | hand-checked cases for `metrics.py` |
| `evaluate.py` | runs the detector, writes the tables and the figure |
