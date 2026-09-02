"""
Merge stockpile_progress.json entries into all_exercises_metadata.json.

Many scripts do a runtime stockpile-merge (see load_all_metadata() in
generate_missing_images.py); the ones that forget silently miss ~30%+ of
exercises. Consolidating once into the canonical metadata file removes
that footgun.

Stockpile field map:
  startPoseDescription -> pose_description
  endPoseDescription   -> end_pose_description
  imageFileName        -> normalized_filename (fallback to dict key)
  targetArea           -> target_area
  bodyPosition         -> body_position
  source field         -> "stockpile" (vs existing entries which keep theirs)
"""
import json
import shutil
from pathlib import Path

OUTPUT = Path(__file__).resolve().parent / "output"
META_PATH = OUTPUT / "all_exercises_metadata.json"
STOCK_PATH = OUTPUT / "stockpile_progress.json"
BACKUP_PATH = OUTPUT / "all_exercises_metadata.before_consolidate.json"


def main() -> int:
    meta = json.loads(META_PATH.read_text())
    stock = json.loads(STOCK_PATH.read_text())

    in_meta = {e["normalized_filename"] for e in meta["exercises"]}
    print(f"Existing metadata entries: {len(in_meta)}")

    added = 0
    skipped = 0
    for k, e in stock.get("all_exercises", {}).items():
        img_name = e.get("imageFileName") or k
        if img_name in in_meta:
            continue
        pose = (e.get("startPoseDescription") or "").strip()
        if not pose:
            skipped += 1
            print(f"  SKIP {img_name}: no startPoseDescription")
            continue
        meta["exercises"].append({
            "normalized_filename": img_name,
            "name": e.get("name", img_name.replace("-", " ").title()),
            "category": e.get("category", ""),
            "target_area": e.get("targetArea", ""),
            "body_position": e.get("bodyPosition", ""),
            "pose_description": pose,
            "end_pose_description": (e.get("endPoseDescription") or "").strip(),
            "source": "stockpile",
        })
        in_meta.add(img_name)
        added += 1

    print(f"Added: {added}  Skipped: {skipped}")
    print(f"Final count: {len(meta['exercises'])}")

    # Backup before write
    if META_PATH.exists():
        shutil.copy(META_PATH, BACKUP_PATH)
        print(f"Backup: {BACKUP_PATH}")

    META_PATH.write_text(json.dumps(meta, indent=2))
    print(f"Wrote: {META_PATH}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
