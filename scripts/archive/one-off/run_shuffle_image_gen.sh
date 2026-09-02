#!/usr/bin/env zsh
# Wrapper around generate_missing_images.py for the 143-exercise shuffle-discovery
# residual list. Splits into chunks of N to avoid argv length issues and to make
# progress observable in the chat log. Skips entries that already have a PNG on
# disk (so the script is safe to re-run after partial completion).
#
# Usage:
#   GEMINI_KEY=$(cd functions && firebase functions:secrets:access GEMINI_API_KEY)
#   scripts/run_shuffle_image_gen.sh "$GEMINI_KEY" [chunk_size]
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <gemini-api-key> [chunk_size=20]" >&2
  exit 1
fi

GEMINI_API_KEY=$1
CHUNK_SIZE=${2:-20}
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
GEN_LIST="$ROOT_DIR/scripts/output/shuffle_image_gen_list.json"
OUT_DIR="$ROOT_DIR/scripts/output"

# Build the to-do list: keys from gen list whose PNG doesn't exist yet
TODO=$(python3 - <<PY
import json
from pathlib import Path
gen = json.load(open("$GEN_LIST"))
out = Path("$OUT_DIR")
needed = []
for ex in gen["exercises"]:
    k = ex["normalized_filename"]
    if not (out / f"{k}.png").exists():
        needed.append(k)
print(",".join(needed))
PY
)

if [[ -z "$TODO" ]]; then
  echo "All 143 images already exist — nothing to generate."
  exit 0
fi

# Convert to array, split into chunks
typeset -a all
all=("${(@s/,/)TODO}")
total=${#all[@]}
echo "[run_shuffle_image_gen] $total images remain to generate (chunk size=$CHUNK_SIZE)"

i=1
chunk_idx=0
while (( i <= total )); do
  chunk_idx=$((chunk_idx + 1))
  end=$((i + CHUNK_SIZE - 1))
  (( end > total )) && end=$total
  chunk=("${all[@]:$((i-1)):$((end-i+1))}")
  joined=${(j:,:)chunk}
  echo
  echo "[chunk $chunk_idx] $i..$end of $total — ${#chunk[@]} images"
  python3 "$ROOT_DIR/scripts/generate_missing_images.py" \
    --api-key "$GEMINI_API_KEY" \
    --only "$joined" \
    || echo "[chunk $chunk_idx] non-zero exit (continuing)"
  i=$((end + 1))
done

echo
echo "[run_shuffle_image_gen] all chunks dispatched. Surviving images:"
ls "$OUT_DIR"/*.png | wc -l
