#!/usr/bin/env bash
# Fetch COCO val2017 images and annotations into eval/data/.
#
# ~1 GB total, downloaded once. Resumable and idempotent.
#
# val2017 is the held-out half of the set the deployed yolov8n weights were
# trained on; see eval/build_coco_manifest.py for why that matters.
#
# Three safeguards, all of which exist because their absence has already
# cost a wasted download here:
#
#   * a lock, so two copies of this script cannot append to one file. Two
#     concurrent curls produced a 999 MB "778 MB" archive that unzip
#     rejected as malformed, and the only symptom was the corrupt size.
#   * .part until complete, so an interrupted download can never be
#     mistaken for a finished one by the next run.
#   * unzip -t before extracting, so a bad archive is caught and deleted
#     rather than half-unpacked into a directory that then looks done.
set -euo pipefail

DATA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/data"
mkdir -p "$DATA"
cd "$DATA"

LOCK="$DATA/.fetch.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "Another fetch_coco.sh is running (or died holding $LOCK)." >&2
  echo "If nothing is running, remove it:  rm -rf '$LOCK'" >&2
  exit 1
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

# Non-empty directory = already unpacked. An empty one is a failed run.
unpacked() { [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null)" ]; }

fetch() {  # url, zip name, directory that proves it is already unpacked
  local url="$1" zip="$2" proof="$3"
  if unpacked "$proof"; then
    echo "already present: $proof"
    return
  fi
  rm -rf "$proof"

  echo "downloading $zip ..."
  curl -fL -C - --retry 3 --retry-delay 5 -o "$zip.part" "$url"

  echo "verifying $zip ..."
  if ! unzip -tqq "$zip.part"; then
    rm -f "$zip.part"
    echo "ERROR: $zip failed its integrity check and was deleted." >&2
    echo "Re-run this script; it will start that file over." >&2
    return 1
  fi

  mv "$zip.part" "$zip"
  echo "unpacking $zip ..."
  unzip -q "$zip"
  rm -f "$zip"
}

# Annotations first, deliberately: they are a quarter the size and they are
# what build_coco_manifest.py and the tests actually read, so the dataset's
# composition can be inspected before committing to the 778 MB of images.
fetch http://images.cocodataset.org/annotations/annotations_trainval2017.zip \
      annotations_trainval2017.zip annotations
fetch http://images.cocodataset.org/zips/val2017.zip \
      val2017.zip val2017

echo
echo "images      : $(find val2017 -name '*.jpg' | wc -l) jpg in $DATA/val2017"
echo "annotations : $DATA/annotations/instances_val2017.json"
